-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Controller"

--[[
Aiming takes priority over menus that share its inputs.

1. The ADS key (V by default) is also the game's vehicle / animal radial menu key (and can be Toggle UI).
   While you hold a firearm and can aim down sights, that key belongs to ADS: the game's handlers
   (ISUIHandler.onKeyStartPressed / onKeyPressed, client/ISUI/ISUIHandler.lua) are wrapped the same way the
   game's own events are registered and only run when ADS does not want the key.
2. Viewpoint Interface (ViewpointUI) shows an interaction prompt / action menu for what the crosshair is on.
   While you aim a firearm (hip or sights) there is no interaction target: its Target.update
   (ViewpointUI.Interaction.Target, read every tick by its controller) returns nothing, so the prompt, the
   action menu and its claim on the Interact key go away until you lower the gun.
Both can be turned off with the "Aiming takes priority" option.
]]

local P = {}
PVADS.Priority = P

local function enabled()
    return PVADS.Settings.aimPriority ~= false
end

local function gunInHand(pl)
    return pl and not pl:isDead() and PVADS.Controller.weapon(pl) ~= nil
end

--- The ADS key press belongs to ADS (not to a radial menu / UI toggle on the same key).
function P.ownsKey(key)
    if not enabled() or not PVADS.Controller.ready then return false end
    local s = PVADS.Settings
    if PVADS.refreshKeys then PVADS.refreshKeys() end
    if key ~= s.key or s.mode == 1 then return false end   -- aim mode does not use the ADS key
    local pl = getSpecificPlayer(0)
    if not gunInHand(pl) or pl:getVehicle() then return false end
    return PVADS_canAds and PVADS_canAds() and true or false
end

--- Aiming a firearm right now (hip or sights).
function P.aimingGun()
    if not enabled() then return false end
    local pl = getSpecificPlayer(0)
    return gunInHand(pl) and pl:isAiming() and not pl:getVehicle()
end

local function wrapKeyHandler(eventName, owner, field)
    local original = owner and owner[field]
    if type(original) ~= "function" then
        PVADS.log("priority: " .. tostring(field) .. " not found; the ADS key may still open its menu")
        return
    end
    Events[eventName].Remove(original)
    local wrapped = function(key, ...)
        local ok, mine = pcall(P.ownsKey, key)
        if ok and mine then return end
        return original(key, ...)
    end
    owner[field] = wrapped
    Events[eventName].Add(wrapped)
end

local function wrapViewpointUI()
    local T = ViewpointUI and ViewpointUI.Interaction and ViewpointUI.Interaction.Target
    if not T or type(T.update) ~= "function" or T.pvadsWrapped then return false end
    local original = T.update
    T.update = function(...)
        local ok, aiming = pcall(P.aimingGun)
        if ok and aiming then
            if type(T.clear) == "function" then pcall(T.clear) end
            return nil
        end
        return original(...)
    end
    T.pvadsWrapped = true
    PVADS.log("priority: Viewpoint Interface prompts step aside while aiming")
    return true
end

local installed = false
local function install()
    if installed then return end
    installed = true
    if ISUIHandler then
        wrapKeyHandler("OnKeyStartPressed", ISUIHandler, "onKeyStartPressed")
        wrapKeyHandler("OnKeyPressed", ISUIHandler, "onKeyPressed")
    end
    wrapViewpointUI()
end

Events.OnGameStart.Add(install)
