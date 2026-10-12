# Viewpoint Gael Compatibility

## Experimental: NewGaelBallistics (not ready for use)

NewGaelBallistics is under active development and is **not ready for Workshop
release or normal gameplay**. It currently covers an estimated 25–35% of the
features in Viewpoint True Ballistics. Its single-player firing and impact path
has been connected and compiled, but has not yet been validated in gameplay.
Multiplayer remains on Project Zomboid's native ballistic path; shotguns and NPC
projectiles are not implemented in SGTB.

Before it can be considered usable, the main remaining work is in-game validation
of firing and damage behavior, collision calibration (including floors, windows,
vehicles, and body regions), ammo-specific damage and native side effects, and
shotgun pellet simulation. A multiplayer replacement additionally needs server
ownership, request validation, and replication. The full feature comparison and
milestones are in [the NewGaelBallistics development status](docs/STableGaelTrueBallistics-Architecture.md).

47 pistols manually verified (45 saved calibrations, 2 verified defaults). 32 of 32 revolvers and 15 of 16 one-handed SMGs have saved manual profiles.

Manual = saved personal calibration; Verified default = checked in game without a personal offset; Profile = included calibration awaiting individual confirmation; Pending = no saved calibration.

## Installation

The native Build 42 ballistics path now shares the purple calibrator marker's
`pvads.Sight.ray` direction, after Project Viewpoint ADS corrects its visual
weapon presence transform. True Ballistics already reads that same ray through
its ADS bridge, so the patch does not rotate its projectiles again or replace
its zeroing, spread, gravity, collision, or damage calculations. The muzzle
position still comes from the held model and Project Viewpoint's presence
correction; the Gael calibrator can add model-local X/Y/Z offsets after the
lean correction. This change
requires a full game restart and an in-game impact check with the enabled mods;
the purple marker is a direction preview, not a guaranteed final impact.

When Viewpoint True Ballistics is installed, a separate green marker records the
terminal point of the latest local shot. It follows confirmed zombie/person,
vehicle, world-surface, barrel-block and maximum-range/lifetime endpoints; a
penetrating pellet is recorded only when it finally stops. The marker stays at
the actual world position as the camera moves and shows the collision type and
coordinates. This requires True Ballistics because vanilla Build 42 does not
report a simulated projectile endpoint or general wall collision to this patch.

Shot mirror version 11 retains the v8 physical sight/barrel axis through ADS's
weapon and final pose matrices, undoing the sight-reference calibration first.
It includes the visual presence correction. The adjusted ADS reference axis can
point in a different direction from the actual weapon; it is not used as the
barrel measurement. The added yaw/pitch motion rotates around the model's grip
attachment, with a weapon-local rear fallback when no grip is available.
Right/up angular deviation produces left/down shot separation about the fixed
screen center. The endpoint is `screenCenter - scale * angularGain *
(renderedAngularPoint - screenCenter)` on both axes. The purple line starts at that same screen center;
the weapon's moving projected sight position (`ovWin`) is not an input.
The purple-marker slider ranges from x0 to x10. An additional smooth angular gain
is 1x up to 1 degree, 1.5x at 5.5 degrees, and 2x at 10 degrees or more. Combined
yaw/pitch deviation is recovered using ADS FOV, so this response does not depend
on resolution or zoom. This is a tunable game response, not a measured ballistic
calibration. Both factors apply once to the shared shot ray; x0 uses the screen
center. Dynamic yaw/pitch uses the post-alignment
motion path only, retaining each weapon's saved calibration. The extra character
aim offset is disabled because the native shot already uses the shared ray.
Ordinary recoil ranges and recovery times are restored to the documented values
(2–5 degrees base pitch before reductions; 0.3–0.5 seconds for light weapons).
The calibrator title shows `Working v12` only when the loaded Java bridge reports
version 12, plus `Axis OK` or `Axis unavailable`. The physical shot bridge removes
only the stable saved sight alignment when reconstructing the barrel axis, so the
live Gael recoil and hold offsets remain in the direction passed to True Ballistics.
A Lua reload alone cannot make an
old jar look current. Missing/stale physical samples hide the point and leave the
native shot unchanged, rather than displaying the wrong reference-axis fallback.

Gael recoil presentation uses 70% rotational barrel kick and 30% positional
push, each relative to its own baseline (degrees and metres are not summed).
The custom yaw/pitch shot and release/regrip curves bypass fine hold attenuation
and use the 70% weight directly. ADS `gunKick` uses 70% and `gunBack` uses 30%.
The 1–3 / 4–5 / later shot stages and the 26-shot regrip policy remain intact.
Balanced profiles are temporary copies, so saved calibrations are not changed
and repeated profile updates cannot multiply the weights again.

True Ballistics shot motion carry (sandbox option `ShotMotionCarry`, default
0.35) adds a fraction of the physical weapon's yaw/pitch change since the
previous shot to the current shot direction. It compares raw per-shot barrel
angles, wraps yaw across the ±180° boundary, resets after 0.3 seconds or a weapon
change, and caps the measured change at 2° per axis before applying the gain.
Set it to 0 to keep the physical barrel direction without the extra carry. This
is a tunable gameplay response; validate it against debug trajectories in game.

After a burst, the custom Pitch/Yaw recoil now has a chance to settle fully at
the ADS center instead of always reaching it. The chance is 90% for shots 1–3,
80% for shots 4–5, then falls linearly to 60% by shot 26 (remaining at 60% for
longer bursts). When a full return does not occur, the weapon settles at 35% of
that shot's recoil offset and holds that residual while ADS remains active. The return slows as the burst builds, with extra delay from Endurance loss and arm pain. Total recovery is capped at 2 seconds.

Version 9 routes dynamic roll through the grip rotation alongside yaw/pitch,
leaving all three saved angular calibration values stable. Walking adds up to
0.8 degrees of yaw/pitch from its existing motion cycle. Dynamic posture offsets
use 30% of their prior amplitude (the 2–4 cm walking offset becomes 0.6–1.2 cm).
The automatic-fire strength divisor is 2–6 instead of 8–24, making custom
automatic angular recoil four times the v8 amplitude while preserving the
existing shot scale, grip, 70% angular weight and burst thresholds. Single-shot
pistol amplitudes are unchanged. These are tuning choices pending gameplay
validation, not physical measurements. Pure roll tilts the weapon without
changing the barrel axis; it must not invent a yaw/pitch shot deviation.

Version 10 preserves the first five shot impulses, then accumulates angular
error during rapid automatic fire (80% of each new custom angular impulse,
bounded at 12 degrees pitch / 8 degrees yaw before the 70% weight). The existing
long-burst corner path starts from that accumulated error at shot 21; the
26-shot release/regrip behaviour remains. Local arm pain now contributes to the
same fatigue factor as stiffness. Walking's angular cycle grows with exertion
and arm fatigue, up to 3.5 times its healthy amplitude. The purple ray formula,
its screen-center origin and calibration multiplier are unchanged: larger
physical yaw/pitch drives more reflected separation through that shared ray.

The Java sources are included in `src/`, and the compiled runtime classes are
shipped in both versioned compatibility jars. To rebuild on another PC, run
`build-native-shot.ps1` with explicit local paths for `-CompilerJar` (Eclipse
ECJ 3.44 or newer), `-GameRoot`, `-AdsJar`, and `-ViewpointJar`; the script
checks each dependency before compiling. It compiles against that PC's game
and mod APIs, runs the included Java verification programs, and preserves all
other classes in the existing compatibility jar. Use `-StageOnly` to compile
and verify a separate jar while the game is open. Installation refuses to
update a loaded jar until Project Zomboid is closed. The packaged mod runs from
the jars; the `.java` sources are for review and reproducible rebuilding.

The Java bridge also supports the October 10 Project Viewpoint API change that
moved third-person state from `viewpoint.input.ThirdPerson.active` to
`viewpoint.core.View.thirdPerson`. It restores the ADS bridge after this mod's
jar is added to the shared classpath and mirrors the renamed camera state.

For Project Zomboid Build 42.21, enable `Viewpoint`, `GaelGunStore_B42`, and `ProjectViewpointADS`, then enable this mod as `ViewpointGaelCompat`. The package is in `Contents/mods/ViewpointGaelCompat`. Restart the game after installing or updating it.

The [current weapon checklist](docs/GaelGunStore_B42_checklist.xlsx) tracks calibration status.

## Experimental: Crouch enables Iron Sights FOV Change

The sandbox option is enabled by default. While crouched, ADS with an unmounted iron sight narrows the view to 70% of that weapon's calibrated ADS FOV. The sandbox multiplier can be adjusted from 0.30 to 1.00 for testing. Standing restores its calibrated FOV. Weapon alignment and saved profiles are unchanged; attached reflex sights and scopes keep their normal behavior. This is a local test feature and needs an in-game visual check.

The additional sandbox option **Experimental: Fixed -0.3 ADS FOV (mouse wheel)** is also enabled by default. With iron sights in ADS, wheel up focuses by subtracting 0.30 from the calibrated `fovMul` (minimum 0.30); wheel down restores normal ADS FOV. The wheel choice overrides crouch focus until ADS ends. Scopes retain their existing wheel zoom.

## Experimental third-person firearm crosshair

The **DayZ-style third-person firearm crosshair** sandbox option is enabled by default. It shows two short side bars and a center vertical bar while aiming a firearm in Viewpoint third person. The gap opens with walking, running or sprinting, Endurance exertion, and arm pain or stiffness. It is hidden in first person and can be disabled in Sandbox Settings.

The **Ease True Ballistics shots toward aim center** option is also enabled by default. While ADS stays held, it blends the projectile direction from the measured weapon axis toward the camera-center aim ray over 1.1 seconds in 0.1-second steps, with 0.05 seconds removed per Aiming level. In ideal conditions, correction caps at 99%; each Endurance level removes 10 percentage points and each arm-pain level removes 5. The aid runs only while the character is stationary. After the full ramp, shots 1-3 aim exactly at the camera center under ideal conditions, temporarily overriding the physical barrel direction. Shots 4-5 retain 40% of the adjusted correction, then it loses 2 percentage points per shot through shot 25, where it reaches 0%. The weapon animation and muzzle position remain physical; only the shot direction receives the correction. Releasing ADS resets the blend and burst count.

## Experimental firearm range

The sandbox option **Experimental: increase all firearm ranges by 50%** extends the effective `MaxRange` of aimed firearms without rewriting each weapon or Gael's dynamic ammo stats. It is on by default during testing. **Nerf long distances?** depends on that option and is also on by default: character hits beyond the weapon's original range deal 30% less damage. Both options are experimental and require an in-game check. The damage reduction currently applies to character hits, not vehicles. True Ballistics may still impose its separate projectile-distance cap, and multiplayer needs matching server support before using this option.

## Jam complaint

When the local player tries to fire an aimed firearm that is jammed, a short voice grunt plays using the game's male or female `PainFromRunIntoWall` event at 30% volume. It triggers on a new attack press or when a gun jams while the trigger is held, with a 1.2-second cooldown. Some random variants of this game event are much longer; the voice fades after 0.45 seconds and stops by 0.75 seconds. It does not alter the jam, damage, ammunition, or firing logic. The shortened sound needs an in-game audio check.

## Recoil without a stock

Gael's dynamic recoil is 90% stronger when a shoulder firearm that supports a removable `Stock` fires without one attached. This includes the M4, AK47 and Mini Draco. Pistols, revolvers, one-handed SMGs, intentionally stockless weapons, launchers, and shortened shotguns are excluded. The modifier is applied only while Gael prepares the shot, then immediately restored; attaching a stock removes the penalty for the next shot. This needs an in-game firing check.

## Experimental hold sway for unsupported irons

Enabled by default for `Base.GOL` without an attached optic. While ADS is held, Lua animates a temporary copy of the PVADS profile by changing its calibrated yaw and pitch offsets through `PVADS_setProfile` every 50 ms. This uses the same alignment path as the in-game calibrator and does not require the separate hold-sway Java patch to run. For this visibility test, yaw and pitch move toward independent random targets 15-25 degrees to either side of the saved manual alignment (maximum +/-25 degrees). Each movement uses a random speed equivalent to 0.5-2.0 degrees every 0.25 seconds (2-8 degrees per second). The temporary offsets stop when ADS ends and pause while the calibrator is open. Saved profiles and scoped profiles stay intact. The eligible weapon list is limited to the GOL until checked in game. PVADS' published sight ray should follow the moving alignment; the camera direction stays unchanged. The console logs when Lua sway starts, reaches 15 degrees, and stops, to help verify the active path.

## Slider calibrator

Open the ADS calibrator with its normal key. A companion panel appears on the right with sliders for the sight, recoil, optics and shot-origin calibration values. The three Shot origin controls move the projectile's starting point in the weapon model's local X/Y/Z axes, relative to the normal muzzle point; Y follows the barrel and Z points up. Drag for live adjustment, type exact values, switch range x1/x5/x20, and use Save to write the personal profile. The centered weapon selector has searchable names and IDs plus left/right arrows. Selecting an ADS firearm reuses or grants it, equips it through the normal inventory action, and prepares Hold ADS. Hold Ctrl to aim; V remains the normal ADS toggle.

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
