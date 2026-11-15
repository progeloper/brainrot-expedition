--!strict
-- Pure presentation arithmetic; never rounds authoritative HP.
local Rules = {}
function Rules.FormatHp(value: number): string
	local text = string.format("%.2f", math.max(0, value))
	return (text:gsub("0+$", ""):gsub("%.$", ""))
end
function Rules.Sample(remaining: number, maximum: number, sleepUntil: number?, now: number): any
	if maximum ~= maximum or maximum <= 0 or math.abs(maximum) == math.huge then
		return nil
	end
	local hp = math.clamp(remaining, 0, maximum)
	local fraction = hp / maximum
	local time = if type(sleepUntil) == "number" then math.max(0, sleepUntil - now) else nil
	return {
		fraction = fraction,
		text = Rules.FormatHp(hp) .. " / " .. Rules.FormatHp(maximum),
		color = if fraction > 0.5 then "Green" elseif fraction > 0.25 then "Amber" else "Red",
		sleeping = time ~= nil,
		remainingSeconds = time,
		waking = time ~= nil and time <= 3,
		countdown = if time
			then string.format("%s %.1fs", if time <= 3 then "WAKING" else "ASLEEP", math.ceil(time * 10) / 10)
			else nil,
	}
end
-- A combat readout follows physical weapon reach, while BillboardGui culling
-- measures from the offset camera. These are separate presentation distances.
local function finiteNonnegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
function Rules.UpdateReadabilityContext(previous: any, state: any): any?
	if not state.visible or state.banked or state.interactionReady == false
		or type(state.itemId) ~= "string" or not finiteNonnegative(state.maximumLockRange) then
		return nil
	end
	if state.focused and state.displayState == "Awake" and finiteNonnegative(state.profileRange) then
		return { itemId = state.itemId, resetToken = state.resetToken,
			rangeStuds = math.min(state.profileRange, state.maximumLockRange), lastFocusedAt = state.now }
	end
	if state.displayState == "Sleeping" and previous
		and previous.itemId == state.itemId and previous.resetToken == state.resetToken then
		-- Attribute replication may deliver Captured before its deadline. Retain
		-- only the recent lock permission briefly; no UI is shown without a deadline.
		if state.sleepUntil == nil and previous.sleepUntil == nil
			and type(previous.lastFocusedAt) == "number" and state.now - previous.lastFocusedAt <= 0.5 then
			return previous
		end
		if finiteNonnegative(state.sleepUntil) and state.sleepUntil > state.now
			and (previous.sleepUntil == nil or previous.sleepUntil == state.sleepUntil) then
			return { itemId = previous.itemId, resetToken = previous.resetToken,
				rangeStuds = previous.rangeStuds, lastFocusedAt = previous.lastFocusedAt, sleepUntil = state.sleepUntil }
		end
	end
	return nil
end
function Rules.Readability(state: any): any
	local ordinaryRange = state.ordinaryRange
	local context = state.context
	local limit = ordinaryRange
	local extended = context ~= nil and finiteNonnegative(context.rangeStuds)
		and finiteNonnegative(state.profileRange)
	if extended then
		limit = math.min(context.rangeStuds, state.profileRange, state.maximumLockRange)
	end
	local within = if extended
		then finiteNonnegative(state.physicalDistance) and state.physicalDistance <= limit
		else finiteNonnegative(state.cameraDistance) and state.cameraDistance <= ordinaryRange
	local cameraAllowance = if extended and finiteNonnegative(state.cameraOffset)
		then math.min(state.cameraOffset, 32) else 0
	local adorneeAllowance = if extended and finiteNonnegative(state.adorneeOffset)
		then math.min(state.adorneeOffset, 64) else 0
	local billboardRange = limit + cameraAllowance + adorneeAllowance + (if extended then 0.05 else 0)
	return { eligible = within and finiteNonnegative(state.cameraDistance) and state.cameraDistance <= billboardRange, physicalRangeStuds = limit,
		billboardRangeStuds = billboardRange,
		extended = extended }
end
return table.freeze(Rules)
