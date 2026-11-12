--!nocheck
-- Real PDS mutation/diagnostic/save boundary with an injected in-memory backend.
-- No real profiles, gameplay startup or platform purchases.
return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Profiles = require(script.Parent.Parent.Services.PlayerDataService)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local Backend = require(script.Parent.Support.FakePlayerProfileBackend)
	local nextId = 839190
	local function run(test)
		Profiles:_ResetForTests()
		local clock, sequence = 1000, 0
		local backend = Backend.new({
			Now = function()
				return clock
			end,
		})
		Profiles:Init({
			Backend = backend,
			UnixNow = function()
				return clock
			end,
			MonotonicNow = function()
				return clock
			end,
			Wait = function(seconds)
				clock += seconds
			end,
			Random = function()
				return 0
			end,
			KickOnFailure = false,
			GenerateOperationId = function(prefix)
				sequence += 1
				return prefix .. ":platform-observer:" .. sequence
			end,
		})
		nextId += 1
		local player = { UserId = nextId, Name = "SyntheticPlatformObserver", Parent = Players, Attributes = {} }
		function player:SetAttribute(key, value)
			self.Attributes[key] = value
		end
		function player:GetAttribute(key)
			return self.Attributes[key]
		end
		function player:Kick(reason)
			error("SYNTHETIC_PROFILE_UNEXPECTED_KICK:" .. tostring(reason))
		end
		local ok, why = xpcall(function()
			Profiles:LoadPlayerAsync(player)
			assert(Profiles:GetStatus(player) == "Ready", "IN_MEMORY_PROFILE_NOT_READY")
			local seeded = Profiles:CommitMutation(player, function(data)
				data.Economy.Balance = 20
				data.Collection.BrainrotInstances.old = { speciesId = "BRT_001", mutationId = "None" }
				data.Collection.BrainrotInstances.incoming = { speciesId = "BRT_001", mutationId = "Golden" }
				data.Base.Slots["1"].brainrotId = "old"
				data.Base.Slots["1"].accumulatedCash = 100
				return true, { code = "SyntheticPlatformObserverSetup" }
			end)
			assert(seeded.ok, "SYNTHETIC_PROFILE_SEED_REJECTED")
			local events = {}
			Profiles:SubscribeDiagnostics(function(_, event)
				if event.kind == "PlatformCashDiscarded" then
					table.insert(events, event)
				end
			end)
			test(player, events, backend)
		end, debug.traceback)
		Profiles:_ResetForTests()
		assert(ok, why)
	end
	local function ordinary(player, walletCredit)
		return Profiles:CommitMutation(player, function(data)
			data.Economy.Balance += walletCredit
			data.Base.Slots["1"].brainrotId = "incoming"
			data.Base.Slots["1"].accumulatedCash = 0
			return true, { code = "SyntheticPlatformSettlement" }
		end)
	end
	local function critical(player, kind, apply)
		local id = "platform-observer:" .. kind
		local handle = assert(Profiles:AcquireCritical(player, id))
		local result = Profiles:CommitCriticalMutation(player, handle, function(data)
			local applied, receipt = apply(data)
			assert(applied, receipt and receipt.code)
			Rules.AppendOperation(data, id, kind, Profiles:GetCurrentRevision(player) + 1, 1000, receipt)
			return true, { code = "PENDING", result = receipt }
		end)
		assert(result.ok and result.committed, "CRITICAL_FIXTURE_REJECTED")
		Profiles:RequestSave(player, "SyntheticPlatformObserverCoveringSave")
		assert(Profiles:IsRevisionConfirmed(player, result.revision), "IN_MEMORY_COVERING_SAVE_MISSING")
		assert(Profiles:ReleaseCritical(player, handle))
		return Profiles:GetReadableData(player), result
	end
	describe("Phase13 proven platform cash loss observations", function()
		it("keeps a conserved wallet settlement out of discard telemetry", function()
			run(function(player, events)
				assert(ordinary(player, 100).ok, "CONSERVED_SETTLEMENT_REJECTED")
				expect(Rules.Cash(Profiles:GetReadableData(player))).to.equal(120)
				expect(#events).to.equal(0)
			end)
		end)
		it("retains genuine ordinary platform loss exactly once across a lost save response", function()
			run(function(player, events, backend)
				backend.CommitThenFailSaveCount = 1
				local mutation = ordinary(player, 0)
				assert(mutation.ok, "LOSS_MUTATION_REJECTED")
				Profiles:RequestSave(player, "SyntheticLostSaveResponse")
				assert(Profiles:IsRevisionConfirmed(player, mutation.revision))
				Profiles:RequestSave(player, "SyntheticDuplicateSave")
				expect(#events).to.equal(1)
				expect(events[1].amount).to.equal(100)
				expect(events[1].signedAmount).to.equal(-100)
				expect(Rules.Cash(Profiles:GetReadableData(player))).to.equal(20)
			end)
		end)
		it("reports only the unretained remainder of a partial settlement", function()
			run(function(player, events)
				assert(ordinary(player, 60).ok, "PARTIAL_SETTLEMENT_REJECTED")
				expect(#events).to.equal(1)
				expect(events[1].amount).to.equal(40)
				expect(events[1].signedAmount).to.equal(-40)
				expect(Rules.Cash(Profiles:GetReadableData(player))).to.equal(80)
			end)
		end)
		it("uses actual collection-rebirth rules without reporting retained cash as lost", function()
			run(function(player, events)
				assert(
					Profiles:CommitMutation(player, function(data)
						for i = 1, 12 do
							local id = "collection-platform-" .. i
							data.Collection.BrainrotInstances[id] =
								{ speciesId = if i <= 4 then "BRT_019" else "BRT_001", mutationId = "None" }
							data.Base.Slots[tostring(i)].brainrotId = id
						end
						return true, { code = "SyntheticFullCollection" }
					end).ok,
					"CANONICAL_FIXTURE_REJECTED"
				)
				local data = critical(player, "Rebirth", function(current)
					local quote = Rules.QuoteRebirth(current, "BDS_002", "Collection")
					assert(quote.ok, "ACTUAL_COLLECTION_RULE_QUOTE_REJECTED")
					return Rules.ApplyRebirth(current, quote, 1000)
				end)
				expect(Rules.Cash(data)).to.equal(120)
				expect(next(data.Collection.BrainrotInstances)).to.equal(nil)
				expect(#events).to.equal(0)
			end)
		end)
		it("settles actual sell-and-replace accrued cash without a false loss", function()
			run(function(player, events)
				local before = Rules.Cash(Profiles:GetReadableData(player))
				local data, mutation = critical(player, "PlatformSwap", function(current)
					return Rules.ApplySwap(current, {
						previewRevision = current.Phase13.EligibilityRevision,
						slotIndex = 1,
						outgoingId = "old",
						action = "SellAndReplace",
						ownerUserId = player.UserId,
						incomingFresh = false,
						incomingRecord = {
							ItemId = "incoming",
							BrainrotId = "BRT_001",
							Metadata = { MutationId = "Golden" },
						},
					}, 1000)
				end)
				expect(Rules.Cash(data)).to.equal(before + mutation.result.saleCash)
				expect(data.Base.Slots["1"].brainrotId).to.equal("incoming")
				expect(#events).to.equal(0)
			end)
		end)
		it("leaves the canonical cash-rebirth receipt as the sole sacrifice accounting", function()
			run(function(player, events)
				assert(
					Profiles:CommitMutation(player, function(data)
						data.Economy.Balance = 300000000
						return true, { code = "SyntheticRebirthWallet" }
					end).ok,
					"CANONICAL_FIXTURE_REJECTED"
				)
				local data, mutation = critical(player, "Rebirth", function(current)
					return Rules.ApplyRebirth(current, Rules.QuoteRebirth(current, "BDS_002", "Cash"), 1000)
				end)
				expect(mutation.result.sacrificedCash).to.equal(300000100)
				expect(Rules.Cash(data)).to.equal(0)
				expect(data.Phase13.RebirthCount).to.equal(1)
				expect(#events).to.equal(0)
			end)
		end)
		it("does not hide a loss behind a mismatched critical receipt amount", function()
			run(function(player, events)
				critical(player, "Rebirth", function(data)
					data.Base.Slots["1"].brainrotId = "incoming"
					data.Base.Slots["1"].accumulatedCash = 0
					return true, { route = "Cash", sacrificedCash = 999 }
				end)
				expect(#events).to.equal(1)
				expect(events[1].amount).to.equal(100)
			end)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
