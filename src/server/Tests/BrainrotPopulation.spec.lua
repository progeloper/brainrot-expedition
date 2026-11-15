--!nocheck
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PopulationConfig = require(ReplicatedStorage.Shared.Config.BrainrotPopulation)
	local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
	local Regions = require(ReplicatedStorage.Shared.Config.Regions)
	local ConfigValidator = require(ReplicatedStorage.Shared.Validation.ConfigValidator)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)

	local function config(overrides)
		local caps = table.clone(PopulationConfig.ProfileAdmissionCaps)
		for profile, value in (overrides and overrides.ProfileAdmissionCaps) or {} do
			caps[profile] = value
		end
		return {
			TargetWildPopulation = (overrides and overrides.TargetWildPopulation) or 42,
			ReplenishDelaySeconds = 2,
			RetryDelaySeconds = 2,
			MaxSpawnReservationsPerPass = (overrides and overrides.MaxSpawnReservationsPerPass)
				or 3,
			ProfileAdmissionCaps = caps,
			NaturalReplenishmentEnabled = if overrides
					and overrides.NaturalReplenishmentEnabled ~= nil
				then overrides.NaturalReplenishmentEnabled
				else true,
		}
	end

	local function fakeScheduler()
		local queued = {}
		return {
			Queue = queued,
			Schedule = function(delaySeconds, callback)
				table.insert(queued, { Delay = delaySeconds, Callback = callback })
			end,
			RunNext = function()
				local item = table.remove(queued, 1)
				assert(item, "No scheduled callback")
				item.Callback()
				return item.Delay
			end,
		}
	end

	local function regionPolicy(order)
		return function(_snapshot, tried)
			for _, rawRegionId in order do
				local regionId = assert(Regions.NormalizeId(rawRegionId))
				if not tried[regionId] then
					return regionId, nil, false
				end
			end
			return nil, "NO_REGION_AVAILABLE_NOW", false
		end
	end

	local function committedSpawner(counter)
		return function(_reservation, commit)
			counter.Value += 1
			local committed, reason = commit("spawn-" .. counter.Value)
			return committed, reason
		end
	end

	describe("Phase 6E-2 population configuration", function()
		it("validates the server-wide target and all approved profile admission caps", function()
			expect(function()
				ConfigValidator.AssertBrainrotPopulation("BrainrotPopulation", PopulationConfig)
			end).never.to.throw()
			expect(PopulationConfig.TargetWildPopulation).to.equal(42)
			expect(PopulationConfig.ProfileAdmissionCaps.Wanderer).to.equal(if Phase10.Enabled then 22 else 20)
			expect(PopulationConfig.ProfileAdmissionCaps.ReactiveRunner).to.equal(12)
			expect(PopulationConfig.ProfileAdmissionCaps.Sprinter).to.equal(8)
			expect(PopulationConfig.ProfileAdmissionCaps.Zigzag).to.equal(4)
			expect(PopulationConfig.ProfileAdmissionCaps.Camouflage).to.equal(2)
			expect(PopulationConfig.ProfileAdmissionCaps.DecoySplit).to.equal(2)
			expect(PopulationConfig.ProfileAdmissionCaps.LegendaryPursuit).to.equal(1)
			expect(PopulationConfig.ProfileAdmissionCaps.MythicEvent).to.equal(1)
			expect(PopulationConfig.NaturalReplenishmentEnabled).to.equal(true)
		end)
	end)

	describe("Phase 6E-2 authoritative identity membership", function()
		it("registers and unregisters RuntimeIds idempotently with derived indexes", function()
			local harness = World._TestCreatePopulationHarness(config(), {})
			expect(harness:Register("A", "BRT_019", "Forest")).to.equal(true)
			expect(harness:Register("A", "BRT_019", "Forest")).to.equal(false)
			expect(harness:Register("B", "BRT_019", nil)).to.equal(true)
			local snapshot = harness:Snapshot()
			expect(snapshot.Wild).to.equal(2)
			expect(snapshot.ByBehaviour.Sprinter).to.equal(2)
			expect(snapshot.ByRegion.REGION_FOREST).to.equal(1)
			expect(harness:Unregister("A", "PickedUp")).to.equal(true)
			expect(harness:Unregister("A", "PickedUp")).to.equal(false)
			expect(harness:Snapshot().Wild).to.equal(2)
			local consistent = harness:Validate()
			expect(consistent).to.equal(true)
		end)

		it("counts a real DecoySplit owner once and rejects effect identities", function()
			local harness = World._TestCreatePopulationHarness(config(), {})
			expect(harness:Register("real", "BRT_029", "GlitchZone")).to.equal(true)
			expect(harness:Register("D:encounter:1", "D:encounter:1", "GlitchZone")).to.equal(false)
			expect(harness:Register("D:encounter:2", "D:encounter:2", "GlitchZone")).to.equal(false)
			expect(harness:Snapshot().Wild).to.equal(1)
			expect(harness:Unregister("real", "PickedUp")).to.equal(true)
			expect(harness:Snapshot().Wild).to.equal(1)
		end)

		it("keeps unclassified player drops in the global total", function()
			local harness = World._TestCreatePopulationHarness(config(), {})
			expect(harness:Register("drop", "BRT_007", "Camp")).to.equal(true)
			local snapshot = harness:Snapshot()
			expect(snapshot.Wild).to.equal(1)
			expect(snapshot.ByRegion.REGION_CAMP).to.equal(nil)
		end)
	end)

	describe("Phase 6E-2 admission caps and reservations", function()
		it("includes reservations in profile admission without trimming player overage", function()
			local harness = World._TestCreatePopulationHarness(config(), {})
			for index = 1, 7 do
				expect(harness:Register("sprinter-" .. index, "BRT_019", "Forest")).to.equal(true)
			end
			expect(harness:Availability().blockedSpecies.BRT_019).to.equal(nil)
			local reservation = assert(harness:Reserve("Forest", "BRT_019"))
			expect(harness:Snapshot().ReservedByBehaviour.Sprinter).to.equal(1)
			expect(harness:Availability().blockedSpecies.BRT_019).to.equal(
				"PROFILE_POPULATION_CAP_REACHED"
			)
			expect(harness:Reserve("Forest", "BRT_020")).to.equal(nil)
			expect(harness:Commit(reservation.ReservationId, "sprinter-8")).to.equal(true)
			expect(harness:Register("player-drop", "BRT_019", nil)).to.equal(true)
			expect(harness:Snapshot().Wild).to.equal(9)
			expect(harness:Reserve("Forest", "BRT_019")).to.equal(nil)
		end)

		it("treats an optional regional maximum as admission-only", function()
			local harness = World._TestCreatePopulationHarness(config(), {
				GetRegion = function(regionId)
					return {
						id = regionId,
						kind = "Hunting",
						naturalSpawnAllowed = true,
						maxWild = 3,
					}
				end,
			})
			harness:Register("one", "BRT_007", "Forest")
			harness:Register("two", "BRT_007", "Forest")
			local reservation = assert(harness:Reserve("Forest", "BRT_007"))
			expect(harness:Reserve("Forest", "BRT_007")).to.equal(nil)
			expect(harness:Commit(reservation.ReservationId, "three")).to.equal(true)
			expect(harness:Register("player-drop", "BRT_007", "Forest")).to.equal(true)
			expect(harness:Snapshot().ByRegion.REGION_FOREST).to.equal(4)
			expect(harness:Reserve("Forest", "BRT_007")).to.equal(nil)
		end)

		it("prevents concurrent overspawn using effective reserved population", function()
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 2 }), {})
			local first = assert(harness:Reserve("Beach", "BRT_007"))
			local second = assert(harness:Reserve("Forest", "BRT_007"))
			expect(harness:Snapshot().Effective).to.equal(2)
			expect(harness:Reserve("Swamp", "BRT_007")).to.equal(nil)
			expect(harness:Commit(first.ReservationId, "first")).to.equal(true)
			expect(harness:Commit(second.ReservationId, "second")).to.equal(true)
			local snapshot = harness:Snapshot()
			expect(snapshot.Wild).to.equal(2)
			expect(snapshot.Reserved).to.equal(0)
		end)
	end)

	describe("Phase 6E-2 central reconciliation", function()
		it("rechecks current state and cancels a pending replenishment after a drop", function()
			local scheduler = fakeScheduler()
			local selectorCalls = 0
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 2 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest" }),
					SelectSpecies = function()
						selectorCalls += 1
						return { status = "Selected", speciesId = "BRT_007" }
					end,
					SpawnReservation = committedSpawner({ Value = 0 }),
				})
			harness:Register("existing", "BRT_007", "Forest")
			expect(harness:Start()).to.equal(true)
			harness:Register("dropped", "BRT_007", nil)
			scheduler.RunNext()
			expect(selectorCalls).to.equal(0)
			expect(harness:Snapshot().Wild).to.equal(2)
			expect(harness:Snapshot().Reserved).to.equal(0)
			harness:Stop()
		end)

		it("keeps both replacement and later player drop above target without trimming", function()
			local scheduler = fakeScheduler()
			local spawns = { Value = 0 }
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 2 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest" }),
					SelectSpecies = function()
						return { status = "Selected", speciesId = "BRT_007" }
					end,
					SpawnReservation = committedSpawner(spawns),
				})
			harness:Register("A", "BRT_007", "Forest")
			harness:Register("C", "BRT_007", "Forest")
			harness:Start()
			harness:Unregister("A", "PickedUp")
			scheduler.RunNext()
			expect(harness:Snapshot().Wild).to.equal(2)
			expect(spawns.Value).to.equal(0)
			expect(harness:Register("A", "BRT_007", nil)).to.equal(false)
			harness:Transition("A", "World")
			harness:Unregister("C", "PickedUp")
			expect(#scheduler.Queue).to.equal(0)
			expect(harness:Snapshot().Wild).to.equal(2)
			harness:FirstBank("C")
			scheduler.RunNext()
			expect(harness:Snapshot().Wild).to.equal(2)
			expect(spawns.Value).to.equal(1)
			harness:Stop()
		end)

		it("retains failed reservations without selecting a replacement species", function()
			local scheduler = fakeScheduler()
			local selectorCalls, spawnCalls = 0, 0
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 1 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest", "Jungle" }),
					SelectSpecies = function()
						selectorCalls += 1
						return { status = "Selected", speciesId = "BRT_007" }
					end,
					SpawnReservation = function()
						spawnCalls += 1
						return false, "PLACEMENT_FAILED"
					end,
				})
			harness:Start()
			scheduler.RunNext()
			expect(selectorCalls).to.equal(1)
			expect(spawnCalls).to.equal(1)
			expect(harness:Snapshot().Wild).to.equal(0)
			expect(harness:Snapshot().Reserved).to.equal(1)
			expect(#scheduler.Queue).to.equal(1)
			harness:Stop()
		end)

		it("does not busy-loop or fall back when the weighted pool is invalid", function()
			local scheduler = fakeScheduler()
			local selectorCalls = 0
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 1 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest" }),
					SelectSpecies = function()
						selectorCalls += 1
						return { status = "INVALID_CONFIGURATION" }
					end,
					SpawnReservation = function()
						error("must not spawn")
					end,
				})
			harness:Start()
			scheduler.RunNext()
			expect(selectorCalls).to.equal(1)
			expect(harness:Snapshot().Wild).to.equal(0)
			expect(harness:Snapshot().Reserved).to.equal(0)
			expect(#scheduler.Queue).to.equal(0)
			harness:Stop()
		end)

		it("treats temporary cap exhaustion as no eligible species now", function()
			local scheduler = fakeScheduler()
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 42 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest" }),
					SelectSpecies = function(_regionId, availability)
						expect(availability.blockedSpecies.BRT_019).to.equal(
							"PROFILE_POPULATION_CAP_REACHED"
						)
						return { status = "NO_ELIGIBLE_SPECIES_NOW" }
					end,
				})
			for index = 1, 8 do
				harness:Register("sprinter-" .. index, "BRT_019", "Forest")
			end
			-- The global target is deliberately larger than this profile count.
			-- Selection sees a temporary exclusion, makes no reservation and retries later.
			harness:Start()
			scheduler.RunNext()
			expect(harness:Snapshot().Reserved).to.equal(0)
			expect(#scheduler.Queue).to.equal(1)
			harness:Stop()
		end)

		it("bounds each pass and debounces duplicate reconcile requests", function()
			local scheduler = fakeScheduler()
			local spawns = { Value = 0 }
			local harness = World._TestCreatePopulationHarness(
				config({ TargetWildPopulation = 5, MaxSpawnReservationsPerPass = 3 }),
				{
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Beach", "Forest", "Swamp" }),
					SelectSpecies = function()
						return { status = "Selected", speciesId = "BRT_007" }
					end,
					SpawnReservation = committedSpawner(spawns),
				}
			)
			harness:Start()
			expect(harness:Request("one")).to.equal(false)
			expect(harness:Request("two")).to.equal(false)
			expect(#scheduler.Queue).to.equal(1)
			scheduler.RunNext()
			expect(spawns.Value).to.equal(3)
			expect(harness:Snapshot().Wild).to.equal(3)
			expect(#scheduler.Queue).to.equal(1)
			harness:Stop()
		end)

		it("invalidates delayed reconciliation and releases reservations on teardown", function()
			local scheduler = fakeScheduler()
			local selectorCalls = 0
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 2 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Forest" }),
					SelectSpecies = function()
						selectorCalls += 1
						return { status = "Selected", speciesId = "BRT_007" }
					end,
				})
			harness:Start()
			harness:Reserve("Forest", "BRT_007")
			expect(harness:Snapshot().Reserved).to.equal(1)
			expect(harness:Stop()).to.equal(true)
			expect(harness:Snapshot().Reserved).to.equal(0)
			scheduler.RunNext()
			expect(selectorCalls).to.equal(0)
			expect(harness:Snapshot().Wild).to.equal(0)
		end)

		it("uses one global target instead of a target per region", function()
			local scheduler = fakeScheduler()
			local selectorCalls = 0
			local harness =
				World._TestCreatePopulationHarness(config({ TargetWildPopulation = 42 }), {
					Schedule = scheduler.Schedule,
					ChooseRegion = regionPolicy({ "Beach" }),
					SelectSpecies = function()
						selectorCalls += 1
						return { status = "Selected", speciesId = "BRT_007" }
					end,
				})
			local regions =
				{ "Beach", "Forest", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" }
			for index = 1, 42 do
				harness:Register("global-" .. index, "BRT_007", regions[((index - 1) % 7) + 1])
			end
			harness:Start()
			scheduler.RunNext()
			expect(selectorCalls).to.equal(0)
			expect(harness:Snapshot().Wild).to.equal(42)
			harness:Stop()
		end)
	end)
end
