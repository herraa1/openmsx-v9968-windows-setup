param([Parameter(Mandatory=$true)][string]$Runtime,[switch]$CStream)
$buildDir=if($CStream){'build-c'}else{'build'}
$ErrorActionPreference='Stop'
$map=Get-Content "$PSScriptRoot/$buildDir/V9968-TECH-DEMO.map" -Raw
function Symbol($name){
 $m=[regex]::Match($map,'(?m)^'+[regex]::Escape($name)+'\s*=\s*\$([0-9A-Fa-f]+)')
 if(!$m.Success){throw "Missing symbol $name"};[Convert]::ToInt32($m.Groups[1].Value,16)
}
$tcl=@'
set save_settings_on_exit false
set throttle false
set sound_driver null
set report [open telemetry.txt w]
set sample 0
set draws 0
set restores 0
set previous -1
set reentry 0
debug set_bp @STREAM@ {[debug read memory @DEST@]==2} {incr draws;debug cont}
debug set_bp @RESTORE@ {} {incr restores;debug cont}
# Select Scene 3 manually so all 128 poses fit before an automatic transition.
after time 8 {keymatrixdown 0 8}
after time 9 {keymatrixup 0 8}
debug set_bp @PREP@ {} {
 # Repeat frame zero, then all other frames; set bit 7 to exercise masking.
 set input [expr {128+($sample==0?0:($sample-1)%128)}]
 set pose [expr {$input&127}]
 if {$reentry} {set input 128;set pose 0}
 debug write memory [expr {[reg SP]+2}] $input
 set expected [expr {$previous!=$pose}]
 set previous $pose
 set before_draws $draws;set before_restores $restores
 set return_address [peek16 [reg SP]]
 debug set_bp -once $return_address {} {
  debug write memory 0xcf80 0xc3
  debug write memory 0xcf81 0x80
  debug write memory 0xcf82 0xcf
  # Prevent resuming in the middle of an ISR, which would corrupt its stack.
  set park_iff [reg IFF]
  reg IFF 0
  reg PC 0xcf80
  after time 0.02 {
   if {$draws-$before_draws!=$expected || $restores-$before_restores!=$expected} {
    puts $report "CACHE=FAIL $sample";close $report;exit 1
   }
   if {[debug read memory 0xcf06]!=0 || [debug read memory 0xcf07]!=1} {
    puts $report "FAULT=FAIL";close $report;exit 1
   }
   set name [format "work-%03d.bin" $sample]
   set f [open $name wb];puts -nonewline $f [debug read_block VRAM 65536 24576];close $f
   puts $report "WORK $name $pose"
   incr sample
   if {$sample==129} {
    # Borrow page 2 for Scene 6, then re-enter with the same requested pose.
    set reentry 1;set previous -1
    keymatrixdown 0 64
    after time 1 {keymatrixup 0 64}
    after time 5 {keymatrixdown 0 8}
    after time 6 {keymatrixup 0 8}
   } elseif {$sample==130} {
    puts $report "CACHE=PASS REENTRY=PASS CAPTURE=PASS";close $report;exit 0
   }
   reg PC $return_address
   reg IFF $park_iff
  }
  debug cont
 }
 debug cont
}
after time 180 {puts $report "TIMEOUT sample=$sample PC=[reg PC] SP=[reg SP] fault=[debug read memory 0xcf06] scene=[debug read memory 0xcf04] ticks=[peek16 0xcf02]";binary scan [debug read_block {VDP regs} 0 64] cu* vals;puts $report "REGS=$vals";close $report;exit 1}
'@
foreach($pair in @(@('PREP','_water_prepare'),@('STREAM','_stream_mesh_page'),@('DEST','_mesh_destination_page'),@('RESTORE','_water_restore'))){$tcl=$tcl.Replace('@'+$pair[0]+'@',[string](Symbol $pair[1]))}
$temp=Join-Path $PSScriptRoot 'test-output'
New-Item -ItemType Directory -Force -Path $temp|Out-Null
$script=Join-Path $temp ('work-'+[guid]::NewGuid().ToString('N')+'.tcl')
[IO.File]::WriteAllText($script,$tcl)
$capture=& "$PSScriptRoot/test.ps1" -Runtime $Runtime -CaptureScript $script -CStream:$CStream -PassThru
if(!$capture.WorkDirectory){throw 'Missing current capture directory'}
$work=Get-Item -LiteralPath $capture.WorkDirectory
if(!(Test-Path -LiteralPath (Join-Path $work.FullName 'work-129.bin'))){throw 'Incomplete current capture'}
if(!$work){throw 'No complete work-surface capture'}
$refs=Get-Content "$PSScriptRoot/assets/mesh-reference.json" -Raw|ConvertFrom-Json
$checked=0
foreach($line in Get-Content "$($work.FullName)/telemetry.txt"){
 if($line -match '^WORK (\S+) (\d+)$'){
  $hash=(Get-FileHash "$($work.FullName)/$($Matches[1])").Hash
  if($hash -ne $refs[[int]$Matches[2]].page2_sha256){throw "Page 2 mismatch: $line"}
  $checked++
 }
}
if($checked -ne 130){throw "Incomplete pose coverage: $checked"}
Write-Host "PASS: 128 poses, 128+ input masking, cache reuse, Scene 6 re-entry; 130 complete VRAM images. $($work.FullName)"
