-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Core"

--[[
Default handling per weapon family and per optic. All numbers are presentation only: they never touch
damage, accuracy stats, ammo, jamming or anything the server owns.

  adsTime    seconds to fully raise the sights (scaled by the player's ADS speed option)
  relief     eye distance behind the sight point, weapon units (~0.55 m per unit on PZ guns)
  fovMul     view narrowing at full ADS for irons/red dots (1 = none)
  swayMul    breathing sway scale        recoilMul  gun kick scale        kickMul  view climb scale
climb      view climb per shot (deg)   side       sideways push (deg)   recover  share of the climb that settles back
gunKick    visible muzzle flip (deg)   gunBack    push back (m)         hipCone  hip-fire cone half angle (deg)
  ironHeight sight height above the bore when a mesh gave nothing better
  zero       distance the sight is zeroed at, metres (0 = none). Read by ballistics mods through the
             Sight API (pvads.Sight); ADS itself does not use it. Families give the iron zero,
             optic kinds/profiles override it (the iron kind has none, so flip-up irons keep the weapon's).
]]

-- pistols (v1.0.21): held close like the long guns, so the arms and body behind them stay out of the view
PVADS.RegisterWeaponFamily("pistol",      { adsTime = 0.17, relief = 0.16, fovMul = 0.95, swayMul = 1.30, recoilMul = 1.00, kickMul = 1.00, climb = 2.2, side = 0.9, recover = 0.65, gunKick = 7.0, gunBack = 0.030, hipCone = 1.2, ironHeight = 0.012, zero = 15 })
PVADS.RegisterWeaponFamily("smg",         { adsTime = 0.21, relief = 0.13, fovMul = 0.94, swayMul = 1.00, recoilMul = 1.00, kickMul = 1.00, climb = 0.75, side = 0.45, recover = 0.35, gunKick = 2.5, gunBack = 0.015, hipCone = 1.8, ironHeight = 0.035, zero = 25 })
PVADS.RegisterWeaponFamily("carbine",     { adsTime = 0.25, relief = 0.12, fovMul = 0.93, swayMul = 1.00, recoilMul = 1.00, kickMul = 1.00, climb = 0.9, side = 0.5, recover = 0.40, gunKick = 3.0, gunBack = 0.020, hipCone = 2.5, ironHeight = 0.030, zero = 50 })
PVADS.RegisterWeaponFamily("assault",     { adsTime = 0.26, relief = 0.11, fovMul = 0.93, swayMul = 1.00, recoilMul = 1.00, kickMul = 1.00, climb = 1.0, side = 0.6, recover = 0.35, gunKick = 3.5, gunBack = 0.022, hipCone = 3.0, ironHeight = 0.045, zero = 50 })
PVADS.RegisterWeaponFamily("shotgun",     { adsTime = 0.27, relief = 0.12, fovMul = 0.95, swayMul = 1.10, recoilMul = 1.00, kickMul = 1.00, climb = 3.5, side = 1.0, recover = 0.60, gunKick = 8.0, gunBack = 0.045, hipCone = 2.0, ironHeight = 0.018, zero = 15 })
PVADS.RegisterWeaponFamily("battlerifle", { adsTime = 0.31, relief = 0.11, fovMul = 0.93, swayMul = 1.15, recoilMul = 1.00, kickMul = 1.00, climb = 1.8, side = 0.8, recover = 0.40, gunKick = 5.0, gunBack = 0.030, hipCone = 3.5, ironHeight = 0.040, zero = 100 })
PVADS.RegisterWeaponFamily("machinegun",  { adsTime = 0.40, relief = 0.12, fovMul = 0.94, swayMul = 1.45, recoilMul = 1.00, kickMul = 1.00, climb = 0.9, side = 0.7, recover = 0.30, gunKick = 3.5, gunBack = 0.025, hipCone = 4.0, ironHeight = 0.045, zero = 100 })
PVADS.RegisterWeaponFamily("sniper",      { adsTime = 0.42, relief = 0.11, fovMul = 0.70, swayMul = 0.90, recoilMul = 1.00, kickMul = 1.00, climb = 3.0, side = 0.6, recover = 0.65, gunKick = 7.0, gunBack = 0.040, hipCone = 5.0, ironHeight = 0.030, zero = 100 })

-- Optic kinds
PVADS.RegisterOpticKind("iron",   { mag = 1, reticle = "none" })
-- Scopes: normal eye relief behind the eyepiece while raising; once the lens is fully up the gun model
-- is hidden and only the magnified view + reticle remain (v1.0.6, from in-game testing on the M4A1 x2).
PVADS.RegisterOpticKind("reflex", { mag = 1, reticle = "dot", relief = 0.17, fovMul = 0.94, zero = 50 })
PVADS.RegisterOpticKind("scope",  { reticle = "duplex", relief = 0.10, fovMul = 1.0, swayMul = 1.15, lensScale = 0.8, zero = 100 })

-- Vanilla / VFE optic items (VFE re-defines the vanilla ones; STALKER and Post '93 reuse them).
-- Magnification comes from the item itself (x2/x4/x8). Reticles are original Project Viewpoint designs,
-- picked per optic model so the Eastern PSO-style scope on AK-pattern rifles gets an Eastern-style reticle.
-- Red dot (v1.0.15): shown like the scopes - gun and arms hidden once it is up, a wide 1x lens with the
-- dot in the middle. Aligning the small red dot model put the gun far forward and stretched the shoulders.
PVADS.RegisterOpticProfile("Base.RedDot",          { kind = "scope", mag = 1.3, reticle = "dot", lensScale = 0.95, swayMul = 0.87, zero = 50 })
PVADS.RegisterOpticProfile("Base.TritiumSights",   { kind = "iron" })
PVADS.RegisterOpticProfile("Base.IronSight",       { kind = "iron" })
PVADS.RegisterOpticProfile("Base.x2Scope",         { kind = "scope", mag = 2, reticle = "crossdot",
                                                     reticles = { M14x2Scope = "crossdot", x2Scope = "chevron" } })
PVADS.RegisterOpticProfile("Base.x4Scope",         { kind = "scope", mag = 4, reticle = "duplex",
                                                     reticles = { PSO1x4Scope = "eastern", Leverx4Scope = "post", M14x4Scope = "duplex", x4Scope = "duplex" } })
PVADS.RegisterOpticProfile("Base.x8Scope",         { kind = "scope", mag = 8, reticle = "mildot", zero = 150 })
PVADS.RegisterOpticProfile("Base.x2Scope_Fake",    { kind = "scope", mag = 2, reticle = "chevron" })
PVADS.RegisterOpticProfile("Base.x4Scope_Fake",    { kind = "scope", mag = 4, reticle = "eastern" })
PVADS.RegisterOpticProfile("Base.x8Scope_Fake",    { kind = "scope", mag = 8, reticle = "mildot", zero = 150 })

-- Registry duplicates above are intentional defaults; clear them so the validator only reports
-- duplicates added by other mods.
PVADS.Registry.duplicates = {}
