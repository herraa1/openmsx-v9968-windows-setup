[日本語](release-notes.ja.md) | English

# Release notes — 0.7.1

[Home](../README.md)

Scene 3 renders faster while preserving the sampled image. The setup and launch steps remain unchanged.

- Animated FULL mode improved from **6.43 to 10.07 FPS on Z80** and **8.24 to 12.31 FPS on R800** in the pinned openMSX fork (three 15-second measurement windows). Animation timing is unchanged.
- Reuse the clean scene image, restore only the previous mesh bounds, merge water transfers and mesh rectangles, and reduce command-stream overhead.
- Include the optimized comparison ROM, updated preview GIFs, and detailed Japanese/English PDF documentation. Historical benchmark ROMs and their measurements remain separate.
- Add a selectable C reference implementation for mesh, glow and water command streams, with pixel comparisons against assembly on both machine configurations.
- Update PROBE to Revision 2 for more detailed LRMM and R20 compatibility diagnostics. FPGA retesting remains pending.
- Strengthen water-data bounds/coverage checks and ensure capture tests inspect only the current run.

Download `openmsx-v9968-windows-setup-0.7.1.zip` from Release Assets, extract the whole ZIP into a new writable folder outside cloud-synced directories, and run the matching setup BAT followed by the matching demo launch BAT. Keep an existing installation in its own folder; setup does not overwrite it.

FPS values are emulator measurements, not FPGA performance guarantees. The C reference path checks rendering behavior, not cycle-equivalent timing. FS-A1GT requires your own BIOS; C-BIOS needs no hardware BIOS. BIOS and emulator executables are not bundled.
