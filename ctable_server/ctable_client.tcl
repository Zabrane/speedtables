#
# Network CTables
#
# Client-Side
#
#
# $Id$
#

package require ctable_net
package require Tclx

#
# remote_ctable - declare a ctable as going to a remote host
#
# remote_ctable $serverHost myTable
#
#  myTable is now a command that works like a ctable except it's all
#  client server behind your back.
#
proc remote_ctable {cttpUrl localTableName} {
    variable ctableUrls
    variable ctableLocalTableUrls

#puts stderr "define remote ctable: $localTableName -> $cttpUrl"

    set ctableUrls($localTableName) $cttpUrl
    set ctableLocalTableUrls($cttpUrl) $localTableName

    proc $localTableName {args} "
	set level \[info level]; incr level -1
	remote_ctable_invoke $localTableName \$level \$args
    "
}

#
# remote_ctable_destroy - destroy a remote ctable connection
#
proc remote_ctable_destroy {cttpUrl} {
    variable ctableUrls
    variable ctableLocalTableUrls

    if [info exists ctableLocalTableUrls($cttpUrl)] {
	rename $ctableLocalTableUrls($cttpUrl) ""
	if [info exists ctableUrls($ctableLocalTableUrls($cttpUrl))] {
	    unset ctableUrls($ctableLocalTableUrls($cttpUrl))
	}
	unset ctableLocalTableUrls($cttpUrl)
    }
    remote_ctable_cache_disconnect $cttpUrl
}

#
# remote_ctable_cache_disconnect - disconnect from a remote ctable server
#
proc remote_ctable_cache_disconnect {cttpUrl {sock ""}} {
    variable ctableSockets

    if {[info exists ctableSockets($cttpUrl)]} {
	close $ctableSockets($cttpUrl)
	if {"$sock" == "$ctableSockets($cttpUrl)"} {
	    set sock ""
	}
	unset ctableSockets($cttpUrl)
    }
    if {"$sock" != ""} {
	close $sock
    }
}

#
# remote_ctable_connect - connect to a remote ctable server
#
proc remote_ctable_cache_connect {cttpUrl} {
    variable ctableSockets

    if {[info exists ctableSockets($cttpUrl)]} {
       return $ctableSockets($cttpUrl)
    }

    lassign [::ctable_net::split_ctable_url $cttpUrl] host port dir remoteTable stuff

    set sock [socket $host $port]
    set ctableSockets($cttpUrl) $sock

    if {[gets $sock line] < 0} {
	error "failed to get hello from ctable server"
    }

    if {[lindex $line 0] != "ctable_server"} {
	error "ctable server hello line format error"
    }

    if {[lindex $line 1] != "1.0"} {
	error "ctable server version [lindex $line 1] mismatch"
    }

    if {[lindex $line 2] != "ready"} {
	error "unable to handle ctable server state of unreadiness"
    }

    return $sock
}

#
# remote_ctable_send - send a command to a remote ctable server
#
proc remote_ctable_send {cttpUrl command {actionData ""} {callerLevel ""} {redirect 1}} {
    variable ctableSockets
    variable ctableLocalTableUrls

#puts "actionData '$actionData'"

    set sock [remote_ctable_cache_connect $cttpUrl]

    set i 0
    while {[catch {puts $sock [list $cttpUrl $command]; flush $sock} result] == 1} {
	incr i
	if {$i > 5} {
	    error "unable to contact remote ctable at $cttpUrl"
	}
        remote_ctable_cache_disconnect $cttpUrl $sock

	set sock [remote_ctable_cache_connect $cttpUrl]
    }

    while 1 {
	set line [gets $sock]

	switch [lindex $line 0] {
	    "e" {
		error [lindex $line 1] [lindex $line 2] [lindex $line 3]
	    }

	    "k" {
		return [lindex $line 1]
	    }

	    "r" {
		if !$redirect {
		    error "Redirected to [lindex $line 1]"
		}
#puts "redirect '$line'"
#parray ctableLocalTableUrls
		remote_ctable_cache_disconnect $cttpUrl $sock
		set newCttpUrl [lindex $line 1]
		if {[info exists ctableLocalTableUrls($cttpUrl)]} {
		    set localTable $ctableLocalTableUrls($cttpUrl)
		    unset ctableLocalTableUrls($cttpUrl)
		    remote_ctable $newCttpUrl $localTable
		}
		return [remote_ctable_send $newCttpUrl $command $actionData $callerLevel]
	    }

	    "m" {
		array set actions $actionData
		set firstLine 1

		while {[gets $sock line] >= 0} {
		    if {$line == "\\."} {
			break
		    }
#puts "processing line '$line'"

		    if {[info exists actions(-write_tabsep)]} {
			puts $actions(-write_tabsep) $line
		    } elseif {[info exists actions(-code)]} {
			if {$firstLine} {
			    set firstLine 0
			    set fields $line
			    continue
			}

#puts "fields '$fields' value '$line'"
			set result ""
			foreach var $fields value [split $line "\t"] {
#puts "var '$var' value '$value"
			    if {$var == "_key"} {
				if {[info exists actions(keyVar)]} {
#puts "set $actions(keyVar) $value"
				    uplevel #$callerLevel set $actions(keyVar) $value
				}
				continue
			    }

			    if {[info exists actions(-get)]} {
				lappend result $value
			    } else {
				lappend result $var $value
			    }
			}

			uplevel #$callerLevel "
			    [list set $actions(bodyVar) $result]
			    $actions(-code)
			"
		    } else {
			error "no action, need -write_tabsep or -code: $actionData"
		    }
		}
	    }

	    default {
		error "unknown command response $line"
	    }
	}
    }
}

#
# remote_ctable_create - create on the specified host an instance of the ctable creator creatorName named tableName
#
proc remote_ctable_create {cttpUrl creatorName remoteTableName} {
    return [remote_ctable_send $cttpUrl [list create $creatorName $remoteTableName]]
}

#
# remote_ctable_invoke - object handler for procs generated by remote_ctable
#
proc remote_ctable_invoke {localTableName level command} {
    variable ctableSockets
    variable ctableUrls
    variable ctableLocalTableUrls

    set cttpUrl $ctableUrls($localTableName)

    set cmd [lindex $command 0]
    set body [lrange $command 1 end]

#puts "cmd '$command', pairs '$body'"

    # Have to handle "destroy" specially - don't pass to far end, just
    # close the socket and destroy myself
    if {"$cmd" == "destroy"} {
	return [remote_ctable_destroy $cttpUrl]
    }

    # If the comand is "redirect" or "shutdown", don't follow redirects
    set redirect [expr {"$cmd" == "redirect" || "$cmd" == "shutdown"}]

    # if it's search, take out args that will freak out the remote side
    if {$cmd == "search" || $cmd == "search+"} {
	array set pairs $body
	if {[info exists pairs(-write_tabsep)]} {
	    set actions(-write_tabsep) $pairs(-write_tabsep)
	    unset pairs(-write_tabsep)
	}

	if {[info exists pairs(-code)]} {
	    set actions(-code) $pairs(-code)
	    unset pairs(-code)

	    foreach var {-key -array_get -array_get_with_nulls -get} {
		if {[info exists pairs($var)]} {
		    set actions($var) $pairs($var)
		    unset pairs($var)

		    if {$var == "-key"} {
			set actions(keyVar) $actions($var)
		    } else {
			set actions(bodyVar) $actions($var)
		    }
		}
	    }

	    set pairs(-include_field_names) 1
	}
	set body [array get pairs]
#puts "new body is '$body'"
#puts "new actions is [array get actions]"
    }

    return [remote_ctable_send $cttpUrl [linsert $body 0 $cmd] [array get actions] $level $redirect]
}

package provide ctable_client 1.0

