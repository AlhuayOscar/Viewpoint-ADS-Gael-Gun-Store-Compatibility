-- Viewpoint True Ballistics - client glue.
--
-- In multiplayer, rounds may only fly further than vanilla's weapon range once the server confirms it
-- runs the True Ballistics Java component (otherwise vanilla anti-cheat would reject - or kick for -
-- long hits). Until then the Java side limits hits to the weapon's MaxRange.
--
-- Developer console:
--   VTB_status()                         what is active
--   VTB_describeHeldWeapon()             resolved ballistic profile of the gun in hand
--   VTB_debug("trajectories", true)      3D flight paths / camera ray / muzzle (also "impacts", "network", "verbose", "all")
--   VTB_tracers(5)                       every 5th round is a visible tracer (0 = off)
--   VTB_stress(250)                      250 inert test rounds; then VTB_stats()
--   VTB_effects()                        bullet holes / impact debris settings; VTB_effects("holes", 800),
--                                        VTB_effects("minutes", 60), VTB_effects("debris", 1.5), "on", "off", "clear"

require "VTB/VTB_Core"

local helloTries = 0
local helloTicks = 0
local confirmed = false

local function sendHello()
    local player = getPlayer()
    if not player then return end
    helloTries = helloTries + 1
    sendClientCommand(player, "VTB", "hello", { version = VTB.version })
end

local function onTick()
    if confirmed or not isClient() then
        Events.OnTick.Remove(onTick)
        return
    end
    helloTicks = helloTicks + 1
    if helloTicks >= 300 then -- roughly every 5 seconds
        helloTicks = 0
        if helloTries >= 6 then
            print("[TrueBallistics] server did not answer; it probably does not run True Ballistics' Java part. Hits stay within vanilla weapon range.")
            Events.OnTick.Remove(onTick)
            return
        end
        sendHello()
    end
end

local function onGameStart()
    if VTB_onGameStart then VTB_onGameStart() end
    confirmed = false
    helloTries = 0
    helloTicks = 0
    if isClient() then
        sendHello()
        Events.OnTick.Add(onTick)
    end
end

-- Bullet holes / impact debris of other players (relayed by the server) and our own for them.
local function sendImpacts()
    if not isClient() or not VTB_takeImpacts then return end
    local d = VTB_takeImpacts()
    if d then
        local player = getPlayer()
        if player then sendClientCommand(player, "VTB", "fx", { d = d }) end
    end
end
Events.OnTick.Add(sendImpacts)

local function onServerCommand(module, command, args)
    if module ~= "VTB" then return end
    if command == "fx" then
        if VTB_remoteImpacts and args then VTB_remoteImpacts(args.d) end
        return
    end
    if command ~= "hello" then return end
    confirmed = true
    print("[TrueBallistics] server answered: java=" .. tostring(args ~= nil and args.java) .. " version=" .. tostring(args and args.version))
    local java = args ~= nil and args.java == true
    local version = (args ~= nil and args.version) or ""
    if VTB_setServerConfirmed then VTB_setServerConfirmed(java, version) end
end

Events.OnGameStart.Add(onGameStart)
Events.OnServerCommand.Add(onServerCommand)

-- Multiplayer ammo guard. The server only takes a round out of the magazine when the shot's hit packet
-- arrives, and True Ballistics sends that packet when the round lands (up to a few tenths of a second
-- later). Without this guard, fast fire at the end of a magazine could outrun the server's count and trip
-- vanilla's "not enough ammo" anti-cheat. It only refuses shots the magazine cannot cover.
local function installAmmoGuard()
    if not ISReloadWeaponAction or not ISReloadWeaponAction.canShoot or ISReloadWeaponAction.VTB_guarded then return end
    local original = ISReloadWeaponAction.canShoot
    ISReloadWeaponAction.canShoot = function(player, weapon)
        local ok = original(player, weapon)
        if not ok or not isClient() then return ok end
        if player:isUnlimitedAmmo() then return ok end
        local pending = VTB_pendingRounds()
        if not pending or pending <= 0 then return ok end
        local available = weapon:getCurrentAmmoCount()
        if weapon:haveChamber() and weapon:isRoundChambered() then available = available + 1 end
        if pending >= available then return false end
        return ok
    end
    ISReloadWeaponAction.VTB_guarded = true
end

Events.OnGameStart.Add(installAmmoGuard)
