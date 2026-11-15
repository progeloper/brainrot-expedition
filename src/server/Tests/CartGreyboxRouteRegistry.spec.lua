--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")

	local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
	local PerformanceIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxPerformanceIds)
	local SectionIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxSectionIds)
	local CartGreyboxValidationRuntime =
		require(script.Parent.Parent.Utility.CartGreyboxValidationRuntime)
	local RuntimeFolders = require(script.Parent.Parent.Utility.RuntimeFolders)
	local CartSpawnRegistry = require(script.Parent.Parent.Services.CartSpawnRegistry)
	local CartGreyboxRouteSystem = require(script.Parent.Parent.Systems.CartGreyboxRouteSystem)

	local function createCanonicalSpawn(spawnFolder: Folder): BasePart
		local marker = Instance.new("Part")

		marker.Name = "DevelopmentSpawn"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CFrame = CFrame.new(0, 10, 0)
		marker:SetAttribute("SpawnId", CartGreybox.CanonicalSpawnId)
		marker:SetAttribute("CartId", CartGreybox.CartId)
		marker:SetAttribute("Enabled", true)
		marker:SetAttribute("Priority", 0)
		marker.Parent = spawnFolder

		return marker
	end

	local function createRuntimeCart(parent: Folder, name: string, position: Vector3): Model
		local cart = Instance.new("Model")

		cart.Name = name
		cart.Parent = parent

		local root = Instance.new("Part")

		root.Name = "Root"
		root.Anchored = true
		root.Position = position
		root.Parent = cart

		return cart
	end

	local function cleanWorkspace()
		CartGreyboxRouteSystem:Stop()
		CartSpawnRegistry:Stop()

		local spawnFolder = Workspace:FindFirstChild("CartSpawns")

		if spawnFolder ~= nil then
			spawnFolder:Destroy()
		end

		local runtime = Workspace:FindFirstChild("Runtime")

		if runtime ~= nil and #runtime:GetChildren() == 0 then
			runtime:Destroy()
		end
	end

	describe("CartGreybox route registry lifecycle", function()
		it("selects free lanes and replaces registry records across route restart", function()
			cleanWorkspace()

			local succeeded, failure = pcall(function()
				local spawnFolder = Instance.new("Folder")

				spawnFolder.Name = "CartSpawns"
				spawnFolder.Parent = Workspace
				createCanonicalSpawn(spawnFolder)
				CartSpawnRegistry:Start()

				local routeStarted, routeError = CartGreyboxRouteSystem:Start()

				expect(routeStarted).to.equal(true)
				expect(routeError).to.equal(nil)

				local laneSpawnIds =
					CartGreyboxRouteSystem:GetSectionSpawnIds(SectionIds.MultiplayerOpenArea)

				expect(#laneSpawnIds).to.equal(3)

				local firstRecord = CartSpawnRegistry:GetById(laneSpawnIds[1])
				local secondRecord = CartSpawnRegistry:GetById(laneSpawnIds[2])
				local thirdRecord = CartSpawnRegistry:GetById(laneSpawnIds[3])

				expect(firstRecord ~= nil).to.equal(true)
				expect(secondRecord ~= nil).to.equal(true)
				expect(thirdRecord ~= nil).to.equal(true)

				local cartsFolder = RuntimeFolders.GetCartsFolder()
				local replaceableCart = createRuntimeCart(
					cartsFolder,
					"ReplaceableCart",
					(firstRecord :: CartSpawnRegistry.CartSpawnRecord).CFrame.Position
				)
				local otherCart = createRuntimeCart(
					cartsFolder,
					"OtherCart",
					(secondRecord :: CartSpawnRegistry.CartSpawnRecord).CFrame.Position
				)

				local excludingReplacement = CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(
					laneSpawnIds,
					function(spawnId)
						return CartSpawnRegistry:IsOccupied(spawnId, replaceableCart)
					end
				)
				local withoutExclusion = CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(
					laneSpawnIds,
					function(spawnId)
						return CartSpawnRegistry:IsOccupied(spawnId, nil)
					end
				)

				expect(excludingReplacement).to.equal(laneSpawnIds[1])
				expect(withoutExclusion).to.equal(laneSpawnIds[3])

				local previousMarker = (firstRecord :: CartSpawnRegistry.CartSpawnRecord).Part

				CartGreyboxRouteSystem:Stop()
				expect(CartSpawnRegistry:GetById(laneSpawnIds[1])).to.equal(nil)
				expect(previousMarker.Parent).to.equal(nil)

				local restarted, restartError = CartGreyboxRouteSystem:Start()

				expect(restarted).to.equal(true)
				expect(restartError).to.equal(nil)

				local replacementRecord = CartSpawnRegistry:GetById(laneSpawnIds[1])

				expect(replacementRecord ~= nil).to.equal(true)
				expect(
					(replacementRecord :: CartSpawnRegistry.CartSpawnRecord).Part == previousMarker
				).to.equal(false)
				expect((replacementRecord :: CartSpawnRegistry.CartSpawnRecord).Part.Parent).to.equal(
					spawnFolder
				)

				replaceableCart:Destroy()
				otherCart:Destroy()
				cartsFolder:Destroy()
			end)

			cleanWorkspace()

			if not succeeded then
				error(failure, 0)
			end
		end)

		it("registers and replaces all twelve performance spawn records on restart", function()
			cleanWorkspace()

			local succeeded, failure = pcall(function()
				local spawnFolder = Instance.new("Folder")

				spawnFolder.Name = "CartSpawns"
				spawnFolder.Parent = Workspace
				createCanonicalSpawn(spawnFolder)
				CartSpawnRegistry:Start()

				local routeStarted, routeError = CartGreyboxRouteSystem:Start()

				expect(routeStarted).to.equal(true)
				expect(routeError).to.equal(nil)

				local spawnIds =
					CartGreyboxRouteSystem:GetSectionSpawnIds(PerformanceIds.TwelveCartLoadZone)
				local previousMarkers: { [string]: BasePart } = {}
				local previousPosition: Vector3? = nil

				expect(#spawnIds).to.equal(12)

				for laneIndex, spawnId in spawnIds do
					expect(spawnId).to.equal(
						string.format("GBOX_SPAWN_GBOX_PERF_12_CART_LANE_%d", laneIndex)
					)

					local record = CartSpawnRegistry:GetById(spawnId)

					expect(record ~= nil).to.equal(true)
					previousMarkers[spawnId] = (record :: CartSpawnRegistry.CartSpawnRecord).Part

					local position = (record :: CartSpawnRegistry.CartSpawnRecord).CFrame.Position

					if previousPosition ~= nil then
						expect((position - previousPosition).Magnitude > 24).to.equal(true)
					end

					previousPosition = position
				end

				CartGreyboxRouteSystem:Stop()

				for _, spawnId in spawnIds do
					expect(CartSpawnRegistry:GetById(spawnId)).to.equal(nil)
					expect(previousMarkers[spawnId].Parent).to.equal(nil)
				end

				local restarted, restartError = CartGreyboxRouteSystem:Start()

				expect(restarted).to.equal(true)
				expect(restartError).to.equal(nil)

				local restartedSpawnIds =
					CartGreyboxRouteSystem:GetSectionSpawnIds(PerformanceIds.TwelveCartLoadZone)

				expect(#restartedSpawnIds).to.equal(12)

				for laneIndex, spawnId in spawnIds do
					expect(restartedSpawnIds[laneIndex]).to.equal(spawnId)
				end

				for _, spawnId in spawnIds do
					local record = CartSpawnRegistry:GetById(spawnId)

					expect(record ~= nil).to.equal(true)
					expect(
						(record :: CartSpawnRegistry.CartSpawnRecord).Part
							== previousMarkers[spawnId]
					).to.equal(false)
				end
			end)

			cleanWorkspace()

			if not succeeded then
				error(failure, 0)
			end
		end)
	end)
end
