require "VAT/VAT_Projectiles"
require "VAT/VAT_Net"
require "VAT/VAT_Launchers"

--[[
Client side of the projectile system.

  - The local player's throw is predicted immediately (it flies the moment the hand lets go) and is
    adopted when the server's "spawn" arrives. If the server clamped anything, the prediction is
    re-simulated from the server's launch and visually blended over 0.25 s instead of teleporting.
  - Everyone else's throws are mirrors created from the server's launch state and simulated with the
    same code; 2 Hz "sync" messages correct them only when the world made them diverge.
  - The server's "end" decides the outcome; world changes (explosions, fire, smoke, dropped items,
    smashed windows) arrive through vanilla synchronisation.
  - Every live projectile is drawn: inside Viewpoint's 3D scene through the Java bridge, and as an icon
    in the normal isometric view (VAT_Overlay).
In single player the server code runs in the same Lua state and owns the projectiles directly; this
module then only draws and plays sounds.
]]

VAT.Client = VAT.Client or {}
local CL = VAT.Client
local M = VAT.Projectiles
local R = VAT.Registry
local N = VAT.Net
local Log = VAT.Log
local S = VAT.S

CL.pending = CL.pending or {}             -- seq -> predicted projectile awaiting the server
CL.seq = CL.seq or (ZombRand(1000) * 1000 + 1)
CL.nextVisual = CL.nextVisual or 1
CL.BLEND = 0.25
CL.MIRROR_TIMEOUT = 6
CL.PENDING_TIMEOUT = 4
CL.MIRROR_MAX_AGE = 120           -- a mirror whose "end" never arrived is dropped after this

local function me() return getPlayer() end

local function myOnlineId()
    local p = me()
    return (p and isClient()) and p:getOnlineID() or -1
end

--- Definition for a type announced by the server. Falls back to a plain physical object when this
--- client's mods cannot classify it, so a mirror is still drawn and simulated.
local function defFor(fullType)
    local def = R.resolveType(fullType)
    if def then return def end
    Log.once("unknown:" .. tostring(fullType), "No local definition for %s; using a generic object", tostring(fullType))
    local generic = R.copy(R.MATERIALS.generic)
    generic.fullType = fullType
    generic.kind = "object"
    generic.material = "generic"
    generic.behaviors = { "inert" }
    generic.fuse = { type = "none" }
    generic.mass = 0.5
    generic.bounceMul = 1
    generic.drag = 0.015
    return generic
end

function CL.nextSeq()
    CL.seq = CL.seq + 1
    return CL.seq
end

-- ------------------------------------------------------------------ sounds (cosmetic, never networked)
CL.MATERIAL_SOUND = {
    grenade = "MetalPipeDrop", canister = "MetalPipeDrop", metal = "MetalPipeDrop",
    stone = "StoneDrop", glass = "SmashedBottleDrop", wood = "BrokenLongStickDrop",
    ball = "LandLight", generic = "LandLight",
}

function CL.playAt(sound, x, y, h, radius, volume)
    if not sound or sound == "" then return end
    local ok, err = pcall(function()
        getSoundManager():PlayWorldSoundImpl(sound, false, math.floor(x), math.floor(y), VAT.Physics.levelOf(h),
            0, radius or 12, volume or 1, false)
    end)
    if not ok then Log.once("sound:" .. sound, "Cannot play sound %s: %s", sound, tostring(err)) end
end

local function impactSound(proj, hit)
    if hit.action == "stop" then
        if proj.endReason == "break" then
            proj.breakSoundPlayed = true
            CL.playAt(proj.def.breakSound or "BreakGlassItem", hit.x, hit.y, hit.h, 20, 1)
        end
        return
    end
    if hit.normalSpeed < 1.0 then return end
    if proj.lastSoundAge and proj.age - proj.lastSoundAge < 0.12 then return end
    proj.lastSoundAge = proj.age
    local sound = proj.def.impactSound or CL.MATERIAL_SOUND[proj.def.material or "generic"]
    if proj.def.material == "soft" then return end
    local vol = VAT.clamp(hit.normalSpeed / 9, 0.25, 1)
    CL.playAt(sound, hit.x, hit.y, hit.h, 10 + math.floor(vol * 10), vol)
end

M.on("impact", function(proj, hit)
    if isServer() then return end
    impactSound(proj, hit)
end)

-- ------------------------------------------------------------------ local prediction (owner)
--- Creates the locally predicted projectile for a throw request that is about to be sent.
function CL.predict(def, launch, seq, item, player, mode)
    local proj = M.spawn(def, launch, {
        id = -seq, authority = false, predicted = true, seq = seq, mode = mode,
        fullType = item:getFullType(), ownerObj = player, ownerKey = "me", mass = R.massOf(item, def),
        createdAt = VAT.nowSeconds(),
    })
    CL.pending[seq] = proj
    return proj
end

local function sameLaunch(proj, a)
    local l = proj.launch
    if not l then return false end
    local e = 1e-4
    return math.abs(l.ox - a.x) < e and math.abs(l.oy - a.y) < e and math.abs(l.oh - a.h) < e
        and math.abs(l.vx - a.vx) < e and math.abs(l.vy - a.vy) < e and math.abs(l.vh - a.vh) < e
end

--- Replaces a projectile's simulation state with `c`, keeping the drawn position continuous.
local function blendTo(proj, c)
    local ox, oy, oh = M.renderPos(proj)
    proj.x, proj.y, proj.h = c.x, c.y, c.h
    proj.px, proj.py, proj.ph = c.x, c.y, c.h
    proj.vx, proj.vy, proj.vh = c.vx, c.vy, c.vh
    proj.phase = c.phase
    proj.bounces = c.bounces or proj.bounces
    proj.smashed = c.smashed or proj.smashed
    local dx, dy, dh = ox - c.x, oy - c.y, oh - c.h
    if dx * dx + dy * dy + dh * dh < 4 then
        proj.blend = { dx = dx, dy = dy, dh = dh, t = CL.BLEND, total = CL.BLEND }
    end
    if proj.phase == "air" or proj.phase == "roll" then
        proj.stopReason, proj.stopNotified = nil, nil
    end
end

local function state(a)
    return { x = a.x, y = a.y, h = a.h, vx = a.vx, vy = a.vy, vh = a.vh, phase = a.ph or "air" }
end

-- ------------------------------------------------------------------ client-only item copies
--[[
The server threw a different item than the one this client asked for (or carries none at all): the
client's copy has an id the server does not know, so it exists on this client only. Left in place it
would be equipped and thrown again and again, and every throw would fail the same way. It is removed
from this client's inventory only; the server inventory is the real one and is never touched here.
]]
function CL.dropGhost(itemId, fullType)
    local player = getPlayer()
    if not player or not itemId then return end
    local inv = player:getInventory()
    local item = inv and inv:getItemById(itemId)
    if not item or (fullType and item:getFullType() ~= fullType) then return end
    if player:getPrimaryHandItem() == item then player:setPrimaryHandItem(nil) end
    if player:getSecondaryHandItem() == item then player:setSecondaryHandItem(nil) end
    local container = item:getContainer() or inv
    container:Remove(item)
    Log.info("Removed client-only copy of %s (id %s): the server does not have it", item:getFullType(), tostring(itemId))
    if VAT.Controller and VAT.Controller.forgetItem then VAT.Controller.forgetItem(item) end
end

local function lastItemId(seq)
    local C = VAT.Controller
    local last = C and C.lastThrown
    if not last or last.seq ~= seq or not last.item then return nil end
    return last.item:getID()
end

-- ------------------------------------------------------------------ server messages
N.clientHandlers.spawn = function(a)
    if not isClient() then return end
    local cfg = VAT.Config.server()
    local mine = a.p == myOnlineId()
    local proj = mine and CL.pending[a.s] or nil
    if mine and a.ri and a.ci and a.ri ~= a.ci then CL.dropGhost(a.ri, a.ft) end
    if proj and not proj.removed then
        CL.pending[a.s] = nil
        M.setId(proj, a.id)
        proj.adopted = true
        if a.f then proj.fuseLeft = math.max(0.05, a.f - proj.age) end
        if not sameLaunch(proj, a) then
            local c = M.simulateCopy(proj.def, state(a), proj.steps, cfg, proj.ownerObj)
            blendTo(proj, c)
            Log.debug("Server adjusted throw %d; prediction corrected", a.id)
        end
        return
    end
    if M.get(a.id) then return end
    local def = (a.lr and VAT.Launchers.def(a.lr)) or defFor(a.ft)
    local owner = a.p and a.p >= 0 and getPlayerByOnlineID(a.p) or nil
    local mirror = M.spawn(def, { ox = a.x, oy = a.y, oh = a.h, vx = a.vx, vy = a.vy, vh = a.vh, phase = a.ph or "air" }, {
        id = a.id, authority = false, mirror = true, fullType = a.ft, mode = a.m, ownerObj = owner,
        ownerKey = "o" .. tostring(a.p), mass = a.ms or def.mass, createdAt = VAT.nowSeconds(),
    })
    if a.f then mirror.fuseLeft = a.f end
    if def.throwSound then CL.playAt(def.throwSound, a.x, a.y, a.h, 10, 0.8) end
end

N.clientHandlers.reject = function(a)
    local proj = CL.pending[a.s]
    if proj then
        CL.pending[a.s] = nil
        M.remove(proj)
    end
    Log.info("Server rejected throw seq=%s: %s%s", tostring(a.s), tostring(a.r), a.d and (" (" .. tostring(a.d) .. ")") or "")
    -- the server carries none of this item: the copy this client holds is a ghost and must not loop
    if a.r == "item" and lastItemId(a.s) then CL.dropGhost(lastItemId(a.s)) end
    if VAT.Controller and VAT.Controller.onRejected then VAT.Controller.onRejected(a) end
end

N.clientHandlers.sync = function(a)
    if not isClient() then return end
    local proj = M.get(a.id)
    if not proj or proj.authority then return end
    local cfg = VAT.Config.server()
    local behind = proj.steps - (a.k or 0)
    local c
    if behind >= 0 then
        c = M.simulateCopy(proj.def, state(a), behind, cfg, proj.ownerObj)
    else
        -- this client is behind the server: catch up from the server's state
        c = M.simulateCopy(proj.def, state(a), 0, cfg, proj.ownerObj)
        proj.steps = a.k
    end
    local dx, dy, dh = c.x - proj.x, c.y - proj.y, c.h - proj.h
    if dx * dx + dy * dy + dh * dh > 0.0064 or c.phase ~= proj.phase then
        blendTo(proj, c)
        Log.debug("Correction for %d: %.3f m", a.id, math.sqrt(dx * dx + dy * dy + dh * dh))
    end
end

N.clientHandlers["end"] = function(a)
    if not isClient() then
        -- single player: the authority already finished; only the cosmetic part is left
        return
    end
    local proj = M.get(a.id)
    if not proj then return end
    proj.x, proj.y, proj.h = a.x or proj.x, a.y or proj.y, a.h or proj.h
    if a.r == "break" and not proj.breakSoundPlayed then
        CL.playAt(proj.def.breakSound or "BreakGlassItem", proj.x, proj.y, proj.h, 20, 1)
    end
    VAT.Behaviors.cosmetic(proj, a.r)
    if a.r == "detonate" then VAT.emit("detonation", proj) end
    VAT.emit("landing", proj, a.r)
    M.remove(proj)
end

local function onServerCommand(module, command, args)
    if module ~= VAT.NET then return end
    local h = N.clientHandlers[command]
    if not h then return end
    local ok, err = pcall(h, args or {})
    if not ok then Log.warn("Server command %s failed: %s", tostring(command), tostring(err)) end
end

-- ------------------------------------------------------------------ drawing
M.on("removed", function(proj)
    if proj.visualId and VAT_removeVisual then VAT_removeVisual(proj.visualId) end
end)

M.on("stopped", function(proj, reason)
    if proj.authority then return end
    -- a mirror or prediction reached its own end: hide what is gone, keep resting objects drawn
    -- until the server's "end" (a timed grenade keeps lying there until it goes off)
    proj.localEnd = reason
    proj.localEndAt = VAT.nowSeconds()
end)

local function hidden(proj)
    if proj.phase == "done" then return true end
    if proj.localEnd == "detonate" or proj.localEnd == "break" then return true end
    return false
end

local function pushVisuals(dt)
    if not VAT_setVisual then return end
    local list = M.list
    for i = 1, #list do
        local proj = list[i]
        if proj.blend and proj.blend.t > 0 then proj.blend.t = math.max(0, proj.blend.t - dt) end
        if not proj.visualId then
            proj.visualId = CL.nextVisual
            CL.nextVisual = CL.nextVisual + 1
        end
        if hidden(proj) then
            VAT_removeVisual(proj.visualId)
        else
            local x, y, h = M.renderPos(proj)
            local yaw = proj.yawDeg or 0
            if proj.phase == "air" or proj.phase == "roll" then
                local hs = proj.vx * proj.vx + proj.vy * proj.vy
                if hs > 0.04 then yaw = math.atan2(proj.vy, proj.vx) * 180 / math.pi; proj.yawDeg = yaw end
            end
            local spin = proj.spinDeg or 0
            local pitch = (proj.phase == "roll") and 0 or spin
            if proj.def.noseForward then
                local hv = math.sqrt(proj.vx * proj.vx + proj.vy * proj.vy)
                pitch = (hv > 1e-4 or math.abs(proj.vh) > 1e-4) and -math.deg(math.atan2(proj.vh, hv)) or 0
            end
            local roll = (proj.phase == "roll") and spin or 0
            if proj.phase == "rest" then pitch, roll = 90, 0 end
            VAT_setVisual(proj.visualId, proj.fullType or proj.def.fullType, x, y, h / S, yaw, pitch, roll)
        end
    end
end

local function expire(now)
    for seq, proj in pairs(CL.pending) do
        if proj.removed or now - (proj.createdAt or now) > CL.PENDING_TIMEOUT then
            CL.pending[seq] = nil
            if not proj.removed and not proj.adopted then
                Log.warn("No server answer for throw seq=%s; prediction dropped", tostring(seq))
                M.remove(proj)
            end
        end
    end
    for i = #M.list, 1, -1 do
        local proj = M.list[i]
        if proj and not proj.authority and proj.localEndAt and now - proj.localEndAt > CL.MIRROR_TIMEOUT then
            M.remove(proj)
        elseif proj and not proj.authority and proj.createdAt and now - proj.createdAt > CL.MIRROR_MAX_AGE then
            Log.debug("Mirror %s outlived its server (%.0f s); dropped", tostring(proj.id), now - proj.createdAt)
            M.remove(proj)
        end
    end
end

local lastFrame
local function onTick()
    local now = VAT.nowSeconds()
    local dt = lastFrame and math.min(0.25, now - lastFrame) or 0
    lastFrame = now
    if isClient() then
        if #M.list > 0 then M.update(now) else M.lastTime = nil end
        expire(now)
    end
    pushVisuals(dt)
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnGameStart.Add(function()
    VAT.bindJava()
    if VAT_clearVisuals then VAT_clearVisuals() end
    Log.info("Viewpoint Advanced Throwables %s (java %s, viewpoint bridge %s)", VAT.VERSION,
        VAT_javaVersion and VAT_javaVersion() or "missing", tostring(VAT_viewpointReady and VAT_viewpointReady()))
end)
