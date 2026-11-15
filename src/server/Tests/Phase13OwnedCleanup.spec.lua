--!nocheck
-- Disposable real carry/cargo representations with a synthetic readable map.
-- The test supplies durable removal explicitly; no profile/backend call occurs.
return function()
	local Fixture = require(script.Parent.Support.Phase12NativeFixture)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local Carry = require(script.Parent.Parent.Systems.BrainrotInteractionSystem)
	local Cargo = require(script.Parent.Parent.Services.CartCargoService)
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	describe("Phase13 confirmed owned source reconciliation", function()
		it("retires only the exact pending-bank hand mirror without releasing its reservation", function()
			Fixture(function(f)
				local fresh = f.carry("BRT_011", { MutationId = "Golden" })
				local operation = "Bank:" .. fresh.ItemId
				assert(World.BeginPendingBank(fresh, operation, 1))
				local valid, pose = Carry.GetPendingBankSourcePose(f.p, fresh, operation)
				expect(valid).to.equal(true)
				expect(typeof(pose)).to.equal("CFrame")
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(fresh.ItemId)
				expect(World.IsPendingBank(fresh.ItemId)).to.equal(true)
				local invalid = Carry.GetPendingBankSourcePose(f.p, fresh, "Bank:wrong")
				expect(invalid).to.equal(false)
				expect(Carry.ReconcilePendingBankSource(f.p, fresh, "Bank:wrong")).to.equal(false)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(fresh.ItemId)
				local wrong = table.clone(fresh)
				wrong.Metadata = table.clone(fresh.Metadata)
				wrong.Metadata.MutationId = "None"
				expect(Carry.ReconcilePendingBankSource(f.p, wrong, operation)).to.equal(false)
				expect(Carry.ReconcilePendingBankSource(f.p, fresh, operation)).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p)).to.equal(nil)
				expect(World.IsPendingBank(fresh.ItemId)).to.equal(true)
				expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
				assert(World.ConfirmPendingBank(fresh, operation))
				local unrelated = f.carry("BRT_011", { MutationId = "None" })
				local noMatch, unrelatedPose = Carry.GetPendingBankSourcePose(f.p, fresh, operation)
				expect(noMatch).to.equal(true)
				expect(unrelatedPose).to.equal(nil)
				expect(Carry.ReconcilePendingBankSource(f.p, fresh, operation)).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(unrelated.ItemId)
				expect(World.HasOrdinaryReservation(unrelated.ItemId)).to.equal(true)
			end)
		end)
		it(
			"uses ordinary counted logout release for an old fresh hand instead of transferring it to the new actor",
			function()
				Fixture(function(f)
					local fresh = f.carry("BRT_011", { MutationId = "None" })
					local newActor = table.clone(f.p)
					local canonical = { Collection = { BrainrotInstances = {} } }
					expect(Carry.HandleAuthoritativeRecovery(f.p, newActor, canonical, canonical)).to.equal(true)
					expect(Carry.GetCarriedRecord(newActor)).to.equal(nil)
					expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
					-- It is either already locally restored or in the counted retry queue;
					-- no new profile ownership and no spawn credit was granted.
					expect(canonical.Collection.BrainrotInstances[fresh.ItemId]).to.equal(nil)
				end)
			end
		)
		it("retires only the departed durable hand mirror before canonical base restoration", function()
			Fixture(function(f)
				local original = f.carry("BRT_011", {
					MutationId = "Golden",
					DurableOwnerUserId = f.p.UserId,
					FirstBankCompleted = true,
				})
				local canonical = {
					Collection = {
						BrainrotInstances = {
							[original.ItemId] = { speciesId = "BRT_011", mutationId = "Golden" },
						},
					},
				}
				local newActor = table.clone(f.p)
				local wrong = {
					Collection = {
						BrainrotInstances = {
							[original.ItemId] = { speciesId = "BRT_011", mutationId = "None" },
						},
					},
				}
				expect(Carry.HandleAuthoritativeRecovery(f.p, newActor, wrong, canonical)).to.equal(false)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(original.ItemId)
				expect(Carry.HandleAuthoritativeRecovery(f.p, newActor, canonical, canonical)).to.equal(true)
				expect(Carry.GetCarriedRecord(newActor)).to.equal(nil)
				expect(canonical.Collection.BrainrotInstances[original.ItemId].mutationId).to.equal("Golden")
				expect(Carry.HandleAuthoritativeRecovery(f.p, newActor, canonical, canonical)).to.equal(true)
				local unrelated = f.carry("BRT_011", { MutationId = "None" })
				expect(Carry.HandleAuthoritativeRecovery(newActor, f.p, canonical, canonical)).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(unrelated.ItemId)
				expect(World.HasOrdinaryReservation(unrelated.ItemId)).to.equal(true)
			end)
		end)
		it("retains canonical-present durable cargo alongside the same fresh reservation after reacquire", function()
			Fixture(function(f)
				local original = f.carry(
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				f.near("Slot1")
				assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot1", original.ItemId))
				local fresh = f.carry("BRT_011", { MutationId = "None" })
				f.near("Slot2")
				assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot2", fresh.ItemId))
				local originalEntry = Cargo:GetCargoItem(f.cart, original.ItemId)
				local freshEntry = Cargo:GetCargoItem(f.cart, fresh.ItemId)
				local canonical = {
					Collection = {
						BrainrotInstances = { [original.ItemId] = { speciesId = "BRT_011", mutationId = "Golden" } },
					},
				}
				f.replace(Profile, "GetReadableData", function()
					error("Old session must not be read")
				end)
				expect(Cargo:HandleAuthoritativeRecovery(f.p, canonical, canonical)).to.equal(true)
				expect(Cargo:GetCargoItem(f.cart, original.ItemId)).to.equal(originalEntry)
				expect(Cargo:GetCargoItem(f.cart, fresh.ItemId)).to.equal(freshEntry)
				expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
				expect(originalEntry.Metadata.MutationId).to.equal("Golden")
			end)
		end)
		it("uses the acquired canonical snapshot for held recovery without consulting invalid old data", function()
			Fixture(function(f)
				local original = f.carry(
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				local previous =
					{ Collection = { BrainrotInstances = { [original.ItemId] = { speciesId = "BRT_011" } } } }
				local canonical = { Collection = { BrainrotInstances = {} } }
				f.replace(Profile, "GetReadableData", function()
					error("Old session must not be read")
				end)
				expect(Carry.HandleAuthoritativeRecovery(f.p, canonical, previous)).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p)).to.equal(nil)
				expect(Carry.HandleAuthoritativeRecovery(f.p, canonical, previous)).to.equal(true)
				local fresh = f.carry("BRT_011", { MutationId = "None" })
				expect(Carry.HandleAuthoritativeRecovery(f.p, canonical, previous)).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(fresh.ItemId)
				expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
			end)
		end)
		it("removes only absent durable cargo during acquired-session recovery", function()
			Fixture(function(f)
				local original = f.carry(
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				f.near("Slot1")
				assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot1", original.ItemId))
				local fresh = f.carry("BRT_011", { MutationId = "None" })
				f.near("Slot2")
				assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot2", fresh.ItemId))
				local previous =
					{ Collection = { BrainrotInstances = { [original.ItemId] = { speciesId = "BRT_011" } } } }
				local canonical = { Collection = { BrainrotInstances = {} } }
				f.replace(Profile, "GetReadableData", function()
					error("Old session must not be read")
				end)
				expect(Cargo:HandleAuthoritativeRecovery(f.p, canonical, previous)).to.equal(true)
				expect(Cargo:GetCargoItem(f.cart, original.ItemId)).to.equal(nil)
				expect(Cargo:GetCargoItem(f.cart, fresh.ItemId).ItemId).to.equal(fresh.ItemId)
				expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
				expect(Cargo:HandleAuthoritativeRecovery(f.p, canonical, previous)).to.equal(true)
			end)
		end)
		it("never removes a still owned held original and preserves fresh catches after sacrifice", function()
			Fixture(function(f)
				local data = { Collection = { BrainrotInstances = {} } }
				f.replace(Profile, "GetReadableData", function()
					return data
				end)
				local original = f.carry(
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				data.Collection.BrainrotInstances[original.ItemId] = { speciesId = original.BrainrotId }
				assert(Carry.PreflightOwnedSacrifice(f.p, { original.ItemId }))
				expect(Carry.ReconcileOwnedSacrifice(f.p, { original.ItemId })).to.equal(false)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(original.ItemId)
				data.Collection.BrainrotInstances[original.ItemId] = nil
				expect(Carry.ReconcileOwnedSacrifice(f.p, { original.ItemId })).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p)).to.equal(nil)
				expect(Carry.ReconcileOwnedSacrifice(f.p, { original.ItemId })).to.equal(true)
				local fresh = f.carry("BRT_011", { MutationId = "None" })
				expect(Carry.ReconcileOwnedSacrifice(f.p, { fresh.ItemId })).to.equal(true)
				expect(Carry.GetCarriedRecord(f.p).ItemId).to.equal(fresh.ItemId)
				expect(World.HasOrdinaryReservation(fresh.ItemId)).to.equal(true)
			end)
		end)
		it("cancels a deferred owned cargo return so it cannot republish after confirmed sacrifice", function()
			Fixture(function(f)
				local data = { Collection = { BrainrotInstances = {} } }
				f.replace(Profile, "GetReadableData", function()
					return data
				end)
				local original = f.carry(
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				data.Collection.BrainrotInstances[original.ItemId] = { speciesId = original.BrainrotId }
				f.near("Slot1")
				assert(Carry.TryPlaceInCargo(f.p, f.cart, "Slot1", original.ItemId))
				assert(Cargo:PreflightOwnedSacrifice(f.p, { original.ItemId }))
				expect(Cargo:ReconcileOwnedSacrifice(f.p, { original.ItemId })).to.equal(false)
				assert(Cargo:PrepareCartRemoval(f.cart))
				expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, original.ItemId) ~= nil).to.equal(true)
				data.Collection.BrainrotInstances[original.ItemId] = nil
				expect(Cargo:ReconcileOwnedSacrifice(f.p, { original.ItemId })).to.equal(true)
				expect(table.find(Cargo:GetRemovalDiagnostics().PendingIds, original.ItemId)).to.equal(nil)
				Cargo:ProcessPendingReturns()
				expect(World.GetWorldModelById(original.ItemId)).to.equal(nil)
			end)
		end)
	end)
end
