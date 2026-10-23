require "VAT/VAT_Registry"
require "VAT/VAT_Physics"

--[[
Behaviours: what a thrown object DOES, kept apart from how it flies.

A behaviour is a table with optional hooks. Shared hooks must be deterministic because the server and
every client run them on the same simulation:
  impact(proj, hit)  -> nil | "bounce" | "stop", reason | "pass"   (first non-nil answer wins)
  fuse(proj)         -> reason                                     (timed fuse ran out)
  rest(proj)         -> nil | reason                               (object came to rest)
Server-only hook (authority; changes the world):
  finish(proj, reason, ctx)                                        (ctx: square, item, owner)
Client-only hook (cosmetic):
  cosmetic(proj, reason)

Built-in behaviours
  vanilla_trap  hands the item to the game's own IsoTrap at the right square: explosions, fire
                (molotovs), smoke, noise makers, timer/sensor/remote traps all use vanilla code.
  inert         the object stays where it stops as a normal world item.
  breakable     breaks on a hard enough impact (glass), otherwise behaves like inert.
Other mods add their own with ViewpointThrowables.registerBehavior(name, table).
]]

VAT.Behaviors = VAT.Behaviors or {}
local B = VAT.Behaviors
B.list = B.list or {}
local Log = VAT.Log

function B.register(name, behavior)
    if type(name) ~= "string" or type(behavior) ~= "table" then return false end
    B.list[name] = behavior
    VAT.Registry.cache = {}
    return true
end

local function each(proj, hook, a, b)
    local names = proj.def.behaviors
    for i = 1, #names do
        local beh = B.list[names[i]]
        local fn = beh and beh[hook]
        if fn then
            local ok, r1, r2 = pcall(fn, proj, a, b)
            if not ok then
                Log.once("beh:" .. names[i] .. ":" .. hook, "Behaviour %s.%s failed: %s", names[i], hook, tostring(r1))
            elseif r1 ~= nil then
                return r1, r2
            end
        end
    end
    return nil
end

--- Shared impact decision used by the physics (installed as VAT.Physics.decide).
function B.decide(proj, hit)
    local def = proj.def
    local cfg = proj.cfg or VAT.Config.server()
    -- closed, intact, unbarricaded glass: a fast enough object goes through and the server smashes it
    if hit.kind == "window" and hit.info and hit.info.intact and not hit.info.barricaded
        and not hit.info.invincible and cfg.WindowBreaking and def.breaksWindows ~= false
        and hit.normalSpeed >= VAT.Physics.WINDOW_BREAK_SPEED then
        hit.smash = true
        -- a breakable object (bottle) shatters on the glass instead of flying on
        if def.breakOnImpact then return "stop", "break" end
        local a, reason = each(proj, "impact", hit)      -- e.g. an impact-fused molotov bursts on the glass
        if a == "stop" then return a, reason end
        return "pass"
    end
    if type(def.impactCallback) == "function" then
        local ok, a, reason = pcall(def.impactCallback, proj, hit)
        if ok and a ~= nil then return a, reason end
    end
    local a, reason = each(proj, "impact", hit)
    if a ~= nil then return a, reason end
    return "bounce"
end

function B.onFuse(proj)
    local r = each(proj, "fuse")
    return r or "detonate"
end

function B.onRest(proj)
    if type(proj.def.landingCallback) == "function" then
        pcall(proj.def.landingCallback, proj)
    end
    return each(proj, "rest")
end

--- Server: performs every behaviour's world change for the final reason.
function B.finish(proj, reason, ctx)
    local names = proj.def.behaviors
    local handled = false
    for i = 1, #names do
        local beh = B.list[names[i]]
        if beh and beh.finish then
            local ok, done = pcall(beh.finish, proj, reason, ctx)
            if not ok then
                Log.warn("Behaviour %s.finish failed for %s: %s", names[i], tostring(proj.def.fullType), tostring(done))
            elseif done then
                handled = true
            end
        end
    end
    return handled
end

function B.cosmetic(proj, reason)
    local names = proj.def.behaviors
    for i = 1, #names do
        local beh = B.list[names[i]]
        if beh and beh.cosmetic then pcall(beh.cosmetic, proj, reason) end
    end
end

-- ------------------------------------------------------------------ world helpers (server side)
--- Drops the projectile's item as a normal world item where it stopped (vanilla drop path).
function B.dropItem(proj, ctx)
    local item, sq = ctx.item, ctx.square
    if not item or not sq then return false end
    local xoff = VAT.clamp(proj.x - sq:getX(), 0.05, 0.95)
    local yoff = VAT.clamp(proj.y - sq:getY(), 0.05, 0.95)
    local zoff = VAT.clamp((proj.h - sq:getZ() * VAT.S) / VAT.S, 0, 0.9)
    -- same call sequence as vanilla ISDropWorldItemAction:complete()
    local worldItem = sq:AddWorldInventoryItem(item, xoff, yoff, zoff, false)
    if worldItem then
        worldItem:setWorldZRotation(proj.restYaw or 0)
        local wo = worldItem:getWorldItem()
        if wo and isServer() then wo:transmitCompleteItemToClients() end
    end
    return true
end

-- ------------------------------------------------------------------ built-in behaviours
B.register("inert", {
    rest = function(proj) return "drop" end,
    finish = function(proj, reason, ctx)
        if reason == "drop" or reason == "rest" or reason == "expire" then return B.dropItem(proj, ctx) end
        return false
    end,
})

B.register("breakable", {
    impact = function(proj, hit)
        local def = proj.def
        if def.breakOnImpact and hit.normalSpeed >= (def.breakSpeed or 6.5) then return "stop", "break" end
        return nil
    end,
    rest = function(proj) return "drop" end,
    finish = function(proj, reason, ctx)
        if reason == "break" then
            local res = proj.def.breakResult
            if res and ctx.square then
                local it = VAT.createItem(res); local ok = it ~= nil
                if ok and it then
                    ctx.item = it
                    B.dropItem(proj, ctx)
                end
            end
            return true                     -- the original item is consumed by breaking
        end
        if reason == "drop" or reason == "rest" or reason == "expire" then return B.dropItem(proj, ctx) end
        return false
    end,
})

B.register("vanilla_trap", {
    impact = function(proj, hit)
        if proj.def.fuse.type == "impact" then return "stop", "detonate" end
        return nil
    end,
    fuse = function(proj) return "detonate" end,
    rest = function(proj)
        local f = proj.def.fuse.type
        if f == "placed" then return "place" end
        if f == "impact" then return "detonate" end      -- rolled to a stop without a hard hit
        if f == "none" then return "drop" end
        return nil                                      -- timed: keep waiting for the fuse
    end,
    finish = function(proj, reason, ctx)
        if reason ~= "detonate" and reason ~= "place" then
            if reason == "drop" or reason == "expire" then return B.dropItem(proj, ctx) end
            return false
        end
        local weapon, sq = ctx.item, ctx.square
        if not weapon or not sq or not instanceof(weapon, "HandWeapon") then return false end
        weapon:setAttackTargetSquare(sq)
        -- the effects show where the object really was, not the middle of its square
        if VAT.Effects and VAT.Effects.note then VAT.Effects.note(proj.x, proj.y, proj.h) end
        local trap
        if ctx.owner then
            trap = IsoTrap.new(ctx.owner, weapon, sq:getCell(), sq)
        else
            trap = IsoTrap.new(weapon, sq:getCell(), sq)
        end
        -- IsoTrap.place(): adds the trap, tells every client (AddExplosiveTrap) and fires an
        -- instant explosion right away; timer / sensor / remote traps stay armed in the world.
        trap:place()
        VAT.Log.info("Detonation: %s at %d,%d,%d (%s)", weapon:getFullType(), sq:getX(), sq:getY(), sq:getZ(), reason)
        return true
    end,
})
