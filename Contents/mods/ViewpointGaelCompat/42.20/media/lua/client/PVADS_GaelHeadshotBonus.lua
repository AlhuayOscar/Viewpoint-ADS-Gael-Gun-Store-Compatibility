-- The game's OnHitZombie event runs after it picks the hit body part and
-- immediately before IsoZombie delegates to IsoGameCharacter.Hit for damage.
local function onHitZombie(zombie, attacker, bodyPart, weapon)
    if not (zombie and attacker and weapon and bodyPart) then return end
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    if not (aim and aim.markHeadshot) then return end
    local ok, bonusApplies = pcall(aim.markHeadshot, zombie, attacker, weapon,
        bodyPart == BodyPartType.Head)
    if not ok or not bonusApplies then return end
    local vars = SandboxVars and SandboxVars.PVADSGAEL2
    if vars and vars.HeadshotImpactSound == false then return end
    local square = zombie:getSquare()
    if not square then return end
    local variant = ZombRand(1, 4)
    local soundManager = getSoundManager()
    if soundManager then
        soundManager:PlayWorldSound("ViewpointGaelHeadImpact" .. variant,
            square, 0, 24, 1, false)
    end
end

Events.OnHitZombie.Add(onHitZombie)
