require "VAT/VAT_Registry"

--[[
Viewpoint - Advanced Throwables : adapters for throwable frameworks of other mods.

Gunworks gang framework (used by Guns of Marz and others)
  Grenades are registered with OrdnanceFactory.Register(fullType, params) in the shared Lua module
  "ExplosivesSystems/OrdnanceFactory" (Workshop 3722064198). Their fuse lives in that registry, not in
  the item script: an M67 has no TriggerExplosionTimer, so the generic classifier would read it as an
  impact fuse. The relevant fields, as the framework itself uses them (ExplosivesSystems/Server.lua):
    detonateOnImpact = true   explodes on the first wall or floor contact
    detonationDelay  = n      seconds after the throw (counted in flight and at rest)
  The explosion itself is an IsoTrap built from the item's own explosion stats
  (ExplosivesSystems/Payloads.lua), which is what this mod's vanilla_trap behaviour does as well.

The module is looked up lazily, at the first classification (every mod has loaded by then). The
game's require() returns the module a mod already loaded, and only logs one warning and returns nil
when the framework is not installed.
]]

VAT.Compat = VAT.Compat or {}
local Compat = VAT.Compat
local R = VAT.Registry
local Log = VAT.Log

local ordnance = nil          -- nil = not looked up yet, false = not installed

function Compat.ordnanceFactory()
    if ordnance == nil then
        ordnance = false
        local ok, mod = pcall(require, "ExplosivesSystems/OrdnanceFactory")
        if ok and type(mod) == "table" and type(mod.GetParams) == "function" then
            ordnance = mod
            Log.info("Gunworks ordnance registry found: grenade fuses are read from it")
        end
    end
    return ordnance or nil
end

--- Looks the registry up again on the next classification (tests, or a late-loading framework).
function Compat.resetOrdnance()
    ordnance = nil
    R.cache = {}
end

function Compat.gunworksAdapter(def, item, fullType)
    local OF = Compat.ordnanceFactory()
    if not OF then return end
    local p = OF.GetParams(fullType)
    if type(p) ~= "table" then return end
    local delay = tonumber(p.detonationDelay) or 0
    if p.detonateOnImpact == true then
        def.fuse = { type = "impact" }
    elseif delay > 0 then
        def.fuse = { type = "timed", seconds = delay }
    else
        return                                    -- a registered rock or bottle: nothing to change
    end
    if def.kind == nil or def.kind == "object" then def.kind = "explosive" end
    if def.material == nil or def.material == "generic" then def.material = "grenade" end
    if def.behaviors == nil or (#def.behaviors == 1 and def.behaviors[1] == "inert") then
        def.behaviors = { "vanilla_trap" }
    end
    def.primaryInput = true
    def.source = (def.source or "?") .. "+gunworks"
end

--[[
Viewpoint True Ballistics (Workshop 3812864848) together with Gunworks launchers

True Ballistics makes every aimed firearm shot under Viewpoint a simulated bullet, the M79 and the
M203 included: next to the framework's 40 mm round it fired a second, invisible bullet that hit for
the launcher's damage. Its client ammo guard (VTB_Client.lua) also refuses a shot while that many of
its bullets are still in the air (pending >= rounds in the gun): a launcher holds one round and the
bullet could fly for the whole configured lifetime (up to 20 s), so the next grenade was refused,
and the framework's attack hook (CustomSystemHooks.lua) only marks the round to launch when
ISReloadWeaponAction.canShoot passes.

True Ballistics has an ammo profile API for exactly this (VTB.registerAmmoProfile, shared). The
profile key is weapon:getAmmoType():getItemKey(); the framework sets the gun's ammo type to the round
being fired (Ammo.AmmoProfileSetter), and an AmmoType's item key is the round's full type
("SWMG.40mm_Round_HE"), the same key as OrdnanceFactory.AmmoRegistry. Every registered ordnance round
gets a profile that makes True Ballistics' bullet harmless and gone at once (no damage, no
penetration, no tracer, the shortest range and life it allows), so only the framework's round acts and
the ammo guard is free again within a tenth of a second. Ordinary rounds (40 mm buckshot) keep theirs.
]]
Compat.BALLISTICS_INERT = {
    damageMultiplier = 0, penetration = 0, maximumRange = 1, projectileLifetime = 0.1,
    tracer = false, pelletCount = 1, category = "ordnance (launched by Gunworks)",
}
local inertDone = {}

function Compat.trueBallistics()
    return type(VTB) == "table" and type(VTB.registerAmmoProfile) == "function" and VTB or nil
end

--- Registers the inert True Ballistics profile for every Gunworks ordnance round; returns how many
--- were new. Idempotent; safe to call again when more rounds were registered later.
function Compat.registerBallisticsExclusions()
    local tb = Compat.trueBallistics()
    local OF = Compat.ordnanceFactory()
    if not tb or not OF or type(OF.AmmoRegistry) ~= "table" then return 0 end
    local n = 0
    for bullet, _ in pairs(OF.AmmoRegistry) do
        if type(bullet) == "string" and not inertDone[bullet] then
            local values = {}
            for k, v in pairs(Compat.BALLISTICS_INERT) do values[k] = v end
            local ok, err = pcall(tb.registerAmmoProfile, bullet, values)
            if ok then
                inertDone[bullet] = true
                n = n + 1
            else
                Log.warn("True Ballistics profile for %s not set: %s", bullet, tostring(err))
            end
        end
    end
    if n > 0 then
        Log.info("True Ballistics: %d Gunworks launcher round(s) left to the launcher (no duplicate bullet)", n)
    end
    return n
end

function Compat.resetBallisticsExclusions() inertDone = {} end

--- Registers the adapters (idempotent: registering by name again replaces the entry).
function Compat.install()
    R.registerAdapter("gunworks_ordnance", Compat.gunworksAdapter)
end

Compat.install()

-- every mod's shared Lua has loaded by these events; True Ballistics queues profiles until its Java
-- part is up and flushes them on OnGameBoot / OnGameStart, so registering at both is enough
local function tbHook()
    local ok, err = pcall(Compat.registerBallisticsExclusions)
    if not ok then Log.warn("True Ballistics compatibility: %s", tostring(err)) end
end
if Events then
    if Events.OnGameBoot then Events.OnGameBoot.Add(tbHook) end
    if Events.OnGameStart then Events.OnGameStart.Add(tbHook) end
    if Events.OnServerStarted then Events.OnServerStarted.Add(tbHook) end
end
