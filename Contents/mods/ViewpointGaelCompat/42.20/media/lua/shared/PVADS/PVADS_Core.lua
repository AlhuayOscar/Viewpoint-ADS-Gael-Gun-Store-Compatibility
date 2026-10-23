-- Project Viewpoint: Recoil & ADS - (c) 2026 the author of Project Viewpoint (Workshop 3812612054). All rights reserved.
-- Not open source: do not copy, modify, reuse or redistribute without permission (see LICENSE.txt).
--[[
Project Viewpoint - ADS & Optics : core profile system and public compatibility API.

Profile hierarchy (later wins):
    generated (meshscan of the installed scripts/meshes)
  > weapon family defaults            PVADS.RegisterWeaponFamily
  > individual weapon profile         PVADS.RegisterWeaponProfile
  > optic profile                     PVADS.RegisterOpticProfile
  > weapon + optic override           PVADS.RegisterWeaponOpticOverride
  > adapters (code)                   PVADS.RegisterADSAdapter
  > the player's own calibration      (saved by the in-game calibrator)

Geometry is in weapon model space: Y = barrel forward, Z = up, same units as script attachments.
]]

PVADS = PVADS or {}
PVADS.VERSION = "1.9.1"

-- Bind the Java side (table PVADSJ, exposed by ZombieBuddy) to the PVADS_* functions used everywhere.
-- On a dedicated server or without ZombieBuddy the table is absent and these stay nil (ADS disabled).
function PVADS.bindJava()
    if PVADS_available then return true end
    if not PVADSJ then return false end
    local J = PVADSJ
    PVADS_version = function() return J.version() end
    PVADS_available = function() return J.available() end
    PVADS_firstPerson = function() return J.firstPerson() end
    PVADS_canAds = function() return J.canAds() end
    PVADS_setWant = function(b) J.setWant(b) end
    PVADS_setDeveloper = function(b) J.setDeveloper(b) end
    PVADS_setSwayFactor = function(v) J.setSwayFactor(v) end
    PVADS_setOpticShape = function(m, h, l, w) J.setOpticShape(m, h, l, w) end
    PVADS_clearProfile = function() J.clearProfile() end
    PVADS_setProfile = function(t) J.setProfile(t) end
    PVADS_setSettings = function(t) J.setSettings(t) end
    PVADS_getState = function(t) return J.getState(t) end
    PVADS_setPipReticle = function(r, g, m, cr, cg, cb, br, d) J.setPipReticle(r, g, m, cr, cg, cb, br, d) end
    PVADS_probe = function() return J.probe() end
    PVADS_presenceTick = J.presenceTick and function() J.presenceTick() end or nil
    PVADS_getPresence = J.getPresence and function(t) return J.getPresence(t) end or nil
    PVADS_setScopeMag = J.setScopeMag and function(m, instant) J.setScopeMag(m, instant and true or false) end or nil
    PVADS_setZero = J.setZero and function(m) J.setZero(m) end or nil
    PVADS_setClickAim = J.setClickAim and function(b) J.setClickAim(b and true or false) end or nil
    PVADS_setAimAllowed = J.setAimAllowed and function(b, why) J.setAimAllowed(b and true or false, why and tostring(why) or "") end or nil
    PVADS_aimLocked = J.aimLocked and function() return J.aimLocked() == true end or nil
    PVADS_clearAimLock = J.clearAimLock and function() J.clearAimLock() end or nil
    PVADS_setSuspended = J.setSuspended and function(b) J.setSuspended(b and true or false) end or nil
    PVADS_viewOn = J.viewOn and function() return J.viewOn() == true end or nil
    PVADS_optionsReady = J.optionsReady and function() return J.optionsReady() == true end or nil
    PVADS_getOptions = J.getOptions and function(t) return J.getOptions(t) end or nil
    PVADS_optionsSignature = J.optionsSignature and function() return J.optionsSignature() end or nil
    -- 1.8.0 optic profiles (calibration keyed to the optic model + mount)
    PVADS_setOpticModelProfile = J.setOpticModelProfile and function(k, t) J.setOpticModelProfile(k, t) end or nil
    PVADS_opticKey = J.opticKey and function() return J.opticKey() or "" end or nil
    PVADS_opticLabel = J.opticLabel and function() return J.opticLabel() or "" end or nil
    PVADS_opticSource = J.opticSource and function() return J.opticSource() or "" end or nil
    PVADS_effective = J.effective and function(f) return J.effective(f) end or nil
    PVADS_userOpticSet = J.userOpticSet and function(f, v) return J.userOpticSet(f, v) == true end or nil
    PVADS_userOpticClear = J.userOpticClear and function() return J.userOpticClear() == true end or nil
    PVADS_userOpticUndo = J.userOpticUndo and function() return J.userOpticUndo() or "" end or nil
    PVADS_userOpticSave = J.userOpticSave and function() return J.userOpticSave() == true end or nil
    PVADS_userOpticDirty = J.userOpticDirty and function() return J.userOpticDirty() == true end or nil
    PVADS_userOpticFields = J.userOpticFields and function(t) return J.userOpticFields(t) end or nil
    PVADS_opticProfileFile = J.opticProfileFile and function() return J.opticProfileFile() or "?" end or nil
    -- 1.9.0 weapon rest and bipods
    PVADS_setBipod = J.setBipod and function(b) J.setBipod(b and true or false) end or nil
    PVADS_getRest = J.getRest and function(t) return J.getRest(t) end or nil
    -- 1.8.7 steady aim
    PVADS_setSteady = J.setSteady and function(b) J.setSteady(b and true or false) end or nil
    PVADS_getSteady = J.getSteady and function(t) return J.getSteady(t) end or nil
    -- 1.8.4 aim pitch sync (PVADS_AimSync.lua)
    PVADS_viewPitchDeg = J.viewPitchDeg and function() return J.viewPitchDeg() or 0 end or nil
    PVADS_setRemoteAim = J.setRemoteAim and function(id, p, a) J.setRemoteAim(id, p, a and true or false) end or nil
    return true
end
PVADS.bindJava()
PVADS.Families = PVADS.Families or {}
PVADS.Weapons = PVADS.Weapons or {}
PVADS.Optics = PVADS.Optics or {}
PVADS.OpticKinds = PVADS.OpticKinds or {}
PVADS.WeaponOptic = PVADS.WeaponOptic or {}
PVADS.Adapters = PVADS.Adapters or {}
PVADS.User = PVADS.User or {}
PVADS.Generated = PVADS.Generated or { weapons = {}, optics = {} }
PVADS.Registry = PVADS.Registry or { duplicates = {}, owners = {} }

local function copyInto(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            local t = {}
            for k2, v2 in pairs(v) do t[k2] = v2 end
            dst[k] = t
        else
            dst[k] = v
        end
    end
    return dst
end
PVADS.copyInto = copyInto

local function note(kind, key)
    local reg = PVADS.Registry
    local id = kind .. ":" .. tostring(key)
    if reg.owners[id] then table.insert(reg.duplicates, id) end
    reg.owners[id] = true
end

function PVADS.log(msg) print("[ProjectViewpoint] " .. tostring(msg)) end
function PVADS.dev(msg) if PVADS.developer then print("[ProjectViewpoint][dev] " .. tostring(msg)) end end

-- ---------------------------------------------------------------------------------------------- public API
--- Family defaults. Fields: adsTime, relief, fovMul, swayMul, recoilMul, kickMul, ironHeight, zero (m).
function PVADS.RegisterWeaponFamily(name, def)
    note("family", name)
    PVADS.Families[name] = copyInto(PVADS.Families[name] or {}, def)
end

--- Per-weapon profile. Any family field plus:
---   family, rear={x,y,z}, front={x,y,z} (iron sight points), adjX/adjY/adjZ/adjPitch/adjYaw/adjRoll,
---   noIrons=true (weapon has no usable irons; ADS needs an optic)
---   physical weapon presence (all optional; measured from the model when absent):
---   weaponLength (m, rear of stock/grip to muzzle), muzzleOffset (m added past the muzzle, e.g. a bayonet),
---   collisionRadius (m, half the barrel's width for the probe), compressedPoseScale (0.3..1.8, how far it gives way)
---   1.6.0: zeroLevels={25,50,100} (iron sight zeroing ranges, metres; {} = fixed irons)
function PVADS.RegisterWeaponProfile(fullType, def)
    note("weapon", fullType)
    PVADS.Weapons[fullType] = copyInto(PVADS.Weapons[fullType] or {}, def)
end

--- Optic item profile. Fields: kind ("iron"|"reflex"|"scope"), mag, reticle, height, window,
---   1.8.3: glassPoly = { x, z, x, z, ... } - outline of the glass as seen (convex, on the glass plane, same axes as glass);
---          glassVariants entries may carry poly = { ... } per mesh. The picture-in-picture window is clipped to it.
---   relief, fovMul, lensScale, windowScale, color={r,g,b}, zero (m; omit to keep the weapon's iron zero)
---   picture-in-picture calibration for every gun the optic sits on (1.7.5): pipX, pipY, pipZ, pipScale, pipZoom, pipRetX, pipRetY, pipDepth, pipCorner (1.7.9: red dot / holo window corner, 0 square .. 1 round)
---   1.6.0: zoomLevels={2,4,8} (variable scope: magnifications the wheel steps through, top = mag),
---          zeroLevels={25,50,100,200} (ranges the zeroing keys step through, metres; used with True Ballistics)
function PVADS.RegisterOpticProfile(fullType, def)
    note("optic", fullType)
    PVADS.Optics[fullType] = copyInto(PVADS.Optics[fullType] or {}, def)
end

--- 1.8.0: optic MODEL profile, keyed by the optic's model script name + the mount attachment it sits on
--- ("ReflexS2_Sight@reddot"; "Model@*" = any mount; "Model@mount@GunModel" only where one gun's mount sits differently).
--- Applies to every weapon the optic model is drawn on, over the weapon + optic values; the player's optic
--- calibration (calibrator) wins over it. Fields: adjX, adjY, adjZ, adjPitch, adjYaw, adjRoll, relief, fovMul,
--- opticHeight, lensScale, windowScale, pipX, pipY, pipZ, pipScale, pipZoom, pipRetX, pipRetY, pipDepth, pipCorner,
--- pipAspect, reticleRoll (deg), rear = {x,y,z} and front = {x,y,z} (the sight line in the optic's own model space).
PVADS.OpticModelProfiles = PVADS.OpticModelProfiles or {}
PVADS.opticModelDirty = true
function PVADS.RegisterOpticModelProfile(key, def)
    note("opticmodel", key)
    PVADS.OpticModelProfiles[string.lower(tostring(key))] = copyInto(PVADS.OpticModelProfiles[string.lower(tostring(key))] or {}, def)
    PVADS.opticModelDirty = true
end
--- Hands the optic model profiles to the Java side (again after new ones were registered).
function PVADS.pushOpticModelProfiles()
    if not PVADS.opticModelDirty or not PVADS_setOpticModelProfile then return end
    PVADS.opticModelDirty = false
    for k, def in pairs(PVADS.OpticModelProfiles) do PVADS_setOpticModelProfile(k, def) end
end

--- 1.8.0: the fields that belong to the optic (the same list as the Java side's OpticProfiles.FIELDS).
PVADS.OPTIC_FIELDS = {}
for _, k in ipairs({ "adjX", "adjY", "adjZ", "adjPitch", "adjYaw", "adjRoll", "relief", "fovMul", "opticHeight", "lensScale", "windowScale",
    "pipX", "pipY", "pipZ", "pipScale", "pipZoom", "pipRetX", "pipRetY", "pipDepth", "pipCorner", "pipAspect", "reticleRoll",
    "rearX", "rearY", "rearZ", "frontX", "frontY", "frontZ" }) do PVADS.OPTIC_FIELDS[k] = true end

--- Defaults for a whole optic kind ("iron", "reflex", "scope").
function PVADS.RegisterOpticKind(kind, def)
    PVADS.OpticKinds[kind] = copyInto(PVADS.OpticKinds[kind] or {}, def)
end

--- Override for one weapon wearing one optic (e.g. a scope that sits unusually high on one rifle).
--- opticType "" = the weapon's own iron sights (no optic attached), the same key the calibrator saves irons under;
--- unlike RegisterWeaponProfile these values do not carry over to the weapon's optics.
--- 1.7.17: iron sight values for one model of a weapon (one item id drawn with different models by different packs,
--- e.g. vanilla ids reused by Vanilla Firearms Expansion). def = { adjX, adjY, adjZ, adjPitch, adjYaw }.
--- Chosen on the Java side by the weapon's model mesh; a calibration for the weapon's irons wins.
PVADS.IronVariants = PVADS.IronVariants or {}
function PVADS.RegisterIronVariant(weaponType, mesh, def)
    note("ironvariant", weaponType .. "|" .. tostring(mesh))
    PVADS.IronVariants[weaponType] = PVADS.IronVariants[weaponType] or {}
    local e = copyInto({}, def); e.mesh = mesh
    table.insert(PVADS.IronVariants[weaponType], e)
end

function PVADS.RegisterWeaponOpticOverride(weaponType, opticType, def)
    note("weaponoptic", weaponType .. "|" .. opticType)
    PVADS.WeaponOptic[weaponType] = PVADS.WeaponOptic[weaponType] or {}
    PVADS.WeaponOptic[weaponType][opticType] = copyInto(PVADS.WeaponOptic[weaponType][opticType] or {}, def)
end

--- Adapter: function(weaponItem, profile, opticItemOrNil) that may edit the resolved profile in place.
function PVADS.RegisterADSAdapter(name, fn)
    note("adapter", name)
    PVADS.Adapters[name] = fn
end

-- ---------------------------------------------------------------------------------------------- resolution
local OPTIC_PART_TYPES = { Scope = true, Sight = true, Optic = true, L_Scope = true }   -- L_Scope: GaelGunStore side mounts

--- Returns the optic WeaponPart on the weapon (or nil) and its full type.
function PVADS.findOptic(weapon)
    if not weapon or not weapon.getAllWeaponParts then return nil end
    local parts = weapon:getAllWeaponParts()
    if not parts then return nil end
    local best
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part then
            local ft = part:getFullType()
            local known = PVADS.Optics[ft] or PVADS.Generated.optics[ft]
            if known then return part, ft end
            if OPTIC_PART_TYPES[part:getPartType() or ""] then best = part end
        end
    end
    if best then return best, best:getFullType() end
    return nil
end

local function guessFamily(weapon)
    local swing = weapon.getSwingAnim and weapon:getSwingAnim() or ""
    if swing == "Handgun" then return "pistol" end
    local n = string.lower(weapon:getFullType() .. " " .. (weapon:getDisplayName() or ""))
    if string.find(n, "shotgun") then return "shotgun" end
    if string.find(n, "sniper") then return "sniper" end
    return "carbine"
end

local function norm3(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return 0, 1, 0 end
    return x / l, y / l, z / l
end

--- Iron sight point + line from the best data available.
local function ironGeometry(p, gen, man, fam)
    local rear = (man and man.rear) or (gen and gen.rear)
    local front = (man and man.front) or (gen and gen.front)
    local length = (gen and gen.length) or 0.5
    if rear and front and front[2] > rear[2] then
        p.sx, p.sy, p.sz = rear[1], rear[2], rear[3]
        p.dx, p.dy, p.dz = norm3(front[1] - rear[1], front[2] - rear[2], front[3] - rear[3])
        p.ironSource = "rear+front"
    elseif front then
        p.sx, p.sy, p.sz = front[1], front[2] - 0.45 * length, front[3]
        p.dx, p.dy, p.dz = 0, 1, 0
        p.ironSource = "front post"
    else
        local m = (gen and (gen.muzzleEstimated or gen.muzzle)) or { 0, 0.3, 0.02 }
        local mount = gen and (gen.scopeMount or gen.reddotMount)
        local h = (fam.ironHeight or 0.035)
        p.sx, p.sy = m[1], m[2] * 0.25
        p.sz = mount and math.max(mount[3], m[3] + h) or (m[3] + h)
        p.dx, p.dy, p.dz = 0, 1, 0
        p.ironSource = "family default"
    end
end

--- Builds the flat profile table handed to Java (PVADS_setProfile).
function PVADS.ResolveProfile(weapon)
    local id = weapon:getFullType()
    local gen = PVADS.Generated.weapons[id]
    -- 1.7.7: a measured profile belongs to one model. GaelGunStore reuses the VFE packs' ids (Base.AK47 ...) with
    -- its own models, so with it active a profile measured on another model is not used for this gun.
    if gen and gen.model and PVADS.GaelGunStore and PVADS.GaelGunStore.active and weapon.getStaticModel then
        local sm = weapon:getStaticModel()
        if sm and sm ~= "" and string.lower(sm) ~= string.lower(gen.model) then gen = nil end
    end
    local man = PVADS.Weapons[id]
    local famName = (man and man.family) or (gen and gen.family) or guessFamily(weapon)
    local fam = PVADS.Families[famName] or PVADS.Families.carbine or {}

    local p = { weaponId = id, family = famName, mode = "iron", mag = 1, reticle = "none" }
    for _, k in ipairs({ "adsTime", "relief", "fovMul", "swayMul", "recoilMul", "kickMul", "zero", "climb", "side", "recover", "gunKick", "gunBack", "hipCone", "bead", "weaponLength", "muzzleOffset", "collisionRadius", "compressedPoseScale" }) do p[k] = fam[k] end
    ironGeometry(p, gen, man, fam)
    if man and type(man.zeroLevels) == "table" then p.zeroLevels = copyInto({}, man.zeroLevels) end
    -- physical weapon presence: the meshscan's length and muzzle (weapon units) as the second-best source
    if gen then
        p.genLength = gen.length
        p.genMuzzleY = (gen.muzzle and gen.muzzle[2]) or (gen.muzzleEstimated and gen.muzzleEstimated[2])
    end
    -- without hand-set sight points the Java side measures the irons on the mesh the game actually loaded
    p.ironAuto = not (man and (man.rear or man.front)) and true or false
    if man then
        for _, k in ipairs({ "adsTime", "relief", "fovMul", "swayMul", "recoilMul", "kickMul", "zero", "climb", "side", "recover", "gunKick", "gunBack", "hipCone", "bead", "adjX", "adjY", "adjZ", "adjPitch", "adjYaw", "adjRoll", "weaponLength", "muzzleOffset", "collisionRadius", "compressedPoseScale" }) do
            if man[k] ~= nil then p[k] = man[k] end
        end
    end

    -- weapon weight / power nudges (presentation only)
    local wgt = weapon.getWeight and weapon:getWeight() or 3
    p.swayMul = (p.swayMul or 1) * math.min(1.6, math.max(0.8, 0.85 + wgt * 0.05))
    local dmg = weapon.getMaxDamage and weapon:getMaxDamage() or 1.5
    p.recoilMul = (p.recoilMul or 1) * math.min(1.4, math.max(0.75, 0.8 + dmg * 0.12))   -- visible gun kick only

    -- optic
    local part, opticId = PVADS.findOptic(weapon)
    p.opticId = opticId
    if part then
        local og = PVADS.Generated.optics[opticId] or {}
        local kind = (PVADS.Optics[opticId] and PVADS.Optics[opticId].kind) or og.kind or "reflex"
        local od = copyInto(copyInto({}, PVADS.OpticKinds[kind]), PVADS.Optics[opticId])
        local model = gen and gen.opticModels and gen.opticModels[string.match(opticId, "[^%.]+$")]
        p.opticModel = model
        local shape = og.shapes and model and og.shapes[model]
        p.mode = (kind == "iron") and "reflex" or kind     -- flip-up iron parts are aligned like an optic (no reticle)
        p.mag = od.mag or og.mag or 1
        p.reticle = (od.reticles and model and od.reticles[model]) or od.reticle or "none"
        p.opticHeight = od.height or (shape and shape.height) or 0.03
        p.opticWindow = od.window or (shape and shape.window) or 0.012
        p.opticLength = (shape and shape.length) or 0.12
        if od.relief then p.relief = od.relief end
        if od.fovMul then p.fovMul = od.fovMul end
        if kind ~= "iron" and od.zero then p.zero = od.zero end
        if type(od.zoomLevels) == "table" then p.zoomLevels = copyInto({}, od.zoomLevels) end
        if kind ~= "iron" and type(od.zeroLevels) == "table" then p.zeroLevels = copyInto({}, od.zeroLevels) end
        if od.glass then   -- open sight's glass in its own mesh space: { x0, x1, z0, z1, y, round }
            p.glassX0, p.glassX1, p.glassZ0, p.glassZ1, p.glassY = od.glass[1], od.glass[2], od.glass[3], od.glass[4], od.glass[5]
            p.glassRound = od.glass[6] and true or false
        end
        -- 1.7.12: glass per model mesh, chosen on the Java side by the mesh the optic is drawn with
        if type(od.glassVariants) == "table" then p.glassVariants = od.glassVariants end
        if type(od.glassPoly) == "table" then p.glassPoly = od.glassPoly end     -- 1.8.3: outline of the glass as seen
        p.lensScale = od.lensScale or 1
        p.windowScale = od.windowScale or 1
        -- 1.7.5: picture-in-picture calibration can belong to the optic itself (every gun it sits on);
        -- a weapon + optic override below still wins
        for _, k in ipairs({ "pipX", "pipY", "pipZ", "pipScale", "pipZoom", "pipRetX", "pipRetY", "pipDepth", "pipCorner", "pipAspect", "pipSpeed", "pipMove" }) do
            if od[k] ~= nil then p[k] = od[k] end
        end
        p.color = od.color
        if kind == "scope" then p.swayMul = p.swayMul * (od.swayMul or 1) end
        local wo = PVADS.WeaponOptic[id] and PVADS.WeaponOptic[id][opticId]
        if wo then copyInto(p, wo) end
        -- 1.7.12: a weapon + optic override that sets PiP values keeps the per-mesh glass variants' own values out
        if wo and (wo.pipScale ~= nil or wo.pipX ~= nil or wo.pipY ~= nil or wo.pipCorner ~= nil or wo.pipAspect ~= nil) then p.pipLocked = true end
    elseif man and man.noIrons then
        p.noIrons = true
    end
    if not part then   -- iron sights: calibration registered for this weapon's irons only (optic key "")
        local wi = PVADS.WeaponOptic[id] and PVADS.WeaponOptic[id][""]
        if wi then copyInto(p, wi) end
        if PVADS.IronVariants[id] then
            p.ironVariants = PVADS.IronVariants[id]
            if wi and (wi.adjX or wi.adjY or wi.adjZ or wi.adjPitch or wi.adjYaw) then p.ironLocked = true end
        end
    end

    for name, fn in pairs(PVADS.Adapters) do
        local ok, err = pcall(fn, weapon, p, part)
        if not ok then PVADS.log("adapter '" .. tostring(name) .. "' failed: " .. tostring(err)) end
    end

    -- the player's own calibration wins
    local u = PVADS.User[id .. "|" .. tostring(opticId or "")]
    if u and part then
        -- 1.8.0: with an optic, the optic's own values are the optic's: an old per-weapon calibration of them goes to
        -- the Java side separately (it is moved to the optic's calibration there, see OpticProfiles); the rest as before
        local uw, other = nil, {}
        for k, v in pairs(u) do
            if PVADS.OPTIC_FIELDS[k] then uw = uw or {}; uw[k] = v else other[k] = v end
        end
        copyInto(p, other)
        p.userWeapon = uw
    elseif u then
        copyInto(p, u)
        if u.adjX ~= nil or u.adjY ~= nil or u.adjZ ~= nil or u.adjPitch ~= nil or u.adjYaw ~= nil then p.ironLocked = true end
        if u.pipScale ~= nil or u.pipX ~= nil or u.pipY ~= nil or u.pipCorner ~= nil or u.pipAspect ~= nil then p.pipLocked = true end
    end
    -- Sniper-class weapons (including bolt-action and historical rifles) always use a tighter ADS view.
    -- Apply this after optic, adapter, and player calibration values so every sniper profile is exactly 0.70.
    if famName == "sniper" then
        p.fovMul = 0.70
    end
    return p
end

--- Key used by the calibrator / user file for the current weapon+optic.
function PVADS.userKey(weapon)
    local _, opticId = PVADS.findOptic(weapon)
    return weapon:getFullType() .. "|" .. tostring(opticId or "")
end

return PVADS
