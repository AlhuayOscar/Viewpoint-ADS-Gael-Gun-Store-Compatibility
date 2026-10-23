require "VAT/VAT_Client"
require "VAT/VAT_Action"

--[[
Throw input and state machine for the local Viewpoint player.

  idle ──press──▶ charging ──release──▶ throwing ──VATRelease──▶ recovery ──VATThrowDone──▶ idle
                     │ cancel / item gone / view left                         (anim event or failsafe)
                     ▼
                   idle (not possible once a cookable fuse has been started)

Inputs (all rebindable):
  * the game's own Attack binding throws vanilla-style throwables (grenades, molotovs, smoke, noise
    makers, registered items) while Viewpoint drives the view; vanilla's isometric attack is gated off
  * the Throw key (Mod Options) throws any throwable object, including tools and bottles, so melee
    weapons keep their normal Attack
  * Underhand modifier, Roll key (or crouching), Cancel key, Cook key (cookable items only)
Charge: hold time / ChargeTime, eased; quick tap = short toss, full hold = strong throw.

The launch is computed at the release point of the animation from Viewpoint's live camera:
release point = right-hand bone (configurable fallback offset when no skeleton is available),
direction = from the hand toward the crosshair raycast point (VAT.Solver.launch).
]]

VAT.Controller = VAT.Controller or {}
local C = VAT.Controller
local R = VAT.Registry
local V = VAT.Solver
local CL = VAT.Client
local N = VAT.Net
local Log = VAT.Log
local S = VAT.S

C.state = "idle"
C.charge = 0
C.mode = VAT.MODE_OVERHAND
C.preview = { points = {}, result = nil, valid = false }
C.debug = { aim = {}, origin = nil, launch = nil }
C.RELEASE_FAILSAFE = 0.75          -- seconds after the throw clip starts
C.RECOVERY_FAILSAFE = 1.0

-- configurable fallback hand offset (metres, relative to the eye and the aim yaw)
C.handOffset = { right = 0.22, up = -0.28, forward = 0.38 }

local aim, hand = {}, {}
local lastPos = { x = 0, y = 0, h = 0, t = 0 }
local vel = { x = 0, y = 0, h = 0 }
local prevHeld, prevCancel, prevCook = false, false, false
local previewTick = 0

local function now() return VAT.nowSeconds() end

local function opt() return VAT.Config.client end

local function keyDown(k) return k ~= nil and k > 0 and isKeyDown(k) end

--- The throwable currently held, with its definition, or nil.
local function held(player)
    local item = player:getPrimaryHandItem()
    if not item then return nil end
    local def = R.resolve(item)
    if not def then return nil end
    return item, def
end

local function viewpointActive(player)
    return VAT_viewpointActive ~= nil and VAT_viewpointActive(player) == true
end

-- ------------------------------------------------------------------ thrower velocity (momentum)
local function trackVelocity(player)
    local t = now()
    local x, y, h = player:getX(), player:getY(), player:getZ() * S
    local dt = t - lastPos.t
    if dt > 0 and dt < 0.5 then
        local k = VAT.clamp(dt / 0.12, 0, 1)
        vel.x = vel.x + ((x - lastPos.x) / dt - vel.x) * k
        vel.y = vel.y + ((y - lastPos.y) / dt - vel.y) * k
        vel.h = vel.h + ((h - lastPos.h) / dt - vel.h) * k
    else
        vel.x, vel.y, vel.h = 0, 0, 0
    end
    -- teleports and vehicle exits are not momentum
    if VAT.len3(vel.x, vel.y, vel.h) > 12 then vel.x, vel.y, vel.h = 0, 0, 0 end
    lastPos.x, lastPos.y, lastPos.h, lastPos.t = x, y, h, t
end

-- ------------------------------------------------------------------ aim and release point
--- Camera, crosshair point and release point. Never falls back to the player's own tile: without a
--- Viewpoint frame the player's forward direction is used.
function C.computeAim(player)
    local ok = VAT_getAim and VAT_getAim(aim)
    local a = {}
    if ok then
        a.cx, a.cy, a.ch = aim.cx, aim.cy, aim.ch
        a.fx, a.fy, a.fh = aim.fx, aim.fy, aim.fh
        a.yaw, a.pitch = aim.yaw, aim.pitch
        a.hit, a.tx, a.ty, a.th = aim.hit, aim.tx, aim.ty, aim.th
        a.third = aim.third
    else
        local dir = player:getForwardDirection()
        local fx, fy = dir:getX(), dir:getY()
        local l = math.sqrt(fx * fx + fy * fy)
        if l < 1e-4 then fx, fy, l = 1, 0, 1 end
        fx, fy = fx / l, fy / l
        a.cx, a.cy, a.ch = player:getX(), player:getY(), player:getZ() * S + 1.6
        a.fx, a.fy, a.fh = fx, fy, 0
        a.yaw, a.pitch = math.atan2(fy, fx), 0
        a.hit = false
        a.fallback = true
    end
    -- release point
    local okHand = VAT_getHand and VAT_getHand(player, hand)
    if okHand then
        a.ox, a.oy, a.oh = hand.x, hand.y, hand.h
        a.handSource = "skeleton"
    else
        local o = C.handOffset
        local cyw, syw = math.cos(a.yaw), math.sin(a.yaw)
        local eyeH = player:getZ() * S + 1.55
        a.ox = player:getX() + cyw * o.forward - syw * o.right
        a.oy = player:getY() + syw * o.forward + cyw * o.right
        a.oh = eyeH + o.up
        a.handSource = "offset"
    end
    -- keep the object out of the camera lens: at least 0.3 m in front of the eye along the view
    if not a.third and not a.fallback then
        local along = (a.ox - a.cx) * a.fx + (a.oy - a.cy) * a.fy + (a.oh - a.ch) * a.fh
        if along < 0.3 then
            local push = 0.3 - along
            a.ox, a.oy, a.oh = a.ox + a.fx * push, a.oy + a.fy * push, a.oh + a.fh * push
        end
    end
    -- never release through a wall the thrower is pressed against
    local chestH = player:getZ() * S + 1.25
    local item, def = held(player)
    local cx, cy, ch = VAT.Physics.clearPath(def or R.MATERIALS.generic, player:getX(), player:getY(), chestH, a.ox, a.oy, a.oh)
    a.ox, a.oy, a.oh = cx, cy, ch
    a.floorH = VAT.World.surface(player:getX(), player:getY(), math.floor(player:getZ())) or player:getZ() * S
    a.pvx, a.pvy, a.pvh = vel.x, vel.y, vel.h
    return a
end

local function chooseMode(player)
    local cfg = VAT.Config.server()
    local o = opt()
    if cfg.EnableRolling and (keyDown(o.keyRoll) or (o.crouchRolls and player:isSneaking())) then return VAT.MODE_ROLL end
    if cfg.EnableUnderhand and keyDown(o.keyUnderhand) then return VAT.MODE_UNDERHAND end
    return VAT.MODE_OVERHAND
end

local function chargeNow()
    local cfg = VAT.Config.server()
    if not C.chargeStart then return 0 end
    return VAT.clamp((now() - C.chargeStart) / cfg.ChargeTime, 0, 1)
end

-- ------------------------------------------------------------------ preview
function C.updatePreview(player, def)
    local cfg = VAT.Config.server()
    local mode = chooseMode(player)
    local a = C.computeAim(player)
    a.mode = mode
    a.charge = chargeNow()
    a.mass = R.massOf(C.item, def)
    a.autoArc = opt().autoArc
    local launch = V.launch(def, a, cfg)
    local res = V.predict(def, launch, cfg, 120, 2, C.preview.points, player)
    C.preview.result = res
    C.preview.valid = true
    C.preview.mode = mode
    C.debug.aimInfo = a
    C.debug.launch = launch
end

-- ------------------------------------------------------------------ state machine
local function started(action)
    return action ~= nil and action.action ~= nil
end

local function setPhase(phase)
    if started(C.action) then C.action:setPhase(phase) end
end

--- Takes our action out of the game's queue whatever state it is in (never leaves it running).
local function dropAction(action, player)
    if not action then return end
    action.orphaned = true
    if started(action) then
        pcall(action.forceStop, action)
    else
        local q = player and ISTimedActionQueue.getTimedActionQueue(player)
        if q then pcall(q.removeFromQueue, q, action) end
    end
end

local function reset(stopAction)
    if stopAction and C.action then
        local a = C.action
        C.action = nil
        dropAction(a, getPlayer())
    end
    C.state = "idle"
    C.item, C.def, C.action = nil, nil, nil
    C.chargeStart, C.releaseAt, C.throwStart, C.cookStart = nil, nil, nil, nil
    C.charge = 0
    C.preview.valid = false
    if VAT_setFacing then VAT_setFacing(false, 0) end
end

function C.cancel(reason)
    if C.state ~= "charging" then return false end
    if C.cookStart then
        Log.debug("Cannot cancel: the fuse is already burning")
        return false
    end
    Log.debug("Throw cancelled (%s)", tostring(reason))
    local action = C.action
    reset()
    if action and action.action then action:forceStop() end
    return true
end

local function begin(player, item, def)
    C.state = "charging"
    C.item, C.def = item, def
    C.chargeStart = now()
    C.charge = 0
    C.cookStart = nil
    local action = VATThrowAction:new(player, item, C)
    C.action = action
    ISTimedActionQueue.add(action)
    if not started(action) then
        -- the game refused or only queued it (asleep, dragging a corpse, another queued action)
        reset(true)
        return
    end
    Log.debug("Preparing throw of %s (%s)", item:getFullType(), tostring(def.source))
end

function C:onActionStarted(action) end

function C:onActionUpdate(action) end

--- Animation release point: the object leaves the hand now.
function C:onReleasePoint(action)
    if C.state ~= "throwing" or C.action ~= action then return end
    C.release(getPlayer(), C.throwMode or VAT.MODE_OVERHAND, C.charge)
end

function C:onActionEnded(action, completed)
    if C.action ~= action then return end
    if C.state == "throwing" then
        -- the clip was interrupted before the release point: the throw still happens
        C.release(getPlayer(), C.throwMode or VAT.MODE_OVERHAND, C.charge)
    end
    local item = C.lastThrown and C.lastThrown.item
    reset()
    if opt().autoEquipNext and item then C.equipNext(getPlayer(), item:getFullType()) end
end

function C.equipNext(player, fullType)
    if not player or player:getPrimaryHandItem() then return end
    local nextItem = player:getInventory():getFirstTypeRecurse(fullType)
    if nextItem and nextItem:getContainer() == player:getInventory() then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(player, nextItem, 50, true, false))
    end
end

--- Builds the launch from the live camera and sends it (with local prediction in multiplayer).
function C.release(player, mode, charge)
    if C.state ~= "throwing" or not player then return end
    local item, def = C.item, C.def
    C.state = "recovery"
    C.releaseDone = now()
    if not item or not def then return end
    local cfg = VAT.Config.server()
    local a = C.computeAim(player)
    a.mode, a.charge, a.mass, a.autoArc = mode, charge, R.massOf(item, def), opt().autoArc
    local launch = V.launch(def, a, cfg)
    local cooked = C.cookStart and (now() - C.cookStart) or 0
    VAT.Throw.send(player, item, def, launch, mode, charge, cooked, a)
    if started(C.action) then C.action:handEmpty() end
end

--- Called by the client when the server refused a throw: the item goes back into the hand.
function C.onRejected(a)
    local last = C.lastThrown
    local player = getPlayer()
    if not last or not player or last.seq ~= a.s then return end
    local item = last.item
    if item and item:getContainer() == player:getInventory() and not player:getPrimaryHandItem() then
        player:setPrimaryHandItem(item)
    elseif item and item:getContainer() == nil and opt().autoEquipNext then
        -- the rejected copy was client-only and has been removed: take a real one if there is one
        C.equipNext(player, item:getFullType())
    end
end

--- Forgets an item that no longer exists on this client (see VAT_Client CL.dropGhost).
function C.forgetItem(item)
    if C.item == item then C.item = nil end
end

function C.tick()
    local player = getPlayer()
    if not player then return end
    trackVelocity(player)
    local cfg = VAT.Config.server()
    local o = opt()
    local active = cfg.Enabled and not player:isDead() and viewpointActive(player)
    local item, def = held(player)

    -- gate the vanilla isometric attack while Viewpoint drives the view and a throwable is in hand
    local gate = active and ((def and def.primaryInput and o.attackThrows) or C.state ~= "idle")
    if VAT_setGate then VAT_setGate(gate and true or false) end
    if VAT_setVanillaFix then VAT_setVanillaFix(true) end

    local attack = gate and VAT_attackDown and VAT_attackDown() and def and def.primaryInput and o.attackThrows
    local throwKey = keyDown(o.keyThrow)
    local input = (attack or throwKey) and true or false
    local cancelPressed = keyDown(o.keyCancel)
    local cookPressed = keyDown(o.keyCook)

    if C.state == "idle" then
        if active and input and not prevHeld and item and def
            and not ISTimedActionQueue.isPlayerDoingAction(player) and not player:getVehicle()
            and #(ISTimedActionQueue.getTimedActionQueue(player).queue or {}) == 0 then
            if R.otherHandOk(player, item) then
                begin(player, item, def)
            else
                player:Say(VAT.Text.needOtherHand)
            end
        end
    elseif C.state == "charging" then
        if not active or player:isDead() then
            if C.cookStart then
                C.throwMode = VAT.MODE_DROP
                C.state = "throwing"
                C.release(player, VAT.MODE_DROP, 0)
            else
                C.cancel("view")
            end
        elseif player:getPrimaryHandItem() ~= C.item then
            C.cancel("item")
        elseif cancelPressed and not prevCancel then
            C.cancel("key")
        else
            C.charge = chargeNow()
            if cookPressed and not prevCook and C.def.cookable and cfg.AllowCooking and not C.cookStart then
                C.cookStart = now()
                Log.debug("Fuse started in hand")
            end
            if C.cookStart and C.def.fuse.type == "timed" and now() - C.cookStart >= (C.def.fuse.seconds or 3) - 0.05 then
                -- held too long: it goes off in the hand
                C.throwMode = VAT.MODE_DROP
                C.state = "throwing"
                C.release(player, VAT.MODE_DROP, 0)
            elseif not input then
                -- released: the throw clip plays and the object leaves at its release point
                C.charge = chargeNow()
                C.throwMode = chooseMode(player)
                C.state = "throwing"
                C.throwStart = now()
                setPhase(C.throwMode == VAT.MODE_OVERHAND and "over" or "under")
            else
                previewTick = previewTick + 1
                if previewTick % 2 == 0 and (VAT.Config.previewMode() > 1 or VAT.Config.debugDrawAllowed(player)) then
                    local ok, err = pcall(C.updatePreview, player, C.def)
                    if not ok then
                        C.preview.valid = false
                        Log.once("preview", "Preview failed: %s", tostring(err))
                    end
                end
            end
        end
    elseif C.state == "throwing" then
        C.preview.valid = false
        if C.throwStart and now() - C.throwStart > C.RELEASE_FAILSAFE then
            Log.debug("Release event did not arrive; releasing on the failsafe timer")
            C.release(player, C.throwMode or VAT.MODE_OVERHAND, C.charge)
        end
    elseif C.state == "recovery" then
        if C.releaseDone and now() - C.releaseDone > C.RECOVERY_FAILSAFE then
            if started(C.action) then C.action:forceComplete() else reset(true) end
        end
    end

    -- face the crosshair while preparing and throwing (third person: toward the aimed point)
    if C.state ~= "idle" and VAT_setFacing then
        local ok = VAT_getAim and VAT_getAim(aim)
        if ok then
            local yaw = aim.yaw
            if aim.third and aim.hit then
                local dx, dy = aim.tx - player:getX(), aim.ty - player:getY()
                if dx * dx + dy * dy > 1 then yaw = math.atan2(dy, dx) end
            end
            VAT_setFacing(true, yaw)
        end
    end

    prevHeld, prevCancel, prevCook = input, cancelPressed, cookPressed
end

Events.OnTick.Add(function()
    local ok, err = pcall(C.tick)
    if not ok then
        Log.once("controller", "Throw controller error: %s", tostring(err))
        if VAT_setGate then VAT_setGate(false) end
        reset(true)
    end
end)

Events.OnPlayerDeath.Add(function(player)
    if player == getPlayer() and C.state == "charging" and C.cookStart then
        C.throwMode = VAT.MODE_DROP
        C.state = "throwing"
        C.release(player, VAT.MODE_DROP, 0)
    end
end)

-- ------------------------------------------------------------------ the request itself
VAT.Throw = VAT.Throw or {}

--- Sends a throw (shared by the controller and ViewpointThrowables.throwItem).
function VAT.Throw.send(player, item, def, launch, mode, charge, cooked, a)
    local seq = CL.nextSeq()
    local args = {
        s = seq, i = item:getID(), ft = item:getFullType(), m = mode, c = charge, k = cooked or 0,
        ox = launch.ox, oy = launch.oy, oh = launch.oh, vx = launch.vx, vy = launch.vy, vh = launch.vh,
        px = a and a.pvx or 0, py = a and a.pvy or 0, ph = a and a.pvh or 0,
    }
    if C.lastThrown == nil or C.lastThrown.item ~= item then C.lastThrown = { item = item } end
    C.lastThrown.seq = seq
    C.lastThrown.item = item
    if def.throwSound then CL.playAt(def.throwSound, launch.ox, launch.oy, launch.oh, 8, 0.8) end
    Log.info("Throw request: seq=%d %s mode=%s charge=%.2f speed=%.1f origin=%s", seq, item:getFullType(),
        VAT.MODE_NAMES[mode] or "?", charge or 0, VAT.len3(launch.vx, launch.vy, launch.vh), a and a.handSource or "api")
    if isClient() then
        CL.predict(def, launch, seq, item, player, mode)
        -- the object is in flight: it must not also stay visible in the hand until the server answers
        -- a multi-use item stays in hand on the server (one use is split off), so only a single one leaves it
        local single = not instanceof(item, "HandWeapon") or item:getCurrentUses() <= 1
        if single and player:getPrimaryHandItem() == item then player:setPrimaryHandItem(nil) end
        if single and player:getSecondaryHandItem() == item then player:setSecondaryHandItem(nil) end
    end
    N.toServer(player, "throw", args)
    C.debug.lastLaunch = launch
    C.debug.lastAim = a
    return seq
end
