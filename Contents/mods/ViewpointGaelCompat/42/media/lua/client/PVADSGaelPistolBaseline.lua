-- Common pistol iron-sight values measured in the Project Viewpoint ADS calibrator.
-- Explicit IDs exclude existing PVADS user calibrations and completed Excel rows.
-- Any future PVADS_UserProfiles.txt entry for a weapon still wins over this baseline.
require "PVADS/PVADS_Core"
require "PVADS/PVADS_Defaults"

local pistolIds = {
    "Kimber1911", "M9_Samurai", "MP1911", "OTS_33", "P220", "P220_Elite",
    "P228", "P99", "PB6P9", "Pistol", "Pistol2", "Pistol3",
    "pistol_shotgun", "Samurai_aw", "Samurai_kendo", "SR1M", "USP45",
    "VictorySW22", "VP70", "Walther_P38", "Wildey", "XD",
}

local baseline = {
    adjX = 0.0,
    adjY = -0.0600,
    adjZ = 0.0072,
    adjPitch = 1.3500,
    adjYaw = 0.0,
    adjRoll = 0.0,
    relief = 0.1600,
    fovMul = 0.9500,
    adsTime = 0.1700,
}

for _, id in ipairs(pistolIds) do
    PVADS.RegisterWeaponProfile("Base." .. id, baseline)
end
print("[ViewpointGaelCompat] Registered " .. #pistolIds .. " pistol profiles")
