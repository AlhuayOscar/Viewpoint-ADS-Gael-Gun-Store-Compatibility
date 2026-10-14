# PVADS profile migration checkpoint

Checkpoint date: 2026-10-14

## User-confirmed rifle preparation update (2026-10-14)

The user confirmed that the historical bolt-action rifles listed in the preceding review are prepared, as are the other bolt-action rifles. They also confirmed these sniper rifles are prepared: `Base.M200` (Cheytac), `Base.CS5`, `Base.GOL`, `Base.JNG90`, `Base.L115A`, `Base.L96`, `Base.M40`, `Base.M98B`, `Base.Scout_elite`, and `Base.SV98`.

The remaining two `Rifles.txt` entries, `Base.DeLisle` and `Base.HuntingRifle`, now each have all 42 AK-74 optic profiles copied under marker `ak74BoltRifleOpticCopyVersion`. All 42 optics were confirmed in both their `ModelWeaponPart` lists and the corresponding `MountOn` lists. 20 pre-existing profiles were updated and 64 added. Backup: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.before-DeLisle-HuntingRifle-optic-copy-20261014.txt`; checkpoint: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-bolt-rifles-20261014.txt`.

Model observations for manual visual review: De Lisle's long barrel is its integral suppressor; it is not an optic. Hunting Rifle uses the R783 model, whose `Mount` attachment offset is `0.0000 0.0000 0.0000`, unlike a normally placed optic mount, so check its scope placement in game.

`Base.AA12` sight-Z correction: the no-optic profile uses `adjZ=0.01700`; its 42 optic profiles match the corresponding AK-74 optics on all shared sight/lens/ADS fields. Backup: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.before-AA12-AK74-optic-restore-20261014.txt`; checkpoint: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-AA12-AK74-restore-20261014.txt`. The AA-12, De Lisle, and Hunting Rifle profile entries were exported into both packaged `PVADS_GaelSavedProfiles.lua` versions for GitHub distribution.

## User profile data

The active profile file is `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.txt`.
Snapshot after the latest completed group:
`%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-shotguns-20261014.txt`

Completed batch markers in the active file:

- `ak74SMGOpticCopyVersion`: 1,674 profiles (44 eligible SMGs; X86 excluded because it has no compatible `Scope` mount entry).
- `ak74LMGOpticCopyVersion`: 966 profiles (23 LMGs).
- `ak74SemiAutoOpticCopyVersion`: 2,142 profiles (51 semiautomatic rifles; G3A3, G27, and Mauser Selbstlader M1916 were added by explicit approval).
- `ak74ShotgunOpticCopyVersion`: 1,764 profiles (42 compatible shotguns × 42 AK-74 optic profiles).
- Prior automatic-rifle batches: 630, 714, 588, and 546 profiles, respectively.

The completed SMG, LMG, and semiautomatic batches were checked for copied-field mismatches; none were found. The approved three-rifle extension copied 42 AK-74 optic profiles to each weapon: 96 combinations were added and 30 existing combinations had the shared optic fields updated. Fields outside the shared optic list were retained. Existing per-profile data is retained and migration markers prevent these batches from being reapplied.

Before-copy backups are kept beside the active profile file:

- `PVADS_UserProfiles.before-SMG-optic-copy-20261014.txt`
- `PVADS_UserProfiles.before-LMG-optic-copy-20261014.txt`
- `PVADS_UserProfiles.before-semi-auto-optic-copy-20261014.txt`
- `PVADS_UserProfiles.before-approved-semi-auto-expansion-20261014.txt`
- `PVADS_UserProfiles.before-shotgun-optic-copy-20261014.txt`

## Continue future batches

When the user names another weapon group:

1. Inventory weapons and compatible optic IDs from the installed game scripts; exclude known model/problem cases and explain exclusions.
2. Use the approved reference profiles for that group (AK-74 optic setup for the recent batches).
3. Back up `PVADS_UserProfiles.txt` before writing.
4. Add/update only missing compatible weapon/optic combinations, with a distinct migration marker so reruns are idempotent.
5. Verify expected profile counts, copied fields, and marker counts; save a fresh checkpoint snapshot.
6. Keep profile-data migrations separate from the runtime Gael K attachment-picker UI.

Semiautomatic expansion snapshot (before shotguns):
`%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-approved-semi-auto-expansion-20261014.txt`

Latest shotgun batch snapshot:
`%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-shotguns-20261014.txt`
Latest bolt-rifle snapshot:
`%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-bolt-rifles-20261014.txt`
Details and per-weapon compatibility list: `docs/PVADS_shotgun_optic_batch_20261014.md`.

## Known profile-copy exclusions and pending classifications

Explicit exclusions from the AK-74 attached-optic copy batches:

- `Base.X86`: excluded from the SMG batch because GaelGunStore has no compatible scope-mount entry.
- `Base.SIG_553`: excluded from the automatic-rifle batch pending a model/ADS rework.
- `Base.AUG_A1` and `Base.G36`: their optics are integrated; they need weapon-specific profile work instead of the AK-74 attached-optic copy. `Base.AUG_A2` and `Base.G36C` were handled separately/as compatible variants.
- `Base.DB_Condor`, `Base.DB_Condor_sawn`, `Base.DoubleBarrelShotgun`, and `Base.DoubleBarrelShotgunSawnoff`: none of the 42 AK-74 optics is listed as a compatible `Scope` part or model weapon part for these double-barrel models.

`Base.G3A3`, `Base.G27`, and `Base.MauserSelbstladerM1916` were previously excluded from the semi-auto copy for visual-model concerns. The user approved their profile copy on 2026-10-14; all three now have 42 optic combinations. Their visual-model review remains open. `Base.SR338` and `Base.Springfield_sniper` were covered in the sniper work, and `Base.VSSK` in the automatic group, so they were overlaps rather than omitted weapons. `Base.pistol_shotgun` is handled in the pistol batch and already has profiles for its 11 compatible optics. Shotgun compatibility was checked against both each optic's `MountOn` list in GaelGunStore's `Scope.txt` and each firearm's `ModelWeaponPart` list. All 42 supported shotguns have all 42 reference optics; no partial-support cases were found. The shotgun classification is now complete for these scripts; integrated-optic weapons still need their own calibration approach.

## Current runtime repair note

`PVADS_GaelVisualChoices.lua` no longer runs completed one-time batch copies during startup. The prior source is preserved as the inactive reference `docs/archive/PVADS_GaelVisualChoices.pre-checkpoint.lua.txt`; existing completed profile data remains in the user profile file. Future classification batches should be prepared only when requested. `PVADS_GaelAttachmentPanel` is intentionally not required from `PVADS_GaelSavedProfiles.lua`; this disables its debug hover marker because it caused errors while interacting with Gael's native picker. The saved-profile and visual-choice Lua files are synchronized across repository 42/42.20 and installed/workshop 42/42.20 copies (matching SHA-256 hashes).

The game must be restarted before validating the runtime fix. After restart, confirm the X86 `Save` path and check the new `DebugLog` for the old `ArrayIndexOutOfBoundsException` before proceeding.
