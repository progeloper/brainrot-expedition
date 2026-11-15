--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Assets = require(script.Parent.Parent.Utility.CreatureAssetService)
	local Query = require(script.Parent.Parent.Utility.CreatureQueryService)
	local function fixture(callback)
		Query.Stop()
		local old = workspace:GetAttribute("Phase13LegacyCreatureReplication")
		workspace:SetAttribute("Phase13LegacyCreatureReplication", nil)
		local assets = RS:FindFirstChild("StudioAssets")
		local ownAssets = not assets
		if not assets then
			assets = Instance.new("Folder")
			assets.Name, assets.Parent = "StudioAssets", RS
		end
		local folder = assets:FindFirstChild("Brainrots")
		local ownFolder = not folder
		if not folder then
			folder = Instance.new("Folder")
			folder.Name, folder.Parent = "Brainrots", assets
		end
		local source = Instance.new("Model")
		source.Name = "SPEC_PRIVATE_QUERY"
		local root = Instance.new("Part")
		root.Name, root.Size, root.Transparency = "Root", Vector3.one * 0.5, 1
		root.CanQuery, root.Anchored, root.CanCollide, root.Parent = false, true, false, source
		source.PrimaryPart = root
		local body = Instance.new("Part")
		body.Name, body.Size, body.Anchored, body.Material, body.Parent =
			"Body", Vector3.new(2, 4, 2), true, Enum.Material.Wood, source
		for _, name in { "CaptureAttachment", "CargoAttachment" } do
			local a = Instance.new("Attachment")
			a.Name, a.Parent = name, body
		end
		local arm = Instance.new("WedgePart")
		arm.Name, arm.Size, arm.CFrame = "PeripheralArm", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0)
		arm.Anchored, arm.CanQuery, arm.CanCollide, arm.Material, arm.Parent =
			true, true, false, Enum.Material.Glacier, source
		local ignored = Instance.new("Part")
		ignored.Name, ignored.Size, ignored.CFrame = "NonQueryArt", Vector3.new(3, 3, 3), CFrame.new(-5, 0, 0)
		ignored.Anchored, ignored.CanQuery, ignored.Parent = true, false, source
		source.Parent = folder
		local proxy, reason = Assets.CreateProxy(source.Name)
		assert(proxy, reason)
		proxy:SetAttribute("BrainrotId", source.Name)
		proxy.Parent = workspace
		local full = source:Clone()
		full.Parent = workspace
		local ok, why = xpcall(function()
			callback(source, proxy, full)
		end, debug.traceback)
		Query.Stop()
		proxy:Destroy()
		full:Destroy()
		source:Destroy()
		if ownFolder then
			folder:Destroy()
		end
		if ownAssets then
			assets:Destroy()
		end
		workspace:SetAttribute("Phase13LegacyCreatureReplication", old)
		assert(ok, why)
	end
	local function reference(full, origin, direction)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { full }
		return workspace:Raycast(origin, direction, params)
	end
	describe("Private exact authored creature query scene", function()
		it(
			"hits a peripheral native shape missing from the replicated proxy at the identical point normal and material",
			function()
				fixture(function(source, proxy, full)
					local ok, stats = Query.SyncWorld({ proxy })
					expect(ok).to.equal(true)
					expect(stats.tracked).to.equal(1)
					local origin, direction = Vector3.new(5, 0, 10), Vector3.new(0, 0, -20)
					local original =
						assert(reference(full, origin, direction), "Authored peripheral reference ray must hit")
					local result = assert(Query.Raycast(origin, direction), "Private peripheral query must hit")
					expect(result.Instance).to.equal(proxy.Body)
					expect(result.QueryPartName).to.equal("PeripheralArm")
					expect(result.QueryPartHuntEligible).to.equal(true)
					expect((result.Position - original.Position).Magnitude < 0.0001).to.equal(true)
					expect((result.Normal - original.Normal).Magnitude < 0.0001).to.equal(true)
					expect(math.abs(result.Distance - original.Distance) < 0.0001).to.equal(true)
					expect(result.Material).to.equal(original.Material)
					expect(proxy:FindFirstChild("PeripheralArm")).to.equal(nil)
					expect(Query.GetDiagnostics().queryParts).to.equal(2)
					expect(Query.GetDiagnostics().privateScene).to.equal(true)
					expect(source.PeripheralArm.Material).to.equal(Enum.Material.Glacier)
				end)
			end
		)
		it("tracks current native rotation and absolute scale without changing the original query flags", function()
			fixture(function(source, proxy, full)
				assert(Query.Track(proxy, source.Name), "Proxy query must track")
				for _, scale in { 1, 2, 0.7 } do
					local pose = CFrame.new(100, 10, 50) * CFrame.Angles(0, math.pi / 2, 0)
					proxy:ScaleTo(scale)
					proxy:PivotTo(pose)
					full:ScaleTo(scale)
					full:PivotTo(pose)
					assert(Query.Track(proxy, source.Name), "Existing query transform must update")
					local arm = full.PeripheralArm
					local origin = arm.Position + arm.CFrame.LookVector * 20
					local direction = -arm.CFrame.LookVector * 40
					local expected = assert(reference(full, origin, direction), "Rotated reference must hit")
					local result = assert(Query.Raycast(origin, direction), "Rotated private query must hit")
					expect((result.Position - expected.Position).Magnitude < 0.001).to.equal(true)
					expect((result.Normal - expected.Normal).Magnitude < 0.001).to.equal(true)
				end
				expect(source.NonQueryArt.CanQuery).to.equal(false)
				expect(source.PeripheralArm.CanQuery).to.equal(true)
			end)
		end)
		it(
			"maps include exclude ancestor Body-only and original collision filters and cleans all tracked resources",
			function()
				fixture(function(source, proxy, _full)
					assert(Query.Track(proxy, source.Name), "Query filter fixture must track")
					local origin, direction = Vector3.new(5, 0, 10), Vector3.new(0, 0, -20)
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Include
					params.FilterDescendantsInstances = { proxy }
					expect(Query.Raycast(origin, direction, params) ~= nil).to.equal(true)
					params.FilterType = Enum.RaycastFilterType.Exclude
					expect(Query.Raycast(origin, direction, params)).to.equal(nil)
					params.FilterDescendantsInstances = { proxy.Body }
					expect(Query.Raycast(origin, direction, params) ~= nil).to.equal(true)
					params.FilterType = Enum.RaycastFilterType.Include
					expect(Query.Raycast(origin, direction, params)).to.equal(nil)
					params.FilterDescendantsInstances = { workspace }
					expect(Query.Raycast(origin, direction, params) ~= nil).to.equal(true)
					params.RespectCanCollide = true
					expect(Query.Raycast(origin, direction, params)).to.equal(nil)
					local ok, stats = Query.SyncWorld({})
					expect(ok).to.equal(true)
					expect(stats.removed).to.equal(1)
					expect(Query.GetDiagnostics().entities).to.equal(0)
					assert(Query.Track(proxy, source.Name), "Query must allow retrack after explicit cleanup")
					proxy.Parent = nil
					task.wait()
					expect(Query.GetDiagnostics().entities).to.equal(0)
					Query.Stop()
					local diagnostic = Query.GetDiagnostics()
					expect(diagnostic.connections).to.equal(0)
					expect(diagnostic.prototypes).to.equal(0)
					expect(diagnostic.queryParts).to.equal(0)
					expect(diagnostic.privateScene).to.equal(false)
				end)
			end
		)
		it(
			"retains originally queryable invisible helper shapes outside hunt bounds and releases source-owned cache on destruction",
			function()
				fixture(function(source, proxy, full)
					local helper = Instance.new("Part")
					helper.Name, helper.Size, helper.CFrame = "OldHitbox", Vector3.new(2, 2, 2), CFrame.new(-7, 0, 0)
					helper.Transparency, helper.CanQuery, helper.CanCollide, helper.Anchored, helper.Parent =
						1, true, false, true, source
					local copy = helper:Clone()
					copy.Parent = full
					assert(Query.Track(proxy, source.Name), "Helper query fixture must track")
					local origin, direction = Vector3.new(-7, 0, 10), Vector3.new(0, 0, -20)
					local expected =
						assert(reference(full, origin, direction), "Original invisible query helper must raycast")
					local result =
						assert(Query.Raycast(origin, direction), "Private invisible query helper must raycast")
					expect(result.QueryPartName).to.equal("OldHitbox")
					expect(result.QueryPartHuntEligible).to.equal(false)
					expect((result.Position - expected.Position).Magnitude < 0.001).to.equal(true)
					source:Destroy()
					task.wait()
					expect(Query.GetDiagnostics().entities).to.equal(0)
					expect(Query.GetDiagnostics().prototypes).to.equal(0)
				end)
			end
		)
	end)
end
