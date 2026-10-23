require "VAT/VAT_Client"
require "VAT/VAT_Compat"
require "VAT/VAT_Effects"
require "VAT/VAT_Launchers"

--[[
Gunworks gang framework (Guns of Marz): grenade launchers and other ammo-launched ordnance under
Viewpoint.

How the framework fires a 40 mm round (verified in its sources):
  * shared WeaponSystems/Hooks/CustomSystemHooks.lua, Hook.Attack: a round registered with
    OrdnanceFactory.RegisterAmmo marks the gun (modData GWG_FiringExplosiveAmmo) and is consumed;
  * client ExplosivesSystems/Client.lua, OnWeaponSwingHitPoint: the target is the MOUSE on the
    isometric screen (screenToIsoX/Y(getMouseX(), getMouseY())), sent to the server ("throwOrdnance");
  * the server flies the round with its own physics and detonates it (Payloads.Detonate: an IsoTrap
    from the round's parentItem stats), and every client draws it with Render3DItem.
Under Viewpoint the mouse is pinned to the middle of the screen, which in the isometric projection
is the player, so every round went to the shooter's feet; and Viewpoint never draws Render3DItem, so
the round was invisible.

What this file does:
  * launchers: a grenade round fired from a gun (M79, M203 underbarrel, any round registered as
    ordnance) is fired as this mod's own projectile (VAT_Launchers.lua, server "launch"): out of the
    muzzle toward the crosshair, its model drawn in flight, impact fuse, explosion through the game's
    IsoTrap with the round's explosion stats and the 3D effects. The framework's own launch is not
    used for it, and the gun's own shot carries the round's stats (no pellets);
  * aim fallback: when this mod cannot launch a round, the framework's own handler runs with the
    crosshair point in place of the mouse point (the two isometric screen functions it calls are
    answered with the crosshair target for the duration of that one call);
  * sight: the framework's thrown ordnance in flight is drawn inside Viewpoint's 3D scene;
  * effects: every explosion is an IsoTrap, so this mod's 3D explosion / fire effects, lights and
    fire damage apply as for any explosive.
]]

VAT.CompatGunworks = VAT.CompatGunworks or {}
local G = VAT.CompatGunworks
local Log = VAT.Log
local S = VAT.S
local E = VAT.Effects

G.VISUAL_BASE = 800000          -- visual ids for the framework's rounds (ours count up from 1)
G.FAR = 60                      -- tiles along the crosshair when it points at nothing

local ES, OF
local original
local installed = false
local override = nil            -- { x, y } while the framework's handler runs for a Viewpoint shot

-- ------------------------------------------------------------------ aim
local function viewpointShooter(player)
    if not player or not player:isLocalPlayer() then return false end
    return VAT_viewpointActive and VAT_viewpointActive(player) and true or false
end

local aim = {}
--- The world point under the crosshair (x, y in tiles), or a point far along it.
function G.crosshairTarget(maxDist)
    if not (VAT_getAim and VAT_getAim(aim)) then return nil end
    local tx, ty
    if aim.hit and aim.tx then
        tx, ty = aim.tx, aim.ty
    else
        local d = maxDist or G.FAR
        local fl = math.sqrt(aim.fx * aim.fx + aim.fy * aim.fy)
        if fl < 1e-4 then return nil end
        tx, ty = aim.cx + aim.fx / fl * d, aim.cy + aim.fy / fl * d
    end
    return tx, ty
end

local realScreenToIsoX, realScreenToIsoY

G.reports = 0                   -- launcher shots reported at info level (the first G.REPORTS)
G.REPORTS = 12

local function report(fmt, ...)
    if G.reports < G.REPORTS then
        G.reports = G.reports + 1
        Log.info(fmt, ...)
    else
        Log.debug(fmt, ...)
    end
end

local function ammoKey(weapon)
    local ok, k = pcall(function()
        local t = weapon:getAmmoType()
        return t and t:getItemKey()
    end)
    return ok and k or nil
end

--- The round this shot launches, and how it was found:
---   "marked"     the framework's attack hook marked it (GWG_FiringExplosiveAmmo);
---   "ammo type"  no mark and no per-round list left: the gun's ammo type, which the framework sets to
---                the round it fires (a gun loaded without the framework's reload, or a mod in the
---                attack hook chain that lost the mark);
---   "unlimited"  unlimited ammo and nothing loaded: the first grenade round the gun takes (its family
---                order, HE before incendiary for the 40 mm), so a launcher still launches grenades.
--- A gun with a buckshot round loaded fires buckshot (nil, "not ordnance").
function G.roundFor(weapon, player)
    local LA = VAT.Launchers
    local md = weapon:getModData()
    local ammo = md and md.GWG_FiringExplosiveAmmo
    if ammo then return ammo, "marked" end
    if md and md.AmmoList and #md.AmmoList > 0 then return nil, "list" end
    local key = ammoKey(weapon)
    if key and OF.IsAmmoRegistered and OF.IsAmmoRegistered(key) then return key, "ammo type" end
    local unlimited = player and player.isUnlimitedAmmo and player:isUnlimitedAmmo()
    if unlimited and weapon:getCurrentAmmoCount() <= 0 then
        local rounds = LA.roundsFor(weapon)
        if rounds[1] then return rounds[1], "unlimited" end
    end
    return nil, "not ordnance"
end

local function launcherWeapon(weapon)
    -- a gun whose ammo family holds a registered round (M79, M203 underbarrel, ...)
    if #VAT.Launchers.roundsFor(weapon) > 0 then return true end
    local key = ammoKey(weapon)
    if key ~= nil and OF.IsAmmoRegistered and OF.IsAmmoRegistered(key) then return true end
    local ft = string.lower(tostring(weapon:getFullType()))
    return string.find(ft, "m79", 1, true) ~= nil or string.find(ft, "m203", 1, true) ~= nil
        or string.find(ft, "launcher", 1, true) ~= nil
end
G.launcherWeapon = launcherWeapon

-- ------------------------------------------------------------------ launching the grenade ourselves
local hand = {}

--- Muzzle point and launch velocity for a round fired by this player now.
function G.launchFor(player, round)
    local LA = VAT.Launchers
    local cfg = VAT.Config.server()
    local speed = LA.speed(round)
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local okAim = VAT_getAim and VAT_getAim(aim)
    local fx, fy, fh, cx, cy, ch
    if okAim then
        fx, fy, fh, cx, cy, ch = aim.fx, aim.fy, aim.fh, aim.cx, aim.cy, aim.ch
    else
        local a = math.rad(player:getDirectionAngle() or 0)
        fx, fy, fh = math.cos(a), math.sin(a), 0
        cx, cy, ch = px, py, pz * S + 1.55
    end
    local fl = math.sqrt(fx * fx + fy * fy + fh * fh)
    if fl < 1e-6 then fx, fy, fh, fl = 1, 0, 0, 1 end
    fx, fy, fh = fx / fl, fy / fl, fh / fl
    -- the muzzle: in front of the hands along the aim (a launcher's barrel is about 0.6 m beyond them)
    local ox, oy, oh
    if VAT_getHand and VAT_getHand(player, hand) then
        ox, oy, oh = hand.x + fx * 0.6, hand.y + fy * 0.6, hand.h + fh * 0.6
    else
        local hl = math.sqrt(fx * fx + fy * fy)
        local hx, hy = hl > 1e-4 and fx / hl or 1, hl > 1e-4 and fy / hl or 0
        ox, oy, oh = px + hx * 0.85, py + hy * 0.85, pz * S + 1.4 + fh * 0.6
    end
    -- never in front of a wall the shooter is pressed against
    local def = LA.def(round)
    local cx2, cy2, ch2 = VAT.Physics.clearPath(def, px, py, pz * S + 1.3, ox, oy, oh)
    ox, oy, oh = cx2, cy2, ch2
    -- straight out of the barrel along the line of sight: no aim assist and no drop compensation, the
    -- shooter raises the launcher for distance. Sights are "zeroed" where the crosshair line is 25 m
    -- out, so the small offset between eye and muzzle does not throw the round sideways.
    local zx, zy, zh = cx + fx * LA.ZERO, cy + fy * LA.ZERO, ch + fh * LA.ZERO
    local dx, dy, dh = zx - ox, zy - oy, zh - oh
    local dl = math.sqrt(dx * dx + dy * dy + dh * dh)
    if dl < 1e-3 then dx, dy, dh, dl = fx, fy, fh, 1 end
    local vx, vy, vh = dx / dl * speed, dy / dl * speed, dh / dl * speed
    local tx, ty, arced = nil, nil, false
    return { ox = ox, oy = oy, oh = oh, vx = vx, vy = vy, vh = vh, phase = "air" }, tx, ty, arced
end

--- Fires `round` out of `weapon` as this mod's projectile: predicted at once, the server decides.
function G.launch(player, weapon, round)
    local LA = VAT.Launchers
    local def = LA.def(round)
    if not def then return false end
    local launch, tx, ty, arced = G.launchFor(player, round)
    local CL = VAT.Client
    local seq = CL.nextSeq()
    if isClient() then
        local proj = VAT.Projectiles.spawn(def, launch, {
            id = -seq, authority = false, predicted = true, seq = seq, mode = VAT.MODE_OVERHAND,
            fullType = LA.visualType(round), round = round, ownerObj = player, ownerKey = "me",
            mass = def.mass, createdAt = VAT.nowSeconds(),
        })
        CL.pending[seq] = proj
    end
    VAT.Net.toServer(player, "launch", {
        s = seq, w = weapon:getID(), r = round,
        ox = launch.ox, oy = launch.oy, oh = launch.oh, vx = launch.vx, vy = launch.vy, vh = launch.vh,
    })
    local px, py = player:getX(), player:getY()
    local hv = math.sqrt(launch.vx * launch.vx + launch.vy * launch.vy)
    report("Launched %s from %s at %.0f m/s, barrel elevation %.1f degrees", round, tostring(weapon:getFullType()),
        VAT.len3(launch.vx, launch.vy, launch.vh), math.deg(math.atan2(launch.vh, hv)))
    return true
end

local function wrapped(player, weapon)
    if not player or not weapon or not player.isLocalPlayer or not player:isLocalPlayer() then
        return original(player, weapon)
    end
    local isRanged = weapon.isRanged and weapon:isRanged()
    local md = weapon.getModData and weapon:getModData()
    local thrown = OF.IsRegistered and OF.IsRegistered(weapon:getFullType())
    local ammo, how = nil, "-"
    if isRanged and not thrown then ammo, how = G.roundFor(weapon, player) end
    local vp = viewpointShooter(player)
    if isRanged and (ammo or launcherWeapon(weapon)) then
        report("Gunworks launcher %s fired: round %s (%s), Viewpoint %s",
            tostring(weapon:getFullType()), tostring(ammo), how, vp and "on" or "off")
    end
    -- a grenade round: this mod fires the grenade, the framework's own launch is not used
    if ammo and VAT.Launchers.def(ammo) and VAT.Config.server().Enabled then
        if md then md.GWG_FiringExplosiveAmmo = nil end
        -- the gun's own shot carries the round's stats (no pellets, no hits); with True Ballistics the
        -- round's inert profile applies (both read the gun's ammo type, set here before they run)
        if how ~= "marked" then VAT.Launchers.setGunRound(weapon, ammo) end
        local ok, err = pcall(G.launch, player, weapon, ammo)
        if ok and err then return end
        Log.warn("Launching %s failed (%s); the framework launches it", tostring(ammo), tostring(err))
        if md then md.GWG_FiringExplosiveAmmo = ammo end
    end
    if not vp then return original(player, weapon) end
    local params
    if ammo and OF.GetAmmoParams then params = OF.GetAmmoParams(ammo) end
    if not params and OF.GetParams then params = OF.GetParams(weapon:getFullType()) end
    if not params then return original(player, weapon) end
    local tx, ty = G.crosshairTarget(params.maxThrowDist)
    if not tx then
        -- no aim snapshot this frame: straight ahead of the body, at the reach
        local ok, a = pcall(function() return math.rad(player:getDirectionAngle() or 0) end)
        local d = math.min(params.maxThrowDist or 20, G.FAR)
        if ok and a then tx, ty = player:getX() + math.cos(a) * d, player:getY() + math.sin(a) * d end
    end
    if not tx then return original(player, weapon) end
    -- the handler adds params.aimOffset to the screen point; take it back off so the crosshair is exact
    local off = params and params.aimOffset or 0
    override = { x = tx - off, y = ty - off }
    realScreenToIsoX, realScreenToIsoY = screenToIsoX, screenToIsoY
    screenToIsoX = function(...) return override and override.x or realScreenToIsoX(...) end
    screenToIsoY = function(...) return override and override.y or realScreenToIsoY(...) end
    local ok, err = pcall(original, player, weapon)
    screenToIsoX, screenToIsoY = realScreenToIsoX, realScreenToIsoY
    override = nil
    if not ok then Log.warn("Gunworks launch failed: %s", tostring(err)) end
end

--- Diagnostics only: what a launcher's trigger pull saw (whether the gun could shoot, the round on
--- top, True Ballistics' bullets still in the air). Nothing is changed here.
function G.onSwing(player, weapon)
    if not player or not weapon or not player.isLocalPlayer or not player:isLocalPlayer() then return end
    if not (weapon.isRanged and weapon:isRanged()) or not launcherWeapon(weapon) then return end
    if G.reports >= G.REPORTS then return end
    local md = weapon:getModData()
    local list = md and md.AmmoList
    local top = list and #list > 0 and list[#list] or nil
    local can = "?"
    if ISReloadWeaponAction and ISReloadWeaponAction.canShoot then
        local ok, v = pcall(ISReloadWeaponAction.canShoot, player, weapon)
        can = ok and tostring(v) or "error"
    end
    local pending = VTB_pendingRounds and VTB_pendingRounds() or nil
    report("Gunworks launcher %s trigger: rounds %d, next round %s, mark %s, can shoot %s, True Ballistics bullets in flight %s",
        tostring(weapon:getFullType()), weapon:getCurrentAmmoCount(), tostring(top),
        tostring(md and md.GWG_FiringExplosiveAmmo), can, tostring(pending))
end

function G.install()
    if installed then return true end
    OF = VAT.Compat.ordnanceFactory and VAT.Compat.ordnanceFactory()
    if not OF then return false end
    local ok, mod = pcall(require, "ExplosivesSystems/Physics")
    if not ok or type(mod) ~= "table" or type(mod.onWeaponSwingHitPoint) ~= "function" then
        Log.info("Gunworks framework found but its launcher hook is not; launchers keep their own aim")
        return false
    end
    ES = mod
    original = ES.onWeaponSwingHitPoint
    Events.OnWeaponSwingHitPoint.Remove(original)
    Events.OnWeaponSwingHitPoint.Add(wrapped)
    if Events.OnWeaponSwing then Events.OnWeaponSwing.Add(G.onSwing) end
    installed = true
    Log.info("Gunworks launchers: aimed with Viewpoint's crosshair, rounds drawn in 3D")
    return true
end

-- ------------------------------------------------------------------ rounds in flight, in 3D
local shown = {}                -- ordnanceId -> { x, y, z } last drawn point

local function itemType(v)
    local ok, ft = pcall(function() return v.itemObj and v.itemObj:getFullType() end)
    return ok and ft or nil
end

function G.pushVisuals()
    if not ES or not VAT_setVisual then return end
    local list = ES.visualOrdnance
    if type(list) ~= "table" then return end
    local seen = {}
    for i = 1, #list do
        local v = list[i]
        local sq = v.square
        local ft = itemType(v)
        if sq and ft and v.ordnanceId then
            local x, y, z = sq:getX() + (v.x or 0), sq:getY() + (v.y or 0), sq:getZ() + (v.z or 0)
            -- turned along the flight: yaw from the horizontal velocity, pitch from the vertical one
            -- the framework's units: x/y advance velocity * 0.10 and z (levels) velocity * 0.05 per
            -- step (ExplosivesSystems XY_STEP / Z_STEP), so in metres vertical = vz * 0.5 * S per vx
            local vx, vy, vz = v.velocityX or 0, v.velocityY or 0, (v.velocityZ or 0) * 0.5 * S
            local yaw = v.rotation or 0
            local pitch = 0
            if v.params and v.params.directProjectile then
                local hv = math.sqrt(vx * vx + vy * vy)
                if hv > 1e-5 then
                    yaw = math.deg(math.atan2(vy, vx))
                    pitch = -math.deg(math.atan2(vz, hv))
                end
            end
            local id = G.VISUAL_BASE + v.ordnanceId
            VAT_setVisual(id, ft, x, y, z, yaw, pitch, 0)
            seen[v.ordnanceId] = true
            local s = shown[v.ordnanceId]
            if not s then s = {}; shown[v.ordnanceId] = s end
            s.x, s.y, s.z = x, y, z
        end
    end
    for id, s in pairs(shown) do
        if not seen[id] then
            -- gone: it went off (or came to rest as a world item); the effect uses this point
            if VAT_removeVisual then VAT_removeVisual(G.VISUAL_BASE + id) end
            if E and E.note then E.note(s.x, s.y, s.z * S) end
            shown[id] = nil
        end
    end
end

Events.OnGameStart.Add(function()
    local ok, err = pcall(G.install)
    if not ok then Log.warn("Gunworks compatibility off: %s", tostring(err)) end
end)

Events.OnTick.Add(function()
    if not installed then return end
    local ok, err = pcall(G.pushVisuals)
    if not ok then Log.once("gunworks.visuals", "Gunworks rounds not drawn: %s", tostring(err)) end
end)
