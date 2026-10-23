-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Options"

--[[
1.6.0 variable zoom and zeroing (client only, nothing goes over the network).

Variable zoom: high-power scopes step through magnifications with the mouse wheel (or optional keys) while you
look through them. An 8x goes 2x / 4x / 8x. The Java side eases the view between steps (ADS.magNow); the reticle
stays the same size (second focal plane), and mouse sensitivity follows the zoom as it already did.

Zeroing (DayZ style): the zeroing keys step the sight's zero range up and down while you hold a firearm. The zero is
published through the Sight API (pvads.Sight.ray, out[6]); Viewpoint True Ballistics raises the bore by the angle that
puts the round back on the sight line at that range. Without True Ballistics there is no bullet drop, so zeroing is
off (and its keys do nothing).

Levels come from the optic / weapon profile (zoomLevels / zeroLevels) or from the defaults below. The step picked is
remembered per weapon + optic for the session.
]]

local S = { zooms = nil, zeros = nil, zi = nil, ri = nil, key = nil, mem = {}, hudAt = -1e9 }
PVADS.Scope = S

S.HUD_MS = 2500

local function num(v) v = tonumber(v); if v and v == v and v > 0 and v < 1e6 then return v end end

local function cleanList(t, lo, hi)
    local out, seen = {}, {}
    if type(t) ~= "table" then return out end
    for _, v in pairs(t) do
        v = num(v)
        if v and v >= lo and v <= hi then
            local k = math.floor(v * 100 + 0.5)
            if not seen[k] then seen[k] = true; out[#out + 1] = v end
        end
    end
    table.sort(out)
    return out
end

local function round1(x) return math.floor(x * 10 + 0.5) / 10 end

--- True Ballistics is running (its Java part is loaded): only then does a zero change where bullets go.
function S.ballistics()
    if not VTB_available then return false end
    local ok, v = pcall(VTB_available)
    return ok and v == true
end

--- Magnifications for this profile, low to high (nil = fixed).
function S.zoomLevelsFor(p)
    if not p or p.mode ~= "scope" then return nil end
    local mag = num(p.mag) or 1
    if mag < 1.9 then return nil end
    if type(p.zoomLevels) == "table" then
        local l = cleanList(p.zoomLevels, 1, 25)
        if #l >= 2 then return l end
        if #l == 1 then return nil end
    end
    if not PVADS.Settings.variableZoom then return nil end
    if mag >= 5.5 then return { math.max(1.5, round1(mag / 4)), round1(mag / 2), mag } end
    if mag >= 3.5 then return { round1(mag / 2), mag } end
    return nil
end

--- Zero ranges (metres) for this profile, low to high (nil = no zeroing).
function S.zeroLevelsFor(p)
    if not p or not S.ballistics() then return nil end
    local l
    if type(p.zeroLevels) == "table" then
        l = cleanList(p.zeroLevels, 5, 1000)
    else
        local mag = num(p.mag) or 1
        if p.mode == "scope" and mag >= 1.9 then
            if mag >= 5.5 then l = { 25, 50, 100, 150, 200, 300, 400, 500 }
            elseif mag >= 3.5 then l = { 25, 50, 100, 150, 200, 300 }
            else l = { 25, 50, 100, 150, 200 } end
        elseif p.mode == "scope" or p.mode == "reflex" then
            l = { 25, 50, 100, 150 }                                -- red dots, holo sights, flip-up irons
        else
            if p.family == "pistol" or p.family == "shotgun" then return nil end   -- fixed irons
            l = { 25, 50, 100, 150, 200 }
        end
        -- the sight's own zero is always one of the steps
        local z = num(p.zero)
        if z and z >= 5 then
            local have = false
            for _, v in ipairs(l) do if math.abs(v - z) < 0.5 then have = true end end
            if not have then l[#l + 1] = z; table.sort(l) end
        end
    end
    if #l < 2 then return nil end
    return l
end

local function nearestIndex(list, v)
    local best, bd = #list, math.huge
    for i, x in ipairs(list) do
        local d = math.abs(x - v)
        if d < bd then best, bd = i, d end
    end
    return best
end

local function push(instant)
    if PVADS_setScopeMag then PVADS_setScopeMag(S.zooms and S.zooms[S.zi] or 0, instant) end
    if PVADS_setZero then PVADS_setZero(S.zeros and S.zeros[S.ri] or 0) end
end

--- New / re-resolved profile (Controller.refresh): pick the remembered or default steps and push them instantly.
function S.onProfile(p, weapon)
    if not p then S.zooms, S.zeros, S.key = nil, nil, nil; return end
    S.key = tostring(p.weaponId) .. "|" .. tostring(p.opticId or "")
    S.zooms = S.zoomLevelsFor(p)
    S.zeros = S.zeroLevelsFor(p)
    local m = S.mem[S.key] or {}
    S.zi = S.zooms and math.max(1, math.min(#S.zooms, m.zi or #S.zooms)) or nil
    S.ri = S.zeros and math.max(1, math.min(#S.zeros, m.ri or nearestIndex(S.zeros, num(p.zero) or 100))) or nil
    push(true)
end

local function remember()
    if not S.key then return end
    S.mem[S.key] = { zi = S.zi, ri = S.ri }
end

local probe = {}
--- Looking through a magnified scope right now (lens up).
local function scopeUp()
    if not PVADS_getState or not PVADS.Controller.ready then return false end
    PVADS_getState(probe)
    return probe.lensUp == true
end

local function holdingGun()
    local pl = getSpecificPlayer(0)
    return pl and not pl:isDead() and PVADS.Controller.weapon(pl) ~= nil and PVADS.Controller.profile ~= nil
end

function S.zoom(dir)
    if not S.zooms or not scopeUp() then return false end
    local i = math.max(1, math.min(#S.zooms, S.zi + dir))
    S.hudAt = getTimestampMs()
    if i == S.zi then return true end
    S.zi = i
    remember()
    if PVADS_setScopeMag then PVADS_setScopeMag(S.zooms[i], false) end
    return true
end

function S.zero(dir)
    if not S.zeros or not holdingGun() then return false end
    local i = math.max(1, math.min(#S.zeros, S.ri + dir))
    S.hudAt = getTimestampMs()
    if i == S.ri then return true end
    S.ri = i
    remember()
    if PVADS_setZero then PVADS_setZero(S.zeros[i]) end
    return true
end

--- What the readout shows: { zoom = "4x" or nil, zero = "100 m" or nil, alpha = 0..1 } or nil when hidden.
function S.hud()
    if not PVADS.Settings.scopeHud then return nil end
    local age = getTimestampMs() - S.hudAt
    if age < 0 or age > S.HUD_MS then return nil end
    if not S.zooms and not S.zeros then return nil end
    local a = math.min(1, (S.HUD_MS - age) / 500)
    local z, r
    if S.zooms then
        local m = S.zooms[S.zi]
        z = (m == math.floor(m) and string.format("%dx", m) or string.format("%.1fx", m))
    end
    if S.zeros then r = string.format("%d m", math.floor(S.zeros[S.ri] + 0.5)) end
    return { zoom = z, zero = r, alpha = a }
end

local function onKey(key)
    if not key or key == 0 or not PVADS.Controller.ready then return end
    local s = PVADS.Settings
    if PVADS.refreshKeys then PVADS.refreshKeys() end
    if key == s.zeroUpKey then S.zero(1)
    elseif key == s.zeroDownKey then S.zero(-1)
    elseif key == s.zoomInKey then S.zoom(1)
    elseif key == s.zoomOutKey then S.zoom(-1) end
end

-- zombie.ui.UIManager.update: OnMouseWheel(wheel), wheel > 0 = wheel turned up (the game zooms the map in on it).
-- Viewpoint's loot menu takes the wheel first while it shows (it clears the wheel, so this then sees 0).
local function onWheel(wheel)
    wheel = tonumber(wheel) or 0
    if wheel == 0 or not PVADS.Settings.wheelZoom then return end
    S.zoom(wheel > 0 and 1 or -1)
end

Events.OnKeyStartPressed.Add(onKey)
Events.OnMouseWheel.Add(onWheel)
