--!nocheck
-- Isolated storage/receipt fixtures. Synthetic platform IDs never enter a normal client remote.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Capacity = require(RS.Shared.Utility.Phase13CommerceCapacity)
	local Rules = require(RS.Shared.Utility.Phase13CommerceRules)
	local PhaseRules = require(RS.Shared.Utility.Phase13Rules)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Store = require(script.Parent.Parent.Data.PlayerProfileStore)
	local Service = require(script.Parent.Parent.Services.Phase13CommerceService)
	local function run(callback)
		local f = {
			data = Schema.CreateDefault(),
			revision = 0,
			saved = 0,
			mutations = 0,
			prompts = 0,
			telemetry = {},
			available = true,
		}
		f.player = { UserId = 831319 }
		local profile = {}
		function profile:GetReadableData()
			return if f.available then f.data else nil
		end
		function profile:GetCurrentRevision()
			return f.revision
		end
		function profile:GetSavedRevision()
			return f.saved
		end
		function profile:IsRevisionConfirmed(_, revision)
			return f.saved >= revision
		end
		function profile:IsWritable()
			return f.available and not f.busy
		end
		function profile:GetSaveEnvelope(_, snapshot, revision)
			return if f.noEnvelope
				then nil
				else {
					Transport = {
						Version = 3,
						OwnerToken = "fixture-owner",
						LastRevision = revision,
						LeaseExpiresAt = 1180,
					},
					Data = snapshot,
					RetainedExtension = f.extension,
				}
		end
		local transactions = {}
		function transactions:IsBusy()
			return f.busy == true or f.revision > f.saved
		end
		function transactions:SubscribeConfirmed(listener)
			f.listener = listener
			return {
				Disconnect = function()
					f.listener = nil
				end,
			}
		end
		function transactions:CommitCritical(_, operationId, kind, mutator)
			if self:IsBusy() then
				return { ok = false, code = "BUSY" }
			end
			if f.cutoverRevision then
				f.revision += 1
				f.cutoverRevision = false
			end
			local before = Capacity.Copy(f.data)
			local ok, result = mutator(f.data, 1000)
			if not ok then
				f.data = before
				return { ok = false, code = result.code }
			end
			f.revision += 1
			f.mutations += 1
			PhaseRules.AppendOperation(f.data, operationId, kind, f.revision, 1000, result)
			f.pending = { operationId = operationId, state = "Confirmed", kind = kind, result = result }
			return { ok = true, state = "Saving" }
		end
		function f.confirm()
			f.saved = f.revision
			f.canonical = Capacity.Copy(f.data)
			if f.pending and f.listener then
				local receipt = f.pending
				f.pending = nil
				f.listener(f.player, receipt)
			end
		end
		f.row = { id = "FIXTURE_POUCH", platformId = 101, verifiedUniverseId = 999, amount = 500000000 }
		f.catalogue = {
			UniverseId = 999,
			Version = "FIXTURE",
			ProductionDeliveryEnabled = true,
			PaidCapacityRecoveryReady = true,
			PriceCacheSeconds = 300,
			Passes = {},
			Products = { f.row },
		}
		Service:_ConfigureForTests({
			Profile = profile,
			Transactions = transactions,
			UniverseId = 999,
			Catalogue = f.catalogue,
			Marketplace = {
				GetProductInfoAsync = function()
					return { ProductId = 101, PriceInRobux = 49 }
				end,
				PromptProductPurchase = function()
					f.prompts += 1
				end,
			},
			ResolvePlayer = function(userId)
				return if userId == f.player.UserId then f.player else nil
			end,
			Telemetry = {
				Record = function(_, _, name, value, fields)
					table.insert(f.telemetry, { name = name, value = value, fields = fields })
				end,
				Funnel = function() end,
			},
		})
		function f.receipt(id)
			return { PlayerId = f.player.UserId, ProductId = 101, PurchaseId = id }
		end
		local ok, why = xpcall(function()
			callback(f)
		end, debug.traceback)
		Service:_ResetFixture()
		assert(ok, why)
	end
	describe("Encoded Transport3 commerce admission and delayed recovery", function()
		it("projects all retained acquired-envelope fields and matches actual saved encoding", function()
			local storeData = {
				value = {
					Transport = { Version = 3, LastRevision = 0, LeaseExpiresAt = 0 },
					Data = Schema.CreateDefault(),
					Extension = string.rep('"', 512),
				},
			}
			function storeData:UpdateAsync(_, transform)
				self.value = transform(Capacity.Copy(self.value))
				return Capacity.Copy(self.value)
			end
			local store = Store.new({
				Available = true,
				DataStore = storeData,
				UnixNow = function()
					return 1000
				end,
			})
			local acquired = store:Acquire("synthetic", "owner", 180)
			expect(acquired.ok).to.equal(true)
			expect(acquired.saveEnvelope.Data).to.equal(nil)
			local projected =
				Store.ProjectSaveEnvelope(acquired.saveEnvelope, acquired.data, "owner", "save:fixture", 1, 1180)
			expect(projected.Extension).to.equal(storeData.value.Extension)
			expect(store:Save("synthetic", "owner", "save:fixture", 1, acquired.data, 180).ok).to.equal(true)
			expect(#Http:JSONEncode(projected)).to.equal(#Http:JSONEncode(storeData.value))
			expect(storeData.value.Transport.Version).to.equal(3)
		end)
		it("uses measured JSON bytes at the exact admission boundary including escaped strings", function()
			local envelope = { Transport = { Version = 3 }, Data = { text = string.rep('"', 200), padding = "" } }
			local overhead = #Http:JSONEncode(envelope)
			local maximum = Capacity.EntryLimitBytes
				- Capacity.PromptMarginBytes
				- Capacity.ProjectionGrowthReserveBytes
			envelope.Data.padding = string.rep("x", maximum - overhead)
			local at = Capacity.MeasureEnvelope(envelope, Capacity.PromptMarginBytes)
			expect(at.ok).to.equal(true)
			expect(at.encodedBytes).to.equal(maximum)
			envelope.Data.padding ..= "x"
			expect(Capacity.MeasureEnvelope(envelope, Capacity.PromptMarginBytes).ok).to.equal(false)
		end)
		it(
			"prevents unsafe prompts while the smaller delayed-receipt delivery reserve still admits an exact saved grant",
			function()
				run(function(f)
					f.data.Padding = string.rep("x", 3800000)
					Service:RefreshPrices()
					expect(Service:Prompt(f.player, f.row.id).code).to.equal("PROFILE_STORAGE_HEADROOM")
					expect(f.prompts).to.equal(0)
					local r = f.receipt("already-issued")
					expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expect(f.data.Economy.Balance).to.equal(500000000)
					expect(f.mutations).to.equal(1)
					f.confirm()
					expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					expect(Service:GetRecoveryStatus(f.player.UserId).pendingCount).to.equal(0)
				end)
			end
		)
		it(
			"retains a full-profile unresolved receipt and recovers after canonical storage room is restored without eviction",
			function()
				run(function(f)
					f.data.Padding = string.rep("x", Capacity.EntryLimitBytes)
					local r = f.receipt("full-then-room")
					expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					expect(f.mutations).to.equal(0)
					expect(Service:GetRecoveryStatus(f.player.UserId).reason).to.equal("PROFILE_STORAGE_HEADROOM")
					f.data.Padding = nil -- Synthetic canonical maintenance, never automatic ledger eviction.
					Service:RecoverPending(f.player)
					expect(f.mutations).to.equal(1)
					f.confirm()
					for _ = 1, 3 do
						expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					end
					expect(f.data.Economy.Balance).to.equal(500000000)
					expect(f.data.Commerce.ProcessedReceipts[r.PurchaseId].ProductId).to.equal(101)
				end)
			end
		)
		it(
			"fails closed at the platform maximum valid encoded value without acknowledging or erasing a receipt",
			function()
				local envelope = { Transport = { Version = 3 }, Data = { padding = "" } }
				local overhead = #Http:JSONEncode(envelope)
				envelope.Data.padding = string.rep("x", Capacity.EntryLimitBytes - overhead)
				expect(#Http:JSONEncode(envelope)).to.equal(Capacity.EntryLimitBytes)
				expect(Capacity.MeasureEnvelope(envelope, 0).ok).to.equal(false)
			end
		)
		it("bounds the transient recovery queue while unresolved excess receipts stay unacknowledged", function()
			run(function(f)
				f.busy = true
				for i = 1, 33 do
					expect(Service:ProcessReceipt(f.receipt("busy-" .. i))).to.equal(
						Enum.ProductPurchaseDecision.NotProcessedYet
					)
				end
				local status = Service:GetRecoveryStatus(f.player.UserId)
				expect(status.pendingCount).to.equal(32)
				expect(status.untrackedPlatformRetries).to.equal(true)
				expect(status.reason).to.equal("RECOVERY_QUEUE_FULL")
				expect(f.data.Commerce.ReceiptCount).to.equal(0)
				expect(f.mutations).to.equal(0)
			end)
		end)
		it("keeps global readiness blocked even with verified synthetic products and ample prompt room", function()
			run(function(f)
				f.catalogue.PaidCapacityRecoveryReady = false
				Service:RefreshPrices()
				expect(Service:GetCatalogue(f.player).readiness).to.equal("Blocked")
				expect(Service:Prompt(f.player, f.row.id).code).to.equal("PAID_CAPACITY_RECOVERY_BLOCKED")
				expect(f.prompts).to.equal(0)
			end)
		end)
		it("fails closed when the exact acquired envelope cannot be measured", function()
			run(function(f)
				f.noEnvelope = true
				expect(Service:ProcessReceipt(f.receipt("missing-envelope"))).to.equal(
					Enum.ProductPurchaseDecision.NotProcessedYet
				)
				expect(f.mutations).to.equal(0)
				expect(Service:GetRecoveryStatus(f.player.UserId).reason).to.equal("ENVELOPE_MEASUREMENT_UNAVAILABLE")
			end)
		end)
		it("captures receipt revision after income cutover rather than acknowledging an earlier save", function()
			run(function(f)
				f.cutoverRevision = true
				local r = f.receipt("income-settled-first")
				Service:ProcessReceipt(r)
				expect(f.revision).to.equal(2)
				expect(f.data.Commerce.ProcessedReceipts[r.PurchaseId].CommitRevision).to.equal(2)
				f.saved = 1
				expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
				f.confirm()
				expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
			end)
		end)
		it(
			"queues out-of-order receipts through a rebirth boundary then conserves the post-sacrifice paid cash",
			function()
				run(function(f)
					f.data.Economy.Balance = 250000000
					f.busy = true
					local a, b = f.receipt("later-b"), f.receipt("earlier-a")
					Service:ProcessReceipt(a)
					Service:ProcessReceipt(b)
					expect(f.mutations).to.equal(0)
					f.data.Economy.Balance = 0
					f.data.Phase13.EligibilityRevision += 1
					f.busy = false
					Service:RecoverPending(f.player)
					f.confirm()
					Service:RecoverPending(f.player)
					f.confirm()
					for _, receipt in { a, b } do
						expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					end
					expect(f.mutations).to.equal(2)
					expect(f.data.Economy.Balance).to.equal(1000000000)
				end)
			end
		)
		it(
			"acknowledges a canonical saved receipt after uncertain response and replacement-player reacquisition without another mutation",
			function()
				run(function(f)
					local r = f.receipt("lost-response")
					Service:ProcessReceipt(r)
					local canonical = Capacity.Copy(f.data) -- Backend persisted, response lost.
					expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
					f.player = { UserId = f.player.UserId }
					f.data = canonical
					f.saved = f.revision
					Service:RecoverPending(f.player)
					expect(Service:ProcessReceipt(r)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
					expect(f.mutations).to.equal(1)
					expect(f.data.Economy.Balance).to.equal(500000000)
				end)
			end
		)
		for _, persisted in { false, true } do
			it(
				"recovers "
					.. (if persisted then "persisted lost-response" else "definite prewrite-failed")
					.. " paid delivery through actual PDS/Transport3 reacquisition",
				function()
					local Players = game:GetService("Players")
					local Profile = require(script.Parent.Parent.Services.PlayerDataService)
					local Transactions = require(script.Parent.Parent.Services.Phase13Service)
					Transactions:_ResetForTests()
					Profile:_ResetForTests()
					local t = 1000
					local storeData = { value = nil, failSave = false }
					function storeData:UpdateAsync(_, transform)
						local proposed = transform(Capacity.Copy(self.value))
						if self.failSave and proposed.Transport.LastOperationId:match("^save:") then
							if persisted then
								self.value = Capacity.Copy(proposed)
							end
							error("synthetic response uncertainty")
						end
						self.value = Capacity.Copy(proposed)
						return Capacity.Copy(self.value)
					end
					local store = Store.new({
						DataStore = storeData,
						Available = true,
						UnixNow = function()
							return t
						end,
					})
					Profile:Init({
						Backend = store,
						UnixNow = function()
							return t
						end,
						MonotonicNow = function()
							return t
						end,
						Wait = function(seconds)
							t += math.max(seconds, 0.001)
						end,
						Random = function()
							return 0
						end,
						KickOnFailure = false,
					})
					local function actor()
						local player =
							{ UserId = 831329, Name = "SyntheticPaidRecovery", Parent = Players, Attributes = {} }
						function player:SetAttribute(key, value)
							self.Attributes[key] = value
						end
						return player
					end
					local old, replacement = actor(), actor()
					local currentPlayer = old
					local completedAttempts = {}
					Profile:SubscribeDiagnostics(function(_, receipt)
						if receipt.kind == "SaveAttemptCompleted" then
							table.insert(completedAttempts, receipt)
						end
					end)
					local income = {}
					function income:BeginCriticalCutover()
						return {}
					end
					function income:EndCriticalCutover()
						return true
					end
					local ok, why = xpcall(function()
						expect(Profile:LoadPlayerAsync(old).ok).to.equal(true)
						expect(Profile:GetSaveEnvelope(old, Profile:GetReadableData(old), 1).Transport.Version).to.equal(
							3
						)
						Transactions:Start({
							Profile = Profile,
							Income = income,
							Now = function()
								return t
							end,
						})
						Service:_ConfigureForTests({
							Profile = Profile,
							Transactions = Transactions,
							Marketplace = {},
							UniverseId = 999,
							Catalogue = {
								UniverseId = 999,
								Version = "FIXTURE",
								Passes = {},
								Products = {
									{
										id = "FIXTURE_POUCH",
										platformId = 101,
										verifiedUniverseId = 999,
										amount = 500000000,
									},
								},
							},
							ResolvePlayer = function()
								return currentPlayer
							end,
							Telemetry = { Record = function() end, Funnel = function() end },
						})
						local receipt = { PlayerId = old.UserId, ProductId = 101, PurchaseId = "actual-pds-recovery" }
						storeData.failSave = true
						expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
						expect(#completedAttempts).to.equal(5)
						local seenAttempts = {}
						for index, attempt in completedAttempts do
							expect(attempt.attemptSequence).to.equal(index)
							expect(attempt.uncertain).to.equal(true)
							expect(attempt.ok).to.equal(false)
							expect(seenAttempts[attempt.eventId]).to.equal(nil)
							seenAttempts[attempt.eventId] = true
						end
						expect(Profile:HasCriticalOperation(old)).to.equal(true)
						expect(Profile:GetReadableData(old).Economy.Balance).to.equal(500000000)
						old.Parent = nil
						expect(Profile:ClosePlayerAsync(old, "PlayerRemoving").code).to.equal("CRITICAL_CLOSE_PENDING")
						t = 2000
						Profile:Step()
						expect(Profile:GetStatus(old)).to.equal("Failed")
						storeData.failSave = false
						currentPlayer = replacement
						expect(Profile:LoadPlayerAsync(replacement).ok).to.equal(true)
						Service:RecoverPending(replacement)
						expect(Service:ProcessReceipt(receipt)).to.equal(Enum.ProductPurchaseDecision.PurchaseGranted)
						expect(Profile:GetReadableData(replacement).Economy.Balance).to.equal(500000000)
						expect(Profile:GetReadableData(replacement).Commerce.ReceiptCount).to.equal(1)
						expect(storeData.value.Transport.Version).to.equal(3)
						expect(storeData.value.Data.Economy.Balance).to.equal(500000000)
						expect(storeData.value.Data.Commerce.ProcessedReceipts[receipt.PurchaseId].Amount).to.equal(
							500000000
						)
					end, debug.traceback)
					Service:_ResetFixture()
					Transactions:_ResetForTests()
					Profile:_ResetForTests()
					assert(ok, why)
				end
			)
		end
		it(
			"compacts only acknowledged confirmed paid balance diagnostics while every paid identity and reward remains",
			function()
				local data = Schema.CreateDefault()
				Rules.GrantReceipt(data, "paid-one", 101, 500000000, 1000, "FIXTURE")
				PhaseRules.AppendOperation(
					data,
					"paid:paid-one",
					"PaidCash",
					4,
					1000,
					{ productId = 101, amount = 500000000, balance = 500000000 }
				)
				PhaseRules.AppendOperation(
					data,
					"pending-other",
					"PaidCash",
					5,
					1000,
					{ amount = 1, balance = 500000001 }
				)
				expect(Rules.CompactPaidDiagnostics(data, 3)).to.equal(0)
				expect(Rules.CompactPaidDiagnostics(data, 4)).to.equal(1)
				expect(data.Phase13.Operations["paid:paid-one"].Result.balance).to.equal(nil)
				expect(data.Phase13.Operations["pending-other"].Result.balance).to.equal(500000001)
				expect(data.Commerce.ProcessedReceipts["paid-one"].Amount).to.equal(500000000)
				expect(data.Economy.Balance).to.equal(500000000)
				expect(PhaseRules.Validate(data)).to.equal(true)
			end
		)
		it(
			"reserves ledger entries for delayed receipts and never treats the bounded retry cache as deduplication",
			function()
				local data = Schema.CreateDefault()
				data.Commerce.ReceiptCount = Capacity.ReceiptLimit - Capacity.PromptReceiptReserve
				expect(Capacity.CheckLedger(data, true).ok).to.equal(true)
				data.Commerce.ReceiptCount += 1
				expect(Capacity.CheckLedger(data, true).ok).to.equal(false)
				expect(Capacity.CheckLedger(data, false).ok).to.equal(true)
				data.Commerce.ReceiptCount = Capacity.ReceiptLimit
				expect(Capacity.CheckLedger(data, false).code).to.equal("PAID_LEDGER_FULL")
			end
		)
	end)
end
