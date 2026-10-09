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
    {"EKP_kobra_2x", 2, "kobra_open"}, {"POSP", 4, "eastern"},
    {"POSP4x24", 4, "eastern"}, {"Zeiss4x25", 4, "duplex"},
    {"Comp_M4", 1, "dot"}, {"Coyote", 1, "dot"},
    {"CP1", 1, "dot"}, {"CrimsonRedDot", 1, "dot"},
    {"Deltapoint", 1, "dot"}, {"Eotech", 1, "holo"},
    {"Eotech_XPS3", 1, "holo"}, {"Kobra", 1, "kobra_open"},
    {"MicroT1", 1, "dot"}, {"MiniRedDot", 1, "dot"},
    {"OKP7", 1, "okp7"}, {"PKA", 1, "dot"},
    {"RDS", 1, "dot"}, {"RedDot", 1, "dot"},
    {"Romeo3", 1, "dot"}, {"RX01", 1, "dot"},
    {"SigSauerRomeo3", 1, "dot"}, {"SLDG", 1, "dot"},
    {"TruBrite", 1, "dot"}, {"VenomRDS", 1, "dot"},
    {"VortexRedDot", 1, "dot"}, {"ZaMiniRDS", 1, "dot"},
    {"EKP_kobra", 1, "kobra_open"},
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
-- These two mini red-dot meshes have an opaque-looking centre when the dot is
-- only overlaid on top. PVADS's 1x scope mode cuts the sight model out of the
-- PiP lens without magnifying the scene. Preserve the normal reflex eye relief
-- so existing weapon+optic alignments remain valid.
local clearMiniDots = { ["Base.ZaMiniRDS"] = true, ["Base.MiniRedDot"] = true }
for opticId in pairs(clearMiniDots) do
    PVADS.RegisterOpticProfile(opticId, {
        kind = "scope", mag = 1, reticle = "dot", zero = 50,
        relief = 0.17, fovMul = 1.0,
    })
end
PVADS.RegisterADSAdapter("GaelMiniDotClearLens", function(_, profile)
    if clearMiniDots[profile.opticId] then profile.pipDepth = 0.04 end
end)
-- Gael's TritiumSights item points at the VenomRDS 3D mesh, so it is a dot.
PVADS.RegisterOpticProfile("Base.TritiumSights", { kind = "reflex", mag = 1, reticle = "dot", zero = 50 })
PVADS.RegisterWeaponProfile("Base.UMP45", { family = "smg" })
PVADS.RegisterWeaponProfile("Base.UMP45_long", { family = "smg" })

-- M1 Garand + Gael ACOG 4x32: manually calibrated scope and PiP lens.
-- These values mirror the user's saved Base.M1|Base.ACOGx4 profile, so the
-- alignment also travels with this compatibility mod.
PVADS.RegisterWeaponOpticOverride("Base.M1", "Base.ACOGx4", {
    mode = "scope", mag = 4, reticle = "mildot",
    zoomLevels = { 2, 4 }, lensScale = 0.8,
    adjZ = -0.00720, adjY = 0.13650, fovMul = 0.50000,
    relief = 0.23000, adjPitch = 0.20000, adjYaw = -0.07500,
    opticHeight = 0.03000, pipDepth = 0.00000, pipZoom = 1.00000,
    pipRetX = 0.00000, pipY = 0.00000, pipZ = -0.08200,
})

-- Preserve the separate M1 + x8 calibration too.
PVADS.RegisterWeaponOpticOverride("Base.M1", "Base.x8Scope", {
    mode = "scope", mag = 8, reticle = "mildot",
    zoomLevels = { 2, 4, 8 }, lensScale = 0.8,
    adjZ = -0.01840, adjY = 0.14350, fovMul = 0.50000,
    pipY = 0.00000, pipZ = -0.07000,
})

-- ADS's generated Base.AK74 geometry belongs to its STALKER mesh, while
-- Gael's active Base.AK74 uses AR/AssaultRifles|AK74. Discard that geometry.
-- Do not replace it with guessed rear/front points: doing so disables ADS's
-- live iron-sight mesh measurement and broke the user's manual calibration.
local generatedAK74 = PVADS.Generated and PVADS.Generated.weapons
    and PVADS.Generated.weapons["Base.AK74"]
if generatedAK74 and generatedAK74.source == "STALKER" then
    PVADS.Generated.weapons["Base.AK74"] = nil
end
PVADS.RegisterWeaponProfile("Base.AK74", {
    family = "assault", weaponLength = 0.55,
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
