--!nocheck
-- Native cargo/world/cart owners with a synthetic acquired profile. No backend.
return function()
	local Fixture = require(script.Parent.Support.Phase12NativeFixture)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Banked = require(script.Parent.Parent.Services.BankedBrainrotService)
	local Carts = require(script.Parent.Parent.Services.CartService)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local Carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local function run(saved, test)
		Fixture(function(f)
			local incoming = f.carry("BRT_011", { MutationId = "None" })
			f.near("Slot1")
			assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot1", incoming.ItemId))
			local target = Cargo:GetCargoItem(f.cart, incoming.ItemId)
			local other = f.carry("BRT_011", { MutationId = "None" })
			f.near("Slot2")
			assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot2", other.ItemId))
			local otherEntry = Cargo:GetCargoItem(f.cart, other.ItemId)
			local original = f.carry("BRT_011", {
				MutationId = "Golden",
				DurableOwnerUserId = f.p.UserId,
				FirstBankCompleted = true,
			})
			f.near("Slot3")
			assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot3", original.ItemId))
			local data = Schema.CreateDefault()
			data.Collection.BrainrotInstances[original.ItemId] = {
				speciesId = "BRT_011",
				mutationId = "Golden",
				firstBankCompleted = true,
			}
			if saved then
				data.Collection.BrainrotInstances[target.ItemId] = {
					speciesId = "BRT_011",
					mutationId = "None",
					firstBankCompleted = true,
				}
				data.Base.Slots["1"].brainrotId = target.ItemId
			end
			local replacement = { UserId = f.p.UserId, Name = "SyntheticRejoin", Parent = game.Players }
			local oldHandle, newHandle = { Player = f.p, Generation = 1 }, { Player = replacement, Generation = 2 }
			local current, writable = oldHandle, false
			local owner = {}
			function owner:GetSessionHandle(p)
				return if p == f.p then oldHandle elseif p == replacement then newHandle else nil
			end
			function owner:IsCurrentSessionHandle(handle)
				return handle == current
			end
			function owner:GetReadableData(p)
				return if p == replacement and current == newHandle then data else nil
			end
			function owner:IsRevisionConfirmed()
				return false
			end
			function owner:RequestSave()
				return { ok = false, code = "SYNTHETIC_UNCERTAIN" }
			end
			function owner:IsWritable(p)
				return writable and p == replacement
			end
			function owner:CommitMutation(p, mutate)
				assert(p == replacement and writable, "New acquired owner only")
				local ok, result = mutate(data)
				result.ok, result.committed, result.revision = ok, ok, 2
				return result
			end
			f.replace(Profile, "GetReadableData", function(_, p)
				return owner:GetReadableData(p)
			end)
			f.replace(Profile, "GetSessionHandle", function(_, p)
				return owner:GetSessionHandle(p)
			end)
			f.replace(Profile, "IsCurrentSessionHandle", function(_, handle)
				return owner:IsCurrentSessionHandle(handle)
			end)
			Banked:_ResetForTests({ Profile = owner })
			local transfer = assert(Cargo:DetachForTransfer(f.cart, target.ItemId))
			local operationId = "Bank:" .. target.ItemId
			assert(World.BeginPendingBank(target, operationId, 1))
			local oldPublications = 0
			Banked:RegisterPendingBank(f.p, target, 1, function()
				oldPublications += 1
				return true
			end)
			local record = { OwnerUserId = f.p.UserId, Model = f.cart, CartId = "CRT_001", Generation = 7 }
			local ok, failure = xpcall(function()
				Carts:_TestWithOwnedSelectionRecord(f.p, record, function()
					return { status = "Ready", userId = f.p.UserId }
				end, function()
					local cartHandle = Carts:GetCartHandle(f.p)
					f.p.Parent = nil
					expect(Carts:DespawnCart(f.p, "Player leaving")).to.equal(false)
					expect(Carts:IsCurrentCartHandle(cartHandle)).to.equal(true)
					expect(World.IsPendingBank(target.ItemId)).to.equal(true)
					current = newHandle
					test({
						Fixture = f,
						Replacement = replacement,
						Data = data,
						Target = target,
						Other = otherEntry,
						Original = original,
						Transfer = transfer,
						CartHandle = cartHandle,
						Publications = function()
							return oldPublications
						end,
						Restore = function()
							writable = true
							return Banked:ReconcileInitialOwnedLocations(replacement, owner)
						end,
					})
				end)
			end, debug.traceback)
			-- Exact staged fixture cleanup if an assertion rejects the recovery path.
			Cargo:FinalizeTransfer(f.cart, transfer)
			if World.IsPendingBank(target.ItemId) then
				World.ConfirmPendingBank(target, operationId)
			end
			Banked:_ResetForTests()
			assert(ok, failure)
		end)
	end
	describe("Phase13 retained departed cart canonical recovery", function()
		for _, saved in { false, true } do
			it(
				"resolves "
					.. (if saved then "saved" else "absent")
					.. " pending transfer before old-cart disposal without orphaning fresh cargo",
				function()
					run(saved, function(f)
						local before = World.GetPopulationSnapshot().Effective
						local handling = World.GetPhase12State(f.Other)
						local targetHandling = World.GetPhase12State(f.Target)
						local releasePose = f.Fixture.cart:GetPivot()
						expect(handling ~= nil).to.equal(true)
						expect(Carts:RecoverDepartedCart(f.Fixture.p, f.Replacement, f.Data)).to.equal(true)
						expect(Carts:IsCurrentCartHandle(f.CartHandle)).to.equal(false)
						expect(f.Fixture.cart.Parent).to.equal(nil)
						expect(World.IsPendingBank(f.Target.ItemId)).to.equal(false)
						expect(World.HasOrdinaryReservation(f.Target.ItemId)).to.equal(not saved)
						expect(World.GetPopulationSnapshot().Effective).to.equal(before - (if saved then 1 else 0))
						if not saved then
							expect(World.GetPhase12State(f.Target)).to.equal(targetHandling)
							local pending
							for _, entry in World.GetPopulationSnapshot().PendingWorldRecords do
								if entry.ItemId == f.Target.ItemId then
									pending = entry
								end
							end
							expect(pending ~= nil).to.equal(true)
							expect(pending.BrainrotId).to.equal(f.Target.BrainrotId)
							expect(pending.Position).to.equal(releasePose.Position)
						end
						expect(World.HasOrdinaryReservation(f.Other.ItemId)).to.equal(true)
						expect(World.GetPhase12State(f.Other)).to.equal(handling)
						-- Diagnostics combines cargo returns and the authoritative counted
						-- world queue. An absent bank belongs in the latter only.
						expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, f.Target.ItemId) ~= nil).to.equal(
							not saved
						)
						local cargoReturn, cargoReturnReason = Cargo:CancelPendingReturnForTesting(f.Target.ItemId)
						expect(cargoReturn).to.equal(false)
						expect(cargoReturnReason).to.equal("NOT_PENDING")
						expect(f.Data.Collection.BrainrotInstances[f.Original.ItemId].mutationId).to.equal("Golden")
						expect(f.Data.Collection.BrainrotInstances[f.Target.ItemId] ~= nil).to.equal(saved)
						expect(Banked:HasPendingBank(f.Replacement)).to.equal(false)
						expect(f.Publications()).to.equal(0)
						expect(f.Data.Economy.Balance).to.equal(0)
						expect(f.Restore().ok).to.equal(true)
						local restored = false
						for _, slot in f.Data.Base.Slots do
							if slot.brainrotId == f.Original.ItemId then
								restored = true
							end
						end
						expect(restored).to.equal(true)
						expect(Carts:RecoverDepartedCart(f.Fixture.p, f.Replacement, f.Data)).to.equal(true)
						expect(World.GetPopulationSnapshot().Effective).to.equal(before - (if saved then 1 else 0))
					end)
				end
			)
		end
		it("refuses an acquired mutation conflict without discarding the counted source or old cart", function()
			run(true, function(f)
				f.Data.Collection.BrainrotInstances[f.Target.ItemId].mutationId = "Golden"
				expect(Carts:RecoverDepartedCart(f.Fixture.p, f.Replacement, f.Data)).to.equal(false)
				expect(Carts:IsCurrentCartHandle(f.CartHandle)).to.equal(true)
				expect(World.IsPendingBank(f.Target.ItemId)).to.equal(true)
				expect(World.HasOrdinaryReservation(f.Other.ItemId)).to.equal(true)
				expect(Cargo:GetCargoItem(f.Fixture.cart, f.Other.ItemId)).to.equal(f.Other)
			end)
		end)
	end)
end
