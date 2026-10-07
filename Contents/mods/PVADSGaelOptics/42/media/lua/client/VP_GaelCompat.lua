-- Gael's Scope and L_Scope parts need explicit Viewpoint ADS profiles.
-- The latter is not one of the optic part types recognized by PVADS.findOptic.
require "PVADS/PVADS_Core"
require "PVADS/PVADS_Defaults"

local Compat = {}

-- { item/model name, magnification, reticle }. Gael uses module Base for these parts.
local optics = {
    {"Accupoint", 4, "duplex"}, {"Acog_ecos", 4, "chevron"},
    {"Acog_TA648", 6, "chevron"}, {"ACOGx4", 4, "chevron"},
    {"ATN_Thor", 4, "crossdot"}, {"BallisticScope", 8, "mildot"},
    {"Bravo4", 4, "chevron"}, {"Compact4x", 4, "duplex"},
    {"Elcan_M145", 3.4, "crossdot"}, {"Eotech_vudu", 6, "crossdot"},
    {"HAMR", 4, "chevron"}, {"IRNV", 4, "crossdot"},
    {"Leapers_UTG3", 3, "mildot"}, {"PistolScope", 2, "duplex"},
    {"PM_IILP", 4, "eastern"}, {"Spectre", 4, "crossdot"},
    {"Springfield_longrange_scope", 8, "mildot"}, {"SUSAT", 4, "post"},
    {"x2Scope", 2, "crossdot"}, {"x4Scope", 4, "duplex"},
    {"x8Scope", 8, "mildot"},
    {"1P78", 2.8, "eastern"}, {"1PN93_4", 4, "eastern"},
    {"EKP_kobra_2x", 2, "dot"}, {"POSP", 4, "eastern"},
    {"POSP4x24", 4, "eastern"}, {"Zeiss4x25", 4, "duplex"},
    {"Comp_M4", 1, "dot"}, {"Coyote", 1, "dot"},
    {"CP1", 1, "dot"}, {"CrimsonRedDot", 1, "dot"},
    {"Deltapoint", 1, "dot"}, {"Eotech", 1, "holo"},
    {"Eotech_XPS3", 1, "holo"}, {"Kobra", 1, "eastern"},
    {"MicroT1", 1, "dot"}, {"MiniRedDot", 1, "dot"},
    {"OKP7", 1, "eastern"}, {"PKA", 1, "dot"},
    {"RDS", 1, "dot"}, {"RedDot", 1, "dot"},
    {"Romeo3", 1, "dot"}, {"RX01", 1, "dot"},
    {"SigSauerRomeo3", 1, "dot"}, {"SLDG", 1, "dot"},
    {"TruBrite", 1, "dot"}, {"VenomRDS", 1, "dot"},
    {"VortexRedDot", 1, "dot"}, {"ZaMiniRDS", 1, "dot"},
    {"EKP_kobra", 1, "eastern"},
}

-- Eye distance is measured from the rear eyepiece in weapon model units.
-- The stock Viewpoint scope value (0.10) puts these large Gael models against
-- the camera. Keep compact scopes and all open sights at their normal distance.
local longScopeRelief = {
    ACOGx4 = 0.22, Acog_ecos = 0.22, Acog_TA648 = 0.25,
    ATN_Thor = 0.24, BallisticScope = 0.26, Eotech_vudu = 0.24,
    IRNV = 0.24, PM_IILP = 0.23, Spectre = 0.21,
    Springfield_longrange_scope = 0.27,
    x8Scope = 0.25, POSP = 0.23, POSP4x24 = 0.23,
    Zeiss4x25 = 0.22, ["1PN93_4"] = 0.24,
}

for _, row in ipairs(optics) do
    local name, mag, reticle = row[1], row[2], row[3]
    PVADS.RegisterOpticProfile("Base." .. name, {
        kind = mag == 1 and "reflex" or "scope", mag = mag, reticle = reticle,
        zero = mag == 1 and 50 or 100,
        relief = longScopeRelief[name],
    })
end
PVADS.RegisterOpticProfile("Base.TritiumSights", { kind = "iron" })
PVADS.RegisterWeaponProfile("Base.UMP45", { family = "smg" })
PVADS.RegisterWeaponProfile("Base.UMP45_long", { family = "smg" })

-- ADS's generated Base.AK74 geometry belongs to its STALKER mesh, while
-- Gael's active Base.AK74 uses AR/AssaultRifles|AK74.  The wrong sight line
-- forces the hands into a distorted pose.  These points use Gael's muzzle,
-- Scope and handguard attachments as a conservative sight-line baseline.
local generatedAK74 = PVADS.Generated and PVADS.Generated.weapons
    and PVADS.Generated.weapons["Base.AK74"]
if generatedAK74 and generatedAK74.source == "STALKER" then
    PVADS.Generated.weapons["Base.AK74"] = nil
end
PVADS.RegisterWeaponProfile("Base.AK74", {
    family = "assault", rear = { 0, 0.083, 0.052 },
    front = { 0, 0.35, 0.052 }, weaponLength = 0.55,
})

-- Registering a model shape also lets PVADS's Java finder recognize Gael's
-- L_Scope models, whose attachment names do not start with "scope".
-- Scope models already have a discoverable attachment, so keep their measured
-- geometry intact instead of replacing it with generic dimensions.
local sideMountModels = {
    "1P78", "1PN93_4", "EKP_kobra", "EKP_kobra_2x",
    "POSP", "POSP4x24", "Zeiss4x25",
}
local function registerShapes()
    if not PVADS_setOpticShape then return end
    for _, model in ipairs(sideMountModels) do
        PVADS_setOpticShape(model, 0.03, 0.12, 0.018)
    end
    if PVADS.Controller and PVADS.Controller.ready then PVADS.Controller.refresh(true) end
    print("[ViewpointGaelCompat] Registered " .. #optics .. " Gael optics")
end

Events.OnGameStart.Add(registerShapes)
return Compat
