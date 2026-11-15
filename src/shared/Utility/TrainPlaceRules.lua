--!strict
-- Playtest Fixes Part D: pure rules for "Train!" (no Instances, no services) so they can be tested.
local Config = require(script.Parent.Parent.Config.PlaytestFixes).TrainPlace

local Rules = {}

export type Input = {
	trainingOn: boolean,
	alive: boolean,
	canAct: boolean,
	busy: boolean,
	carrying: boolean,
	hasCart: boolean,
	alreadyTraining: boolean,
	distance: number, -- player to the Training prompt (studs)
	promptDistance: number, -- that prompt's MaxActivationDistance
}

-- First failing reason in a fixed order, or nil when the player may be placed on the rollers.
function Rules.Check(input: Input): string?
	if not input.trainingOn then
		return "TrainingOff"
	end
	if input.alreadyTraining then
		return "AlreadyTraining"
	end
	if not input.alive then
		return "NotLiving"
	end
	if input.distance > input.promptDistance + Config.ExtraActivationDistance then
		return "TooFar"
	end
	if not input.canAct then
		return "Dazed"
	end
	if input.busy then
		return "Busy"
	end
	if input.carrying then
		return "Carrying"
	end
	if not input.hasCart then
		return "NoCart"
	end
	return nil
end

-- The toast for a refusal (Stud Pop toast via the server Feedback channel).
function Rules.Message(reason: string): string?
	return (Config.Messages :: any)[reason]
end

-- Who trains this tick. Legacy bays keep one occupant (the current one, else the first eligible);
-- the shared bay trains everyone eligible.
function Rules.Occupants(sharedBay: boolean, eligible: { any }, current: any?): { any }
	if sharedBay then
		return table.clone(eligible)
	end
	if current ~= nil and table.find(eligible, current) then
		return { current }
	end
	return if eligible[1] ~= nil then { eligible[1] } else {}
end

-- The bay pose: on the trigger, facing along its LookVector (the way carts drive onto the rollers),
-- standing on `groundY`. `spawnOffset` is CartGeometry.SpawnOffset(cart).
function Rules.BayFrame(trigger: CFrame, groundY: number, spawnOffset: CFrame): CFrame
	local at = Vector3.new(trigger.Position.X, groundY, trigger.Position.Z)
	local look = Vector3.new(trigger.LookVector.X, 0, trigger.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(at, at + look, Vector3.yAxis) * spawnOffset
end

return table.freeze(Rules)
