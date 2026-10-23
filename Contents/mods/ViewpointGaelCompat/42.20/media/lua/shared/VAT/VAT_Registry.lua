require "VAT/VAT_Config"

--[[
Throwable registry. Answers one question: "can this item be thrown, and how does it behave?"

Throwing and detonating are separate concepts. Every definition describes the physical object
(mass, bounce, friction, rolling, collision radius, sounds) and lists behaviours that decide what
happens on impact, on fuse expiry and when the object stops (see VAT_Behaviors.lua). A grenade is a
physical object plus the "vanilla_trap" behaviour; a rock is only a physical object.

Resolution order (first match wins, then adapters may edit the result):
  Layer 4  explicit registration    ViewpointThrowables.registerThrowable("Mod.Item", {...})
  Layer 1  vanilla-compatible       HandWeapon with PhysicsObject / SwingAnim = Throw (every vanilla
                                     and most modded grenades, molotovs, smoke and noise makers)
  Layer 2  metadata                 explosive/fire/smoke/noise stats, remote/sensor/timer data,
                                     "throwable"/"grenade"/"explosive" tags, mod data flags
  Layer 3  generic fallback         any small inventory object (bottle, can, rock, brick, tool, melee
                                     weapon, gun, bag with its contents) under the weight limit,
                                     when the server allows object throwing
Results are cached per full type; the cache is rebuilt only when the registry changes.
]]

VAT.Registry = VAT.Registry or {}
local R = VAT.Registry
local Log = VAT.Log

R.explicit = R.explicit or {}       -- fullType -> partial definition table
R.adapters = R.adapters or {}       -- ordered { name, fn }
R.cache = R.cache or {}             -- fullType -> resolved definition or false
R.version = R.version or 0
R.probes = R.probes or {}           -- fullType -> temporary item used for classification

-- Physical presets. Values are deliberately modest: believable game physics, not simulation.
R.MATERIALS = {
    grenade  = { bounce = 0.36, friction = 0.35, rollResistance = 0.35, canRoll = true,  radius = 0.05, spin = 9 },
    canister = { bounce = 0.30, friction = 0.35, rollResistance = 0.30, canRoll = true,  radius = 0.06, spin = 7 },
    glass    = { bounce = 0.22, friction = 0.30, rollResistance = 0.35, canRoll = true,  radius = 0.05, spin = 10 },
    metal    = { bounce = 0.38, friction = 0.35, rollResistance = 0.30, canRoll = true,  radius = 0.05, spin = 9 },
    stone    = { bounce = 0.22, friction = 0.60, rollResistance = 0.90, canRoll = false, radius = 0.05, spin = 6 },
    ball     = { bounce = 0.68, friction = 0.18, rollResistance = 0.12, canRoll = true,  radius = 0.06, spin = 6 },
    wood     = { bounce = 0.30, friction = 0.50, rollResistance = 0.90, canRoll = false, radius = 0.07, spin = 7 },
    soft     = { bounce = 0.08, friction = 0.85, rollResistance = 1.50, canRoll = false, radius = 0.08, spin = 3 },
    generic  = { bounce = 0.26, friction = 0.50, rollResistance = 0.90, canRoll = false, radius = 0.06, spin = 7 },
}

-- Every field a definition may carry, with its default. Unknown keys from registrations are kept
-- (they are passed to behaviours), so mods can attach their own data.
R.FIELDS = {
    kind = "object",          -- object | explosive | incendiary | smoke | noise | trap
    material = "generic",
    behaviors = nil,          -- list of behaviour names (VAT_Behaviors); nil = { "inert" }
    mass = nil,               -- kg-ish; nil = item weight
    throwMultiplier = 1.0,    -- scales launch speed
    verticalMultiplier = 1.0, -- scales the upward launch bias
    bounce = nil, friction = nil, rollResistance = nil, canRoll = nil, radius = nil, spin = nil,
    drag = nil,               -- linear air drag per second; nil = from mass (light objects slow down more)
    breakOnImpact = false,
    breakSpeed = 6.5,         -- m/s normal impact speed that breaks a breakable object
    breakResult = nil,        -- full type left behind when it breaks (nil = nothing)
    breaksWindows = true,     -- can smash a closed intact window when fast enough
    maxVelocity = nil,        -- absolute cap (m/s); nil = server MaxThrowSpeed * 1.25
    fuse = nil,               -- { type = "none" | "impact" | "timed" | "placed", seconds = n }
    cookable = false,         -- fuse can be started while still held (needs the server option)
    damageMultiplier = 1.0,
    noiseRadius = nil,        -- zombie distraction radius in tiles (nil = from mass)
    noiseVolume = nil,
    impactSound = nil, breakSound = nil, throwSound = nil,
    primaryInput = nil,       -- true: the Attack button throws it in Viewpoint (vanilla throwables)
    throwAnimation = "overhand",
    impactCallback = nil, landingCallback = nil,   -- optional functions (proj, hit) / (proj)
}

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
R.copy = copy

local function bump()
    R.version = R.version + 1
    R.cache = {}
end

-- ------------------------------------------------------------------ public registration
function R.register(fullType, config)
    if type(fullType) ~= "string" or fullType == "" then return false end
    if config ~= nil and type(config) ~= "table" then return false end
    R.explicit[fullType] = copy(config or {})
    bump()
    Log.info("Registered throwable: %s", fullType)
    return true
end

function R.unregister(fullType)
    if R.explicit[fullType] == nil then return false end
    R.explicit[fullType] = nil
    bump()
    Log.info("Unregistered throwable: %s", fullType)
    return true
end

--- Explicitly marks an item as never throwable (wins over every other layer).
function R.exclude(fullType)
    if type(fullType) ~= "string" then return false end
    R.explicit[fullType] = { excluded = true }
    bump()
    return true
end

function R.setBehavior(fullType, behaviors)
    if type(behaviors) == "string" then behaviors = { behaviors } end
    if type(behaviors) ~= "table" then return false end
    local e = R.explicit[fullType] or { _behaviorOnly = true }
    e.behaviors = copy(behaviors)
    R.explicit[fullType] = e
    bump()
    return true
end

--- Adapter: function(def, item, fullType) that may edit def in place, or return false to reject.
function R.registerAdapter(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return false end
    for i = 1, #R.adapters do
        if R.adapters[i].name == name then R.adapters[i].fn = fn; bump(); return true end
    end
    R.adapters[#R.adapters + 1] = { name = name, fn = fn }
    bump()
    return true
end

-- ------------------------------------------------------------------ item inspection helpers
local function index(o, k) return o[k] end

--- Calls obj:method(...) defensively. Kahlua's pcall does not catch "tried to call nil", and indexing
--- a Java object can itself throw, so the method is looked up inside pcall and checked before calling.
local function call(obj, method, ...)
    if obj == nil then return nil end
    local okF, f = pcall(index, obj, method)
    if not okF or f == nil then return nil end
    local ok, v = pcall(f, obj, ...)
    if ok then return v end
    return nil
end
R.call = call

local function tagString(item)
    local out = ""
    -- B42: getTags() is a java Set<ItemTag>; walk it with its iterator (ipairs does not see a Java array)
    local ok = pcall(function()
        local it = item:getTags():iterator()
        local guard = 0
        while it:hasNext() and guard < 64 do
            guard = guard + 1
            out = out .. " " .. string.lower(tostring(it:next()))
        end
    end)
    if not ok then return "" end
    return out
end

R.tagString = tagString
local function has(s, word) return string.find(s, word, 1, true) ~= nil end

--- Picks a material preset from tags, durability material, sounds and names.
local function guessMaterial(item, tags, fullType)
    local lname = string.lower(fullType)
    local short = string.match(lname, "%.([^%.]+)$") or lname
    if has(tags, "glass") or has(short, "bottle") or string.find(short, "jar$") then
        if not has(tags, "plastic") and not has(short, "plastic") then return "glass" end
    end
    if string.find(short, "ball$") then return "ball" end
    if has(tags, "stone") or has(short, "stone") or has(short, "rock") or has(short, "brick") then return "stone" end
    if has(tags, "hasmetal") or has(tags, "tincan") or has(tags, "emptycan") or string.find(short, "can$")
        or has(short, "tincan") then return "metal" end
    if instanceof(item, "Clothing") or string.find(short, "^rag") or has(short, "sheet") then return "soft" end
    if has(short, "plank") or string.find(short, "stick$") or has(short, "log") then return "wood" end
    return "generic"
end

local function weaponFuse(w)
    local trig = call(w, "getTriggerExplosionTimer") or 0
    local timer = call(w, "getExplosionTimer") or 0
    local sensor = call(w, "getSensorRange") or 0
    local remote = call(w, "canBeRemote") and true or false
    local power = call(w, "getExplosionPower") or 0
    local range = call(w, "getExplosionRange") or 0
    local fire = call(w, "getFireRange") or 0
    local smoke = call(w, "getSmokeRange") or 0
    local noise = call(w, "getNoiseRange") or 0
    local sound = call(w, "getExplosionSound")
    local effect = power > 0 or range > 0 or fire > 0 or smoke > 0 or noise > 0 or (sound ~= nil and sound ~= "")
    local kind = "object"
    if fire > 0 and range <= 0 then kind = "incendiary"
    elseif range > 0 or power > 0 then kind = "explosive"
    elseif smoke > 0 then kind = "smoke"
    elseif noise > 0 then kind = "noise" end
    local fuse
    if trig > 0 then
        fuse = { type = "timed", seconds = trig / 30 }        -- vanilla counts 30 fps ticks in flight
    elseif timer > 0 or sensor > 0 or remote then
        fuse = { type = "placed" }                             -- becomes a vanilla IsoTrap where it stops
        kind = "trap"
    elseif effect then
        fuse = { type = "impact" }                             -- vanilla: explodes on the first collision
    end
    return effect, kind, fuse
end

-- ------------------------------------------------------------------ classification
--- Builds a definition from layers 1-3. Returns nil when the item is not throwable.
local function classify(item, fullType, cfg)
    local def = {}
    local tags = tagString(item)
    local weight = call(item, "getActualWeight") or call(item, "getWeight") or 0.5
    def.mass = VAT.clamp(weight, 0.05, 25)
    def.material = guessMaterial(item, tags, fullType)
    def.impactSound = call(item, "getDropSound")

    local isWeapon = instanceof(item, "HandWeapon")
    if isWeapon then
        local physics = call(item, "getPhysicsObject")
        local swing = call(item, "getSwingAnim")
        local effect, kind, fuse = weaponFuse(item)
        if physics ~= nil or swing == "Throw" then
            -- Layer 1: built to be thrown by the game itself.
            def.source = "vanilla"
            def.kind = kind
            def.fuse = fuse or { type = "none" }
            def.primaryInput = true
            def.throwSound = call(item, "getSwingSound")
            if effect then
                def.behaviors = { "vanilla_trap" }
                if kind == "incendiary" then
                    def.material = "glass"                 -- molotov / flame bottle
                elseif kind == "smoke" or kind == "noise" then
                    def.material = "canister"
                elseif def.material == "generic" then
                    def.material = "grenade"
                end
            elseif physics ~= nil and string.find(string.lower(physics), "ball", 1, true) then
                def.material = "ball"
                def.behaviors = { "inert" }
            else
                def.behaviors = { "inert" }
            end
            return def
        end
        if effect and (has(tags, "throw") or has(tags, "grenade") or has(tags, "explosive")) then
            -- Layer 2: explosive metadata on a weapon the game itself would not throw.
            def.source = "metadata"
            def.kind = kind
            def.fuse = fuse or { type = "impact" }
            def.behaviors = { "vanilla_trap" }
            def.primaryInput = true
            def.material = def.material == "generic" and "grenade" or def.material
            return def
        end
        -- a gun or a melee weapon without a throw animation is a plain object: thrown with the Throw
        -- key only (primaryInput = false below keeps Attack as its normal attack / shot)
    end

    -- Layer 2: mod data / tags on non-weapons
    local md = call(item, "getModData")
    if type(md) == "table" and md.VATThrowable == false then return nil end
    if has(tags, "grenade") or has(tags, "throwable") then
        def.source = "metadata"
        def.kind = "object"
        def.behaviors = { "inert" }
        def.primaryInput = true
        return def
    end

    -- Layer 3: generic object
    if not cfg.ObjectThrowing then return nil end
    -- bags and other containers are thrown with what is in them (their actual weight counts
    -- against the limit); a worn one is never in the hand
    if instanceof(item, "Moveable") then return nil end
    if call(item, "isWorn") then return nil end
    if weight > cfg.MaxObjectWeight then return nil end
    def.source = "fallback"
    def.kind = "object"
    if def.material == "glass" then
        def.behaviors = { "breakable" }
        def.breakOnImpact = true
        def.breakSound = "BreakGlassItem"
    else
        def.behaviors = { "inert" }
    end
    def.primaryInput = false        -- generic objects use the Throw key; Attack keeps its vanilla meaning
    return def
end

--- Fills every missing field from the material preset and the field defaults.
local function finish(def, cfg)
    local mat = R.MATERIALS[def.material or "generic"] or R.MATERIALS.generic
    for k, v in pairs(mat) do if def[k] == nil then def[k] = v end end
    for k, v in pairs(R.FIELDS) do if def[k] == nil and v ~= nil then def[k] = copy(v) end end
    if def.behaviors == nil then def.behaviors = { "inert" } end
    if def.fuse == nil then def.fuse = { type = "none" } end
    def.mass = VAT.clamp(def.mass or 0.5, 0.05, 25)
    if def.drag == nil then def.drag = 0.01 + 0.03 / math.sqrt(math.max(def.mass, 0.05)) end
    if def.noiseRadius == nil then def.noiseRadius = VAT.clamp(4 + def.mass * 6, 4, 22) end
    if def.noiseVolume == nil then def.noiseVolume = VAT.clamp(10 + def.mass * 25, 10, 80) end
    local isExplosiveKind = def.kind ~= "object"
    def.bounceMul = isExplosiveKind and cfg.GrenadeBounceMultiplier or cfg.ObjectBounceMultiplier
    return def
end

--- Item used to classify a type when no instance is at hand (remote clients, server mirrors).
local function probe(fullType)
    local p = R.probes[fullType]
    if p == nil then
        local it = VAT.createItem(fullType); local ok = it ~= nil
        p = (ok and it) or false
        R.probes[fullType] = p
    end
    return p or nil
end

--- Resolves the definition of a full type. Cached; returns nil when not throwable.
function R.resolveType(fullType, item)
    if type(fullType) ~= "string" then return nil end
    local cached = R.cache[fullType]
    if cached ~= nil then return cached or nil end
    local cfg = VAT.Config.server()
    local explicit = R.explicit[fullType]
    local def
    if explicit and explicit.excluded then
        R.cache[fullType] = false
        return nil
    end
    item = item or probe(fullType)
    if explicit and not explicit._behaviorOnly then
        def = copy(explicit)
        def.source = "registered"
        if item and (def.mass == nil) then def.mass = call(item, "getActualWeight") or call(item, "getWeight") end
        if def.primaryInput == nil then def.primaryInput = true end
        if item and def.impactSound == nil then def.impactSound = call(item, "getDropSound") end
        if item and def.throwSound == nil and instanceof(item, "HandWeapon") then def.throwSound = call(item, "getSwingSound") end
        if def.fuse == nil and item and instanceof(item, "HandWeapon") then
            local effect, kind, fuse = weaponFuse(item)
            if effect then
                def.fuse = fuse
                def.kind = def.kind or kind
                if def.behaviors == nil then def.behaviors = { "vanilla_trap" } end
            end
        end
    elseif item then
        local ok, res = pcall(classify, item, fullType, cfg)
        if not ok then
            Log.once("classify:" .. fullType, "Could not classify %s: %s", fullType, tostring(res))
            res = nil
        end
        def = res
        if def and explicit and explicit.behaviors then def.behaviors = copy(explicit.behaviors) end
    end
    if def then
        for i = 1, #R.adapters do
            local ok, keep = pcall(R.adapters[i].fn, def, item, fullType)
            if not ok then
                Log.once("adapter:" .. R.adapters[i].name, "Adapter %s failed: %s", R.adapters[i].name, tostring(keep))
            elseif keep == false then
                def = nil
                break
            end
        end
    end
    if def then
        def.fullType = fullType
        finish(def, cfg)
        Log.debug("Classified %s source=%s kind=%s material=%s fuse=%s behaviors=%s", fullType, tostring(def.source),
            tostring(def.kind), tostring(def.material), tostring(def.fuse.type), table.concat(def.behaviors, ","))
    elseif item then
        Log.debug("Not throwable: %s", fullType)
    end
    R.cache[fullType] = def or false
    return def
end

--- Definition for an inventory item instance (uses the instance for classification the first time).
function R.resolve(item)
    if not item then return nil end
    local fullType = call(item, "getFullType")
    if not fullType then return nil end
    return R.resolveType(fullType, item)
end

--- Mass of this particular instance (a full bottle is heavier than an empty one).
function R.massOf(item, def)
    local w = item and (call(item, "getActualWeight") or call(item, "getWeight"))
    if not w or w <= 0 then return def and def.mass or 0.5 end
    if def and R.explicit[def.fullType] and R.explicit[def.fullType].mass then return def.mass end
    return VAT.clamp(w, 0.05, 25)
end

--- Vanilla "OtherHandRequire" (a molotov needs a lit lighter in the other hand): the same rule as
--- CombatManager.calculateAttackVars. Returns ok, secondaryItem, mustUseSecondary.
function R.otherHandOk(player, item)
    if not item or not instanceof(item, "HandWeapon") then return true end
    local tag = call(item, "getOtherHandRequire")
    if tag == nil then return true end
    local secondary = player and player:getSecondaryHandItem()
    if not secondary then return false end
    if not call(secondary, "hasTag", tag) then return false end
    if (call(secondary, "getCurrentUses") or 1) <= 0 then return false end
    return true, secondary, call(item, "isOtherHandUse") == true
end
