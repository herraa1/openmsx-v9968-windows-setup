param([Parameter(Mandatory=$true)][string]$Runtime,[switch]$CStream)
$ErrorActionPreference='Stop'
$buildDir=if($CStream){'build-c'}else{'build'}
$map=Get-Content "$PSScriptRoot/$buildDir/V9968-TECH-DEMO.map" -Raw
function Symbol($name){
 $m=[regex]::Match($map,'(?m)^'+[regex]::Escape($name)+'\s*=\s*\$([0-9A-Fa-f]+)')
 if(!$m.Success){throw "Missing symbol $name"};[Convert]::ToInt32($m.Groups[1].Value,16)
}
$layout=Get-Content "$PSScriptRoot/assets/bank-layout.json" -Raw|ConvertFrom-Json
$tcl=@'
set save_settings_on_exit false
set throttle false
set sound_driver null
set report [open telemetry.txt w]
set sample 0
after time 8 {keymatrixdown 0 64}
after time 9 {keymatrixup 0 64}
debug set_bp @GLOW@ {} {
 # Hold the opening's scene clock while exercising all mesh records.
 # Emulator scheduling continues normally; this is a pixel fixture, not FPS.
 if {$sample==0} {set first_tick [peek16 @TICKS@]}
 debug write memory @TICKS@ [expr {$first_tick&255}]
 debug write memory [expr {@TICKS@+1}] [expr {$first_tick>>8}]
 set page [expr {$sample%2}]
 debug write memory @BACK@ $page
 debug write_block VRAM [expr {$page*32768}] [string repeat "\x00" 24576]
 debug write memory 0x7000 [expr {@BANK@+$sample/4}]
 reg HL [expr {0x8000+($sample%4)*4096}]
 set return_address [peek16 [reg SP]]
 debug set_bp -once $return_address {} {
  debug write_block memory 0xcf80 "\xc3\x80\xcf"
  set saved_iff [reg IFF];reg IFF 0;reg PC 0xcf80
  after time 0.02 {
   set name [format "glow-%03d.bin" $sample]
   set f [open $name wb];puts -nonewline $f [debug read_block VRAM [expr {$page*32768}] 24576];close $f
   puts $report "GLOW $sample $page"
   incr sample
   if {$sample==128} {puts $report "GLOW=PASS CAPTURE=PASS";close $report;exit 0}
   reg PC $return_address;reg IFF $saved_iff
  }
  debug cont
 }
 debug cont
}
after time 180 {puts $report "GLOW=TIMEOUT";close $report;exit 1}
'@
$tcl=$tcl.Replace('@GLOW@',[string](Symbol '_stream_spans_glow')).Replace('@BACK@',[string](Symbol '_back_page')).Replace('@BANK@',[string]$layout.MESH.bank).Replace('@TICKS@',[string](Symbol '_ticks'))
$temp=Join-Path $PSScriptRoot 'test-output'
New-Item -ItemType Directory -Force -Path $temp|Out-Null
$script=Join-Path $temp ('glow-'+[guid]::NewGuid().ToString('N')+'.tcl')
[IO.File]::WriteAllText($script,$tcl)
$capture=& "$PSScriptRoot/test.ps1" -Runtime $Runtime -CaptureScript $script -CStream:$CStream -PassThru
if(!$capture.WorkDirectory){throw 'Missing current capture directory'}
$work=Get-Item -LiteralPath $capture.WorkDirectory
if(!(Test-Path -LiteralPath (Join-Path $work.FullName 'glow-127.bin'))){throw 'Incomplete current capture'}
if(!$work -or (Get-Content "$($work.FullName)/telemetry.txt" -Raw) -notmatch 'GLOW=PASS'){throw 'Incomplete glow capture'}
$rom=[IO.File]::ReadAllBytes("$PSScriptRoot/$buildDir/V9968-TECH-DEMO.rom")
for($frame=0;$frame -lt 128;$frame++){
 $offset=[int]$layout.MESH.bank*16384+$frame*4096
 $count=[int]$rom[$offset]+256*[int]$rom[$offset+1]
 $expected=New-Object byte[] 24576
 for($i=0;$i -lt $count;$i++){
  $p=$offset+2+$i*11
  $x=[int]$rom[$p];$y=[int]$rom[$p+2];$w=[int]$rom[$p+4]+256*[int]$rom[$p+5];$h=[int]$rom[$p+6]+256*[int]$rom[$p+7]
  for($yy=$y;$yy -lt $y+$h;$yy++){for($xx=$x;$xx -lt $x+$w;$xx++){$index=$yy*128+[int][Math]::Floor($xx/2);$expected[$index]=$expected[$index] -bor $(if($xx%2){15}else{240})}}
 }
 $actual=[IO.File]::ReadAllBytes((Join-Path $work.FullName ('glow-{0:D3}.bin' -f $frame)))
 if([Convert]::ToBase64String($actual) -ne [Convert]::ToBase64String($expected)){throw "Glow mismatch: frame $frame"}
}
Write-Host "PASS: all 128 glow meshes, alternating destination pages, exact color-15 raster. $($work.FullName)"
