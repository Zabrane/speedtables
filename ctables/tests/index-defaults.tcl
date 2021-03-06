# $Id$

source test_common.tcl

source index-defaults.ct

source index-test-proc.tcl

package require Indef

# set to 1 to create some spiciness
set spicy_brains 1

set t [indef create #auto]

proc di {t i} {
  puts "begin $t index dump $i"
  $t index dump $i
  puts "end"
}

$t index create color
$t index create flavor
$t index create spiciness

set foods {pizza sugar toast waffles soup nuts}
set colors {red orange yellow white maroon}
set flavors {sweet sour cheesy pepper acid}

puts "Initializing..."

proc re {list} {
  return [lindex $list [expr {int(rand() * [llength $list])}]]
}

for {set i 0} {$i < 100} {incr i} {
  if {int(rand() * 2)} {
    $t set $i id [re $foods]$i color [re $colors]
  } else {
    $t set $i id [re $foods]$i flavor [re $flavors]
  }
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  if {int(rand() * 2)} {
    if {$spicy_brains} {
      $t set $j spiciness [expr {int(rand() * 100) * 0.1}]
    } else {
      $t set $j id [re $foods]$i flavor [re $flavors]
    }
  } else {
    if {[$t exists $j]} {
      $t delete $j
    } else {
      $t set $j id [re $foods]$i flavor [re $flavors]
    }
  }
}

# di $t color
# di $t flavor
# di $t spiciness

puts "Testing..."
test_index $t = color maroon
test_index $t = flavor cheesy
if $spicy_brains {
  test_index $t > spiciness 5
}
puts "Scrambling..."

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  if {[$t exists $j]} {
    $t delete $j
  } else {
    $t set $j id [re $foods]$i flavor [re $flavors]
  }
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t delete $j
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j id [re $foods]$j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

puts "Testing..."
# di $t color
# di $t flavor

test_index $t = color maroon
test_index $t = flavor cheesy
if $spicy_brains {
  test_index $t > spiciness 5
  test_index $t >= spiciness 5
  test_index $t <= spiciness 5
  test_index $t < spiciness 5
}
test_index $t match flavor che*
test_index $t notmatch flavor che*
test_index $t match_case flavor che*
test_index $t notmatch_case flavor che*
test_index $t range spiciness 1 4
test_index $t in flavor {acid cheesy}

puts "DONE"
