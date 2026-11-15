--!strict

local Config = require(script.Parent.Parent.Config.Phase10)
local Presentation = {}
Presentation.Red = Config.CountdownRed
Presentation.Blue = Config.CountdownBlue
Presentation.Green = Config.CountdownGreen
Presentation.Film = Config.FilmColor
Presentation.ZeroHold = Config.ZeroHoldSeconds
Presentation.FadeDuration = Config.ZeroFadeSeconds

function Presentation.Remaining(deadline: number, now: number): number
	return math.clamp(deadline - now, 0, Config.DazeSeconds)
end

function Presentation.Text(deadline: number, now: number): string
	local remaining = Presentation.Remaining(deadline, now)
	-- Rounded hundredths would display 0.00 during the last 5ms of active daze.
	return string.format("%.2f", if remaining > 0 then math.max(0.01, remaining) else 0)
end

function Presentation.Color(deadline: number, now: number): Color3
	local remaining = Presentation.Remaining(deadline, now)
	local half = Config.DazeSeconds / 2
	if remaining == Config.DazeSeconds then
		return Presentation.Red
	end
	if remaining == half then
		return Presentation.Blue
	end
	if remaining == 0 then
		return Presentation.Green
	end
	return if remaining >= half
		then Presentation.Red:Lerp(Presentation.Blue, (Config.DazeSeconds - remaining) / half)
		else Presentation.Blue:Lerp(Presentation.Green, (half - remaining) / half)
end

return table.freeze(Presentation)
