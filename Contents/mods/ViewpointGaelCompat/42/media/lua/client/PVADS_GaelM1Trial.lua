-- Debug-only setup for testing Gael's M1 Garand with its ACOG 4x32.
local function attachTrialScope(player, weapon)
    if not player or not weapon or weapon:getFullType() ~= "Base.M1" then return end
    if weapon:getWeaponPart("Scope") then return end

    local inventory = player:getInventory()
    local optic = inventory and inventory:AddItem("Base.ACOGx4")
    if not optic then return end

    weapon:attachWeaponPart(player, optic)
    local attached = weapon:getWeaponPart("Scope")
    if attached == optic then
        if inventory:contains(optic) then inventory:Remove(optic) end
        player:Say("ACOG 4x32 mounted: test 2x/4x scope mode.")
    else
        player:Say("Could not mount the ACOG 4x32.")
    end
end

local function addTrialOption(playerNum, context)
    if not context or not isDebugEnabled or not isDebugEnabled() then return end
    local player = type(playerNum) == "number" and getSpecificPlayer(playerNum) or getPlayer()
    local weapon = player and player:getPrimaryHandItem()
    if not weapon or weapon:getFullType() ~= "Base.M1" then return end
    if weapon:getWeaponPart("Scope") then return end
    context:addOption("Debug: Mount ACOG 4x32 on M1 Garand", nil, attachTrialScope, player, weapon)
end

Events.OnFillInventoryObjectContextMenu.Add(addTrialOption)
