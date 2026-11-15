--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ConfigValidator = require(ReplicatedStorage.Shared.Validation.ConfigValidator)

	describe("ConfigValidator", function()
		it("validates the shared natural-territory placement contract", function()
			local source = require(ReplicatedStorage.Shared.Config.BrainrotTerritory)
			expect(function()
				ConfigValidator.AssertBrainrotTerritory("BrainrotTerritory", source)
			end).never.to.throw()

			for key, value in
				{
					MaxPlacementAttemptsPerSpawn = 7.5,
					BoundaryPaddingStuds = 0,
					MinWalkableNormalY = 1.1,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertBrainrotTerritory("BrainrotTerritory", invalid)
				end).to.throw()
			end
		end)

		it("accepts unique IDs", function()
			expect(function()
				ConfigValidator.AssertUniqueIds("Test", {
					First = "ONE",
					Second = "TWO",
				})
			end).never.to.throw()
		end)

		it("rejects duplicate IDs", function()
			expect(function()
				ConfigValidator.AssertUniqueIds("Test", {
					First = "DUPLICATE",
					Second = "DUPLICATE",
				})
			end).to.throw()
		end)

		it("validates the Sprinter timing and multiplier contract", function()
			local source = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).Sprinter
			expect(function()
				ConfigValidator.AssertSprinterProfile("Sprinter", source)
			end).never.to.throw()

			for key, value in
				{
					AccelerationSeconds = source.BurstDurationSeconds + 0.01,
					RecoveryDecelerationSeconds = source.RecoveryDurationSeconds + 0.01,
					RecoverySpeedMultiplier = 1,
					BurstSpeedMultiplier = 1,
					CooldownDurationSeconds = 0 / 0,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertSprinterProfile("Sprinter", invalid)
				end).to.throw()
			end
		end)

		it("validates the Zigzag duration, angle, width, and side contract", function()
			local source = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).Zigzag
			expect(function()
				ConfigValidator.AssertZigzagProfile("Zigzag", source)
			end).never.to.throw()

			for key, value in
				{
					SweepTurnSeconds = source.SweepDurationSeconds * 0.5,
					MaxSweepAngleDegrees = 90,
					MaxLateralOffsetStuds = 0,
					InitialSide = 0,
					DisengageRadius = source.AwarenessRadius - 1,
					CourseReorientSeconds = 0 / 0,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertZigzagProfile("Zigzag", invalid)
				end).to.throw()
			end
		end)

		it("validates the Camouflage period, fades, concealment, and cue contract", function()
			local source = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).Camouflage
			expect(function()
				ConfigValidator.AssertCamouflageProfile("Camouflage", source)
			end).never.to.throw()

			for key, value in
				{
					ConcealAmount = 1,
					FullRevealSeconds = source.RevealPeriodSeconds,
					RevealCueSeconds = source.FullRevealSeconds + 0.01,
					RevealCueOutlineTransparency = 1.1,
					DisengageRadius = source.AwarenessRadius - 1,
					RevealFadeSeconds = 0 / 0,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertCamouflageProfile("Camouflage", invalid)
				end).to.throw()
			end
		end)

		it("validates the Decoy Split caps, spacing, retention, and cue contract", function()
			local source = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours).DecoySplit
			expect(function()
				ConfigValidator.AssertDecoySplitProfile("DecoySplit", source)
			end).never.to.throw()

			for key, value in
				{
					MaxDecoysPerEncounter = 3,
					MaxActiveEncounters = 3,
					MaximumSpacingStuds = source.MinimumSpacingStuds - 1,
					DisengageRadius = source.AwarenessRadius - 1,
					CuePulseDurationSeconds = source.CuePulsePeriodSeconds + 0.01,
					ActiveDurationSeconds = 0 / 0,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertDecoySplitProfile("DecoySplit", invalid)
				end).to.throw()
			end
		end)

		it("validates the Legendary Pursuit sequence, budget, and reusable dependencies", function()
			local behaviours = require(ReplicatedStorage.Shared.Config.BrainrotBehaviours)
			local source = behaviours.LegendaryPursuit
			expect(function()
				ConfigValidator.AssertLegendaryPursuitProfile(
					"LegendaryPursuit",
					source,
					behaviours.Sprinter,
					behaviours.Zigzag
				)
			end).never.to.throw()

			for key, value in
				{
					ZigzagCycleCount = 1.5,
					MaxActiveEncounters = 2,
					DisengageRadius = source.AwarenessRadius - 1,
					OpeningDurationSeconds = 0,
					MaxUpdateGapSeconds = 0 / 0,
				}
			do
				local invalid = table.clone(source)
				invalid[key] = value
				expect(function()
					ConfigValidator.AssertLegendaryPursuitProfile(
						"LegendaryPursuit",
						invalid,
						behaviours.Sprinter,
						behaviours.Zigzag
					)
				end).to.throw()
			end
		end)
	end)
end
