require "VAT/VAT_Projectiles"
require "VAT/VAT_Compat"

--[[
Public API for other mods. Nothing here requires editing Viewpoint or this mod.

    require "VAT/VAT_API"

    -- an item the generic detection would get wrong
    ViewpointThrowables.registerThrowable("MyMod.FlashBang", {
        kind = "explosive", material = "grenade", mass = 0.45,
        fuse = { type = "timed", seconds = 1.5 }, cookable = true,
        behaviors = { "vanilla_trap", "mymod_flash" }, bounce = 0.35, canRoll = true,
        fx = "flashbang",                    -- 3D effect when it goes off (see below)
    })
    -- a behaviour (shared hooks must be deterministic; finish runs on the server)
    ViewpointThrowables.registerBehavior("mymod_flash", {
        fuse = function(proj) return "detonate" end,
        finish = function(proj, reason, ctx) return false end,   -- e.g. blind zombies near ctx.square
    })
    -- edit every definition (e.g. make all bottles of a mod break more easily)
    ViewpointThrowables.registerAdapter("MyMod", function(def, item, fullType)
        if fullType:find("^MyMod%.Bottle") then def.breakSpeed = 4 end
    end)
    ViewpointThrowables.addImpactListener(function(proj, hit) print(hit.kind, hit.speed) end)

Definition fields: see VAT.Registry.FIELDS (mass, throwMultiplier, verticalMultiplier, bounce,
friction, rollResistance, canRoll, radius, spin, drag, breakOnImpact, breakSpeed, breakResult,
breaksWindows, maxVelocity, fuse, cookable, damageMultiplier, noiseRadius, noiseVolume,
impactSound, breakSound, throwSound, primaryInput, throwAnimation, impactCallback, landingCallback).
Effects (client, Viewpoint only): fx = "flashbang" marks a flashbang (blinding flash and whiteout;
names such as "Flashbang", "Stun Grenade" or "M84" are recognised without it), smokeColour = {r, g, b}
colours a smoke grenade's cloud (names with red, green, yellow, violet, blue, orange, black work
without it). Everything else follows the item's own stats (explosion range, fire range, smoke range).
Listener arguments: proj (x, y, h, vx, vy, vh, phase, def, fullType, id, authority, ownerObj) and
hit (kind, material, x, y, h, nx, ny, nh, speed, normalSpeed, action, body, vehicle).
proj.authority is true on the machine whose result counts (server, or single player).
]]

ViewpointThrowables = ViewpointThrowables or {}
local API = ViewpointThrowables
local R = VAT.Registry

API.VERSION = VAT.VERSION

function API.registerThrowable(fullType, config) return R.register(fullType, config) end
function API.unregisterThrowable(fullType) return R.unregister(fullType) end
function API.excludeItem(fullType) return R.exclude(fullType) end
function API.setBehavior(fullType, behaviors) return R.setBehavior(fullType, behaviors) end
function API.registerBehavior(name, behavior) return VAT.Behaviors.register(name, behavior) end
function API.registerAdapter(name, fn) return R.registerAdapter(name, fn) end

--- Resolved definition for an item instance or a full type string (nil = not throwable).
function API.getDefinition(itemOrType)
    if type(itemOrType) == "string" then return R.resolveType(itemOrType) end
    return R.resolve(itemOrType)
end

function API.isThrowable(itemOrType) return API.getDefinition(itemOrType) ~= nil end

--[[
Predicts a throw with the real simulation. `params` is a VAT.Solver.launch argument table
(ox, oy, oh, fx, fy, fh, cx, cy, ch, mode, charge, ...). On a client with no params the current
Viewpoint aim of the local player is used. Returns { points = {...}, result = {...}, launch = {...} }.
]]
function API.getTrajectory(itemOrType, params, maxSteps)
    local def = API.getDefinition(itemOrType)
    if not def then return nil end
    local cfg = VAT.Config.server()
    if not params and VAT.Controller and getPlayer then
        params = VAT.Controller.computeAim(getPlayer())
        params.mode, params.charge = VAT.MODE_OVERHAND, 1
    end
    if not params then return nil end
    local launch = VAT.Solver.launch(def, params, cfg)
    local points = {}
    local result = VAT.Solver.predict(def, launch, cfg, maxSteps or 150, 1, points)
    return { points = points, result = result, launch = launch }
end

--[[
Client: throws `item` (in the local player's main inventory) right now with the current Viewpoint aim,
through the same validated server request as a manual throw. opts: mode (VAT.MODE_*), charge (0..1).
Returns the request sequence number or nil.
]]
function API.throwItem(player, item, opts)
    if not (VAT.Throw and VAT.Throw.send and VAT.Controller) then return nil end
    local def = R.resolve(item)
    if not def or not player then return nil end
    opts = opts or {}
    local a = VAT.Controller.computeAim(player)
    a.mode = opts.mode or VAT.MODE_OVERHAND
    a.charge = opts.charge or 0.6
    a.mass = R.massOf(item, def)
    local launch = VAT.Solver.launch(def, a, VAT.Config.server())
    return VAT.Throw.send(player, item, def, launch, a.mode, a.charge, 0, a)
end

function API.addImpactListener(fn) return VAT.addListener("impact", fn) end
function API.removeImpactListener(fn) VAT.removeListener("impact", fn) end
function API.addLandingListener(fn) return VAT.addListener("landing", fn) end
function API.removeLandingListener(fn) VAT.removeListener("landing", fn) end
function API.addDetonationListener(fn) return VAT.addListener("detonation", fn) end
function API.removeDetonationListener(fn) VAT.removeListener("detonation", fn) end
function API.addThrowListener(fn) return VAT.addListener("throw", fn) end
function API.addRestListener(fn) return VAT.addListener("rest", fn) end

--- Live projectiles on this machine (read only).
function API.getActiveProjectiles() return VAT.Projectiles.list end
