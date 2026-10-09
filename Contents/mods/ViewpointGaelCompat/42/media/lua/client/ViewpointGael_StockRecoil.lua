-- Gael's dynamic recoil is calculated inside prepareShot. Supply a temporary
-- handling modifier for shoulder weapons fired without their removable stock.
local aiming = require "GGS_AimingSystem"
require "GGS_AttachmentRules"
require "PVADS_GaelWeaponCatalog"

local shoulderWeapons = {}
for _, entry in ipairs(PVADS_GaelWeaponCatalog or {}) do
    local number, fullType = entry[1], entry[2]
    -- 96-124: shoulder SMGs; 125-343: rifles, machine guns and shotguns.
    -- Pistols, revolvers, one-handed SMGs and launchers are outside this range.
    if number >= 96 and number <= 343
        and not fullType:match("_Short$")
        and not fullType:match("_sawn$")
        and not fullType:match("Sawnoff$") then
        shoulderWeapons[fullType] = true
    end
end

local function permitsStock(fullType)
    local slots = AWCWF_GunAllowAttachments and AWCWF_GunAllowAttachments[fullType]
    if not slots then return false end
    for _, slot in ipairs(slots) do
        if slot == "Stock" then return true end
    end
    return false
end

local function modifier(item, key, registry)
    if not item then return 0 end
    local data = item:getModData()
    local profile = registry and registry[item:getFullType()]
    local value = data and data[key]
    if value == nil then value = profile and profile[key] end
    return math.max(-75, math.min(150, tonumber(value) or 0))
end

local originalPrepareShot = aiming.prepareShot
if type(originalPrepareShot) == "function" then
    aiming.prepareShot = function(playerObj, weapon)
        if not (playerObj and weapon and weapon.getFullType and weapon.getWeaponPart
            and aiming.isDynamicAimEnabled(playerObj)
            and aiming.isFirearmWeapon(weapon)) then
            return originalPrepareShot(playerObj, weapon)
        end

        local fullType = weapon:getFullType()
        if not (shoulderWeapons[fullType] and permitsStock(fullType))
            or weapon:getWeaponPart("Stock") then
            return originalPrepareShot(playerObj, weapon)
        end

        local data = weapon:getModData()
        if not data then return originalPrepareShot(playerObj, weapon) end
        local previous = data.RealRecoil
        local weaponRecoil = modifier(weapon, "RealRecoil", aiming.weaponModifiers)
        local partsRecoil = 0
        local parts = weapon:getAllWeaponParts()
        if parts then
            for index = 0, parts:size() - 1 do
                partsRecoil = partsRecoil + modifier(parts:get(index), "RealRecoil", aiming.partModifiers)
            end
        end

        -- Gael uses 1 + (weaponRecoil + partsRecoil) / 100. Adjust the weapon
        -- term so the complete recoil multiplier, including parts, grows 90%.
        data.RealRecoil = math.max(-75, math.min(150,
            90 + 1.90 * weaponRecoil + 0.90 * partsRecoil))
        local ok, result = pcall(originalPrepareShot, playerObj, weapon)
        data.RealRecoil = previous
        if not ok then error(result) end
        return result
    end
end
