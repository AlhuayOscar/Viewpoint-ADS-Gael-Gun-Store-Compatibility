require "VAT/VAT_Client"
require "VAT/VAT_Effects"

--[[
Client side of the 3D effects.

  * Explosions, molotovs, smoke grenades, flashbangs and noise makers are shown with 3D effects drawn
    inside Viewpoint's renderer (Java: vpthrow.Fx / FxDraw). The trigger is the game's own
    OnThrowableExplode (instant explosives go off on every client too), plus the server's "fx"
    message for the ones that only go off on the server (timer, sensor, remote). The second copy of
    an effect is dropped.
  * Fires and smoke squares (IsoFire) are found and drawn by the Java side by itself: in Viewpoint the
    vanilla 2D fire and smoke sprites are never drawn, so without this a fire shows nothing.
  * A flashbang whites out the screen of a player who sees it, more the closer and the more directly
    they look at it (server option). Drawn by VAT_Overlay through VAT.FxClient.drawWhiteout.
  * Hard hits of thrown objects kick up a little dust.
]]

VAT.FxClient = VAT.FxClient or {}
local F = VAT.FxClient
local E = VAT.Effects
local N = VAT.Net
local M = VAT.Projectiles
local S = VAT.S
local Log = VAT.Log

F.recent = {}                 -- "kind@x,y,z" -> time shown (drops the second copy)
F.white = { start = -1, hold = 0, fade = 0, peak = 0 }

local function now() return VAT.nowSeconds() end

-- ------------------------------------------------------------------ settings
function F.applySettings()
    local c = VAT.Config.client
    if VAT_fxSettings then
        VAT_fxSettings(c.effects ~= false, c.fireEffects ~= false, c.effectLights ~= false, c.effectQuality or 2)
    end
end

-- ------------------------------------------------------------------ playing a description
local function dedupeKey(d)
    return tostring(d.k) .. "@" .. math.floor(d.x) .. "," .. math.floor(d.y) .. "," .. math.floor(d.z)
end

--- Where a client-simulated projectile of ours is, if one is sitting on that square (exact point).
local function ourProjectileOn(sx, sy, sz)
    local list = M.list
    for i = 1, #list do
        local p = list[i]
        if math.floor(p.x) == sx and math.floor(p.y) == sy and math.abs(p.h / S - sz) < 1.0 then
            local x, y, h = M.renderPos(p)
            return x, y, h / S
        end
    end
    return nil
end

function F.play(d)
    if type(d) ~= "table" or not d.k or not d.x then return end
    local t = now()
    local key = dedupeKey(d)
    if F.recent[key] and t - F.recent[key] < 2.0 then return end
    F.recent[key] = t
    -- forget old keys now and then
    if (F.prune or 0) < t then
        F.prune = t + 10
        for k, v in pairs(F.recent) do if t - v > 5 then F.recent[k] = nil end end
    end
    if not VAT_fx then return end
    local x, y, z = d.x, d.y, d.z
    if d.k == "explosion" then
        VAT_fx("explosion", x, y, z, d.p or 90, d.r or 7, 0, 0, 0, 0)
        if (d.fr or 0) > 0 then VAT_fx("incendiary", x, y, z, 0, d.fr, 0, 0, 0, 0) end
        if (d.sr or 0) > 0 then VAT_fx("smoke", x, y, z, 0, d.sr, d.s or 20, d.cr or 0.64, d.cg or 0.64, d.cb or 0.66) end
    elseif d.k == "incendiary" then
        VAT_fx("incendiary", x, y, z, 0, d.fr or 6, 0, 0, 0, 0)
    elseif d.k == "smoke" then
        VAT_fx("smoke", x, y, z, 0, d.sr or 5, d.s or 20, d.cr or 0.64, d.cg or 0.64, d.cb or 0.66)
    elseif d.k == "flash" then
        VAT_fx("flash", x, y, z, 0, 0, 0, 0, 0, 0)
        F.flashbang(d)
    elseif d.k == "pop" then
        VAT_fx("pop", x, y, z, 0, 0, 0, 0, 0, 0)
    end
    F.shown = F.shown or {}
    if not F.shown[d.k] then
        F.shown[d.k] = true
        Log.info("First %s effect: %s at %.2f,%.2f,%.2f", d.k, tostring(d.ft), x, y, z)
    else
        Log.debug("Effect %s at %.2f,%.2f,%.2f (%s)", d.k, x, y, z, tostring(d.ft))
    end
end

-- the game's own event: every client sees the instant explosives itself
if Events and Events.OnThrowableExplode then
    Events.OnThrowableExplode.Add(function(trap, square)
        if isServer() then return end
        local ok, d = pcall(E.fromTrap, trap, square)
        if not ok or not d then return end
        local ex, ey, ez = ourProjectileOn(square:getX(), square:getY(), square:getZ())
        if ex then d.x, d.y, d.z = ex, ey, ez end
        F.play(d)
    end)
end

-- the server's copy (timer, sensor and remote explosives, and anything this client missed)
N.clientHandlers.fx = function(a) F.play(a) end

-- ------------------------------------------------------------------ flashbang
--- How hard a flashbang at d hits the local player: 0 (unaffected) .. 1 (full whiteout).
function F.flashStrength(d, player)
    local cfg = VAT.Config.server()
    if not cfg.FlashbangBlinds then return 0 end
    if not player or player:isDead() then return 0 end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local eh = pz * S + 1.6
    local fh = (d.z or pz) * S + 0.3
    local dx, dy, dh = d.x - px, d.y - py, fh - eh
    local dist = math.sqrt(dx * dx + dy * dy + dh * dh)
    local range = cfg.FlashbangRange or 16
    if dist > range then return 0 end
    -- line of sight: the game's own visibility of the flash square (walls, doors), or very close
    local seen = dist < 2.5
    if not seen then
        local sq = getCell():getGridSquare(math.floor(d.x), math.floor(d.y), math.floor(d.z or pz))
        local ok, v = pcall(function() return sq and sq:isCouldSee(player:getPlayerNum()) end)
        seen = ok and v and true or false
    end
    -- facing: Viewpoint's camera when it drives the view, otherwise the body's facing
    local fx, fy, fhh
    local aim = F.aim or {}
    F.aim = aim
    if VAT_getAim and VAT_getAim(aim) then
        fx, fy, fhh = aim.fx, aim.fy, aim.fh
    else
        local ok, a = pcall(function() return player:getForwardDirection():getDirection() end)
        a = ok and a or 0
        fx, fy, fhh = math.cos(a), math.sin(a), 0
    end
    local l = math.max(dist, 0.001)
    local dot = (fx * dx + fy * dy + fhh * dh) / l
    local facing = 0.3 + 0.7 * VAT.clamp((dot + 0.15) / 1.15, 0, 1)
    local near = (1 - dist / range) ^ 0.7
    return VAT.clamp(near * facing * (seen and 1 or 0.12), 0, 1)
end

function F.flashbang(d)
    local player = getPlayer()
    local k = F.flashStrength(d, player)
    if k <= 0.06 then return end
    local w = F.white
    local t = now()
    -- a new flash only makes it worse, never shorter
    local remaining = 0
    if w.start >= 0 then remaining = math.max(0, w.start + w.hold + w.fade - t) end
    w.start = t
    w.peak = math.max(VAT.clamp(0.2 + 0.8 * k, 0, 1), F.whiteAlpha(t))
    w.hold = 0.25 + 2.2 * k
    w.fade = math.max(1.0 + 4.0 * k, remaining)
    Log.debug("Flashbang: strength %.2f, blind %.1f s", k, w.hold + w.fade)
end

function F.whiteAlpha(t)
    local w = F.white
    if w.start < 0 then return 0 end
    local a = t - w.start
    if a < 0 then return 0 end
    if a <= w.hold then return w.peak end
    local f = (a - w.hold) / math.max(0.01, w.fade)
    if f >= 1 then w.start = -1; return 0 end
    return w.peak * (1 - f) ^ 1.6
end

--- Called from VATOverlay:render.
function F.drawWhiteout(ui)
    local a = F.whiteAlpha(now())
    if a <= 0.003 then return end
    local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
    ui:drawRect(0, 0, w, h, a, 1, 1, 0.97)
end

-- ------------------------------------------------------------------ dust where thrown objects hit hard
M.on("impact", function(proj, hit)
    if isServer() or not VAT_fx then return end
    if hit.action == "stop" or (hit.normalSpeed or 0) < 4.5 then return end
    if proj.def and proj.def.material == "soft" then return end
    VAT_fx("dust", hit.x, hit.y, hit.h / S, VAT.clamp(hit.normalSpeed / 14, 0, 1), 0, 0, 0, 0, 0)
end)

Events.OnGameStart.Add(function()
    F.white.start = -1
    F.applySettings()
end)
