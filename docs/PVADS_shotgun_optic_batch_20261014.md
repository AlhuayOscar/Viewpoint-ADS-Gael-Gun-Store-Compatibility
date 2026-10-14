# Shotgun optic profile batch (2026-10-14)

Source file: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.txt`
Reference: the 42 optic profiles on `Base.AK74`
Backup: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.before-shotgun-optic-copy-20261014.txt`
Checkpoint: `%USERPROFILE%\Zomboid\Lua\PVADS_UserProfiles.checkpoint-after-shotguns-20261014.txt`

## Compatibility method

A shotgun was included only when all 42 reference optics were listed in both the optic's `MountOn` field in GaelGunStore `GunPartItem/Scope.txt` and the firearm's `ModelWeaponPart` scope list in its shotgun firearm script. All 42 included guns passed both checks for all 42 optics; no partial cases were found.

Copied the shared sight/lens/ADS fields: `adjX`, `adjY`, `adjZ`, `lensScale`, PiP lens position/size/zoom/reticle/depth, `mode`, `reticle`, `fovMul`, `opticHeight`, and `adsTime`. Other fields were retained. The batch marker is `ak74ShotgunOpticCopyVersion=1`.

## Included (42)

- **Shotguns:** `Base.KS23`, `Base.KSG`, `Base.M1887`, `Base.M1887_Short`, `Base.M620`, `Base.Mossber500`, `Base.Mossber590`, `Base.Remington870`, `Base.Remington870_Short`, `Base.RMB93`, `Base.Shorty`, `Base.Shotgun`, `Base.ShotgunSawnoff`, `Base.SWMP_12`, `Base.Winchester1897`.
- **Semi-automatic:** `Base.Becker_Shotgun`, `Base.Becker_Shotgun_Short`, `Base.BenelliM3`, `Base.BenelliM4`, `Base.Beretta_A400`, `Base.Beretta_A400_Short`, `Base.Browning_Auto`, `Base.Browning_Auto_Short`, `Base.ENARM_Pentagun`, `Base.Jackhammer`, `Base.MTS_255`, `Base.MTS_255_Short`, `Base.QBS09`, `Base.QBS09_Short`, `Base.Remington1100`, `Base.Remington1100_Short`, `Base.Sjorgen`, `Base.Sjorgen_Short`, `Base.SPAS12`, `Base.Striker`.
- **Automatic:** `Base.AA12`, `Base.DVB15`, `Base.QBA`, `Base.Saiga12`, `Base.SPAS15`, `Base.USAS12`, `Base.VR80`.

## Excluded (4)

These double-barrel weapons have neither compatible `Scope` mount entries for the reference optics nor scope model-part entries in the firearm definitions:

- `Base.DB_Condor`
- `Base.DB_Condor_sawn`
- `Base.DoubleBarrelShotgun`
- `Base.DoubleBarrelShotgunSawnoff`

The special `Base.pistol_shotgun` is outside these four shotgun script groups. It is already handled with pistols and has profiles for its 11 compatible reference optics.

## Result

- 1,764 compatible shotgun/optic combinations updated.
- 420 combinations already existed and received the shared AK-74 optic values.
- 1,344 compatible combinations were added.
- Verification: all included profiles match the AK-74 values in the copied fields; mismatch count 0.
