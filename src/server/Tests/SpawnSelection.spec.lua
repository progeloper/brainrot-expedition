--!nocheck
return function()
	local SpawnSelection = require(script.Parent.Parent.Systems.SpawnSelection)
	local Regions = require(game.ReplicatedStorage.Shared.Config.Regions)

	local function weights(overrides)
		local result = {
			Common = 0,
			Uncommon = 0,
			Rare = 0,
			Epic = 0,
			Legendary = 0,
			Mythic = 0,
		}
		for key, value in overrides or {} do
			result[key] = value
		end
		return result
	end

	local function region(tierWeights, speciesOverrides)
		return {
			id = "Forest",
			displayName = "Forest",
			kind = "Hunting",
			enabled = true,
			naturalSpawnAllowed = true,
			spawnSelection = {
				tierWeights = tierWeights,
				speciesWeightOverrides = speciesOverrides or {},
			},
		}
	end

	local function candidate(id, tier, overrides)
		local value = {
			id = id,
			tier = tier,
			assignmentStatus = "Approved",
			homeRegionId = "Forest",
			allowedRegionIds = { "Forest" },
			spawnEnabled = true,
			launchStatus = "Live",
			naturalSpawnEligible = true,
			modelReady = true,
			behaviourReady = true,
			locationReady = true,
		}
		for key, item in overrides or {} do
			value[key] = item
		end
		return value
	end

	local function compile(tierWeights, candidates, speciesOverrides)
		return SpawnSelection.CompileRegion(
			"Forest",
			region(tierWeights, speciesOverrides),
			candidates
		)
	end

	local function hasCode(items, code)
		for _, issue in items do
			if issue.code == code then
				return true
			end
		end
		return false
	end

	local function close(left, right, tolerance)
		return math.abs(left - right) <= (tolerance or 1e-9)
	end

	local function findTier(report, tier)
		for _, row in report.tiers do
			if row.tier == tier then
				return row
			end
		end
		return nil
	end

	local function findSpecies(report, speciesId)
		for _, row in report.species do
			if row.speciesId == speciesId then
				return row
			end
		end
		return nil
	end

	local function selectedWithUnits(pool, units)
		local effective = SpawnSelection.PrepareEffective(pool, nil)
		local index = 0
		local result = SpawnSelection.Select(effective, function()
			index += 1
			return units[index]
		end)
		return result, index
	end

	describe("Phase 9 Development ordinary-spawn probability ceilings", function()
		local ceilings = { BRT_032 = 0.0002, BRT_034 = 0.00002, BRT_035 = 0 }
		local function bounded(tierWeights, candidates, policy)
			return SpawnSelection.CompileRegion("Forest", region(tierWeights), candidates, policy or ceilings)
		end

		it("caps the actual tier × species probability even for a sole-species tier", function()
			local pool = bounded(weights({ Common = 0.4, Legendary = 0.6 }), {
				candidate("BRT_101", "Common"), candidate("BRT_032", "Legendary"),
			}).pool
			local report = SpawnSelection.DescribeDistribution(pool)
			expect(close(findSpecies(report, "BRT_032").authoredOverallProbability, 0.6)).to.equal(true)
			expect(close(findSpecies(report, "BRT_032").baselineOverallProbability, 0.0002)).to.equal(true)
			expect(close(findSpecies(report, "BRT_101").effectiveOverallProbability, 0.9998)).to.equal(true)
			expect(pool.configuredTierWeights.Legendary).to.equal(0.6)
			expect(report.ordinarySpawnCeilingStatus).to.equal("Ready")
			expect(#report.ordinarySpawnCeilingAdjustments).to.equal(1)
		end)

		it("preserves the relative probability of uncapped recipients across tiers", function()
			local pool = bounded(weights({ Common = 0.1, Epic = 0.3, Legendary = 0.6 }), {
				candidate("BRT_101", "Common"), candidate("BRT_102", "Epic"), candidate("BRT_032", "Legendary"),
			}).pool
			local report = SpawnSelection.DescribeDistribution(pool)
			local common = findSpecies(report, "BRT_101").effectiveOverallProbability
			local epic = findSpecies(report, "BRT_102").effectiveOverallProbability
			expect(close(epic / common, 3)).to.equal(true)
			expect(close(common + epic, 0.9998)).to.equal(true)
		end)

		it("reapplies ceilings after temporary species and tier exclusions", function()
			local pool = bounded(weights({ Common = 0.1, Legendary = 0.8, Mythic = 0.1 }), {
				candidate("BRT_101", "Common"), candidate("BRT_031", "Legendary"),
				candidate("BRT_032", "Legendary"), candidate("BRT_034", "Mythic"),
			}).pool
			for _, snapshot in {
				{}, { blockedSpecies = { BRT_031 = "Fixture" } },
				{ blockedTiers = { Legendary = "Fixture" } },
			} do
				local report = SpawnSelection.DescribeDistribution(pool, SpawnSelection.PrepareEffective(pool, snapshot))
				expect(findSpecies(report, "BRT_032").effectiveOverallProbability <= ceilings.BRT_032 + 1e-12).to.equal(true)
				expect(findSpecies(report, "BRT_034").effectiveOverallProbability <= ceilings.BRT_034 + 1e-12).to.equal(true)
			end
		end)

		it("blocks a temporarily all-capped pool without draws or excess rare probability", function()
			local pool = bounded(weights({ Common = 0.4, Legendary = 0.6 }), {
				candidate("BRT_101", "Common"), candidate("BRT_032", "Legendary"),
			}).pool
			local effective = SpawnSelection.PrepareEffective(pool, { blockedSpecies = { BRT_101 = "Fixture" } })
			expect(effective.status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
			expect(effective.ordinarySpawnCeilingStatus).to.equal("ORDINARY_SPAWN_CEILING_NO_RECIPIENT")
			local calls = 0
			expect(SpawnSelection.Select(effective, function() calls += 1; return 0 end).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
			expect(calls).to.equal(0)
		end)

		it("keeps unreleased content excluded and Secret ordinary probability zero", function()
			local result = bounded(weights({ Common = 1 }), {
				candidate("BRT_101", "Common"),
				candidate("BRT_034", "Mythic", { spawnEnabled = false, launchStatus = "Teased" }),
				candidate("BRT_035", "Secret"),
			})
			expect(result.status).to.equal("Compiled")
			expect(hasCode(result.report.exclusions, "SPAWN_DISABLED")).to.equal(true)
			expect(hasCode(result.report.exclusions, "ORDINARY_SPAWN_CEILING_ZERO")).to.equal(true)
			expect(findSpecies(SpawnSelection.DescribeDistribution(result.pool), "BRT_035")).to.equal(nil)
		end)

		it("preserves authored probabilities when the feature policy is off", function()
			local pool = bounded(weights({ Common = 0.4, Legendary = 0.6 }), {
				candidate("BRT_101", "Common"), candidate("BRT_032", "Legendary"),
			}, {}).pool
			expect(close(findSpecies(SpawnSelection.DescribeDistribution(pool), "BRT_032").effectiveOverallProbability, 0.6)).to.equal(true)
		end)

		it("audits every current region pool without changing membership, economy or release flags", function()
			local Progression = require(game.ReplicatedStorage.Shared.Config.WorldProgression)
			local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
			local count = 0
			for regionId, authored in Progression.Pools do
				local candidates = {}
				for tier, ids in authored.species do
					for _, id in ids do
						local definition = Catalog.Get(id)
						table.insert(candidates, candidate(id, tier, {
							allowedRegionIds = definition.allowedRegionIds,
							launchStatus = definition.launchStatus,
							spawnEnabled = definition.spawnEnabled,
							naturalSpawnEligible = definition.launchStatus == "Live",
						}))
					end
				end
				local compilation = SpawnSelection.CompileRegion(regionId, Regions.Get(regionId), candidates, ceilings)
				expect(compilation.status).to.equal("Compiled")
				local report = SpawnSelection.DescribeDistribution(compilation.pool)
				for _, row in report.species do
					if ceilings[row.speciesId] then expect(row.effectiveOverallProbability <= ceilings[row.speciesId] + 1e-12).to.equal(true) end
				end
				if regionId == "REGION_GLITCH" then
					expect(close(findSpecies(report, "BRT_032").baselineOverallProbability, 0.0002)).to.equal(true)
					expect(close(findSpecies(report, "BRT_031").baselineOverallProbability, 0.5998)).to.equal(true)
					expect(close(findTier(report, "Rare").baselineProbability, 0.05)).to.equal(true)
					expect(close(findTier(report, "Epic").baselineProbability, 0.35)).to.equal(true)
				end
				count += 1
			end
			expect(count).to.equal(7)
			expect(Catalog.Get("BRT_034").launchStatus).to.equal("Teased")
			expect(Catalog.Get("BRT_035").spawnEnabled).to.equal(false)
		end)
	end)

	describe("Phase 6E-1 regional tier-first selection", function()
		it("compiles relative decimal weights without requiring a sum of 1 or 100", function()
			local result = compile(
				weights({
					Common = 68,
					Uncommon = 25,
					Rare = 6,
					Epic = 0.9,
					Legendary = 0.1,
				}),
				{
					candidate("BRT_101", "Common"),
					candidate("BRT_102", "Uncommon"),
					candidate("BRT_103", "Rare"),
					candidate("BRT_104", "Epic"),
					candidate("BRT_105", "Legendary"),
				}
			)
			expect(result.status).to.equal("Compiled")
			expect(close(result.pool.totalTierWeight, 100)).to.equal(true)
			expect(#result.pool.tiers).to.equal(5)
		end)

		it("rejects missing, unknown and non-finite tier weights", function()
			local missing = weights({ Common = 1 })
			missing.Mythic = nil
			local missingResult = compile(missing, { candidate("BRT_101", "Common") })
			expect(hasCode(missingResult.report.errors, "MISSING_TIER_WEIGHT")).to.equal(true)

			for _, bad in { -1, 0 / 0, math.huge, -math.huge, "1", true, {} } do
				local invalid =
					compile(weights({ Common = bad }), { candidate("BRT_101", "Common") })
				expect(hasCode(invalid.report.errors, "INVALID_TIER_WEIGHT")).to.equal(true)
			end

			for _, key in { "Secret", "Mythic/Secret", "SuperRare" } do
				local invalidWeights = weights({ Common = 1 })
				invalidWeights[key] = 1
				local invalid = compile(invalidWeights, { candidate("BRT_101", "Common") })
				expect(hasCode(invalid.report.errors, "UNKNOWN_TIER_WEIGHT_KEY")).to.equal(true)
			end
		end)

		it(
			"rejects all-zero configuration and excludes empty positive tiers cleanly",
			function()
				local allZero = compile(weights(), { candidate("BRT_101", "Common") })
				expect(hasCode(allZero.report.errors, "ALL_TIER_WEIGHTS_ZERO")).to.equal(true)

				local emptyRare = compile(weights({ Rare = 1 }), { candidate("BRT_101", "Common") })
				expect(hasCode(emptyRare.report.exclusions, "NO_ELIGIBLE_SPECIES_IN_POSITIVE_TIER")).to.equal(
					true
				)
				expect(emptyRare.status).to.equal("Compiled")
				expect(SpawnSelection.PrepareEffective(emptyRare.pool).status).to.equal("NO_ELIGIBLE_SPECIES_NOW")

				local zeroRare = compile(
					weights({ Rare = 1 }),
					{ candidate("BRT_101", "Rare") },
					{ BRT_101 = 0 }
				)
				expect(hasCode(zeroRare.report.exclusions, "SPECIES_WEIGHT_ZERO")).to.equal(true)
				expect(hasCode(zeroRare.report.exclusions, "NO_ELIGIBLE_SPECIES_IN_POSITIVE_TIER")).to.equal(
					true
				)
				local emptyCelestial=compile(weights({Common=1,Celestial=1}),{candidate("BRT_101","Common")})
				expect(emptyCelestial.status).to.equal("Compiled")
				expect(hasCode(emptyCelestial.report.exclusions,"EMPTY_CELESTIAL_POOL")).to.equal(true)
				local distribution=SpawnSelection.DescribeDistribution(emptyCelestial.pool)
				for _, tier in distribution.tiers do
					if tier.tier=="Common" then expect(tier.effectiveProbability).to.equal(1) end
					if tier.tier=="Celestial" then expect(tier.effectiveProbability).to.equal(0) end
				end
			end
		)

		it("rejects bad species overrides, pending membership and normalized duplicates", function()
			local unknownOverride = compile(
				weights({ Common = 1 }),
				{ candidate("BRT_101", "Common") },
				{ BRT_999 = 1 }
			)
			expect(hasCode(unknownOverride.report.errors, "UNKNOWN_SPECIES_WEIGHT_OVERRIDE")).to.equal(
				true
			)

			local pending = candidate("BRT_102", "Common", {
				assignmentStatus = "Pending",
			})
			local outsideOverride = compile(
				weights({ Common = 1 }),
				{ candidate("BRT_101", "Common"), pending },
				{ BRT_102 = 1 }
			)
			expect(hasCode(outsideOverride.report.errors, "SPECIES_WEIGHT_OVERRIDE_OUTSIDE_REGION")).to.equal(
				true
			)

			local duplicate = compile(weights({ Common = 1 }), {
				candidate("BRT-101", "Common"),
				candidate("BRT_101", "Common"),
			})
			expect(hasCode(duplicate.report.errors, "DUPLICATE_SPECIES_ID")).to.equal(true)
		end)

		it(
			"permits an approved allowed region different from home but rejects home-only pending evidence",
			function()
				local multiRegion = candidate("BRT_101", "Common", {
					homeRegionId = "Beach",
					allowedRegionIds = { "Beach", "Forest" },
				})
				expect(compile(weights({ Common = 1 }), { multiRegion }).status).to.equal(
					"Compiled"
				)

				local pending = candidate("BRT_102", "Common", {
					assignmentStatus = "Pending",
					homeRegionId = "Forest",
					allowedRegionIds = {},
				})
				local result = compile(weights({ Common = 1 }), { pending })
				expect(result.status).to.equal("INVALID_CONFIGURATION")
				expect(hasCode(result.report.errors, "MISSING_APPROVED_MEMBERSHIP")).to.equal(true)
			end
		)

		it("excludes disabled future content but errors for an enabled broken asset", function()
			local disabledMissing = candidate("BRT_102", "Common", {
				spawnEnabled = false,
				modelReady = false,
			})
			local valid = compile(weights({ Common = 1 }), {
				candidate("BRT_101", "Common"),
				disabledMissing,
			})
			expect(valid.status).to.equal("Compiled")
			expect(hasCode(valid.report.exclusions, "SPAWN_DISABLED")).to.equal(true)
			expect(hasCode(valid.report.errors, "MODEL_MISSING")).to.equal(false)

			local enabledMissing = compile(weights({ Common = 1 }), {
				candidate("BRT_101", "Common", { modelReady = false }),
			})
			expect(enabledMissing.status).to.equal("INVALID_CONFIGURATION")
			expect(hasCode(enabledMissing.report.errors, "MODEL_MISSING")).to.equal(true)
		end)

		it("preserves a disabled Teased Secret row without admitting or rejecting it", function()
			local teasedSecret = candidate("BRT_102", "Secret", {
				spawnEnabled = false,
				launchStatus = "Teased",
				naturalSpawnEligible = false,
				modelReady = false,
			})
			local result = compile(weights({ Common = 1 }), {
				candidate("BRT_101", "Common"),
				teasedSecret,
			})
			expect(result.status).to.equal("Compiled")
			expect(hasCode(result.report.exclusions, "SPAWN_DISABLED")).to.equal(true)
			expect(hasCode(result.report.errors, "INVALID_SPECIES_TIER")).to.equal(false)
		end)

		it("detects aggregate overflow and precision loss", function()
			local overflow = compile(
				weights({ Common = 1 }),
				{ candidate("BRT_101", "Common"), candidate("BRT_102", "Common") },
				{ BRT_101 = 1e308, BRT_102 = 1e308 }
			)
			expect(hasCode(overflow.report.errors, "WEIGHT_TOTAL_NOT_FINITE")).to.equal(true)

			local precision = compile(
				weights({ Common = 1 }),
				{ candidate("BRT_101", "Common"), candidate("BRT_102", "Common") },
				{ BRT_101 = 1e308, BRT_102 = 1 }
			)
			expect(hasCode(precision.report.errors, "WEIGHT_PRECISION_LOSS")).to.equal(true)
		end)

		it("uses the next bucket at exact boundaries and the last bucket at unit one", function()
			local compiled = compile(
				weights({ Common = 1 }),
				{ candidate("BRT_101", "Common"), candidate("BRT_102", "Common") },
				{ BRT_101 = 1, BRT_102 = 3 }
			).pool
			for _, case in
				{
					{ 0, "BRT_101" },
					{ 0.249999999, "BRT_101" },
					{ 0.25, "BRT_102" },
					{ 0.999999999, "BRT_102" },
					{ 1, "BRT_102" },
				}
			do
				local result, draws = selectedWithUnits(compiled, { 0, case[1] })
				expect(result.speciesId).to.equal(case[2])
				expect(draws).to.equal(2)
			end

			local tiers = compile(
				weights({ Common = 1, Rare = 3 }),
				{ candidate("BRT_101", "Common"), candidate("BRT_102", "Rare") }
			).pool
			local last = selectedWithUnits(tiers, { 1, 1 })
			expect(last.tier).to.equal("Rare")
		end)

		it("uses two independent draws and consumes none for invalid or empty pools", function()
			local pool = compile(weights({ Common = 1, Rare = 1 }), {
				candidate("BRT_101", "Common"),
				candidate("BRT_102", "Rare"),
				candidate("BRT_103", "Rare"),
			}).pool
			local selected, draws = selectedWithUnits(pool, { 0.75, 0 })
			expect(selected.tier).to.equal("Rare")
			expect(selected.speciesId).to.equal("BRT_102")
			expect(draws).to.equal(2)

			local count = 0
			local invalid = SpawnSelection.Select(
				SpawnSelection.PrepareEffective(nil, nil),
				function()
					count += 1
					return 0
				end
			)
			expect(invalid.status).to.equal("INVALID_CONFIGURATION")
			expect(count).to.equal(0)

			local empty = SpawnSelection.PrepareEffective(pool, {
				blockedTiers = { Common = "Test", Rare = "Test" },
			})
			local noEligible = SpawnSelection.Select(empty, function()
				count += 1
				return 0
			end)
			expect(noEligible.status).to.equal("NO_ELIGIBLE_SPECIES_NOW")
			expect(count).to.equal(0)
		end)

		it("rejects invalid random values without rerolling", function()
			local pool = compile(weights({ Common = 1 }), { candidate("BRT_101", "Common") }).pool
			local effective = SpawnSelection.PrepareEffective(pool, nil)
			for _, unit in { -0.01, 1.01, 0 / 0, math.huge, "0.5" } do
				local count = 0
				local result = SpawnSelection.Select(effective, function()
					count += 1
					return unit
				end)
				expect(result.status).to.equal("INVALID_RANDOM_VALUE")
				expect(count).to.equal(1)
			end
		end)

		it("keeps tier probability invariant as species membership and weights change", function()
			local tenCommons = {}
			for index = 1, 10 do
				table.insert(
					tenCommons,
					candidate(string.format("BRT_%03d", 100 + index), "Common")
				)
			end
			table.insert(tenCommons, candidate("BRT_150", "Rare"))
			local first = compile(weights({ Common = 80, Rare = 20 }), tenCommons).pool
			local firstReport = SpawnSelection.DescribeDistribution(first)
			expect(close(findTier(firstReport, "Common").baselineProbability, 0.8)).to.equal(true)
			expect(close(findSpecies(firstReport, "BRT_101").baselineOverallProbability, 0.08)).to.equal(
				true
			)
			expect(close(findSpecies(firstReport, "BRT_150").baselineOverallProbability, 0.2)).to.equal(
				true
			)

			local twentyCommons = table.clone(tenCommons)
			for index = 11, 20 do
				table.insert(
					twentyCommons,
					candidate(string.format("BRT_%03d", 100 + index), "Common")
				)
			end
			local second = compile(weights({ Common = 80, Rare = 20 }), twentyCommons).pool
			local secondReport = SpawnSelection.DescribeDistribution(second)
			expect(close(findTier(secondReport, "Common").baselineProbability, 0.8)).to.equal(true)
			expect(close(findSpecies(secondReport, "BRT_101").baselineOverallProbability, 0.04)).to.equal(
				true
			)

			local weightedRare = compile(weights({ Common = 80, Rare = 20 }), {
				candidate("BRT_101", "Common"),
				candidate("BRT_151", "Rare"),
				candidate("BRT_152", "Rare"),
			}, { BRT_151 = 3, BRT_152 = 1 }).pool
			local weightedReport = SpawnSelection.DescribeDistribution(weightedRare)
			expect(close(findTier(weightedReport, "Rare").baselineProbability, 0.2)).to.equal(true)
			expect(close(findSpecies(weightedReport, "BRT_151").baselineOverallProbability, 0.15)).to.equal(
				true
			)
			expect(close(findSpecies(weightedReport, "BRT_152").baselineOverallProbability, 0.05)).to.equal(
				true
			)
		end)

		it("omits zero weights, records defaults, and ignores behaviour-effect budgets", function()
			local pool = compile(weights({ Common = 1, Rare = 0 }), {
				candidate("BRT_101", "Common", { behaviourBudgetOccupied = true }),
				candidate("BRT_102", "Common"),
				candidate("BRT_103", "Rare"),
			}, { BRT_102 = 0 }).pool
			local report = SpawnSelection.DescribeDistribution(pool)
			expect(#report.species).to.equal(1)
			expect(report.species[1].speciesId).to.equal("BRT_101")
			expect(report.species[1].weightSource).to.equal("Default")
			expect(report.defaultedSpeciesIds[1]).to.equal("BRT_101")
			expect(findTier(report, "Rare").baselineProbability).to.equal(0)
			for _, unit in { 0, 0.25, 0.75, 1 } do
				local selected = selectedWithUnits(pool, { unit, unit })
				expect(selected.speciesId).to.equal("BRT_101")
			end
		end)

		it("recomputes effective tiers without mutating authored or compiled weights", function()
			local pool = compile(weights({ Common = 70, Uncommon = 20, Rare = 10 }), {
				candidate("BRT_101", "Common"),
				candidate("BRT_102", "Uncommon"),
				candidate("BRT_103", "Rare"),
				candidate("BRT_104", "Rare"),
			}, { BRT_103 = 1, BRT_104 = 3 }).pool
			local oneBlocked = SpawnSelection.PrepareEffective(pool, {
				blockedSpecies = { BRT_104 = "ExistingTemporaryRestriction" },
			})
			local oneReport = SpawnSelection.DescribeDistribution(pool, oneBlocked)
			expect(close(findTier(oneReport, "Rare").effectiveProbability, 0.1)).to.equal(true)
			expect(close(findSpecies(oneReport, "BRT_103").effectiveConditionalProbability, 1)).to.equal(
				true
			)

			local rareBlocked = SpawnSelection.PrepareEffective(pool, {
				blockedTiers = { Rare = "ExistingTemporaryRestriction" },
			})
			local blockedReport = SpawnSelection.DescribeDistribution(pool, rareBlocked)
			expect(close(findTier(blockedReport, "Common").effectiveProbability, 70 / 90)).to.equal(
				true
			)
			expect(close(findTier(blockedReport, "Uncommon").effectiveProbability, 20 / 90)).to.equal(
				true
			)
			expect(findTier(blockedReport, "Rare").effectiveProbability).to.equal(0)
			expect(pool.configuredTierWeights.Rare).to.equal(10)

			local baseline = SpawnSelection.DescribeDistribution(
				pool,
				SpawnSelection.PrepareEffective(pool, nil)
			)
			expect(close(findTier(baseline, "Rare").effectiveProbability, 0.1)).to.equal(true)
		end)

		it(
			"is deterministic across candidate insertion order and equal seeded generators",
			function()
				local forward = {
					candidate("BRT_101", "Common"),
					candidate("BRT_102", "Common"),
					candidate("BRT_103", "Rare"),
				}
				local reverse = { forward[3], forward[2], forward[1] }
				local left = SpawnSelection.PrepareEffective(
					compile(weights({ Common = 4, Rare = 1 }), forward).pool,
					nil
				)
				local right = SpawnSelection.PrepareEffective(
					compile(weights({ Rare = 1, Common = 4 }), reverse).pool,
					nil
				)
				local leftRandom = Random.new(12345)
				local rightRandom = Random.new(12345)
				for _ = 1, 100 do
					local a = SpawnSelection.Select(left, function()
						return leftRandom:NextNumber()
					end)
					local b = SpawnSelection.Select(right, function()
						return rightRandom:NextNumber()
					end)
					expect(a.speciesId).to.equal(b.speciesId)
				end
			end
		)

		it("does not consume draws while reporting and allows repeated species results", function()
			local pool = compile(weights({ Common = 1 }), { candidate("BRT_101", "Common") }).pool
			local before = #workspace:GetDescendants()
			local report = SpawnSelection.DescribeDistribution(pool)
			expect(report.status).to.equal("Ready")
			expect(#workspace:GetDescendants()).to.equal(before)
			local effective = SpawnSelection.PrepareEffective(pool, nil)
			local first = SpawnSelection.Select(effective, function()
				return 0
			end)
			local second = SpawnSelection.Select(effective, function()
				return 0
			end)
			expect(first.speciesId).to.equal("BRT_101")
			expect(second.speciesId).to.equal("BRT_101")
			expect(function()
				pool.configuredTierWeights.Common = 99
			end).to.throw()
		end)

		it("ships approved current distributions while preserving invalid-region gates", function()
			local production = SpawnSelection.CompileConfiguredRegion("Forest")
			expect(Regions.Get("Forest").spawnSelection ~= nil).to.equal(true)
			expect(hasCode(production.report.errors, "MISSING_SPAWN_SELECTION")).to.equal(false)
			expect(hasCode(production.report.errors, "MISSING_APPROVED_MEMBERSHIP")).to.equal(false)
			expect(SpawnSelection.CompileConfiguredRegion("Meme Meadows").status).to.equal(
				"UNKNOWN_REGION"
			)
			expect(SpawnSelection.CompileConfiguredRegion("Camp").status).to.equal(
				"REGION_NOT_SPAWNABLE"
			)
		end)

		it("matches seeded tier frequencies for the historical synthetic fixture", function()
			local configured = weights({
				Common = 68,
				Uncommon = 25,
				Rare = 6,
				Epic = 0.9,
				Legendary = 0.1,
			})
			local pool = compile(configured, {
				candidate("BRT_101", "Common"),
				candidate("BRT_102", "Uncommon"),
				candidate("BRT_103", "Rare"),
				candidate("BRT_104", "Epic"),
				candidate("BRT_105", "Legendary"),
			}).pool
			local effective = SpawnSelection.PrepareEffective(pool, nil)
			local probabilities = {
				Common = 0.68,
				Uncommon = 0.25,
				Rare = 0.06,
				Epic = 0.009,
				Legendary = 0.001,
				Mythic = 0,
			}
			local count = 100000
			for _, seed in { 12345, 67890, 24680 } do
				local random = Random.new(seed)
				local observed = {
					Common = 0,
					Uncommon = 0,
					Rare = 0,
					Epic = 0,
					Legendary = 0,
					Mythic = 0,
				}
				for _ = 1, count do
					local result = SpawnSelection.Select(effective, function()
						return random:NextNumber()
					end)
					observed[result.tier] += 1
				end
				print(
					string.format(
						"[SpawnSelectionDryRun] seed=%d N=%d Common=%d Uncommon=%d Rare=%d Epic=%d Legendary=%d Mythic=%d",
						seed,
						count,
						observed.Common,
						observed.Uncommon,
						observed.Rare,
						observed.Epic,
						observed.Legendary,
						observed.Mythic
					)
				)
				for tier, probability in probabilities do
					if probability == 0 then
						expect(observed[tier]).to.equal(0)
					else
						local expected = count * probability
						local standardDeviation = math.sqrt(count * probability * (1 - probability))
						expect(math.abs(observed[tier] - expected) <= 6 * standardDeviation + 1).to.equal(
							true
						)
					end
				end
			end
		end)

		it("matches effective frequencies when one tier is temporarily unavailable", function()
			local pool = compile(weights({ Common = 70, Uncommon = 20, Rare = 10 }), {
				candidate("BRT_101", "Common"),
				candidate("BRT_102", "Uncommon"),
				candidate("BRT_103", "Rare"),
			}).pool
			local effective = SpawnSelection.PrepareEffective(pool, {
				blockedTiers = { Rare = "TestRestriction" },
			})
			local random = Random.new(13579)
			local count = 100000
			local common = 0
			local rare = 0
			for _ = 1, count do
				local result = SpawnSelection.Select(effective, function()
					return random:NextNumber()
				end)
				if result.tier == "Common" then
					common += 1
				elseif result.tier == "Rare" then
					rare += 1
				end
			end
			local probability = 70 / 90
			local expected = count * probability
			local standardDeviation = math.sqrt(count * probability * (1 - probability))
			print(
				string.format(
					"[SpawnSelectionDryRun] seed=13579 N=%d effectiveCommon=%d effectiveUncommon=%d blockedRare=%d",
					count,
					common,
					count - common,
					rare
				)
			)
			expect(math.abs(common - expected) <= 6 * standardDeviation + 1).to.equal(true)
			expect(rare).to.equal(0)
		end)
	end)
end
