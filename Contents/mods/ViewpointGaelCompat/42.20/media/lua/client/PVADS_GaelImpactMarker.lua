require "ISUI/ISPanel"

local ImpactMarker = ISPanel:derive("PVADSGaelImpactMarker")

function ImpactMarker:new()
    local core = getCore()
    local o = ISPanel.new(self, 0, 0, core:getScreenWidth(), core:getScreenHeight())
    o.background = false
    o.border = false
    o:noBackground()
    return o
end

function ImpactMarker:isMouseOver()
    return false
end

function ImpactMarker:onMouseDown()
    return false
end

function ImpactMarker:onMouseUp()
    return false
end

local function renderSGTBDebugTrajectory(panel, aim)
    local vars = SandboxVars and SandboxVars.ViewpointGaelCompat
    if not (vars and vars.SGTBDebugTrajectory) or not aim.ballisticTrailCount or not aim.ballisticTrailPath then return end
    local okCount, count = pcall(aim.ballisticTrailCount)
    if not okCount then return end
    count = math.min(8, math.max(0, tonumber(count) or 0))
    for trailIndex = 0, count - 1 do
        local okPath, encoded = pcall(aim.ballisticTrailPath, trailIndex)
        if okPath and type(encoded) == "string" then
            local previousX, previousY
            for pair in string.gmatch(encoded, "[^;]+") do
                local sx, sy = string.match(pair, "([^,]+),([^,]+)")
                sx, sy = tonumber(sx), tonumber(sy)
                if sx and sy then
                    if previousX then
                        panel:drawLine2(previousX, previousY, sx, sy, 0.10, 0.82, 1.00, 0.78)
                    end
                    previousX, previousY = sx, sy
                end
            end
        end
    end
end

function ImpactMarker:render()
    local core = getCore()
    if self.width ~= core:getScreenWidth() then self:setWidth(core:getScreenWidth()) end
    if self.height ~= core:getScreenHeight() then self:setHeight(core:getScreenHeight()) end
    local root = rawget(_G, "ViewpointGael")
    local aim = root and root.Aim
    if not aim then return end
    renderSGTBDebugTrajectory(self, aim)
    if not aim.impactVisible then return end
    local ok, visible = pcall(aim.impactVisible)
    if not ok or visible ~= true then return end
    local okX, x = pcall(aim.impactScreenX)
    local okY, y = pcall(aim.impactScreenY)
    if not okX or not okY then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x ~= x or y ~= y then return end

    -- Black outline keeps the real impact marker legible over bright surfaces.
    self:drawRect(x - 7, y - 7, 15, 15, 0.95, 0.02, 0.05, 0.02)
    self:drawRect(x - 4, y - 4, 9, 9, 1.00, 0.10, 1.00, 0.20)
    local label = ""
    local okLabel, value = pcall(aim.impactLabel)
    if okLabel and value then label = tostring(value) end
    if label ~= "" then
        local width = getTextManager():MeasureStringX(UIFont.Small, label)
        local left = math.min(getCore():getScreenWidth() - width - 12, x + 11)
        self:drawText(label, left, y + 8, 0.10, 1.00, 0.20, 1.00, UIFont.Small)
    end
end

local function installImpactMarker()
    if PVADS and PVADS.gaelImpactMarker then return end
    local marker = ImpactMarker:new()
    marker:initialise()
    marker:instantiate()
    marker:setAlwaysOnTop(true)
    marker:addToUIManager()
    PVADS = PVADS or {}
    PVADS.gaelImpactMarker = marker
end

Events.OnGameStart.Add(installImpactMarker)
