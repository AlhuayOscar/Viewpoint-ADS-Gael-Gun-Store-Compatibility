-- Adds debug-only Viewpoint profile markers and instant attachment previews
-- to GaelGunStore's 3D Inspect attachment picker.
local hooked = false

local function debugUser()
    local config = rawget(_G, "GGS_DebugConfig")
    local player = getPlayer and getPlayer() or nil
    if config and config.canUse and player then
        local ok, allowed = pcall(config.canUse, player)
        if ok and allowed == true then return true end
    end
    -- The marker is a developer aid; also honor the game's native debug mode.
    if type(isDebugEnabled) == "function" and isDebugEnabled() then return true end
    if type(getDebug) == "function" and getDebug() then return true end
    local pvads = rawget(_G, "PVADS")
    return pvads and pvads.Settings and pvads.Settings.developer == true or false
end

local function profileExists(weapon, part)
    local pvads = rawget(_G, "PVADS")
    if not (pvads and pvads.User and weapon and part) then return false end
    local weaponId = weapon.getFullType and weapon:getFullType()
    local opticId = type(part) == "string" and part
        or (part.getFullType and part:getFullType())
    if not weaponId or not opticId then return false end
    local values = pvads.User[tostring(weaponId) .. "|" .. tostring(opticId)]
    return type(values) == "table" and next(values) ~= nil
end

local function install()
    if hooked then return true end
    local class = rawget(_G, "addAttachmentButton")
    if not (class and class.render) then return false end
    local oldRender = class.render
    class.render = function(self, ...)
        local result = oldRender(self, ...)
        local ok, isDebug = pcall(debugUser)
        if ok and isDebug and self.type == "WeaponPart" then
            local optic = self.slotItem or self.devSpawnFullType
            local hasProfile = false
            local profileOK = pcall(function()
                hasProfile = profileExists(self.attachingTo, optic)
            end)
            local missingHover = profileOK and not hasProfile and self:isMouseOver()
            if hasProfile or missingHover then
                -- The inventory tooltip overlaps the lower part of the cell;
                -- this short status strip stays visible while hovering.
                local label = hasProfile and "Tiene perfil." or "Mira que falta"
                self:drawRect(0, 1, self.width, 15, 0.9, 0, 0, 0)
                self:drawTextCentre(label, self.width / 2, 1, 1, 0.95, 0.72, 0.08, UIFont.Small)
            end
        end
        return result
    end
    hooked = true
    print("[ViewpointGaelCompat][GGS attachment] profile marker hook installed; native install flow preserved")
    return true
end

local function tryInstall()
    if install() and Events.OnTick then Events.OnTick.Remove(tryInstall) end
end

print("[ViewpointGaelCompat][GGS attachment] profile marker loaded")
tryInstall()
if not hooked then
    if Events.OnGameBoot then Events.OnGameBoot.Add(tryInstall) end
    if Events.OnGameStart then Events.OnGameStart.Add(tryInstall) end
    if Events.OnTick then Events.OnTick.Add(tryInstall) end
end
