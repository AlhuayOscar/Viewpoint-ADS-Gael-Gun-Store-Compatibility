-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Defaults"

--[[
Hand-set per-weapon data that the mesh scan cannot know. Everything else comes from
PVADS_GeneratedProfiles.lua (measured from the installed meshes) and the family defaults.
These entries are harmless when the pack is not installed: they are only read for items that exist.
]]

-- Families the name heuristics get wrong
PVADS.RegisterWeaponProfile("Base.SPRSD",        { family = "sniper" })
PVADS.RegisterWeaponProfile("Base.AssaultRifleM1", { family = "battlerifle" })
PVADS.RegisterWeaponProfile("Base.M2400_Rifle",  { family = "sniper" })
PVADS.RegisterWeaponProfile("Base.Revolver_Long", { relief = 0.19 })
PVADS.RegisterWeaponProfile("Base.Vector45",     { family = "smg" })
PVADS.RegisterWeaponProfile("Base.Vector9",      { family = "smg" })
PVADS.RegisterWeaponProfile("Base.P90",          { family = "smg" })
PVADS.RegisterWeaponProfile("Base.MP7",          { family = "smg" })
PVADS.RegisterWeaponProfile("Base.MAC10Unfolded", { family = "smg" })
PVADS.RegisterWeaponProfile("Base.MAC10Folded",  { family = "smg", relief = 0.16 })
PVADS.RegisterWeaponProfile("Base.UziUnfolded",  { family = "smg" })
PVADS.RegisterWeaponProfile("Base.UziFolded",    { family = "smg", relief = 0.16 })
PVADS.RegisterWeaponProfile("Base.Tec9",         { family = "pistol" })
PVADS.RegisterWeaponProfile("Base.Glock18",      { family = "pistol", recoilMul = 0.8, kickMul = 0.55, recover = 0.45 })

-- Rifles whose mesh has no usable irons (scope-only bolt guns): ADS still works, aligned on the
-- receiver top; with an optic mounted the optic takes over.
PVADS.RegisterWeaponProfile("Base.SniperRifle",  { family = "sniper" })
PVADS.RegisterWeaponProfile("Base.MSR7T_Rifle",  { family = "sniper" })

-- Sawn-off guns are pointed, not aimed: shorter, quicker, a little less zoom.
for _, id in ipairs({ "Base.ShotgunSawnoff", "Base.ShotgunSawnoffNoStock", "Base.DoubleBarrelShotgunSawnoff",
                      "Base.DoubleBarrelShotgunSawnoffNoStock", "Base.MP153sawn" }) do
    PVADS.RegisterWeaponProfile(id, { adsTime = 0.2, fovMul = 0.95, relief = 0.15 })
end

-- Toys
PVADS.RegisterWeaponProfile("Base.Revolver_CapGun", { family = "pistol", recoilMul = 0.1, kickMul = 0.1 })
PVADS.RegisterWeaponProfile("Base.Rifle_CapGun",    { family = "carbine", recoilMul = 0.1, kickMul = 0.1 })

PVADS.Registry.duplicates = {}
