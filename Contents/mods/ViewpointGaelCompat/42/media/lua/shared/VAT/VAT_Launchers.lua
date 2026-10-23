require "VAT/VAT_Projectiles"
require "VAT/VAT_Compat"

--[[
Launched grenades: rounds fired out of a gun (Guns of Marz M79 and M203, and any round a mod
registers with the Gunworks framework's OrdnanceFactory.RegisterAmmo) fly as this mod's own
projectiles, exactly like a thrown grenade: the same shared simulation on the server and every
client, the round's model drawn in Viewpoint's 3D scene, an impact fuse, and the explosion through
the game's own IsoTrap with the 3D explosion effects.

Where the numbers come from (Gunworks gang framework, verified in its sources):
  OrdnanceFactory.AmmoRegistry[round]   parentItem   item whose script stats explode
                                                     (MarzGuns.40mm_HE_Explosion: ExplosionPower 70,
                                                     ExplosionRange 7)
                                        worldModel   item drawn in flight (MarzGuns.M67)
                                        throwSpeed   the framework's launch speed (40 for 40 mm)
  Ammo (WeaponSystems/Utils/Ammo)       GetFamilyForItem(gun) / GetBulletTypesForFamily(family):
                                        which rounds a gun chambers ("40mm": M79, M203_Weapon)
                                        AmmoProfileSetter(gun, round): sets the gun's ammo type and
                                        stats to that round (the 40 mm HE profile has no projectiles
                                        and no hits, so the gun itself fires nothing)

A launched round's definition is built the same way on every side from those shared registries
(L.def), so a client mirror simulates the same flight as the server.
]]

VAT.Launchers = VAT.Launchers or {}
local L = VAT.Launchers
local R = VAT.Registry
local Log = VAT.Log

L.MAX_SPEED = 120
L.ZERO = 25                 -- metres along the line of sight where the launcher's sights meet the bore
L.DRAG = 0                  -- no air drag: over a ~1-3 s flight it is negligible, and the arc onto the
                            -- crosshair point stays exact
L.MIN_INTERVAL = 0.45       -- seconds between two launches by one player (server)
L.MUZZLE_REACH = 2.2        -- metres from the body a muzzle point may be (server)
L.cache = L.cache or {}

local ammoModule = nil      -- nil = not looked up, false = missing
function L.ammo()
    if ammoModule == nil then
        ammoModule = false
        local ok, mod = pcall(require, "WeaponSystems/Utils/Ammo")
        if ok and type(mod) == "table" and type(mod.GetFamilyForItem) == "function" then ammoModule = mod end
    end
    return ammoModule or nil
end

local function OF() return VAT.Compat.ordnanceFactory() end

--- Gunworks parameters of a launched round, or nil when it is not ordnance.
function L.params(round)
    local of = OF()
    if not of or type(round) ~= "string" or not of.GetAmmoParams then return nil end
    local p = of.GetAmmoParams(round)
    return type(p) == "table" and p or nil
end

function L.isRound(round) return L.params(round) ~= nil end

--- Launch speed (m/s) of a round: the server's LauncherSpeed (sandbox, default 32 m/s) for the
--- framework's standard 40 mm throwSpeed of 40, scaled for rounds registered faster or slower.
--- A real M79 fires at about 76 m/s (range ~400 m); for Project Zomboid's distances the default is a
--- visible lob: about 1.3 s of flight to 40 m, about 100 m at the highest arc.
function L.speed(round)
    local p = L.params(round)
    local s = p and tonumber(p.throwSpeed) or 40
    local base = VAT.Config.server().LauncherSpeed or 32
    return VAT.clamp(base * s / 40, 8, L.MAX_SPEED)
end

--- What is drawn in flight.
function L.visualType(round)
    local p = L.params(round)
    return (p and p.worldModel) or (p and p.parentItem) or round
end

--- The item that explodes.
function L.payloadType(round)
    local p = L.params(round)
    return (p and p.parentItem) or round
end

--- Projectile definition of a launched round (shared: the server and every client build the same one).
function L.def(round)
    local c = L.cache[round]
    if c ~= nil then return c or nil end
    local p = L.params(round)
    if not p then L.cache[round] = false; return nil end
    local payload = L.payloadType(round)
    local base = R.resolveType(payload)
    local def = base and R.copy(base) or R.copy(R.MATERIALS.grenade)
    def.fullType = payload
    def.round = round
    def.launched = true
    def.kind = (def.kind == nil or def.kind == "object") and "explosive" or def.kind
    def.material = "grenade"
    def.behaviors = { "vanilla_trap" }
    def.fuse = { type = "impact" }
    def.drag = L.DRAG
    def.spin = 0
    def.radius = 0.04
    def.bounce = 0.1
    def.canRoll = false
    def.noseForward = true
    def.breaksWindows = true
    def.mass = def.mass or 0.23
    def.bounceMul = def.bounceMul or 1
    def.maxVelocity = L.MAX_SPEED
    def.primaryInput = false
    def.throwSound = nil
    L.cache[round] = def
    return def
end

--- Rounds a gun chambers that are launched ordnance, in the family's order.
function L.roundsFor(weapon)
    local out = {}
    local A = L.ammo()
    if A and weapon then
        local okF, family = pcall(A.GetFamilyForItem, weapon)
        local list = okF and family and A.GetBulletTypesForFamily(family) or nil
        if type(list) == "table" then
            for i = 1, #list do if L.isRound(list[i]) then out[#out + 1] = list[i] end end
        end
    end
    return out
end

--- True when this gun may launch this round (its ammo family holds it, or it is the gun's ammo type).
function L.gunTakes(weapon, round)
    if not weapon or not L.isRound(round) then return false end
    local ok, key = pcall(function() local t = weapon:getAmmoType(); return t and t:getItemKey() end)
    if ok and key == round then return true end
    local rounds = L.roundsFor(weapon)
    for i = 1, #rounds do if rounds[i] == round then return true end end
    return false
end

--- Puts the gun's ammo type and stats on the round being fired (the framework's own call), so the
--- gun's own shot carries no pellets and True Ballistics uses the round's inert profile.
function L.setGunRound(weapon, round)
    local A = L.ammo()
    if not A or type(A.AmmoProfileSetter) ~= "function" then return false end
    local ok, err = pcall(A.AmmoProfileSetter, weapon, round)
    if not ok then Log.once("ammoProfile", "Could not switch the gun to %s: %s", tostring(round), tostring(err)) end
    return ok
end
