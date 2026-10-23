# Workshop snapshot synchronized to main — 2026-10-22

The authoritative runtime for this checkpoint is the local Workshop upload folder `ViewpointGaelCompat`, Workshop item **3815134719**, copied into `Contents/mods/ViewpointGaelCompat`. Both `42` and `42.20` are included. The in-game mod ID remains `ViewpointGaelCompat`.

This snapshot uses the integrated **PVADSGAEL2.jar** and its ADS, advanced throwable and True Ballistics Lua modules. It supersedes the previous runtime layout that loaded `media/java/client/ViewpointGaelCompat.jar`. Do not enable the separate ADS/Advanced Throwables/True Ballistics mods alongside it; see the packaged mod.info.

Temporary files and root backup folders were excluded. The retired compatibility jar and attachment panel absent from the local snapshot were removed from the packaged runtime. Existing notes, README, source code and tests were preserved. Additional branch-specific notes are retained in docs or docs/archive/branch-notes instead of replacing existing notes.

The root src/ directory and build-native-shot.ps1 are historical compatibility sources, not a claim that the entire integrated PVADSGAEL2.jar can be rebuilt from this checkout. No Java code was rebuilt or installed in the game during this synchronization. The supplied runtime jar was copied byte-for-byte. The checksum manifest records every synchronized runtime file.

This records a GitHub synchronization, not a confirmed Steam Workshop publication. In-game multiplayer, animation and ballistics validation are separate from syntax and package-integrity checks.

## Validation performed

- All synchronized runtime files match the local Workshop snapshot by SHA-256.
- Both Build 42 runtime trees compile with Project Zomboid's Kahlua compiler.
- Eight JSON files and fourteen XML files parse successfully; both jar archives pass CRC integrity checks.
- The nine existing differences between 42 and 42.20 were retained as supplied, rather than silently unifying them.
- The legacy tests/test_compat.lua requires an old PVADSGaelOptics package path. With the current client/shared paths supplied externally, it reaches an assertion failure at line 43. It is retained unchanged and is not reported as passing. This synchronization does not establish full gameplay compatibility.
