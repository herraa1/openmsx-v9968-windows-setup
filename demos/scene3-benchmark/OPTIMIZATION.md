[日本語](OPTIMIZATION.ja.md)

# Exact Scene 3 optimization

Measured 2026-09-14. Included in release 0.7.1.
> **Historical geometry note:** all FPS, bbox and mesh-command counts in this document were measured on 2026-09-14 with the then-default octahedron. The current demo generator accepts arbitrary OBJ input and defaults to `assets/octahedron.obj`; rebuilding the benchmark with that OBJ changes the geometry workload, so do not compare newly rebuilt OBJ results directly to the numbers below.
 The published reference ROM, rom.json and results.json are unchanged. The optimized ROM is `SCENE3-BENCHMARK-OPTIMIZED.rom`; its identity is in [rom-optimized.json](rom-optimized.json) and all measured frame/tick counts are in [results-optimized.json](results-optimized.json).

## Measurement method

Windows 10 x64, PowerShell 5.1, local z88dk/sdcc -SO3, pinned openMSX d884c4b. C-BIOS uses Z80; FS-A1GT uses R800 ROM mode and privately owned BIOS. The same measurement script runs all checkpoints, with three consecutive 15-second emulated-time windows for every FULL/FAST/COMPAT and animated/fixed configuration. FPS is total completed frames × 60 / total elapsed VBlank ticks. It includes HUD, PSG/BGM and VSync. Ranges are sampling variation, not confidence intervals. Physical hardware and audio quality were not tested.

The rebuilt baseline benchmark hash differs from the shipped historical reference, so the before/after values below are fresh measurements. The baseline demo exactly reproduced the published demo hash. Compiler hashes and the source commit are recorded in the JSON. Animation is tick-based: higher FPS samples more poses; it does not speed up the timeline. P fixes pose and water at zero and keeps rendering; after optimization it deliberately benefits from the geometry cache.

## Animated FULL

| Stage | C-BIOS / Z80 fps | FS-A1GT / R800 fps |
|---|---:|---:|
| baseline | 6.433 | 8.244 |
| A | 6.548 | 8.539 |
| AB | 6.716 | 8.867 |
| ABC | 7.957 | 10.504 |
| ABCD | 8.305 | 10.798 |
| ABCDE | 10.070 | 12.312 |

## Fixed-pose FULL

| Stage | C-BIOS / Z80 fps | FS-A1GT / R800 fps |
|---|---:|---:|
| baseline | 6.000 | 7.500 |
| A | 6.000 | 7.500 |
| AB | 9.627 | 12.000 |
| ABC | 12.000 | 15.000 |
| ABCD | 12.000 | 15.000 |
| ABCDE | 13.005 | 20.000 |

## Stages and exactness

- A: remove only the 49,152-pixel water clear. Main transfer plus exact repeated edges overwrites every pixel.
- AB: remove capture; compose background and mesh on page 2. Restore the previous bbox from page 3, then draw the new pose. Exact bbox averages 15,175.680 pixels; HMMM byte alignment expands the actual restore to 15,298.141 pixels. The same pose requires no restore or mesh command.
- ABC: merge only adjacent bands with identical horizontal mapping and contiguous source/destination rows. Mean main runs: 96 → 53.102. Including both one-pixel edge copies: 224.000 → 123.273 commands, excluding the removed clear. All 256 phases reproduce the original rows and edges.
- ABCD: merge identical final nonzero mesh runs vertically. Mean LMMV commands: 257.141 → 223.836; range 107–328. All 128 reconstructed rasters match the original Pillow raster. Scene 6 substitutes color 15 while retaining rectangle height.
- ABCDE: direct assembly CE polling and packet streaming; atomic R17 selection; no active command register writes before CE clears. A 65,535-poll watchdog retains fault marker CF06=1 and stops video/audio. The ISR still runs, restores S2 and never changes the ROM bank or R17. `-CStream` retains the C mesh, glow and water paths for diagnostics.

The default is exact. No approximate FAST_EDGE option, reduced resolution, changed sampling or reduced geometry was introduced. The water source is immutable while copying. Pages 0/1 remain double-buffered, page 2 is borrowed work/history, page 3 retains background and header. Background/texture reloads invalidate the work cache, including Scene 6 transitions.

## Data and compiler details

ROM stays 1 MiB / 64 ASCII16 banks. MESH remains 4,096 bytes/frame: count (u16), count×11-byte LMMV rectangles, padding, then exact x/y/width/height at offset 4092. WATER remains 512 bytes/phase: count (u8), count×5-byte sx/dx/width/sy/height, padding; width 0 means 256. Destination Y accumulates heights. IDENTITY is one six-byte record for the full 192 rows. Banks do not move.

The -SO3 toolchain removed an in-place mask on the water_prepare argument. Assigning the masked result to a separate pose variable prevents reads into the FLOOR banks for inputs 128–255. The test injects all these high-bit inputs. This was found by the full-demo regression; intermediate benchmark inputs were already 0–127.

## Verification

- Generator reconstructs every merged mesh image, rejects overlapping rectangles, validates capacities and exact water expansion.
- verify-water-model.py: all 256 phases / 24,576 original two-row bands against independent math, including horizontal mapping and vertical clamp.
- test-water.ps1: identity equals source, wave matches an independent byte reference with distinctive edge pixels, both CPUs, zero mismatched bytes.
- test-water-work.ps1: 130 full page-2 images per CPU, all 128 poses, high-bit inputs, repeated-pose cache and Scene 6 re-entry. Pixel hashes use the original raster composed over the background, not runtime command output. The test suppresses IRQ only while its CPU parking loop is held for VRAM capture; it restores IFF before resuming and is not used for performance measurement.
- Full demo: all six scenes, headers, W/control tests, mapper and R20/fault checks pass on both CPUs.
- Benchmark: F/P/Esc and all three modes pass on V9968 for both CPUs; standard V9958 COMPAT also passes on both. Conventional VDPs do not receive V9968 mode writes.

## Reproduce

From the repository root, specify your actual z88dk directory and installed runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/build.ps1 -Z88dk "<z88dk>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/launch.ps1 -Mode cbios -Optimized
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/scene3-benchmark/measure-optimization.ps1 -Runtime runtime/cbios
powershell.exe -NoProfile -ExecutionPolicy Bypass -File demos/v9968-tech-demo/test-water-work.ps1 -Runtime runtime/cbios
```

Use fsa1gt for the other runtime. Build the main demo with its build.ps1 first for demo tests. `-Reference` on measure-optimization.ps1 selects the historical shipped ROM, not the freshly rebuilt pre-optimization baseline. Results are written under ignored test-output; local BIOS copies must never be published. The shared asset generators also run and regenerate asset files in place; unchanged inputs produce identical data. `-CStream` writes a separate ROM under `build-c/` and does not change distributed ROMs or existing measurements. VBlank quantization and the substantial fixed-pose cache benefit must be kept explicit in future comparisons, including a later V9990 port. No V9990 work was performed here.

## Presentation and C-reference checks

[English PDF](scene3-optimization.pdf) / [日本語PDF](scene3-optimization.ja.pdf).

Build the C benchmark with `build.ps1 -CStream`, then use `launch.ps1 -Mode cbios -CStream` or `test.ps1 -Runtime <runtime> -CStream`. Add `-Standard` to test a conventional VDP. [C/ASM correspondence and full-demo test commands](../v9968-tech-demo/DEVELOPMENT.md).
