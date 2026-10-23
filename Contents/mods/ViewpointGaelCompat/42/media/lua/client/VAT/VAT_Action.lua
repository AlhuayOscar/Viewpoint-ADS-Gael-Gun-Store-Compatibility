require "TimedActions/ISBaseTimedAction"
require "VAT/VAT_Core"

--[[
The throw animation as a client-side timed action.

It has no complete() method, so the game treats it as a purely local action (LuaTimedActionNew sets
useCustomRemoteTimedActionSync): nothing about it is sent to the server; the throw itself goes
through VAT's own validated request.

Stages, driven by the anim variable VATThrowPhase (see media/AnimSets/player/actions/VATThrow*.xml):
  ready   item raised in the one-hand aim pose while the throw is prepared and charged
  over    overhand throw clip; event VATRelease at the moment the hand opens
  under   the same clip played faster for underhand tosses and rolls (Build 42 ships one throw clip)
The projectile leaves the hand only on the VATRelease event (or a timed failsafe if another mod
replaced the animation), never at the button press. VATThrowDone ends the action after recovery.
]]

VATThrowAction = ISBaseTimedAction:derive("VATThrowAction")

function VATThrowAction:new(character, item, controller)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.controller = controller
    o.maxTime = -1
    o.stopOnWalk = false
    o.stopOnRun = false
    o.stopOnAim = false
    o.useProgressBar = false
    o.released = false
    return o
end

function VATThrowAction:isValid()
    if self.released then return true end                -- the item has already left the hand
    return self.character:getPrimaryHandItem() == self.item
end

function VATThrowAction:waitToStart()
    return false
end

function VATThrowAction:start()
    self:setActionAnim("VATThrow")
    self:setAnimVariable("VATThrowPhase", "ready")
    self:setOverrideHandModels(self.item, nil)
    if self.controller then self.controller:onActionStarted(self) end
end

function VATThrowAction:setPhase(phase)
    self:setAnimVariable("VATThrowPhase", phase)
end

--- Called by the controller once the projectile is away: the hand is empty for the follow-through.
function VATThrowAction:handEmpty()
    self.released = true
    self:setOverrideHandModels(nil, nil)
end

function VATThrowAction:update()
    -- the controller no longer owns this action (reset after an error): end it, never linger
    if self.orphaned or (self.controller and self.controller.action ~= self) then
        self:forceStop()
        return
    end
    if self.controller then self.controller:onActionUpdate(self) end
end

function VATThrowAction:animEvent(event, parameter)
    if event == "VATRelease" then
        if self.controller then self.controller:onReleasePoint(self) end
    elseif event == "VATThrowDone" then
        self:forceComplete()
    end
end

function VATThrowAction:stop()
    if self.controller then self.controller:onActionEnded(self, false) end
    ISBaseTimedAction.stop(self)
end

function VATThrowAction:perform()
    if self.controller then self.controller:onActionEnded(self, true) end
    ISBaseTimedAction.perform(self)
end
