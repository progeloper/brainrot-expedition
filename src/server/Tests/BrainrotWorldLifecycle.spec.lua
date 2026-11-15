--!nocheck
-- Real modules/geometry and timed movement checks using the existing spec runner.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Http = game:GetService("HttpService")
	local World = require(script.Parent.Parent.Systems.DevelopmentBrainrotSpawner)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	local NaturalTerritory = require(script.Parent.Parent.Systems.NaturalTerritory)
	local VisualScale = require(RS.Shared.Utility.BrainrotVisualScale)
	local PILOT_SPECIES = { "BRT_007", "BRT_011", "BRT_015", "BRT_016" }

	local function provisionPilotTemplates()
		local studioAssets = RS:FindFirstChild("StudioAssets")
		local ownsStudioAssets = studioAssets == nil
		if studioAssets == nil then
			studioAssets = Instance.new("Folder")
			studioAssets.Name, studioAssets.Parent = "StudioAssets", RS
		end
		local templates = studioAssets:FindFirstChild("Brainrots")
		local ownsTemplates = templates == nil
		if templates == nil then
			templates = Instance.new("Folder")
			templates.Name, templates.Parent = "Brainrots", studioAssets
		end
		local created = {}
		for _, speciesId in PILOT_SPECIES do
			if not templates:FindFirstChild(speciesId) then
				local model = Instance.new("Model")
				model.Name = speciesId
				local body = Instance.new("Part")
				body.Name = "Body"
				body.Size = Vector3.new(2, 5, 3)
				body.CFrame = CFrame.new(0, 2.5, 0)
				body.CanQuery, body.CanCollide = true, true
				body.Parent = model
				local capture = Instance.new("Attachment")
				capture.Name, capture.Parent = "CaptureAttachment", body
				local cargo = Instance.new("Attachment")
				cargo.Name, cargo.Parent = "CargoAttachment", body
				model.PrimaryPart, model.Parent = body, templates
				table.insert(created, model)
			end
		end
		return function()
			for _, model in created do
				model:Destroy()
			end
			if ownsTemplates then
				templates:Destroy()
			end
			if ownsStudioAssets then
				studioAssets:Destroy()
			end
		end
	end

	local function fixture(callback, speciesId)
		Placement.ResetQueryBudgetForTesting()
		local created, models, preparations = {}, {}, {}
		local function folder(parent, name)
			local existing = parent:FindFirstChild(name)
			if existing then
				return existing
			end
			local value = Instance.new("Folder")
			value.Name, value.Parent = name, parent
			table.insert(created, value)
			return value
		end
		local templates = folder(folder(RS, "StudioAssets"), "Brainrots")
		local templateName = speciesId or "SPEC_WORLD_1A"
		local template = templates:FindFirstChild(templateName)
		local ownsTemplate = template == nil
		if template == nil then
			template = Instance.new("Model")
			template.Name = templateName
			local body = Instance.new("Part")
			body.Name = "Body"
			body.Size = Vector3.new(2, 5, 3)
			body.CFrame = CFrame.new(0, 2.5, 0)
			body.CanQuery, body.CanCollide = true, true
			body:AddTag("SPEC_WORLD_BODY")
			body.Parent = template
			local attachment = Instance.new("Attachment")
			attachment.Name, attachment.Parent = "CaptureAttachment", body
			template.PrimaryPart = body
			template.Parent = templates
		end
		assert(template:IsA("Model"), "Brainrot fixture source must be a Model")
		local record = {
			ItemId = Http:GenerateGUID(false),
			BrainrotId = template.Name,
			Metadata = {
				Tier = 1,
				Rarity = "Authored",
				Mutation = { Name = "Original", Quality = 3 },
			},
			World = {
				Name = "SPEC_INDIVIDUAL",
				Scale = 1.3,
				SpawnPosition = { X = 0, Y = 20, Z = 0 },
			},
		}
		local function prepare(data, pose)
			local staged, reason = World.PrepareWorldRepresentation(data or record, pose or CFrame.new(0, 20, 0))
			assert(staged, reason)
			table.insert(preparations, staged)
			table.insert(models, staged.Model)
			return staged
		end
		local ok, failure = xpcall(function()
			callback(record, prepare, template)
		end, debug.traceback)
		for _, staged in preparations do
			World.DiscardPreparedWorld(staged)
		end
		for _, model in models do
			World.DestroyWorldForTesting(model:GetAttribute("ItemId"))
			model:Destroy()
			World.Unregister(model)
		end
		if ownsTemplate then
			template:Destroy()
		end
		for index = #created, 1, -1 do
			created[index]:Destroy()
		end
		if not ok then
			error(failure, 0)
		end
	end

	describe("Physical hunting Phase 1A world lifecycle", function()
		it("keeps the deterministic ten-spawn 6A-2 pilot loadable without duplicate individuals", function()
			local cleanupTemplates = provisionPilotTemplates()
			local pilotGround = Instance.new("Part")
			pilotGround.Name = "SPEC_PILOT_GROUND"
			pilotGround.Anchored = true
			pilotGround:SetAttribute("CartDrivableGround", true)
			pilotGround.Size = Vector3.new(160, 2, 160)
			pilotGround.Position = Vector3.new(0, -0.95, -30)
			pilotGround.Parent = workspace
			-- World.Start also owns real registry entries. Preserve any pre-existing
			-- world and retire only pilots created by this isolated test before its
			-- temporary source templates disappear.
			local priorModels = {}
			for _, model in World.GetWorldModels() do
				priorModels[model] = true
			end
			local testOk, testFailure = xpcall(function()
				World.Start()
				Roaming.Start()
				local ids, counts, total = {}, {}, 0
				for _, model in workspace.Runtime.Brainrots:GetChildren() do
					if string.find(model.Name, "_Pilot_", 1, true) then
						local record = World.GetWorldRecord(model)
						assert(record and not ids[record.ItemId], "Spawn must have a unique world ID")
						ids[record.ItemId] = true
						counts[record.BrainrotId] = (counts[record.BrainrotId] or 0) + 1
						total += 1
						local height = VisualScale.GetVisualHeight(model)
						expect(math.abs(height - VisualScale.TARGET_HEIGHT_STUDS) <= VisualScale.TOLERANCE_STUDS).to.equal(
							true
						)
						local box, size = model:GetBoundingBox()
						expect(box.Y - size.Y / 2 >= 0.149).to.equal(true)
					end
				end
				expect(total).to.equal(10)
				expect(counts.BRT_007).to.equal(3)
				expect(counts.BRT_011).to.equal(3)
				expect(counts.BRT_015).to.equal(2)
				expect(counts.BRT_016).to.equal(2)
				local count = Roaming.GetDiagnostics().Registered
				World.Start()
				expect(Roaming.GetDiagnostics().Registered).to.equal(count)
				local Sleep = require(script.Parent.Parent.Systems.BrainrotSleepSystem)
				local wasStarted = Sleep.GetDiagnostics().Started
				Sleep:Start()
				Sleep:Start()
				expect(RS.Remotes.SleepRequest:IsA("RemoteEvent")).to.equal(true)
				if not wasStarted then
					Sleep:Stop()
				end
			end, debug.traceback)
			for _, model in World.GetWorldModels() do
				if not priorModels[model] and string.find(model.Name, "_Pilot_", 1, true) then
					local record = World.GetWorldRecord(model)
					if record then
						World.DestroyWorldForTesting(record.ItemId)
					end
				end
			end
			pilotGround:Destroy()
			cleanupTemplates()
			if not testOk then
				error(testFailure, 0)
			end
		end)

		it("grounds released pilots above raised floor seams before horizontal movement", function()
			local geometry = Instance.new("Folder")
			geometry.Name, geometry.Parent = "SPEC_PILOT_SEAM", workspace
			local origin = Vector3.new(18500, 0, 18500)
			local floors = {}
			for index, x in { -10, 10 } do
				local floor = Instance.new("Part")
				floor.Name = "RaisedFloor_" .. index
				floor.Anchored = true
				floor:SetAttribute("CartDrivableGround", true)
				floor.Size = Vector3.new(20, 2, 30)
				floor.Position = origin + Vector3.new(x, -0.95, 0)
				floor.Parent = geometry
				floors[index] = floor
			end
			local ok, failure = xpcall(function()
				fixture(function(_, prepare)
					local source = CFrame.new(origin + Vector3.new(-5, 0, 0))
					local staged = prepare(nil, source)
					local box, size = staged.Model:GetBoundingBox()
					local oldPose = staged.Model:GetPivot() + Vector3.new(0, -(box.Y - size.Y / 2), 0)
					staged.Model:PivotTo(oldPose)
					local query = RaycastParams.new()
					query.FilterType = Enum.RaycastFilterType.Include
					query.FilterDescendantsInstances = { geometry }
					query.RespectCanCollide = true
					local legacyHit =
						workspace:Blockcast(staged.Model:GetBoundingBox(), size, Vector3.new(10, 0, 0), query)
					expect(legacyHit and legacyHit.Instance).to.equal(floors[2])
					local grounded = World.FindSafeReleasePose(staged, source, {}, true)
					expect(grounded).never.to.equal(nil)
					staged.Model:PivotTo(assert(grounded, "Expected grounded pilot placement"))
					local groundedBox, groundedSize = staged.Model:GetBoundingBox()
					expect(groundedBox.Y - groundedSize.Y / 2 >= 0.149).to.equal(true)
					expect(workspace:Blockcast(groundedBox, groundedSize, Vector3.new(10, 0, 0), query)).to.equal(nil)
				end)
			end, debug.traceback)
			geometry:Destroy()
			if not ok then
				error(failure, 0)
			end
		end)

		it("creates every pilot through one species-aware world factory", function()
			local cleanupTemplates = provisionPilotTemplates()
			Roaming.Start()
			local expected = { "BRT_007", "BRT_011", "BRT_015", "BRT_016" }
			local pilots = World.GetPilotSpecies()
			local created, ids = {}, {}
			local ok, failure = xpcall(function()
				for index, speciesId in expected do
					expect(pilots[index]).to.equal(speciesId)
					local pose = CFrame.new(200 + index * 12, 20, 200)
					local record, recordReason = World.CreateWorldRecord(speciesId, "SPEC_PILOT_" .. speciesId, pose)
					assert(record, recordReason)
					expect(record.BrainrotId).to.equal(speciesId)
					expect(ids[record.ItemId]).to.equal(nil)
					ids[record.ItemId] = true
					local prepared, prepareReason = World.PrepareWorldRepresentation(record, pose)
					assert(prepared, prepareReason)
					local model, activationReason = World.ActivatePreparedWorld(prepared)
					assert(model, activationReason)
					table.insert(created, model)
					expect(model:GetAttribute("BrainrotId")).to.equal(speciesId)
					expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
					expect(World.TrySleep(model)).to.equal(true)
					expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
					expect(World.ResumeWorld(model)).to.equal(true)
					expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
				end

				local first = assert(World.CreateWorldRecord("BRT_007", "SPEC_DUPLICATE_A", CFrame.new()))
				local second = assert(World.CreateWorldRecord("BRT_007", "SPEC_DUPLICATE_B", CFrame.new()))
				expect(first.ItemId == second.ItemId).to.equal(false)
				expect(first.BrainrotId).to.equal(second.BrainrotId)
				expect(World.CreateWorldRecord("BRT_999", "SPEC_INVALID", CFrame.new())).to.equal(nil)
			end, debug.traceback)
			for _, model in created do
				World.DestroyWorldForTesting(model:GetAttribute("ItemId"))
				model:Destroy()
				World.Unregister(model)
			end
			cleanupTemplates()
			if not ok then
				error(failure, 0)
			end
		end)

		it("retires only the exact owner-secured dropped original after its durable departure outcome", function()
			fixture(function(record, prepare)
				local secured = table.clone(record)
				secured.Metadata = { DurableOwnerUserId = 778899, Mutation = { Name = "Original", Quality = 3 } }
				local before = World.GetWildCount()
				local model = assert(World.ActivatePreparedWorld(prepare(secured, CFrame.new(970, 20, 970))))
				expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
				expect(World.GetWildCount()).to.equal(before)
				expect(#World.GetSecuredWorldRecords(778899)).to.equal(1)
				expect(World.RetireSecuredWorld(secured.ItemId, 778900)).to.equal(false)
				expect(World.GetWorldRecord(model).ItemId).to.equal(secured.ItemId)
				expect(World.RetireSecuredWorld(secured.ItemId, 778899)).to.equal(true)
				expect(#World.GetSecuredWorldRecords(778899)).to.equal(0)
				expect(World.RetireSecuredWorld(secured.ItemId, 778899)).to.equal(true)
				expect(World.GetWildCount()).to.equal(before)
			end, "BRT_007")
		end)

		it("counts sleep, pickup and world drop at the authoritative registry boundary", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local before = World.GetWildCount()
				local pose = CFrame.new(950, 20, 950)
				local model = assert(World.ActivatePreparedWorld(prepare(nil, pose)))
				expect(World.GetWildCount()).to.equal(before + 1)
				expect(World.TrySleep(model)).to.equal(true)
				expect(World.GetWildCount()).to.equal(before + 1)
				expect(World.ResumeWorld(model)).to.equal(true)
				expect(World.GetWildCount()).to.equal(before + 1)
				expect(World.TrySleep(model)).to.equal(true)

				local registeredRecord = assert(World.GetWorldRecord(model))
				expect(World.TakeSleepingWorld(model, registeredRecord)).to.equal(true)
				expect(World.GetWildCount()).to.equal(before + 1)
				model:Destroy()

				local droppedPreparation = prepare(registeredRecord, pose + Vector3.new(12, 0, 0))
				model = assert(World.ActivatePreparedWorld(droppedPreparation))
				expect(World.GetWildCount()).to.equal(before + 1)
				expect(World.GetWorldRecord(model).ItemId).to.equal(registeredRecord.ItemId)
				model:Destroy()
				World.Unregister(model)
				expect(World.GetWildCount()).to.equal(before + 1)
			end, "BRT_007")
		end)

		it("expires one shared sleep window at exactly ten server seconds without refresh", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local now = 0
				World._TestSetSleepClock(function()
					return now
				end)
				local ok, failure = xpcall(function()
					local before = World.GetWildCount()
					local model = assert(World.ActivatePreparedWorld(prepare()))
					expect(World.TrySleep(model)).to.equal(true)
					expect(model:GetAttribute("BrainrotSleepUntil")).to.equal(12)
					expect(model:GetAttribute("BrainrotLifecycleRevision")).to.equal(1)
					expect(World.GetWildCount()).to.equal(before + 1)

					now = 4
					expect(select(2, World.TrySleep(model))).to.equal("ALREADY_SLEEPING")
					expect(model:GetAttribute("BrainrotSleepUntil")).to.equal(12)
					expect(model:GetAttribute("BrainrotLifecycleRevision")).to.equal(1)

					now = 11.999
					expect(World.ProcessSleepExpirations()).to.equal(0)
					expect(select(2, World.GetWorldRecord(model))).to.equal("WorldSleeping")
					now = 12
					expect(World.ProcessSleepExpirations()).to.equal(1)
					expect(select(2, World.GetWorldRecord(model))).to.equal("WorldAwake")
					expect(model:GetAttribute("BrainrotSleepUntil")).to.equal(nil)
					expect(model:GetAttribute("BrainrotLifecycleRevision")).to.equal(2)
					expect(World.ProcessSleepExpirations()).to.equal(0)
					expect(World.GetWildCount()).to.equal(before + 1)
				end, debug.traceback)
				World._TestSetSleepClock(nil)
				if not ok then
					error(failure, 0)
				end
			end, "BRT_007")
		end)

		it("clears a natural territory only on successful pickup and never restores it on drop", function()
			fixture(function(sourceRecord, prepare)
				Roaming.Start()
				local natural = assert(NaturalTerritory.BindNaturalSpawn(sourceRecord, "Forest"))
				local originalId = natural.ItemId
				local pose = CFrame.new(960, 20, 960)
				local model = assert(World.ActivatePreparedWorld(prepare(natural, pose)))
				local registered = assert(World.GetWorldRecord(model))
				expect(registered.ItemId).to.equal(originalId)
				expect(NaturalTerritory.GetSpawnRegionId(registered)).to.equal("REGION_FOREST")
				expect(NaturalTerritory.GetTerritoryRegionId(registered)).to.equal("REGION_FOREST")

				expect(World.TrySleep(model)).to.equal(true)
				local sleeping = assert(World.GetWorldRecord(model))
				expect(NaturalTerritory.GetTerritoryRegionId(sleeping)).to.equal("REGION_FOREST")
				expect(World.ResumeWorld(model)).to.equal(true)
				local awake = assert(World.GetWorldRecord(model))
				expect(NaturalTerritory.GetTerritoryRegionId(awake)).to.equal("REGION_FOREST")
				expect(World.TrySleep(model)).to.equal(true)

				local controlled = assert(World.CreatePlayerControlledRecord(awake))
				local droppedPreparation = prepare(controlled, CFrame.new(1100, 20, 1100))
				local taken, committed = World.TakeSleepingWorld(model, awake, controlled)
				expect(taken).to.equal(true)
				assert(committed, "Pickup did not return the committed player-controlled record")
				expect(committed.ItemId).to.equal(originalId)
				expect(NaturalTerritory.GetSpawnRegionId(committed)).to.equal("REGION_FOREST")
				expect(NaturalTerritory.GetTerritoryRegionId(committed)).to.equal(nil)
				model:Destroy()

				local dropped = assert(World.ActivatePreparedWorld(droppedPreparation))
				local droppedRecord = assert(World.GetWorldRecord(dropped))
				expect(droppedRecord.ItemId).to.equal(originalId)
				expect(NaturalTerritory.GetSpawnRegionId(droppedRecord)).to.equal("REGION_FOREST")
				expect(NaturalTerritory.GetTerritoryRegionId(droppedRecord)).to.equal(nil)
				expect((dropped:GetPivot().Position - Vector3.new(1100, 20, 1100)).Magnitude < 0.001).to.equal(true)
				dropped:Destroy()
				World.Unregister(dropped)
			end, "BRT_007")
		end)

		it("stages inactive authority geometry and preserves frozen identity and nested metadata", function()
			fixture(function(record, prepare)
				local before = Roaming.GetDiagnostics().Registered
				local staged = prepare()
				expect(staged.Model.Parent).to.equal(nil)
				expect(World.GetWorldRecord(staged.Model)).to.equal(nil)
				expect(Roaming.GetDiagnostics().Registered).to.equal(before)
				record.Metadata.Mutation.Name = "Caller changed"
				local model = World.ActivatePreparedWorld(staged)
				assert(model, "Prepared model did not activate")
				local restored, state = World.GetWorldRecord(model)
				expect(restored.ItemId).to.equal(record.ItemId)
				expect(restored.Metadata.Mutation.Name).to.equal("Original")
				expect(state).to.equal("WorldAwake")
				expect(model.Body.CanQuery and model.Body.CanCollide and model.Body.Anchored).to.equal(true)
				expect(model.Body:HasTag("SPEC_WORLD_BODY")).to.equal(false) -- Template discovery tags never enter proxy clones.
				expect(model.Body.CaptureAttachment:IsA("Attachment")).to.equal(true)
				expect(math.abs(model:GetScale() - staged.Record.World.Scale) < 0.0001).to.equal(true)
				local height = VisualScale.GetVisualHeight(model)
				expect(math.abs(height - VisualScale.TARGET_HEIGHT_STUDS) <= VisualScale.TOLERANCE_STUDS).to.equal(true)
				expect(Roaming.GetDiagnostics().Registered).to.equal(before + 1)
				expect(World.ActivatePreparedWorld(staged)).to.equal(nil)
				expect(World.DiscardPreparedWorld(staged)).to.equal(false)
				expect(model.Parent ~= nil).to.equal(true)
			end)
		end)

		it("rejects live duplicate ownership and activates one same-ID replacement after retirement", function()
			fixture(function(record, prepare)
				local model = World.ActivatePreparedWorld(prepare())
				local snapshot = World.GetWorldRecord(model)
				local replacement = prepare(snapshot, CFrame.new(800, 30, -600))
				local result, reason = World.ActivatePreparedWorld(replacement)
				expect(result).to.equal(nil)
				expect(reason).to.equal("INDIVIDUAL_ALREADY_IN_WORLD")
				expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
				expect(replacement.Model.Parent).to.equal(nil)
				model:Destroy()
				World.Unregister(model)
				local restored = World.ActivatePreparedWorld(replacement)
				expect(World.GetWorldRecord(restored).ItemId).to.equal(record.ItemId)
				expect(World.GetWorldRecord(restored).World.SpawnPosition.X).to.equal(0)
				expect((restored:GetPivot().Position - Vector3.new(800, 30, -600)).Magnitude < 0.001).to.equal(true)
			end)
		end)

		it("does not let two prepared representations activate the same individual", function()
			fixture(function(_, prepare)
				local first, second = prepare(), prepare()
				local model = World.ActivatePreparedWorld(first)
				expect(World.ActivatePreparedWorld(second)).to.equal(nil)
				expect(World.DiscardPreparedWorld(second)).to.equal(true)
				expect(World.GetWorldRecord(model) ~= nil).to.equal(true)
			end)
		end)

		it("sleep/resume cycles cancel pending motion and never multiply controllers or speed", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local before = Roaming.GetDiagnostics().Registered
				local model = World.ActivatePreparedWorld(prepare())
				for _ = 1, 3 do
					expect(World.TrySleep(model)).to.equal(true)
					expect(World.TrySleep(model)).to.equal(false)
					local position = model:GetPivot().Position
					task.wait(3.1) -- longer than the ordinary maximum idle pause
					expect((model:GetPivot().Position - position).Magnitude < 0.0001).to.equal(true)
					expect(World.ResumeWorld(model)).to.equal(true)
					for _ = 1, 8 do
						expect(Roaming.Resume(model)).to.equal(true)
					end
					expect(Roaming.GetDiagnostics().Registered).to.equal(before + 1)
					local elapsed, travelled = 0, 0
					local previous = model:GetPivot().Position
					while elapsed < 4 do
						elapsed += task.wait(0.05)
						local current = model:GetPivot().Position
						travelled += (current - previous).Magnitude
						previous = current
					end
					expect(travelled > 0.1).to.equal(true)
					expect(travelled <= 6 * (elapsed + 0.2)).to.equal(true)
				end
			end)
		end)

		it("rebases ordinary roaming at release without changing original spawn metadata", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local model = World.ActivatePreparedWorld(prepare())
				local saved = World.GetWorldRecord(model)
				local pose = CFrame.new(500, 40, -500)
				local staged = prepare(saved, pose)
				model:Destroy()
				World.Unregister(model)
				local restored = World.ActivatePreparedWorld(staged)
				task.wait(4)
				local distance = (restored:GetPivot().Position - pose.Position).Magnitude
				expect(distance > 0.1 and distance <= 20.01).to.equal(true)
				expect(math.abs(restored:GetPivot().Position.Y - 40) < 0.001).to.equal(true)
				expect(World.GetWorldRecord(restored).World.SpawnPosition.Y).to.equal(20)
				-- It is an ordinary awake/queryable target, immediately sleepable again.
				expect(restored:GetAttribute("Captured")).to.equal(false)
				expect(World.TrySleep(restored)).to.equal(true)
			end)
		end)

		it("legacy capture pauses, but a restored clone cannot be deleted by its old callbacks", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local old = World.ActivatePreparedWorld(prepare())
				old:SetAttribute("Captured", true)
				old.Body.CanCollide = false
				local awake, reason = World.ResumeWorld(old)
				expect(awake).to.equal(false)
				expect(reason).to.equal("LEGACY_CAPTURE_REQUIRES_RESTORATION")
				local saved = World.GetWorldRecord(old)
				local staged = prepare(saved, CFrame.new(50, 20, 50))
				old.Parent = nil
				World.Unregister(old)
				local restored = World.ActivatePreparedWorld(staged)
				task.delay(0.1, function()
					old:Destroy()
				end)
				task.wait(0.3)
				expect(restored.Parent ~= nil).to.equal(true)
				expect(restored.Body.CanCollide).to.equal(true)
				expect(restored:GetAttribute("Captured")).to.equal(false)
				expect(World.GetWorldRecord(restored).ItemId).to.equal(saved.ItemId)
			end)
		end)

		it("unregister cancels an active task and does not silently rediscover a retired model", function()
			fixture(function(_, prepare)
				Roaming.Start()
				local before = Roaming.GetDiagnostics().Registered
				local model = World.ActivatePreparedWorld(prepare())
				task.wait(0.2)
				model.Parent = nil
				World.Unregister(model)
				local position = model:GetPivot().Position
				task.wait(1.1)
				expect((model:GetPivot().Position - position).Magnitude < 0.0001).to.equal(true)
				expect(Roaming.GetDiagnostics().Registered).to.equal(before)
				expect(Roaming.Resume(model)).to.equal(false)
			end)
		end)

		it("bad preparations leave source intact and discard retires only staging", function()
			fixture(function(record, prepare, template)
				local model = World.ActivatePreparedWorld(prepare())
				local staged = prepare()
				expect(World.DiscardPreparedWorld(staged)).to.equal(true)
				expect(World.ActivatePreparedWorld(staged)).to.equal(nil)
				expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
				local invalid = table.clone(record)
				invalid.ItemId = ""
				expect(World.PrepareWorldRepresentation(invalid, CFrame.new())).to.equal(nil)
				expect(World.PrepareWorldRepresentation(record, CFrame.new(0 / 0, 0, 0))).to.equal(nil)
				template.Body.CaptureAttachment:Destroy()
				-- Retired capture markers are optional; current queryable Body
				-- authority remains mandatory and a bad source never retires live IDs.
				local withoutLegacyMarker = prepare()
				expect(withoutLegacyMarker ~= nil).to.equal(true)
				expect(World.DiscardPreparedWorld(withoutLegacyMarker)).to.equal(true)
				local malformedMarker = Instance.new("Folder")
				malformedMarker.Name, malformedMarker.Parent = "CaptureAttachment", template.Body
				local withMalformedMarker = prepare()
				expect(withMalformedMarker ~= nil).to.equal(true)
				expect(World.DiscardPreparedWorld(withMalformedMarker)).to.equal(true)
				template.Body.CanQuery = false
				expect(World.PrepareWorldRepresentation(record, CFrame.new())).to.equal(nil)
				expect(World.GetWorldRecord(model).ItemId).to.equal(record.ItemId)
			end)
		end)
	end)
end
