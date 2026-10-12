--[[
    Project Viewpoint ADS - Dynamic Optics & Mounts Adapter for Gael Gun Store.
    
    Solves variations across 342 weapons and 52 optics:
    1. Pistols vs Rifles: Low slide mount + arm-length eye relief (0.18 m).
    2. Intermediate Mounts: Detects equipped mount parts (AK side mounts, Mosin mounts,
       shotgun rails) and dynamically adds the physical riser height.
    3. Scopes: Eye relief into eyepiece tube (0.0 m) and magnification-scaled FOV.
    4. Manual override protection: If the weapon+optic was hand-calibrated in
       PVADS_GaelSavedProfiles.lua or user profiles, manual values win!
]]

require "PVADS/PVADS_Core"

local MOUNT_HEIGHTS = {
    ["ak_mount_kobra"] = 0.0515,
    ["ak_mount_sag"] = 0.0426,
    ["ak_mount_vpo"] = 0.0345,
    ["ak_mount_xd_rgl"] = 0.0408,
    ["AkMount"] = 0.0429,
    ["ak_mount"] = 0.0429,
    ["Mosin_Mount"] = 0.0285,
    ["mount_mosin"] = 0.0285,
    ["mount_rail"] = 0.0186,
    ["RB7M_Mount"] = 0.0450,
    ["scrap_mount"] = 0.0437,
    ["scrap_mount_shotgun"] = 0.0440,
    ["UniversalMount"] = 0.0369,
}

local PISTOL_OPTICS = {
    ["Base.MiniRedDot"] = true,
    ["Base.ZaMiniRDS"] = true,
    ["Base.PistolScope"] = true,
    ["Base.Deltapoint"] = true,
    ["Base.VenomRDS"] = true,
    ["Base.Romeo3"] = true,
}

local function findEquippedMount(weapon)
    if not weapon or not weapon.getAllWeaponParts then return nil, nil end
    local parts = weapon:getAllWeaponParts()
    if not parts then return nil, nil end
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part then
            local partType = part:getPartType() or ""
            local fullType = part:getFullType() or ""
            local shortType = string.match(fullType, "[^%.]+$") or fullType
            if partType == "Mount" or (part.hasTag and part:hasTag("mounts")) or MOUNT_HEIGHTS[shortType] then
                return part, shortType
            end
        end
    end
    return nil, nil
end

local function gaelOpticsAdapter(weapon, profile, opticPart)
    if not weapon or not profile or not opticPart then return end
    
    local weaponId = weapon:getFullType()
    local opticId = opticPart:getFullType()
    local userKey = weaponId .. "|" .. opticId
    
    -- If user hand-tuned this specific weapon+optic combination, do NOT override their manual values!
    local manualTune = (PVADS.WeaponOptic[weaponId] and PVADS.WeaponOptic[weaponId][opticId])
        or (PVADS.User and PVADS.User[userKey])
    if manualTune and (manualTune.adjZ or manualTune.adjPitch or manualTune.opticHeight) then
        return
    end

    local isPistol = profile.family == "pistol" or (weapon.getSwingAnim and weapon:getSwingAnim() == "Handgun")
    local mountPart, mountType = findEquippedMount(weapon)

    -- 1. Pistol slide optics
    if isPistol then
        profile.relief = 0.18
        if PISTOL_OPTICS[opticId] or profile.mode == "reflex" then
            profile.opticHeight = 0.013
            profile.fovMul = 0.92
        end
    else
        -- 2. Rifles & Shotguns: intermediate mounts
        if mountType and MOUNT_HEIGHTS[mountType] then
            local mountRiser = MOUNT_HEIGHTS[mountType]
            profile.opticHeight = (profile.opticHeight or 0.028) + mountRiser
        end
        
        -- 3. High-magnification scopes: eye relief into eyepiece tube
        if profile.kind == "scope" or (profile.mag and profile.mag >= 2.0) then
            profile.relief = 0.0
            if profile.mag >= 7.0 then
                profile.fovMul = 0.35
            elseif profile.mag >= 3.5 then
                profile.fovMul = 0.50
            elseif profile.mag >= 1.8 then
                profile.fovMul = 0.65
            end
        end
    end
end

PVADS.RegisterADSAdapter("GaelOpticsMountAdapter", gaelOpticsAdapter)
print("[ViewpointGaelCompat] Registered GaelOpticsMountAdapter (Dynamic Mount & Optic Adjuster).")
