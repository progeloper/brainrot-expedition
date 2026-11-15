--!strict
-- Playtest Fixes 2 (owner prompt v1.1, 14 Nov 2026): the final wrap-up pass. Input, cash pads, Studio
-- parity and progress bars only. No CPS, income, price, weapon stat, HP, odds, cargo, carry/steal,
-- villager chase or existing profile numbers live here.
--
-- Gating: FeatureFlags.PlaytestFixesV2Enabled (default false) AND the part's sub-flag below. See
-- Config/PlaytestFixes2Flags. Part D (base walls) is an authored world change
-- (scripts/RevertBaseWalls.server.lua undoes it). Part E changes how Studio previews resolve and is
-- not flag-gated. Part G (Legs) has its own flag, FeatureFlags.LegsTrainingV1Enabled.

return table.freeze({
	Version = "PTF2_20261114",

	Parts = table.freeze({
		InputUnstick = true, -- Part A
		JumpHopOut = true, -- Part B
		CashPads = true, -- Part C
		StableBars = true, -- Part F
	}),

	-- Part A ---------------------------------------------------------------------------------------
	InputUnstick = table.freeze({
		WatchdogHz = 1,
		-- An open attribute must look stale on this many consecutive watchdog ticks before it is
		-- healed (a window that is mid-open is never cleared).
		StaleTicks = 2,
		-- DEV warning when a seated driver has been blocked this long.
		SeatedBlockWarnSeconds = 1,
		TraceCooldownSeconds = 1,
	}),

	-- Part B ---------------------------------------------------------------------------------------
	JumpHopOut = table.freeze({
		MinIntervalSeconds = 0.3,
	}),

	-- Part C ---------------------------------------------------------------------------------------
	CashPads = table.freeze({
		TouchHeightStuds = 6,
		PollHz = 5,
		-- While the owner stands on a pad, claim again every RepeatSeconds once it holds >= MinClaim.
		RepeatSeconds = 1,
		MinClaim = 1,
		-- Stack size steps, in seconds of that pad's income.
		StackSteps = table.freeze({ 10, 60 }),
		StackMaxParts = 12,
		StackCullStuds = 80,
		StackBobHz = 10,
		CoinsHigh = 8,
		CoinsLow = 4,
		CoinFlightSeconds = table.freeze({ 0.5, 0.7 }),
		CoinStaggerSeconds = 0.04,
		ChimeIncomeSeconds = 60,
		CounterRollSeconds = 0.6,
	}),

	-- Part F ---------------------------------------------------------------------------------------
	StableBars = table.freeze({
		MinDelta = 0.002,
		HideBelow = 0.04,
	}),
})
