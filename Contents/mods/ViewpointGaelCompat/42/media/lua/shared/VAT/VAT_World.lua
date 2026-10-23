require "VAT/VAT_Core"

--[[
World collision queries for thrown objects, built on the game's own grid data so windows, doors,
barricades, fences and floors behave exactly as the rest of the game sees them. No fake geometry.

Every function here is a narrow question the physics asks during a swept segment test:
  W.edge(ax, ay, bx, by, z, lh)  what blocks the edge between two orthogonal neighbour squares at
                                  local height lh (metres above that level's floor)?
  W.surface(x, y, L)             height (m) of the walkable surface of level L at a point, or nil
  W.ceiling(x, y, L)             does level L+1 have a floor above this point?
  W.solid(x, y, L)               furniture / pillar / tree occupying the square
  W.soft(x, y, L)                bushes and other vegetation that slow an object down
  W.bodies(...), W.vehicles(...) characters and vehicles near a segment

The physics module only talks to the world through this table, which keeps it testable and lets a
mod replace a single query (for example to add custom geometry) without touching the solver.
]]

VAT.World = VAT.World or {}
local W = VAT.World
local S = VAT.S

-- Heights (metres above the level floor) of openings in a wall line. Vanilla windows have a sill;
-- the wall under the sill and above the lintel still stops a throw.
W.FENCE_HEIGHT = 1.05
W.SILL_HEIGHT = 0.80
W.LINTEL_HEIGHT = 2.15
W.DOOR_HEIGHT = 2.05
W.FURNITURE_HEIGHT = 0.85
W.FURNITURE_INSET = 0.08
W.TREE_RADIUS = 0.22
W.BODY_RADIUS = 0.28
W.BODY_HEIGHT = 1.75
W.LOW_BODY_HEIGHT = 0.55

local floor = math.floor

local function cell()
    return getCell()
end

function W.square(x, y, z)
    local c = cell()
    if not c then return nil end
    return c:getGridSquare(x, y, z)
end

local function flag(sq, f)
    return f ~= nil and sq:has(f)
end

-- ------------------------------------------------------------------ edges
--- Returns nil when the edge is open at that height, or a hit description.
function W.edge(ax, ay, bx, by, z, lh)
    local a = W.square(ax, ay, z)
    local b = W.square(bx, by, z)
    if a == nil or b == nil then return nil end

    -- which square carries the edge and whether it is a north (y) or west (x) edge
    local owner, north
    if by < ay then owner, north = a, true
    elseif by > ay then owner, north = b, true
    elseif bx < ax then owner, north = a, false
    else owner, north = b, false end

    -- waist-high fences and hedges only stop low throws
    if flag(owner, north and IsoFlagType.HoppableN or IsoFlagType.HoppableW) then
        if lh < W.FENCE_HEIGHT then return { kind = "fence", material = "wood" } end
        return nil
    end
    if flag(owner, north and IsoFlagType.TallHoppableN or IsoFlagType.TallHoppableW) then
        return { kind = "wall", material = "wood" }
    end

    local window = a:getWindowTo(b)
    if window ~= nil then
        if lh < W.SILL_HEIGHT or lh > W.LINTEL_HEIGHT then return { kind = "wall", material = "wall" } end
        if window:isBlocked() then
            local barricaded = window:isBarricaded()
            return {
                kind = barricaded and "barricade" or "window", material = barricaded and "wood" or "glass",
                window = window, intact = (not window:isDestroyed()) and (not window:IsOpen()),
                barricaded = barricaded, invincible = window:isInvincible(),
                wx = window:getSquare():getX(), wy = window:getSquare():getY(), wz = window:getSquare():getZ(),
            }
        end
        return nil
    end

    local thump = a:getWindowThumpableTo(b)
    if thump ~= nil then
        if lh < W.SILL_HEIGHT or lh > W.LINTEL_HEIGHT then return { kind = "wall", material = "wall" } end
        if (not thump:IsOpen()) or thump:isBarricaded() then
            return { kind = thump:isBarricaded() and "barricade" or "window", material = "wood", intact = false }
        end
        return nil
    end

    local frame = a:getWindowFrameTo(b)
    if frame ~= nil then
        if lh < W.SILL_HEIGHT or lh > W.LINTEL_HEIGHT then return { kind = "wall", material = "wall" } end
        if frame:isBarricaded() then return { kind = "barricade", material = "wood" } end
        return nil
    end

    if a:isDoorTo(b) then
        if lh > W.DOOR_HEIGHT then return { kind = "wall", material = "wall" } end
        if a:isDoorBlockedTo(b) then
            return { kind = "door", material = "wood", door = a:getDoorTo(b) }
        end
        return nil
    end

    if a:isWallTo(b) then return { kind = "wall", material = "wall" } end
    return nil
end

-- ------------------------------------------------------------------ floors
-- Stair surfaces, written out from IsoGridSquare.getApparentZ but without its renderer-dependent
-- "fudge" term, so the dedicated server (no renderer) and clients agree to the millimetre.
local STAIRS
local function stairOffset(sq, fx, fy)
    if not STAIRS then
        STAIRS = {
            { IsoObjectType.stairsTN, 0.6666, 1.0, true },
            { IsoObjectType.stairsTW, 0.6666, 1.0, false },
            { IsoObjectType.stairsMN, 0.3333, 0.6666, true },
            { IsoObjectType.stairsMW, 0.3333, 0.6666, false },
            { IsoObjectType.stairsBN, 0.01, 0.3333, true },
            { IsoObjectType.stairsBW, 0.01, 0.3333, false },
        }
    end
    for i = 1, #STAIRS do
        local s = STAIRS[i]
        if sq:has(s[1]) then
            local t = s[4] and (1 - fy) or (1 - fx)
            return s[2] + (s[3] - s[2]) * VAT.clamp(t, 0, 1)
        end
    end
    return 0
end

--- Absolute height (m) of the surface you would stand on in level L at (x, y), or nil if open air.
function W.surface(x, y, L)
    local ix, iy = floor(x), floor(y)
    local sq = W.square(ix, iy, L)
    if sq == nil then
        if L == 0 then return 0 end            -- outside the loaded area: assume ground
        return nil
    end
    if not sq:TreatAsSolidFloor() then
        if L == 0 then return 0 end            -- water / odd ground tiles still stop a fall at level 0
        return nil
    end
    local off = 0
    if sq:HasStairs() then
        off = stairOffset(sq, x - ix, y - iy)
    elseif sq:hasSlopedSurface() then
        off = sq:getSlopedSurfaceHeight(x - ix, y - iy)
    end
    return L * S + off * S
end

function W.ceiling(x, y, L)
    local sq = W.square(floor(x), floor(y), L + 1)
    if sq == nil then return false end
    return sq:TreatAsSolidFloor() and not sq:HasStairs()
end

-- ------------------------------------------------------------------ objects inside squares
local solidCache = {}      -- per step: "x,y,z" -> result or false

function W.beginStep()
    solidCache = {}
end

--- Furniture, pillars and trees. Returns nil or { kind, top (m above floor), inset, tree }.
function W.solid(ix, iy, L)
    local key = ix .. "," .. iy .. "," .. L
    local c = solidCache[key]
    if c ~= nil then return c or nil end
    local sq = W.square(ix, iy, L)
    local res = false
    if sq ~= nil then
        if sq:getTree() ~= nil then
            res = { kind = "tree", tree = true, radius = W.TREE_RADIUS, top = S, material = "wood" }
        elseif sq:isSolid() then
            res = { kind = "solid", top = S, inset = 0, material = "wall" }
        elseif sq:isSolidTrans() then
            res = { kind = "furniture", top = W.FURNITURE_HEIGHT, inset = W.FURNITURE_INSET, material = "wood" }
        end
    end
    solidCache[key] = res
    return res or nil
end

--- True when the square holds vegetation that should drag on a passing object.
function W.soft(ix, iy, L)
    local sq = W.square(ix, iy, L)
    return sq ~= nil and sq:has(IsoFlagType.vegitation) and not sq:isSolidTrans()
end

-- ------------------------------------------------------------------ characters and vehicles
local function isLow(chr)
    local ok, low = pcall(function()
        if chr:isProne() then return true end
        if instanceof(chr, "IsoZombie") and (chr:isCrawling() or chr:isKnockedDown()) then return true end
        if chr:isSitOnGround() then return true end
        return false
    end)
    return ok and low
end

local function index(o, k) return o[k] end

-- Animals have no getOnlineID; Kahlua's pcall does not catch calling a missing method, so look it up first.
local function bodyId(chr)
    local okF, f = pcall(index, chr, "getOnlineID")
    if not okF or f == nil then return -1 end
    local ok, id = pcall(f, chr)
    if ok then return id end
    return -1
end

--- Characters (zombies, players, animals) whose bodies could meet a segment in this box.
--- Fills `out` (reused) and returns the count.
function W.bodies(minX, minY, maxX, maxY, L0, L1, out)
    local n = 0
    local seen = {}
    for L = L0, L1 do
        for iy = floor(minY) - 1, floor(maxY) + 1 do
            for ix = floor(minX) - 1, floor(maxX) + 1 do
                local sq = W.square(ix, iy, L)
                if sq ~= nil then
                    local list = sq:getMovingObjects()
                    for i = 0, list:size() - 1 do
                        local o = list:get(i)
                        if o ~= nil and not seen[o] and instanceof(o, "IsoGameCharacter") and not o:isDead() then
                            seen[o] = true
                            n = n + 1
                            local b = out[n] or {}
                            out[n] = b
                            b.obj = o
                            b.x, b.y = o:getX(), o:getY()
                            b.base = o:getZ() * S
                            b.top = b.base + (isLow(o) and W.LOW_BODY_HEIGHT or W.BODY_HEIGHT)
                            b.r = W.BODY_RADIUS
                            b.zombie = instanceof(o, "IsoZombie")
                            b.player = instanceof(o, "IsoPlayer") and not instanceof(o, "IsoAnimal")   -- IsoAnimal extends IsoPlayer
                            b.id = bodyId(o)
                        end
                    end
                end
            end
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end

local vtmp
--- Vehicles near the box as oriented boxes (centre, unit axes, half sizes, height range).
function W.vehicles(minX, minY, maxX, maxY, L0, L1, out)
    local n = 0
    local seen = {}
    if not vtmp then vtmp = { Vector3f.new(), Vector3f.new(), Vector3f.new() } end
    for L = L0, L1 do
        for iy = floor(minY) - 3, floor(maxY) + 3 do
            for ix = floor(minX) - 3, floor(maxX) + 3 do
                local sq = W.square(ix, iy, L)
                if sq ~= nil then
                    local list = sq:getMovingObjects()
                    for i = 0, list:size() - 1 do
                        local v = list:get(i)
                        if v ~= nil and not seen[v] and instanceof(v, "BaseVehicle") then
                            seen[v] = true
                            local ok = pcall(function()
                                local script = v:getScript()
                                local ext = script:getExtents()
                                local o = v:getWorldPos(0, 0, 0, vtmp[1])
                                local ax = v:getWorldPos(1, 0, 0, vtmp[2])
                                local az = v:getWorldPos(0, 0, 1, vtmp[3])
                                local ox, oy = o:x(), o:y()
                                local wx, wy = ax:x() - ox, ax:y() - oy
                                local lx, ly = az:x() - ox, az:y() - oy
                                local wl = math.sqrt(wx * wx + wy * wy)
                                local ll = math.sqrt(lx * lx + ly * ly)
                                if wl > 0.0001 and ll > 0.0001 then
                                    n = n + 1
                                    local b = out[n] or {}
                                    out[n] = b
                                    b.obj = v
                                    b.cx, b.cy = ox, oy
                                    b.ux, b.uy = wx / wl, wy / wl
                                    b.wx, b.wy = lx / ll, ly / ll
                                    b.hw, b.hl = ext:x() / 2, ext:z() / 2
                                    b.base = v:getZ() * S
                                    b.top = b.base + math.max(0.8, ext:y())
                                end
                            end)
                            if not ok then VAT.Log.once("vehicle-shape", "Vehicle shape unavailable; vehicles ignored by throws") end
                        end
                    end
                end
            end
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end
