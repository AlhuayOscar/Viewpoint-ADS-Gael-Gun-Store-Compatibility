-- Recoil benefit for attached grips; handguards are not treated as grips.
PVADS_GaelGrip = PVADS_GaelGrip or {}

local function isGrip(part)
    local identifier = (tostring(part:getPartType() or "") .. " "
        .. tostring(part:getFullType() or "") .. " "
        .. tostring(part:getName() or "")):lower():gsub("[%s_%-]", "")
    if identifier:find("handguard", 1, true)
        or identifier:find("guardamanos", 1, true)
        or identifier:find("foreend", 1, true)
        or identifier:find("forend", 1, true) then return false end
    return identifier:find("grip", 1, true) ~= nil
        or identifier:find("empunadura", 1, true) ~= nil
        or identifier:find("empuñadura", 1, true) ~= nil
end

function PVADS_GaelGrip.recoilMultiplier(weapon)
    if not weapon or not weapon.getAllWeaponParts then return 1 end
    local parts = weapon:getAllWeaponParts()
    if not parts then return 1 end
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part and isGrip(part) then return 0.60 end
    end
    return 1
end
