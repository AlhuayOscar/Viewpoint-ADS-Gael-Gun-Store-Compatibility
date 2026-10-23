--[[
Viewpoint - Advanced Throwables : core namespace, constants, logging, listener plumbing.

Units used everywhere in this mod (shared by client prediction and server authority):
  x, y  world tile coordinates (1 tile = 1 metre)
  h     height in metres above level 0: h = z * VAT.S  (one storey = sqrt(6) m, the same scale
        Viewpoint renders with, see viewpoint.input.CrosshairAim)
  v*    metres per second
The simulation runs at a fixed step VAT.DT so the server and every client compute the same path
from the same launch state (deterministic: no random numbers, no table-order dependence).
]]

VAT = VAT or {}
VAT.VERSION = "1.4.1"
VAT.MOD_ID = "ViewpointAdvancedThrowables"
VAT.NET = "VATThrow"                     -- client/server command module name
VAT.S = 2.4494897                        -- metres per level
VAT.DT = 1 / 30                          -- fixed simulation step (seconds)
VAT.MAX_SUBSTEP = 0.24                   -- longest swept segment per collision test (metres)

VAT.MODE_OVERHAND = 1
VAT.MODE_UNDERHAND = 2
VAT.MODE_ROLL = 3
VAT.MODE_DROP = 4                        -- dropped, e.g. a live grenade when the thrower dies
VAT.MODE_NAMES = { "overhand", "underhand", "roll", "drop" }

VAT.debug = false                        -- verbose logging (client option or server sandbox)

-- Player-facing strings live here (B42 translation files fail silently on a missing key).
VAT.Text = VAT.Text or {
    needOtherHand = "I need the right thing in my other hand for that.",
}

-- ------------------------------------------------------------------ items
--[[
Creates an inventory item of a full type, or nil. Build 42 exposes the global instanceItem(String)
(LuaManager.GlobalObject; the Gunworks framework uses it too); the InventoryItemFactory class is not
exposed to Lua there, and indexing it (InventoryItemFactory.CreateItem) is an "attempted index of
non-table" error that pcall does not stop. Both are looked up as globals, which is safe when missing.
]]
function VAT.createItem(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local make = instanceItem
    if type(make) == "function" or type(make) == "userdata" then
        local ok, it = pcall(make, fullType)
        if ok and it then return it end
    end
    local factory = InventoryItemFactory
    if type(factory) == "table" and factory.CreateItem then
        local ok, it = pcall(factory.CreateItem, fullType)
        if ok and it then return it end
    end
    return nil
end

-- ------------------------------------------------------------------ logging
VAT.Log = VAT.Log or {}
local Log = VAT.Log
local onceKeys = {}

local function side()
    if isServer and isServer() then return "S" end
    if isClient and isClient() then return "C" end
    return "SP"
end

function Log.info(fmt, ...)
    print("[ViewpointThrow][" .. side() .. "] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

function Log.debug(fmt, ...)
    if not VAT.debug then return end
    print("[ViewpointThrow][" .. side() .. "][dbg] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

function Log.warn(fmt, ...)
    print("[ViewpointThrow][" .. side() .. "][warn] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Warns only the first time a key is seen (per-tick faults never flood the log).
function Log.once(key, fmt, ...)
    if onceKeys[key] then return end
    onceKeys[key] = true
    Log.warn(fmt, ...)
end

-- ------------------------------------------------------------------ small math helpers
function VAT.clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function VAT.lerp(a, b, t) return a + (b - a) * t end

function VAT.len3(x, y, z) return math.sqrt(x * x + y * y + z * z) end

function VAT.finite(v)
    return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end

-- ------------------------------------------------------------------ listeners (public API backs onto these)
VAT.listeners = VAT.listeners or { impact = {}, landing = {}, detonation = {}, throw = {}, rest = {} }

function VAT.addListener(kind, fn)
    local list = VAT.listeners[kind]
    if not list or type(fn) ~= "function" then return false end
    for i = 1, #list do if list[i] == fn then return true end end
    list[#list + 1] = fn
    return true
end

function VAT.removeListener(kind, fn)
    local list = VAT.listeners[kind]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

--- Calls every listener of a kind; one failing listener never stops the others or the simulation.
function VAT.emit(kind, a, b, c)
    local list = VAT.listeners[kind]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], a, b, c)
        if not ok then Log.once("listener:" .. kind .. ":" .. tostring(i), "%s listener failed: %s", kind, tostring(err)) end
    end
end

-- ------------------------------------------------------------------ time
--- Real time in seconds (monotonic enough for fixed-step accumulation on client and server).
function VAT.nowSeconds()
    return getTimestampMs() / 1000
end

-- ------------------------------------------------------------------ Java bridge
--[[
The Java side is exposed by ZombieBuddy as the table VATJ (@Exposer.LuaClass, the same pattern
Project Viewpoint ADS uses). The rest of the Lua calls VAT_* globals; they are bound here. On a
dedicated server, or without ZombieBuddy, VATJ is absent and the globals stay nil (advanced throwing
is then off on that client; servers never need them).
]]
--[[
ZombieBuddy also registers every @LuaMethod(global = true) method as a raw global of the same name.
A raw Kahlua Java call needs every parameter (a missing one is a Java error that pcall does not
catch and that corrupts the Lua call frame: "Viewpoint stops working" after a throw). So the
wrappers below are installed whenever VATJ exists, replacing the raw globals, never skipped because
a global of that name is already there (1.3.x did that, and VAT_fx("dust", x, y, z, k) with five of
ten arguments crashed on every hard bounce of a thrown tool).
]]
function VAT.bindJava()
    if not VATJ then return VAT_javaVersion ~= nil end
    local J = VATJ                      -- (re)bound on every call: cheap, and a Lua reload cannot miss it
    VAT_javaVersion = function() return J.version() end
    VAT_viewpointReady = function() return J.ready() end
    VAT_viewpointActive = function(p) return J.active(p) end
    VAT_viewpointOwns = function(p) return J.owns(p) end
    VAT_thirdPerson = function() return J.third() end
    VAT_getAim = function(t) return J.getAim(t) end
    VAT_getHand = function(p, t) return J.getHand(p, t) end
    VAT_project = function(t, x, y, h) return J.project(t, x, y, h) end
    VAT_setGate = function(on) J.setGate(on) end
    VAT_attackDown = function() return J.attackDown() end
    VAT_setFacing = function(on, yaw) J.setFacing(on, yaw) end
    VAT_setVisual = function(id, ft, x, y, z, yaw, pitch, roll) J.setVisual(id, ft, x, y, z, yaw, pitch, roll) end
    VAT_removeVisual = function(id) J.removeVisual(id) end
    VAT_clearVisuals = function() J.clearVisuals() end
    VAT_setVanillaFix = function(on) J.setVanillaFix(on) end
    VAT_setDebug = function(on) J.setDebug(on) end
    VAT_status = function() return J.status() end
    -- every argument is always passed (nil would leave Kahlua without a value for the Java parameter)
    VAT_fx = function(k, x, y, z, a, b, c, d, e, f)
        J.fx(k, x or 0, y or 0, z or 0, a or 0, b or 0, c or 0, d or 0, e or 0, f or 0)
    end
    VAT_fxSettings = function(on, fires, lights, quality)
        J.fxSettings(on and true or false, fires and true or false, lights and true or false, quality or 2)
    end
    return true
end
VAT.bindJava()
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(VAT.bindJava) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(VAT.bindJava) end
