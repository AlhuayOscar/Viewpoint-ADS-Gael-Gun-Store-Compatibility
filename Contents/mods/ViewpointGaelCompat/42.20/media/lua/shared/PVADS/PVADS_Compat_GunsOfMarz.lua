-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Weapons"

--[[
Guns of Marz (Workshop 3722134990, module MarzGuns) compatibility.

Read from the pack's own scripts (items/weapons/*.txt, items/attachments/scopes.txt):
- GoM optics are ordinary weapon parts (PartType = Scope) whose models attach at the gun's "scope" attachment,
  so the runtime systems (iron sights measured on the loaded mesh, scope tube measurement, upside-down model
  detection, picture-in-picture) apply as they are. This file only says what each gun and optic IS.
- Magnifications follow the item names ("LR4X" = 4x, "TR06X" = 6x, "LR10X" = 10x, "LRX12X" = 12x, "Elcan X2" = 2x).
  GoM's "Sight" items are 1x red dot / holographic sights and are shown like the vanilla red dot.
Harmless when Guns of Marz is not installed: entries are only read for items that exist.
]]

local function fam(family, ids, extra)
    for _, id in ipairs(ids) do
        local def = { family = family }
        if extra then for k, v in pairs(extra) do def[k] = v end end
        PVADS.RegisterWeaponProfile("MarzGuns." .. id, def)
    end
end

-- ---------------------------------------------------------------- weapons (by the pack's own file categories)
fam("assault",     { "M16A1", "M16A2", "M16A2_M203", "M16A3", "AR15", "FNC", "FAMAS", "G36", "AK74", "AK47" })
fam("carbine",     { "CAR15", "XM177", "M4A1", "G36C", "AKS74U", "ASVAL" })
fam("battlerifle", { "M14", "M1_GARAND", "FAL", "G3" })
fam("sniper",      { "MOSIN", "M24", "M1903", "REMINGTON_700", "MODEL_70", "SVD", "PSG1" })
fam("carbine",     { "SKS", "CAMP_CARBINE", "MINI_14", "W1894", "M1895", "W1873", "W1873_CARBINE" })
fam("shotgun",     { "BENELLI_M4", "SPAS12", "AA12" })
-- bead sight only (no rear sight): the eye looks along the top of the receiver to the bead
fam("shotgun",     { "W1887", "MOSSBERG_590", "TRENCHGUN", "STEVENS_555", "DOUBLEBARREL", "REMINGTON_870", "TOZ34" }, { bead = true })
fam("machinegun",  { "M60", "BAR" })
fam("smg",         { "THOMPSON", "MP5", "MP5SD", "MP5A2" })
fam("smg",         { "MP5K", "MAC10" }, { relief = 0.16 })       -- handgun-held SMGs: closer, like the folded MAC-10
fam("pistol",      { "M92FS", "M93R", "HIPOWER", "P226", "M1911", "USP", "DEAGLE", "VP70M", "TEC9" })
fam("pistol",      { "SW629", "PYTHON", "RHINO", "MP412", "COLT_SINGLE", "DETECTIVE_38" })

-- ---------------------------------------------------------------- optics
-- glass: the lens faces of each sight in its own mesh space { x0, x1, z0, z1, y, round }, read from
-- GunsOfMarz media/models_X/weapons/parts/scopes.fbx (the light faces facing along the bore; checked on a
-- rear-view render of every sight). The clear view and the eye are placed on exactly that glass.
local function redDot(id, reticle, glass, extra)
    local def = { kind = "scope", mag = 1.3, reticle = reticle or "dot", lensScale = 0.95, swayMul = 0.87, zero = 50, glass = glass }
    if extra then for k, v in pairs(extra) do def[k] = v end end
    PVADS.RegisterOpticProfile("MarzGuns." .. id, def)
end
local function scope(id, mag, reticle, zero)
    PVADS.RegisterOpticProfile("MarzGuns." .. id, { kind = "scope", mag = mag, reticle = reticle, zero = zero or 100 })
end

-- long-gun red dots / holographic sights
redDot("ReflexS2_Sight", nil,   { -0.0079, 0.0079, -0.0190, -0.0100, 0.0140 })
redDot("Kobra_Sight", nil,      { -0.0087, 0.0087, -0.0301, -0.0127, 0.0270, true })
redDot("OKP3_Sight", nil,       { -0.0094, 0.0094, -0.0336, -0.0148, 0.0251, true })
redDot("JS14_Sight", nil,       { -0.0070, 0.0070, -0.0258, -0.0118, -0.0031, true })
redDot("Aimpoint_Sight", nil,   { -0.0100, 0.0100, -0.0445, -0.0203, 0.0239, true })
redDot("EXPS3_Sight", "holo",   { -0.0069, 0.0069, -0.0269, -0.0145, 0.0167 })
-- EXPS1: its clear window is ~1.9x the measured glass face. Calibrated on the AK47 and AK74 (both 1.90,
-- Brian21699, 2026-10-07); seen just as small on the M4A1 (Bluesky, 2026-10-10), so it is set for every gun.
redDot("EXPS1_Sight", "holo",   { -0.0095, 0.0095, -0.0372, -0.0211, -0.0245 }, { pipScale = 1.90 })
-- pistol red dots
redDot("PL4_Sight", nil,        { -0.0091, 0.0091, 0.0161, 0.0278, 0.0098 })
redDot("PS1_Sight", nil,        { -0.0073, 0.0073, 0.0137, 0.0245, 0.0090 })
redDot("PM2_Sight", nil,        { -0.0072, 0.0072, 0.0185, 0.0351, 0.0262, true })

-- magnified scopes
scope("ElcanX2_Scope", 2,  "crossdot")
scope("LR4X_Scope",    4,  "duplex")
scope("TA28_Scope",    4,  "chevron")
scope("PSO1_Scope",    4,  "eastern")
scope("TR06X_Scope",   6,  "crossdot")
scope("LR10X_Scope",   10, "mildot", 150)
scope("LRX12X_Scope",  12, "mildot", 200)
scope("PRL1_Scope",    2,  "duplex", 25)                         -- pistol / revolver scope

-- ---------------------------------------------------------------- calibration (1.6.2)
-- Tuned in game with the F9 calibrator by tester Brian21699 [TPCR] (Discord #calibration, 2026-10-07).
-- Only values that differ from what the profiles above already resolve to are listed: assault/shotgun family
-- relief, ADS FOV and ADS time, the red dots' 0.95 lens size and the scopes' 0.80 lens size are unchanged.
-- Per weapon + optic (optic "" = iron sights), so nothing carries over to other guns or sights.
local function cal(weapon, optic, def)
    PVADS.RegisterWeaponOpticOverride("MarzGuns." .. weapon, optic == "" and "" or ("MarzGuns." .. optic), def)
end

-- 1.7.16: the iron sight values for the AA12, AK47 and AK74 are gone. They were set by eye before the slope fix
-- (1.7.14) and while the eye still followed the front sight ears; the bench lines these irons up now (PVADS_Compat_Bench).

-- AA12 (no optics on this gun)

-- AK47
cal("AK47", "LRX12X_Scope",    { pipScale = 1.02, pipZoom = 1.20 })
cal("AK47", "TA28_Scope",      { pipY = -0.05, pipScale = 1.02 })
cal("AK47", "ElcanX2_Scope",   { pipScale = 1.025 })
-- 1.7.14: the AK47 / AK74 Reflex S2, Kobra, OKP3 and JS14 values (made for the old glass) are gone: the bench data (PVADS_Compat_Bench) fits them now.
-- AK47 EXPS1: 1.90 on the optic itself (above). LR10X, LR4X, TR06X, PSO1 and EXPS3: already right

-- AK74
cal("AK74", "TA28_Scope",      { pipY = -0.05 })
-- AK74 EXPS1: 1.90 on the optic itself (above). EXPS3 (PiP lens size 1.00), LR4X, ElcanX2, TR06X, PSO1 and LRX12X: already right
