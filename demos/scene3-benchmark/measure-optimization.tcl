# Emulated-time samples, identical script for every optimization checkpoint.
set save_settings_on_exit false
set throttle false
set maxframeskip 0
set sound_driver null
set report [open measurements.txt w]
set failed 0
proc later {t body} {after time $t [list guarded $body]}
proc guarded {body} {
 global report
 if {[catch {uplevel #0 $body} message]} {puts $report "ERROR=$message";close $report;exit 1}
}
proc check_state {opt_mode pose} {
 if {[debug read memory 0xcf06]!=0 || [debug read memory 0xcf07]!=1} {error "fault/mapper"}
 if {[debug read memory 0xcf09]!=$opt_mode || [debug read memory 0xcf0e]!=$pose} {error "opt_mode/pose"}
}
proc begin {opt_mode pose repeat} {
 global first_frame first_tick
 check_state $opt_mode $pose
 set first_frame [peek16 0xcf00];set first_tick [peek16 0xcf02]
 later 15 [list finish $opt_mode $pose $repeat]
}
proc finish {opt_mode pose repeat} {
 global report first_frame first_tick
 check_state $opt_mode $pose
 set frames [expr {([peek16 0xcf00]-$first_frame)&65535}]
 set ticks [expr {([peek16 0xcf02]-$first_tick)&65535}]
 if {$frames<=0 || $ticks<=0} {error "no progress"}
 puts $report "SAMPLE $opt_mode $pose $repeat $frames $ticks [expr {$frames*60.0/$ticks}]"
 flush $report
}
proc press_f {} {keymatrixdown 3 8;later 1 {keymatrixup 3 8}}
later 10 {
 puts $report "VDP=[debug read memory 0xcf0a] CPU=[debug read memory 0xcf0b]"
 # Animation first. P then freezes both pose and wave at zero, retaining rendering.
 set t 0
 for {set pose 0} {$pose<2} {incr pose} {
  for {set opt_mode 0} {$opt_mode<3} {incr opt_mode} {
   for {set rep 0} {$rep<3} {incr rep} {
    later $t [list begin $opt_mode $pose $rep]
    incr t 16
   }
   later $t {press_f};incr t 3
  }
  if {!$pose} {later $t {keymatrixdown 4 32};incr t;later $t {keymatrixup 4 32};incr t 2}
 }
 later $t {puts $report "TEST=PASS";close $report;exit 0}
}
later 400 {exit 1}
