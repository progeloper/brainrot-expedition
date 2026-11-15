--!nocheck
-- Native displaced owned world originals + real base/profile return binding.
-- Isolated fake profile/assignment authority; no user profile or live place writes.
return function()
	local server = script.Parent.Parent
	local Fixture = require(script.Parent.Support.Phase12NativeFixture)
	local Schema = require(server.Data.PlayerProfileSchema)
	local Banked = require(server.Services.BankedBrainrotService)
	local Storage = require(server.Systems.BaseStorageSystem)
	local Bases = require(server.Systems.PlayerBaseSystem)
	local World = require(server.Systems.DevelopmentBrainrotSpawner)
	local H = game:GetService("HttpService")
	local function fixture(callback, full)
		Fixture(function(f)
			local data = Schema.CreateDefault()
			local failCommit = false
			local owner = { Revision = 0 }
			function owner:IsWritable(player)
				return player == f.p
			end
			function owner:GetReadableData(player)
				return if self:IsWritable(player) then data else nil
			end
			function owner:GetWritableData(player)
				return self:GetReadableData(player), "PROFILE_NOT_READY"
			end
			function owner:GetSessionHandle(player)
				return if self:IsWritable(player) then { Generation = 1, UserId = player.UserId } else nil
			end
			function owner:IsCurrentSessionHandle(handle)
				return handle and handle.Generation == 1 and handle.UserId == f.p.UserId
			end
			function owner:GetDiagnostics()
				return { currentRevision = self.Revision }
			end
			function owner:CommitMutation(player, mutator)
				if not self:IsWritable(player) then
					return { ok = false, code = "PROFILE_NOT_READY" }
				end
				if failCommit then
					return { ok = false, committed = false, code = "INJECTED_COMMIT_FAILURE" }
				end
				local changed, result = mutator(data)
				if changed then
					self.Revision += 1
					result.ok, result.committed, result.revision = true, true, self.Revision
				end
				return result
			end
			local base = Instance.new("Model")
			base.Name = "Phase12SecuredBase"
			base:SetAttribute("BaseId", base.Name)
			base.Parent = f.root
			for i = 1, 48 do
				local platform = f.part(
					base,
					string.format("Slot_%02d", i),
					f.origin + Vector3.new(50 + i * 10, 0, 40),
					Vector3.new(8, 0.75, 8)
				)
				local marker = Instance.new("Attachment")
				marker.Name = "BrainrotPlacement"
				marker.CFrame = CFrame.new(0, 0.375, 0)
				marker.Parent = platform
			end
			local assignment = { Player = f.p, Base = base, BaseId = base.Name, Generation = 1 }
			local assigned
			f.replace(Bases, "GetRegisteredBases", function()
				return { base }
			end)
			f.replace(Bases, "GetBase", function(_, player)
				return if player == f.p then base else nil
			end)
			f.replace(Bases, "GetAssignment", function(_, player)
				return if player == f.p then assignment else nil
			end)
			f.replace(Bases, "IsOwner", function(_, player, b)
				return player == f.p and b == base
			end)
			f.replace(Bases, "IsCurrentAssignment", function(_, handle)
				return handle == assignment
			end)
			f.replace(Bases, "SubscribeAssignments", function(_, add)
				assigned = add
				return { Disconnect = function() end }
			end)
			local function saved(id, species, mutation)
				data.Collection.BrainrotInstances[id] = {
					speciesId = species,
					mutationId = mutation,
					firstBankCompleted = true,
					metadata = {
						MutationId = mutation,
						DurableOwnerUserId = f.p.UserId,
						FirstBankCompleted = true,
						PreservedNote = "existing-owned",
					},
				}
			end
			if full then
				for i = 1, 12 do
					local id = "secured-full-" .. i
					saved(id, "BRT_007", "None")
					data.Base.Slots[tostring(i)].brainrotId = id
				end
			end
			Banked:_ResetForTests({ Profile = owner })
			Storage:Start({ Profile = owner })
			assigned(f.p, base, assignment)
			local function displaced()
				local model, record = f.spawn(
					true,
					"BRT_011",
					{ MutationId = "Golden", DurableOwnerUserId = f.p.UserId, FirstBankCompleted = true }
				)
				saved(record.ItemId, record.BrainrotId, "Golden")
				return model, record
			end
			local ok, reason = xpcall(function()
				callback({
					f = f,
					data = data,
					base = base,
					owner = owner,
					displaced = displaced,
					setFailure = function(value)
						failCommit = value
					end,
				})
			end, debug.traceback)
			Storage:Destroy()
			Banked:_ResetForTests()
			assert(ok, reason)
		end)
	end
	describe("Phase12 timed reset secured world originals", function()
		it(
			"restores an outside owned world original once and retries native binding without granting bank rewards",
			function()
				fixture(function(t)
					local model, record = t.displaced()
					local savedBefore = H:JSONEncode(t.data.Collection.BrainrotInstances[record.ItemId])
					local progressBefore = H:JSONEncode({
						t.data.Collection.Species,
						t.data.Collection.Mutations,
						t.data.Progression.ExpeditionBest,
					})
					local cashBefore = t.data.Economy.Balance
					expect(#World.GetSecuredWorldRecords(t.f.p.UserId)).to.equal(1)
					World.ResetOutsideCamp(function()
						return false
					end, 77)
					expect(World.GetWorldRecord(model)).to.equal(record)
					local original = Storage.BindReturnedOwnedIndividual
					local bindCalls = 0
					t.f.replace(Storage, "BindReturnedOwnedIndividual", function(self, ...)
						bindCalls += 1
						if bindCalls == 1 then
							return false, "INJECTED_BIND_PENDING"
						end
						return original(self, ...)
					end)
					local first, firstReason = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					expect(first).to.equal(false)
					expect(firstReason).to.equal("INJECTED_BIND_PENDING")
					expect(#World.GetSecuredWorldRecords(t.f.p.UserId)).to.equal(0)
					expect(t.data.Base.Slots["1"].brainrotId).to.equal(record.ItemId)
					expect(Storage:GetStorageForPlayer(t.f.p):GetPlatformRecord(1)).to.equal(nil)
					local revision = t.owner.Revision
					local ok, reason, summary = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					assert(ok, reason)
					expect(summary.worldSources).to.equal(0)
					expect(t.owner.Revision).to.equal(revision)
					local runtime = Storage:GetStorageForPlayer(t.f.p)
					expect(runtime:GetPlatformRecord(1).ItemId).to.equal(record.ItemId)
					expect(runtime:TakeBankReceipt(record.ItemId)).to.equal(nil)
					expect(#t.base.StoredBrainrots:GetChildren()).to.equal(1)
					expect(H:JSONEncode(t.data.Collection.BrainrotInstances[record.ItemId])).to.equal(savedBefore)
					expect(H:JSONEncode({
						t.data.Collection.Species,
						t.data.Collection.Mutations,
						t.data.Progression.ExpeditionBest,
					})).to.equal(progressBefore)
					expect(t.data.Economy.Balance).to.equal(cashBefore)
					expect(Banked:RestoreSecuredWorldForReset(t.f.p, World)).to.equal(true)
					expect(#t.base.StoredBrainrots:GetChildren()).to.equal(1)
				end)
			end
		)
		it(
			"full base preserves the durable unassigned original and retires only its displaced native world source",
			function()
				fixture(function(t)
					local model, record = t.displaced()
					local savedBefore = H:JSONEncode(t.data.Collection.BrainrotInstances[record.ItemId])
					local occupied = Storage:GetStorageForPlayer(t.f.p):GetOccupiedCount()
					expect(occupied).to.equal(12)
					local ok, reason, summary = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					assert(ok, reason)
					expect(summary.preservedUnassigned).to.equal(1)
					expect(summary.retired).to.equal(1)
					expect(World.GetWorldRecord(model)).to.equal(nil)
					expect(H:JSONEncode(t.data.Collection.BrainrotInstances[record.ItemId])).to.equal(savedBefore)
					for _, slot in t.data.Base.Slots do
						expect(slot.brainrotId == record.ItemId).to.equal(false)
					end
					expect(Storage:GetStorageForPlayer(t.f.p):GetOccupiedCount()).to.equal(12)
					expect(#t.base.StoredBrainrots:GetChildren()).to.equal(12)
					expect(t.data.Economy.Balance).to.equal(0)
					expect(t.data.Collection.Species.BRT_011).to.equal(nil)
				end, true)
			end
		)
		it(
			"failed profile commit or changed mutation retains the exact owned world source and leaves the slot untouched",
			function()
				fixture(function(t)
					local model, record = t.displaced()
					local pose = model:GetPivot()
					t.setFailure(true)
					local ok, reason = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					expect(ok).to.equal(false)
					expect(reason).to.equal("INJECTED_COMMIT_FAILURE")
					expect(World.GetWorldRecord(model)).to.equal(record)
					expect(model:GetPivot()).to.equal(pose)
					expect(t.data.Base.Slots["1"].brainrotId).to.equal(nil)
					t.setFailure(false)
					t.data.Collection.BrainrotInstances[record.ItemId].mutationId = "Shiny"
					local changed, changedReason = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					expect(changed).to.equal(false)
					expect(changedReason).to.equal("SECURED_OWNERSHIP_INCONSISTENT")
					expect(World.GetWorldRecord(model)).to.equal(record)
					expect(t.data.Base.Slots["1"].brainrotId).to.equal(nil)
					t.data.Collection.BrainrotInstances[record.ItemId].mutationId = "Golden"
					local retried, retryReason = Banked:RestoreSecuredWorldForReset(t.f.p, World)
					assert(retried, retryReason)
					expect(#World.GetSecuredWorldRecords(t.f.p.UserId)).to.equal(0)
					expect(Storage:GetStorageForPlayer(t.f.p):GetPlatformRecord(1).ItemId).to.equal(record.ItemId)
				end)
			end
		)
	end)
end
