require "VAT/VAT_World"
require "VAT/VAT_Config"

--[[
Lightweight deterministic projectile simulation (no rigid bodies).

State per projectile: position (x, y, h), velocity (vx, vy, vh), phase "air" | "roll" | "rest" | "done".
One call to P.step advances exactly VAT.DT seconds:

  air   gravity + linear drag, then the displacement is swept in substeps no longer than
        VAT.MAX_SUBSTEP against edges (walls, windows, doors, fences), floors and ceilings,
        furniture/trees, characters and vehicles. The earliest contact wins (no tunnelling).
  roll  the object follows the floor (stairs included), loses speed to rolling resistance, still
        collides with edges, furniture, characters and vehicles, and falls off ledges.
  rest  not stepped at all (only a fuse may still be counting), so idle objects cost nothing.

Impacts are reported as events in proj.events; what an impact *means* (bounce, detonate, break,
smash a window) is decided by the definition's behaviours through P.decide, which the projectile
manager wires to VAT_Behaviors. Server and clients run this same code on the same launch state.
]]

VAT.Physics = VAT.Physics or {}
local P = VAT.Physics
local W = VAT.World
local S = VAT.S
local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max

P.SETTLE_SPEED = 1.1        -- below this normal speed a floor contact stops bouncing
P.MAX_ROLL_SPEED = 4.5      -- an object that starts rolling after a landing keeps at most this speed
P.STOP_SPEED = 0.18         -- rolling objects below this speed come to rest
P.MAX_BOUNCES = 14
P.MAX_AGE = 30              -- seconds in motion before the object is forced to rest
P.OWNER_GRACE = 0.30        -- seconds during which the thrower's own body is ignored
P.WINDOW_BREAK_SPEED = 5.0
P.SKIN = 0.012              -- distance kept from a surface after a contact

-- per-surface restitution scale (multiplies the object's own bounce)
P.SURFACE_BOUNCE = {
    floor = 1.0, wall = 0.85, glass = 0.55, wood = 0.7, body = 0.25, vehicle = 0.6, tree = 0.6,
    furniture = 0.75, ceiling = 0.8,
}

--- Default impact decision, replaced by the projectile manager with VAT.Behaviors.decide.
P.decide = P.decide or function(proj, hit) return "bounce" end

function P.levelOf(h)
    return floor((h + 0.0001) / S)
end

-- ------------------------------------------------------------------ construction
--- Creates simulation state. `def` is a resolved registry definition.
function P.new(def, x, y, h, vx, vy, vh, phase)
    return {
        def = def,
        x = x, y = y, h = h, vx = vx, vy = vy, vh = vh,
        px = x, py = y, ph = h,                 -- previous step position (render interpolation)
        phase = phase or "air",
        age = 0, steps = 0, bounces = 0,
        events = {},
        smashed = {},                           -- windows this object has broken through
        mass = def.mass or 0.5,
    }
end

function P.copyState(p)
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    c.events = {}
    local sm = {}
    for k, v in pairs(p.smashed or {}) do sm[k] = v end
    c.smashed = sm
    return c
end

local function event(proj, ev)
    local e = proj.events
    e[#e + 1] = ev
end

-- ------------------------------------------------------------------ swept tests
-- Each test returns the parameter t in [0,1] along the segment p -> q and fills `best` when it is
-- earlier than the best contact found so far.

local best = {}
local function consider(t, kind, nx, ny, nh, info)
    if t < 0 or t > 1 then return end
    if best.t ~= nil and t >= best.t then return end
    best.t, best.kind, best.nx, best.ny, best.nh, best.info = t, kind, nx, ny, nh, info
end

local function edgeKey(ix, iy, jx, jy, L)
    if jx < ix or jy < iy then ix, iy, jx, jy = jx, jy, ix, iy end
    return ix .. "," .. iy .. ">" .. jx .. "," .. jy .. "@" .. L
end

local function sweepEdges(proj, x0, y0, h0, x1, y1, h1, liftOverride)
    local ix0, ix1 = floor(x0), floor(x1)
    if ix0 ~= ix1 then
        local bx = (x1 > x0) and ix1 or ix0
        local t = (bx - x0) / (x1 - x0)
        local yc = y0 + t * (y1 - y0)
        local hc = h0 + t * (h1 - h0)
        local L = P.levelOf(hc)
        local lh = liftOverride or (hc - L * S)
        local iy = floor(yc)
        local key = edgeKey(ix0, iy, ix1, iy, L)
        if not proj.smashed[key] then
            local hit = W.edge(ix0, iy, ix1, iy, L, lh)
            if hit then
                hit.key = key
                consider(t, "edge", (x1 > x0) and -1 or 1, 0, 0, hit)
            end
        end
    end
    local iy0, iy1 = floor(y0), floor(y1)
    if iy0 ~= iy1 then
        local by = (y1 > y0) and iy1 or iy0
        local t = (by - y0) / (y1 - y0)
        local xc = x0 + t * (x1 - x0)
        local hc = h0 + t * (h1 - h0)
        local L = P.levelOf(hc)
        local lh = liftOverride or (hc - L * S)
        local ix = floor(xc)
        local key = edgeKey(ix, iy0, ix, iy1, L)
        if not proj.smashed[key] then
            local hit = W.edge(ix, iy0, ix, iy1, L, lh)
            if hit then
                hit.key = key
                consider(t, "edge", 0, (y1 > y0) and -1 or 1, 0, hit)
            end
        end
    end
end

local function sweepFloors(x0, y0, h0, x1, y1, h1)
    local L0 = P.levelOf(h0)
    if h1 < h0 then
        local s = W.surface(x1, y1, L0)
        if s ~= nil and h1 <= s then
            local t = (h0 >= s) and (h0 - s) / (h0 - h1) or 0
            consider(t, "floor", 0, 0, 1, { surface = s, material = "floor" })
            return
        end
        local L1 = P.levelOf(h1)
        if L1 < L0 then
            local s1 = W.surface(x1, y1, L1)
            if s1 ~= nil and h1 <= s1 then
                consider((h0 - s1) / (h0 - h1), "floor", 0, 0, 1, { surface = s1, material = "floor" })
            end
        end
    elseif h1 > h0 then
        local top = (L0 + 1) * S
        if h1 >= top and h0 < top and W.ceiling(x1, y1, L0) then
            consider((top - h0) / (h1 - h0), "ceiling", 0, 0, -1, { material = "ceiling" })
        end
    end
end

-- Segment against an axis-aligned box (slab method). Only entries from outside count.
local function segBox(x0, y0, h0, dx, dy, dh, bx0, by0, bh0, bx1, by1, bh1)
    if x0 > bx0 and x0 < bx1 and y0 > by0 and y0 < by1 and h0 > bh0 and h0 < bh1 then return nil end
    local tmin, tmax = 0, 1
    local nx, ny, nh = 0, 0, 0
    local function slab(o, d, lo, hi, ax)
        if abs(d) < 1e-9 then
            if o < lo or o > hi then return false end
            return true
        end
        local t1, t2 = (lo - o) / d, (hi - o) / d
        local sign = -1
        if t1 > t2 then t1, t2 = t2, t1; sign = 1 end
        if t1 > tmin then
            tmin = t1
            nx, ny, nh = 0, 0, 0
            if ax == 1 then nx = sign elseif ax == 2 then ny = sign else nh = sign end
        end
        if t2 < tmax then tmax = t2 end
        return tmin <= tmax
    end
    if not slab(x0, dx, bx0, bx1, 1) then return nil end
    if not slab(y0, dy, by0, by1, 2) then return nil end
    if not slab(h0, dh, bh0, bh1, 3) then return nil end
    if nx == 0 and ny == 0 and nh == 0 then return nil end
    return tmin, nx, ny, nh
end

-- First t at which a 2D segment comes within radius r of a centre (entries only).
local function segCircle(x0, y0, dx, dy, cx, cy, r)
    local fx, fy = x0 - cx, y0 - cy
    local c = fx * fx + fy * fy - r * r
    if c <= 0 then return nil end
    local a = dx * dx + dy * dy
    if a < 1e-12 then return nil end
    local b = 2 * (fx * dx + fy * dy)
    local disc = b * b - 4 * a * c
    if disc < 0 then return nil end
    local t = (-b - sqrt(disc)) / (2 * a)
    if t < 0 or t > 1 then return nil end
    return t
end

local function sweepSolids(proj, x0, y0, h0, x1, y1, h1)
    local L = P.levelOf(h1)
    local ix, iy = floor(x1), floor(y1)
    local sol = W.solid(ix, iy, L)
    if not sol then return end
    local base = L * S
    local dx, dy, dh = x1 - x0, y1 - y0, h1 - h0
    local r = proj.def.radius or 0.05
    if sol.tree then
        local t = segCircle(x0, y0, dx, dy, ix + 0.5, iy + 0.5, sol.radius + r)
        if t then
            local hc = h0 + t * dh
            if hc >= base and hc <= base + sol.top then
                local px, py = x0 + t * dx - (ix + 0.5), y0 + t * dy - (iy + 0.5)
                local l = sqrt(px * px + py * py)
                if l > 1e-6 then consider(t, "tree", px / l, py / l, 0, sol) end
            end
        end
        return
    end
    local inset = (sol.inset or 0) - r
    local t, nx, ny, nh = segBox(x0, y0, h0, dx, dy, dh,
        ix + inset, iy + inset, base - 1, ix + 1 - inset, iy + 1 - inset, base + sol.top + r)
    if t then consider(t, sol.kind == "furniture" and "furniture" or "solid", nx, ny, nh, sol) end
end

local bodyBuf, vehBuf = {}, {}

local function sweepBodies(proj, x0, y0, h0, x1, y1, h1, nb)
    local dx, dy, dh = x1 - x0, y1 - y0, h1 - h0
    local r = proj.def.radius or 0.05
    for i = 1, nb do
        local b = bodyBuf[i]
        local skip = proj.ownerObj ~= nil and b.obj == proj.ownerObj and proj.age < P.OWNER_GRACE
        if not skip and proj.ignoreBody ~= b.obj then
            local t = segCircle(x0, y0, dx, dy, b.x, b.y, b.r + r)
            if t then
                local hc = h0 + t * dh
                if hc >= b.base and hc <= b.top then
                    local px, py = x0 + t * dx - b.x, y0 + t * dy - b.y
                    local l = sqrt(px * px + py * py)
                    if l < 1e-6 then px, py, l = -dx, -dy, sqrt(dx * dx + dy * dy) end
                    if l > 1e-9 then consider(t, "body", px / l, py / l, 0, b) end
                end
            end
        end
    end
end

local function sweepVehicles(proj, x0, y0, h0, x1, y1, h1, nv)
    local dx, dy, dh = x1 - x0, y1 - y0, h1 - h0
    local r = proj.def.radius or 0.05
    for i = 1, nv do
        local v = vehBuf[i]
        -- into the vehicle's frame: u = width axis, w = length axis
        local ox, oy = x0 - v.cx, y0 - v.cy
        local lu, lw = ox * v.ux + oy * v.uy, ox * v.wx + oy * v.wy
        local du, dw = dx * v.ux + dy * v.uy, dx * v.wx + dy * v.wy
        local t, nu, nw, nh = segBox(lu, lw, h0, du, dw, dh,
            -v.hw - r, -v.hl - r, v.base, v.hw + r, v.hl + r, v.top + r)
        if t then
            local nx = nu * v.ux + nw * v.wx
            local ny = nu * v.uy + nw * v.wy
            consider(t, "vehicle", nx, ny, nh, v)
        end
    end
end

-- ------------------------------------------------------------------ responses
local function reflect(proj, nx, ny, nh, e, friction)
    local vx, vy, vh = proj.vx, proj.vy, proj.vh
    local vn = vx * nx + vy * ny + vh * nh
    if vn >= 0 then return 0 end
    local tx, ty, th = vx - vn * nx, vy - vn * ny, vh - vn * nh
    local keep = 1 - VAT.clamp(friction, 0, 0.95)
    proj.vx = tx * keep - e * vn * nx
    proj.vy = ty * keep - e * vn * ny
    proj.vh = th * keep - e * vn * nh
    return -vn
end

--- Applies the earliest contact found in `best` to the projectile at segment p -> q.
--- Returns true when the step must end here.
local function respond(proj, x0, y0, h0, x1, y1, h1, cfg)
    local t = best.t
    local cx, cy, ch = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, h0 + (h1 - h0) * t
    local nx, ny, nh = best.nx, best.ny, best.nh
    local vn = proj.vx * nx + proj.vy * ny + proj.vh * nh
    if vn >= 0 then
        -- grazing or moving away from the surface: no impact, just do not cross it
        proj.x, proj.y, proj.h = cx + nx * P.SKIN, cy + ny * P.SKIN, ch + nh * P.SKIN
        return false
    end
    local speed = sqrt(proj.vx * proj.vx + proj.vy * proj.vy + proj.vh * proj.vh)
    -- copy the contact before any behaviour runs: a hook may run physics (a preview) and reuse `best`
    local bestKind = best.kind
    local info = best.info or {}
    local hit = {
        kind = bestKind == "edge" and (info.kind or "wall") or bestKind,
        material = info.material, info = info,
        x = cx, y = cy, h = ch, nx = nx, ny = ny, nh = nh,
        speed = speed, normalSpeed = -vn, body = (bestKind == "body") and info or nil,
        vehicle = (bestKind == "vehicle") and info.obj or nil,
    }
    local action, reason = P.decide(proj, hit)
    hit.action = action
    event(proj, { type = "impact", hit = hit })

    if action == "pass" then
        -- broke through (a window): keep flying, slowed down
        if info.key then proj.smashed[info.key] = true end
        proj.vx, proj.vy, proj.vh = proj.vx * 0.65, proj.vy * 0.65, proj.vh * 0.65
        proj.x, proj.y, proj.h = cx, cy, ch
        return true
    end
    proj.x, proj.y, proj.h = cx + nx * P.SKIN, cy + ny * P.SKIN, ch + nh * P.SKIN
    if action == "stop" then
        proj.vx, proj.vy, proj.vh = 0, 0, 0
        proj.phase = "done"
        proj.endReason = reason or "stop"
        proj.endHit = hit
        return true
    end

    local def = proj.def
    local surf = (bestKind == "floor") and "floor" or (info.material == "glass" and "glass")
        or (bestKind == "body" and "body") or (bestKind == "vehicle" and "vehicle")
        or (bestKind == "tree" and "tree") or (bestKind == "furniture" and "furniture")
        or (bestKind == "ceiling" and "ceiling") or (info.material == "wood" and "wood") or "wall"
    local e = VAT.clamp((def.bounce or 0.3) * (def.bounceMul or 1) * (P.SURFACE_BOUNCE[surf] or 0.8), 0, 0.95)
    local fr = (def.friction or 0.4) * (nh > 0.7 and 1 or 0.5)
    reflect(proj, nx, ny, nh, e, fr)
    proj.bounces = proj.bounces + 1

    if nh > 0.7 then
        local up = proj.vh
        local hs = sqrt(proj.vx * proj.vx + proj.vy * proj.vy)
        if up < P.SETTLE_SPEED or proj.bounces >= P.MAX_BOUNCES then
            proj.vh = 0
            proj.h = info.surface or proj.h
            if def.canRoll and hs > P.STOP_SPEED * 2 then
                if hs > P.MAX_ROLL_SPEED then
                    local k = P.MAX_ROLL_SPEED / hs
                    proj.vx, proj.vy = proj.vx * k, proj.vy * k
                end
                proj.phase = "roll"
                event(proj, { type = "roll" })
            else
                proj.vx, proj.vy = 0, 0
                proj.phase = "rest"
                event(proj, { type = "rest" })
            end
        end
    elseif proj.bounces >= P.MAX_BOUNCES then
        proj.vx, proj.vy, proj.vh = 0, 0, 0
    end
    return true
end

--- Surface under a rolling object: the floor, or a furniture top it is already resting on.
function P.supportAt(proj, x, y, L, h)
    local s = W.surface(x, y, L)
    local ix, iy = floor(x), floor(y)
    local sol = W.solid(ix, iy, L)
    if sol and not sol.tree and sol.top < S then
        local inset = (sol.inset or 0)
        local fx, fy = x - ix, y - iy
        if fx > inset and fx < 1 - inset and fy > inset and fy < 1 - inset then
            local top = L * S + sol.top
            if h >= top - 0.12 and (s == nil or top > s) then s = top end
        end
    end
    return s
end

-- ------------------------------------------------------------------ stepping
local function gather(proj, x0, y0, h0, x1, y1, h1)
    local L0, L1 = P.levelOf(min(h0, h1) - 2), P.levelOf(max(h0, h1))
    local nb = W.bodies(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), L0, L1, bodyBuf)
    local nv = 0
    if proj.def.collideVehicles ~= false then
        -- previews (100+ steps per frame) look for vehicles every 4th step over a wider box; the
        -- authoritative and mirrored simulations look every step
        if proj.predicting and proj.vehAt and proj.steps - proj.vehAt < 4 then
            nv = proj.vehN or 0
        else
            local pad = proj.predicting and 3 or 0
            nv = W.vehicles(min(x0, x1) - pad, min(y0, y1) - pad, max(x0, x1) + pad, max(y0, y1) + pad, L0, L1, vehBuf)
            if proj.predicting then proj.vehAt, proj.vehN = proj.steps, nv end
        end
    end
    return nb, nv
end

local function sweep(proj, x0, y0, h0, x1, y1, h1, nb, nv, rolling)
    best.t = nil
    sweepEdges(proj, x0, y0, h0, x1, y1, h1, rolling and 0.06 or nil)
    if not rolling then sweepFloors(x0, y0, h0, x1, y1, h1) end
    sweepSolids(proj, x0, y0, h0, x1, y1, h1)
    if nb > 0 then sweepBodies(proj, x0, y0, h0, x1, y1, h1, nb) end
    if nv > 0 then sweepVehicles(proj, x0, y0, h0, x1, y1, h1, nv) end
    return best.t ~= nil
end

local function stepAir(proj, cfg, dt)
    local def = proj.def
    local g = cfg.gravity or 9.81
    local drag = 1 - VAT.clamp((def.drag or 0.015) * dt, 0, 0.5)
    proj.vh = proj.vh - g * dt
    proj.vx, proj.vy, proj.vh = proj.vx * drag, proj.vy * drag, proj.vh * drag
    -- vegetation drags on the object
    local L = P.levelOf(proj.h)
    if proj.h - L * S < 1.6 and W.soft(floor(proj.x), floor(proj.y), L) then
        proj.vx, proj.vy, proj.vh = proj.vx * 0.86, proj.vy * 0.86, proj.vh * 0.9
    end

    local dx, dy, dh = proj.vx * dt, proj.vy * dt, proj.vh * dt
    local len = sqrt(dx * dx + dy * dy + dh * dh)
    local n = min(10, max(1, math.ceil(len / VAT.MAX_SUBSTEP)))
    local x0, y0, h0 = proj.x, proj.y, proj.h
    local nb, nv = gather(proj, x0, y0, h0, x0 + dx, y0 + dy, h0 + dh)
    for i = 1, n do
        local ax, ay, ah = proj.x, proj.y, proj.h
        local bx, by, bh = x0 + dx * i / n, y0 + dy * i / n, h0 + dh * i / n
        if sweep(proj, ax, ay, ah, bx, by, bh, nb, nv, false) then
            if respond(proj, ax, ay, ah, bx, by, bh, cfg) then return end
        else
            proj.x, proj.y, proj.h = bx, by, bh
        end
    end
end

local function stepRoll(proj, cfg, dt)
    local def = proj.def
    local g = cfg.gravity or 9.81
    local hs = sqrt(proj.vx * proj.vx + proj.vy * proj.vy)
    local dec = (def.rollResistance or 0.2) * g * dt
    if hs <= dec + P.STOP_SPEED * 0.5 then
        proj.vx, proj.vy, proj.vh = 0, 0, 0
        proj.phase = "rest"
        event(proj, { type = "rest" })
        return
    end
    local k = (hs - dec) / hs
    proj.vx, proj.vy, proj.vh = proj.vx * k, proj.vy * k, 0
    local dx, dy = proj.vx * dt, proj.vy * dt
    local len = sqrt(dx * dx + dy * dy)
    local n = min(8, max(1, math.ceil(len / VAT.MAX_SUBSTEP)))
    local x0, y0, h = proj.x, proj.y, proj.h
    local nb, nv = gather(proj, x0, y0, h, x0 + dx, y0 + dy, h)
    local L = P.levelOf(h)
    for i = 1, n do
        local ax, ay = proj.x, proj.y
        local bx, by = x0 + dx * i / n, y0 + dy * i / n
        if sweep(proj, ax, ay, h + 0.02, bx, by, h + 0.02, nb, nv, true) then
            -- rolling contacts are horizontal: never let a wall normal push it off the floor
            best.nh = 0
            local l = sqrt(best.nx * best.nx + best.ny * best.ny)
            if l < 1e-6 then best.nx, best.ny = -proj.vx, -proj.vy; l = hs end
            best.nx, best.ny = best.nx / l, best.ny / l
            respond(proj, ax, ay, h, bx, by, h, cfg)
            if proj.phase ~= "roll" then return end
            proj.h = h
            if proj.phase == "roll" and proj.bounces >= P.MAX_BOUNCES then
                proj.vx, proj.vy = 0, 0
                proj.phase = "rest"
                event(proj, { type = "rest" })
            end
            return
        end
        -- follow the ground, or the top of the furniture it is rolling on
        local s = P.supportAt(proj, bx, by, L, h)
        if s == nil or s < h - 0.12 then
            proj.x, proj.y = bx, by
            proj.phase = "air"                 -- rolled off a ledge, a table or down the stairs
            proj.vh = 0
            return
        elseif s > h + 0.12 then
            -- a step it cannot roll up: bounce back weakly
            proj.vx, proj.vy = -proj.vx * 0.3, -proj.vy * 0.3
            return
        end
        proj.x, proj.y = bx, by
        h = s
        proj.h = s
    end
end

--- Advances one fixed step. Returns false once the object no longer needs stepping.
function P.step(proj, cfg)
    if proj.phase == "rest" or proj.phase == "done" then return false end
    local dt = VAT.DT
    proj.px, proj.py, proj.ph = proj.x, proj.y, proj.h
    proj.age = proj.age + dt
    proj.steps = proj.steps + 1
    W.beginStep()
    if proj.phase == "air" then
        stepAir(proj, cfg, dt)
    elseif proj.phase == "roll" then
        stepRoll(proj, cfg, dt)
    end
    if proj.phase == "air" or proj.phase == "roll" then
        if proj.age > P.MAX_AGE or proj.h < -32 * S then
            proj.vx, proj.vy, proj.vh = 0, 0, 0
            proj.phase = "rest"
            event(proj, { type = "rest", forced = true })
        end
    end
    return proj.phase == "air" or proj.phase == "roll"
end

--- Moves a point from `from` toward `to` until the first blocking edge or solid; used to keep a
--- release point on the thrower's side of a wall they are pressed against.
function P.clearPath(def, fx, fy, fh, tx, ty, th)
    local probe = { def = def, smashed = {}, age = 1, vx = tx - fx, vy = ty - fy, vh = th - fh }
    local len = VAT.len3(tx - fx, ty - fy, th - fh)
    local n = max(1, math.ceil(len / VAT.MAX_SUBSTEP))
    local x, y, h = fx, fy, fh
    for i = 1, n do
        local bx, by, bh = fx + (tx - fx) * i / n, fy + (ty - fy) * i / n, fh + (th - fh) * i / n
        best.t = nil
        sweepEdges(probe, x, y, h, bx, by, bh, nil)
        sweepSolids(probe, x, y, h, bx, by, bh)
        if best.t then
            local t = math.max(0, best.t - 0.05)
            return x + (bx - x) * t, y + (by - y) * t, h + (bh - h) * t, true
        end
        x, y, h = bx, by, bh
    end
    return tx, ty, th, false
end
