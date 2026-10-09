-- Client only. Dedicated servers do not load media/lua/client.
-- Keeps Gael's recoil spread, and stops its isometric cursor alignment while Viewpoint
-- has the mouse captured. The shot then follows Viewpoint's own aim.

if isServer() and not isClient() then return end

local ZS = 2.44949
local installedCrosshair = false
local installedArchery = false
local warned = false

local function api()
    local root = rawget(_G, "ViewpointGael")
    return root and root.Aim or nil
end

local function looking()
    local aim = api()
    if not aim or not aim.looking then return false end
    local ok, on = pcall(aim.looking)
    return ok and on == true
end

local function setSuppress(on)
    local aim = api()
    if aim and aim.setSuppressPose then
        pcall(aim.setSuppressPose, on == true)
    end
end

local function centerMarker(playerObj)
    local crosshair = rawget(_G, "GGS_ScopeCrosshair")
    local panels = crosshair and crosshair.panels
    if not panels or not playerObj or not playerObj.getPlayerNum then return end
    local panel = panels[playerObj:getPlayerNum()]
    local state = panel and panel.state
    if not state then return end
    local aim = api()
    local height = panel.getHeight and panel:getHeight() or 0
    local scale = math.max(0.65, math.min(1.50,
        math.min(panel:getWidth(), height) / 1080))
    local x, y = 0, 0
    if height > 0 and aim and aim.recoilScreenX and aim.recoilScreenY then
        local okX, offsetX = pcall(aim.recoilScreenX, height)
        local okY, offsetY = pcall(aim.recoilScreenY, height)
        if okX and okY then
            x = (tonumber(offsetX) or 0) / scale
            y = (tonumber(offsetY) or 0) / scale
        end
    end
    state.aimOffsetX, state.aimOffsetY = x, y
    state.shotAimOffsetX, state.shotAimOffsetY = x, y
end

local function installCrosshair()
    if installedCrosshair then return true end
    local crosshair = rawget(_G, "GGS_ScopeCrosshair")
    local originalUpdate = crosshair and crosshair.updatePlayer
    local originalAlign = crosshair and crosshair.alignShotToReticle
    if type(originalUpdate) ~= "function" or type(originalAlign) ~= "function" then
        return false
    end

    local function wrappedUpdate(playerObj)
        local guard = looking()
        if guard then setSuppress(true) end
        local ok, err = pcall(originalUpdate, playerObj)
        if guard then
            setSuppress(false)
            centerMarker(playerObj)
        end
        if not ok then error(err) end
    end

    if Events.OnPlayerUpdate.Remove then
        Events.OnPlayerUpdate.Remove(originalUpdate)
    end
    crosshair.updatePlayer = wrappedUpdate
    Events.OnPlayerUpdate.Add(wrappedUpdate)

    crosshair.alignShotToReticle = function(playerObj, state)
        if looking() then return false end
        return originalAlign(playerObj, state)
    end

    installedCrosshair = true
    print("[ViewpointGael] firearm reticle follows the Viewpoint view")
    return true
end

local function lookDir(probe)
    local yaw = tonumber(probe.yaw and probe.yaw()) or 0
    local pitch = tonumber(probe.pitch and probe.pitch()) or 0
    local flat = math.cos(pitch)
    return math.cos(yaw) * flat, math.sin(yaw) * flat, math.sin(pitch)
end

-- The crossbow mesh and the ground under a third-person camera both sit here.
local NEAR = 2.75

local function bury(hit)
    local zombie = hit.zombie
    local tx, ty, th = hit.x, hit.y, hit.h
    if not (zombie and zombie.getX) then return tx, ty, th end
    local zx, zy = zombie:getX(), zombie:getY()
    local floorH = zombie:getZ() * ZS
    tx = hit.x + (zx - hit.x) * 0.55
    ty = hit.y + (zy - hit.y) * 0.55
    -- A graze at ankle height makes Gael's parabola meet the floor first.
    if th < floorH + 0.45 then th = floorH + 1.15 end
    return tx, ty, th
end

local function installArchery()
    if installedArchery then return true end
    local flight = rawget(_G, "GGS_ArcheryFlight")
    local original = flight and flight.resolveAim
    if type(original) ~= "function" or type(flight.sweep) ~= "function" then return false end

    function flight.resolveAim(player, range)
        local aim = original(player, range)
        local probe = api()
        if not aim or not probe or not looking() then return aim end

        local reach = tonumber(range) or 30
        if reach < 3 then reach = 3 end
        local dx, dy, dh = lookDir(probe)
        local px, py = player:getX(), player:getY()
        local ph = player:getZ() * ZS + 1.48

        local function accept(hit, source)
            if not (hit and hit.kind == "zombie") then return false end
            local tx, ty, th = bury(hit)
            aim.tx, aim.ty, aim.th = tx, ty, th
            aim.zombie, aim.zone, aim.source = hit.zombie, hit.zone, source
            return true
        end

        local function sweep(x1, y1, h1, x2, y2, h2, tip)
            return flight.sweep(x1, y1, h1, x2, y2, h2, player, tip, true, false, true)
        end

        local hx, hy, hz = probe.aimX(), probe.aimY(), probe.aimZ()
        local sx, sy, sh, along
        if tonumber(hx) and tonumber(hy) and tonumber(hz) then
            sx, sy, sh = tonumber(hx), tonumber(hy), tonumber(hz) * ZS
            along = (sx - px) * dx + (sy - py) * dy + (sh - ph) * dh
            if along < NEAR or along > reach + 3 then
                sx, sy, sh, along = nil, nil, nil, nil
            end
        end

        if sx then
            local floorH = math.floor(sh / ZS + 1e-4) * ZS
            local onFloor = (sh - floorH) < 0.35
            -- The depth point is on the camera ray. Third person is not the player's ray.
            local back = math.min(reach, along + 3.2)
            local past = onFloor and 2.5 or 0.55
            local x1, y1, h1 = sx - dx * back, sy - dy * back, sh - dh * back
            local x2, y2, h2 = sx + dx * past, sy + dy * past, sh + dh * past
            if accept(sweep(x1, y1, h1, x2, y2, h2, 0.06), "viewpoint_zombie") then return aim end
            if accept(sweep(x1, y1, h1, x2, y2, h2, 0.4), "viewpoint_near") then return aim end
            if onFloor then
                aim.tx, aim.ty, aim.th = sx, sy, floorH + 1.15
                aim.source = "viewpoint_floor"
            else
                aim.tx, aim.ty, aim.th = sx, sy, sh
                aim.source = "viewpoint_surface"
            end
            aim.zombie, aim.zone = nil, nil
            return aim
        end

        local x1, y1, h1 = px + dx * 0.45, py + dy * 0.45, ph + dh * 0.45
        local x2, y2, h2 = px + dx * reach, py + dy * reach, ph + dh * reach
        if accept(sweep(x1, y1, h1, x2, y2, h2, 0.06), "viewpoint_zombie") then return aim end
        if accept(sweep(x1, y1, h1, x2, y2, h2, 0.4), "viewpoint_near") then return aim end
        aim.tx, aim.ty, aim.th = x2, y2, h2
        aim.source = "viewpoint_ray"
        aim.zombie, aim.zone = nil, nil
        return aim
    end

    installedArchery = true
    print("[ViewpointGael] arrows follow the Viewpoint view")
    return true
end

local function install()
    if not api() then
        if not warned then
            warned = true
            print("[ViewpointGael] waiting for ViewpointGael.Aim (ZombieBuddy has not exposed the jar yet)")
        end
        return
    end
    warned = false
    installCrosshair()
    installArchery()
end

local function tick()
    install()
    if installedCrosshair and installedArchery then
        Events.OnTick.Remove(tick)
    end
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnTick.Add(tick)
