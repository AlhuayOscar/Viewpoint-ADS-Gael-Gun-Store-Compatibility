-- Client only. Dedicated servers do not load media/lua/client.
-- Keeps Gael's recoil spread, and stops its isometric cursor alignment while Viewpoint
-- has the mouse captured. The shot then follows Viewpoint's own aim.

if isServer() and not isClient() then return end

local ZS = 2.44949
local MIN_UPWARD_LAUNCHER_RANGE = 8.0 -- outside Gael's largest standalone blast radius
local installedCrosshair = false
local installedArchery = false
local installedLauncherAim = false
local installedLauncherPreview = false
local installedTracerPreview = false
local installedLauncherImpactTarget = false
local warned = false
local originalLauncherPreviewActive
local originalLauncherImpactResolver

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

-- Shared camera-ray target for Gael's projectile launchers in Viewpoint modes.
GGS_ViewpointLauncherMode = GGS_ViewpointLauncherMode or {}
function GGS_ViewpointLauncherMode.active(playerObj)
    if playerObj and playerObj.isLocalPlayer and not playerObj:isLocalPlayer() then return false end
    if looking() then return true end
    -- Third-person Viewpoint can release mouse capture while its camera is still
    -- active. The launcher profile/aiming guard is checked by the caller.
    local aim = api()
    if aim and type(aim.isThirdPerson) == "function" then
        local ok, thirdPerson = pcall(aim.isThirdPerson)
        if ok and thirdPerson == true then return true end
    end
    return false
end

function GGS_ViewpointLauncherMode.target(playerObj, maxDistance)
    if not GGS_ViewpointLauncherMode.active(playerObj) then return nil end
    local aim = api()
    if not (aim and aim.aimX and aim.aimY and aim.aimZ) then return nil end
    local sightRange = tonumber(aim.sightTargetDistance and aim.sightTargetDistance())
    local requestedRange = sightRange
    if not requestedRange or requestedRange ~= requestedRange or requestedRange == math.huge
        or requestedRange <= 2.75 then
        requestedRange = tonumber(maxDistance) or 60
    end
    requestedRange = math.max(1, requestedRange)
    local okX, hitX = pcall(aim.aimX)
    local okY, hitY = pcall(aim.aimY)
    local okZ, hitZ = pcall(aim.aimZ)
    local px, py, pz = playerObj:getX(), playerObj:getY(), playerObj:getZ()
    local dx, dy, dz
    if okX and okY and okZ and tonumber(hitX) and tonumber(hitY) and tonumber(hitZ) then
        dx, dy, dz = tonumber(hitX) - px, tonumber(hitY) - py, tonumber(hitZ) - pz
    else
        dx, dy, dz = 0, 0, 0
    end
    local distance = math.sqrt(dx * dx + dy * dy)
    -- aimX/Y/Z are the camera ray's actual MousePick hit. Keep valid close hits:
    -- replacing every hit within 2.75 tiles with the fallback range sent rockets
    -- far beyond nearby targets. Only synthesize a forward point when the ray
    -- has no usable hit (or lands on the shooter's own origin).
    local validHit = okX and okY and okZ and tonumber(hitX) and tonumber(hitY) and tonumber(hitZ)
    if not validHit or distance < 0.25 then
        local yaw = tonumber(aim.yaw and aim.yaw()) or 0
        local pitch = tonumber(aim.pitch and aim.pitch()) or 0
        local reach = requestedRange
        local flat = math.cos(pitch)
        dx, dy, dz = math.cos(yaw) * flat * reach,
            math.sin(yaw) * flat * reach, math.sin(pitch) * reach / 2.44949
        distance = math.sqrt(dx * dx + dy * dy)
        -- Gael's fire request only accepts a ground square. Looking high into
        -- empty sky makes the ray's ground projection collapse back onto the
        -- shooter, so its impact fuse can explode at the launcher's feet. Keep
        -- that fallback safely downrange; Gael still simulates the flight and
        -- resolves an earlier wall/window collision on the server.
        if pitch > 0.25 and distance < MIN_UPWARD_LAUNCHER_RANGE then
            dx, dy = math.cos(yaw) * MIN_UPWARD_LAUNCHER_RANGE,
                math.sin(yaw) * MIN_UPWARD_LAUNCHER_RANGE
            distance = MIN_UPWARD_LAUNCHER_RANGE
        end
    end
    -- In first person, preserve the real rendered Gael weapon axis (including
    -- ADS recoil/sway) and use the camera hit only to choose launch distance.
    local ax = tonumber(aim.launcherAxisX and aim.launcherAxisX())
    local ay = tonumber(aim.launcherAxisY and aim.launcherAxisY())
    local az = tonumber(aim.launcherAxisZ and aim.launcherAxisZ())
    local horizontal = ax and ay and math.sqrt(ax * ax + ay * ay) or 0
    -- Some Gael launcher models do not share the rifle sight-axis calibration.
    -- Reject an axis that points away from the selected camera target; otherwise
    -- the RPG can resolve its impact back into the shooter's own tile.
    local alignment = horizontal > 0.01 and distance > 0.01
        and (ax * dx + ay * dy) / (horizontal * distance) or -1
    if ax and ay and az and ax == ax and ay == ay and az == az
        and horizontal > 0.01 and horizontal < math.huge and alignment > 0.25 then
        dx, dy, dz = ax / horizontal * distance, ay / horizontal * distance, az / horizontal * distance
    end
    if distance <= 0.01 then return nil end
    return px + dx, py + dy, pz + dz
end

-- Gael's standalone RPG/grenade-launcher handler keeps pickTargetSquare() local,
-- and converts the pinned mouse position directly with IsoUtils.XToIso/YToIso.
-- Redirect only that exact mouse conversion while a supported launcher is aimed
-- in Viewpoint mode. Gael then sends this camera-ray point to its normal server
-- projectile simulator, which still resolves walls and the final impact square.
local realXToIso, realYToIso
local function isGaelLauncherAiming()
    local preview = rawget(_G, "GGS_StandaloneTrajectoryPreview")
    local player = getPlayer and getPlayer() or nil
    local activeFn = originalLauncherPreviewActive or (preview and preview.active)
    if not (player and type(activeFn) == "function") then return false end
    local ok, active = pcall(activeFn, player)
    return ok and active == true and GGS_ViewpointLauncherMode.active(player)
end

local function installLauncherPreview()
    if installedLauncherPreview then return true end
    local preview = rawget(_G, "GGS_StandaloneTrajectoryPreview")
    if not (preview and type(preview.active) == "function") then return false end
    originalLauncherPreviewActive = preview.active
    preview.active = function(playerObj)
        -- Hide Gael's isometric arc while Viewpoint owns aiming. The launcher
        -- still fires through Gael; only its screen-space preview is suppressed.
        if GGS_ViewpointLauncherMode.active(playerObj) then return false end
        return originalLauncherPreviewActive(playerObj)
    end
    installedLauncherPreview = true
    print("[ViewpointGael] isometric launcher preview hidden in Viewpoint modes")
    return true
end

-- Gael's shared tracer overlay has a second preview path for underbarrel
-- launchers. Hide only its predicted arc while Viewpoint owns the camera aim;
-- keep live projectile trails visible after firing.
local function installTracerPreviewFilter()
    local tracer = rawget(_G, "GGS_LauncherTracer")
    local panel = tracer and tracer.panel
    if not panel then return false end
    if panel.__viewpointPreviewFilter then
        installedTracerPreview = true
        return true
    end
    local drawPreview = panel.preview
    if type(drawPreview) ~= "function" then return false end
    panel.preview = function(self, state)
        local playerObj = getPlayer and getPlayer() or nil
        if playerObj and GGS_ViewpointLauncherMode.active(playerObj) then return end
        return drawPreview(self, state)
    end
    panel.__viewpointPreviewFilter = true
    installedTracerPreview = true
    print("[ViewpointGael] predicted launcher arc hidden in Viewpoint modes")
    return true
end

-- Gael's standalone fire callback resolves its isometric pick into the impact
-- square through this global function. Replace that input only for a local
-- Viewpoint launcher shot; Gael still resolves intervening walls and owns the
-- explosion at the resulting impact square.
local function installLauncherImpactTarget()
    if installedLauncherImpactTarget then return true end
    local resolver = rawget(_G, "ggsGLResolveImpactSquare")
    if type(resolver) ~= "function" then return false end
    originalLauncherImpactResolver = resolver
    _G.ggsGLResolveImpactSquare = function(startX, startY, startZ, targetSquare, ...)
        local playerObj = getPlayer and getPlayer() or nil
        local activeFn = originalLauncherPreviewActive
        local active = false
        if playerObj and type(activeFn) == "function" then
            local ok, result = pcall(activeFn, playerObj)
            active = ok and result == true
        end
        if active and GGS_ViewpointLauncherMode.active(playerObj) then
            local tx, ty, tz = GGS_ViewpointLauncherMode.target(playerObj, 24)
            if tx and ty then
                local dx, dy = tx - startX, ty - startY
                local distance = math.sqrt(dx * dx + dy * dy)
                local maxDistance = 24
                if distance > maxDistance then
                    local scale = maxDistance / distance
                    tx, ty = startX + dx * scale, startY + dy * scale
                end
                local cell = getCell and getCell() or nil
                local gx, gy = math.floor(tx), math.floor(ty)
                local gz = math.floor(tonumber(tz) or tonumber(startZ) or 0)
                local cameraSquare = cell and cell:getGridSquare(gx, gy, gz) or nil
                if not cameraSquare and cell then cameraSquare = cell:getGridSquare(gx, gy, 0) end
                if cameraSquare then
                    local isoX = targetSquare and targetSquare:getX() or -1
                    local isoY = targetSquare and targetSquare:getY() or -1
                    targetSquare = cameraSquare
                    print(string.format("[ViewpointGael] launcher impact target iso=%d,%d camera=%d,%d,%d range=%.2f",
                        isoX, isoY, gx, gy, gz, distance))
                else
                    print(string.format("[ViewpointGael] camera impact square missing at %d,%d,%d; retaining Gael target",
                        gx, gy, gz))
                end
            end
        end
        return originalLauncherImpactResolver(startX, startY, startZ, targetSquare, ...)
    end
    installedLauncherImpactTarget = true
    print("[ViewpointGael] standalone launcher impact uses the camera target; Gael resolves walls and detonation")
    return true
end

local function installLauncherAim()
    if installedLauncherAim then return true end
    local iso = rawget(_G, "IsoUtils")
    if not (iso and type(iso.XToIso) == "function" and type(iso.YToIso) == "function") then
        return false
    end
    realXToIso, realYToIso = iso.XToIso, iso.YToIso

    local function mousePoint(x, y, playerNum)
        if not isGaelLauncherAiming() then return nil end
        local mx, my = getMouseX and getMouseX() or nil, getMouseY and getMouseY() or nil
        if not (mx and my) then return nil end
        local player = getPlayer and getPlayer() or nil
        local pn = player and player.getPlayerNum and player:getPlayerNum() or playerNum or 0
        local core = getCore and getCore() or nil
        local zoom = core and core.getZoom and core:getZoom(pn) or 1
        zoom = tonumber(zoom) or 1
        if zoom <= 0 then zoom = 1 end
        -- Do not affect other isometric conversions (inventory/UI/world picking).
        if math.abs((tonumber(x) or 0) - mx * zoom) > 0.01
            or math.abs((tonumber(y) or 0) - my * zoom) > 0.01 then
            return nil
        end
        local tx, ty = GGS_ViewpointLauncherMode.target(player, 60)
        if tx and ty then return tx, ty end
        return nil
    end

    iso.XToIso = function(x, y, z, playerNum)
        local tx = mousePoint(x, y, playerNum)
        if tx then return tx end
        return realXToIso(x, y, z)
    end
    iso.YToIso = function(x, y, z, playerNum)
        local _, ty = mousePoint(x, y, playerNum)
        if ty then return ty end
        return realYToIso(x, y, z)
    end
    installedLauncherAim = true
    print("[ViewpointGael] standalone launchers use the Viewpoint camera-ray impact target")
    return true
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
    installLauncherAim()
    installLauncherPreview()
    installTracerPreviewFilter()
    installLauncherImpactTarget()
end

local function tick()
    install()
    if installedCrosshair and installedArchery and installedLauncherAim
        and installedLauncherPreview and installedTracerPreview and installedLauncherImpactTarget then
        Events.OnTick.Remove(tick)
    end
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnTick.Add(tick)
