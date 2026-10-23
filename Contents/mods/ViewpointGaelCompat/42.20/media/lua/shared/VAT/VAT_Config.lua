require "VAT/VAT_Core"

--[[
Configuration.

Gameplay values are SERVER controlled (sandbox options, page "Viewpoint Throwables"). The server never
trusts a client copy: VAT.Config.server() reads SandboxVars on whichever side calls it, and the dedicated
server's SandboxVars are the authority. Clients receive the same SandboxVars from the server on join,
so their prediction uses the same numbers.

Personal preferences (preview style, keys, debug drawing) live in VAT.Config.client and come from
Mod Options (client/VAT/VAT_Options.lua). A client can only lower the preview below the server ceiling.
]]

VAT.Config = VAT.Config or {}
local C = VAT.Config

C.PREVIEW_OFF, C.PREVIEW_SIMPLE, C.PREVIEW_FULL = 1, 2, 3

--- Defaults for every sandbox value (also used when SandboxVars is missing, e.g. very early on boot).
C.defaults = {
    Enabled = true,
    StrengthMultiplier = 1.0,
    MinThrowSpeed = 5.0,          -- m/s at zero charge (quick tap)
    MaxThrowSpeed = 16.0,         -- m/s at full charge for a ~1 kg object, overhand
    ChargeTime = 1.1,             -- seconds to reach full charge
    EnableUnderhand = true,
    EnableRolling = true,
    MomentumInfluence = 0.6,      -- share of the thrower's velocity added to the throw
    ImpactDamage = true,
    ImpactDamageMultiplier = 1.0,
    PlayerImpactDamage = false,   -- thrown objects hurting players (also needs server PVP)
    ZombieDistraction = true,
    DistractionMultiplier = 1.0,
    ObjectThrowing = true,        -- non-explosive inventory objects can be thrown
    MaxObjectWeight = 3.0,
    GrenadeBounceMultiplier = 1.0,
    ObjectBounceMultiplier = 1.0,
    WindowBreaking = true,
    ServerValidation = true,
    MaxPreview = 3,               -- 1 Off, 2 Simple, 3 Full: the most a client may show
    AllowCooking = true,          -- only for items whose definition says cookable
    MaxActivePerPlayer = 6,
    ThrowCooldown = 0.35,
    GravityMultiplier = 1.0,
    DebugLogging = false,
    AllowDebugDraw = false,
    FlashbangBlinds = true,       -- a flashbang whites out the screen of players who see it
    FlashbangRange = 16.0,        -- tiles
    FireDamageMultiplier = 1.0,   -- incendiary fires burn zombies to death (0 = only the game's own fire)
    LauncherSpeed = 32.0,         -- m/s a launched 40 mm grenade leaves the muzzle at
}

--- Client preferences (overwritten by Mod Options when they load).
C.client = {
    previewMode = 1,              -- Off by default; players can enable the preview in Mod Options
    previewWhileCharging = true,
    chargeIndicator = true,
    debugDraw = false,
    attackThrows = true,          -- the game's Attack binding throws vanilla throwables in Viewpoint
    crouchRolls = true,
    autoArc = false,              -- aim assist: solve the arc onto the crosshair point
    autoEquipNext = false,
    keyThrow = 34,                -- Keyboard.KEY_G
    keyCancel = 45,               -- Keyboard.KEY_X
    keyUnderhand = 56,            -- Keyboard.KEY_LMENU (left Alt)
    keyRoll = 0,                  -- unbound by default; crouching rolls when crouchRolls is on
    keyCook = 0,                  -- unbound: only items registered as cookable use it
    effects = true,               -- 3D explosion, smoke and flash effects in Viewpoint
    fireEffects = true,           -- 3D flames and smoke for every fire in view
    effectLights = true,          -- explosions and fires light up the scene
    effectQuality = 2,            -- 1 low, 2 normal, 3 high (particle counts)
}

local cache, cacheStamp = nil, -1

--- Server-controlled values merged over defaults. Cheap: rebuilt at most once per second.
function C.server()
    local now = getTimestampMs and getTimestampMs() or 0
    if cache and now - cacheStamp < 1000 then return cache end
    local out = {}
    for k, v in pairs(C.defaults) do out[k] = v end
    local sv = SandboxVars and SandboxVars.ViewpointThrowables
    if type(sv) == "table" then
        for k, d in pairs(C.defaults) do
            local v = sv[k]
            if v ~= nil and type(v) == type(d) then out[k] = v end
        end
    end
    -- sanity: a broken preset must not create impossible physics
    out.MinThrowSpeed = VAT.clamp(out.MinThrowSpeed, 0.5, 40)
    out.MaxThrowSpeed = VAT.clamp(math.max(out.MaxThrowSpeed, out.MinThrowSpeed + 0.5), 1, 60)
    out.ChargeTime = VAT.clamp(out.ChargeTime, 0.1, 6)
    out.GravityMultiplier = VAT.clamp(out.GravityMultiplier, 0.2, 3)
    out.MaxActivePerPlayer = math.floor(VAT.clamp(out.MaxActivePerPlayer, 1, 50))
    out.LauncherSpeed = VAT.clamp(out.LauncherSpeed, 10, 90)
    out.gravity = 9.81 * out.GravityMultiplier
    cache, cacheStamp = out, now
    VAT.debug = out.DebugLogging or C.client.debugDraw or false
    return out
end

function C.invalidate() cache = nil end

--- Effective preview mode for this client (personal choice, never above the server ceiling).
function C.previewMode()
    local cap = C.server().MaxPreview or 3
    return math.min(C.client.previewMode or 2, cap)
end

--- Debug drawing is personal but only when the server allows it, or in single player / for admins.
function C.debugDrawAllowed(player)
    if not C.client.debugDraw then return false end
    if not isClient() then return true end
    if C.server().AllowDebugDraw then return true end
    local ok, level = pcall(function() return player and player:getAccessLevel() end)
    return ok and level ~= nil and level ~= "" and level ~= "None"
end
