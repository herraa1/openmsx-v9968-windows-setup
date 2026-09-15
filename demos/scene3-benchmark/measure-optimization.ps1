param([Parameter(Mandatory=$true)][string]$Runtime,[switch]$Reference)
$ErrorActionPreference='Stop'
$Runtime=[IO.Path]::GetFullPath($Runtime)
$cfg=Get-Content "$Runtime/config.json" -Raw|ConvertFrom-Json
$work=Join-Path $PSScriptRoot ('test-output/measurement-'+[guid]::NewGuid().ToString('N'))
& "$PSScriptRoot/launch.ps1" -Mode $cfg.mode -Runtime $Runtime -Optimized:(!$Reference) -TestScript "$PSScriptRoot/measure-optimization.tcl" -WorkRoot $work
$text=Get-Content "$work/measurements.txt" -Raw
if($text -notmatch 'TEST=PASS' -or $text -match 'ERROR|FAIL'){throw "Measurement failed: $work"}
$samples=@(foreach($line in $text -split '\r?\n'){
 if($line -match '^SAMPLE (\d) (\d) (\d) (\d+) (\d+) ([\d.]+)$'){
  [ordered]@{mode=@('FULL','FAST','COMPAT')[[int]$Matches[1]];fixed_pose=([int]$Matches[2] -eq 1);repeat=[int]$Matches[3];frames=[int]$Matches[4];ticks=[int]$Matches[5];fps=[double]::Parse($Matches[6],[Globalization.CultureInfo]::InvariantCulture)}
 }
})
if($samples.Count -ne 18){throw 'Incomplete measurement matrix'}
$infoName=if($Reference){'rom.json'}else{'rom-optimized.json'}
$info=Get-Content "$PSScriptRoot/$infoName" -Raw|ConvertFrom-Json
$record=[ordered]@{date=(Get-Date -Format 'yyyy-MM-dd');machine=$cfg.mode;rom_sha256=$info.sha256;fork_sha256=$cfg.forkSha256;vblank_hz=60;sample_seconds=15;samples=$samples}
[IO.File]::WriteAllText("$work/measurements.json",($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Host $text
Write-Host "Results: $work/measurements.json (historical results.json is unchanged)"
