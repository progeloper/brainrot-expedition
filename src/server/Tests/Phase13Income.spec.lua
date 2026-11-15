--!nocheck
return function()
	local Players = game:GetService("Players")
	local Income = require(script.Parent.Parent.Systems.BrainrotIncomeSystem)
	local Storage = require(script.Parent.Parent.Classes.BaseStorage)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local function run(callback, options)
		local opts = options or {}
		local mutationId = opts.MutationId or "Shiny"
		Income:Stop()
		local now = opts.InitialTime or 0
		local data = Schema.CreateDefault()
		local player = { Name = "Phase13IncomeSynthetic", UserId = 831305, Parent = Players }
		local base = Instance.new("Model")
		base:SetAttribute("BaseId", "Phase13IncomeSynthetic")
		base.Parent = workspace
		local slots = {}
		for i = 1, 48 do
			local part = Instance.new("Part")
			part.Name = "Slot_" .. i
			part.Parent = base
			local marker = Instance.new("Attachment")
			marker.Parent = part
			slots[i] = { Index = i, Platform = part, Marker = marker }
		end
		data.Collection.BrainrotInstances.earner =
			{ speciesId = "BRT_001", mutationId = mutationId, firstBankCompleted = true }
		data.Base.Slots["1"] = { brainrotId = "earner", accumulatedCash = opts.InitialCash or 7.25 }
		local storage = Storage.new(base, player.UserId, slots, data)
		assert(storage:BindRestoredRecord(1, {
			ItemId = "earner",
			BrainrotId = "BRT_001",
			MutationId = mutationId,
			Metadata = { MutationId = mutationId },
		}, nil))
		local stores = {}
		function stores:GetStorageForPlayer(p)
			return if p == player then storage else nil
		end
		function stores:ObserveStorage()
			return function() end
		end
		local bases = {}
		function bases:GetBase(p)
			return if p == player then base else nil
		end
		function bases:IsOwner(p, b)
			return p == player and b == base
		end
		local profile = { Dirty = 0 }
		function profile:GetReadableData(p)
			return if p == player then data else nil
		end
		function profile:MarkDirty()
			self.Dirty += 1
			return self.Dirty
		end
		function profile:GetSessionHandle()
			return { Generation = 1 }
		end
		function profile:SubscribeCloseRequested(observer)
			self.CloseRequested = observer
			return { Disconnect = function() end }
		end
		local wallet = { Credits = 0 }
		function wallet:IsReady(p)
			return p == player and p.Parent == Players
		end
		function wallet:TryCreditWithSource(_, amount, _reason, consume)
			local ok, why = consume()
			if not ok then
				return { ok = false, code = why, committed = false }
			end
			data.Economy.Balance += amount
			self.Credits += 1
			return { ok = true, committed = true }
		end
		function wallet:SyncBalance()
			return true
		end
		local telemetry = { Events = {}, Sources = {}, Funnels = {} }
		function telemetry:Record(_, name, value, fields)
			table.insert(self.Events, { name = name, value = value, fields = fields })
			return true
		end
		function telemetry:Economy(_, flow, amount, balance, category, sku)
			table.insert(
				self.Sources,
				{ flow = flow, amount = amount, balance = balance, category = category, sku = sku }
			)
			return true
		end
		function telemetry:Funnel(_, name, step)
			table.insert(self.Funnels, { name, step })
			return true
		end
		assert(Income:Start({
			Storage = stores,
			Base = bases,
			Profile = profile,
			Wallet = wallet,
			Analytics = telemetry,
			Now = function()
				return now
			end,
			ConnectScheduler = false,
		}))
		Income:TrackPlayer(player)
		Income:BindStorage(player, storage)
		local ok, why = xpcall(function()
			callback({
				Player = player,
				Data = data,
				Storage = storage,
				Wallet = wallet,
				Telemetry = telemetry,
				Profile = profile,
				BaseId = storage.BaseId,
				Time = function(t)
					now = t
				end,
			})
		end, debug.traceback)
		Income:Stop()
		storage:Destroy()
		base:Destroy()
		assert(ok, why)
	end
	describe("Phase13 canonical production and collection", function()
		it("earns exactly18M or36M from ten starter seconds and credits a repeated collection zero", function()
			for _, pass in { false, true } do
				run(function(f)
					f.Data.Commerce.Entitlements.INCOME_2X = pass
					f.Time(10)
					Income:Step()
					local expected = if pass then 36000000 else 18000000
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(expected)
					expect(f.Data.Economy.Balance).to.equal(0)
					expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).paid).to.equal(expected)
					expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).code).to.equal("NothingToCollect")
					expect(f.Data.Economy.Balance).to.equal(expected)
					expect(f.Wallet.Credits).to.equal(1)
				end, { MutationId = "None", InitialCash = 0 })
			end
		end)
		it("settles mutation once and pass old/new rates at an explicit covering-save boundary", function()
			run(function(f)
				f.Time(2)
				expect(Income:Step()).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(5400007.25)
				f.Time(3)
				local token = assert(Income:BeginCriticalCutover(f.Player, 3))
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(8100007.25)
				f.Data.Commerce.Entitlements.INCOME_2X = true
				f.Time(8)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(8100007.25)
				expect(Income:EndCriticalCutover(f.Player, token, 8)).to.equal(true)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(35100007.25)
				expect(Income:GetPlatformIncomeSnapshot(f.BaseId, 1).RatePerSecond).to.equal(5400000)
				Income:Step()
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(35100007.25)
			end)
		end)
		it(
			"caps queued critical earnings at the first departure timestamp and starts a new session at its own clock",
			function()
				local saved
				run(function(f)
					f.Time(3)
					local token = assert(Income:BeginCriticalCutover(f.Player, 3), "Income cutover unavailable")
					f.Data.Commerce.Entitlements.INCOME_2X = true
					f.Time(4)
					f.Profile.CloseRequested(f.Player, "PlayerRemoving")
					f.Player.Parent = nil
					f.Time(12)
					expect(Income:EndCriticalCutover(f.Player, token, 12)).to.equal(true)
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(13500007.25)
					f.Time(20)
					Income:Step()
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(13500007.25)
					saved = f.Storage:GetUnclaimedCashExact(1)
				end)
				run(function(f)
					f.Data.Commerce.Entitlements.INCOME_2X = true
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(saved)
					f.Time(35)
					Income:Step()
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(saved + 27000000)
				end, { InitialCash = saved, InitialTime = 30 })
			end
		)
		it("conserves wallet plus ledgers when automatic and manual collection share one boundary", function()
			run(function(f)
				f.Data.Commerce.Entitlements.AUTO_COLLECT = true
				f.Time(1)
				Income:Step()
				expect(f.Data.Economy.Balance).to.equal(2700007.25)
				expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(0)
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).code).to.equal("NothingToCollect")
				expect(f.Wallet.Credits).to.equal(1)
				f.Time(2)
				Income:Step()
				expect(f.Data.Economy.Balance).to.equal(5400007.25)
				expect(f.Wallet.Credits).to.equal(2)
			end)
		end)
		it("withholds collection for a PendingBank individual without dropping its accrued money", function()
			run(function(f)
				local old = Banked.IsBankPending
				Banked.IsBankPending = function(_, p, id)
					return p == f.Player and id == "earner"
				end
				local ok, why = xpcall(function()
					f.Time(1)
					Income:Step()
					expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).code).to.equal("Saving")
					expect(f.Storage:GetUnclaimedCashExact(1)).to.equal(2700007.25)
					expect(f.Data.Economy.Balance).to.equal(0)
				end, debug.traceback)
				Banked.IsBankPending = old
				assert(ok, why)
				expect(Income:TryClaimPlatform(f.Player, f.BaseId, 1).paid).to.equal(2700007.25)
			end)
		end)
		it("aggregates production once per60 seconds and treats collection as an internal transfer", function()
			run(function(f)
				f.Time(1)
				Income:Step()
				expect(#f.Telemetry.Sources).to.equal(0)
				Income:TryClaimPlatform(f.Player, f.BaseId, 1)
				f.Time(61)
				Income:Step()
				expect(#f.Telemetry.Sources).to.equal(1)
				expect(f.Telemetry.Sources[1].amount).to.equal(164700000)
				expect(f.Telemetry.Sources[1].balance).to.equal(164700007.25)
				expect(f.Telemetry.Sources[1].sku).to.equal("PLATFORM_PRODUCTION")
				expect(#f.Telemetry.Events).to.equal(2)
				expect(f.Telemetry.Events[2].name).to.equal("CollectionSummary")
				expect(f.Telemetry.Events[2].value).to.equal(2700007.25)
			end)
		end)
	end)
end
