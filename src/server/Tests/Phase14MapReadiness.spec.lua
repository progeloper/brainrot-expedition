--!nocheck
-- Disposable engine fixtures. Native streaming/aim/frame measurements remain
-- separate acceptance evidence; these assert policy and lifecycle regressions.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Policy = require(RS.Shared.Utility.RegionPresentationPolicy)
	local Approach = require(RS.Shared.Utility.RegionStreamingApproachPolicy)
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Visibility = require(Client.Controllers.RegionVisibilityController)
	local Binding = require(Client.Utility.RemoteDependencyBinding)
	local Slots = require(RS.Shared.Utility.BaseSlotPresentation)
	local function await(predicate)
		local expires = os.clock() + 1
		repeat
			if predicate() then
				return true
			end
			task.wait()
		until os.clock() >= expires
		return predicate()
	end
	describe("Phase14 map navigation and late functional dependencies", function()
		it("keeps the128stud minimum and supplied-input protected-radius arithmetic", function()
			expect(Policy.ProtectedRadius(0, 0, 0)).to.equal(128)
			expect(Policy.ProtectedRadius(14, 1, 0)).to.equal(128)
			expect(Policy.ProtectedRadius(0, 40, 0)).to.equal(128)
			expect(math.abs(Policy.ProtectedRadius(125, 81.675, 36) - 231.35) < 0.000001).to.equal(true)
		end)
		it("retains three originally hidden unlocked Forest floors from Camp and protects locked geometry", function()
			Visibility.Stop()
			local map = Instance.new("Folder")
			map.Name = "MapBlockout"
			map.Parent = workspace
			local forest = Instance.new("Folder")
			forest.Name = "Forest"
			forest.Parent = map
			local rows = {
				{ "Floor_R2_C2", Vector3.new(-387, -1.95, -384), Vector3.new(240, 4, 180) },
				{ "Floor_R2_C3", Vector3.new(-19, -1.95, -384), Vector3.new(496, 4, 180) },
				{ "Floor_R3_C2", Vector3.new(-387, -1.95, -46), Vector3.new(240, 4, 496) },
			}
			for _, row in rows do
				local floor = Instance.new("Part")
				floor.Name, floor.Position, floor.Size = row[1], row[2], row[3]
				floor.Anchored, floor.CanCollide = true, true
				floor:SetAttribute("LayoutRole", "Floor")
				floor:SetAttribute("GeneratedBy", "CreateBasicMap_v1")
				floor.Parent = forest
				Visibility._CacheRegionForTesting(floor)
			end
			Visibility._AcceptContextForTesting({
				kind = "Context",
				sequence = 1,
				regionId = "REGION_CAMP",
				unlocked = { REGION_CAMP = true, REGION_FOREST = true },
			})
			local distanceBefore = Visibility.GetDiagnostics().distanceEvaluations
			Visibility._SyncForTesting()
			expect(Visibility.GetDiagnostics().distanceEvaluations).to.equal(distanceBefore)
			for _, floor in forest:GetChildren() do
				expect(floor.LocalTransparencyModifier).to.equal(0)
			end
			Visibility._AcceptContextForTesting({
				kind = "Context",
				sequence = 2,
				regionId = "REGION_CAMP",
				unlocked = { REGION_CAMP = true },
			})
			Visibility._SyncForTesting()
			for _, floor in forest:GetChildren() do
				expect(floor.LocalTransparencyModifier).to.equal(1)
			end
			Visibility.Stop()
			map:Destroy()
		end)
		it("applies arriving map records immediately and keeps locked regions fail closed", function()
			Visibility.Stop()
			local map = Instance.new("Folder")
			map.Name = "MapBlockout"
			map.Parent = workspace
			local forest = Instance.new("Folder")
			forest.Name = "Forest"
			forest.Parent = map
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide = true, true
			part:SetAttribute("LayoutRole", "Floor")
			part.Parent = forest
			Visibility._AcceptContextForTesting({
				kind = "Context",
				sequence = 1,
				regionId = "REGION_CAMP",
				unlocked = { REGION_CAMP = true },
			})
			local began = os.clock()
			Visibility._RememberForTesting(part)
			expect(part.LocalTransparencyModifier).to.equal(1)
			local receipt = Visibility.GetPresentationState(part)
			expect(receipt.appliedAt >= receipt.arrivedAt).to.equal(true)
			expect(receipt.appliedAt - began < 0.1).to.equal(true)
			Visibility._AcceptContextForTesting({
				kind = "Context",
				sequence = 2,
				regionId = "REGION_CAMP",
				unlocked = { REGION_CAMP = true, REGION_FOREST = true },
			})
			Visibility._SyncForTesting()
			expect(part.LocalTransparencyModifier).to.equal(0)
			local generation = receipt.generation
			Visibility._ForgetForTesting(part)
			expect(Visibility.GetPresentationState(part)).to.equal(nil)
			Visibility._RememberForTesting(part)
			expect(Visibility.GetPresentationState(part).generation > generation).to.equal(true)
			Visibility.Stop()
			map:Destroy()
			expect(Visibility.GetDiagnostics().cachedSpatialRecords).to.equal(0)
		end)
		it("refreshes moved optional scenery without a full pass and expires idle release grace", function()
			Visibility.Stop()
			local camera = Instance.new("Camera")
			local map = Instance.new("Folder")
			map.Name = "MapBlockout"
			map.Parent = workspace
			local forest = Instance.new("Folder")
			forest.Name = "Forest"
			forest.Parent = map
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide = true, false
			part.Position = Vector3.new(1000, 0, 0)
			part.Parent = forest
			local ok, reason = xpcall(function()
				Visibility._AcceptContextForTesting({
					kind = "Context",
					sequence = 1,
					regionId = "REGION_CAMP",
					unlocked = { REGION_CAMP = true, REGION_FOREST = true },
				})
				camera.CFrame = CFrame.new(0, 0, 0)
				Visibility._RememberForTesting(part)
				Visibility._SpatialForTesting(camera)
				expect(part.LocalTransparencyModifier).to.equal(1)
				camera.CFrame = CFrame.new(900, 0, 0)
				Visibility._SpatialForTesting(camera)
				expect(part.LocalTransparencyModifier).to.equal(0)
				local passes = Visibility.GetDiagnostics().spatialPasses
				Visibility._SpatialForTesting(camera)
				expect(Visibility.GetDiagnostics().spatialPasses).to.equal(passes)
				camera.CFrame = CFrame.new(0, 0, 0)
				Visibility._SpatialForTesting(camera)
				expect(part.LocalTransparencyModifier).to.equal(0)
				expect(type(Visibility.GetPresentationState(part).optionalReleaseAt)).to.equal("number")
				task.wait(2.05)
				Visibility._SpatialForTesting(camera)
				expect(part.LocalTransparencyModifier).to.equal(1)
				camera.CFrame = CFrame.new(900, 0, 0)
				Visibility._SpatialForTesting(camera)
				expect(part.LocalTransparencyModifier).to.equal(0)
				Visibility._AcceptContextForTesting({
					kind = "Context",
					sequence = 2,
					regionId = "REGION_CAMP",
					unlocked = { REGION_CAMP = true },
				})
				Visibility._SyncForTesting()
				expect(part.LocalTransparencyModifier).to.equal(1)
			end, debug.traceback)
			Visibility.Stop()
			camera:Destroy()
			map:Destroy()
			if not ok then
				error(reason)
			end
		end)
		it("retains optional scenery across release jitter and releases after two seconds beyond the band", function()
			local visible, releaseAt = Policy.OptionalVisible(false, nil, 100, 128, 0)
			expect(visible).to.equal(true)
			expect(releaseAt).to.equal(nil)
			visible, releaseAt = Policy.OptionalVisible(visible, releaseAt, 190, 128, 1)
			expect(visible).to.equal(true)
			expect(releaseAt).to.equal(nil)
			visible, releaseAt = Policy.OptionalVisible(visible, releaseAt, 193, 128, 2)
			expect(releaseAt).to.equal(4)
			visible, releaseAt = Policy.OptionalVisible(visible, releaseAt, 193, 128, 3.999)
			expect(visible).to.equal(true)
			visible, releaseAt = Policy.OptionalVisible(visible, releaseAt, 193, 128, 4)
			expect(visible).to.equal(false)
			expect(releaseAt).to.equal(nil)
			visible, releaseAt = Policy.OptionalVisible(true, 5, 128, 128, 4.5)
			expect(visible).to.equal(true)
			expect(releaseAt).to.equal(nil)
		end)
		it("measures long rotated road bounds instead of a distant group pivot", function()
			local frame = CFrame.new(1000, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			local edge = frame:PointToWorldSpace(Vector3.new(0, 0, 495))
			expect(Policy.DistanceToBounds(edge, frame, Vector3.new(20, 4, 1000))).to.equal(0)
			expect(Policy.StaticVisible("REGION_FOREST", "REGION_CAMP", { REGION_FOREST = true }, false, 0, 96)).to.equal(
				true
			)
			expect(Policy.StaticVisible("REGION_BEACH", "REGION_CAMP", { REGION_FOREST = true }, true, 0, 96)).to.equal(
				false
			)
			expect(Policy.ProtectedRadius(125, 81.675, 36)).to.equal(231.35)
		end)
		it("restores authored local visibility before twenty forget and re-entry cycles", function()
			Visibility.Stop()
			local model = Instance.new("Model")
			model:SetAttribute("RegionId", "REGION_FOREST")
			model.Parent = workspace
			local part = Instance.new("Part")
			part.Parent = model
			for _ = 1, 20 do
				Visibility._ApplyHiddenForTesting(part, true)
				expect(part.LocalTransparencyModifier).to.equal(1)
				Visibility._ForgetForTesting(part)
				expect(part.LocalTransparencyModifier).to.equal(0)
				Visibility._ApplyHiddenForTesting(part, false)
				expect(part.LocalTransparencyModifier).to.equal(0)
			end
			Visibility.Stop()
			model:Destroy()
			expect(Visibility.GetDiagnostics().cachedRecords).to.equal(0)
			expect(Visibility.GetDiagnostics().activeBindingConnections).to.equal(0)
		end)
		it("does not resurrect a server-locked base label during entry, forget or stop", function()
			Visibility.Stop()
			local base = Instance.new("Model")
			base:SetAttribute("BasePresentationManaged", true)
			base:SetAttribute("BasePresentationState", "1:44:2:12")
			base.Parent = workspace
			local slot = Instance.new("Part")
			slot.Parent = base
			local gui = Instance.new("SurfaceGui")
			gui.Enabled = true
			gui.Parent = slot
			Slots.CaptureGroup(slot)
			slot:SetAttribute("BaseSlotIndex", 48)
			slot:SetAttribute("BaseRequiredStage", 3)
			slot:SetAttribute("BaseSlotState", "1:44:2:12")
			gui.Enabled = false
			Visibility._ApplyHiddenForTesting(gui, false)
			expect(gui.Enabled).to.equal(false)
			Visibility._ForgetForTesting(gui)
			expect(gui.Enabled).to.equal(false)
			Visibility._ApplyHiddenForTesting(gui, false)
			Visibility.Stop()
			expect(gui.Enabled).to.equal(false)
			base:Destroy()
		end)
		it("evaluates a shared semantic group on mutations and retains atomic owner and revision checks", function()
			Visibility.Stop()
			local base = Instance.new("Model")
			base:SetAttribute("BasePresentationManaged", true)
			base:SetAttribute("OwnerUserId", 44)
			base:SetAttribute("BaseOwnershipRevision", 2)
			base:SetAttribute("BasePresentationState", "1:44:2:12")
			base.Parent = workspace
			local slot = Instance.new("Model")
			slot:SetAttribute("BaseRequiredStage", 0)
			slot:SetAttribute("BaseSlotIndex", 1)
			slot:SetAttribute("BaseSlotState", "1:44:2:12")
			slot.Parent = base
			local labels = {}
			for _ = 1, 8 do
				local part = Instance.new("Part")
				part.Parent = slot
				local gui = Instance.new("SurfaceGui")
				gui.Parent = part
				Slots.Capture(gui)
				Visibility._ApplyHiddenForTesting(gui, false)
				table.insert(labels, gui)
			end
			local evaluations = Visibility.GetDiagnostics().semanticEvaluations
			for _ = 1, 20 do
				Visibility._SyncForTesting()
				Visibility._EnforceHiddenForTesting()
			end
			expect(Visibility.GetDiagnostics().semanticEvaluations).to.equal(evaluations)
			base:SetAttribute("OwnerUserId", 55)
			expect(await(function()
				return Visibility._RecordCacheForTesting(labels[1]).slotActive == false
			end)).to.equal(true)
			expect(Visibility.GetDiagnostics().semanticEvaluations).to.equal(evaluations + 1)
			for _, gui in labels do
				expect(gui.Enabled).to.equal(false)
			end
			base:SetAttribute("BasePresentationState", "1:55:3:12")
			slot:SetAttribute("BaseSlotState", "1:55:3:12")
			task.wait()
			expect(Visibility._RecordCacheForTesting(labels[1]).slotActive).to.equal(false)
			base:SetAttribute("BaseOwnershipRevision", 3)
			expect(await(function()
				return Visibility._RecordCacheForTesting(labels[1]).slotActive == true
			end)).to.equal(true)
			Visibility._SyncForTesting()
			expect(labels[1].Enabled).to.equal(true)
			base:SetAttribute("BasePresentationState", "0:55:3:0")
			expect(await(function()
				return labels[1].Enabled == false
			end)).to.equal(true)
			Visibility.Stop()
			base:Destroy()
			expect(Visibility.GetDiagnostics().ancestorBindingGroups).to.equal(0)
			expect(Visibility.GetDiagnostics().semanticBindingGroups).to.equal(0)
			expect(Visibility.GetDiagnostics().activeBindingConnections).to.equal(0)
		end)
		it("rebinds late semantic promotion, authored content changes and ancestor reparenting", function()
			Visibility.Stop()
			local plain = Instance.new("Model")
			plain.Parent = workspace
			local base = Instance.new("Model")
			base:SetAttribute("BasePresentationManaged", true)
			base:SetAttribute("OwnerUserId", 44)
			base:SetAttribute("BaseOwnershipRevision", 2)
			base:SetAttribute("BasePresentationState", "1:44:2:12")
			base.Parent = workspace
			local slot = Instance.new("Model")
			slot.Parent = base
			local part = Instance.new("Part")
			part.Parent = slot
			local gui = Instance.new("SurfaceGui")
			gui.Parent = part
			Slots.CaptureGroup(part)
			Visibility._ApplyHiddenForTesting(part, false)
			Visibility._ApplyHiddenForTesting(gui, false)
			expect(Visibility._RecordCacheForTesting(gui).slotActive).to.equal(nil)
			slot:SetAttribute("BaseSlotIndex", 19)
			slot:SetAttribute("BaseSlotState", "1:44:2:12")
			slot:SetAttribute("BaseRequiredStage", 1)
			expect(await(function()
				return Visibility._RecordCacheForTesting(gui).slotActive == false and not gui.Enabled
			end)).to.equal(true)
			expect(part.LocalTransparencyModifier).to.equal(1)
			part.Parent = plain
			expect(await(function()
				return Visibility._RecordCacheForTesting(gui).slotActive == nil
			end)).to.equal(true)
			Visibility._SyncForTesting()
			expect(gui.Enabled).to.equal(true)
			expect(part.LocalTransparencyModifier).to.equal(0)
			Slots.SetContentEnabled(gui, false)
			expect(await(function()
				return gui.Enabled == false
			end)).to.equal(true)
			Slots.SetContentEnabled(gui, true)
			expect(await(function()
				return gui.Enabled == true
			end)).to.equal(true)
			part.Parent = slot
			expect(await(function()
				return Visibility._RecordCacheForTesting(gui).slotActive == false and not gui.Enabled
			end)).to.equal(true)
			Visibility.Stop()
			base:Destroy()
			plain:Destroy()
		end)
		it("registers late stored ancestors, clears renamed and proxy membership and skips empty LOD scans", function()
			Visibility.Stop()
			local model = Instance.new("Model")
			model.Name = "Stored_LateFixture"
			model.Parent = workspace
			local part = Instance.new("Part")
			part.Parent = model
			Visibility._ApplyHiddenForTesting(part, false)
			expect(Visibility._RecordCacheForTesting(part).stored).to.equal(nil)
			Visibility._CacheRegionForTesting(part)
			expect(Visibility._RecordCacheForTesting(part).stored).to.equal(model)
			expect(Visibility.GetDiagnostics().cachedStoredRecords).to.equal(1)
			model.Name = "UnstoredFixture"
			expect(await(function()
				return Visibility._RecordCacheForTesting(part).stored == nil
			end)).to.equal(true)
			local visited = Visibility.GetDiagnostics().storedRecordVisits
			for _ = 1, 20 do
				Visibility._SyncLODForTesting()
			end
			expect(Visibility.GetDiagnostics().storedRecordVisits).to.equal(visited)
			expect(Visibility.GetDiagnostics().cachedStoredRecords).to.equal(0)
			model.Name = "Stored_ReturnFixture"
			expect(await(function()
				return Visibility._RecordCacheForTesting(part).stored == model
			end)).to.equal(true)
			model:SetAttribute("CreatureProxy", true)
			expect(await(function()
				return Visibility._RecordCacheForTesting(part).stored == nil
			end)).to.equal(true)
			Visibility._ForgetForTesting(part)
			expect(Visibility.GetDiagnostics().activeBindingConnections).to.equal(0)
			Visibility.Stop()
			model:Destroy()
		end)
		it("reports a bounded missing dependency then binds late and replacement generations once", function()
			local root = Instance.new("Folder")
			local signal = Instance.new("BindableEvent")
			local calls, events, states = 0, 0, {}
			local began, controlAt = os.clock(), nil
			local control = task.delay(0.01, function() controlAt = os.clock() - began end)
			local binding
			local ok, failure = xpcall(function()
				binding = Binding.new({
					Root = root,
					Name = "SleepRequest",
					Timeout = 0.01,
					OnState = function(status, reason)
						table.insert(states, { status, reason, os.clock() - began })
					end,
					OnRemote = function(remote)
						if not remote then
							return nil
						end
						calls += 1
						return signal.Event:Connect(function()
							events += 1
						end)
					end,
				})
				expect(await(function()
					return binding.state == "Unavailable"
				end)).to.equal(true)
				expect(binding.reason).to.equal("MISSING_REMOTE_SleepRequest")
				expect(states[1][1]).to.equal("Loading")
				expect(states[#states][1]).to.equal("Unavailable")
				local folder = Instance.new("Folder")
				folder.Name = "Remotes"
				folder.Parent = root
				for cycle = 1, 20 do
					local remote = Instance.new("RemoteEvent")
					remote.Name = "SleepRequest"
					remote.Parent = folder
					expect(await(function()
						return binding.remote == remote
					end)).to.equal(true)
					expect(binding.state).to.equal("Ready")
					expect(calls).to.equal(cycle)
					signal:Fire()
					expect(await(function()
						return events == cycle
					end)).to.equal(true)
					remote:Destroy()
					expect(await(function()
						return binding.remote == nil
					end)).to.equal(true)
					signal:Fire()
					task.wait()
					expect(events).to.equal(cycle)
				end
				binding:Destroy()
				local remote = Instance.new("RemoteEvent")
				remote.Name = "SleepRequest"
				remote.Parent = folder
				task.wait()
				signal:Fire()
				task.wait()
				expect(calls).to.equal(20)
				expect(events).to.equal(20)
			end, debug.traceback)
			if not ok then
				local lastStates = {}
				for index = math.max(1, #states - 7), #states do table.insert(lastStates, states[index]) end
				script:SetAttribute("P14R3LateRemoteFailureJSON", game:GetService("HttpService"):JSONEncode({
					elapsed = os.clock() - began, controlDelayAt = controlAt,
					controlTaskStatus = coroutine.status(control), stateCount = #states, states = lastStates,
					state = binding and binding.state, reason = binding and binding.reason,
					destroyed = binding and binding.destroyed, hasRemote = binding and binding.remote ~= nil,
					rootChildren = #root:GetChildren(), calls = calls, events = events,
				}))
			end
			local cleanupOK, cleanupFailure = true, nil
			if binding then cleanupOK, cleanupFailure = pcall(binding.Destroy) end
			root:Destroy()
			signal:Destroy()
			if coroutine.status(control) ~= "dead" then pcall(task.cancel, control) end
			assert(ok, failure)
			assert(cleanupOK, cleanupFailure)
		end)
		it(
			"limits approach requests, permits one failed retry and preserves one outstanding during transitions",
			function()
				local state = {}
				local ok, first = Approach.TryRequest(state, "Beach:in", 0)
				expect(ok).to.equal(true)
				expect(Approach.TryRequest(state, "Beach:in", 100)).to.equal(false)
				expect(Approach.CompleteRequest(state, first, false)).to.equal(true)
				expect(Approach.TryRequest(state, "Beach:in", 1.99)).to.equal(false)
				local retry, second = Approach.TryRequest(state, "Beach:in", 2)
				expect(retry).to.equal(true)
				Approach.CompleteRequest(state, second, false)
				expect(Approach.TryRequest(state, "Beach:in", 100)).to.equal(false)
				Approach.TryRequest(state, nil, 101)
				local entered, pending = Approach.TryRequest(state, "Beach:out", 102)
				expect(entered).to.equal(true)
				expect(Approach.TryRequest(state, "Swamp:in", 104)).to.equal(false)
				expect(Approach.CompleteRequest(state, pending, true)).to.equal(false)
				local changed, latest = Approach.TryRequest(state, "Swamp:in", 104)
				expect(changed).to.equal(true)
				Approach.CompleteRequest(state, latest, true)
				expect(Approach.TryRequest(state, "Swamp:in", 1000)).to.equal(false)
				expect(Approach.RequestTimeout).to.equal(5)
			end
		)
		it("binds only the explicitly required functional RemoteFunction class", function()
			local root = Instance.new("Folder")
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = root
			local wrong = Instance.new("RemoteEvent")
			wrong.Name = "RetentionRequest"
			wrong.Parent = folder
			local bound = nil
			local binding = Binding.new({
				Root = root,
				Name = "RetentionRequest",
				ClassName = "RemoteFunction",
				OnRemote = function(remote)
					bound = remote
					return nil
				end,
			})
			expect(binding.state).to.equal("Unavailable")
			expect(bound).to.equal(nil)
			wrong:Destroy()
			local valid = Instance.new("RemoteFunction")
			valid.Name = "RetentionRequest"
			valid.Parent = folder
			expect(await(function()
				return bound == valid
			end)).to.equal(true)
			expect(binding.state).to.equal("Ready")
			binding:Destroy()
			root:Destroy()
		end)
	end)
end
