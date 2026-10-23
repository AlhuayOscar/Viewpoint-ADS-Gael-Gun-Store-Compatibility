-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
--[[
GaelGunStore's scope overlay (lua/client/UI/GGS_ScopeCrosshair.lua, global GGS_ScopeCrosshair) is made for the
top-down view: while you aim with an optic it draws a full-screen lens border, a black mask and peripheral
vision shading, and before each shot (GGS_DynamicAmmo -> GGS_ScopeCrosshair.alignShotToReticle) it warps the
mouse cursor and turns the character toward its reticle. Under Viewpoint the view is drawn from the eye, so
that overlay covered the sights and the cursor warp turned the camera.

While Viewpoint draws the view (first or third person) this keeps it off: its per-player update is skipped
(the panel is hidden once with its own GGS_ScopeCrosshair.resetAllPanels, which also gives back the game's
reticle and cursor options) and the shot alignment returns false (not aligned), as it does when it cannot warp.
In the top-down view everything runs exactly as the pack made it. Nothing in the pack's files is changed:
its handler is taken off Events.OnPlayerUpdate (vanilla Events.X.Remove) and a wrapper put on in its place.
]]

local wrapped = false

local function viewOn()
    return PVADS_viewOn ~= nil and PVADS_viewOn() == true
end

local function wrap()
    if wrapped then return end
    local SC = rawget(_G, "GGS_ScopeCrosshair")
    if type(SC) ~= "table" or type(SC.updatePlayer) ~= "function" then return end
    if PVADS.bindJava then PVADS.bindJava() end
    if not PVADS_viewOn then return end                       -- Java part not loaded: leave the pack alone
    wrapped = true
    local origUpdate, origAlign = SC.updatePlayer, SC.alignShotToReticle
    local hidden = false
    local function update(playerObj)
        if playerObj and viewOn() then
            if not hidden then
                hidden = true
                if SC.resetAllPanels then pcall(SC.resetAllPanels) end
            end
            return
        end
        hidden = false
        return origUpdate(playerObj)
    end
    Events.OnPlayerUpdate.Remove(origUpdate)
    Events.OnPlayerUpdate.Add(update)
    SC.updatePlayer = update
    if type(origAlign) == "function" then
        SC.alignShotToReticle = function(playerObj, state)
            if viewOn() then return false end
            return origAlign(playerObj, state)
        end
    end
    PVADS.log("GaelGunStore: its top-down scope overlay and shot cursor warp are off while Viewpoint draws the view")
end

Events.OnGameStart.Add(wrap)
