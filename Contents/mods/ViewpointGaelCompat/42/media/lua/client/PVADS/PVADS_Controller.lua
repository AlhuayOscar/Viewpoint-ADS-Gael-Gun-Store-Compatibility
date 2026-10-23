-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Options"
require "TimedActions/ISTimedActionQueue"

--[[
ADS controller: decides each tick whether the local player wants the sights up, pushes the resolved
profile to the Java side when the weapon or its optic changes, and feeds the stability factor.
All of this is local to this client; nothing is sent over the network.

State machine (Java side, driven by "want"): NORMAL -> ENTERING -> ADS -> EXITING -> NORMAL.
Any interruption simply drops "want", so the sights always come down and can never stick.
]]

local C = { toggled = false, sig = nil, ticks = 0, profile = nil, ready = false, lastWant = false }
PVADS.Controller = C

local function localPlayer() return getSpecificPlayer(0) end

function C.weapon(pl)
    local w = pl and pl:getPrimaryHandItem()
    if w and instanceof(w, "HandWeapon") and w:isAimedFirearm() then return w end
    return nil
end

local function signature(w)
    if not w then return "none" end
    local s = w:getFullType()
    local parts = w:getAllWeaponParts()
    if parts then for i = 0, parts:size() - 1 do s = s .. "|" .. parts:get(i):getFullType() end end
    return s
end

function C.refresh(force)
    local pl = localPlayer()
    local w = C.weapon(pl)
    local sig = signature(w)
    if PVADS.pushOpticModelProfiles then PVADS.pushOpticModelProfiles() end
    if not force and sig == C.sig then return end
    local prevWeapon = C.sig and string.match(C.sig, "^[^|]*")
    C.sig = sig
    if prevWeapon ~= string.match(sig, "^[^|]*") then                          -- new gun starts at the hip
        C.toggled = false
        if PVADS_clearAimLock then PVADS_clearAimLock() end
    end
    if not w then C.profile = nil; PVADS_clearProfile(); if PVADS.Scope then PVADS.Scope.onProfile(nil) end; return end
    local ok, p = pcall(PVADS.ResolveProfile, w)
    if not ok then
        PVADS.log("profile error for " .. w:getFullType() .. ": " .. tostring(p))
        C.profile = nil; PVADS_clearProfile(); return
    end
    C.profile = p
    PVADS_setProfile(p)
    if PVADS.Scope then PVADS.Scope.onProfile(p, w) end
    if not PVADS.Generated.weapons[w:getFullType()] then
        PVADS.dev("Using generic ADS profile for " .. w:getFullType())
    end
    PVADS.dev("profile " .. p.weaponId .. " mode=" .. p.mode .. " optic=" .. tostring(p.opticId) .. " model=" .. tostring(p.opticModel) .. " iron=" .. tostring(p.ironSource))
end

-- Timed actions that keep the sights up (working the action of a bolt/pump gun between shots).
C.ALLOWED_ACTIONS = { ISRackFirearm = true }

local function blockingAction(pl)
    local q = ISTimedActionQueue.queues and ISTimedActionQueue.queues[pl]
    if not q or not q.queue then return nil end
    local a = q.queue[1]
    if a and not C.ALLOWED_ACTIONS[a.Type or ""] then return a.Type or "action" end
    return nil
end

-- Blocking timed actions own the upper-body pose until they finish.
-- Respect the same allowlist as blocked(): cycling a bolt/pump is deliberately
-- allowed to keep ADS up so the existing BoltPitchMotion runs over the sights.
-- Magazine changes/reloads still block immediately, including packs that keep
-- isAiming() true during their reload animation.
local function timedActionActive(pl)
    local q = ISTimedActionQueue.queues and ISTimedActionQueue.queues[pl]
    local action = q and q.queue and q.queue[1]
    return action ~= nil and not C.ALLOWED_ACTIONS[action.Type or ""]
end

--- Reasons the sights must come down. Returns (reason, hard): hard reasons drop ADS at once,
--- soft ones only after they persist (so a one-frame state flicker while firing never drops ADS).
--- Firing itself is never a reason: shooting is what ADS is for.
function C.blocked(pl)
    if pl:isDead() or pl:isAsleep() then return "dead/asleep", true end
    if pl:getVehicle() then return "vehicle", true end
    if pl:isSprinting() or pl:isRunning() then return "running", true end
    if pl:isClimbing() then return "climbing", true end
    if pl:isKnockedDown() or pl:isSitOnGround() then return "down", true end
    if pl:isBumped() then return "bumped", false end
    local act = blockingAction(pl)
    if act then return act, false end                 -- reload, magazine, eat, etc.
    if C.profile and C.profile.noIrons and not C.profile.opticId then return "no sights", true end
    return nil
end

C.softSince = nil
local SOFT_GRACE = 0.15   -- seconds a soft reason must persist before the sights come down
-- 1.6.1: a shove / gun bash plays a big arm swing; ADS pulling the arms and gun to the eye at the same time
-- made the view and the gun thrash. The sights drop for the shove and come back after this many ms.
local SHOVE_HOLD_MS = 250
C.shoveUntil = 0
C.suspended = false
-- reasons that lower the sights only while they last (click aiming keeps its lock through them)
C.PAUSE_REASONS = { crawling = true, shove = true }

local function setSuspended(b)
    if b == C.suspended then return end
    C.suspended = b
    if PVADS_setSuspended then PVADS_setSuspended(b) end
end

local function stability(pl, w)
    local f = 1.0
    local aiming = pl:getPerkLevel(Perks.Aiming) or 0
    f = f * (1.35 - 0.065 * aiming)
    local st = pl:getStats()
    if st and CharacterStat then
        local endu = st:get(CharacterStat.ENDURANCE) or 1
        local fat = st:get(CharacterStat.FATIGUE) or 0
        local pan = st:get(CharacterStat.PANIC) or 0
        if pan > 1 then pan = pan / 100 end
        f = f * (1 + (1 - math.min(1, math.max(0, endu))) * 0.9)
        f = f * (1 + math.min(1, math.max(0, fat)) * 0.5)
        f = f * (1 + math.min(1, math.max(0, pan)) * 0.8)
    end
    if pl:isPlayerMoving() then f = f * 1.7 elseif pl:isSneaking() then f = f * 0.8 end
    return f
end

local function onPlayerUpdate(pl)
    if not C.ready or pl ~= localPlayer() then return end
    C.ticks = C.ticks + 1
    if C.ticks % 15 == 0 or C.dirty then C.dirty = false; C.refresh(false) end

    local s = PVADS.Settings
    local w = C.weapon(pl)
    local want = false
    local reason, hard = C.blocked(pl)
    local stop = false
    -- shoving with the gun (vanilla IsoGameCharacter.isDoShove, as ISReloadWeaponAction uses it)
    local now0 = getTimestampMs()
    if pl.isDoShove and pl:isDoShove() then C.shoveUntil = now0 + SHOVE_HOLD_MS end
    local shoving = now0 < C.shoveUntil
    if shoving and not reason then reason, hard = "shove", true end
    setSuspended(shoving and (C.lastWant or C.suspended))   -- sights were up when the shove began: stay in first person
    if reason then
        if hard then stop = true
        else
            local now = getTimestampMs()
            C.softSince = C.softSince or now
            stop = (now - C.softSince) >= SOFT_GRACE * 1000
        end
    else
        C.softSince = nil
    end
    C.lastBlock = reason
    -- the aim flag can drop for a frame or two inside the fire/rack animation: bridge short gaps
    local aiming = pl:isAiming()
    if aiming then C.aimLostAt = nil
    elseif C.lastWant then
        local now = getTimestampMs()
        C.aimLostAt = C.aimLostAt or now
        aiming = (now - C.aimLostAt) < SOFT_GRACE * 1000
    end
    local actionActive = timedActionActive(pl)
    if w and C.profile and PVADS_canAds() and aiming and not stop and not actionActive then
        if s.mode == 1 then want = true
        elseif s.mode == 2 then
            -- the bound key re-read every second, not every tick
            C.keyTick = (C.keyTick or 0) + 1
            if C.keyTick >= 60 then C.keyTick = 0; if PVADS.refreshKeys then PVADS.refreshKeys() end end
            want = s.key ~= 0 and isKeyDown(s.key)
        else want = C.toggled end
        if C.forceADS then want = true end
    end
    if want ~= C.lastWant then C.lastWant = want; PVADS_setWant(want) end
    -- 1.8.7 steady aim: the key state goes to the Java part, which only uses it with the sights fully up
    if PVADS_setSteady then
        local down = want and s.steady and (s.steadyKey or 0) ~= 0 and isKeyDown(s.steadyKey) or false
        if down ~= C.steadyDown then C.steadyDown = down; PVADS_setSteady(down) end
    end
    if C.ticks % 10 == 0 and w then PVADS_setSwayFactor(stability(pl, w)) end
    -- physical weapon presence: the world query for the local player's gun (Java; no-op while inactive)
    if PVADS_presenceTick then PVADS_presenceTick() end
end

local function onKey(key)
    if not C.ready then return end
    local s = PVADS.Settings
    if PVADS.refreshKeys then PVADS.refreshKeys() end
    -- Toggle mode: the choice (hip or sights) is remembered across aim releases, so the next time you
    -- aim you come up the way you left it. It can be set while not aiming too. Reset on weapon change.
    if key == s.key and key ~= 0 and s.mode == 3 then
        C.toggled = not C.toggled
    end
    if key == s.calibKey and key ~= 0 and s.developer and PVADS.Calibrator then PVADS.Calibrator.toggle() end
end

local function onEquip(chr) if chr == localPlayer() then C.dirty = true end end

local function init()
    PVADS.bindJava()
    if not PVADS_available then
        PVADS.log("Java part not loaded (ZombieBuddy / Viewpoint missing or the jar was not approved); ADS disabled")
        return
    end
    if not PVADS_available() then
        PVADS.log("Viewpoint was not found by the Java part; ADS disabled")
        return
    end
    for _, o in pairs(PVADS.Generated.optics) do
        if o.shapes then
            for model, sh in pairs(o.shapes) do PVADS_setOpticShape(model, sh.height or 0.03, sh.length or 0.12, sh.window or 0) end
        end
    end
    if PVADS.loadUserProfiles then PVADS.loadUserProfiles() end
    PVADS.applySettings()
    C.ready = true
    C.refresh(true)
    PVADS.log("ready (" .. PVADS.VERSION .. ", java " .. tostring(PVADS_version()) .. ")")
end

Events.OnGameStart.Add(init)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnKeyStartPressed.Add(onKey)
Events.OnEquipPrimary.Add(onEquip)
Events.OnPlayerDeath.Add(function(p) if C.ready and p == localPlayer() then PVADS_setWant(false); C.lastWant = false; C.toggled = false; if PVADS_clearAimLock then PVADS_clearAimLock() end; C.shoveUntil = 0; setSuspended(false) end end)
