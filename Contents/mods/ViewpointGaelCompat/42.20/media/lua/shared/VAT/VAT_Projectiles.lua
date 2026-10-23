require "VAT/VAT_Solver"

--[[
Projectile manager shared by the server (authoritative projectiles) and clients (the local player's
predicted throw and mirrors of everyone else's). Fixed-step accumulator: every projectile advances
in whole VAT.DT steps no matter the frame rate, so a mirror that started from the same launch state
follows the same path as the server.

Hooks (VAT_Server and VAT_Client each add theirs with M.on; in single player both are active):
  "impact"    (proj, hit)     every impact event (sounds, damage, distraction, window smash)
  "stopped"   (proj, reason)  the simulation decided the object is finished (stop, rest, fuse)
  "afterStep" ()              after every fixed step of all projectiles
  "removed"   (proj)          a projectile left the manager
Resting objects are not stepped; only their fuse is counted down.
]]

VAT.Projectiles = VAT.Projectiles or {}
local M = VAT.Projectiles
local P = VAT.Physics
local B = VAT.Behaviors
local Log = VAT.Log

M.list = M.list or {}               -- array of live projectiles
M.byId = M.byId or {}
M.acc = 0
M.lastTime = nil
M.alpha = 0                         -- render interpolation factor between the last two steps
M.MAX_CATCHUP = 10                  -- steps per frame at most (a long hitch does not freeze the game)
M.GLOBAL_LIMIT = 96

P.decide = B.decide

M.hooks = M.hooks or { impact = {}, stopped = {}, afterStep = {}, removed = {} }

function M.on(kind, fn)
    local list = M.hooks[kind]
    if list and type(fn) == "function" then list[#list + 1] = fn end
end

local function fire(kind, a, b)
    local list = M.hooks[kind]
    for i = 1, #list do
        local ok, err = pcall(list[i], a, b)
        if not ok then Log.once("hook:" .. kind .. i, "%s handler failed: %s", kind, tostring(err)) end
    end
end
M.fire = fire

function M.add(proj)
    if #M.list >= M.GLOBAL_LIMIT then
        Log.once("global-limit", "Too many live throwables (%d); oldest is finished early", M.GLOBAL_LIMIT)
        local oldest = M.list[1]
        if oldest.authority and not oldest.stopNotified then
            -- finish it through the normal path so its item lands / its charge goes off
            oldest.stopReason = "expire"
            oldest.stopNotified = true
            fire("stopped", oldest, "expire")
        end
        if not oldest.removed then M.remove(oldest) end
    end
    M.list[#M.list + 1] = proj
    if proj.id ~= nil then M.byId[proj.id] = proj end
    return proj
end

function M.setId(proj, id)
    if proj.id ~= nil and M.byId[proj.id] == proj then M.byId[proj.id] = nil end
    proj.id = id
    M.byId[id] = proj
end

function M.remove(proj)
    if not proj then return end
    for i = #M.list, 1, -1 do
        if M.list[i] == proj then table.remove(M.list, i) end
    end
    if proj.id ~= nil and M.byId[proj.id] == proj then M.byId[proj.id] = nil end
    proj.removed = true
    fire("removed", proj)
end

function M.get(id) return M.byId[id] end

function M.countForOwner(ownerKey)
    local n = 0
    for i = 1, #M.list do if M.list[i].ownerKey == ownerKey then n = n + 1 end end
    return n
end

--- Creates a projectile from a launch table and a definition.
function M.spawn(def, launch, opts)
    local proj = P.new(def, launch.ox, launch.oy, launch.oh, launch.vx, launch.vy, launch.vh, launch.phase)
    opts = opts or {}
    for k, v in pairs(opts) do proj[k] = v end
    proj.cfg = VAT.Config.server()
    if def.fuse and def.fuse.type == "timed" then
        proj.fuseLeft = math.max(0.05, (def.fuse.seconds or 3) - (opts.cooked or 0))
    end
    proj.yawDeg = math.atan2(launch.vy, launch.vx) * 180 / math.pi
    proj.spinDeg = 0
    proj.launch = { ox = launch.ox, oy = launch.oy, oh = launch.oh, vx = launch.vx, vy = launch.vy, vh = launch.vh, phase = launch.phase }
    M.add(proj)
    VAT.emit("throw", proj)
    return proj
end

--- One fixed step of one projectile, including fuse and event dispatch.
function M.stepOne(proj, cfg)
    proj.cfg = cfg
    if proj.phase == "air" or proj.phase == "roll" then
        P.step(proj, cfg)
        proj.spinDeg = (proj.spinDeg + (proj.def.spin or 6) * 57.3 * VAT.DT *
            math.min(1, math.sqrt(proj.vx * proj.vx + proj.vy * proj.vy + proj.vh * proj.vh) / 6)) % 360
    else
        proj.px, proj.py, proj.ph = proj.x, proj.y, proj.h
        proj.age = proj.age + VAT.DT
        proj.steps = proj.steps + 1
    end
    local events = proj.events
    if #events > 0 then
        proj.events = {}
        for i = 1, #events do
            local ev = events[i]
            if ev.type == "impact" then
                VAT.emit("impact", proj, ev.hit)
                fire("impact", proj, ev.hit)
            elseif ev.type == "rest" then
                proj.restYaw = proj.yawDeg
                VAT.emit("rest", proj)
                local reason = B.onRest(proj)
                -- no behaviour claimed the landing and nothing is counting down: it simply lies there
                if reason == nil and not proj.fuseLeft then reason = "drop" end
                if reason and not proj.stopReason then proj.stopReason = reason end
            end
        end
    end
    if proj.phase == "done" and not proj.stopReason then
        proj.stopReason = proj.endReason or "stop"
    end
    if proj.fuseLeft and not proj.stopReason then
        proj.fuseLeft = proj.fuseLeft - VAT.DT
        if proj.fuseLeft <= 0 then
            proj.stopReason = B.onFuse(proj)
            proj.phase = "done"
        end
    end
    if proj.stopReason and not proj.stopNotified then
        proj.stopNotified = true
        fire("stopped", proj, proj.stopReason)
    end
end

--- Advances every live projectile by whole fixed steps for the real time that passed.
function M.update(now)
    if M.lastTime == nil then M.lastTime = now end
    local dt = now - M.lastTime
    M.lastTime = now
    if dt < 0 or dt > 1 then dt = VAT.DT end
    M.acc = M.acc + dt
    local cfg = VAT.Config.server()
    local steps = 0
    while M.acc >= VAT.DT and steps < M.MAX_CATCHUP do
        M.acc = M.acc - VAT.DT
        steps = steps + 1
        for i = #M.list, 1, -1 do
            local proj = M.list[i]
            if proj and not proj.removed and not proj.frozen then M.stepOne(proj, cfg) end
        end
        fire("afterStep")
    end
    if steps >= M.MAX_CATCHUP then M.acc = 0 end
    M.alpha = VAT.clamp(M.acc / VAT.DT, 0, 1)
end

--- Fast-forwards a copy of a launch state by n steps (corrections and adoption of server state).
function M.simulateCopy(def, st, n, cfg, ownerObj)
    local proj = P.new(def, st.x, st.y, st.h, st.vx, st.vy, st.vh, st.phase)
    proj.ownerObj = ownerObj
    proj.cfg = cfg
    proj.predicting = true
    proj.age = st.age or 0
    for i = 1, n do
        if not P.step(proj, cfg) then break end
        proj.events = {}
    end
    return proj
end

--- Interpolated render position.
function M.renderPos(proj)
    local a = M.alpha
    local x = proj.px + (proj.x - proj.px) * a
    local y = proj.py + (proj.y - proj.py) * a
    local h = proj.ph + (proj.h - proj.ph) * a
    if proj.blend and proj.blend.t > 0 then
        local k = proj.blend.t / proj.blend.total
        x, y, h = x + proj.blend.dx * k, y + proj.blend.dy * k, h + proj.blend.dh * k
    end
    return x, y, h
end
