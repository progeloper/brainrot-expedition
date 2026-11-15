--!strict

return function()
	local PhysicsService = game:GetService("PhysicsService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")

	local CartCamera = require(ReplicatedStorage.Shared.Config.CartCamera)
	local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)
	local CartCameraMath = require(ReplicatedStorage.Shared.Utility.CartCameraMath)
	local CartCameraOcclusion = require(ReplicatedStorage.Shared.Utility.CartCameraOcclusion)

	type Resolver = CartCameraOcclusion.Resolver

	type Fixture = {
		Container: Folder,
		Actors: Folder,
		CreatedMap: Folder?,
		Cart: Model,
		Character: Model,
		Origin: Vector3,
		DesiredPosition: Vector3,
		Resolver: Resolver,
	}

	local EPSILON = 1e-4
	local VECTOR_EPSILON = 1e-3
	local fixtureCount = 0
	local collisionGroupReady = false
	local previousCartsDefaultCollidable = false
	local createdCollisionGroup = false

	local function expectNear(actual: number, expected: number, epsilon: number?)
		expect(math.abs(actual - expected) <= (epsilon or EPSILON)).to.equal(true)
	end

	local function expectVectorNear(actual: Vector3, expected: Vector3, epsilon: number?)
		expect((actual - expected).Magnitude <= (epsilon or VECTOR_EPSILON)).to.equal(true)
	end

	local function ensureQueryCollisionGroup()
		if collisionGroupReady then
			return
		end

		createdCollisionGroup = not PhysicsService:IsCollisionGroupRegistered(CollisionGroups.Carts)

		if createdCollisionGroup then
			PhysicsService:RegisterCollisionGroup(CollisionGroups.Carts)
		end

		previousCartsDefaultCollidable = PhysicsService:CollisionGroupsAreCollidable(
			CollisionGroups.Carts,
			CollisionGroups.Default
		)

		PhysicsService:CollisionGroupSetCollidable(
			CollisionGroups.Carts,
			CollisionGroups.Default,
			true
		)

		collisionGroupReady = true
	end

	local function restoreQueryCollisionGroup()
		if not collisionGroupReady then
			return
		end

		PhysicsService:CollisionGroupSetCollidable(
			CollisionGroups.Carts,
			CollisionGroups.Default,
			previousCartsDefaultCollidable
		)

		if createdCollisionGroup then
			PhysicsService:UnregisterCollisionGroup(CollisionGroups.Carts)
		end

		collisionGroupReady = false
		createdCollisionGroup = false
	end

	local function withTerrainSimulation(callback: () -> ())
		local wasRunning = RunService:IsRunning()

		if not wasRunning then
			RunService:Run()
		end

		local succeeded, failure = pcall(callback)

		if not wasRunning then
			RunService:Pause()
		end

		if not succeeded then
			error(failure, 0)
		end
	end

	local function createQueryPart(
		parent: Instance,
		name: string,
		position: Vector3,
		size: Vector3?,
		canCollide: boolean?,
		canQuery: boolean?
	): BasePart
		local part = Instance.new("Part")

		part.Name = name
		part.Size = size or Vector3.new(12, 12, 1)
		part.Position = position
		part.Anchored = true
		part.CanCollide = if canCollide == nil then true else canCollide
		part.CanQuery = if canQuery == nil then true else canQuery
		part.Parent = parent

		return part
	end

	local function createFixture(): Fixture
		fixtureCount += 1
		ensureQueryCollisionGroup()

		local origin = Vector3.new(1000 + fixtureCount * 100, 1000, 1000)

		-- The default resolver is the bounded world volume (CartCameraVolume): it
		-- only considers Terrain and anchored geometry under Workspace.MapBlockout,
		-- so world obstructions are authored there. The cart and character live
		-- outside the map, exactly as they do at runtime.
		local existingMap = Workspace:FindFirstChild("MapBlockout")
		local createdMap: Folder? = nil

		if existingMap == nil then
			createdMap = Instance.new("Folder")
			;(createdMap :: Folder).Name = "MapBlockout"
			;(createdMap :: Folder).Parent = Workspace
		end

		local container = Instance.new("Folder")

		container.Name = string.format("CartCameraOcclusionTest_%d", fixtureCount)
		container.Parent = existingMap or createdMap

		local actors = Instance.new("Folder")

		actors.Name = string.format("CartCameraOcclusionActors_%d", fixtureCount)
		actors.Parent = Workspace

		local cart = Instance.new("Model")

		cart.Name = "ActiveCart"
		cart.Parent = actors

		local character = Instance.new("Model")

		character.Name = "LocalCharacter"
		character.Parent = actors

		return {
			Container = container,
			Actors = actors,
			CreatedMap = createdMap,
			Cart = cart,
			Character = character,
			Origin = origin,
			DesiredPosition = origin + Vector3.new(0, 0, 20),
			Resolver = CartCameraOcclusion.new(CartCamera.Obstruction),
		}
	end

	local function withFixture(callback: (Fixture) -> ())
		local fixture = createFixture()
		local succeeded, failure = pcall(callback, fixture)

		local cleanupFailure: unknown = nil

		local function clean(cleanupCallback: () -> ())
			local cleanupSucceeded, currentFailure = pcall(cleanupCallback)

			if not cleanupSucceeded and cleanupFailure == nil then
				cleanupFailure = currentFailure
			end
		end

		clean(function()
			fixture.Resolver:Destroy()
		end)
		clean(function()
			fixture.Container:Destroy()
		end)
		clean(function()
			fixture.Actors:Destroy()
		end)
		clean(function()
			if fixture.CreatedMap ~= nil then
				fixture.CreatedMap:Destroy()
			end
		end)
		if not succeeded then
			error(failure, 0)
		end

		if cleanupFailure ~= nil then
			error(cleanupFailure, 0)
		end
	end

	describe("CartCameraOcclusion math", function()
		it("preserves the full desired distance when there is no hit", function()
			local distance, minimumCompromised =
				CartCameraOcclusion.ResolveSafeDistance(20, nil, 0.25, 2)

			expect(distance).to.equal(20)
			expect(minimumCompromised).to.equal(false)
		end)

		it("subtracts the surface buffer from the nearest hit distance", function()
			local distance, minimumCompromised =
				CartCameraOcclusion.ResolveSafeDistance(20, 9, 0.25, 2)

			expect(distance).to.equal(8.75)
			expect(minimumCompromised).to.equal(false)
		end)

		it("never pushes through a close surface to honour the preferred minimum", function()
			local distance, minimumCompromised =
				CartCameraOcclusion.ResolveSafeDistance(20, 0.5, 0.25, 2)

			expect(distance).to.equal(0.25)
			expect(minimumCompromised).to.equal(true)
		end)

		it("never expands a known close position when a query fails", function()
			expect(CartCameraOcclusion.ResolveQueryFailureDistance(20, nil, 2)).to.equal(2)
			expect(CartCameraOcclusion.ResolveQueryFailureDistance(20, 8, 2)).to.equal(2)
			expect(CartCameraOcclusion.ResolveQueryFailureDistance(20, 0.5, 2)).to.equal(0.5)
		end)

		it("contracts inward immediately and decays the deficit without overshoot", function()
			expect(CartCameraOcclusion.AdvanceDeficit(0, 13, 8, 0.05, 1 / 60, false)).to.equal(13)

			local recovered = CartCameraOcclusion.AdvanceDeficit(13, 0, 8, 0.05, 0.1, false)

			expect(recovered > 0).to.equal(true)
			expect(recovered < 13).to.equal(true)
			expect(CartCameraOcclusion.AdvanceDeficit(13, 0, 8, 0.05, 0.1, true)).to.equal(0)
		end)

		it("recovers comparably across frame rates", function()
			local oneStep = CartCameraOcclusion.AdvanceDeficit(16, 0, 8, 0, 1, false)
			local manySteps = 16

			for _ = 1, 60 do
				manySteps = CartCameraOcclusion.AdvanceDeficit(manySteps, 0, 8, 0, 1 / 60, false)
			end

			expectNear(oneStep, manySteps, 1e-4)
			expect(oneStep >= 0).to.equal(true)
		end)

		it("places the corrected camera on the existing orbit segment", function()
			local position =
				CartCameraOcclusion.ResolvePosition(Vector3.new(1, 2, 3), Vector3.new(1, 2, 23), 8)

			expect(position ~= nil).to.equal(true)
			expectVectorNear(position :: Vector3, Vector3.new(1, 2, 11))
		end)

		it("changes only position when applying correction to the Phase 1M frame", function()
			local base = CFrame.lookAt(Vector3.new(4, 8, 20), Vector3.new(1, 2, 3))
			local corrected =
				CartCameraOcclusion.ApplyCorrectedPosition(base, Vector3.new(2, 4, 10))

			expect(corrected ~= nil).to.equal(true)
			expectVectorNear((corrected :: CFrame).Position, Vector3.new(2, 4, 10))
			expectVectorNear((corrected :: CFrame).LookVector, base.LookVector)
			expectVectorNear((corrected :: CFrame).UpVector, base.UpVector)
		end)

		it("rejects degenerate and non-finite correction input", function()
			expect(CartCameraOcclusion.ResolvePosition(Vector3.zero, Vector3.zero, 1)).to.equal(nil)
			expect(CartCameraOcclusion.ResolvePosition(Vector3.zero, Vector3.zAxis, math.huge)).to.equal(
				nil
			)
			expect(
				CartCameraOcclusion.ApplyCorrectedPosition(
					CFrame.new(math.huge, 0, 0),
					Vector3.zero
				)
			).to.equal(nil)
		end)
	end)

	describe("CartCameraOcclusion resolver", function()
		it("preserves the Phase 1M desired transform on a clear path", function()
			withFixture(function(fixture)
				local targetFrame = CFrame.new(fixture.Origin)
				local rootFrame = CFrame.new(fixture.Origin)
				local desiredFrame, focus = CartCameraMath.GetDesiredCFrame(
					targetFrame,
					rootFrame,
					math.rad(25),
					math.rad(10),
					CartCamera.Distance,
					CartCamera.HeightOffset
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local result, failure =
					fixture.Resolver:Resolve(focus, desiredFrame.Position, 1 / 60, true)

				expect(failure).to.equal(nil)
				expect(result ~= nil).to.equal(true)
				expect((result :: CartCameraOcclusion.Result).Obstructed).to.equal(false)
				expectVectorNear(
					(result :: CartCameraOcclusion.Result).CorrectedPosition,
					desiredFrame.Position
				)
			end)
		end)

		it("does not mistake a clear Phase 1M distance change for recovery", function()
			withFixture(function(fixture)
				local initial = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result
				local initialDistance = initial.CorrectedDistance
				local fartherPosition = fixture.Origin + Vector3.new(0, 0, 30)
				local changed = fixture.Resolver:Resolve(
					fixture.Origin,
					fartherPosition,
					1 / 60,
					false
				) :: CartCameraOcclusion.Result

				expect(initialDistance).to.equal(20)
				expect(changed.CorrectedDistance).to.equal(30)
				expect(changed.Recovering).to.equal(false)
				expectVectorNear(changed.CorrectedPosition, fartherPosition)
			end)
		end)

		it("detects external geometry already overlapping the query origin", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"OriginOverlap",
					fixture.Origin + Vector3.new(0, 0, 1),
					Vector3.new(12, 12, 1)
				)
				createQueryPart(
					fixture.Container,
					"FartherWall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(result.Obstructed).to.equal(true)
				expect(result.InitialOverlap).to.equal(true)
				expect(result.HitInstance).to.equal(wall)
				expect(result.HitDistance).to.equal(0)
				expect(result.CorrectedDistance).to.equal(0)
				expect(result.MinimumCompromised).to.equal(true)
			end)
		end)

		it("detects a wall and keeps the camera on the target side", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"Wall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local result, failure =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect(failure).to.equal(nil)
				expect(result ~= nil).to.equal(true)

				local resolved = result :: CartCameraOcclusion.Result

				expect(resolved.Obstructed).to.equal(true)
				expect(resolved.HitInstance).to.equal(wall)
				expect(resolved.CorrectedDistance < (resolved.HitDistance :: number)).to.equal(true)
				expectNear(
					resolved.CorrectedDistance,
					(resolved.HitDistance :: number) - CartCamera.Obstruction.SurfaceBuffer
				)
				expect(resolved.CorrectedPosition.Z < wall.Position.Z).to.equal(true)
			end)
		end)

		it("excludes the current cart and local character from the query", function()
			withFixture(function(fixture)
				createQueryPart(fixture.Cart, "CartHull", fixture.Origin + Vector3.new(0, 0, 3))
				createQueryPart(
					fixture.Character,
					"CharacterPart",
					fixture.Origin + Vector3.new(0, 0, 5)
				)
				local externalWall = createQueryPart(
					fixture.Container,
					"ExternalWall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local result =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect(result ~= nil).to.equal(true)
				expect((result :: CartCameraOcclusion.Result).HitInstance).to.equal(externalWall)
			end)
		end)

		it("updates filters only when cart or character context changes", function()
			withFixture(function(fixture)
				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local initialRevision = fixture.Resolver:GetFilterRevision()

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				expect(fixture.Resolver:GetFilterRevision()).to.equal(initialRevision)

				local replacementCart = Instance.new("Model")

				replacementCart.Name = "ReplacementCart"
				replacementCart.Parent = fixture.Container
				fixture.Resolver:SetFilterContext(replacementCart, fixture.Character)

				expect(fixture.Resolver:GetFilterRevision()).to.equal(initialRevision + 1)
			end)
		end)

		it("removes stale cart exclusions after replacement", function()
			withFixture(function(fixture)
				local oldPart = createQueryPart(
					fixture.Cart,
					"OldCartPart",
					fixture.Origin + Vector3.new(0, 0, 3)
				)
				local replacementCart = Instance.new("Model")

				replacementCart.Name = "ReplacementCart"
				replacementCart.Parent = fixture.Container

				local newPart = createQueryPart(
					replacementCart,
					"NewCartPart",
					fixture.Origin + Vector3.new(0, 0, 6)
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local before =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((before :: CartCameraOcclusion.Result).HitInstance).to.equal(newPart)

				fixture.Resolver:SetFilterContext(replacementCart, fixture.Character)
				fixture.Resolver:Reset()
				local after =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((after :: CartCameraOcclusion.Result).HitInstance).to.equal(oldPart)
			end)
		end)

		it("removes stale character exclusions after respawn", function()
			withFixture(function(fixture)
				local oldCharacterPart = createQueryPart(
					fixture.Character,
					"OldCharacterPart",
					fixture.Origin + Vector3.new(0, 0, 3)
				)
				local replacementCharacter = Instance.new("Model")

				replacementCharacter.Name = "ReplacementCharacter"
				replacementCharacter.Parent = fixture.Container

				local replacementCharacterPart = createQueryPart(
					replacementCharacter,
					"ReplacementCharacterPart",
					fixture.Origin + Vector3.new(0, 0, 6)
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)
				local before =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((before :: CartCameraOcclusion.Result).HitInstance).to.equal(
					replacementCharacterPart
				)

				fixture.Resolver:SetFilterContext(fixture.Cart, replacementCharacter)
				fixture.Resolver:Reset()
				local after =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((after :: CartCameraOcclusion.Result).HitInstance).to.equal(oldCharacterPart)
			end)
		end)

		it("uses the established collidable-query policy", function()
			withFixture(function(fixture)
				-- Current volume policy: map geometry obstructs when it is collidable
				-- or visible, so only an invisible non-collidable marker is ignored.
				local marker = Instance.new("Part")

				marker.Name = "NonCollidableMarker"
				marker.Size = Vector3.new(12, 12, 1)
				marker.Position = fixture.Origin + Vector3.new(0, 0, 3)
				marker.Anchored = true
				marker.CanCollide = false
				marker.Transparency = 1
				marker.Parent = fixture.Container
				local wall = createQueryPart(
					fixture.Container,
					"Wall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				local result =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((result :: CartCameraOcclusion.Result).HitInstance).to.equal(wall)
			end)
		end)

		it("treats collidable geometry as obstruction even when CanQuery is false", function()
			withFixture(function(fixture)
				local collidablePart = createQueryPart(
					fixture.Container,
					"CollidablePart",
					fixture.Origin + Vector3.new(0, 0, 3),
					nil,
					true,
					false
				)
				createQueryPart(fixture.Container, "Wall", fixture.Origin + Vector3.new(0, 0, 10))

				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(result.HitInstance).to.equal(collidablePart)
			end)
		end)

		it("treats transparent collidable world geometry as obstruction", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"TransparentCollisionHull",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				wall.Transparency = 1

				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(result.Obstructed).to.equal(true)
				expect(result.HitInstance).to.equal(wall)
			end)
		end)

		it("reports when close geometry compromises the preferred minimum", function()
			withFixture(function(fixture)
				createQueryPart(
					fixture.Container,
					"CloseWall",
					fixture.Origin + Vector3.new(0, 0, 2)
				)

				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(result.InitialOverlap).to.equal(false)
				expect(result.MinimumCompromised).to.equal(true)
				expect(result.CorrectedDistance < CartCamera.Obstruction.MinimumDistance).to.equal(
					true
				)
			end)
		end)

		it("passes through exactly without queries when obstruction is disabled", function()
			withFixture(function(fixture)
				local disabled = table.clone(CartCamera.Obstruction)

				disabled.Enabled = false
				fixture.Resolver:Destroy()
				fixture.Resolver = CartCameraOcclusion.new(disabled)
				createQueryPart(
					fixture.Container,
					"IgnoredWall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(result.QueryPerformed).to.equal(false)
				expect(result.Obstructed).to.equal(false)
				expectVectorNear(result.CorrectedPosition, fixture.DesiredPosition)
			end)
		end)

		it("does not cast beyond the desired camera position", function()
			withFixture(function(fixture)
				createQueryPart(
					fixture.Container,
					"BeyondCamera",
					fixture.Origin + Vector3.new(0, 0, 25)
				)

				local result =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)

				expect((result :: CartCameraOcclusion.Result).Obstructed).to.equal(false)
				expectVectorNear(
					(result :: CartCameraOcclusion.Result).CorrectedPosition,
					fixture.DesiredPosition
				)
			end)
		end)

		it("recovers smoothly after the obstruction clears", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"Wall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				local obstructed = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result
				local obstructedDistance = obstructed.CorrectedDistance

				wall:Destroy()

				local recovering = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					0.1,
					false
				) :: CartCameraOcclusion.Result
				local recoveringDistance = recovering.CorrectedDistance

				expect(recovering.Obstructed).to.equal(false)
				expect(recovering.Recovering).to.equal(true)
				expect(recoveringDistance > obstructedDistance).to.equal(true)
				expect(recoveringDistance < recovering.DesiredDistance).to.equal(true)

				for _ = 1, 120 do
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, false)
				end

				expectNear(fixture.Resolver:GetCurrentDistance() :: number, 20)
			end)
		end)

		it("preserves Phase 1M distance changes while recovering a deficit", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"Wall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)
				local obstructed = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result
				local obstructedDistance = obstructed.CorrectedDistance

				wall:Destroy()

				local fartherPosition = fixture.Origin + Vector3.new(0, 0, 30)
				local recovering = fixture.Resolver:Resolve(
					fixture.Origin,
					fartherPosition,
					0.1,
					false
				) :: CartCameraOcclusion.Result

				expect(recovering.Recovering).to.equal(true)
				expect(recovering.CorrectedDistance > obstructedDistance + 10).to.equal(true)
				expect(recovering.CorrectedDistance < 30).to.equal(true)
			end)
		end)

		it("lets a new obstruction interrupt outward recovery immediately", function()
			withFixture(function(fixture)
				local nearWall = createQueryPart(
					fixture.Container,
					"NearWall",
					fixture.Origin + Vector3.new(0, 0, 7)
				)

				fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)
				nearWall:Destroy()

				local recovering = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					0.1,
					false
				) :: CartCameraOcclusion.Result
				local fartherDistance = recovering.CorrectedDistance
				local closerWall = createQueryPart(
					fixture.Container,
					"CloserWall",
					fixture.Origin + Vector3.new(0, 0, 4)
				)

				local interrupted = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					false
				) :: CartCameraOcclusion.Result

				expect(interrupted.HitInstance).to.equal(closerWall)
				expect(interrupted.CorrectedDistance < fartherDistance).to.equal(true)
				expectNear(
					interrupted.CorrectedDistance,
					(interrupted.HitDistance :: number) - CartCamera.Obstruction.SurfaceBuffer
				)
			end)
		end)

		it("clears old obstruction history for reset resynchronisation", function()
			withFixture(function(fixture)
				local wall = createQueryPart(
					fixture.Container,
					"Wall",
					fixture.Origin + Vector3.new(0, 0, 10)
				)

				fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, true)
				fixture.Resolver:Reset()
				wall:Destroy()

				expect(fixture.Resolver:GetCurrentDistance()).to.equal(nil)

				local resynchronised = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					true
				) :: CartCameraOcclusion.Result

				expect(resynchronised.CorrectedDistance).to.equal(20)
				expectVectorNear(resynchronised.CorrectedPosition, fixture.DesiredPosition)
			end)
		end)

		it("contracts safely on query failure and recovers on the next valid frame", function()
			withFixture(function(fixture)
				local queryCount = 0

				fixture.Resolver:Destroy()
				fixture.Resolver = CartCameraOcclusion.new(
					CartCamera.Obstruction,
					function(_origin, _radius, _direction, _params)
						queryCount += 1

						if queryCount == 1 then
							error("forced query failure")
						end

						return nil
					end
				)

				local failed = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					false
				) :: CartCameraOcclusion.Result

				expect(failed.QueryFailed).to.equal(true)
				expect(type(failed.Failure)).to.equal("string")
				expect(failed.CorrectedDistance).to.equal(CartCamera.Obstruction.MinimumDistance)
				local failedDistance = failed.CorrectedDistance

				local recovering = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					0.1,
					false
				) :: CartCameraOcclusion.Result

				expect(recovering.QueryFailed).to.equal(false)
				expect(recovering.Recovering).to.equal(true)
				expect(recovering.CorrectedDistance > failedDistance).to.equal(true)
			end)
		end)

		it("preserves a known close forward hit when the overlap probe fails", function()
			withFixture(function(fixture)
				local closeWall = createQueryPart(
					fixture.Container,
					"CloseWall",
					fixture.Origin + Vector3.new(0, 0, 2)
				)
				local queryCount = 0

				fixture.Resolver:Destroy()
				fixture.Resolver = CartCameraOcclusion.new(
					CartCamera.Obstruction,
					function(origin, radius, direction, params)
						queryCount += 1

						if queryCount == 2 then
							error("forced overlap-probe failure")
						end

						return Workspace:Spherecast(origin, radius, direction, params)
					end
				)
				fixture.Resolver:SetFilterContext(fixture.Cart, fixture.Character)

				local result = fixture.Resolver:Resolve(
					fixture.Origin,
					fixture.DesiredPosition,
					1 / 60,
					false
				) :: CartCameraOcclusion.Result

				expect(result.QueryFailed).to.equal(true)
				expect(result.Obstructed).to.equal(true)
				expect(result.HitInstance).to.equal(closeWall)
				expect(result.CorrectedDistance < (result.HitDistance :: number)).to.equal(true)
				expectNear(
					result.CorrectedDistance,
					math.max(
						(result.HitDistance :: number) - CartCamera.Obstruction.SurfaceBuffer,
						0
					)
				)
			end)
		end)

		it("treats Terrain as an obstruction", function()
			withTerrainSimulation(function()
				withFixture(function(fixture)
					local terrainCenter = fixture.Origin + Vector3.new(0, 0, 10)
					local terrainSize = Vector3.new(12, 12, 4)

					Workspace.Terrain:FillBlock(
						CFrame.new(terrainCenter),
						terrainSize,
						Enum.Material.Rock
					)
					RunService.Heartbeat:Wait()

					local succeeded, failure = pcall(function()
						local result = fixture.Resolver:Resolve(
							fixture.Origin,
							fixture.DesiredPosition,
							1 / 60,
							true
						) :: CartCameraOcclusion.Result

						expect(result.Obstructed).to.equal(true)
						expect(result.HitInstance).to.equal(Workspace.Terrain)
						expect(result.CorrectedPosition.Z < terrainCenter.Z).to.equal(true)
					end)

					Workspace.Terrain:FillBlock(
						CFrame.new(terrainCenter),
						terrainSize,
						Enum.Material.Air
					)

					if not succeeded then
						error(failure, 0)
					end
				end)
			end)
		end)

		it("detects Terrain already intersecting the query origin", function()
			withTerrainSimulation(function()
				withFixture(function(fixture)
					local terrainSize = Vector3.new(4, 4, 4)

					createQueryPart(
						fixture.Container,
						"FartherWall",
						fixture.Origin + Vector3.new(0, 0, 10)
					)

					Workspace.Terrain:FillBlock(
						CFrame.new(fixture.Origin),
						terrainSize,
						Enum.Material.Rock
					)
					RunService.Heartbeat:Wait()

					local succeeded, failure = pcall(function()
						local result = fixture.Resolver:Resolve(
							fixture.Origin,
							fixture.DesiredPosition,
							1 / 60,
							true
						) :: CartCameraOcclusion.Result

						expect(result.Obstructed).to.equal(true)
						expect(result.InitialOverlap).to.equal(true)
						expect(result.HitInstance).to.equal(Workspace.Terrain)
						expect(result.CorrectedDistance).to.equal(0)
					end)

					Workspace.Terrain:FillBlock(
						CFrame.new(fixture.Origin),
						terrainSize,
						Enum.Material.Air
					)

					if not succeeded then
						error(failure, 0)
					end
				end)
			end)
		end)

		it("rejects invalid segments and stops querying after teardown", function()
			withFixture(function(fixture)
				local invalid, invalidFailure =
					fixture.Resolver:Resolve(fixture.Origin, fixture.Origin, 1 / 60, false)

				expect(invalid).to.equal(nil)
				expect(type(invalidFailure)).to.equal("string")

				fixture.Resolver:Destroy()

				local destroyed, destroyedFailure =
					fixture.Resolver:Resolve(fixture.Origin, fixture.DesiredPosition, 1 / 60, false)

				expect(destroyed).to.equal(nil)
				expect(type(destroyedFailure)).to.equal("string")
			end)
		end)

		it("restores the shared collision-query fixture state", function()
			restoreQueryCollisionGroup()
			expect(collisionGroupReady).to.equal(false)
		end)
	end)
end
