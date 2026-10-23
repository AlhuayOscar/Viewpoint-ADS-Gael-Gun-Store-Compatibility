-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
-- Project Viewpoint ADS 1.8.4: aim pitch sync, server side.
-- Relays each client's "aim" command (view pitch while aiming, see client/PVADS/PVADS_AimSync.lua) to the other
-- players within RANGE tiles, tagged with the sender's online id. Nothing is stored; nothing else is changed.
if not isServer() then return end

local MODULE, COMMAND = "PVADS", "aim"
local RANGE = 60

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= COMMAND or not player or type(args) ~= "table" then return end
    local out = { id = player:getOnlineID(), p = tonumber(args.p) or 0, a = args.a == true }
    local players = getOnlinePlayers()
    if not players then return end
    local px, py = player:getX(), player:getY()
    for i = 0, players:size() - 1 do
        local o = players:get(i)
        if o and o ~= player then
            local dx, dy = o:getX() - px, o:getY() - py
            if dx * dx + dy * dy <= RANGE * RANGE then
                sendServerCommand(o, MODULE, COMMAND, out)
            end
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
