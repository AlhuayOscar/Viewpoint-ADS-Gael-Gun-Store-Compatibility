-- Viewpoint True Ballistics - shared Lua API (loaded on clients and on the server).
--
-- Compatibility packs register ballistic values here. Put registrations in a *shared* Lua file so the
-- server and every client use identical profiles (the server validates hit distances with them).
--
--   require "VTB/VTB_Core"
--   VTB.registerAmmoProfile("Base.Bullets9mm", { muzzleVelocity = 370 })
--   VTB.registerWeaponProfile("Base.HuntingRifle", { muzzleVelocity = 820, penetration = 2 })
--
-- Keys (all optional): muzzleVelocity (m/s), gravityScale, drag (1/m), projectileMass (g), penetration
-- (bodies), damageMultiplier, maximumRange (m), projectileLifetime (s), pelletCount, spread (pellet
-- cone half-angle, degrees), baseSpread (mrad), tracer (true/false), category (text).

VTB = VTB or {}
VTB.version = "1.4.6"

-- Java bridge. The Java part is exposed by ZombieBuddy as the table TrueBallisticsJ; it is nil when the
-- Java part is not running (ZombieBuddy missing, or the jar was not approved). The VTB_* globals below
-- forward to it and do nothing (return nil) without it.
local function J() return TrueBallisticsJ end

function VTB_version() local j = J(); if j then return j.version() end end
function VTB_available() local j = J(); if j then return j.available() end end
function VTB_registerWeaponProfile(fullType, values) local j = J(); if j then j.registerWeaponProfile(fullType, values) end end
function VTB_registerAmmoProfile(ammo, values) local j = J(); if j then j.registerAmmoProfile(ammo, values) end end
function VTB_describeHeldWeapon() local j = J(); if j then return j.describeHeldWeapon() end end
function VTB_setZero(meters) local j = J(); if j then j.setZero(meters) end end
function VTB_getZero() local j = J(); if j then return j.getZero() end end
function VTB_debug(what, on) local j = J(); if j then return j.debug(what, on) end end
function VTB_tracers(every) local j = J(); if j then j.tracers(every) end end
function VTB_stress(count) local j = J(); if j then return j.stress(count) end end
function VTB_pendingRounds() local j = J(); if j then return j.pendingRounds() end end
function VTB_stats() local j = J(); if j then return j.stats() end end
function VTB_status() local j = J(); if j then return j.status() end; return "True Ballistics Java part is NOT running" end
function VTB_setServerConfirmed(confirmed, version) local j = J(); if j then j.setServerConfirmed(confirmed, version) end end
function VTB_serverInfo() local j = J(); if j then return j.serverInfo() end end
function VTB_onGameStart() local j = J(); if j then j.onGameStart() end end
-- Bullet holes / impact debris (client presentation; relayed between players by VTB_Client/VTB_Server).
function VTB_takeImpacts() local j = J(); if j then return j.takeImpacts() end end
function VTB_remoteImpacts(d) local j = J(); if j then j.remoteImpacts(d) end end
function VTB_effects(what, value) local j = J(); if j then return j.effects(what, value) end end
-- NPC mods: real projectiles for scripted shooters (see docs/README.md, "NPC mods").
function VTB_npcFire(shooter, target, aimX, aimY, aimZ, weapon, hitChance, maxDistance, authoritative, tracer)
    local j = J(); if j then return j.npcFire(shooter, target, aimX, aimY, aimZ, weapon, hitChance, maxDistance, authoritative, tracer) end
end
function VTB_npcTick() local j = J(); if j then return j.npcTick() end end
function VTB_npcVisual(launch) local j = J(); if j then j.npcVisual(launch) end end

local queued = {}

local function javaReady()
    return J() ~= nil
end

local function flush()
    if not javaReady() then return end
    for i = 1, #queued do
        local q = queued[i]
        if q.kind == "weapon" then VTB_registerWeaponProfile(q.key, q.values)
        else VTB_registerAmmoProfile(q.key, q.values) end
    end
    queued = {}
end

function VTB.registerWeaponProfile(fullType, values)
    if type(fullType) ~= "string" or type(values) ~= "table" then
        print("[TrueBallistics] VTB.registerWeaponProfile(fullType, table) expected")
        return
    end
    if javaReady() then VTB_registerWeaponProfile(fullType, values)
    else table.insert(queued, { kind = "weapon", key = fullType, values = values }) end
end

function VTB.registerAmmoProfile(ammo, values)
    if type(ammo) ~= "string" or type(values) ~= "table" then
        print("[TrueBallistics] VTB.registerAmmoProfile(ammo, table) expected")
        return
    end
    if javaReady() then VTB_registerAmmoProfile(ammo, values)
    else table.insert(queued, { kind = "ammo", key = ammo, values = values }) end
end

-- For ADS / scope mods: zero distance of the sight in use (metres); a negative value restores the default.
function VTB.setZero(meters)
    VTB_setZero(meters)
end

function VTB.getZero()
    return VTB_getZero() or 0
end

function VTB.isAvailable()
    return J() ~= nil
end

Events.OnGameBoot.Add(flush)
Events.OnGameStart.Add(flush)
if Events.OnServerStarted then Events.OnServerStarted.Add(flush) end
