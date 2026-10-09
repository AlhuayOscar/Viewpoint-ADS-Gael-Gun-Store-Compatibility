-- A quiet character grunt when the player tries to fire an already jammed gun.
-- Uses the game's voice events and leaves the weapon jam and firing logic intact.
local VOLUME = 0.30
local COOLDOWN_MS = 1200
local FADE_START_MS = 450
local VOICE_END_MS = 750

local lastWeapon = nil
local lastAttackDown = false
local lastJammed = false
local lastVoiceAt = -COOLDOWN_MS
local activeSoundId = nil

local function trimLongVoice(player, now)
    if not activeSoundId then return end
    local elapsed = now - lastVoiceAt
    local emitter = player:getEmitter()
    if not emitter then activeSoundId = nil; return end
    if elapsed >= VOICE_END_MS then
        emitter:stopSound(activeSoundId)
        activeSoundId = nil
    elseif elapsed >= FADE_START_MS then
        emitter:setVolume(activeSoundId,
            VOLUME * (VOICE_END_MS - elapsed) / (VOICE_END_MS - FADE_START_MS))
    end
end

local function onPlayerUpdate(player)
    if player ~= getSpecificPlayer(0) then return end
    local now = getTimestampMs()
    trimLongVoice(player, now)

    local weapon = player:getPrimaryHandItem()
    local firearm = weapon and instanceof(weapon, "HandWeapon") and weapon:isAimedFirearm()
    local jammed = firearm and weapon:isJammed() or false
    local attackDown = firearm and player:isAiming() and player:isAttackButtonDown()
        and not player:isDoShove() or false
    local changedWeapon = weapon ~= lastWeapon
    local attemptedJammedShot = attackDown and jammed
        and (not lastAttackDown or (not lastJammed and not changedWeapon))

    lastWeapon = weapon
    lastAttackDown = attackDown
    lastJammed = jammed
    if not attemptedJammedShot then return end

    if now - lastVoiceAt < COOLDOWN_MS then return end
    local emitter = player:getEmitter()
    if not emitter then return end
    local sound = player:isFemale() and "VoiceFemalePainFromRunIntoWall"
        or "VoiceMalePainFromRunIntoWall"
    local soundId = emitter:playSound(sound)
    if not soundId or soundId == 0 then return end
    emitter:setVolume(soundId, VOLUME)
    activeSoundId = soundId
    lastVoiceAt = now
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
