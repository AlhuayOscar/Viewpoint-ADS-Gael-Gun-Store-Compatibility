require "ISUI/ISPanel"

local ThirdPersonCrosshair = ISPanel:derive("PVADSGaelThirdPersonCrosshair")

local function safeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    return ok and value or nil
end

local function aimingInThirdPerson(player)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    if vars and vars.ThirdPersonCrosshair == false then return false end
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    if not aim or not aim.isThirdPerson or not player then return false end
    local ok, thirdPerson = pcall(aim.isThirdPerson)
    if not ok or thirdPerson ~= true or safeCall(player, "isAiming") ~= true then
        return false
    end
    local weapon = safeCall(player, "getPrimaryHandItem")
    return safeCall(weapon, "isRanged") == true
end

local function updateCrosshairVisibility()
    local panel = PVADS and PVADS.gaelThirdPersonCrosshair
    if not panel then return end
    local shouldShow = aimingInThirdPerson(getSpecificPlayer(0))
    if panel:isVisible() ~= shouldShow then
        panel:setVisible(shouldShow)
        if shouldShow then panel:backMost() end
    end
end

local function armPenalty(player)
    local body = safeCall(player, "getBodyDamage")
    local bodyTypes = BodyPartType
    if not body or not bodyTypes then return 0 end
    local parts = {
        bodyTypes.Hand_L, bodyTypes.Hand_R,
        bodyTypes.ForeArm_L, bodyTypes.ForeArm_R,
        bodyTypes.UpperArm_L, bodyTypes.UpperArm_R,
    }
    local stiffness, pain = 0, 0
    for _, partType in ipairs(parts) do
        local part = safeCall(body, "getBodyPart", partType)
        stiffness = math.max(stiffness, tonumber(safeCall(part, "getStiffness")) or 0)
        pain = math.max(pain, tonumber(safeCall(part, "getPain")) or 0)
    end
    local balance = rawget(_G, "PVADS_GaelRecoilBalance")
    if balance and balance.armPenalty then
        local ok, value = pcall(balance.armPenalty, stiffness, pain)
        if ok then return math.max(0, tonumber(value) or 0) end
    end
    return math.max(stiffness >= 20 and 3 or (stiffness >= 5 and 1.5 or 0),
        math.max(0, math.min(100, pain)) * 0.03)
end

function ThirdPersonCrosshair:new()
    local core = getCore()
    local o = ISPanel.new(self, 0, 0, core:getScreenWidth(), core:getScreenHeight())
    o.background = false
    o.border = false
    o:noBackground()
    o.gap = 7
    o.lastAt = nil
    return o
end

function ThirdPersonCrosshair:isMouseOver()
    return false
end

function ThirdPersonCrosshair:instantiate()
    ISPanel.instantiate(self)
    self.javaObject:setConsumeMouseEvents(false)
end

function ThirdPersonCrosshair:onMouseDown()
    return false
end

function ThirdPersonCrosshair:onMouseUp()
    return false
end

function ThirdPersonCrosshair:render()
    local core = getCore()
    local width, height = core:getScreenWidth(), core:getScreenHeight()
    if self.width ~= width then self:setWidth(width) end
    if self.height ~= height then self:setHeight(height) end

    local player = getSpecificPlayer(0)
    if not aimingInThirdPerson(player) then
        self.lastAt = nil
        return
    end

    local now = getTimestampMs()
    local dt = math.min(0.1, math.max(0, (now - (self.lastAt or now)) / 1000))
    self.lastAt = now
    local scale = math.max(0.65, math.min(1.5, height / 1080))
    local spread = 0
    if safeCall(player, "isPlayerMoving") == true then
        spread = safeCall(player, "isSprinting") == true and 22
            or (safeCall(player, "isRunning") == true and 14 or 7)
    end
    local moodles = safeCall(player, "getMoodles")
    local enduranceType = MoodleType and MoodleType.ENDURANCE
    local exertion = enduranceType
        and (tonumber(safeCall(moodles, "getMoodleLevel", enduranceType)) or 0) or 0
    spread = spread + math.max(0, math.min(4, exertion)) * 2.5
    spread = spread + armPenalty(player) * 2.5
    local targetGap = math.min(58, (7 + spread) * scale)
    local step = math.max(0.5, dt * 55 * scale)
    if math.abs(targetGap - self.gap) <= step then
        self.gap = targetGap
    else
        self.gap = self.gap + (targetGap > self.gap and step or -step)
    end

    local centerX, centerY = math.floor(width / 2), math.floor(height / 2)
    local gap = math.floor(self.gap + 0.5)
    local barLength, thickness, centerLength = math.floor(11 * scale), math.max(2, math.floor(2 * scale)), math.floor(11 * scale)
    local sideY = centerY - math.floor(thickness / 2)
    local leftX, rightX = centerX - gap - barLength, centerX + gap
    local outline = { r = 0.02, g = 0.02, b = 0.02, a = 0.85 }
    local mark = { r = 0.92, g = 0.96, b = 1.00, a = 0.95 }
    for _, x in ipairs({ leftX, rightX }) do
        self:drawRect(x - 1, sideY - 1, barLength + 2, thickness + 2,
            outline.a, outline.r, outline.g, outline.b)
        self:drawRect(x, sideY, barLength, thickness,
            mark.a, mark.r, mark.g, mark.b)
    end
    local verticalX = centerX - math.floor(thickness / 2)
    local verticalY = centerY - math.floor(centerLength / 2)
    self:drawRect(verticalX - 1, verticalY - 1, thickness + 2, centerLength + 2,
        outline.a, outline.r, outline.g, outline.b)
    self:drawRect(verticalX, verticalY, thickness, centerLength,
        mark.a, mark.r, mark.g, mark.b)
end

local function installThirdPersonCrosshair()
    if PVADS and PVADS.gaelThirdPersonCrosshair then return end
    local crosshair = ThirdPersonCrosshair:new()
    crosshair:initialise()
    crosshair:instantiate()
    -- Keep this full-screen drawing panel behind real UI windows. Click-through
    -- alone is insufficient because the UI hover test also considers z-order.
    crosshair:setAlwaysOnTop(false)
    crosshair:addToUIManager()
    crosshair:backMost()
    crosshair:setVisible(false)
    PVADS = PVADS or {}
    PVADS.gaelThirdPersonCrosshair = crosshair
end

Events.OnGameStart.Add(installThirdPersonCrosshair)
Events.OnTick.Add(updateCrosshairVisibility)
