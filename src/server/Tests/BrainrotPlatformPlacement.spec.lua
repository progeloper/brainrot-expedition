--!nocheck
-- Isolated geometry/authority fixtures, not a live client walking/Play test.
-- Fake Player/base assignment only; real shot, world/carry/storage, visual factory,
-- configured catalogue rates, currency and actual Heartbeat income processing.
return function()
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local Systems = script.Parent.Parent.Systems
	local Base = require(Systems.PlayerBaseSystem)
	local Storage = require(Systems.BaseStorageSystem)
	local Interaction = require(Systems.BrainrotInteractionSystem)
	local World = require(Systems.DevelopmentBrainrotSpawner)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Sleep = require(Systems.BrainrotSleepSystem)

	-- Camera-ray intent adapter for existing lifecycle fixtures, not gameplay input.
	local function fireAt(player, point)
		local origin = player.Character.HumanoidRootPart.Position
		local offset = point - origin
		return Sleep.HandleFireRequest(player, {
			CameraOrigin = origin,
			CameraDirection = if offset.Magnitude > 0.001 then offset.Unit else -Vector3.zAxis,
		})
	end
	local Income = require(Systems.BrainrotIncomeSystem)
	local Currency = require(Systems.CurrencySystem)
	local Return = require(Systems.BaseReturnSystem)
	local Roaming = require(Systems.DevelopmentBrainrotRoaming)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local Carts = require(script.Parent.Parent.Services.CartService)
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)
	local ProfileSchema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local sequence = -34000

	local function fixture(test)
		Placement.ResetQueryBudgetForTesting()
		assert(Interaction.Stop())
		assert(Income:Destroy())
		Return:Destroy()
		Storage:Destroy()
		local restores, owned, ids = {}, {}, {}
		local function own(instance)
			table.insert(owned, instance)
			return instance
		end
		local function replace(object, key, value)
			local old = object[key]
			table.insert(restores, function()
				object[key] = old
			end)
			object[key] = value
		end
		local function folder(parent, name)
			local found = parent:FindFirstChild(name)
			if found then
				return found
			end
			local v = own(Instance.new("Folder"))
			v.Name, v.Parent = name, parent
			return v
		end
		local root = own(Instance.new("Folder"))
		root.Name, root.Parent = "SPEC_PLATFORM_PLACEMENT", workspace
		local origin = Vector3.new(20000, 103, 20000)
		local function part(parent, name, position, size)
			local p = Instance.new("Part")
			p.Name, p.Position, p.Size, p.Anchored, p.Parent =
				name, position, size or Vector3.new(2, 2, 2), true, parent
			return p
		end
		part(root, "Ground", origin - Vector3.new(0, 4, 0), Vector3.new(600, 2, 600)):SetAttribute(
			"CartDrivableGround",
			true
		)
		local templates = folder(folder(RS, "StudioAssets"), "Brainrots")
		for _, speciesId in { "BRT_007", "BRT_011", "BRT_015", "BRT_016" } do
			if not templates:FindFirstChild(speciesId) then
				local t = own(Instance.new("Model"))
				t.Name = speciesId
				local body = part(t, "Body", Vector3.zero, Vector3.new(2, 5, 2))
				local capture = Instance.new("Attachment")
				capture.Name, capture.Parent = "CaptureAttachment", body
				local cargo = Instance.new("Attachment")
				cargo.Name, cargo.Parent = "CargoAttachment", body
				t.PrimaryPart, t.Parent = body, templates
			end
		end
		local homes, bases = {}, {}
		local function base(n)
			local b = Instance.new("Model")
			b.Name, b.Parent = "SpecBase" .. n, root
			b:SetAttribute("BaseId", b.Name)
			for i = 1, 48 do
				local p =
					part(b, "Slot_" .. i, origin + Vector3.new((i - 1) * 14, -2.5, 50 + n * 40), Vector3.new(10, 1, 10))
				p:SetAttribute("SlotIndex", i)
				local a = Instance.new("Attachment")
				a.Name, a.Position, a.Parent = "BrainrotPlacement", Vector3.new(0, 0.5, 0), p
			end
			part(b, "DecorativeSlab", origin + Vector3.new(0, -2, 75), Vector3.new(10, 1, 10))
			table.insert(bases, b)
			return b
		end
		local function player(b)
			sequence -= 1
			local c = Instance.new("Model")
			c.Name, c.Parent = "Character", root
			local hrp = part(c, "HumanoidRootPart", origin + Vector3.new(0, 0, 5))
			part(c, "Head", hrp.Position + Vector3.new(0, 1.5, 0))
			local h = Instance.new("Humanoid")
			h.RequiresNeck, h.Parent = false, c
			c.PrimaryPart = hrp
			local removing = own(Instance.new("BindableEvent"))
			local attrs = {}
			local p = {
				Name = "PlacementSpec",
				UserId = sequence,
				Parent = Players,
				CameraMaxZoomDistance = 128,
				Character = c,
				CharacterRemoving = removing.Event,
			}
			function p:GetAttribute(k)
				return attrs[k]
			end
			function p:SetAttribute(k, v)
				attrs[k] = v
			end
			homes[p] = b
			return p
		end
		local p, other = player(base(1)), player(base(2))
		local walletOwner = {
			Revision = 0,
			Data = { [p] = ProfileSchema.CreateDefault(), [other] = ProfileSchema.CreateDefault() },
		}
		function walletOwner:IsWritable(subject)
			return self.Data[subject] ~= nil and subject.Parent == Players
		end
		function walletOwner:GetReadableData(subject)
			return self.Data[subject], if self.Data[subject] then nil else "PROFILE_NOT_READY"
		end
		function walletOwner:GetWritableData(subject)
			return self:GetReadableData(subject)
		end
		function walletOwner:MarkDirty(subject)
			if not self:IsWritable(subject) then
				return nil, "PROFILE_NOT_READY"
			end
			self.Revision += 1
			return self.Revision
		end
		function walletOwner:CommitMutation(subject, mutator)
			if not self:IsWritable(subject) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutator(self.Data[subject])
			if not committed then
				return result
			end
			self.Revision += 1
			result.ok, result.committed, result.revision = true, true, self.Revision
			return result
		end
		function walletOwner:GetDiagnostics()
			return { currentRevision = self.Revision }
		end
		function walletOwner:BeginClosing()
			return true
		end
		Currency:_ResetForTests(walletOwner)
		table.insert(restores, function()
			Currency:_ResetForTests()
		end)
		local assigned
		local assignmentHandles = {}
		assignmentHandles[p] = {
			Player = p,
			Base = homes[p],
			BaseId = homes[p]:GetAttribute("BaseId"),
			Generation = 1,
		}
		assignmentHandles[other] = {
			Player = other,
			Base = homes[other],
			BaseId = homes[other]:GetAttribute("BaseId"),
			Generation = 1,
		}
		replace(Base, "GetRegisteredBases", function()
			return bases
		end)
		replace(Base, "GetBase", function(_, who)
			return homes[who]
		end)
		replace(Base, "IsOwner", function(_, who, b)
			return homes[who] == b and who.Parent == Players
		end)
		replace(Base, "GetAssignment", function(_, who)
			return assignmentHandles[who]
		end)
		replace(Base, "IsCurrentAssignment", function(_, handle)
			return handle ~= nil and assignmentHandles[handle.Player] == handle and homes[handle.Player] == handle.Base
		end)
		replace(Base, "SubscribeAssignments", function(_, add)
			assigned = add
			return { Disconnect = function() end }
		end)
		local function spawn(awake, speciesId)
			local record = {
				ItemId = Http:GenerateGUID(false),
				BrainrotId = speciesId or "BRT_007",
				Metadata = { Tier = 3, Mutation = { Name = "Original", Quality = 7 } },
				World = {
					Name = "SPEC_PLACE",
					Scale = 1,
					SpawnPosition = { X = origin.X, Y = origin.Y, Z = origin.Z },
				},
			}
			ids[record.ItemId] = true
			local prepared = assert(World.PrepareWorldRepresentation(record, CFrame.new(origin)))
			local model = assert(World.ActivatePreparedWorld(prepared))
			if not awake then
				assert(World.TrySleep(model))
			end
			return model, World.GetWorldRecord(model)
		end
		local function near(platform)
			p.Character:PivotTo(CFrame.new(platform.Position + Vector3.new(0, 2.5, 6)))
		end
		local function carry(speciesId)
			p.Character:PivotTo(CFrame.new(origin + Vector3.new(0, 0, 5)))
			local m, r = spawn(nil, speciesId)
			assert(Interaction.TryPickupWorld(p, m, r.ItemId))
			return r
		end
		local function restoreSavedBase()
			-- Discard all runtime slot records, then restore an independent production
			-- serializer snapshot. In particular, no world-return envelope is saved.
			local snapshot = assert(ProfileSchema.CreateSaveSnapshot(walletOwner.Data[p]))
			Storage:Destroy()
			walletOwner.Data[p] = assert(ProfileSchema.Migrate(snapshot))
			Storage:Start({ Profile = walletOwner })
			assigned(p, homes[p])
			assigned(other, homes[other])
			return assert(Storage:GetStorageForPlayer(p)), snapshot
		end
        -- This legacy native transfer fixture uses an in-memory profile owner.
        -- Immediate synthetic covering saves are independent of the dedicated
        -- Phase13 delayed-save/population-conservation tests.
        local banked=require(script.Parent.Parent.Services.BankedBrainrotService)
        replace(World,"BeginPendingBank",function()return true end)
        replace(World,"ConfirmPendingBank",function()return true end)
        replace(banked,"RegisterPendingBank",function(_self,_player,_record,_revision,callback)
            callback() return {ok=true,state="Confirmed"}
        end)
		local setupRestoreCount = #restores
		local ok, failure = xpcall(function()
			Storage:Start({ Profile = walletOwner })
			assigned(p, homes[p])
			assigned(other, homes[other])
			Interaction.Start({
				World = World,
				CreateItemVisual = function(id)
					return Cargo:CreateItemVisual(id)
				end,
				IsDriving = function()
					return false
				end,
			})
			Sleep.SetCarryingPredicate(Interaction.IsCarrying)
			test({
				p = p,
				other = other,
				base = homes[p],
				otherBase = homes[other],
				storage = Storage:GetStorageForPlayer(p),
				near = near,
				carry = carry,
				spawn = spawn,
				replace = replace,
				root = root,
				origin = origin,
				part = part,
				homes = homes,
				restoreSavedBase = restoreSavedBase,
				profile = function()
					return walletOwner.Data[p]
				end,
			})
		end, debug.traceback)
		-- Restore injected faults before normal lifecycle cleanup.
		for i = #restores, setupRestoreCount + 1, -1 do
			restores[i]()
		end
		assert(Interaction.Stop())
		assert(Income:Destroy())
		Storage:Destroy()
		Sleep.SetCarryingPredicate(nil)
		-- Retire only fixture cargo before destroying its artificial ground/templates.
		for _, cart in root:GetDescendants() do
			if cart:IsA("Model") and cart:GetAttribute("RuntimeCart") == true then
				for _, record in Cargo:GetCargoSnapshot(cart) do
					local token = Cargo:DetachForTransfer(cart, record.ItemId)
					if token then
						Cargo:FinalizeTransfer(cart, token)
					end
				end
			end
		end
		for i = #restores, 1, -1 do
			restores[i]()
		end
		-- Retire this fixture's exact identities through the existing Studio seam.
		-- Unregister refuses a model still inside the world folder; destroying that
		-- model as an ordinary loss can queue recovery after its source is gone.
		for itemId in ids do
			Cargo:CancelPendingReturnForTesting(itemId)
			World.DestroyWorldForTesting(itemId)
		end
		for i = #owned, 1, -1 do
			owned[i]:Destroy()
		end
		assert(ok, failure)
	end

	local function seed(f, index)
		local r = {
			ItemId = Http:GenerateGUID(false),
			BrainrotId = "BRT_007",
			Metadata = {
				Existing = true,
			},
		}
		local token = assert(Storage:PrepareStoreAtPlatform(f.p, f.base["Slot_" .. index], r))
		assert(Storage:CommitPlatformPlacement(token))
		Storage:FinishPlatformPlacement(token)
		return r
	end

	describe("Manual carried-individual platform placement", function()

		it("retires an unbanked fixture identity and every queued return before removing its source", function()
			local itemId
			fixture(function(f)
				itemId = f.carry().ItemId
			end)
			expect(World.GetWorldModelById(itemId)).to.equal(nil)
			for _, pendingId in Cargo:GetRemovalDiagnostics().PendingIds do
				expect(pendingId == itemId).to.equal(false)
			end
			for _, member in World.GetPopulationSnapshot().Members do
				expect(member.RuntimeId == itemId).to.equal(false)
			end
		end)
		it(
			"picks up a serializer-restored banked individual through the real world factory without saving runtime return data",
			function()
				fixture(function(f)
					local original = f.carry("BRT_007")
					local platform = f.base.Slot_7
					f.near(platform)
					assert(Interaction.TryPlaceOnPlatform(f.p, platform, original.ItemId))
					assert(f.storage:SetUnclaimedCashExact(7, 80.25))
					local restored, saved = f.restoreSavedBase()
					local stored = assert(restored:GetPlatformRecord(7))
					expect(stored.World).to.equal(nil)
					expect(saved.Collection.BrainrotInstances[original.ItemId].World).to.equal(nil)
					local beforeWild = World.GetWildCount()
					local factory, staged = World.PrepareWorldRepresentation, nil
					f.replace(World, "PrepareWorldRepresentation", function(record, pose)
						local prepared, reason = factory(record, pose)
						staged = prepared
						return prepared, reason
					end)
					local pickedUp, reason = Interaction.TryPickupPlatform(f.p, platform, original.ItemId)
					assert(pickedUp, reason)
					local carried = assert(Interaction.GetCarriedRecord(f.p))
					expect(carried.ItemId).to.equal(original.ItemId)
					expect(carried.BrainrotId).to.equal(original.BrainrotId)
					expect(carried.Metadata.Mutation.Name).to.equal("Original")
					expect(carried.Metadata.Mutation.Quality).to.equal(7)
					expect(carried.Metadata.DurableOwnerUserId).to.equal(f.p.UserId)
					expect(carried.World.SpawnPosition.X).to.equal(platform.BrainrotPlacement.WorldPosition.X)
					expect(carried.World.SpawnRegionId).to.equal(nil)
					expect(carried.World.TerritoryRegionId).to.equal(nil)
					expect(carried.World.ReturnRegionId).to.equal(nil)
					expect(staged.Model.Parent).to.equal(nil)
					expect(World.GetWildCount()).to.equal(beforeWild)
					expect(restored:GetUnclaimedCashExact(7)).to.equal(80.25)
					expect(restored:GetPlatformRecord(7)).to.equal(nil)
					expect(f.profile().Collection.BrainrotInstances[original.ItemId].World).to.equal(nil)
					assert(Interaction.TryPlaceOnPlatform(f.p, platform, original.ItemId))
					expect(staged.Model.Parent).to.equal(nil)
					expect(World.ActivatePreparedWorld(staged)).to.equal(nil)
					expect(World.GetWildCount()).to.equal(beforeWild)
					local final = assert(ProfileSchema.CreateSaveSnapshot(f.profile()))
					expect(final.Base.Slots["7"].brainrotId).to.equal(original.ItemId)
					expect(final.Base.Slots["7"].accumulatedCash).to.equal(80.25)
					expect(final.Collection.BrainrotInstances[original.ItemId].World).to.equal(nil)
				end)
			end
		)

		it("banks a mixed four-species set without changing individual identity", function()
			fixture(function(f)
				local species = { "BRT_007", "BRT_011", "BRT_015", "BRT_016" }
				local ids, expectedRate = {}, 0
				for index, speciesId in species do
					local record = f.carry(speciesId)
					local platform = f.base["Slot_" .. index]
					f.near(platform)
					assert(Interaction.TryPlaceOnPlatform(f.p, platform, record.ItemId))
					local stored = assert(f.storage:GetPlatformRecord(index))
					expect(stored.ItemId).to.equal(record.ItemId)
					expect(stored.BrainrotId).to.equal(speciesId)
					expect(ids[stored.ItemId]).to.equal(nil)
					ids[stored.ItemId] = true
					expectedRate += assert(Catalog.GetCashPerSecond(speciesId))
					local display = assert(f.base.StoredBrainrots:FindFirstChild("Stored_" .. record.ItemId))
					expect(display:GetAttribute("ItemId")).to.equal(record.ItemId)
					expect(display:GetAttribute("BrainrotId")).to.equal(speciesId)
				end
				expect(#f.base.StoredBrainrots:GetChildren()).to.equal(4)
				expect(f.storage:GetOccupiedCount()).to.equal(4)

				local displaced = assert(f.storage:GetPlatformRecord(4))
				f.near(f.base.Slot_4)
				assert(Interaction.TryPickupPlatform(f.p, f.base.Slot_4, displaced.ItemId))
				assert(Interaction.TryDropCarried(f.p, displaced.ItemId))
				local released
				for _, model in World.GetWorldModels() do
					local worldRecord = World.GetWorldRecord(model)
					if worldRecord and worldRecord.ItemId == displaced.ItemId then
						released = model
					end
				end
				assert(released, "Dropped pilot individual must return to world")
				expect(World.GetWorldRecord(released).BrainrotId).to.equal("BRT_016")
				expect(select(2, World.GetWorldRecord(released))).to.equal("WorldSleeping")
				expect(World.TrySleep(released)).to.equal(false)
				f.p.Character:PivotTo(CFrame.new(released:GetPivot().Position + Vector3.new(0, 0, 5)))
				assert(Interaction.TryPickupWorld(f.p, released, displaced.ItemId))
				f.near(f.base.Slot_4)
				assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_4, displaced.ItemId))
				expect(f.storage:GetPlatformRecord(4).BrainrotId).to.equal("BRT_016")
				expect(f.storage:GetOccupiedCount()).to.equal(4)
				expect(expectedRate).to.equal(14300000)
			end)
		end)

		it("keeps restored ownership and platform cash unchanged when its exact source asset is missing", function()
			fixture(function(f)
				local original = f.carry("BRT_007")
				local platform = f.base.Slot_7
				f.near(platform)
				assert(Interaction.TryPlaceOnPlatform(f.p, platform, original.ItemId))
				assert(f.storage:SetUnclaimedCashExact(7, 80.25))
				local restored = f.restoreSavedBase()
				local template = RS.StudioAssets.Brainrots.BRT_007
				local parent = template.Parent
				local beforeWild, beforeRevision = World.GetWildCount(), restored:GetRevision()
				template.Parent = nil
				local ok, pickedUp, reason = pcall(Interaction.TryPickupPlatform, f.p, platform, original.ItemId)
				template.Parent = parent
				assert(ok, pickedUp)
				expect(pickedUp).to.equal(false)
				expect(reason).to.equal("PREPARATION_FAILED")
				expect(Interaction.GetCarriedRecord(f.p)).to.equal(nil)
				expect(restored:GetPlatformRecord(7).ItemId).to.equal(original.ItemId)
				expect(restored:GetUnclaimedCashExact(7)).to.equal(80.25)
				expect(restored:GetRevision()).to.equal(beforeRevision)
				expect(World.GetWildCount()).to.equal(beforeWild)
				local saved = assert(ProfileSchema.CreateSaveSnapshot(f.profile()))
				expect(saved.Collection.BrainrotInstances[original.ItemId].speciesId).to.equal("BRT_007")
				expect(saved.Collection.BrainrotInstances[original.ItemId].World).to.equal(nil)
				expect(saved.Base.Slots["7"].brainrotId).to.equal(original.ItemId)
				expect(saved.Base.Slots["7"].accumulatedCash).to.equal(80.25)
			end)
		end)

		local function replacementCart(f)
			local cart = Instance.new("Model")
			cart.Name, cart.Parent = "ReplacementRoute", f.root
			cart:SetAttribute("CartId", "CRT_001")
			cart:SetAttribute("RuntimeCart", true)
			cart:SetAttribute("OwnerUserId", f.p.UserId)
			cart.PrimaryPart = f.part(cart, "Root", f.origin + Vector3.new(30, -2, 0), Vector3.new(6, 1, 10))
			local slots = Instance.new("Folder")
			slots.Name, slots.Parent = "CargoSlots", cart
			for i = 1, 3 do
				local slot = f.part(slots, "Slot" .. i, f.origin + Vector3.new(28 + i * 2, 0, 3.5), Vector3.one)
				slot.CanCollide = false
				local a = Instance.new("Attachment")
				a.Name, a.Parent = "CargoAttachment", slot
			end
			local record = { Model = cart, OwnerUserId = f.p.UserId }
			f.replace(Carts, "GetCart", function(_, who)
				return if who == f.p then cart else nil
			end)
			f.replace(Carts, "GetCartRecordByOwnerUserId", function(_, id)
				return if id == f.p.UserId then record else nil
			end)
			return cart, slots
		end

		it(
			"preserves a restored individual's runtime return record through carry cargo removal and re-banking",
			function()
				fixture(function(f)
					local original = f.carry("BRT_007")
					local platform = f.base.Slot_7
					f.near(platform)
					assert(Interaction.TryPlaceOnPlatform(f.p, platform, original.ItemId))
					assert(f.storage:SetUnclaimedCashExact(7, 80.25))
					local restored = f.restoreSavedBase()
					local cart, slots = replacementCart(f)
					local beforeWild = World.GetWildCount()
					assert(Interaction.TryPickupPlatform(f.p, platform, original.ItemId))
					local runtime = assert(Interaction.GetCarriedRecord(f.p)).World
					f.near(slots.Slot2)
					assert(Interaction.TryPlaceInCargo(f.p, cart, "Slot2", original.ItemId))
					local cargo = assert(Cargo:GetSlotRecord(cart, "Slot2"))
					expect(cargo.ItemId).to.equal(original.ItemId)
					expect(cargo.World.Name).to.equal(runtime.Name)
					expect(cargo.Metadata.Mutation.Quality).to.equal(7)
					expect(World.GetWildCount()).to.equal(beforeWild)
					assert(Interaction.TryPickupCargo(f.p, cart, "Slot2", original.ItemId))
					expect(Cargo:GetCargoCount(cart)).to.equal(0)
					local carried = assert(Interaction.GetCarriedRecord(f.p))
					expect(carried.ItemId).to.equal(original.ItemId)
					expect(carried.World.Name).to.equal(runtime.Name)
					f.near(platform)
					assert(Interaction.TryPlaceOnPlatform(f.p, platform, original.ItemId))
					expect(restored:GetPlatformRecord(7).ItemId).to.equal(original.ItemId)
					expect(restored:GetUnclaimedCashExact(7)).to.equal(80.25)
					expect(World.GetWildCount()).to.equal(beforeWild)
					local saved = assert(ProfileSchema.CreateSaveSnapshot(f.profile()))
					expect(saved.Collection.BrainrotInstances[original.ItemId].World).to.equal(nil)
					expect(saved.Base.Slots["7"].brainrotId).to.equal(original.ItemId)
				end)
			end
		)

		it("picks up a deposited individual and retains platform cash", function()
			fixture(function(f)
				local record = f.carry()
				local platform = f.base.Slot_7
				f.near(platform)
				assert(Interaction.TryPlaceOnPlatform(f.p, platform, record.ItemId))
				assert(f.storage:SetUnclaimedCashExact(7, 80))
				local oldDisplay = f.base.StoredBrainrots["Stored_" .. record.ItemId]
				expect(oldDisplay ~= nil).to.equal(true)

				local pickedUp, reason = Interaction.TryPickupPlatform(f.p, platform, record.ItemId)
				assert(pickedUp, reason)
				expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(record.ItemId)
				expect(f.storage:GetPlatformRecord(7)).to.equal(nil)
				expect(f.storage:GetUnclaimedCashExact(7)).to.equal(80)
				expect(oldDisplay.Parent).to.equal(nil)

				f.near(platform)
				assert(Interaction.TryPlaceOnPlatform(f.p, platform, record.ItemId))
				expect(f.storage:GetPlatformRecord(7).ItemId).to.equal(record.ItemId)
				expect(f.storage:GetUnclaimedCashExact(7)).to.equal(80)
			end)
		end)

		it(
			"replaces A with same-species B, releases/roams/recaptures A and earns only after manually banking A",
			function()
				fixture(function(f)
					local cart, slots = replacementCart(f)
					-- Actual world/shot/carry/cargo/base/income services; fake Player/registry only.
					f.other.Character:PivotTo(CFrame.new(f.origin + Vector3.new(100, 0, -100)))
					Income:Start()
					Income:TrackPlayer(f.p)
					assert(Income:BindStorage(f.p, f.storage))
					local a = f.carry()
					f.near(slots.Slot2)
					assert(Interaction.TryPlaceInCargo(f.p, cart, "Slot2", a.ItemId))
					for _, slotId in { "Slot1", "Slot3" } do
						local filler = f.carry()
						f.near(slots[slotId])
						assert(Interaction.TryPlaceInCargo(f.p, cart, slotId, filler.ItemId))
					end
					local b = f.carry()
					f.near(slots.Slot2)
					Roaming.Start()
					local registered = Roaming.GetDiagnostics().Registered
					local cash = Currency:GetBalance(f.p)
					local ok, reason = Interaction.TryReplaceCargo(f.p, cart, "Slot2", a.ItemId, b.ItemId)
					assert(ok, reason)
					local released
					for _, m in World.GetWorldModels() do
						if World.GetWorldRecord(m).ItemId == a.ItemId then
							released = m
						end
					end
					assert(released, "Replacement must publish the displaced individual")
					expect(Roaming.GetDiagnostics().Registered).to.equal(registered + 1)
					expect(select(2, World.GetWorldRecord(released))).to.equal("WorldAwake")
					expect(released.Body.CanQuery).to.equal(true)
					f.p.Character:PivotTo(CFrame.new(released.Body.Position + Vector3.new(0, 0, 5)))
					expect(Interaction.TryPickupWorld(f.p, released, a.ItemId)).to.equal(false)
					local initial = released:GetPivot().Position
					local moved = false
					for _ = 1, 60 do
						task.wait(0.1)
						if (released:GetPivot().Position - initial).Magnitude > 0.2 then
							moved = true
							break
						end
					end
					expect(moved).to.equal(true)
					expect(Currency:GetBalance(f.p)).to.equal(cash)
					expect(Income:GetIncomeRate(f.p)).to.equal(0)
					-- Approach the canonical torso from the cart's outward side. Five
					-- studs can begin inside a large/rotated body in a geometry fixture.
					local outward = Vector3.new(
						released.Body.Position.X - cart:GetPivot().X,
						0,
						released.Body.Position.Z - cart:GetPivot().Z
					)
					outward = if outward.Magnitude > 0.001 then outward.Unit else Vector3.zAxis
					local viewDistance = math.max(10, released.Body.Size.Magnitude * 0.5 + 3)
					f.p.Character:PivotTo(CFrame.new(released.Body.Position + outward * viewDistance))
					local tool = Instance.new("Tool")
					tool.Name, tool.RequiresHandle = "SleepLauncher", false
					tool:SetAttribute("BrainrotSleepLauncher", true)
					local handle = f.part(tool, "Handle", f.p.Character.PrimaryPart.Position)
					local muzzle = Instance.new("Attachment")
					muzzle.Name, muzzle.Parent = "Muzzle", handle
					tool.Parent = f.p.Character
					local params = RaycastParams.new()
					params.FilterType, params.FilterDescendantsInstances =
						Enum.RaycastFilterType.Exclude, { f.p.Character }
					local muzzleOrigin = f.p.Character.PrimaryPart.Position
					local debugHit = workspace:Raycast(muzzleOrigin, released.Body.Position - muzzleOrigin, params)
					print(
						"[PHASE10_RECAPTURE_RAY] first="
							.. (if debugHit then debugHit.Instance:GetFullName() else "none")
							.. " target="
							.. released.Body:GetFullName()
					)
					local priorTrace = RS:GetAttribute("HuntingAimTrace")
					RS:SetAttribute("HuntingAimTrace", true)
					local shot, shotReason = fireAt(f.p, released.Body.Position)
					RS:SetAttribute("HuntingAimTrace", priorTrace)
					assert(shot, shotReason)
					expect(select(2, World.GetWorldRecord(released))).to.equal("WorldSleeping")
					f.p.Character:PivotTo(CFrame.new(released.Body.Position + outward * 5))
					assert(Interaction.TryPickupWorld(f.p, released, a.ItemId))
					expect(Interaction.GetCarriedRecord(f.p).Metadata.Mutation.Quality).to.equal(7)
					expect(Income:GetIncomeRate(f.p)).to.equal(0)
					f.near(f.base.Slot_7)
					Return:Step()
					expect(Cargo:GetSlotRecord(cart, "Slot2").ItemId).to.equal(b.ItemId)
					expect(f.storage:GetRevision()).to.equal(0)
					assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_7, a.ItemId))
					expect(f.storage:GetPlatformRecord(7).ItemId).to.equal(a.ItemId)
					expect(Income:GetIncomeRate(f.p)).to.equal(Catalog.GetCashPerSecond("BRT_007"))
					expect(Cargo:GetSlotRecord(cart, "Slot2").ItemId).to.equal(b.ItemId)
					expect(Cargo:GetCargoCount(cart)).to.equal(3)
					expect(Cargo:GetCargoRevision(cart)).to.equal(4)
					print("[PHASE10_ID] replacement-recapture-bank A=" .. a.ItemId .. " cargo-B=" .. b.ItemId)
					task.wait(1.2)
					expect(Currency:GetBalance(f.p)).to.equal(cash)
					expect(f.storage:GetUnclaimedCashExact(7) > 0).to.equal(true)
				end)
			end
		)

		it("allows only one mutation when two permitted-player fixture requests overlap", function()
			fixture(function(f)
				local cart, slots = replacementCart(f)
				local a = f.carry()
				f.near(slots.Slot1)
				assert(Interaction.TryPlaceInCargo(f.p, cart, "Slot1", a.ItemId))
				for _, slotId in { "Slot2", "Slot3" } do
					local filler = f.carry()
					f.near(slots[slotId])
					assert(Interaction.TryPlaceInCargo(f.p, cart, slotId, filler.ItemId))
				end
				local b = f.carry()
				f.near(slots.Slot1)
				local m, c = f.spawn()
				assert(Interaction.TryPickupWorld(f.other, m, c.ItemId))
				f.other.Character:PivotTo(CFrame.new(slots.Slot1.Position + Vector3.new(-4, 0, 4)))
				-- Explicit permission fixture ONLY: production policy stays owner-only.
				local permission = Cargo.CanPlayerHandleCargo
				f.replace(Cargo, "CanPlayerHandleCargo", function(self, who, target)
					return (who == f.other and target == cart) or permission(self, who, target)
				end)
				local factory, loser = Cargo.CreateItemVisual, nil
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					Cargo.CreateItemVisual = factory
					task.wait()
					loser = table.pack(Interaction.TryReplaceCargo(f.other, cart, "Slot1", a.ItemId, c.ItemId))
					return factory(self, id)
				end)
				local ok, reason = Interaction.TryReplaceCargo(f.p, cart, "Slot1", a.ItemId, b.ItemId)
				assert(ok, reason)
				expect(loser[1]).to.equal(false)
				expect(loser[2]).to.equal("BUSY")
				expect(Cargo:GetSlotRecord(cart, "Slot1").ItemId).to.equal(b.ItemId)
				expect(Cargo:GetCargoRevision(cart)).to.equal(4)
				expect(Interaction.GetCarriedRecord(f.other).ItemId).to.equal(c.ItemId)
				task.wait(0.65)
				expect(select(2, Interaction.TryReplaceCargo(f.other, cart, "Slot1", a.ItemId, c.ItemId))).to.equal(
					"STALE_ID"
				)
				expect(Cargo:GetCargoRevision(cart)).to.equal(4)
			end)
		end)

		it(
			"tracks three loaded IDs through simulated arrival and selected manual banking; only banked records earn",
			function()
				fixture(function(f)
					-- Registry and arrival-position fixture only: this does not simulate driving.
					local cart = Instance.new("Model")
					cart.Name, cart.Parent = "ManualCargoRoute", f.root
					cart:SetAttribute("CartId", "CRT_001")
					cart:SetAttribute("RuntimeCart", true)
					cart:SetAttribute("OwnerUserId", f.p.UserId)
					local chassis = f.part(cart, "Root", f.origin + Vector3.new(30, -2, 0), Vector3.new(6, 1, 10))
					cart.PrimaryPart = chassis
					local slots = Instance.new("Folder")
					slots.Name, slots.Parent = "CargoSlots", cart
					for i = 1, 3 do
						local s = f.part(slots, "Slot" .. i, f.origin + Vector3.new(28 + i * 2, 0, 3.5), Vector3.one)
						s.CanCollide = false
						local a = Instance.new("Attachment")
						a.Name, a.Parent = "CargoAttachment", s
					end
					local record = { Model = cart, OwnerUserId = f.p.UserId }
					f.replace(Carts, "GetCart", function(_, who)
						return if who == f.p then cart else nil
					end)
					f.replace(Carts, "GetCartRecordByOwnerUserId", function(_, id)
						return if id == f.p.UserId then record else nil
					end)
					local ids = {}
					Income:Start()
					Income:TrackPlayer(f.p)
					assert(Income:BindStorage(f.p, f.storage))
					local rate = assert(Catalog.GetCashPerSecond("BRT_007"))
					for _, i in { 3, 1, 2 } do
						local r = f.carry()
						ids[i] = r.ItemId
						f.near(slots["Slot" .. i])
						assert(Interaction.TryPlaceInCargo(f.p, cart, "Slot" .. i, r.ItemId))
					end
					local cash = Currency:GetBalance(f.p)
					cart:PivotTo(CFrame.new(f.base.Slot_1.Position + Vector3.new(0, 1, -18)))
					Return:Step()
					task.wait(1.1)
					expect(Cargo:GetCargoCount(cart)).to.equal(3)
					expect(Cargo:GetCargoRevision(cart)).to.equal(3)
					expect(f.storage:GetRevision()).to.equal(0)
					expect(Income:GetIncomeRate(f.p)).to.equal(0)
					expect(Currency:GetBalance(f.p)).to.equal(cash)
					for n, pair in { { 2, 7 }, { 3, 4 }, { 1, 11 } } do
						local index, platform = pair[1], f.base["Slot_" .. pair[2]]
						f.near(slots["Slot" .. index])
						assert(Interaction.TryPickupCargo(f.p, cart, "Slot" .. index, ids[index]))
						expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(ids[index])
						expect(Cargo:GetSlotRecord(cart, "Slot" .. index)).to.equal(nil)
						expect(Cargo:GetCargoCount(cart)).to.equal(3 - n)
						expect(Income:GetIncomeRate(f.p)).to.equal((n - 1) * rate)
						f.near(platform)
						assert(Interaction.TryPlaceOnPlatform(f.p, platform, ids[index]))
						expect(f.storage:GetPlatformRecord(pair[2]).ItemId).to.equal(ids[index])
						expect(f.storage:GetPlatformRecord(pair[2]).Metadata.Mutation.Quality).to.equal(7)
						expect(Interaction.IsCarrying(f.p)).to.equal(false)
						expect(Income:GetIncomeRate(f.p)).to.equal(n * rate)
					end
					expect(Cargo:GetCargoRevision(cart)).to.equal(6)
					expect(#cart.CargoVisuals:GetChildren()).to.equal(0)
					expect(#f.base.StoredBrainrots:GetChildren()).to.equal(3)
					expect(cart.Parent).to.equal(f.root)
					local before = Currency:GetBalance(f.p)
					task.wait(1.2)
					expect(Currency:GetBalance(f.p)).to.equal(before)
					local unclaimed = f.storage:GetUnclaimedCashExact(7)
						+ f.storage:GetUnclaimedCashExact(4)
						+ f.storage:GetUnclaimedCashExact(11)
					expect(unclaimed > 0).to.equal(true)
				end)
			end
		)

		it(
			"completes no-cart shot/pickup/arrival/exact placement and two real income intervals over a banked baseline",
			function()
				fixture(function(f)
					seed(f, 1) -- Supported existing-banked-state fixture, not capture/reward logic.
					Income:Start()
					Income:TrackPlayer(f.p)
					assert(Income:BindStorage(f.p, f.storage))
					local rate = assert(Catalog.GetCashPerSecond("BRT_007"))
					expect(Income:GetIncomeRate(f.p)).to.equal(rate)
					local m, r = f.spawn(true)
					local tool = Instance.new("Tool")
					tool.Name = "SleepLauncher"
					tool:SetAttribute("BrainrotSleepLauncher", true)
					local handle = f.part(tool, "Handle", f.p.Character.PrimaryPart.Position)
					local muzzle = Instance.new("Attachment")
					muzzle.Name, muzzle.Parent = "Muzzle", handle
					tool.Parent = f.p.Character
					assert(fireAt(f.p, m.Body.Position))
					assert(Interaction.TryPickupWorld(f.p, m, r.ItemId))
					f.near(f.base.Slot_7)
					Return:Step()
					task.wait(1.1)
					expect(Interaction.IsCarrying(f.p)).to.equal(true)
					expect(Income:GetIncomeRate(f.p)).to.equal(rate)
					local notifications = 0
					local consistent = false
					local unsub = Storage:ObserveStorage({
						OnCommitted = function(_, s, revision)
							notifications += 1
							consistent = not Interaction.IsCarrying(f.p)
								and s:GetPlatformRecord(7).ItemId == r.ItemId
								and revision == 2
						end,
					})
					assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_7, r.ItemId))
					unsub()
					expect(notifications).to.equal(1)
					expect(consistent).to.equal(true)
					expect(f.storage:GetPlatformRecord(2)).to.equal(nil)
					expect(f.storage:GetPlatformRecord(7).Metadata.Mutation.Quality).to.equal(7)
					expect(f.p.Character:FindFirstChild("CarriedBrainrot")).to.equal(nil)
					expect(f.p:GetAttribute("CarriedItemId")).to.equal(nil)
					expect(#f.base.StoredBrainrots:GetChildren()).to.equal(2)
					local display = f.base.StoredBrainrots["Stored_" .. r.ItemId]
					expect(World.GetWorldRecord(display)).to.equal(nil)
					expect((display:GetPivot().Position - f.base.Slot_7.Position).Magnitude < 8).to.equal(true)
					expect(Income:GetIncomeRate(f.p)).to.equal(rate * 2)
					expect(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_8, r.ItemId)).to.equal(false)
					local before = Income:GetStateSnapshot(f.p)
					local cash = Currency:GetBalance(f.p)
					local seen, last = 0, before.LastAccruedMs
					local deadline = os.clock() + 5
					repeat
						task.wait(0.05)
						local state = Income:GetStateSnapshot(f.p)
						if state.LastAccruedMs ~= last then
							seen += 1
							last = state.LastAccruedMs
						end
					until seen >= 2 or os.clock() > deadline
					local after = Income:GetStateSnapshot(f.p)
					expect(seen >= 2).to.equal(true)
					local earned = after.UnclaimedCashExact - before.UnclaimedCashExact
					local expected = (after.LastAccruedMs - before.LastAccruedMs) / 1000 * rate * 2
					expect(math.abs(earned - expected) <= rate * 2 / 1000 + 1e-6).to.equal(true)
					expect(Currency:GetBalance(f.p)).to.equal(cash)
					expect(f.storage:GetRevision()).to.equal(2)
					print(
						string.format(
							"[PlatformIncomeFixture] baselineRate=%.1f placedRate=%.1f realIntervals=%d elapsedMs=%d unclaimedExact=%.3f",
							rate,
							rate * 2,
							seen,
							after.LastAccruedMs - before.LastAccruedMs,
							earned
						)
					)
				end)
			end
		)

		it(
			"rejects occupied, foreign, slab, stale, distant, obstructed and dead requests without losing carry",
			function()
				fixture(function(f)
					seed(f, 4)
					local r = f.carry()
					f.near(f.base.Slot_4)
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_4, r.ItemId))).to.equal("OCCUPIED")
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.otherBase.Slot_1, r.ItemId))).to.equal(
						"NOT_OWNER"
					)
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.DecorativeSlab, r.ItemId))).to.equal(
						"INVALID_PLATFORM"
					)
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_5, "stale"))).to.equal("STALE_ID")
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_12, r.ItemId))).to.equal(
						"OUT_OF_REACH"
					)
					f.near(f.base.Slot_5)
					local wall =
						f.part(f.root, "Wall", f.base.Slot_5.Position + Vector3.new(0, 3, 3), Vector3.new(12, 8, 0.5))
					expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_5, r.ItemId))).to.equal(
						"OBSTRUCTED"
					)
					wall:Destroy()
					expect(Interaction.GetCarriedRecord(f.p).ItemId).to.equal(r.ItemId)
					expect(f.storage:GetRevision()).to.equal(1)
					f.p.Character.Humanoid.Health = 0
					expect(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_5, r.ItemId)).to.equal(false)
				end)
			end
		)

		it("rechecks reach after yielding presentation preparation and releases the exact reservation", function()
			fixture(function(f)
				local r = f.carry()
				f.near(f.base.Slot_8)
				local factory = Cargo.CreateItemVisual
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					task.wait()
					f.p.Character:PivotTo(CFrame.new(f.origin))
					return factory(self, id)
				end)
				expect(select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_8, r.ItemId))).to.equal("OUT_OF_REACH")
				Cargo.CreateItemVisual = factory
				expect(f.storage:GetAvailableSlotCount()).to.equal(12)
				expect(Interaction.IsCarrying(f.p)).to.equal(true)
				f.near(f.base.Slot_8)
				assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_8, r.ItemId))
			end)
		end)

		it("two overlapping requests for one slot have one winner and one notification", function()
			fixture(function(f)
				local r = f.carry()
				f.near(f.base.Slot_9)
				local factory = Cargo.CreateItemVisual
				local rejected
				local count = 0
				local unsub = Storage:ObserveStorage({
					OnCommitted = function()
						count += 1
					end,
				})
				f.replace(Cargo, "CreateItemVisual", function(self, id)
					rejected = select(2, Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_9, r.ItemId))
					task.wait()
					return factory(self, id)
				end)
				assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_9, r.ItemId))
				Cargo.CreateItemVisual = factory
				unsub()
				expect(rejected).to.equal("BUSY")
				expect(count).to.equal(1)
				expect(f.storage:GetOccupiedCount()).to.equal(1)
				expect(f.storage:GetRevision()).to.equal(1)
			end)
		end)

		it("fallible preparation retains the catch and post-commit/observer errors cannot duplicate it", function()
			fixture(function(f)
				local r = f.carry()
				f.near(f.base.Slot_6)
				local factory = Cargo.CreateItemVisual
				f.replace(Cargo, "CreateItemVisual", function()
					return nil
				end)
				expect(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_6, r.ItemId)).to.equal(false)
				expect(Interaction.IsCarrying(f.p)).to.equal(true)
				Cargo.CreateItemVisual = factory
				local commit = f.storage.CommitReservation
				f.replace(f.storage, "CommitReservation", function(self, ...)
					assert(commit(self, ...))
					error("Injected post-commit diagnostic failure")
				end)
				local unsub = Storage:ObserveStorage({
					OnCommitted = function()
						error("Injected observer failure")
					end,
				})
				assert(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_6, r.ItemId))
				unsub()
				expect(Interaction.IsCarrying(f.p)).to.equal(false)
				expect(f.storage:GetPlatformRecord(6).ItemId).to.equal(r.ItemId)
				expect(Interaction.TryPlaceOnPlatform(f.p, f.base.Slot_7, r.ItemId)).to.equal(false)
				expect(f.storage:GetOccupiedCount()).to.equal(1)
			end)
		end)
	end)
end
