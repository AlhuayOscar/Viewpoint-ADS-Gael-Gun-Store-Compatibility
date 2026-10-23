-- Viewpoint True Ballistics - server glue: answers the client handshake. "java" is only true when the
-- server itself loaded the True Ballistics jar through ZombieBuddy (the widened anti-cheat range and the
-- line-of-fire validation live there).

require "VTB/VTB_Core"

-- Bullet holes / impact debris: a client sends its own world impacts ("fx", a flat list of numbers, 13 per
-- impact); the server passes them on to the other players nearby. Pure Lua, works without the server Java
-- part. Malformed or flooding messages are dropped.
local FX_PER_IMPACT = 13
local FX_MAX_NUMBERS = 64 * FX_PER_IMPACT
local FX_RANGE = 120
local fxLast = {}

local function relayImpacts(player, args)
    local d = args and args.d
    if type(d) ~= "table" then return end
    local n = 0
    while n < FX_MAX_NUMBERS and type(d[n + 1]) == "number" do n = n + 1 end
    if n < FX_PER_IMPACT then return end
    local who = player:getUsername() or "?"
    local now = getTimestampMs()
    if fxLast[who] and now - fxLast[who] < 80 then return end -- clients send at most every 100 ms
    fxLast[who] = now
    local out = {}
    for i = 1, n - (n % FX_PER_IMPACT) do out[i] = d[i] end
    local px, py = player:getX(), player:getY()
    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local other = players:get(i)
        if other and other ~= player then
            local dx, dy = other:getX() - px, other:getY() - py
            if dx * dx + dy * dy < FX_RANGE * FX_RANGE then
                sendServerCommand(other, "VTB", "fx", { d = out })
            end
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "VTB" then return end
    if command == "fx" then relayImpacts(player, args) return end
    if command ~= "hello" then return end
    local java = TrueBallisticsJ ~= nil
    local version = ""
    if java then version = VTB_serverInfo() or "" end
    sendServerCommand(player, "VTB", "hello", { java = java, version = version })
end

Events.OnClientCommand.Add(onClientCommand)
