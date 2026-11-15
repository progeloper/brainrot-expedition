--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")

	local CartGreybox = require(ReplicatedStorage.Shared.Config.CartGreybox)
	local PerformanceIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxPerformanceIds)
	local CartSpawnValidator = require(ReplicatedStorage.Shared.Validation.CartSpawnValidator)
	local CartGreyboxRouteBuilder = require(script.Parent.Parent.Utility.CartGreyboxRouteBuilder)

	local TEST_ROOT_NAME = "CartGreyboxRouteBuilderSpecRuntime"

	local function createHierarchy(): (Folder, Folder, Folder)
		local stale = Workspace:FindFirstChild(TEST_ROOT_NAME)

		if stale ~= nil then
			stale:Destroy()
		end

		local root = Instance.new("Folder")

		root.Name = TEST_ROOT_NAME
		root.Parent = Workspace

		local routeParent = Instance.new("Folder")

		routeParent.Name = "Development"
		routeParent.Parent = root

		local spawnFolder = Instance.new("Folder")

		spawnFolder.Name = "CartSpawns"
		spawnFolder.Parent = root

		return root, routeParent, spawnFolder
	end

	local function expectedStartCFrame(origin: CFrame, section: any): CFrame
		return origin
			* CFrame.new(CartGreybox.RouteOffset)
			* CFrame.new(
				section.GridColumn * CartGreybox.GridSpacing.X,
				0,
				section.GridRow * CartGreybox.GridSpacing.Y
			)
			* CFrame.new(section.StartOffset)
	end

	local function forwardIsHigher(part: BasePart): boolean
		local sampleDistance = part.Size.Z * 0.4
		local rear = part.CFrame:PointToWorldSpace(Vector3.new(0, 0, sampleDistance))
		local forward = part.CFrame:PointToWorldSpace(Vector3.new(0, 0, -sampleDistance))

		return forward.Y > rear.Y
	end

	describe("CartGreyboxRouteBuilder", function()
		it("builds deterministic owned route geometry and spawn markers", function()
			local root, routeParent, spawnFolder = createHierarchy()
			local origin = CFrame.new(35, 12, -80) * CFrame.Angles(0, math.rad(30), 0)
			local result, failure =
				CartGreyboxRouteBuilder.Build(CartGreybox, origin, routeParent, spawnFolder)

			expect(failure).to.equal(nil)
			expect(result ~= nil).to.equal(true)

			local built = result :: CartGreyboxRouteBuilder.BuildResult

			expect(built.RouteFolder.Name).to.equal("Phase1SGreybox")
			expect(built.RouteFolder:GetAttribute(CartGreybox.OwnedAttribute)).to.equal(true)
			expect(#built.RouteFolder:GetChildren()).to.equal(21)
			expect(#built.SpawnMarkers).to.equal(34)

			local seenSpawnIds: { [string]: boolean } = {}
			local markersBySpawnId: { [string]: BasePart } = {}

			for _, marker in built.SpawnMarkers do
				local spawnId = marker:GetAttribute("SpawnId") :: string
				local spawnValidation = CartSpawnValidator.Validate(marker)

				expect(marker.Anchored).to.equal(true)
				expect(marker.CanCollide).to.equal(false)
				expect(marker.CanQuery).to.equal(false)
				expect(marker:GetAttribute("DebugOnly")).to.equal(true)
				expect(seenSpawnIds[spawnId]).to.equal(nil)
				expect(spawnValidation.IsValid).to.equal(true)

				seenSpawnIds[spawnId] = true
				markersBySpawnId[spawnId] = marker
			end

			for index, section in CartGreybox.Sections do
				local spawnIds = built.SpawnIdsBySection[section.Id]
				local spawnOffsets = section.SpawnOffsets or { section.StartOffset }

				expect(#spawnIds).to.equal(#spawnOffsets)
				expect(built.StartCFramesBySection[section.Id]).to.equal(
					expectedStartCFrame(origin, section)
				)

				for laneIndex, spawnOffset in spawnOffsets do
					local baseSpawnId = CartGreybox.SpawnIdPrefix .. section.Id
					local spawnId = if #spawnOffsets > 1
						then string.format("%s_LANE_%d", baseSpawnId, laneIndex)
						else baseSpawnId
					local marker = markersBySpawnId[spawnId]
					local expectedName = if #spawnOffsets > 1
						then string.format("GreyboxSpawn_%02d_Lane_%d", index, laneIndex)
						else string.format("GreyboxSpawn_%02d", index)
					local expectedCFrame = origin
						* CFrame.new(CartGreybox.RouteOffset)
						* CFrame.new(
							section.GridColumn * CartGreybox.GridSpacing.X,
							0,
							section.GridRow * CartGreybox.GridSpacing.Y
						)
						* CFrame.new(spawnOffset)

					expect(spawnIds[laneIndex]).to.equal(spawnId)
					expect(marker.Name).to.equal(expectedName)
					expect(marker.CFrame).to.equal(expectedCFrame)
					expect(marker:GetAttribute(CartGreybox.SectionIdAttribute)).to.equal(section.Id)
				end

				if #spawnIds > 1 then
					for laneIndex = 2, #spawnIds do
						local previousMarker = markersBySpawnId[spawnIds[laneIndex - 1]]
						local marker = markersBySpawnId[spawnIds[laneIndex]]

						expect((marker.Position - previousMarker.Position).Magnitude > 24).to.equal(
							true
						)
					end
				end
			end

			expect(built.RouteFolder:FindFirstChild("GBOX_CAMERA_WALL")).never.to.equal(nil)
			expect(built.RouteFolder:FindFirstChild("GBOX_STUCK")).never.to.equal(nil)

			CartGreyboxRouteBuilder.Destroy(built)
			expect(routeParent:FindFirstChild("Phase1SGreybox")).to.equal(nil)
			expect(#spawnFolder:GetChildren()).to.equal(0)

			root:Destroy()
		end)

		it("builds twelve stable separated performance lanes", function()
			local root, routeParent, spawnFolder = createHierarchy()
			local result, failure = CartGreyboxRouteBuilder.Build(
				CartGreybox,
				CFrame.new(15, 9, -30),
				routeParent,
				spawnFolder
			)

			expect(failure).to.equal(nil)
			expect(result ~= nil).to.equal(true)

			local built = result :: CartGreyboxRouteBuilder.BuildResult
			local spawnIds = built.SpawnIdsBySection[PerformanceIds.TwelveCartLoadZone]
			local zone = built.RouteFolder:FindFirstChild(PerformanceIds.TwelveCartLoadZone)
			local previousPosition: Vector3? = nil

			expect(#spawnIds).to.equal(12)
			expect(zone ~= nil and zone:IsA("Model")).to.equal(true)

			for laneIndex, spawnId in spawnIds do
				expect(spawnId).to.equal(
					string.format("GBOX_SPAWN_GBOX_PERF_12_CART_LANE_%d", laneIndex)
				)

				local marker: BasePart? = nil

				for _, candidate in built.SpawnMarkers do
					if candidate:GetAttribute("SpawnId") == spawnId then
						marker = candidate
						break
					end
				end

				expect(marker ~= nil).to.equal(true)

				local lane = (zone :: Model):FindFirstChild(
					string.format("PerformanceLane_%02d", laneIndex)
				)
				local barrier = (zone :: Model):FindFirstChild(
					string.format("PerformanceEndBarrier_%02d", laneIndex)
				)

				expect(lane ~= nil and lane:IsA("BasePart")).to.equal(true)
				expect(barrier ~= nil and barrier:IsA("BasePart")).to.equal(true)
				expect((barrier :: BasePart).Anchored).to.equal(true)
				expect((barrier :: BasePart).CanCollide).to.equal(true)
				expect(
					((marker :: BasePart).Position - (barrier :: BasePart).Position).Magnitude > 180
				).to.equal(true)

				local position = (marker :: BasePart).Position

				if previousPosition ~= nil then
					expect((position - previousPosition).Magnitude > 24).to.equal(true)
				end

				previousPosition = position
			end

			CartGreyboxRouteBuilder.Destroy(built)
			expect(#spawnFolder:GetChildren()).to.equal(0)
			root:Destroy()
		end)

		it("rejects duplicate marker ownership without changing existing state", function()
			local root, routeParent, spawnFolder = createHierarchy()
			local unrelatedMarker = Instance.new("Part")

			unrelatedMarker.Name = "UnrelatedMarker"
			unrelatedMarker:SetAttribute(
				"SpawnId",
				CartGreybox.SpawnIdPrefix .. CartGreybox.Sections[1].Id
			)
			unrelatedMarker.Parent = spawnFolder

			local result, failure = CartGreyboxRouteBuilder.Build(
				CartGreybox,
				CFrame.new(0, 10, 0),
				routeParent,
				spawnFolder
			)

			expect(result).to.equal(nil)
			expect(type(failure)).to.equal("string")
			expect(routeParent:FindFirstChild("Phase1SGreybox")).to.equal(nil)
			expect(unrelatedMarker.Parent).to.equal(spawnFolder)
			expect(#spawnFolder:GetChildren()).to.equal(1)

			root:Destroy()
		end)

		it("orients uphill, downhill, and crest surfaces along cart forward travel", function()
			local root, routeParent, spawnFolder = createHierarchy()
			local result = CartGreyboxRouteBuilder.Build(
				CartGreybox,
				CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(35), 0),
				routeParent,
				spawnFolder
			)
			local built = result :: CartGreyboxRouteBuilder.BuildResult
			local uphill = built.RouteFolder.GBOX_SLOPE_UP.GentleRamp :: BasePart
			local downhill = built.RouteFolder.GBOX_SLOPE_DOWN.GentleRamp :: BasePart
			local crestApproach = built.RouteFolder.GBOX_CREST.CrestApproach :: BasePart
			local crestDeparture = built.RouteFolder.GBOX_CREST.CrestDeparture :: BasePart

			expect(forwardIsHigher(uphill)).to.equal(true)
			expect(forwardIsHigher(downhill)).to.equal(false)
			expect(forwardIsHigher(crestApproach)).to.equal(true)
			expect(forwardIsHigher(crestDeparture)).to.equal(false)

			CartGreyboxRouteBuilder.Destroy(built)
			root:Destroy()
		end)

		it("rejects non-finite canonical transforms before creating Instances", function()
			local root, routeParent, spawnFolder = createHierarchy()
			local invalidCFrame = CFrame.new(0 / 0, 0, 0)
			local result, failure =
				CartGreyboxRouteBuilder.Build(CartGreybox, invalidCFrame, routeParent, spawnFolder)

			expect(result).to.equal(nil)
			expect(type(failure)).to.equal("string")
			expect(#routeParent:GetChildren()).to.equal(0)
			expect(#spawnFolder:GetChildren()).to.equal(0)

			root:Destroy()
		end)
	end)
end
