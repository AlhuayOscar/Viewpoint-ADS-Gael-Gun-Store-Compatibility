require "VAT/VAT_Registry"

--[[
What an explosion looks like (shared by the server, which tells every client, and the clients).

The game raises OnThrowableExplode(trap, square) wherever an IsoTrap goes off: on the server (and in
single player) for every explosive, and on each client too for the instant ones it receives
(AddExplosiveTrapPacket.processClient calls trap:triggerExplosion()). Timer, sensor and remote bombs
only go off on the server, so the server also sends the description to everyone ("fx"); clients drop
the second copy of an effect they already showed.

A description is a small table that crosses the network as is:
  k   kind: "explosion" | "incendiary" | "smoke" | "flash" | "pop"
  x, y, z   where (tiles, z in levels)
  p, r      explosion power and range;  fr fire range;  sr smoke range
  s         seconds the smoke keeps coming (ExplosionDuration * 2.5, see below)
  cr, cg, cb   smoke colour
  ft        the item's full type
Smoke duration: IsoTrap.updateExplosionDuration ends the trap after ExplosionDuration / 60 * (60 /
day length in minutes) game hours, and a game hour lasts day length * 60 / 24 real seconds, so the
real time is ExplosionDuration * 2.5 seconds whatever the day length (vanilla smoke bomb: 25 s).
]]

VAT.Effects = VAT.Effects or {}
local E = VAT.Effects
local R = VAT.Registry

E.FLASH_WORDS = { "flashbang", "flash bang", "flash_bang", "flash-bang", "stun grenade", "stungrenade",
    "stun_grenade", "flash grenade", "flashgrenade", "flash_grenade", "m84" }
E.SMOKE_COLOURS = {
    { "red", 0.62, 0.16, 0.13 }, { "green", 0.3, 0.58, 0.27 }, { "yellow", 0.72, 0.64, 0.2 },
    { "violet", 0.45, 0.28, 0.6 }, { "purple", 0.45, 0.28, 0.6 }, { "blue", 0.28, 0.38, 0.66 },
    { "orange", 0.75, 0.42, 0.14 }, { "black", 0.12, 0.12, 0.12 },
}
E.SMOKE_DEFAULT = { 0.64, 0.64, 0.66 }

local function lower(s) return s and string.lower(tostring(s)) or "" end

local function nameOf(item)
    local ok, n = pcall(function() return item:getDisplayName() end)
    return ok and n or ""
end

--- True when the item is a flashbang: an explicit registration (fx = "flashbang"), a "flashbang" tag,
--- or a name such as "Flashbang", "Stun Grenade" or "M84".
function E.isFlashbang(item, fullType)
    fullType = fullType or (item and item:getFullType())
    local def = fullType and R.explicit and R.explicit[fullType]
    if def and def.fx then return def.fx == "flashbang" end
    -- tags as text (B42's InventoryItem.hasTag takes an ItemTag, not a string, so it is not used)
    local text = lower(fullType) .. " " .. lower(item and nameOf(item)) .. " " .. (item and R.tagString and R.tagString(item) or "")
    for i = 1, #E.FLASH_WORDS do
        if string.find(text, E.FLASH_WORDS[i], 1, true) then return true end
    end
    return false
end

function E.smokeColour(item, fullType)
    fullType = fullType or (item and item:getFullType())
    local def = fullType and R.explicit and R.explicit[fullType]
    if def and type(def.smokeColour) == "table" then return def.smokeColour[1], def.smokeColour[2], def.smokeColour[3] end
    local text = lower(fullType) .. " " .. lower(item and nameOf(item))
    for i = 1, #E.SMOKE_COLOURS do
        local c = E.SMOKE_COLOURS[i]
        if string.find(text, c[1], 1, true) then return c[2], c[3], c[4] end
    end
    return E.SMOKE_DEFAULT[1], E.SMOKE_DEFAULT[2], E.SMOKE_DEFAULT[3]
end

local function stat(o, getter)
    local ok, v = pcall(function() return o[getter](o) end)
    return (ok and type(v) == "number") and v or 0
end

-- ------------------------------------------------------------------ exact detonation points
-- The trap sits on a square; the grenade itself was somewhere on it. Whoever knows the real point
-- (the server that resolved the throw, or a client that simulated it) notes it here.
E.exact = E.exact or {}

local function skey(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end

function E.note(x, y, h)
    local z = math.floor(h / VAT.S + 0.01)
    E.exact[skey(x, y, z)] = { x = x, y = y, z = h / VAT.S, t = VAT.nowSeconds() }
end

function E.exactAt(sx, sy, sz)
    local k = skey(sx, sy, sz)
    local e = E.exact[k]
    if e and VAT.nowSeconds() - e.t < 3 then
        E.exact[k] = nil
        return e.x, e.y, e.z
    end
    return nil
end

-- ------------------------------------------------------------------ description of a trap going off
function E.fromTrap(trap, square)
    if not trap then return nil end
    square = square or (trap.getSquare and trap:getSquare())
    if not square then return nil end
    local weapon = trap.getHandWeapon and trap:getHandWeapon() or nil
    local ft = weapon and weapon:getFullType() or nil
    local d = {
        x = square:getX() + 0.5, y = square:getY() + 0.5, z = square:getZ(), ft = ft,
        p = stat(trap, "getExplosionPower"), r = stat(trap, "getExplosionRange"),
        fr = stat(trap, "getFireRange"), sr = stat(trap, "getSmokeRange"),
        nr = stat(trap, "getNoiseRange"), dur = stat(trap, "getExplosionDuration"),
    }
    local ex, ey, ez = E.exactAt(square:getX(), square:getY(), square:getZ())
    if ex then d.x, d.y, d.z = ex, ey, ez end
    if weapon and E.isFlashbang(weapon, ft) then
        d.k = "flash"
    elseif d.r > 0 or d.p > 0 then
        d.k = "explosion"
    elseif d.fr > 0 then
        d.k = "incendiary"
    elseif d.sr > 0 then
        d.k = "smoke"
        d.s = d.dur > 0 and d.dur * 2.5 or 20
        d.cr, d.cg, d.cb = E.smokeColour(weapon, ft)
    elseif d.nr > 0 then
        d.k = "pop"
    else
        return nil
    end
    return d
end
