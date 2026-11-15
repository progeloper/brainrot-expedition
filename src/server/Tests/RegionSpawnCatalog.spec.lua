--!nocheck
return function()
	local Catalog = require(game.ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local Regions = require(game.ReplicatedStorage.Shared.Config.Regions)
	local VisualScale = require(game.ReplicatedStorage.Shared.Utility.BrainrotVisualScale)
	local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Phase10 = require(game.ReplicatedStorage.Shared.Config.Phase10)

	local function part(name, cframe, size)
		local value = Instance.new("Part")
		value.Name = name
		value.Anchored = true
		value.CFrame = cframe
		value.Size = size
		return value
	end

	local function region(id, boundaries, areas, kind, naturalSpawnAllowed)
		return {
			id = assert(Regions.NormalizeId(id)),
			displayName = assert(Regions.Get(id)).displayName,
			kind = kind or "Hunting",
			enabled = true,
			naturalSpawnAllowed = if naturalSpawnAllowed == nil then true else naturalSpawnAllowed,
			boundaryRefs = boundaries or {},
			spawnAreaRefs = areas or {},
		}
	end

	local function species(id, home, allowed, status, modelRef)
		local normalizedAllowed = {}
		for _, regionId in allowed do
			table.insert(normalizedAllowed, assert(Regions.NormalizeId(regionId)))
		end
		return {
			id = id,
			tier = "Common",
			homeRegionId = if home then assert(Regions.NormalizeId(home)) else nil,
			allowedRegionIds = normalizedAllowed,
			regionAssignmentStatus = status,
			modelRef = modelRef or id,
			behaviourId = "Wanderer",
			launchStatus = "Live",
			spawnEnabled = false,
		}
	end

	local function makeFixture(options)
		options = options or {}
		local instances = {}
		local forestBoundary = part("ForestBoundary", CFrame.new(0, 5, 0), Vector3.new(100, 20, 100))
		local jungleBoundary = part("JungleBoundary", CFrame.new(150, 5, 0), Vector3.new(100, 20, 100))
		local campBoundary = part("CampBoundary", CFrame.new(400, 5, 0), Vector3.new(40, 20, 40))
		local forestArea =
			part("ForestArea", options.areaCFrame or CFrame.new(0, 2, 0), options.areaSize or Vector3.new(30, 4, 30))
		forestArea:SetAttribute("SpawnAreaId", "Forest_A")
		forestArea:SetAttribute("RegionId", "REGION_FOREST")
		forestArea:SetAttribute("SpawnAreaKind", "Volume")
		local jungleArea = part("JungleArea", CFrame.new(150, 2, 0), Vector3.new(30, 4, 30))
		jungleArea:SetAttribute("SpawnAreaId", "Jungle_A")
		jungleArea:SetAttribute("RegionId", "REGION_JUNGLE")
		jungleArea:SetAttribute("SpawnAreaKind", "Volume")
		instances.ForestBoundary = forestBoundary
		instances.JungleBoundary = jungleBoundary
		instances.CampBoundary = campBoundary
		instances.ForestArea = forestArea
		instances.JungleArea = jungleArea

		local assets = Instance.new("Folder")
		local model = Instance.new("Model")
		model.Name = "BRT_007"
		model.Parent = assets
		local body = part("Body", options.bodyCFrame or CFrame.new(), options.bodySize or Vector3.new(2, 2, 2))
		body.CanQuery = true
		body.Parent = model
		model.WorldPivot = options.modelPivot or CFrame.new()

		local context = {
			AssetFolder = assets,
			ResolveReference = function(reference)
				return instances[reference]
			end,
			ProbeGround = function()
				return true
			end,
			ValidateGround = function(candidate, area, definition)
				if options.validateGround then
					return options.validateGround(candidate, area, definition)
				end
				return true, Vector3.new(candidate.X, 0, candidate.Z), nil
			end,
			ValidateClearance = function()
				return true, nil
			end,
			IsProtected = function(frame, size)
				if options.isProtected then
					return options.isProtected(frame, size)
				end
				return false, nil
			end,
		}
		local regions = {
			region("REGION_FOREST", { "ForestBoundary" }, { "ForestArea" }),
			region("REGION_JUNGLE", { "JungleBoundary" }, { "JungleArea" }),
			region("REGION_CAMP", { "CampBoundary" }, {}, "Hub", false),
		}
		return {
			Instances = instances,
			Assets = assets,
			Model = model,
			Body = body,
			Context = context,
			Regions = regions,
			Destroy = function()
				assets:Destroy()
				for _, instance in instances do
					instance:Destroy()
				end
			end,
		}
	end

	local function hasCode(items, code)
		for _, item in items do
			if item.code == code then
				return true
			end
		end
		return false
	end

	local function hasReason(result, code)
		for _, reason in result.reasons do
			if reason == code then
				return true
			end
		end
		return false
	end

	local nativeFixtureCount = 0
	local function withNativePlacement(callback)
		Placement.ResetQueryBudgetForTesting()
		nativeFixtureCount += 1
		local origin = Vector3.new(18000 + nativeFixtureCount * 100, 6000, 18000)
		local fixture =
			makeFixture({ areaCFrame = CFrame.new(origin + Vector3.yAxis * 4), areaSize = Vector3.new(30, 8, 30) })
		local root = Instance.new("Folder")
		root.Name, root.Parent = "SPEC_NATURAL_CLEARANCE", workspace
		for _, name in { "ForestBoundary", "ForestArea" } do
			local marker = fixture.Instances[name]
			if name == "ForestBoundary" then
				marker.CFrame = CFrame.new(origin + Vector3.yAxis * 5)
			end
			marker.CanCollide, marker.CanQuery, marker.Parent = false, false, root
		end
		local ground = part("AuthoredFloor", CFrame.new(origin - Vector3.yAxis), Vector3.new(40, 2, 40))
		ground:SetAttribute("LayoutRole", "Floor")
		ground.Parent = root
		fixture.Context.ValidateGround, fixture.Context.ValidateClearance, fixture.Context.ProbeGround = nil, nil, nil
		local previous = Placement.Configure(nil)
		local function rebuild()
			return RegionSpawnCatalog.BuildIndex(
				fixture.Regions,
				{ species("BRT_007", "Forest", { "Forest" }, "Approved") },
				fixture.Context
			)
		end
		local function validate()
			return RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", origin)
		end
		local ok, failure = pcall(function()
			rebuild()
			callback({
				root = root,
				origin = origin,
				ground = ground,
				fixture = fixture,
				rebuild = rebuild,
				validate = validate,
			})
		end)
		Placement.Configure(previous)
		root:Destroy()
		fixture.Destroy()
		if not ok then
			error(failure, 0)
		end
	end

	describe("Phase 6F-1 regional spawn catalogue", function()
		it("proves native footprint support and rejects anchored roofs and decorative tops", function()
			withNativePlacement(function(f)
				local accepted = f.validate()
				expect(accepted.valid).to.equal(true)
				expect(
					math.abs(
						accepted.placementEnvelope.Y
							- VisualScale.TARGET_HEIGHT_STUDS / 2
							- f.origin.Y
							- Phase10.SafetySkin
					) < 0.001
				).to.equal(true)
				f.ground:SetAttribute("LayoutRole", nil)
				f.ground.Name = "DecorativeRoof"
				expect(hasReason(f.validate(), "NO_VALID_GROUND")).to.equal(true)
				f.ground:SetAttribute("CartDrivableGround", true)
				f.ground.Size = Vector3.new(1, 2, 1)
				expect(hasReason(f.validate(), "UNSUPPORTED_FOOTPRINT")).to.equal(true)
				f.ground.Size = Vector3.new(40, 2, 40)
				expect(f.validate().valid).to.equal(true)
			end)
		end)

		it("checks the full safety skin against thin native ceilings and nonqueryable semantic gates", function()
			withNativePlacement(function(f)
				local accepted = f.validate()
				expect(accepted.valid).to.equal(true)
				local ceiling = part(
					"ThinCeiling",
					CFrame.new(
						f.origin + Vector3.new(0.8, VisualScale.TARGET_HEIGHT_STUDS + Phase10.SafetySkin + 0.1, 0.8)
					),
					Vector3.new(0.3, 0.1, 0.3)
				)
				ceiling.Parent = f.root
				expect(hasReason(f.validate(), "INSUFFICIENT_CLEARANCE")).to.equal(true)
				ceiling:Destroy()
				local crossing = part("SemanticGate", accepted.placementEnvelope, Vector3.new(0.1, 12, 15))
				crossing.CanCollide, crossing.CanQuery, crossing.Parent = false, false, f.root
				Placement.Configure({
					Descriptors = {
						GetGate = function(_, id)
							return if id == "REGION_FOREST" then { crossing = crossing } else nil
						end,
					},
				})
				expect(hasReason(f.validate(), "SEMANTIC_GATE_OVERLAP")).to.equal(true)
				crossing:Destroy()
				Placement.Configure(nil)
				expect(f.validate().valid).to.equal(true)
			end)
		end)

		it("keeps static readiness usable after transient runtime query exhaustion and retries next window", function()
			withNativePlacement(function(f)
				local params = RaycastParams.new()
				for _ = 1, 60 do
					Placement.ProbeBrainrotGround(f.origin + Vector3.yAxis * 4, -Vector3.yAxis * 8, params)
				end
				expect(hasReason(f.validate(), "QueryBudget")).to.equal(true)
				f.rebuild()
				expect(RegionSpawnCatalog.GetSpawnAreas("Forest")[1].UsableProbeCount).to.equal(9)
				expect(RegionSpawnCatalog.EvaluateNaturalSpawnReadiness("BRT_007", "Forest").ready).to.equal(true)
				Placement.ResetQueryBudgetForTesting()
				expect(f.validate().valid).to.equal(true)
			end)
		end)

		it("rejects native Terrain embedding that part overlap cannot see", function()
			local RunService = game:GetService("RunService")
			local PhysicsService = game:GetService("PhysicsService")
			if not PhysicsService:IsCollisionGroupRegistered("Carts") then
				PhysicsService:RegisterCollisionGroup("Carts")
			end
			local wasRunning = RunService:IsRunning()
			if not wasRunning then
				RunService:Run()
			end
			local ok, failure = pcall(function()
				withNativePlacement(function(f)
					local voxelRegion = Region3.new(f.origin - Vector3.one * 20, f.origin + Vector3.one * 24)
						:ExpandToGrid(4)
					local materials, occupancy = workspace.Terrain:ReadVoxels(voxelRegion, 4)
					local succeeded, terrainFailure = pcall(function()
						-- Wider native art leaves an obstruction between the five support
						-- samples, so only the full initial-volume Terrain proof can reject it.
						f.fixture.Body.Size = Vector3.new(8, 2, 8)
						f.rebuild()
						expect(f.validate().valid).to.equal(true)
						workspace.Terrain:FillBlock(
							CFrame.new(f.origin + Vector3.new(3.5, 2.8, 0)),
							Vector3.new(2, 2, 2),
							Enum.Material.Rock
						)
						RunService.Heartbeat:Wait()
						local blocked = f.validate()
						expect(blocked.valid).to.equal(false)
						expect(hasReason(blocked, "TerrainOccupied") or hasReason(blocked, "TerrainAbovePose")).to.equal(
							true
						)
					end)
					workspace.Terrain:WriteVoxels(voxelRegion, 4, materials, occupancy)
					if not succeeded then
						error(terrainFailure, 0)
					end
				end)
			end)
			if not wasRunning then
				RunService:Pause()
			end
			if not ok then
				error(failure, 0)
			end
		end)

		it("permits native Terrain support contact under the ordinary full envelope", function()
			local RunService = game:GetService("RunService")
			local PhysicsService = game:GetService("PhysicsService")
			if not PhysicsService:IsCollisionGroupRegistered("Carts") then
				PhysicsService:RegisterCollisionGroup("Carts")
			end
			local wasRunning = RunService:IsRunning()
			if not wasRunning then
				RunService:Run()
			end
			local ok, failure = pcall(function()
				withNativePlacement(function(f)
					local voxelRegion = Region3.new(f.origin - Vector3.one * 24, f.origin + Vector3.one * 24)
						:ExpandToGrid(4)
					local materials, occupancy = workspace.Terrain:ReadVoxels(voxelRegion, 4)
					local succeeded, terrainFailure = pcall(function()
						f.ground:Destroy()
						workspace.Terrain:FillBlock(
							CFrame.new(f.origin - Vector3.yAxis * 4),
							Vector3.new(40, 8, 40),
							Enum.Material.Grass
						)
						RunService.Heartbeat:Wait()
						f.rebuild()
						expect(f.validate().valid).to.equal(true)
					end)
					workspace.Terrain:WriteVoxels(voxelRegion, 4, materials, occupancy)
					if not succeeded then
						error(terrainFailure, 0)
					end
				end)
			end)
			if not wasRunning then
				RunService:Pause()
			end
			if not ok then
				error(failure, 0)
			end
		end)

		it("derives duplicate-free multi-region pools from approved species assignments", function()
			local fixture = makeFixture()
			local definitions = {
				species("BRT_007", "Forest", { "Forest", "Jungle" }, "Approved"),
			}
			local report = RegionSpawnCatalog.BuildIndex(fixture.Regions, definitions, fixture.Context)
			expect(#report.errors).to.equal(0)
			expect(#RegionSpawnCatalog.GetApprovedSpeciesIds("Forest")).to.equal(1)
			expect(RegionSpawnCatalog.GetApprovedSpeciesIds("Jungle")[1]).to.equal("BRT_007")
			expect(RegionSpawnCatalog.IsSpeciesAllowedInRegion("BRT-007", "Forest")).to.equal(true)
			expect(RegionSpawnCatalog.IsSpeciesAllowedInRegion("BRT_007", "Camp")).to.equal(false)
			local readiness = RegionSpawnCatalog.EvaluateNaturalSpawnReadiness("BRT_007", "Forest")
			expect(readiness.ready).to.equal(true)
			expect(readiness.activated).to.equal(false)
			fixture.Destroy()
		end)

		it("keeps pending home-only evidence out of approved pools", function()
			local fixture = makeFixture()
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", {}, "Pending"),
			}, fixture.Context)
			expect(#RegionSpawnCatalog.GetApprovedSpeciesIds("Forest")).to.equal(0)
			local result = RegionSpawnCatalog.EvaluateNaturalSpawnReadiness("BRT_007", "Forest")
			expect(result.ready).to.equal(false)
			expect(hasReason(result, "REGION_ASSIGNMENT_PENDING")).to.equal(true)
			fixture.Destroy()
		end)

		it("resolves only an approved authoritative home and never defaults pending data", function()
			local fixture = makeFixture()
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest", "Jungle" }, "Approved"),
				species("BRT_008", nil, {}, "Pending"),
			}, fixture.Context)
			local home, reason = RegionSpawnCatalog.ResolveHomeRegion("BRT_007")
			expect(home).to.equal("REGION_FOREST")
			expect(reason).to.equal(nil)
			local missing, missingReason = RegionSpawnCatalog.ResolveHomeRegion("BRT_008")
			expect(missing).to.equal(nil)
			expect(missingReason).to.equal("REGION_ASSIGNMENT_PENDING")
			fixture.Destroy()
		end)

		it("rejects duplicate area IDs instead of allowing reference order to win", function()
			local fixture = makeFixture()
			local duplicate = part("Duplicate", CFrame.new(20, 2, 0), Vector3.new(10, 4, 10))
			duplicate:SetAttribute("SpawnAreaId", "Forest_A")
			duplicate:SetAttribute("RegionId", "REGION_FOREST")
			duplicate:SetAttribute("SpawnAreaKind", "Volume")
			fixture.Instances.Duplicate = duplicate
			fixture.Regions[1].spawnAreaRefs = { "ForestArea", "Duplicate" }
			local report = RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			expect(hasCode(report.errors, "DUPLICATE_SPAWN_AREA_ID")).to.equal(true)
			fixture.Destroy()
		end)

		it("uses local-space containment for a rotated spawn volume", function()
			local rotated = CFrame.new(0, 2, 0) * CFrame.Angles(0, math.rad(45), 0)
			local fixture = makeFixture({ areaCFrame = rotated })
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			local inside = rotated:PointToWorldSpace(Vector3.new(5, -2, 0))
			local outside = rotated:PointToWorldSpace(Vector3.new(20, -2, 0))
			expect(RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", inside).valid).to.equal(true)
			local rejected = RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", outside)
			expect(rejected.valid).to.equal(false)
			expect(hasReason(rejected, "CANDIDATE_OUTSIDE_SPAWN_AREA")).to.equal(true)
			fixture.Destroy()
		end)

		it("rejects a Forest-labelled candidate inside the protected Camp boundary", function()
			local fixture = makeFixture({ areaCFrame = CFrame.new(400, 2, 0) })
			fixture.Instances.ForestBoundary.CFrame = CFrame.new(400, 5, 0)
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			local result = RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", Vector3.new(400, 0, 0))
			expect(result.valid).to.equal(false)
			expect(hasReason(result, "PROTECTED_AREA_OVERLAP")).to.equal(true)
			fixture.Destroy()
		end)

		it("lets Camp return cross only the Camp boundary while preserving other protection", function()
			local fixture = makeFixture()
			-- Exercise the production overlap filter rather than the fixture's
			-- injectable protection seam.
			fixture.Context.IsProtected = nil
			local protectedFoundation = part("SPEC_ReturnFoundation", CFrame.new(410, 2, 0), Vector3.new(2, 2, 2))
			protectedFoundation.Parent = workspace
			fixture.Instances.ProtectedFoundation = protectedFoundation
			fixture.Context.ProtectedInstances = { protectedFoundation }
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			expect(RegionSpawnCatalog.IsProtectedSpace(CFrame.new(400, 2, 0), Vector3.new(2, 4, 2))).to.equal(true)
			expect(RegionSpawnCatalog.IsProtectedForCampReturn(CFrame.new(400, 2, 0), Vector3.new(2, 4, 2))).to.equal(
				false
			)
			local blocked, reason, owner =
				RegionSpawnCatalog.IsProtectedForCampReturn(CFrame.new(410, 2, 0), Vector3.new(2, 4, 2))
			expect(blocked).to.equal(true)
			expect(reason).to.equal("PROTECTED_AREA_OVERLAP")
			expect(owner).to.equal(protectedFoundation:GetFullName())
			fixture.Destroy()

			local protectedFixture = makeFixture({
				isProtected = function()
					return true, "PROTECTED_AREA_OVERLAP"
				end,
			})
			RegionSpawnCatalog.BuildIndex(protectedFixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, protectedFixture.Context)
			expect(RegionSpawnCatalog.IsProtectedForCampReturn(CFrame.new(400, 2, 0), Vector3.new(2, 4, 2))).to.equal(
				true
			)
			protectedFixture.Destroy()
		end)

		it("checks the full envelope against hunting boundaries and protected interiors", function()
			local fixture = makeFixture({
				isProtected = function(frame)
					return frame.Position.X >= 20, "PROTECTED_AREA_OVERLAP"
				end,
			})
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)

			expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", CFrame.new(0, 2, 0), Vector3.new(2, 4, 2), 2)).to.equal(
				true
			)
			local outside, outsideReason =
				RegionSpawnCatalog.IsInsideHuntingSpace("Forest", CFrame.new(48, 2, 0), Vector3.new(2, 4, 2), 2)
			expect(outside).to.equal(false)
			expect(outsideReason).to.equal("OUTSIDE_REGION")
			local protected, protectedReason =
				RegionSpawnCatalog.IsInsideHuntingSpace("Forest", CFrame.new(20, 2, 0), Vector3.new(2, 4, 2), 2)
			expect(protected).to.equal(false)
			expect(protectedReason).to.equal("PROTECTED_AREA_OVERLAP")
			local protectedOnly, protectedOnlyReason =
				RegionSpawnCatalog.IsProtectedSpace(CFrame.new(20, 2, 0), Vector3.new(2, 4, 2))
			expect(protectedOnly).to.equal(true)
			expect(protectedOnlyReason).to.equal("PROTECTED_AREA_OVERLAP")
			expect(RegionSpawnCatalog.IsInsideHuntingSpace("Camp", CFrame.new(400, 2, 0), Vector3.new(2, 4, 2), 2)).to.equal(
				false
			)
			expect(RegionSpawnCatalog.IsInsideRegionSpace("Camp", CFrame.new(400, 2, 0), Vector3.new(2, 4, 2), 0)).to.equal(
				true
			)
			fixture.Destroy()
		end)

		it(
			"covers native internal floor seams while rejecting gaps, foreign floors and reactive boundary exits",
			function()
				local fixture = makeFixture()
				local folder = Instance.new("Folder")
				folder.Name, folder.Parent = "SPEC_REGION_FLOOR_UNION", workspace
				local origin = Vector3.new(26000, 5000, 26000)
				local left, right =
					fixture.Instances.ForestBoundary, part("ForestRightFloor", CFrame.new(), Vector3.new(20, 1, 40))
				left.Size = Vector3.new(20, 1, 40)
				left.CFrame, right.CFrame =
					CFrame.new(origin + Vector3.new(-10, -0.5, 0)), CFrame.new(origin + Vector3.new(10, -0.5, 0))
				left:SetAttribute("LayoutRole", "Floor")
				right:SetAttribute("LayoutRole", "Floor")
				left:SetAttribute("CellId", "NativeSeamLeft")
				right:SetAttribute("CellId", "NativeSeamRight")
				left:SetAttribute("GeneratedBy", "CreateBasicMap_v1")
				right:SetAttribute("GeneratedBy", "CreateBasicMap_v1")
				left.Parent, right.Parent = folder, folder
				fixture.Instances.ForestRightFloor = right
				fixture.Regions[1].boundaryRefs = { "ForestBoundary", "ForestRightFloor" }
				local ran, failure = xpcall(function()
					RegionSpawnCatalog.BuildIndex(
						fixture.Regions,
						{ species("BRT_007", "Forest", { "Forest" }, "Approved") },
						fixture.Context
					)
					local frame, size = CFrame.new(origin + Vector3.yAxis * 2), Vector3.new(4, 4, 4)
					expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", frame, size, 2)).to.equal(true)
					expect(RegionSpawnCatalog.IsInsideRegionSpace("Forest", frame, size, 2)).to.equal(true)
					expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", frame + Vector3.xAxis * 18, size, 2)).to.equal(
						false
					)
					right.CFrame += Vector3.xAxis * 2 -- A foreign tile cannot fill a gap in this region's union.
					local foreign = fixture.Instances.JungleBoundary
					foreign.Size, foreign.CFrame = Vector3.new(40, 1, 40), CFrame.new(origin - Vector3.yAxis * 0.5)
					foreign:SetAttribute("LayoutRole", "Floor")
					foreign:SetAttribute("CellId", "NativeForeign")
					foreign:SetAttribute("GeneratedBy", "CreateBasicMap_v1")
					foreign.Parent = folder
					expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", frame, size, 2)).to.equal(false)
					right.CFrame = CFrame.new(origin + Vector3.new(10, -0.5, 20)) -- Concave missing quadrant.
					expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", frame - Vector3.zAxis * 5, size, 2)).to.equal(
						false
					)
					right.CFrame = CFrame.new(origin + Vector3.new(10, 3.5, 0))
					expect(RegionSpawnCatalog.IsInsideHuntingSpace("Forest", frame, size, 2)).to.equal(false)
					right.CFrame = CFrame.new(origin + Vector3.new(10, -0.5, 0))
					foreign.CanCollide, foreign.CanQuery = false, false
					local RouteCatalog = require(script.Parent.Parent.Utility.BurrowRouteCatalog)
					local Motor = require(script.Parent.Parent.Utility.BurrowRouteMotor)
					local RouteRules = require(game.ReplicatedStorage.Shared.Utility.BrainrotRouteRules)
					local data = {
						Ready = true,
						GeometryVersion = "NativeSeam",
						Hull = { X = 2, Y = 4, Z = 2 },
						Mouths = {},
						Routes = {
							{
								Id = "A>B",
								EntranceId = "A",
								DestinationId = "B",
								RegionId = "REGION_FOREST",
								Validated = true,
								Points = { origin - Vector3.xAxis * 15, origin + Vector3.xAxis * 15 },
							},
						},
					}
					RouteCatalog._TestWithGeometry(data, RegionSpawnCatalog.ContainsPosition, function()
						local route = assert(RouteCatalog.Get("A>B"), "Native seam route must compile")
						local model = Instance.new("Model")
						local root = part("Root", CFrame.new(origin - Vector3.xAxis * 2), Vector3.one)
						root.CanCollide, root.CanQuery, root.Parent = false, false, model
						model.PrimaryPart, model.Parent = root, folder
						local state = { Route = RouteRules.NewJourney(route) }
						local motor = Motor.Create(model, route, {
							GetState = function()
								return state
							end,
							Commit = function(value)
								state.Route = value
								return true
							end,
							OnDepart = function()
								return false
							end,
						}, { GroundOffset = 0, Geometry = RouteCatalog })
						local from, across = origin - Vector3.xAxis * 2, origin + Vector3.new(2, 0, 4)
						expect(Motor.RecordExcursion(motor, from, across)).to.equal(true)
						model:PivotTo(CFrame.new(across))
						expect(
							RegionSpawnCatalog.IsInsideHuntingSpace(
								"Forest",
								CFrame.new(across + Vector3.yAxis * 2),
								size,
								2
							)
						).to.equal(true)
						local retained = state.Route
						expect(Motor.RecordExcursion(motor, across, origin + Vector3.xAxis * 22)).to.equal(false)
						expect(state.Route).to.equal(retained)
						expect(motor.BlockedReason).to.equal("ROUTE_LEAVES_REGION")
					end)
				end, debug.traceback)
				folder:Destroy()
				fixture.Destroy()
				assert(ran, failure)
			end
		)

		it("preserves categorized surface-validation failures", function()
			for _, reason in
				{
					"NO_VALID_GROUND",
					"UNSUITABLE_SURFACE",
					"INSUFFICIENT_CLEARANCE",
				}
			do
				local fixture = makeFixture({
					validateGround = function(_candidate)
						return false, nil, reason
					end,
				})
				RegionSpawnCatalog.BuildIndex(fixture.Regions, {
					species("BRT_007", "Forest", { "Forest" }, "Approved"),
				}, fixture.Context)
				local result = RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", Vector3.zero)
				expect(result.valid).to.equal(false)
				expect(hasReason(result, reason)).to.equal(true)
				fixture.Destroy()
			end
		end)

		it("rejects a large logical Body that does not fit the authored volume", function()
			local fixture = makeFixture({ areaSize = Vector3.new(8, 4, 8), bodySize = Vector3.new(12, 2, 12) })
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			local result = RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", Vector3.zero)
			expect(result.valid).to.equal(false)
			expect(hasReason(result, "CANDIDATE_OUTSIDE_SPAWN_AREA")).to.equal(true)
			fixture.Destroy()
		end)

		it("grounds the existing visual envelope while preserving the authored model pivot", function()
			local fixture = makeFixture({ bodyCFrame = CFrame.new(2, 3, 0) })
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			local result = RegionSpawnCatalog.ValidatePlacement("BRT_007", "Forest", "Forest_A", Vector3.zero)
			expect(result.valid).to.equal(true)
			expect(math.abs(result.placementPivot.Position.X) <= 0.0001).to.equal(true)
			local correction = VisualScale.TARGET_HEIGHT_STUDS / fixture.Body.Size.Y
			expect(math.abs(result.placementEnvelope.Position.X - 2 * correction) <= 0.0001).to.equal(true)
			expect(
				math.abs(
					result.placementEnvelope.Position.Y
						- fixture.Body.Size.Y * correction * 0.5
						- (if Phase10.Enabled then Phase10.SafetySkin else 0.1)
				) <= 0.0001
			).to.equal(true)
			fixture.Destroy()
		end)

		it("separates approved mapping, technical readiness and activation", function()
			local fixture = makeFixture()
			local definition = species("BRT_007", "Forest", { "Forest" }, "Approved", "Missing")
			definition.spawnEnabled = true
			RegionSpawnCatalog.BuildIndex(fixture.Regions, { definition }, fixture.Context)
			local result = RegionSpawnCatalog.EvaluateNaturalSpawnReadiness("BRT_007", "Forest")
			expect(RegionSpawnCatalog.IsSpeciesAllowedInRegion("BRT_007", "Forest")).to.equal(true)
			expect(result.ready).to.equal(false)
			expect(result.activated).to.equal(false)
			expect(hasReason(result, "MODEL_MISSING")).to.equal(true)
			fixture.Destroy()
		end)

		it("rebuilds without duplicate pools, areas or retained listeners", function()
			local fixture = makeFixture()
			local definitions = {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}
			RegionSpawnCatalog.BuildIndex(fixture.Regions, definitions, fixture.Context)
			RegionSpawnCatalog.BuildIndex(fixture.Regions, definitions, fixture.Context)
			expect(#RegionSpawnCatalog.GetApprovedSpeciesIds("Forest")).to.equal(1)
			expect(#RegionSpawnCatalog.GetSpawnAreas("Forest")).to.equal(1)
			fixture.Destroy()
		end)

		it("discovers the Studio MapBlockout floor contract for all current regions", function()
			local root = Instance.new("Folder")
			root.Name = "Workspace"
			local map = Instance.new("Folder")
			map.Name, map.Parent = "MapBlockout", root
			local folderNames = {
				REGION_BEACH = "Beach",
				REGION_FOREST = "Forest",
				REGION_SWAMP = "Swamp",
				REGION_JUNGLE = "Jungle",
				REGION_ARCTIC = "Arctic",
				REGION_VOLCANO = "Volcano",
				REGION_GLITCH = "Glitch Zone",
				REGION_CAMP = "Camp",
			}
			local centres = {}
			for index, definition in Regions.GetAll() do
				local regionFolder = Instance.new("Folder")
				regionFolder.Name, regionFolder.Parent = folderNames[definition.id], map
				local floor = part(
					"Floor_R" .. tostring(index) .. "_C1",
					CFrame.new(index * 200, -2, 0),
					Vector3.new(120, 4, 120)
				)
				floor:SetAttribute("LayoutRole", "Floor")
				floor:SetAttribute("CellId", floor.Name)
				floor:SetAttribute("GeneratedBy", "CreateBasicMap_v1")
				floor.Parent = regionFolder
				centres[definition.id] = Vector3.new(index * 200, 0, 0)
			end
			local assets = Instance.new("Folder")
			local report = RegionSpawnCatalog.BuildIndex(Regions.GetAll(), {}, {
				Root = root,
				AssetFolder = assets,
				ProtectedInstances = {},
				ProbeGround = function()
					return true
				end,
			})
			expect(#report.errors).to.equal(0)
			for _, definition in Regions.GetAll() do
				local centre = centres[definition.id]
				expect(RegionSpawnCatalog.ContainsPosition(definition.id, centre)).to.equal(true)
				expect(
					RegionSpawnCatalog.IsInsideRegionSpace(
						definition.id,
						CFrame.new(centre + Vector3.new(0, 3, 0)),
						Vector3.new(2, 2, 2),
						0
					)
				).to.equal(true)
				local areaCount = #RegionSpawnCatalog.GetSpawnAreas(definition.id)
				expect(areaCount).to.equal(if definition.id == Regions.CampId then 0 else 1)
			end
			expect(RegionSpawnCatalog.GetRegionAtPosition(centres.REGION_CAMP).id).to.equal("REGION_CAMP")
			expect(RegionSpawnCatalog.GetRegionAtPosition(Vector3.new(9999, 0, 9999))).to.equal(nil)
			local raisedCargoSource = centres.REGION_FOREST + Vector3.yAxis * 20
			expect(RegionSpawnCatalog.GetRegionAtPosition(raisedCargoSource)).to.equal(nil)
			expect(RegionSpawnCatalog.GetRegionAtPosition(raisedCargoSource, math.huge).id).to.equal("REGION_FOREST")
			assets:Destroy()
			root:Destroy()
		end)

		it("supplies immutable approved selector candidates without Instance references", function()
			local fixture = makeFixture()
			RegionSpawnCatalog.BuildIndex(fixture.Regions, {
				species("BRT_007", "Forest", { "Forest" }, "Approved"),
			}, fixture.Context)
			local candidates = RegionSpawnCatalog.GetSelectionCandidates("Forest")
			expect(#candidates).to.equal(1)
			expect(candidates[1].id).to.equal("BRT_007")
			expect(candidates[1].tier).to.equal("Common")
			expect(candidates[1].modelReady).to.equal(true)
			expect(candidates[1].locationReady).to.equal(true)
			expect(candidates[1].globalWithinTierWeight).to.equal(nil)
			expect(function()
				candidates[1].spawnEnabled = true
			end).to.throw()
			fixture.Destroy()
		end)

		it("loads all approved shipped assignments without substituting BRT_007", function()
			RegionSpawnCatalog.BuildIndex(nil, Catalog.GetAll(), {
				ResolveReference = function()
					return nil
				end,
				AssetFolder = nil,
			})
			expect(RegionSpawnCatalog.GetSpeciesAssignment("BRT-007").status).to.equal("Approved")
			expect(RegionSpawnCatalog.GetSpeciesAssignment("BRT-007").homeRegionId).to.equal("REGION_FOREST")
			expect(RegionSpawnCatalog.GetSpeciesAssignment("BRT_999")).to.equal(nil)
			expect(#RegionSpawnCatalog.GetApprovedSpeciesIds("Forest")).to.equal(13)
		end)
	end)
end
