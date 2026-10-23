require "VAT/VAT_Core"

--[[
Transport. Multiplayer uses sendClientCommand / sendServerCommand on module VAT.NET.
Single player has no network: the same handlers are called directly, so SP and MP run one code path.

Message summary (all small tables of numbers and short strings):
  client -> server  "throw"   { s seq, i itemId, ft fullType, m mode, c charge, ox oy oh, vx vy vh,
                                k cookedSeconds, px py ph thrower velocity }
  client -> server  "launch"  { s seq, w gunId, r round, ox oy oh muzzle, vx vy vh }  (VAT_Launchers)
  server -> clients "spawn"   { id, s seq, p ownerOnlineId, ft, x y h vx vy vh, ph phase, f fuseLeft, m mode, ms mass,
                                lr launched round (its definition comes from VAT_Launchers) }
  server -> owner   "reject"  { s seq, r reason }
  server -> clients "sync"    { id, k steps, x y h vx vy vh, ph phase }      (2 Hz while moving)
  server -> clients "end"     { id, r reason, x y h, w smashedWindow? }
Nothing is sent per frame; motion is reproduced from the launch state by the shared simulation.
]]

VAT.Net = VAT.Net or {}
local N = VAT.Net
N.serverHandlers = N.serverHandlers or {}
N.clientHandlers = N.clientHandlers or {}

function N.isMP() return isClient() or isServer() end

--- Client -> server.
function N.toServer(player, command, args)
    if isClient() then
        sendClientCommand(player, VAT.NET, command, args)
    else
        local h = N.serverHandlers[command]
        if h then h(player, args) end
    end
end

--- Server -> every client (in SP: the local client handler).
function N.toAll(command, args)
    if isServer() then
        sendServerCommand(VAT.NET, command, args)
    elseif not isClient() then
        local h = N.clientHandlers[command]
        if h then h(args) end
    end
end

--- Server -> one client.
function N.toOne(player, command, args)
    if isServer() then
        sendServerCommand(player, VAT.NET, command, args)
    elseif not isClient() then
        local h = N.clientHandlers[command]
        if h then h(args) end
    end
end

function N.round(v, q)
    q = q or 1000
    return math.floor(v * q + 0.5) / q
end
