--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")

	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local CartTerrainProfileResolver =
		require(ReplicatedStorage.Shared.Utility.CartTerrainProfileResolver)
	local CartTerrainSampler = require(ReplicatedStorage.Shared.Utility.CartTerrainSampler)

	type Sampler = CartTerrainSampler.Sampler

	type TerrainFixture = {
		Container: Folder,
		Cart: Model,
		Root: BasePart,
		Ground: BasePart,
		GroundTopPosition: Vector3,
		Sampler: Sampler,
	}

	local fixtureCount = 0

	local function expectClose(actual: number, expected: number, tolerance: number?)
		expect(math.abs(actual - expected) <= (tolerance or 1e-4)).to.equal(true)
	end

	local function expectVectorClose(actual: Vector3, expected: Vector3, tolerance: number?)
		expect((actual - expected).Magnitude <= (tolerance or 1e-4)).to.equal(true)
	end

	local function createQueryPart(
		parent: Instance,
		name: string,
		size: Vector3,
		position: Vector3
	): BasePart
		local part = Instance.new("Part")

		part.Name = name
		part.Size = size
		part.Position = position
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.Parent = parent

		return part
	end

	local function createFixture(): TerrainFixture
		fixtureCount += 1

		local isolatedPosition = Vector3.new(1000 + fixtureCount * 50, 10000, 1000)
		local container = Instance.new("Folder")

		container.Name = string.format("CartTerrainSamplerTest_%d", fixtureCount)
		container.Parent = Workspace

		local ground = createQueryPart(
			container,
			"FlatGround",
			Vector3.new(20, 1, 20),
			isolatedPosition - Vector3.new(0, 0.5, 0)
		)
		local cart = Instance.new("Model")

		cart.Name = "TerrainSamplerTestCart"
		cart:SetAttribute("CartId", Ids.Carts.ScrapChariot)
		cart:SetAttribute("AssemblyValidationState", "Valid")
		cart.Parent = container

		local root = Instance.new("Part")

		root.Name = "Root"
		root.Size = Vector3.new(4, 2, 6)
		root.CFrame = CFrame.new(isolatedPosition + Vector3.new(0, root.Size.Y / 2 + 0.5, 0))
		root.Anchored = false
		root.CanCollide = false
		root.Parent = cart
		cart.PrimaryPart = root

		local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)
		local sampler = CartTerrainSampler.new(cart, root, profile)

		return {
			Container = container,
			Cart = cart,
			Root = root,
			Ground = ground,
			GroundTopPosition = isolatedPosition,
			Sampler = sampler,
		}
	end

	local function withFixture(callback: (TerrainFixture) -> ())
		local fixture = createFixture()
		local success, errorMessage = pcall(callback, fixture)

		fixture.Sampler:Destroy()
		fixture.Container:Destroy()

		if not success then
			error(errorMessage, 0)
		end
	end

	local function resumeAndGround(fixture: TerrainFixture, startTime: number)
		local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

		fixture.Sampler:Resume()

		local acquiring = fixture.Sampler:SampleNow(startTime)

		expect(acquiring.State).to.equal("Partial")
		expect(acquiring.HitCount).to.equal(3)

		local grounded =
			fixture.Sampler:SampleNow(startTime + profile.GroundedReacquireDelay + 0.01)

		expect(grounded.State).to.equal("Grounded")
		expect(grounded.Grounded).to.equal(true)
		expect(grounded.FullyGrounded).to.equal(true)
		expect(grounded.HitCount).to.equal(3)
		expect(grounded.Confidence).to.equal(1)
	end

	describe("CartTerrainSampler", function()
		it("resolves three flat-ground hits and requires sustained support to reacquire", function()
			withFixture(function(fixture)
				local initial = fixture.Sampler:GetSnapshot()

				expect(initial.State).to.equal("Airborne")
				expect(initial.HitCount).to.equal(0)

				resumeAndGround(fixture, 0)

				local grounded = fixture.Sampler:GetSnapshot()

				expect(grounded.RawNormal).to.equal(Vector3.yAxis)
				expect(grounded.DesiredUp).to.equal(Vector3.yAxis)
				expect(grounded.SlopeAngleDegrees).to.equal(0)
				expect(grounded.Driveable).to.equal(true)
				expectClose(
					grounded.GroundDistance,
					fixture.Root.Position.Y - fixture.Root.Size.Y / 2 - fixture.GroundTopPosition.Y
				)
			end)
		end)

		it("does not treat a distant ray hit as physical support", function()
			withFixture(function(fixture)
				local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

				fixture.Root.Position += Vector3.new(0, profile.MaximumSupportGap + 0.25, 0)
				fixture.Sampler:Resume()

				local first = fixture.Sampler:SampleNow(0)
				local afterGrace = fixture.Sampler:SampleNow(profile.AirborneDelay + 0.01)

				expect(first.HitCount).to.equal(0)
				expect(afterGrace.HitCount).to.equal(0)
				expect(afterGrace.State).to.equal("Airborne")
			end)
		end)

		it("rejects a deep intersecting obstruction as support", function()
			withFixture(function(fixture)
				createQueryPart(
					fixture.Container,
					"DeepProbeObstruction",
					Vector3.new(12, 0.5, 12),
					fixture.GroundTopPosition + Vector3.new(0, 2.25, 0)
				)
				fixture.Sampler:Resume()

				local obstructed = fixture.Sampler:SampleNow(0)

				expect(obstructed.HitCount).to.equal(0)
				expect(obstructed.State).to.equal("Airborne")
				expect(obstructed.GroundDistance).to.equal(0)
			end)
		end)

		it("primes an inclined desired-up reference initially and after reset", function()
			withFixture(function(fixture)
				local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

				fixture.Ground.CFrame = CFrame.new(fixture.Ground.Position)
					* CFrame.Angles(math.rad(15), 0, 0)
				fixture.Sampler:Resume()

				local initialPrime = fixture.Sampler:SampleNow(0)

				expect(initialPrime.HitCount >= profile.FullGroundedHitCount).to.equal(true)
				expect(initialPrime.SlopeAngleDegrees > 10).to.equal(true)
				expectVectorClose(initialPrime.DesiredUp, initialPrime.RawNormal)

				fixture.Sampler:Reset()
				fixture.Ground.CFrame = CFrame.new(fixture.Ground.Position)
					* CFrame.Angles(math.rad(-15), 0, 0)

				local resetPrime = fixture.Sampler:SampleNow(1)

				expect(resetPrime.HitCount >= profile.FullGroundedHitCount).to.equal(true)
				expect(resetPrime.RawNormal:Dot(initialPrime.RawNormal) < 1).to.equal(true)
				expectVectorClose(resetPrime.DesiredUp, resetPrime.RawNormal)
			end)
		end)

		it("measures support from each probe against a tilted Root lower face", function()
			withFixture(function(fixture)
				local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)
				local rotation = CFrame.Angles(math.rad(55), 0, 0)
				local rootPosition = fixture.Root.Position

				fixture.Root.CFrame = CFrame.new(rootPosition) * rotation

				local rootUp = fixture.Root.CFrame.UpVector
				local lowerFacePoint = fixture.Root.Position - rootUp * fixture.Root.Size.Y * 0.5
				local expectedGap = 0.5
				local groundTopPoint = lowerFacePoint - Vector3.yAxis * expectedGap

				fixture.Ground.CFrame = CFrame.new(
					groundTopPoint - rootUp * fixture.Ground.Size.Y * 0.5
				) * rotation
				fixture.Sampler:Resume()

				local tilted = fixture.Sampler:SampleNow(0)

				expect(tilted.HitCount >= profile.FullGroundedHitCount).to.equal(true)
				expect(tilted.SlopeAngleDegrees > 50).to.equal(true)
				expectClose(tilted.GroundDistance, expectedGap, 1e-3)
			end)
		end)

		it("reports partial support and applies airborne grace before support loss", function()
			withFixture(function(fixture)
				local profile = CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot)

				resumeAndGround(fixture, 0)
				fixture.Ground:Destroy()

				local lateralOffset = fixture.Root.Size.X
					* CartTerrainProfileResolver.Resolve(Ids.Carts.ScrapChariot).LateralProbeFraction
				local partialSupport = createQueryPart(
					fixture.Container,
					"LeftProbeSupport",
					Vector3.new(0.75, 0.5, 0.75),
					fixture.GroundTopPosition - Vector3.new(lateralOffset, 0.25, 0)
				)
				local partial = fixture.Sampler:SampleNow(0.2)

				expect(partial.State).to.equal("Partial")
				expect(partial.Grounded).to.equal(true)
				expect(partial.FullyGrounded).to.equal(false)
				expect(partial.HitCount).to.equal(1)
				expectClose(partial.Confidence, 1 / 3)
				expect(partial.StabilityMultiplier).to.equal(
					profile.PartialSupportStabilityMultiplier
				)

				partialSupport:Destroy()

				local grace = fixture.Sampler:SampleNow(0.2 + profile.AirborneDelay * 0.5)

				expect(grace.State).to.equal("Partial")
				expect(grace.HitCount).to.equal(0)
				expect(grace.Grounded).to.equal(true)

				local airborne = fixture.Sampler:SampleNow(0.2 + profile.AirborneDelay + 0.01)

				expect(airborne.State).to.equal("Airborne")
				expect(airborne.Grounded).to.equal(false)
				expect(airborne.HitCount).to.equal(0)
				expect(airborne.StabilityMultiplier).to.equal(profile.AirborneStabilityMultiplier)
			end)
		end)

		it("does not sample while suspended", function()
			withFixture(function(fixture)
				local initial = fixture.Sampler:GetSnapshot()

				expect(fixture.Sampler:ShouldSample(0, 15)).to.equal(false)
				expect((fixture.Sampler:SampleNow(0) :: any) == (initial :: any)).to.equal(true)

				fixture.Sampler:Resume()
				expect(fixture.Sampler:ShouldSample(0, 15)).to.equal(true)
				fixture.Sampler:SampleNow(0)
				fixture.Sampler:Suspend()

				local suspended = fixture.Sampler:GetSnapshot()

				expect(fixture.Sampler:ShouldSample(1, 15)).to.equal(false)
				expect((fixture.Sampler:SampleNow(1) :: any) == (suspended :: any)).to.equal(true)
				expect(fixture.Sampler:GetSnapshot().SampleCount).to.equal(1)
			end)
		end)

		it("excludes the cart and the optional driver character from raycasts", function()
			withFixture(function(fixture)
				createQueryPart(
					fixture.Cart,
					"CartProbeBlocker",
					Vector3.new(12, 0.5, 12),
					fixture.GroundTopPosition + Vector3.new(0, 0.15, 0)
				)
				resumeAndGround(fixture, 0)

				local expectedGroundDistance = fixture.Root.Position.Y
					- fixture.Root.Size.Y / 2
					- fixture.GroundTopPosition.Y

				expectClose(fixture.Sampler:GetSnapshot().GroundDistance, expectedGroundDistance)

				local character = Instance.new("Model")

				character.Name = "IgnoredDriverCharacter"
				character.Parent = fixture.Container

				createQueryPart(
					character,
					"CharacterProbeBlocker",
					Vector3.new(12, 0.5, 12),
					fixture.GroundTopPosition + Vector3.new(0, 0.15, 0)
				)

				local characterHit = fixture.Sampler:SampleNow(0.2)

				character.Parent = nil
				fixture.Sampler:SetIgnoredCharacter(character)
				character.Parent = fixture.Container

				fixture.Sampler:SetIgnoredCharacter(character)

				local groundHit = fixture.Sampler:SampleNow(0.3)

				expect(characterHit.HitCount).to.equal(3)
				expect(characterHit.GroundDistance < expectedGroundDistance).to.equal(true)
				expect(groundHit.HitCount).to.equal(3)
				expectClose(groundHit.GroundDistance, expectedGroundDistance)
			end)
		end)

		it("resets, destroys, and exposes only immutable snapshots", function()
			withFixture(function(fixture)
				resumeAndGround(fixture, 0)

				local grounded = fixture.Sampler:GetSnapshot()
				local groundedSampleCount = grounded.SampleCount
				local groundedRevision = grounded.Revision

				expect(table.isfrozen(grounded)).to.equal(true)

				local mutationSucceeded = pcall(function()
					(grounded :: any).State = "Airborne"
				end)

				expect(mutationSucceeded).to.equal(false)
				expect(fixture.Sampler:GetSnapshot().State).to.equal("Grounded")

				fixture.Sampler:Reset()

				local reset = fixture.Sampler:GetSnapshot()

				expect(table.isfrozen(reset)).to.equal(true)
				expect((reset :: any) == (grounded :: any)).to.equal(false)
				expect(reset.State).to.equal("Airborne")
				expect(reset.SampleCount).to.equal(groundedSampleCount)
				expect(reset.Revision).to.equal(groundedRevision + 1)
				expect(fixture.Sampler:ShouldSample(1, 15)).to.equal(true)

				fixture.Sampler:Destroy()
				fixture.Sampler:Resume()
				fixture.Sampler:Reset()

				expect(fixture.Sampler:ShouldSample(2, 15)).to.equal(false)
				expect((fixture.Sampler:SampleNow(2) :: any) == (reset :: any)).to.equal(true)
				expect((fixture.Sampler:GetSnapshot() :: any) == (reset :: any)).to.equal(true)
			end)
		end)
	end)
end
