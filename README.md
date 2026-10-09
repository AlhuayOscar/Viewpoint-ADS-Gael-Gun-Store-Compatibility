# Viewpoint Gael Compatibility

47 pistols manually verified (45 saved calibrations, 2 verified defaults). 32 of 32 revolvers and 15 of 16 one-handed SMGs have saved manual profiles.

Manual = saved personal calibration; Verified default = checked in game without a personal offset; Profile = included calibration awaiting individual confirmation; Pending = no saved calibration.

## Installation

For Project Zomboid Build 42.21, enable `Viewpoint`, `GaelGunStore_B42`, and `ProjectViewpointADS`, then enable this mod as `ViewpointGaelCompat`. The package is in `Contents/mods/ViewpointGaelCompat`. Restart the game after installing or updating it.

The [current weapon checklist](docs/GaelGunStore_B42_checklist.xlsx) tracks calibration status.

## Experimental: Crouch enables Iron Sights FOV Change

The sandbox option is enabled by default. While crouched, ADS with an unmounted iron sight narrows the view to 70% of that weapon's calibrated ADS FOV. The sandbox multiplier can be adjusted from 0.30 to 1.00 for testing. Standing restores its calibrated FOV. Weapon alignment and saved profiles are unchanged; attached reflex sights and scopes keep their normal behavior. This is a local test feature and needs an in-game visual check.

The additional sandbox option **Experimental: Fixed -0.3 ADS FOV (mouse wheel)** is also enabled by default. With iron sights in ADS, wheel up focuses by subtracting 0.30 from the calibrated `fovMul` (minimum 0.30); wheel down restores normal ADS FOV. The wheel choice overrides crouch focus until ADS ends. Scopes retain their existing wheel zoom.

## Experimental firearm range

The sandbox option **Experimental: increase all firearm ranges by 50%** extends the effective `MaxRange` of aimed firearms without rewriting each weapon or Gael's dynamic ammo stats. It is on by default during testing. **Nerf long distances?** depends on that option and is also on by default: character hits beyond the weapon's original range deal 30% less damage. Both options are experimental and require an in-game check. The damage reduction currently applies to character hits, not vehicles. True Ballistics may still impose its separate projectile-distance cap, and multiplayer needs matching server support before using this option.

## Jam complaint

When the local player tries to fire an aimed firearm that is jammed, a short voice grunt plays using the game's male or female `PainFromRunIntoWall` event at 30% volume. It triggers on a new attack press or when a gun jams while the trigger is held, with a 1.2-second cooldown. Some random variants of this game event are much longer; the voice fades after 0.45 seconds and stops by 0.75 seconds. It does not alter the jam, damage, ammunition, or firing logic. The shortened sound needs an in-game audio check.

## Recoil without a stock

Gael's dynamic recoil is 90% stronger when a shoulder firearm that supports a removable `Stock` fires without one attached. This includes the M4, AK47 and Mini Draco. Pistols, revolvers, one-handed SMGs, intentionally stockless weapons, launchers, and shortened shotguns are excluded. The modifier is applied only while Gael prepares the shot, then immediately restored; attaching a stock removes the penalty for the next shot. This needs an in-game firing check.

## Experimental hold sway for unsupported irons

Enabled by default for `Base.GOL` without an attached optic. While ADS is held, Lua animates a temporary copy of the PVADS profile by changing its calibrated yaw and pitch offsets through `PVADS_setProfile` every 50 ms. This uses the same alignment path as the in-game calibrator and does not require the separate hold-sway Java patch to run. For this visibility test, yaw and pitch move toward independent random targets 15-25 degrees to either side of the saved manual alignment (maximum +/-25 degrees). Each movement uses a random speed equivalent to 0.5-2.0 degrees every 0.25 seconds (2-8 degrees per second). The temporary offsets stop when ADS ends and pause while the calibrator is open. Saved profiles and scoped profiles stay intact. The eligible weapon list is limited to the GOL until checked in game. PVADS' published sight ray should follow the moving alignment; the camera direction stays unchanged. The console logs when Lua sway starts, reaches 15 degrees, and stops, to help verify the active path.

## Slider calibrator

Open the ADS calibrator with its normal key. A companion panel appears on the right with sliders for the same 19 values. Drag for live adjustment, type exact values, switch range x1/x5/x20, and use Save to write the personal profile. The centered weapon selector has searchable names and IDs plus left/right arrows. Selecting an ADS firearm reuses or grants it, equips it through the normal inventory action, and prepares Hold ADS. Hold Ctrl to aim; V remains the normal ADS toggle.

The companion panel also has **Retícula** and **Modo ADS** selectors for the equipped weapon and optic. Auto keeps the optic's default; a selection changes the live ADS profile and Save writes it alongside the numeric calibration in `PVADS_UserProfiles.txt`. Copy includes the visual choices in a ready-to-paste override. OKP-7 offers the supplied arrow-and-bars mark plus ring-and-dot and double-ring marks. Kobra offers a solid or LED-dotted T, dot plus chevron, chevron alone, and the shared dot. Modo ADS selects Viewpoint's rendering mode (iron/reflex/scope), separately from the reticle pattern. The assets are drawn for this mod, not copied optic textures; check their appearance in-game.

`Base.ZaMiniRDS` and `Base.MiniRedDot` default to Viewpoint's 1x clear-lens PiP mode. Their sight models remain around the lens, while the centre shows the unobstructed world and dot without scope magnification. The usual numeric calibration for each weapon carrying either optic is retained.

## Weapon status

| Name | Iron Sights | Red Dot Sight | Other Optics |
|---|---|---|---|
| AA-12 (Base.AA12) | Manual | - | - |
| ACE21 (Base.ACE21) | Manual | - | - |
| ACE23 (Base.ACE23) | Manual | - | - |
| ACE52_CQB (Base.ACE52_CQB) | Manual | - | - |
| ACE53 (Base.ACE53) | Manual | - | - |
| AEK919 9mm (Base.AEK919) | Manual | - | - |
| AK47 (Base.AK47) | Manual | - | - |
| AK74 (Base.AK74) | Manual | - | - |
| AK_minidrako (Base.AK_minidrako) | Manual | - | - |
| AKM (Base.AKM) | Manual | Manual | - |
| Anaconda 44 (Base.Anaconda) | Manual | - | - |
| AR-10 (Base.AR10) | Manual | - | - |
| Armsel Striker Shotgun (Base.Striker) | Manual | - | - |
| AssaultRifle (Base.AssaultRifle) | Manual | - | - |
| AssaultRifle2 (Base.AssaultRifle2) | Manual | - | - |
| AUG_A1 (Base.AUG_A1) | Manual | - | - |
| Automag calibre .357 (Base.Automag357) | Manual | - | - |
| Automag calibre .44 (Base.Automag44) | Manual | - | - |
| Automag calibre .50AE (Base.Automag50AE) | Manual | - | - |
| BAR M1918A (Base.BAR) | Manual | - | - |
| Benelli M3 (Base.BenelliM3) | Manual | - | - |
| Benelli M4 Super 90 (Base.BenelliM4) | Manual | - | - |
| Beretta_PX4 (Base.Beretta_PX4) | Manual | - | - |
| BrowningHP Pistol (Base.BrowningHP) | Manual | - | - |
| CBJ 9mm (Base.CBJ) | Manual | - | - |
| ColtNavy1851 38 (Base.ColtNavy1851) | Manual | - | - |
| ColtNavyExorcist 9mm (Base.ColtNavyExorcist) | Manual | - | - |
| ColtPeacemaker1873 45 (Base.ColtPeacemaker1873) | Manual | - | - |
| Coonan-357 (Base.Coonan357) | Manual | - | - |
| crafted Bow (Base.Bow_crafted) | Manual | - | - |
| Crossbow (Base.Crossbow) | Manual | - | - |
| CZ75 Pistol (Base.CZ75) | Manual | - | - |
| Daniel Defense M16A2 (Base.M16A2) | Manual | - | - |
| Deagle 357 Gold (Base.Deagle357_gold) | Manual | - | - |
| Deagle Carabine 14 (Base.DeagleCar14) | Manual | - | - |
| Deagle50AE (Base.Deagle50AE) | Manual | - | - |
| DoubleBarrelShotgun (Base.DoubleBarrelShotgun) | Manual | - | - |
| DoubleBarrelShotgunSawnoff (Base.DoubleBarrelShotgunSawnoff) | Manual | - | - |
| Enfield1917 (Base.Enfield1917) | Manual | - | - |
| FAMAS (Base.FAMAS) | Manual | - | - |
| FiveSeven Pistol (Base.FiveSeven) | Manual | - | - |
| FN FAL (Base.FAL) | Manual | - | - |
| FN502 22LR (Base.FN502_22LR) | Manual | - | - |
| FNX-45 (Base.FNX45) | Manual | - | - |
| G2 Pistol (Base.G2) | Manual | - | - |
| G36 (Base.G36) | Manual | - | - |
| Glock-17 (Base.G17) | Manual | - | - |
| Glock-18 (Base.G18) | Manual | - | - |
| Glock43 (Base.Glock43) | Manual | - | - |
| Glock_tactical (Base.Glock_tactical) | Manual | - | - |
| GSH-18 (Base.GSH18) | Manual | - | - |
| HK-MK23 (Base.HKMK23) | Manual | - | - |
| Hunting Bow (Base.Bow_hunting) | Manual | - | - |
| Hunting Bow (Base.Bow_compbound) | Manual | - | - |
| Hunting Crossbow (Base.Crossbow_hunting) | Manual | - | - |
| IMI Galil (Base.Galil) | Manual | - | - |
| Jericho-941 (Base.Jericho941) | Manual | - | - |
| Kark98 (Base.Kark98) | Manual | - | - |
| Kimber1911 (Base.Kimber1911) | Manual | - | - |
| L85 (Base.L85) | Manual | - | - |
| M1 Garand (Base.M1) | Manual | - | Manual |
| M1A1 Carbine (Base.M1A1) | Manual | - | - |
| M24 (Base.M24) | Manual | - | - |
| M240B (Base.M240B) | Manual | - | - |
| M249 (Base.M249) | Manual | - | - |
| M4 Assault Rifle (Base.M4) | Manual | Manual | - |
| M60E4 (Base.M60E4) | Manual | - | - |
| M9 Samurai (Base.M9_Samurai) | Manual | - | - |
| M9A3 Pistol (Base.M9A3) | Manual | - | - |
| M9R Pistol (Base.M93R) | Manual | - | - |
| MAC10 .45 (Base.MAC10) | Manual | - | - |
| Micro_UZI 22LR (Base.Micro_UZI) | Manual | - | - |
| Mini_14 Assault Rifle (Base.Mini_14) | Manual | - | - |
| MK18 Assault Rifle (Base.MK18) | Manual | - | - |
| Mosin-Nagant (Base.Mosin) | Manual | - | - |
| MosinNagant1891 (Base.MosinNagant1891) | Manual | - | - |
| MP1911 Marccenary (Base.MP1911) | Manual | - | - |
| MP40 9mm (Base.MP40) | Manual | - | - |
| MP5 (Base.MP5) | Manual | - | - |
| MP5K (Base.MP5K) | Manual | - | - |
| MP5SD 9mm (Base.MP5SD) | Manual | - | - |
| MP7 9mm (Base.MP7) | Manual | - | - |
| MP9 45 (Base.MP9) | Manual | - | - |
| MP_R8 357 (Base.MP_R8) | Manual | - | - |
| MSST 45 (Base.MSST) | Manual | - | - |
| Nagant_M1895 22LR (Base.Nagant_M1895) | Manual | - | - |
| OTS33 (Base.OTS_33) | Manual | - | - |
| P220 (Base.P220) | Manual | - | - |
| P220 Elite (Base.P220_Elite) | Manual | - | - |
| P228 (Base.P228) | Manual | - | - |
| P90 9mm (Base.P90) | Manual | - | - |
| PB6P9 (Base.PB6P9) | Manual | - | - |
| Pistol (Base.Pistol) | Manual | - | - |
| pistol shotgun (Base.pistol_shotgun) | Manual | - | - |
| Pistol2 (Base.Pistol2) | Manual | - | - |
| Pistol3 (Base.Pistol3) | Manual | - | - |
| PP2000 9mm (Base.PP2000) | Manual | - | - |
| PP93 9mm (Base.PP93) | Manual | - | - |
| PPSH41 9mm (Base.PPSH41) | Manual | - | - |
| Python .357 (Base.Python357) | Manual | - | - |
| Remington870 (Base.Remington870) | Manual | - | - |
| Remington870 Short (Base.Remington870_Short) | Manual | - | - |
| Revolver (Base.Revolver) | Manual | - | - |
| Revolver38 (Base.Revolver38) | Manual | - | - |
| Revolver666 22LR (Base.Revolver666) | Manual | - | - |
| Revolver_long (Base.Revolver_long) | Manual | - | - |
| Revolver_short (Base.Revolver_short) | Manual | - | - |
| Rhino20DS 357 (Base.Rhino20DS) | Manual | - | - |
| Rhino60DS (Base.Rhino60DS) | Manual | - | - |
| RPG7 (Base.RPG7) | Manual | - | - |
| RPK (Base.RPK) | Manual | - | - |
| RPK12 (Base.RPK12) | Manual | - | - |
| RPK16 (Base.RPK16) | Manual | - | - |
| RSH12 308 (Base.RSH12) | Manual | - | - |
| Ruger357 45 (Base.Ruger357) | Manual | - | - |
| S&W M&P 12 (Base.SWMP_12) | Manual | - | - |
| Samurai kendo (Base.Samurai_kendo) | Manual | - | - |
| Scar-H (Base.ScarH) | Manual | - | - |
| ScarL (Base.ScarL) | Manual | - | - |
| Schofield1875 44 (Base.Schofield1875) | Manual | - | - |
| ScrapRevolver 9mm (Base.ScrapRevolver) | Manual | - | - |
| Shotgun (Base.Shotgun) | Manual | - | - |
| SIG-553 Assault Rifle (Base.SIG_553) | Manual | - | - |
| SKS (Base.SKS) | Manual | - | - |
| SKS Carbine (Base.SKS_carbine) | Manual | - | - |
| SKS Carbine short (Base.SKS_carbine_short) | Manual | - | - |
| Smith&Wesson M629 (Base.SW629) | Manual | - | - |
| Snub22LR (Base.Snub22LR) | Manual | - | - |
| Springfield XD Pistol (Base.XD) | Manual | - | - |
| Springfield1903 (Base.Springfield1903) | Manual | - | - |
| SR1M Pistol (Base.SR1M) | Manual | - | - |
| SW1905 38 (Base.SW1905) | Manual | - | - |
| SW1917 45 (Base.SW1917) | Manual | - | - |
| SW500 50Magnum (Base.SW500) | Manual | - | - |
| SWM3 38 (Base.SWM3) | Manual | - | - |
| SWM327 357 (Base.SWM327) | Manual | - | - |
| SWM629_Deluxe 44 (Base.SWM629_Deluxe) | Manual | - | - |
| Taurus606 357 (Base.Taurus606) | Manual | - | - |
| Taurus_raging_bull 357 (Base.Taurus_raging_bull) | Manual | - | - |
| Taurus_raging_bull460 50Magnum (Base.Taurus_raging_bull460) | Manual | - | - |
| Taurus_RT85 38 (Base.Taurus_RT85) | Manual | - | - |
| TEC9 9mm (Base.TEC9) | Manual | - | - |
| Thompson 45 (Base.Thompson) | Manual | - | - |
| TMP 9mm (Base.TMP) | Manual | - | - |
| USP-45 (Base.Glock23) | Manual | - | - |
| USP-45 (Base.USP45) | Manual | - | - |
| UZI 9mm (Base.UZI) | Manual | - | - |
| Veresk 9mm (Base.Veresk) | Manual | - | - |
| VictorySW22 (Base.VictorySW22) | Manual | - | - |
| VP70 Pistol (Base.VP70) | Manual | - | - |
| VZ. 58 (Base.VZ58) | Manual | - | - |
| VZ61 22LR (Base.VZ61) | Manual | - | - |
| Walther P99 (Base.P99) | Manual | - | - |
| Walther_P38 (Base.Walther_P38) | Manual | - | - |
| Webley_MK_snub 38 (Base.Webley_MK_snub) | Manual | - | - |
| Webley_Revolver 38 (Base.Webley_Revolver) | Manual | - | - |
| Wildey pistol calibre .44 (Base.Wildey) | Manual | - | - |
| Grizzly50AE (Base.Grizzly50AE) | Verified default | - | - |
| Samurai Albert Wesker (Base.Samurai_aw) | Verified default | - | - |
| P99_Kilin 9mm (Base.P99_Kilin) | Pending | - | - |

## Optics

Magnified Gael optics (2x-8x) use scope mode on supported rifles. 1x sights use reflex mode. Other weapon/optic combinations still need individual visual calibration.

Requires Viewpoint, GaelGunStore_B42 and ProjectViewpointADS. Build 42.21. This package contains one mod: ViewpointGaelCompat.
