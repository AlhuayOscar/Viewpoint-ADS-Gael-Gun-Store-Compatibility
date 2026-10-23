require "VAT/VAT_Physics"
require "VAT/VAT_Behaviors"

--[[
Trajectory solver: turns "where I look, how long I held, how I throw" into a launch state, and
predicts the resulting path with the real simulation (so the preview is the actual physics).

Launch velocity =
    direction  from the release point toward the point under the crosshair (camera raycast), so the
               object leaves the hand along the line of sight even though the camera is offset from
               the hand (third person over the shoulder, or the eye in first person)
  + lift       a small upward bias per throw style (an overhand throw is released slightly upward)
  * speed      lerp(MinThrowSpeed, MaxThrowSpeed, eased charge) * style * item * mass factors
  + momentum   the thrower's own velocity * MomentumInfluence
The server recomputes the maximum legal speed with the same functions (VAT.Solver.maxSpeed).
]]

VAT.Solver = VAT.Solver or {}
local V = VAT.Solver
local P = VAT.Physics
local sqrt, abs, cos, sin, atan2, min, max = math.sqrt, math.abs, math.cos, math.sin, math.atan2, math.min, math.max
local RAD = math.pi / 180

V.STYLE = {
    [VAT.MODE_OVERHAND]  = { speed = 1.00, lift = 7 * RAD,  minCharge = 0.0 },
    [VAT.MODE_UNDERHAND] = { speed = 0.55, lift = 16 * RAD, minCharge = 0.0 },
    [VAT.MODE_ROLL]      = { speed = 0.42, lift = 0,        minCharge = 0.0 },
    [VAT.MODE_DROP]      = { speed = 0.00, lift = 0,        minCharge = 0.0 },
}
V.CONVERGE_FAR = 60          -- metres along the view when the crosshair sees sky
V.CONVERGE_MIN = 1.2         -- closer aim points are pushed out to avoid throwing into your own feet
V.ROLL_HEIGHT = 0.12         -- release height above the floor for rolls

--- Eased charge curve: quick taps give a toss, the last part of the hold adds less.
function V.curve(charge)
    local c = VAT.clamp(charge or 0, 0, 1)
    return 1 - (1 - c) * (1 - c)
end

--- Lighter objects leave the hand faster, heavy ones slower (bounded so nothing becomes silly).
function V.massFactor(mass)
    local m = max(mass or 0.5, 0.1)
    return VAT.clamp((1.0 / m) ^ 0.22, 0.55, 1.3)
end

function V.speedFor(def, mode, charge, cfg, mass)
    local style = V.STYLE[mode] or V.STYLE[VAT.MODE_OVERHAND]
    local base = cfg.MinThrowSpeed + (cfg.MaxThrowSpeed - cfg.MinThrowSpeed) * V.curve(charge)
    local s = base * style.speed * (cfg.StrengthMultiplier or 1) * (def.throwMultiplier or 1) * V.massFactor(mass or def.mass)
    local cap = def.maxVelocity or (cfg.MaxThrowSpeed * 1.25)
    return min(s, cap)
end

--- Largest launch speed (before momentum) the server accepts for this item and style.
function V.maxSpeed(def, mode, cfg, mass)
    return V.speedFor(def, mode, 1, cfg, mass)
end

--- Low-arc launch angle reaching (dx horizontal, dh vertical) at speed s; nil when out of reach.
function V.arcAngle(dx, dh, s, g, high)
    if dx < 0.01 then return nil end
    local s2 = s * s
    local disc = s2 * s2 - g * (g * dx * dx + 2 * dh * s2)
    if disc < 0 then return nil end
    local r = sqrt(disc)
    local num = high and (s2 + r) or (s2 - r)
    return math.atan(num / (g * dx))
end

--[[
Computes a launch.
  a = {
    ox, oy, oh          release point (hand), metres
    fx, fy, fh          unit view direction (camera forward)
    cx, cy, ch          camera position
    tx, ty, th, hit     crosshair raycast point and whether it hit something
    yaw                 view yaw (radians) for rolls
    mode, charge, mass
    pvx, pvy, pvh       thrower velocity (m/s)
    autoArc             solve the arc onto the crosshair point when reachable
    floorH              floor height under the thrower (rolls)
  }
Returns a table { ox, oy, oh, vx, vy, vh, speed, phase }.
]]
function V.launch(def, a, cfg)
    local mode = a.mode or VAT.MODE_OVERHAND
    local style = V.STYLE[mode] or V.STYLE[VAT.MODE_OVERHAND]
    local speed = V.speedFor(def, mode, a.charge or 0, cfg, a.mass)
    local ox, oy, oh = a.ox, a.oy, a.oh
    local dx, dy, dh

    if mode == VAT.MODE_ROLL then
        local yaw = a.yaw or atan2(a.fy or 0, a.fx or 1)
        dx, dy, dh = cos(yaw), sin(yaw), 0
        oh = (a.floorH or (oh - 1.0)) + V.ROLL_HEIGHT
    elseif mode == VAT.MODE_DROP then
        dx, dy, dh = 0, 0, -1
    else
        -- convergence point: where the crosshair looks, never closer than CONVERGE_MIN to the camera
        local tx, ty, th
        if a.hit and a.tx then
            local d = VAT.len3(a.tx - a.cx, a.ty - a.cy, a.th - a.ch)
            if d >= V.CONVERGE_MIN then
                tx, ty, th = a.tx, a.ty, a.th
            else
                tx, ty, th = a.cx + a.fx * V.CONVERGE_MIN, a.cy + a.fy * V.CONVERGE_MIN, a.ch + a.fh * V.CONVERGE_MIN
            end
        else
            tx, ty, th = a.cx + a.fx * V.CONVERGE_FAR, a.cy + a.fy * V.CONVERGE_FAR, a.ch + a.fh * V.CONVERGE_FAR
        end
        dx, dy, dh = tx - ox, ty - oy, th - oh
        local l = VAT.len3(dx, dy, dh)
        if l < 1e-4 then dx, dy, dh, l = a.fx, a.fy, a.fh, 1 end
        dx, dy, dh = dx / l, dy / l, dh / l
        -- release lift: rotate the direction upward in its vertical plane
        local horiz = sqrt(dx * dx + dy * dy)
        local pitch = atan2(dh, horiz)
        local yaw = horiz > 1e-6 and atan2(dy, dx) or (a.yaw or 0)
        local lift = style.lift * (def.verticalMultiplier or 1) * (1 - VAT.clamp(pitch / (70 * RAD), 0, 1))
        pitch = pitch + lift
        if a.autoArc and a.hit and a.tx then
            local hx, hy = a.tx - ox, a.ty - oy
            local hd = sqrt(hx * hx + hy * hy)
            local ang = V.arcAngle(hd, a.th - oh, speed, cfg.gravity or 9.81, false)
            if ang then pitch = ang; yaw = atan2(hy, hx) end
        end
        pitch = VAT.clamp(pitch, -85 * RAD, 82 * RAD)
        dx, dy, dh = cos(yaw) * cos(pitch), sin(yaw) * cos(pitch), sin(pitch)
    end

    local k = cfg.MomentumInfluence or 0.6
    local vx = dx * speed + (a.pvx or 0) * k
    local vy = dy * speed + (a.pvy or 0) * k
    local vh = dh * speed + (a.pvh or 0) * k
    return {
        ox = ox, oy = oy, oh = oh, vx = vx, vy = vy, vh = vh, speed = speed,
        phase = (mode == VAT.MODE_ROLL) and "roll" or "air",
    }
end

--[[
Runs the real simulation from a launch and records the path. `points` receives { x, y, h } every
`every` steps. The returned table has the landing point (first floor/obstacle contact) and the final
resting point. Uses copies only: nothing in the world changes.
]]
function V.predict(def, launch, cfg, maxSteps, every, points, ownerObj)
    local proj = P.new(def, launch.ox, launch.oy, launch.oh, launch.vx, launch.vy, launch.vh, launch.phase)
    proj.ownerObj = ownerObj
    proj.cfg = cfg
    proj.predicting = true
    local n = 0
    local landing
    every = every or 1
    points = points or {}
    n = n + 1
    local p0 = points[n] or {}
    points[n] = p0
    p0.x, p0.y, p0.h = proj.x, proj.y, proj.h
    for i = 1, (maxSteps or 150) do
        local moving = P.step(proj, cfg)
        if not landing and #proj.events > 0 then
            for j = 1, #proj.events do
                local ev = proj.events[j]
                if ev.type == "impact" then
                    landing = { x = ev.hit.x, y = ev.hit.y, h = ev.hit.h, kind = ev.hit.kind, nh = ev.hit.nh, action = ev.hit.action }
                    break
                end
            end
        end
        proj.events = {}
        if i % every == 0 or not moving then
            n = n + 1
            local p = points[n] or {}
            points[n] = p
            p.x, p.y, p.h = proj.x, proj.y, proj.h
        end
        if not moving then break end
        if proj.def.fuse and proj.def.fuse.type == "timed" and proj.age >= (proj.def.fuse.seconds or 99) then break end
    end
    for i = n + 1, #points do points[i] = nil end
    return {
        count = n, landing = landing,
        restX = proj.x, restY = proj.y, restH = proj.h, phase = proj.phase, reason = proj.endReason,
    }
end
