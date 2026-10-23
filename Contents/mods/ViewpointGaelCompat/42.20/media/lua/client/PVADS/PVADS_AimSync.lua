-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
-- Project Viewpoint ADS 1.8.4: aim pitch sync.
-- The game syncs where a player faces and that they aim, but not how far up or down: everyone else saw a gun aimed
-- at the ground as aimed straight ahead. While aiming, this client sends its view pitch (whole degrees) whenever it
-- changes by 2 degrees or more, at most 10 times a second, plus a keep-alive once a second; the server relays it to
-- the players nearby (PVADS_AimSyncServer.lua) and the Java side pitches the sender's arms and gun on their screens.
if not isClient() then return end

local MODULE, COMMAND = "PVADS", "aim"
local SEND_MIN_MS, KEEPALIVE_MS, STEP_DEG = 100, 1000, 2

local S = { lastMs = 0, lastDeg = nil, lastAim = false }

local function onPlayerUpdate(pl)
    if not pl or pl ~= getSpecificPlayer(0) then return end
    if not PVADS_viewPitchDeg or not PVADS_setRemoteAim then return end
    local now = getTimestampMs()
    if now - S.lastMs < SEND_MIN_MS then return end
    local aiming = pl:isAiming() == true
    local deg = 0
    if aiming then
        local p = PVADS_viewPitchDeg()
        if type(p) == "number" then deg = math.floor(p + 0.5) end
    end
    local send = aiming ~= S.lastAim
    if not send and aiming then
        if S.lastDeg == nil or math.abs(deg - S.lastDeg) >= STEP_DEG then send = true
        elseif now - S.lastMs >= KEEPALIVE_MS then send = true end
    end
    if not send then return end
    S.lastMs, S.lastDeg, S.lastAim = now, deg, aiming
    sendClientCommand(pl, MODULE, COMMAND, { p = deg, a = aiming })
end

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= COMMAND or type(args) ~= "table" then return end
    if not PVADS_setRemoteAim then return end
    local id = tonumber(args.id)
    if not id then return end
    local me = getSpecificPlayer(0)
    if me and id == tonumber(me:getOnlineID()) then return end
    PVADS_setRemoteAim(id, tonumber(args.p) or 0, args.a == true)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnServerCommand.Add(onServerCommand)
