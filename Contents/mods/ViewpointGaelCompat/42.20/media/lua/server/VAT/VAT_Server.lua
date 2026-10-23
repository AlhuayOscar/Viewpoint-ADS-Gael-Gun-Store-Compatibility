require "VAT/VAT_Projectiles"
require "VAT/VAT_Net"
require "VAT/VAT_Effects"
require "VAT/VAT_Launchers"

--[[
Server authority (also runs in single player, where it is called directly).

A throw request is validated against the server's own state before anything exists in the world:
  - the server option is on, the player exists, is alive, not in a vehicle
  - the item is in the player's main inventory, by id, and the SERVER's registry says it is throwable
  - cooldown and in-flight limits per player
  - release point near the player's body and not reached through a wall
  - launch speed within what that item and throw style can produce (+ momentum allowance)
  - cooked fuse only for items defined as cookable, clamped below the full fuse
Out-of-range values are clamped (smooth for honest players with latency); an impossible request is
rejected and the client gets its item back in hand. The item leaves the inventory here, once, so
nothing can be duplicated by replaying or racing requests.

The authoritative projectile then runs the shared simulation. Only important results are sent:
spawn, a 2 Hz correction while moving, and the end (detonation/landing/break). World effects use the
game's own systems: IsoTrap for explosives/fire/smoke/noise, world items for landed objects,
IsoWindow.smashWindow for glass, WorldSoundManager for zombie attraction, Hit() for impact damage.
]]

VAT.Server = VAT.Server or {}
local SV = VAT.Server
local M = VAT.Projectiles
local R = VAT.Registry
local N = VAT.Net
local Log = VAT.Log
local S = VAT.S

SV.nextId = SV.nextId or 1
SV.lastThrow = SV.lastThrow or {}       -- ownerKey -> seconds
SV.seenSeq = SV.seenSeq or {}           -- ownerKey -> highest accepted seq (replay protection)
SV.SYNC_EVERY = 15                      -- steps between corrections (0.5 s)
SV.REACH = 1.35                         -- metres from the body centre a release point may be
SV.MOMENTUM_ALLOWANCE = 7.5             -- m/s of thrower speed accepted for momentum

local function ownerKey(player)
    -- by account, not online id: online ids are reused after a disconnect
    if isServer() then return "u" .. tostring(player:getUsername()) end
    return "p" .. tostring(player:getPlayerNum())
end

local function num(v) return VAT.finite(v) and v or nil end

--[[
Item ids are random 32-bit ints (InventoryItemFactory: Rand.Next(2146250223) + 1233423, so up to
~2.15e9). num() above is for coordinates and speeds and refuses anything past 1e9, which in 1.0.1 threw
away the id of about half of all items: those throws were rejected as "item". Ids get their own check.
]]
local function itemIdOf(v)
    if type(v) ~= "number" or v ~= v then return nil end
    if v < -2147483648 or v > 2147483647 or math.floor(v) ~= v then return nil end
    return v
end

local function reject(player, args, reason, detail)
    Log.info("Server rejected throw: player=%s seq=%s reason=%s%s", tostring(player and player:getUsername()),
        tostring(args and args.s), reason, detail and (" (" .. detail .. ")") or "")
    N.toOne(player, "reject", { s = args and args.s or -1, r = reason, d = detail })
end

local bareHands
local function hitWeapon(proj)
    if proj.item and instanceof(proj.item, "HandWeapon") then return proj.item end
    if not bareHands then bareHands = VAT.createItem("Base.BareHands") end
    return bareHands
end

--- Removes exactly one throwable from the player and returns the item that will fly.
local function takeOne(player, item)
    local inv = player:getInventory()
    if instanceof(item, "HandWeapon") and item:getCurrentUses() > 1 then
        local single = VAT.createItem(item:getFullType())
        if not single then return nil end
        item:setCurrentUses(item:getCurrentUses() - 1)
        syncItemFields(player, item)
        return single
    end
    if player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item then
        player:removeFromHands(item)
    end
    -- the item may sit in a worn bag or rig: remove it from the container that actually holds it
    local container = item:getContainer() or inv
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    return item
end

--[[
Finds the item the client asked to throw. The id is the normal path. As a safety net for an id the
server does not know (an item created on the client only, or an inventory that fell out of sync), the
server falls back to an item of the same type the player really carries, so one bad id cannot block
every later throw. The lookup is, in order:
  1. the id, anywhere in the player's inventory tree (main inventory, worn bags, rigs);
  2. the item in the primary or secondary hand, when it is of the requested type;
  3. the first item of the requested type anywhere in the player's inventory tree.
All three only ever return an item the player really carries on the server, so nothing can be thrown
that the player does not have. Returns item, how ("id" | "hand" | "type") or nil, reason detail.
]]
function SV.findItem(player, args)
    local inv = player:getInventory()
    local ft = type(args.ft) == "string" and args.ft or nil
    local itemId = itemIdOf(args.i)
    local item = itemId and inv:getItemById(itemId) or nil
    if item then
        if ft and item:getFullType() ~= ft then return nil, nil, "type mismatch" end
        return item, "id"
    end
    if not ft then return nil, nil, "id " .. tostring(args.i) .. " not carried" end
    local hands = { player:getPrimaryHandItem(), player:getSecondaryHandItem() }
    for i = 1, 2 do
        local h = hands[i]
        if h and h:getFullType() == ft then return h, "hand" end
    end
    item = inv:getFirstTypeRecurse(ft)
    if item then return item, "type" end
    return nil, nil, "no " .. ft .. " carried (id " .. tostring(args.i) .. ")"
end

-- ------------------------------------------------------------------ throw request
function SV.handleThrow(player, args)
    if not player or type(args) ~= "table" then return end
    local cfg = VAT.Config.server()
    if not cfg.Enabled then return reject(player, args, "disabled") end
    local droppedCooked = num(args.m) == VAT.MODE_DROP and (num(args.k) or 0) > 0
    if player:isDead() and not droppedCooked then return reject(player, args, "dead") end
    if player:getVehicle() ~= nil then return reject(player, args, "vehicle") end

    local key = ownerKey(player)
    local seq = num(args.s) or -1
    local now = VAT.nowSeconds()
    if cfg.ServerValidation then
        local last = SV.seenSeq[key]
        if last and (seq == last or (seq < last and SV.lastThrow[key] and now - SV.lastThrow[key] < 10)) then
            return reject(player, args, "replay")
        end
        if SV.lastThrow[key] and now - SV.lastThrow[key] < cfg.ThrowCooldown * 0.8 then return reject(player, args, "cooldown") end
        if M.countForOwner(key) >= cfg.MaxActivePerPlayer then return reject(player, args, "limit") end
    end

    local item, found, why = SV.findItem(player, args)
    if not item then return reject(player, args, "item", why) end
    if found ~= "id" then
        Log.info("Throw seq=%s: client item id %s unknown to the server, using the %s carried (%s, id %s)",
            tostring(args.s), tostring(args.i), found == "hand" and "one in hand" or "first one", item:getFullType(), tostring(item:getID()))
    end
    local def = R.resolve(item)
    if not def then return reject(player, args, "notThrowable", item:getFullType()) end
    local handOk, secondary, useSecondary = R.otherHandOk(player, item)
    if not handOk then return reject(player, args, "requirement", "needs its other-hand item (e.g. a lighter)") end

    local mode = math.floor(num(args.m) or VAT.MODE_OVERHAND)
    if mode < VAT.MODE_OVERHAND or mode > VAT.MODE_DROP then mode = VAT.MODE_OVERHAND end
    if mode == VAT.MODE_UNDERHAND and not cfg.EnableUnderhand then mode = VAT.MODE_OVERHAND end
    if mode == VAT.MODE_ROLL and not cfg.EnableRolling then mode = VAT.MODE_UNDERHAND end

    local ox, oy, oh = num(args.ox), num(args.oy), num(args.oh)
    local vx, vy, vh = num(args.vx), num(args.vy), num(args.vh)
    if not (ox and oy and oh and vx and vy and vh) then return reject(player, args, "malformed") end

    local mass = R.massOf(item, def)
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local chestH = pz * S + 1.25
    if cfg.ServerValidation then
        -- release point: within reach of the body, at a height a hand can be
        local dx, dy = ox - px, oy - py
        local reach = SV.REACH + math.min(1.0, VAT.len3(num(args.px) or 0, num(args.py) or 0, 0) * 0.15)
        local d = math.sqrt(dx * dx + dy * dy)
        if d > reach * 2.5 or oh < pz * S - 0.5 or oh > pz * S + 2.6 then
            return reject(player, args, "origin", string.format("%.2f m away", d))
        end
        if d > reach then
            ox, oy = px + dx / d * reach, py + dy / d * reach
        end
        oh = VAT.clamp(oh, pz * S + 0.05, pz * S + 2.3)
        -- a hand pushed through a wall does not release on the other side
        local cx, cy, ch, blocked = VAT.Physics.clearPath(def, px, py, chestH, ox, oy, oh)
        if blocked then ox, oy, oh = cx, cy, ch end

        -- speed: at most what this item and style can do, plus the thrower's own movement
        local maxV = VAT.Solver.maxSpeed(def, mode, cfg, mass) * 1.06 + SV.MOMENTUM_ALLOWANCE * cfg.MomentumInfluence + 0.25
        local sp = VAT.len3(vx, vy, vh)
        if sp > maxV * 1.6 then return reject(player, args, "speed", string.format("%.1f > %.1f", sp, maxV)) end
        if sp > maxV then
            local k = maxV / sp
            vx, vy, vh = vx * k, vy * k, vh * k
        end
    end

    local cooked = 0
    if def.cookable and cfg.AllowCooking and def.fuse.type == "timed" then
        cooked = VAT.clamp(num(args.k) or 0, 0, (def.fuse.seconds or 3) * 0.9)
    elseif droppedCooked and player:isDead() then
        return reject(player, args, "dead")
    end
    if mode == VAT.MODE_DROP then vx, vy, vh = 0, 0, 0 end

    local flying = takeOne(player, item)
    if not flying then return reject(player, args, "item", "split failed") end
    if useSecondary and secondary then secondary:UseAndSync() end        -- vanilla: the lighter is used

    local id = SV.nextId
    SV.nextId = SV.nextId + 1
    local launch = { ox = ox, oy = oy, oh = oh, vx = vx, vy = vy, vh = vh, phase = (mode == VAT.MODE_ROLL) and "roll" or "air" }
    local proj = M.spawn(def, launch, {
        id = id, authority = true, seq = seq, mode = mode, item = flying, fullType = flying:getFullType(),
        ownerObj = player, ownerKey = key, ownerOnline = isServer() and player:getOnlineID() or -1,
        cooked = cooked, mass = mass, local_ = not isClient() and not isServer(),
    })
    proj.mass = mass
    SV.lastThrow[key] = now
    SV.seenSeq[key] = seq

    Log.info("Projectile created: id=%d %s by %s mode=%s speed=%.1f source=%s", id, proj.fullType,
        tostring(player:getUsername()), VAT.MODE_NAMES[mode] or "?", VAT.len3(vx, vy, vh), tostring(def.source))
    N.toAll("spawn", {
        id = id, s = seq, p = proj.ownerOnline, ft = proj.fullType, m = mode, ms = mass,
        ri = itemIdOf(args.i), ci = item:getID(),
        x = ox, y = oy, h = oh, vx = vx, vy = vy, vh = vh, ph = launch.phase, f = proj.fuseLeft,
    })
end

N.serverHandlers.throw = SV.handleThrow

-- ------------------------------------------------------------------ launched grenades (VAT_Launchers)
--[[
"launch" { s seq, w gunId, r round, ox oy oh muzzle, vx vy vh }
The gun's own shot is the vanilla one (it takes the round out of the gun and makes the sound); this
only adds the grenade it fires. Checked here: the gun is the one in the player's hands, is a firearm
that chambers this round, has a round (or the player has unlimited ammo), the muzzle is at the body,
the speed is the round's launch speed, and one player cannot launch faster than a launcher reloads.
]]
SV.lastLaunch = SV.lastLaunch or {}

local function rejectLaunch(player, args, reason, detail)
    Log.info("Server rejected launch: player=%s seq=%s reason=%s%s", tostring(player and player:getUsername()),
        tostring(args and args.s), reason, detail and (" (" .. detail .. ")") or "")
    N.toOne(player, "reject", { s = args and args.s or -1, r = reason, d = detail })
end

function SV.handleLaunch(player, args)
    if not player or type(args) ~= "table" then return end
    local LA = VAT.Launchers
    local cfg = VAT.Config.server()
    if not cfg.Enabled then return rejectLaunch(player, args, "disabled") end
    if player:isDead() then return rejectLaunch(player, args, "dead") end
    if player:getVehicle() ~= nil then return rejectLaunch(player, args, "vehicle") end
    local round = type(args.r) == "string" and args.r or nil
    local def = round and LA.def(round)
    if not def then return rejectLaunch(player, args, "notOrdnance", tostring(round)) end

    local gun = player:getPrimaryHandItem()
    local gunId = itemIdOf(args.w)
    if not gun or not instanceof(gun, "HandWeapon") or not gun:isRanged() then return rejectLaunch(player, args, "gun", "no firearm in hand") end
    if gunId and gun:getID() ~= gunId then
        Log.info("Launch seq=%s: gun id %s differs from the one in hand (%s), using the one in hand", tostring(args.s), tostring(gunId), tostring(gun:getID()))
    end
    if not LA.gunTakes(gun, round) then return rejectLaunch(player, args, "gun", gun:getFullType() .. " does not fire " .. round) end

    local key = ownerKey(player)
    local now = VAT.nowSeconds()
    local seq = num(args.s) or -1
    if cfg.ServerValidation then
        if SV.lastLaunch[key] and now - SV.lastLaunch[key] < LA.MIN_INTERVAL then return rejectLaunch(player, args, "cooldown") end
        local unlimited = player.isUnlimitedAmmo and player:isUnlimitedAmmo()
        local list = gun:getModData().AmmoList
        if not unlimited and gun:getCurrentAmmoCount() <= 0 and not (list and #list > 0)
            and not (SV.lastAmmo[gun:getID()] and now - SV.lastAmmo[gun:getID()] < 3) then
            return rejectLaunch(player, args, "empty")
        end
    end

    local ox, oy, oh = num(args.ox), num(args.oy), num(args.oh)
    local vx, vy, vh = num(args.vx), num(args.vy), num(args.vh)
    if not (ox and oy and oh and vx and vy and vh) then return rejectLaunch(player, args, "malformed") end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local chestH = pz * S + 1.3
    if cfg.ServerValidation then
        local dx, dy = ox - px, oy - py
        local d = math.sqrt(dx * dx + dy * dy)
        if d > LA.MUZZLE_REACH * 2 or oh < pz * S - 0.3 or oh > pz * S + 2.6 then
            return rejectLaunch(player, args, "origin", string.format("%.2f m away", d))
        end
        if d > LA.MUZZLE_REACH then ox, oy = px + dx / d * LA.MUZZLE_REACH, py + dy / d * LA.MUZZLE_REACH end
        oh = VAT.clamp(oh, pz * S + 0.2, pz * S + 2.3)
        local cx, cy, ch, blocked = VAT.Physics.clearPath(def, px, py, chestH, ox, oy, oh)
        if blocked then ox, oy, oh = cx, cy, ch end
        local maxV = LA.speed(round) * 1.05 + 0.5
        local sp = VAT.len3(vx, vy, vh)
        if sp > maxV then
            local k = maxV / sp
            vx, vy, vh = vx * k, vy * k, vh * k
        end
    end

    local payload = VAT.createItem(LA.payloadType(round))
    if not payload then return rejectLaunch(player, args, "payload", LA.payloadType(round)) end

    local id = SV.nextId
    SV.nextId = SV.nextId + 1
    local launch = { ox = ox, oy = oy, oh = oh, vx = vx, vy = vy, vh = vh, phase = "air" }
    local visual = LA.visualType(round)
    local proj = M.spawn(def, launch, {
        id = id, authority = true, seq = seq, mode = VAT.MODE_OVERHAND, item = payload, fullType = visual,
        round = round, ownerObj = player, ownerKey = key, ownerOnline = isServer() and player:getOnlineID() or -1,
        mass = def.mass, local_ = not isClient() and not isServer(),
    })
    SV.lastLaunch[key] = now
    Log.info("Grenade launched: id=%d %s from %s by %s speed=%.1f", id, round, gun:getFullType(),
        tostring(player:getUsername()), VAT.len3(vx, vy, vh))
    N.toAll("spawn", {
        id = id, s = seq, p = proj.ownerOnline, ft = visual, lr = round, m = VAT.MODE_OVERHAND, ms = def.mass,
        x = ox, y = oy, h = oh, vx = vx, vy = vy, vh = vh, ph = "air",
    })
end

N.serverHandlers.launch = SV.handleLaunch

-- a gun that had a round a moment ago: the vanilla shot may already have taken it out on the server
SV.lastAmmo = SV.lastAmmo or {}
if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(function(player)
        if isClient() then return end
        local gun = player and player:getPrimaryHandItem()
        if gun and instanceof(gun, "HandWeapon") and gun:isRanged() and gun:getCurrentAmmoCount() > 0 then
            SV.lastAmmo[gun:getID()] = VAT.nowSeconds()
        end
    end)
end

-- ------------------------------------------------------------------ impacts (authority)
local function finishSquare(proj)
    local cell = getCell()
    local x, y, h = proj.x, proj.y, proj.h
    local hit = proj.endHit
    if hit then
        -- stay on the side the object came from (never explode inside or behind a wall)
        x, y, h = hit.x + hit.nx * 0.06, hit.y + hit.ny * 0.06, hit.h + hit.nh * 0.06
    end
    local L = VAT.Physics.levelOf(h)
    for z = L, math.max(L - 4, -32), -1 do
        local sq = cell:getGridSquare(math.floor(x), math.floor(y), z)
        if sq and (z == 0 or sq:TreatAsSolidFloor()) then return sq end
    end
    if proj.ownerObj then return proj.ownerObj:getCurrentSquare() end
    return nil
end

local function pvpAllowed(attacker, target)
    if attacker == target then return true end
    local ok, pvp = pcall(function() return getServerOptions():getBoolean("PVP") end)
    if isServer() and not (ok and pvp) then return false end
    local okT, tSafe = pcall(function() return target:getSafety():isEnabled() end)
    local okA, aSafe = pcall(function() return attacker and attacker:getSafety():isEnabled() end)
    return not ((okT and tSafe) and (okA and aSafe))
end

local function applyDamage(proj, hit, cfg)
    if not cfg.ImpactDamage then return end
    local body = hit.body
    if not body or not body.obj then return end
    local momentum = (proj.mass or 0.5) * hit.normalSpeed
    if momentum < 3 then return end
    local dmg = VAT.clamp((momentum - 3) * 0.03 * cfg.ImpactDamageMultiplier * (proj.def.damageMultiplier or 1), 0, 0.9)
    if dmg <= 0.001 then return end
    local target = body.obj
    local attacker = proj.ownerObj or getCell():getFakeZombieForHit()
    if body.player then
        if not cfg.PlayerImpactDamage or not pvpAllowed(proj.ownerObj, target) then return end
    end
    target:Hit(hitWeapon(proj), attacker, dmg, false, 1.0)
    Log.debug("Impact damage %.2f to %s (momentum %.1f)", dmg, body.zombie and "zombie" or "player", momentum)
end

local function distract(proj, hit, cfg, final)
    if not cfg.ZombieDistraction or not proj.ownerObj then return end
    local now = proj.age
    if not final and (hit and hit.normalSpeed < 2.5 or (proj.lastNoise and now - proj.lastNoise < 0.4)) then return end
    proj.lastNoise = now
    local def = proj.def
    local radius = math.floor(VAT.clamp(def.noiseRadius * cfg.DistractionMultiplier, 1, 60) + 0.5)
    local volume = math.floor(VAT.clamp(def.noiseVolume * cfg.DistractionMultiplier, 1, 100) + 0.5)
    local x, y, h = hit and hit.x or proj.x, hit and hit.y or proj.y, hit and hit.h or proj.h
    addSound(proj.ownerObj, math.floor(x), math.floor(y), VAT.Physics.levelOf(h), radius, volume)
end

M.on("impact", function(proj, hit)
    if not proj.authority then return end
    local cfg = proj.cfg
    Log.debug("%s: id=%s kind=%s speed=%.1f normal=%.1f action=%s at %.2f,%.2f,%.2f n=(%.2f,%.2f,%.2f)",
        hit.action == "bounce" and "Bounce" or "Collision", tostring(proj.id), hit.kind, hit.speed, hit.normalSpeed,
        tostring(hit.action), hit.x, hit.y, hit.h, hit.nx, hit.ny, hit.nh)
    if hit.smash and hit.info and hit.info.window then
        local w = hit.info.window
        if not w:isDestroyed() then
            w:smashWindow()
            if proj.ownerObj then w:addBrokenGlass(proj.ownerObj) end
            Log.info("Window smashed by throwable id=%s at %d,%d,%d", tostring(proj.id), hit.info.wx, hit.info.wy, hit.info.wz)
        end
    end
    applyDamage(proj, hit, cfg)
    distract(proj, hit, cfg, false)
end)

M.on("stopped", function(proj, reason)
    if not proj.authority then return end
    local ctx = { item = proj.item, owner = proj.ownerObj, square = finishSquare(proj) }
    if ctx.owner and ctx.owner:isDead() and isServer() then
        -- a dead thrower is still a valid attacker object; only a disconnected one is dropped
        local still = getPlayerByOnlineID(proj.ownerOnline)
        if not still then ctx.owner = nil end
    elseif ctx.owner and isServer() and not getPlayerByOnlineID(proj.ownerOnline) then
        ctx.owner = nil
    end
    local handled = VAT.Behaviors.finish(proj, reason, ctx)
    if not handled and ctx.item and reason ~= "break" and reason ~= "detonate" then
        VAT.Behaviors.dropItem(proj, ctx)          -- never lose an item silently
    end
    if reason == "detonate" then VAT.emit("detonation", proj) end
    if reason ~= "detonate" then distract(proj, nil, proj.cfg, true) end
    if not isServer() then VAT.Behaviors.cosmetic(proj, reason) end   -- single player: the local view
    VAT.emit("landing", proj, reason)
    Log.info("Projectile finished: id=%s %s reason=%s at %.2f,%.2f,%.2f after %.2fs, %d bounces", tostring(proj.id),
        tostring(proj.fullType), reason, proj.x, proj.y, proj.h, proj.age, proj.bounces or 0)
    N.toAll("end", { id = proj.id, r = reason, x = proj.x, y = proj.y, h = proj.h })
    M.remove(proj)
end)

M.on("afterStep", function()
    if not isServer() then return end
    for i = 1, #M.list do
        local proj = M.list[i]
        if proj.authority and (proj.phase == "air" or proj.phase == "roll") and proj.steps % SV.SYNC_EVERY == 0 then
            N.toAll("sync", { id = proj.id, k = proj.steps, x = proj.x, y = proj.y, h = proj.h,
                vx = proj.vx, vy = proj.vy, vh = proj.vh, ph = proj.phase })
        end
    end
end)

-- ------------------------------------------------------------------ event wiring
local function onClientCommand(module, command, player, args)
    if module ~= VAT.NET then return end
    local h = N.serverHandlers[command]
    if not h then return end
    local ok, err = pcall(h, player, args)
    if not ok then Log.warn("Command %s failed: %s", tostring(command), tostring(err)) end
end

local function onTick()
    if not isServer() and isClient() then return end   -- MP clients step in VAT_Client
    if #M.list == 0 then M.lastTime = nil; return end
    M.update(VAT.nowSeconds())
end

if isServer() then
    Events.OnClientCommand.Add(onClientCommand)
end
Events.OnTick.Add(onTick)

-- ------------------------------------------------------------------ explosion effects for everyone
-- Instant explosives also go off on each client (and show there at once); timer, sensor and remote
-- ones only go off here, so the server describes every explosion to all clients. Clients drop a copy
-- of an effect they already showed (VAT_Fx.lua).
if Events and Events.OnThrowableExplode then
    Events.OnThrowableExplode.Add(function(trap, square)
        if isClient() then return end
        local ok, d = pcall(VAT.Effects.fromTrap, trap, square)
        if not ok or not d then return end
        if isServer() then N.toAll("fx", d) end
        if (d.fr or 0) > 0 then
            local okA, attacker = pcall(function() return trap:getAttacker() end)
            SV.addFireArea(d.x, d.y, d.z, d.fr, okA and attacker or nil, d.ft)
        end
    end)
end

-- ------------------------------------------------------------------ fire that catches what walks into it
--[[
The game sets a zombie on fire when it stands on a burning square (IsoGameCharacter fire check, run
by the server), but a burning zombie keeps walking for a long time, and one that only brushes the
edge of a burning square never catches at all. Around incendiary fires (molotovs, incendiary
grenades) this mod, every half second, for as long as the area burns:
  * ignites zombies whose body overlaps a burning square (within 0.85 tiles of its middle);
  * burns them: damage while they are in the flames, less while they carry the fire elsewhere in the
    area, so fire kills (sandbox FireDamageMultiplier, 0 = off).
Damage goes through IsoGameCharacter.Hit with the thrower as the attacker (the game's fake zombie
when unknown), exactly as an explosive trap hurts what it catches (IsoTrap.explosion), so kills are
handled and synced by the game. Server (or single player) only.
]]
SV.fireAreas = SV.fireAreas or {}
SV.FIRE_AREA_SECONDS = 180
SV.FIRE_REACH = 0.85

SV.FIRE_DAMAGE_IN = 0.12          -- per half second inside the flames (a zombie has 1.8-2.1 health: ~8 s)
SV.FIRE_DAMAGE_CARRIED = 0.05     -- per half second while burning elsewhere in the area (~20 s)

local fireWeapons = {}
local function fireWeapon(ft)
    ft = ft or "Base.Molotov"
    local w = fireWeapons[ft]
    if w == nil then
        local it = VAT.createItem(ft); local ok = it ~= nil
        if not (ok and it and instanceof(it, "HandWeapon")) then
            it = VAT.createItem("Base.Molotov"); ok = it ~= nil
        end
        w = (ok and it and instanceof(it, "HandWeapon")) and it or false
        fireWeapons[ft] = w
    end
    return w or nil
end

function SV.addFireArea(x, y, z, range, attacker, ft)
    local areas = SV.fireAreas
    areas[#areas + 1] = { x = x, y = y, z = math.floor(z + 0.01), r = math.min(12, range + 1),
        expires = VAT.nowSeconds() + SV.FIRE_AREA_SECONDS, attacker = attacker, ft = ft }
    if #areas > 24 then table.remove(areas, 1) end
end

local function burn(zombie, area, amount)
    local mult = VAT.Config.server().FireDamageMultiplier or 1
    if mult <= 0 or amount <= 0 then return end
    local weapon = fireWeapon(area.ft)
    if not weapon then return end
    local attacker = area.attacker or getCell():getFakeZombieForHit()
    zombie:Hit(weapon, attacker, amount * mult, false, 1.0)
end

local function igniteNear(cell, sq, area, hurt)
    local cx, cy, z = sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()
    for dy = -1, 1 do
        for dx = -1, 1 do
            local n = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, z)
            local movers = n and n:getMovingObjects()
            if movers then
                for i = 0, movers:size() - 1 do
                    local m = movers:get(i)
                    if instanceof(m, "IsoZombie") and not m:isDead() and not hurt[m] then
                        local ddx, ddy = m:getX() - cx, m:getY() - cy
                        if ddx * ddx + ddy * ddy <= SV.FIRE_REACH * SV.FIRE_REACH then
                            hurt[m] = true
                            if not m:isOnFire() then m:SetOnFire() end
                            burn(m, area, SV.FIRE_DAMAGE_IN)
                        end
                    end
                end
            end
        end
    end
end

--- Burning zombies anywhere in the area that are not in the flames right now still burn.
local function burnCarried(cell, area, hurt)
    local r = math.ceil(area.r) + 3
    local bx, by = math.floor(area.x), math.floor(area.y)
    for y = by - r, by + r do
        for x = bx - r, bx + r do
            local sq = cell:getGridSquare(x, y, area.z)
            local movers = sq and sq:getMovingObjects()
            if movers then
                for i = 0, movers:size() - 1 do
                    local m = movers:get(i)
                    if instanceof(m, "IsoZombie") and not m:isDead() and not hurt[m] and m:isOnFire() then
                        hurt[m] = true
                        burn(m, area, SV.FIRE_DAMAGE_CARRIED)
                    end
                end
            end
        end
    end
end

function SV.updateFireAreas()
    local areas = SV.fireAreas
    if #areas == 0 then return end
    local t = VAT.nowSeconds()
    if (SV.nextFireCheck or 0) > t then return end
    SV.nextFireCheck = t + 0.5
    local cell = getCell()
    if not cell then return end
    for a = #areas, 1, -1 do
        local area = areas[a]
        if area.expires < t then
            table.remove(areas, a)
        else
            local r = math.ceil(area.r)
            local bx, by = math.floor(area.x), math.floor(area.y)
            local hurt = {}
            for y = by - r, by + r do
                for x = bx - r, bx + r do
                    local sq = cell:getGridSquare(x, y, area.z)
                    if sq and sq:has(IsoFlagType.burning) then igniteNear(cell, sq, area, hurt) end
                end
            end
            burnCarried(cell, area, hurt)
        end
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(function()
        if isClient() then return end
        local ok, err = pcall(SV.updateFireAreas)
        if not ok then Log.once("fireareas", "Fire area check failed: %s", tostring(err)) end
    end)
end
