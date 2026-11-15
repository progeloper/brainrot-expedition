--!strict
-- Playtest Fixes 2 Part C: pure cash-pad decisions shared by the server presence poll
-- (BaseIncomePlaqueSystem) and the client cash stack (CashPadController). No instances, no state.
local CashPadRules = {}

-- Live unclaimed cash on a pad from its replicated snapshot attributes.
function CashPadRules.Unclaimed(
	snapshot: number?,
	rate: number?,
	snapshotTime: number?,
	now: number
): number
	local base = if type(snapshot) == "number"
			and snapshot == snapshot
			and snapshot > 0
		then snapshot
		else 0
	local perSecond = if type(rate) == "number" and rate == rate and rate > 0 then rate else 0
	local since = if type(snapshotTime) == "number" and snapshotTime > 0
		then math.max(0, now - snapshotTime)
		else 0
	return base + perSecond * since
end

-- Should the presence poll claim this pad now?
--   * entry: the owner was not on the pad last poll and is now -> claim at once;
--   * staying: claim again every `repeatSeconds` while the pad holds at least `minClaim`.
function CashPadRules.ShouldClaim(
	present: boolean,
	wasPresent: boolean,
	now: number,
	lastClaimAt: number,
	unclaimed: number,
	repeatSeconds: number,
	minClaim: number
): boolean
	if not present then
		return false
	end
	if not wasPresent then
		return true
	end
	return now - lastClaimAt >= repeatSeconds and unclaimed >= minClaim
end

-- Cash-stack size step 0..3 from seconds of that pad's income: 0 = hidden, 1 = < steps[1] s,
-- 2 = steps[1]..steps[2] s, 3 = > steps[2] s.
function CashPadRules.StackStep(unclaimed: number, rate: number, steps: { number }): number
	if unclaimed < 0.5 then
		return 0
	end
	if rate <= 0 then
		return 1
	end
	local seconds = unclaimed / rate
	if seconds < steps[1] then
		return 1
	elseif seconds <= steps[2] then
		return 2
	end
	return 3
end

-- Coins to fly for a claim on this quality tier (pooled; never more than the cap).
function CashPadRules.CoinCount(low: boolean, high: number, lowCount: number): number
	return if low then lowCount else high
end

-- Where the coins start: the pad's screen point, or (off-screen / behind the camera) the nearest
-- point on the screen edge, inset by `margin`.
function CashPadRules.CoinOrigin(
	point: Vector2,
	onScreen: boolean,
	viewport: Vector2,
	margin: number
): Vector2
	if onScreen then
		return point
	end
	local centre = viewport / 2
	local dir = point - centre
	if dir.Magnitude < 1e-3 then
		dir = Vector2.new(0, 1)
	end
	local half = centre - Vector2.new(margin, margin)
	local scale = math.min(
		if math.abs(dir.X) > 1e-6 then half.X / math.abs(dir.X) else math.huge,
		if math.abs(dir.Y) > 1e-6 then half.Y / math.abs(dir.Y) else math.huge
	)
	return centre + dir * scale
end

return table.freeze(CashPadRules)
