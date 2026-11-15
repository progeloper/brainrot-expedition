--!nocheck
-- Disposable native geometry/source transactions with fake actors and isolated profiles.
-- This does not claim connected players, actual mobile rendering or backend saves.
return function()
	local Fixture = require(script.Parent.Support.Phase12NativeFixture)
	local Services, Systems = script.Parent.Parent.Services, script.Parent.Parent.Systems
	local Escape = require(Services.Phase12EscapeService)
	local Cycle = require(Services.Phase12WorldService)
	local World = require(Systems.DevelopmentBrainrotSpawner)
	local Interaction = require(Systems.BrainrotInteractionSystem)
	local Cargo = require(Services.CartCargoService)
	local Carts = require(Services.CartService)
	local Regions = require(Systems.RegionSpawnCatalog)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Storage = require(script.Parent.Parent.Classes.BaseStorage)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	-- Only Epic and above escape; Epic rolls 4-7 s, so the fixed 0.25 draw gives 4.75.
	local ESCAPER = "BRT_027"
	local function native(callback)
		Escape:Stop()
		Cycle:Stop()
		Fixture(function(f)
			local time = 1000
			local draws = 0
			local rng = {}
			function rng:NextNumber()
				draws += 1
				return 0.25
			end
			function rng:NextInteger(low, _high)
				return low
			end
			assert(Interaction._TrackCharacterForTesting(f.p), "Native actor tracker must bind")
			World._TestSetSleepClock(function()
				return time
			end)
			f.now = function()
				return time
			end
			f.at = function(value)
				time = value
				Placement.ResetQueryBudgetForTesting()
			end
			f.draws = function()
				return draws
			end
			f.find = function(id)
				local found, count = nil, 0
				for _, model in World.GetWorldModels() do
					local record = World.GetWorldRecord(model)
					if record and record.ItemId == id then
						found, count = model, count + 1
					end
				end
				return found, count
			end
			f.repick = function(id)
				local model, count = f.find(id)
				assert(model and count == 1, "One escaped representation required")
				local record, state = World.GetWorldRecord(model)
				if state ~= "WorldSleeping" then
					assert(World.TrySleep(model))
				end
				f.p.Character:PivotTo(CFrame.new(model:GetPivot().Position + Vector3.new(0, 0, 5)))
				assert(Interaction.TryPickupWorld(f.p, model, record.ItemId))
				return record
			end
			f.load = function(species, slot)
				local record = f.carry(species or "BRT_011", { MutationId = "Golden" })
				f.near(slot or "Slot1")
				assert(Interaction.TryPlaceInCargo(f.p, f.cart, slot or "Slot1", record.ItemId))
				return Cargo:GetSlotRecord(f.cart, slot or "Slot1")
			end
			f.startCycle = function(campPosition, wipes)
				local camp = f.part(f.root, "AuthoredCampColumn", campPosition or f.origin, Vector3.new(20, 2, 20))
				camp.CanCollide, camp.CanTouch, camp.CanQuery = false, false, false
				camp:SetAttribute("RegionId", "REGION_CAMP")
				local original = Regions.ContainsPosition
				f.replace(Regions, "ContainsPosition", function(id, position, tolerance)
					if id ~= "REGION_CAMP" then
						return original(id, position, tolerance)
					end
					local p = camp.CFrame:PointToObjectSpace(position)
					return math.abs(p.X) <= camp.Size.X / 2 and math.abs(p.Z) <= camp.Size.Z / 2
				end)
				local returns = 0
				assert(Cycle:Start({
					Spawner = World,
					InteractionService = Interaction,
					CargoService = Cargo,
					Analytics = f.cycleAnalytics,
					CartService = Carts,
					WorldReady = function()
						return f.cycleWorldReady ~= false
					end,
					GetPlayers = function()
						return { f.p }
					end,
					Now = f.now,
					Random = rng,
					Heartbeat = false,
					ReturnCart = function(player, cart, cycle)
						assert(
							player == f.p and cart == f.cart and Cycle:IsReturnAuthorized(player, cart, cycle),
							"Server-only exact return context"
						)
						returns += 1
						cart:PivotTo(CFrame.new(camp.Position + Vector3.new(0, 3, 0)))
						return true
					end,
					RestoreBanked = function()
						return true
					end,
				}))
				Cycle:_SetResetWipesWorldForTesting(wipes ~= false)
				return camp, function()
					return returns
				end
			end
			f.bankHeld = function(record)
				local base = Instance.new("Model")
				base.Name = "NativeBank"
				base.Parent = f.root
				local profile = Schema.CreateDefault()
				local slots = {}
				for i = 1, 12 do
					local part = f.part(base, "Slot" .. i, f.origin + Vector3.new(i * 4, 0, 20))
					local marker = Instance.new("Attachment")
					marker.Parent = part
					slots[i] = { Index = i, Platform = part, Marker = marker }
				end
				local storage = Storage.new(base, f.p.UserId, slots, profile)
				local display = assert(Cargo:CreateItemVisual(record.BrainrotId))
				local token = assert(storage:TryReserveSlot(record.ItemId, 1))
				local consumed = Interaction.ConsumeCarriedBrainrot(
					f.p,
					record.ItemId,
					"Phase12NativeBank",
					function(exact)
						assert(storage:CommitReservation(token, exact, display, nil, time))
						-- This isolated fixture supplies its covering-save acknowledgement explicitly.
						local operationId = "Bank:" .. exact.ItemId
						assert(World.BeginPendingBank(exact, operationId, 1))
						assert(World.ConfirmPendingBank(exact, operationId))
						return true
					end
				)
				assert(consumed, "Existing exact carry consume failed")
				return profile, storage
			end
			assert(Escape:Start({
				World = World,
				Interaction = Interaction,
				Cargo = Cargo,
				Cart = Carts,
				GetPlayers = function()
					return { f.p }
				end,
				Now = f.now,
				Random = rng,
				Heartbeat = false,
				WorldService = Cycle,
			}))
			-- Cycle is inactive for ordinary escape fixtures; its normal CanCommit permits them.
			local ok, reason = xpcall(function()
				callback(f)
			end, debug.traceback)
			Escape:Stop()
			Cycle:Stop()
			World._TestSetSleepClock(nil)
			assert(ok, reason)
		end)
	end
	describe("Phase 12 native transport source integration", function()
		it("Uncommon and Rare never arm an escape (owner decision, 10 Nov 2026)", function()
			native(function(f)
				local record = f.load("BRT_011")
				local state = World.GetPhase12State(record)
				expect(state.EscapeDeadline).to.equal(nil)
				expect(state.EscapeRolledDelay).to.equal(nil)
				expect(f.draws()).to.equal(0)
				f.at(1100)
				Escape:Step(f.now())
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
			end)
		end)
		it(
			"arms only on physical pickup and retains the exact fractional deadline through carry/cargo/pickup",
			function()
				native(function(f)
					local model, record = f.spawn(nil, ESCAPER, { MutationId = "Golden" })
					expect(World.GetPhase12State(record).EscapeDeadline).to.equal(nil)
					f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 5)))
					assert(Interaction.TryPickupWorld(f.p, model, record.ItemId))
					local state = World.GetPhase12State(record)
					expect(state.EscapeRolledDelay).to.equal(4.75)
					expect(state.EscapeDeadline).to.equal(1004.75)
					expect(f.draws()).to.equal(1)
					f.at(1002)
					f.near("Slot1")
					assert(Interaction.TryPlaceInCargo(f.p, f.cart, "Slot1", record.ItemId))
					local cargo = Cargo:GetSlotRecord(f.cart, "Slot1")
					expect(cargo.ItemId).to.equal(record.ItemId)
					expect(cargo.Metadata.MutationId).to.equal("Golden")
					expect(World.GetPhase12State(cargo).EscapeDeadline).to.equal(1004.75)
					assert(Interaction.TryPickupCargo(f.p, f.cart, "Slot1", record.ItemId))
					expect(World.GetPhase12State(Interaction.GetCarriedRecord(f.p)).EscapeDeadline).to.equal(1004.75)
					expect(f.draws()).to.equal(1)
				end)
			end
		)
		it("external drop pauses and resumes remaining time without consuming or rerolling an attempt", function()
			native(function(f)
				local record = f.carry(ESCAPER, { MutationId = "Golden" })
				f.at(1003)
				assert(Interaction.TryDropCarried(f.p, record.ItemId))
				local state = World.GetPhase12State(record)
				expect(state.EscapeDeadline).to.equal(nil)
				expect(state.EscapeRemainingSeconds).to.equal(1.75)
				expect(state.EscapeAttemptsUsed).to.equal(0)
				f.at(1010)
				record = f.repick(record.ItemId)
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(1011.75)
				expect(f.draws()).to.equal(1)
			end)
		end)
		it(
			"failed native placement retains exact cargo, reservation and charge; retry commits one jump and recapture HP",
			function()
				native(function(f)
					local record = f.load(ESCAPER)
					local revision = Cargo:GetCargoRevision(f.cart)
					local ground = f.root.Ground
					ground.Parent = nil
					f.at(1005)
					Escape:Step(f.now())
					expect(Cargo:GetSlotRecord(f.cart, "Slot1")).to.equal(record)
					expect(Cargo:GetCargoRevision(f.cart)).to.equal(revision)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
					expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(0)
					expect(select(2, f.find(record.ItemId))).to.equal(0)
					ground.Parent = f.root
					f.at(1006)
					Escape:Step(f.now())
					expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
					local model, count = f.find(record.ItemId)
					expect(count).to.equal(1)
					expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(1)
					expect(World.GetPhase12State(record).RemainingHp).to.equal(3) -- Epic recaptures at full HP
					expect(model:GetAttribute("Phase12RemainingHp")).to.equal(3)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
					f.at(1007)
					Escape:Step(f.now())
					expect(select(2, f.find(record.ItemId))).to.equal(1)
				end)
			end
		)
		it("two cargo clocks stay independent and focused warning names the actual earliest due slot", function()
			native(function(f)
				local first = f.load(ESCAPER, "Slot1")
				f.at(1001)
				local second = f.load(ESCAPER, "Slot2")
				expect(World.GetPhase12State(first).EscapeDeadline).to.equal(1004.75)
				expect(World.GetPhase12State(second).EscapeDeadline).to.equal(1005.75)
				f.at(1004.2)
				Escape:Step(f.now())
				expect(f.p:GetAttribute("Phase12EscapeInstanceId")).to.equal(first.ItemId)
				expect(f.p:GetAttribute("Phase12EscapeRemainingJumps")).to.equal(1)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1")).to.equal(first)
				expect(World.GetPhase12State(second).EscapeDeadline).to.equal(1005.75)
				expect(f.draws()).to.equal(2)
			end)
		end)
		it("real held release consumes one allowance, and exhausted recapture remains stable", function()
			native(function(f)
				local record = f.carry(ESCAPER, { MutationId = "Astral" })
				f.at(1009)
				Escape:Step(f.now())
				expect(Interaction.GetCarriedRecord(f.p)).to.equal(nil)
				expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(1)
				expect(World.GetPhase12State(record).RemainingHp).to.equal(3) -- Epic recaptures at full HP
				record = f.repick(record.ItemId)
				expect(record.Metadata.MutationId).to.equal("Astral")
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(nil)
				expect(f.draws()).to.equal(1)
				f.at(1100)
				Escape:Step(f.now())
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(record.ItemId)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
			end)
		end)
		it("Legendary second pickup rolls a new independent interval after the first actual jump", function()
			native(function(f)
				local record = f.load("BRT_031")
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(1002.5)
				f.at(1003)
				Escape:Step(f.now())
				expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(1)
				f.at(1004)
				record = f.repick(record.ItemId)
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(1006.5)
				expect(f.draws()).to.equal(2)
				f.at(1007)
				Escape:Step(f.now())
				expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(2)
				f.at(1008)
				record = f.repick(record.ItemId)
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(nil)
				expect(f.draws()).to.equal(2)
			end)
		end)
		it("bank commit wins a due escape without another jump, reservation release or discovery", function()
			native(function(f)
				local record = f.carry(ESCAPER, { MutationId = "Golden" })
				f.at(1004.75)
				local profile, storage = f.bankHeld(record)
				expect(profile.Collection.BrainrotInstances[record.ItemId].mutationId).to.equal("Golden")
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(false)
				Escape:Step(f.now())
				expect(select(2, f.find(record.ItemId))).to.equal(0)
				expect(profile.Economy.Balance).to.equal(0)
				expect(World.CommitFirstBank(record)).to.equal(false)
				storage:Destroy()
			end)
		end)
	end)
	describe("Phase 12 native timed retirement races (legacy wipe path, ResetWipesWorld = true)", function()
		it("default rollover starts a rare wave and forfeits nothing", function()
			native(function(f)
				local record = f.load("BRT_011")
				local held = f.carry("BRT_011", { MutationId = "Golden" })
				local free, freeRecord = f.spawn(true, "BRT_007", { MutationId = "None" })
				free:PivotTo(CFrame.new(f.origin - Vector3.new(60, 0, 0)))
				local waves = 0
				f.replace(World, "BeginRareWave", function()
					waves += 1
					return true
				end)
				local _camp, returns = f.startCycle(f.origin + Vector3.new(80, 0, 0), false)
				local before = Cycle:GetCycleSnapshot().cycleId
				f.at(1300)
				Cycle:Step(f.now())
				expect(waves).to.equal(1)
				expect(Cycle:IsResetCommitting()).to.equal(false)
				expect(Cycle:GetCycleSnapshot().cycleId).to.equal(before + 1)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
				expect(Cargo:IsResetPreserved(f.cart)).to.equal(false)
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(held.ItemId)
				expect(World.HasOrdinaryReservation(freeRecord.ItemId)).to.equal(true)
				expect(free.Parent ~= nil).to.equal(true)
				expect(returns()).to.equal(0)
				expect(f.p.Character:FindFirstChildOfClass("Humanoid").Health > 0).to.equal(true)
			end)
		end)
		it("keeps reset frozen until exact cargo resume succeeds and observes each outcome once", function()
			native(function(f)
				local record = f.load("BRT_011")
				local events = {}
				f.cycleAnalytics = {
					Record = function(_, _, name, value, fields)
						table.insert(
							events,
							{ name = name, value = value, category = fields.category, result = fields.result }
						)
						return true
					end,
				}
				local calls, originalEnd = 0, Cargo.EndResetPreservation
				f.replace(Cargo, "EndResetPreservation", function(self, player, generation)
					calls += 1
					if calls == 1 then
						return false
					end
					return originalEnd(self, player, generation)
				end)
				f.startCycle(f.origin + Vector3.new(80, 0, 0))
				f.at(1300)
				Cycle:Step(f.now())
				expect(Cycle:IsResetCommitting()).to.equal(true)
				expect(Cargo:IsResetPreserved(f.cart)).to.equal(true)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
				expect(#events).to.equal(1)
				expect(events[1].category).to.equal("ResetCargoPendingJobs")
				expect(events[1].value).to.equal(1)
				f.at(1301)
				Cycle:Step(f.now())
				expect(Cargo:IsResetPreserved(f.cart)).to.equal(false)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
				expect(#events).to.equal(2)
				expect(events[2].category).to.equal("ResetCargoPreserved")
				expect(events[2].value).to.equal(1)
				f.at(1302)
				Cycle:Step(f.now())
				expect(#events).to.equal(2)
			end)
		end)
		it("pauses committed cargo for an unready owner with no held item", function()
			native(function(f)
				local record = f.load(ESCAPER)
				World.UpdatePhase12State(record, { EscapeDeadline = 1307.5, EscapeAttemptsUsed = 0 })
				local pauses, oldPause = 0, Escape.PauseForReset
				f.replace(Escape, "PauseForReset", function(self, generation, records)
					pauses += 1
					expect(records[1].ItemId).to.equal(record.ItemId)
					return oldPause(self, generation, records)
				end)
				f.cycleWorldReady = false
				local _, returns = f.startCycle(f.origin + Vector3.new(80, 0, 0))
				local draws = f.draws()
				f.at(1300)
				Cycle:Step(f.now())
				expect(pauses).to.equal(1)
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
				expect(World.GetPhase12State(record).EscapeDeadline).to.equal(1307.5)
				expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(0)
				expect(f.draws()).to.equal(draws)
				expect(returns()).to.equal(0)
				expect(f.p.Character:FindFirstChildOfClass("Humanoid").Health > 0).to.equal(true)
			end)
		end)
		it("successful owned bank survives a later wipe and character cleanup with no fresh recreation", function()
			native(function(f)
				local record = f.carry("BRT_011", { MutationId = "Golden" })
				local profile, storage = f.bankHeld(record)
				f.startCycle(f.origin + Vector3.new(80, 0, 0))
				f.at(1300)
				Cycle:Step(f.now())
				f.removing:Fire(f.p.Character)
				task.wait()
				expect(profile.Collection.BrainrotInstances[record.ItemId].mutationId).to.equal("Golden")
				expect(profile.Collection.SpeciesMutations.BRT_011.Golden ~= nil).to.equal(true)
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(false)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
				expect(profile.Economy.Balance).to.equal(0)
				storage:Destroy()
			end)
		end)
		it("wipe wins before held bank, and delayed character callbacks cannot recreate the retired source", function()
			native(function(f)
				local record = f.carry("BRT_011", { MutationId = "Golden" })
				local camp = f.startCycle(f.origin + Vector3.new(80, 0, 0))
				expect(Cycle:IsInCamp(f.p.Character.HumanoidRootPart.Position)).to.equal(false)
				f.at(1300)
				Cycle:Step(f.now())
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(false)
				expect(Interaction.GetCarriedRecord(f.p)).to.equal(nil)
				expect(f.p.Character:FindFirstChildOfClass("Humanoid").Health).to.equal(0)
				f.removing:Fire(f.p.Character)
				task.wait()
				expect(Interaction.ConsumeCarriedBrainrot(f.p, record.ItemId, "late-bank")).to.equal(nil)
				expect(World.PrepareFreshRelease(record, CFrame.new(camp.Position))).to.equal(nil)
				expect(select(2, f.find(record.ItemId))).to.equal(0)
				expect(Cycle:CanCommit(1, camp.Position, f.p)).to.equal(false)
			end)
		end)
		it(
			"preserved cargo keeps its identity and reservation across reset and ignores delayed character cleanup",
			function()
				native(function(f)
					local record = f.load("BRT_011")
					local token = assert(World.PrepareFreshRelease(record, f.cart:GetPivot(), { f.cart }, nil, f.cart))
					local _camp, returns = f.startCycle(f.origin + Vector3.new(80, 0, 0))
					f.at(1300)
					Cycle:Step(f.now())
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
					expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
					local called = false
					expect(World.CommitFreshRelease(token, function()
						called = true
						return true
					end)).to.equal(nil)
					expect(called).to.equal(false)
					expect(returns()).to.equal(1)
					f.removing:Fire(f.p.Character)
					task.wait()
					World.ProcessPendingFreshReleases(os.clock() + 3)
					expect(select(2, f.find(record.ItemId))).to.equal(0)
					expect(Cargo:GetCargoCount(f.cart)).to.equal(1)
				end)
			end
		)
		it("Camp player and committed cargo survive while all fresh free worlds retire", function()
			native(function(f)
				local record = f.load("BRT_011")
				local inside, insideRecord = f.spawn(nil, "BRT_007", { MutationId = "None" })
				inside:PivotTo(CFrame.new(f.origin + Vector3.new(30, 0, 0)))
				local outside, outsideRecord = f.spawn(true, "BRT_007", { MutationId = "None" })
				outside:PivotTo(CFrame.new(f.origin - Vector3.new(60, 0, 0)))
				f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(30, 0, 4)))
				f.startCycle(f.origin + Vector3.new(30, 0, 0))
				f.at(1300)
				Cycle:Step(f.now())
				expect(Cargo:GetSlotRecord(f.cart, "Slot1").ItemId).to.equal(record.ItemId)
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
				expect(World.HasOrdinaryReservation(insideRecord.ItemId)).to.equal(false)
				expect(inside.Parent == nil).to.equal(true)
				expect(World.HasOrdinaryReservation(outsideRecord.ItemId)).to.equal(false)
				expect(outside.Parent).to.equal(nil)
				expect(f.p.Character:FindFirstChildOfClass("Humanoid").Health > 0).to.equal(true)
			end)
		end)
		it("ordinary CharacterRemoving preserves and releases fresh individuals instead of timed forfeiture", function()
			native(function(f)
				local record = f.load("BRT_011")
				local originalPivot = f.cart:GetPivot()
				f.removing:Fire(f.p.Character)
				task.wait()
				-- The ordinary owner commits a counted pending world handoff. Move the old
				-- avatar clear as native respawn does, then run its existing bounded retry.
				f.p.Character:PivotTo(CFrame.new(f.origin + Vector3.new(0, 0, 50)))
				f.at(1001)
				World.ProcessPendingFreshReleases(os.clock() + 10)
				expect(World.HasOrdinaryReservation(record.ItemId)).to.equal(true)
				expect(Cargo:GetCargoCount(f.cart)).to.equal(0)
				expect(select(2, f.find(record.ItemId))).to.equal(1)
				expect(f.cart:GetPivot()).to.equal(originalPivot)
				expect(World.GetPhase12State(record).EscapeAttemptsUsed).to.equal(0)
			end)
		end)
	end)
end
