-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
require "PVADS/PVADS_Options"

--[[
1.9.0 bipods. Every gun pack deploys its bipod its own way; this file only decides WHEN and asks the pack to do it,
so the pack's own stat changes, models and multiplayer sync stay as the pack made them. All calls below are the
packs' own (read from their files):

  Guns of Marz, integrated (M60, BAR, M24)   WeaponSystems/Utils/FoldingBipod: HasFoldableBipod / IsBipodDeployed;
                                             toggled by the framework's timed action ISFoldBipod:new(chr, weapon, anim)
  Guns of Marz, add-on bipod (Bipod slot)    MarzGuns.Bipod_Folded <-> MarzGuns.Bipod_Deployed, swapped by the
                                             framework's ISSwapAttachment:new(chr, weapon, anim) (DynamicAttachment)
  Gael's Gun Store (Barrel_Shroud slot)      Base.bipod_* <-> Base.bipod_*_open; the pack's radial toggle is a local
                                             function, so its steps are repeated here exactly (GGS_MagSwapReloadRadial)
  VFE                                        Base.Bipod on the Canon slot is always out (deployed, nothing to toggle);
                                             the M60 swaps Base.M60MMG <-> Base.M60MMG_Bipod by VFEAltOperationAction

The timed actions are given the vanilla "AttachItem" animation instead of the packs' "Craft": Viewpoint Advanced
Movement keeps you prone only through actions it knows (attachitem is one), so a crafting animation would stand
you up in the middle of putting the bipod down.
]]

PVADS.Bipod = PVADS.Bipod or {}
local B = PVADS.Bipod

local ANIM = "AttachItem"
local COOLDOWN_MS = 1500
local FOLD_AFTER_MS = 800

local function req(path)
    local ok, m = pcall(require, path)
    if ok and type(m) == "table" then return m end
    return nil
end
local FoldingBipod, DynamicAttachment
local function libs()
    if FoldingBipod == nil then FoldingBipod = req("WeaponSystems/Utils/FoldingBipod") or false end
    if DynamicAttachment == nil then DynamicAttachment = req("WeaponSystems/Utils/DynamicAttachment") or false end
end

local GGS_SLOT = "Barrel_Shroud"
local GGS_TOGGLE = {
    ["Base.bipod_harris"] = "Base.bipod_harris_open", ["Base.bipod_harris_open"] = "Base.bipod_harris",
    ["Base.bipod_old"] = "Base.bipod_old_open",       ["Base.bipod_old_open"] = "Base.bipod_old",
    ["Base.bipod_simple"] = "Base.bipod_simple_open", ["Base.bipod_simple_open"] = "Base.bipod_simple",
    ["Base.scrap_bipod"] = "Base.scrap_bipod_open",   ["Base.scrap_bipod_open"] = "Base.scrap_bipod",
}
local MARZ_DEPLOYED, MARZ_FOLDED = "MarzGuns.Bipod_Deployed", "MarzGuns.Bipod_Folded"

local function part(w, slot)
    if not (w and w.getWeaponPart) then return nil end
    local ok, p = pcall(w.getWeaponPart, w, slot)
    if ok then return p end
    return nil
end
local function fullType(it) return it and it.getFullType and it:getFullType() or nil end

--- What bipod the gun has: returns kind, deployed (bool), canToggle (bool). kind nil = no bipod.
function B.inspect(w)
    if not w then return nil end
    libs()
    -- Guns of Marz integrated
    if FoldingBipod and FoldingBipod.HasFoldableBipod and FoldingBipod.HasFoldableBipod(w) then
        return "marzIntegrated", FoldingBipod.IsBipodDeployed(w) == true, ISFoldBipod ~= nil
    end
    -- Guns of Marz add-on bipod
    local mp = fullType(part(w, "Bipod"))
    if mp == MARZ_DEPLOYED or mp == MARZ_FOLDED then
        return "marzPart", mp == MARZ_DEPLOYED, ISSwapAttachment ~= nil and DynamicAttachment ~= false
    end
    -- Gael's Gun Store
    local gp = fullType(part(w, GGS_SLOT))
    if gp and GGS_TOGGLE[gp] then
        return "ggs", string.find(gp, "_open", 1, true) ~= nil, true
    end
    -- VFE M60 (two items)
    local ft = fullType(w)
    if ft == "Base.M60MMG" or ft == "Base.M60MMG_Bipod" then
        return "vfeM60", ft == "Base.M60MMG_Bipod", VFEAltOperationAction ~= nil and VFEAltOperationSet ~= nil
    end
    -- VFE fixed bipod on the barrel
    local cp = part(w, "Canon")
    if cp and cp.getType and cp:getType() == "Bipod" then return "vfeFixed", true, false end
    return nil
end

local function busy(pl)
    local q = ISTimedActionQueue.queues and ISTimedActionQueue.queues[pl]
    return q ~= nil and q.queue ~= nil and q.queue[1] ~= nil
end

--- Asks the gun's pack to deploy (want = true) or fold its bipod. Returns true when something was started.
function B.toggle(pl, w, want)
    local kind, deployed, can = B.inspect(w)
    if not kind or not can then return false end
    if want ~= nil and want == deployed then return false end
    if kind == "marzIntegrated" then
        ISTimedActionQueue.add(ISFoldBipod:new(pl, w, ANIM))
    elseif kind == "marzPart" then
        -- the framework swaps the first paired part it finds: only when that is the bipod
        local partner, slot = DynamicAttachment.GetSwappableAttachment(w)
        if partner ~= MARZ_DEPLOYED and partner ~= MARZ_FOLDED then return false end
        ISTimedActionQueue.add(ISSwapAttachment:new(pl, w, ANIM))
    elseif kind == "ggs" then
        -- the pack's own toggle steps (GGS_MagSwapReloadRadial.lua: toggleBipod / copyPartState / syncBipodToggle)
        local cur = part(w, GGS_SLOT)
        local target = GGS_TOGGLE[fullType(cur) or ""]
        if not (cur and target and instanceItem and w.setWeaponPart) then return false end
        local np = instanceItem(target)
        if not np then return false end
        if cur.getCondition and np.setCondition then np:setCondition(cur:getCondition()) end
        if cur.getModData and np.getModData then
            local s, d = cur:getModData(), np:getModData()
            for k, v in pairs(s) do d[k] = v end
        end
        w:setWeaponPart(GGS_SLOT, np)
        if syncHandWeaponFields then syncHandWeaponFields(pl, w) end
        if pl.resetEquippedHandsModels then pl:resetEquippedHandsModels() end
        if pl.resetModelNextFrame then pl:resetModelNextFrame() end
    elseif kind == "vfeM60" then
        local idx, entry
        for i, e in ipairs(VFEAltOperationSet) do
            if e.Name and e.Name[1] == "Base.M60MMG" and e.Name[2] == "Base.M60MMG_Bipod" then idx, entry = i, e; break end
        end
        if not idx then return false end
        local target = deployed and 1 or 2
        if VFESwapCosmetics and VFESwapCosmetics.rememberSlot then pcall(VFESwapCosmetics.rememberSlot, pl, w) end
        local time = entry.Time
        if not time or time <= 0 then time = 1.0 end
        ISTimedActionQueue.add(VFEAltOperationAction:new(w, idx, target, pl, ANIM, time))
    else
        return false
    end
    PVADS.log("bipod: " .. (deployed and "folding" or "deploying") .. " (" .. kind .. ")")
    return true
end

-- ------------------------------------------------------------------ per update
local rest = {}
B.lastMs, B.movingSince, B.restSince = 0, nil, nil

function B.update(pl, w)
    local s = PVADS.Settings
    local kind, deployed, can = B.inspect(w)
    if PVADS_setBipod then
        local d = kind ~= nil and deployed or false
        if d ~= B.lastSent then B.lastSent = d; PVADS_setBipod(d) end
    end
    B.kind, B.deployed = kind, deployed
    if not kind or not can or not s.rest or not s.bipodAuto or not PVADS_getRest then return end
    local now = getTimestampMs()
    if now - B.lastMs < COOLDOWN_MS or busy(pl) then return end
    PVADS_getRest(rest)
    if not deployed then
        -- prone (Advanced Movement), or the gun resting on something with the sights up
        local onRest = rest.surface == true and rest.sightsUp == true
        if onRest then B.restSince = B.restSince or now else B.restSince = nil end
        local want = rest.prone == true or (B.restSince ~= nil and now - B.restSince >= 400)
        -- the M60 changes item: never in the middle of aiming (the sights would drop)
        if want and kind == "vfeM60" and rest.sightsUp then want = false end
        if want and B.toggle(pl, w, true) then B.lastMs = now; B.restSince = nil end
    else
        -- walking off with it out and nothing to rest on: fold it
        local loose = rest.prone ~= true and rest.surface ~= true and pl:isPlayerMoving() and not pl:isAiming()
        if loose then B.movingSince = B.movingSince or now else B.movingSince = nil end
        if B.movingSince and now - B.movingSince >= FOLD_AFTER_MS and B.toggle(pl, w, false) then B.lastMs = now; B.movingSince = nil end
    end
end

local function onKey(key)
    local s = PVADS.Settings
    if not s or (s.bipodKey or 0) == 0 or key ~= s.bipodKey then return end
    local pl = getSpecificPlayer(0)
    if not pl or pl:isDead() then return end
    local w = pl:getPrimaryHandItem()
    if not (w and instanceof(w, "HandWeapon")) then return end
    if busy(pl) then return end
    if B.toggle(pl, w, nil) then B.lastMs = getTimestampMs() end
end

local function onPlayerUpdate(pl)
    if pl ~= getSpecificPlayer(0) or not PVADS.Controller or not PVADS.Controller.ready then return end
    local w = pl:getPrimaryHandItem()
    if not (w and instanceof(w, "HandWeapon")) then
        if B.lastSent then B.lastSent = false; if PVADS_setBipod then PVADS_setBipod(false) end end
        return
    end
    local ok, err = pcall(B.update, pl, w)
    if not ok and not B.errLogged then B.errLogged = true; PVADS.log("bipod: " .. tostring(err)) end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnKeyStartPressed.Add(onKey)
