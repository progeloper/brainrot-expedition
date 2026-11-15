--!strict

export type Config = {
	MeaningfulMovementSpeed: number,
	MovementConfirmationDuration: number,
}

local CartAnalyticsMovementTracker = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function CartAnalyticsMovementTracker.Advance(
	candidateStartedAt: number?,
	alreadyEmitted: boolean,
	horizontalSpeed: number,
	now: number,
	eligible: boolean,
	config: Config
): (number?, boolean, boolean)
	if alreadyEmitted then
		return nil, true, false
	end

	if
		not eligible
		or not isFiniteNumber(horizontalSpeed)
		or not isFiniteNumber(now)
		or horizontalSpeed < config.MeaningfulMovementSpeed
	then
		return nil, false, false
	end

	if
		candidateStartedAt == nil
		or not isFiniteNumber(candidateStartedAt)
		or now < candidateStartedAt
	then
		return now, false, false
	end

	if now - candidateStartedAt < config.MovementConfirmationDuration then
		return candidateStartedAt, false, false
	end

	return nil, true, true
end

return table.freeze(CartAnalyticsMovementTracker)
