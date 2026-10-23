require "ISUI/ISUIElement"
require "VAT/VAT_Controller"

--[[
Screen overlay (click-through, never takes mouse input):
  * trajectory preview while a throw is being prepared (Off / Simple / Full, server-capped):
      Simple  a small ring where the object will first touch something
      Full    plus a faint dotted arc of the real simulated path and its resting point
  * a thin charge bar under the crosshair (optional)
  * debug drawing (only with the debug option, and only where the server allows it): release point,
    camera ray hit, launch velocity, predicted path, actual paths, collision points and normals,
    classification and network ownership of every live projectile
  * in the normal isometric view (Viewpoint off) thrown objects are drawn as item icons
Points are projected with Viewpoint's camera (VAT_project) or the isometric camera (isoToScreenX/Y).

Out of the way of every other window: the game lets a window take a mouse-wheel scroll, an item
drop or a tooltip only when no UI element above it covers that point, and drag-to-floor, moveable
placement and the minimap check the same thing (UIElement.isPointOver on every top-level element;
it counts any VISIBLE element, also one that lets clicks through, and skips hidden ones). A
full-screen overlay therefore blocked all of that whenever it was visible. This overlay is a
0 x 0 element at the screen corner: isPointOver is false for it at every point (local x is never
below its width of 0), so it can never cover anything, whether it is drawing or not. Drawing is not
clipped to an element's own size (UIElement.render runs prerender/render with absolute coordinates
and no stencil unless one is set), so it still draws anywhere on screen. It is also kept behind every
other window (backMost) and is never always-on-top.
]]

VATOverlay = ISUIElement:derive("VATOverlay")

local C = VAT.Controller
local M = VAT.Projectiles
local S = VAT.S
local scr = {}
local trails = {}                 -- projectile -> list of {x,y,h}
local hits = {}                   -- recent collision points (debug)
local MAX_HITS = 24
local icons = {}                  -- fullType -> item used for its icon (or false)

local function iconItem(fullType)
    local it = icons[fullType]
    if it == nil then
        local created = VAT.createItem(fullType); local ok = created ~= nil
        it = (ok and created) or false
        icons[fullType] = it
    end
    return it or nil
end

function VATOverlay:new()
    local o = ISUIElement.new(self, 0, 0, 0, 0)      -- 0 x 0: can never be "over" anything
    return o
end

function VATOverlay:instantiate()
    ISUIElement.instantiate(self)
    self.javaObject:setConsumeMouseEvents(false)
end

function VATOverlay:onMouseDown() return false end
function VATOverlay:onMouseUp() return false end
function VATOverlay:onRightMouseDown() return false end
function VATOverlay:onRightMouseUp() return false end
function VATOverlay:onMouseWheel() return false end

function VATOverlay:prerender()
    -- stays 0 x 0 whatever the resolution; the screen size is read where something is drawn
    if self.width ~= 0 or self.height ~= 0 then self:setWidth(0); self:setHeight(0) end
end

local function viewpointDraws(player)
    return VAT_viewpointOwns ~= nil and VAT_viewpointOwns(player) == true
end

--- World point -> screen; returns x, y or nil when not visible.
local function project(player, x, y, h)
    if viewpointDraws(player) then
        if VAT_project and VAT_project(scr, x, y, h) then return scr.sx, scr.sy, scr.depth end
        return nil
    end
    local z = h / S
    return isoToScreenX(player:getPlayerNum(), x, y, z), isoToScreenY(player:getPlayerNum(), x, y, z), 6
end

function VATOverlay:ring(x, y, r, a, cr, cg, cb)
    local n = 12
    for i = 0, n - 1 do
        local ang = i / n * math.pi * 2
        self:drawRect(x + math.cos(ang) * r - 1, y + math.sin(ang) * r * 0.55 - 1, 2, 2, a, cr, cg, cb)
    end
end

function VATOverlay:drawPreview(player)
    local mode = VAT.Config.previewMode()
    if mode <= 1 or not C.preview.valid or C.state ~= "charging" then return end
    local res = C.preview.result
    if not res then return end
    if mode >= 3 then
        local pts = C.preview.points
        for i = 2, res.count, 2 do
            local p = pts[i]
            if p then
                local sx, sy = project(player, p.x, p.y, p.h)
                if sx then
                    local a = 0.32 * (1 - i / (res.count + 4))
                    self:drawRect(sx - 1, sy - 1, 2, 2, a, 0.95, 0.92, 0.85)
                end
            end
        end
        local rx, ry = project(player, res.restX, res.restY, res.restH)
        if rx then self:drawRect(rx - 1.5, ry - 1.5, 3, 3, 0.35, 0.95, 0.92, 0.85) end
    end
    local land = res.landing or { x = res.restX, y = res.restY, h = res.restH }
    local lx, ly, depth = project(player, land.x, land.y, land.h)
    if lx then
        local r = VAT.clamp(160 / math.max(depth or 6, 0.5), 4, 20)
        self:ring(lx, ly, r, 0.5, 0.95, 0.92, 0.85)
    end
end

function VATOverlay:drawCharge()
    if not VAT.Config.client.chargeIndicator then return end
    if C.state ~= "charging" then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, cx, cy = 46, sw / 2, sh / 2 + 26
    self:drawRect(cx - w / 2, cy, w, 2, 0.18, 1, 1, 1)
    local c = C.charge or 0
    self:drawRect(cx - w / 2, cy, w * c, 2, 0.35 + 0.3 * c, 0.95, 0.92, 0.85)
    if C.cookStart and C.def and C.def.fuse and C.def.fuse.seconds then
        local left = 1 - VAT.clamp((VAT.nowSeconds() - C.cookStart) / C.def.fuse.seconds, 0, 1)
        self:drawRect(cx - w / 2, cy + 4, w * left, 2, 0.6, 1, 0.35, 0.2)
    end
end

function VATOverlay:drawIsoProjectiles(player)
    if viewpointDraws(player) then return end
    local list = M.list
    for i = 1, #list do
        local proj = list[i]
        if proj.phase ~= "done" and proj.localEnd ~= "detonate" and proj.localEnd ~= "break" then
            local x, y, h = M.renderPos(proj)
            local sx, sy = project(player, x, y, h)
            local item = iconItem(proj.fullType or proj.def.fullType or "")
            if sx and item then self:drawItemIcon(item, sx - 8, sy - 8, 1, 16, 16) end
        end
    end
end

-- ------------------------------------------------------------------ debug
M.on("impact", function(proj, hit)
    if not (VAT.Config.client.debugDraw) then return end
    table.insert(hits, { x = hit.x, y = hit.y, h = hit.h, nx = hit.nx, ny = hit.ny, nh = hit.nh, kind = hit.kind,
        t = VAT.nowSeconds(), auth = proj.authority })
    while #hits > MAX_HITS do table.remove(hits, 1) end
end)

M.on("removed", function(proj) trails[proj] = nil end)

function VATOverlay:line(player, x0, y0, h0, x1, y1, h1, a, r, g, b)
    local ax, ay = project(player, x0, y0, h0)
    local bx, by = project(player, x1, y1, h1)
    if ax and bx then self:drawLine2(ax, ay, bx, by, a, r, g, b) end
end

function VATOverlay:drawDebug(player)
    if not VAT.Config.debugDrawAllowed(player) then return end
    local font = UIFont.Small
    local y = 60
    local function text(s, r, g, b)
        self:drawText(s, 12, y, r or 1, g or 1, b or 1, 0.9, font)
        y = y + 15
    end
    text("[ViewpointThrow] " .. (VAT_status and VAT_status() or "java bridge missing"), 0.6, 1, 1)
    text(string.format("state=%s charge=%.2f mode=%s live=%d", C.state, C.charge or 0,
        VAT.MODE_NAMES[C.preview.mode or C.throwMode or 1] or "?", #M.list))
    local item = player:getPrimaryHandItem()
    local def = item and VAT.Registry.resolve(item)
    if def then
        text(string.format("held %s: source=%s kind=%s material=%s fuse=%s%s behaviors=%s mass=%.2f",
            def.fullType, tostring(def.source), tostring(def.kind), tostring(def.material), tostring(def.fuse.type),
            def.fuse.seconds and string.format("(%.1fs)", def.fuse.seconds) or "", table.concat(def.behaviors, ","),
            VAT.Registry.massOf(item, def)))
    elseif item then
        text("held " .. item:getFullType() .. ": not throwable", 1, 0.6, 0.6)
    end

    local a = C.debug.aimInfo
    if a then
        self:line(player, a.cx, a.cy, a.ch, a.cx + a.fx * 3, a.cy + a.fy * 3, a.ch + a.fh * 3, 0.6, 1, 1, 0)
        if a.hit then
            local sx, sy = project(player, a.tx, a.ty, a.th)
            if sx then self:drawRect(sx - 3, sy - 3, 6, 6, 0.9, 1, 1, 0) end
        end
        local ox, oy = project(player, a.ox, a.oy, a.oh)
        if ox then self:drawRect(ox - 3, oy - 3, 6, 6, 0.9, 0, 1, 1) end
        local l = C.debug.launch
        if l then
            self:line(player, l.ox, l.oy, l.oh, l.ox + l.vx * 0.2, l.oy + l.vy * 0.2, l.oh + l.vh * 0.2, 0.9, 1, 0.55, 0)
            text(string.format("hand=%s third=%s hit=%s speed=%.1f m/s v=(%.1f %.1f %.1f)", tostring(a.handSource),
                tostring(a.third), tostring(a.hit), l.speed or 0, l.vx, l.vy, l.vh))
        end
    end
    -- predicted path (always, in debug)
    if C.preview.valid and C.preview.result then
        local pts = C.preview.points
        for i = 1, C.preview.result.count do
            local p = pts[i]
            local sx, sy = p and project(player, p.x, p.y, p.h)
            if sx then self:drawRect(sx - 1, sy - 1, 2, 2, 0.8, 0.2, 1, 0.2) end
        end
    end
    -- live projectiles: actual paths, state and ownership
    local list = M.list
    for i = 1, #list do
        local proj = list[i]
        local tr = trails[proj]
        if not tr then tr = {}; trails[proj] = tr end
        local x, y, h = M.renderPos(proj)
        local last = tr[#tr]
        if not last or VAT.len3(last.x - x, last.y - y, last.h - h) > 0.15 then
            tr[#tr + 1] = { x = x, y = y, h = h }
            if #tr > 80 then table.remove(tr, 1) end
        end
        for j = 2, #tr do
            self:line(player, tr[j - 1].x, tr[j - 1].y, tr[j - 1].h, tr[j].x, tr[j].y, tr[j].h, 0.7, 1, 0.25, 0.25)
        end
        local sx, sy = project(player, x, y, h)
        if sx then
            local sp = VAT.len3(proj.vx, proj.vy, proj.vh)
            local role = proj.authority and "server" or (proj.predicted and "predicted" or "mirror")
            self:drawText(string.format("#%s %s %s %.1fm/s %s%s", tostring(proj.id), proj.phase, role, sp,
                tostring(proj.def.kind), proj.fuseLeft and string.format(" fuse %.1f", proj.fuseLeft) or ""),
                sx + 8, sy - 6, 1, 0.8, 0.8, 0.9, font)
        end
    end
    local t = VAT.nowSeconds()
    for i = 1, #hits do
        local hp = hits[i]
        if t - hp.t < 8 then
            local sx, sy = project(player, hp.x, hp.y, hp.h)
            if sx then self:drawRect(sx - 2, sy - 2, 4, 4, 0.9, 1, 0, 1) end
            self:line(player, hp.x, hp.y, hp.h, hp.x + hp.nx * 0.4, hp.y + hp.ny * 0.4, hp.h + hp.nh * 0.4, 0.8, 1, 0, 1)
        end
    end
end

--- True only when the overlay has something to draw (diagnostics; drawing itself checks the same).
function VATOverlay.wanted(player)
    if not player then return false end
    if C.state == "charging" then return true end
    local F = VAT.FxClient
    if F and F.whiteAlpha and F.whiteAlpha(VAT.nowSeconds()) > 0.003 then return true end
    if #M.list > 0 and not viewpointDraws(player) then return true end
    if VAT.Config.debugDrawAllowed(player) then return true end
    return false
end
VATOverlay.needed = VATOverlay.wanted

VATOverlay.BACK_EVERY = 60        -- ticks between pushing the element behind newly opened windows

--- Every tick: a 0 x 0 element never blocks anything, so it stays visible; it is only kept at the
--- back and at size 0 (in case any code resized it).
function VATOverlay:updateVisibility()
    if not self:getIsVisible() then self:setVisible(true) end
    if self.width ~= 0 or self.height ~= 0 then self:setWidth(0); self:setHeight(0) end
    self.backTicks = (self.backTicks or 0) + 1
    if self.backTicks >= VATOverlay.BACK_EVERY then
        self:backMost()
        self.backTicks = 0
    end
end

function VATOverlay:render()
    local player = getPlayer()
    if not player then return end
    local ok, err = pcall(function()
        self:drawIsoProjectiles(player)
        self:drawPreview(player)
        self:drawCharge()
        self:drawDebug(player)
        if VAT.FxClient and VAT.FxClient.drawWhiteout then VAT.FxClient.drawWhiteout(self) end
    end)
    if not ok then VAT.Log.once("overlay", "Overlay draw failed: %s", tostring(err)) end
end

local function create()
    if VAT.overlay then return end
    local o = VATOverlay:new()
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(false)
    o:backMost()
    o:setVisible(true)
    VAT.overlay = o
end

Events.OnGameStart.Add(create)
Events.OnTick.Add(function()
    local o = VAT.overlay
    if not o then return end
    local ok, err = pcall(o.updateVisibility, o)
    if not ok then VAT.Log.once("overlayVisibility", "Overlay visibility failed: %s", tostring(err)) end
end)
