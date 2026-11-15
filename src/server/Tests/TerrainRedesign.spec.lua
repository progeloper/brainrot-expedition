--!nocheck
-- TerrainRedesign (V5 world + Storm): polygon maths, the guard's Storm response, carry safety,
-- builder determinism, quality tiers and the flag swap. No profile, economy or Play state.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Geometry = require(RS.Shared.Utility.StormGeometry)
	local Boundaries = require(RS.Shared.Config.StormBoundaries)
	local Rules = require(RS.Shared.Utility.WorldPresentationRules)
	local Builder = require(RS.Shared.Utility.TerrainBuilder)
	local FeatureFlags = require(RS.Shared.Config.FeatureFlags)
	local Progression = require(RS.Shared.Config.WorldProgression)
	local Guard = require(script.Parent.Parent.Services.RegionBoundaryGuard)
	local Response = require(script.Parent.Parent.Services.StormBoundaryResponse)
	local Switch = require(script.Parent.Parent.Utility.TerrainRedesignSwitch)

	local function near(a, b, t)
		assert(math.abs(a - b) < (t or 1e-6), tostring(a) .. " differs from " .. tostring(b))
	end

	it("contains points in the concave Beach footprint and rejects the notch", function()
		local beach = Boundaries.Beach.points
		assert(Geometry.Contains(beach, -627, -46), "Beach west column")
		assert(Geometry.Contains(beach, -387, -564), "Beach north-east arm")
		assert(not Geometry.Contains(beach, -387, -384), "the L notch belongs to the Forest")
		assert(not Geometry.Contains(beach, -19, -46), "the Camp is outside")
	end)

	it(
		"returns the nearest edge with a unit outward normal, including inside the concave corner",
		function()
			local beach = Boundaries.Beach.points
			-- Just inside the east edge of the west column (x = -507), next to the Forest notch.
			local hit = Geometry.NearestEdge(beach, -510, -384)
			near(hit.distance, 3)
			near(hit.normal.X, 1)
			near(hit.normal.Y, 0)
			near(hit.normal.Magnitude, 1)
			-- Inside the north-east arm, nearest its south edge (z = -474) under the notch.
			local arm = Geometry.NearestEdge(beach, -380, -478)
			near(arm.normal.Y, 1)
			local exits = Geometry.ExitCandidates(beach, -510, -384, 8)
			assert(#exits > 0, "an exit exists")
			assert(
				not Geometry.Contains(beach, exits[1].point.X, exits[1].point.Y),
				"exit lands outside"
			)
			near(exits[1].point.X, -499)
		end
	)

	it("splits curtain edges into segments no longer than 48 studs", function()
		for key, boundary in Boundaries do
			for _, segment in Geometry.Segments(boundary.points, 48) do
				assert((segment.b - segment.a).Magnitude <= 48 + 1e-6, key .. " segment too long")
			end
		end
	end)

	local function stormFixture(allowed)
		local time = 0
		local log = { pushes = 0, moves = 0, legacy = 0, records = {} }
		local response = Response.new({
			Boundaries = Boundaries,
			KeyForRegion = function(id)
				return if id == "REGION_BEACH" then "Beach" else nil
			end,
			Now = function()
				return time
			end,
			Push = function(_, key, normal)
				log.pushes += 1
				log.normal = normal
				log.key = key
			end,
			ResolveLanding = function(_, point)
				return Vector3.new(point.X, 0, point.Y)
			end,
			Move = function(entity, landing)
				log.moves += 1
				entity.position = landing
				return true
			end,
			LegacyCorrect = function()
				log.legacy += 1
				return true
			end,
			Record = function(name, data)
				table.insert(log.records, { name = name, data = data })
			end,
		})
		local carried = { id = "BRT_001" }
		local entity = {
			id = {},
			members = { { UserId = 1 } },
			ready = true,
			alive = true,
			position = Vector3.new(-510, 0, -384),
			velocity = Vector3.zero,
			forward = Vector3.new(-1, 0, 0),
			extent = 1,
			lateralExtent = 1,
			carried = carried,
		}
		local access = {}
		function access:GetEffectiveAccess()
			return allowed
		end
		function access:GetCartEntryAccess()
			return { allowed = allowed, code = "RegionAccessRequired" }
		end
		local descriptors = {}
		function descriptors:GetGate()
			return nil
		end
		function descriptors:GetRegionAtPosition(p)
			return if Geometry.Contains(Boundaries.Beach.points, p.X, p.Z)
				then "REGION_BEACH"
				else "REGION_FOREST"
		end
		local guard = Guard.new({
			Access = access,
			Descriptors = descriptors,
			GetEntities = function()
				return { entity }
			end,
			Correct = function()
				log.legacy += 1
			end,
			SetDenied = function() end,
			StopInward = function() end,
			Notice = function() end,
			Storm = response,
		})
		return {
			guard = guard,
			entity = entity,
			log = log,
			carried = carried,
			advance = function(n)
				time += n
			end,
		}
	end

	it("pushes first, then moves the entity outside after the 0.6 s grace", function()
		local f = stormFixture(false)
		f.guard:Step()
		expect(f.log.pushes).to.equal(1)
		near(f.log.normal.X, 1)
		near(f.log.normal.Y, 0)
		f.advance(0.3)
		f.guard:Step()
		expect(f.log.moves).to.equal(0)
		f.advance(0.31)
		f.guard:Step()
		expect(f.log.moves).to.equal(1)
		expect(f.log.legacy).to.equal(0)
		assert(
			not Geometry.Contains(Boundaries.Beach.points, f.entity.position.X, f.entity.position.Z),
			"moved outside"
		)
		expect(f.log.records[1].name).to.equal("StormPushed")
		expect(f.log.records[1].data.fallbackUsed).to.equal(true)
	end)

	it("records a push without fallback when the client push was enough", function()
		local f = stormFixture(false)
		f.guard:Step()
		f.entity.position = Vector3.new(-480, 0, -384) -- the client push carried it out
		f.guard:Step()
		expect(f.log.moves).to.equal(0)
		expect(f.log.records[1].data.fallbackUsed).to.equal(false)
	end)

	it("never changes carry state while pushing or moving", function()
		local f = stormFixture(false)
		local before = f.entity.carried
		f.guard:Step()
		f.advance(1)
		f.guard:Step()
		expect(f.entity.carried).to.equal(before)
		expect(f.carried.id).to.equal("BRT_001")
	end)

	it("never pushes a player who has unlocked the region", function()
		local f = stormFixture(true)
		f.guard:Step()
		f.advance(1)
		f.guard:Step()
		expect(f.log.pushes).to.equal(0)
		expect(f.log.moves).to.equal(0)
		expect(f.log.legacy).to.equal(0)
	end)

	it("derives locked regions from the progression summary", function()
		local locked = Rules.LockedKeys({ personalUnlocks = { Beach = true } }, Progression.Ordered)
		assert(
			locked.Beach == nil and locked.Swamp == true and locked.GlitchZone == true,
			"locked set"
		)
		assert(locked.Forest == nil and locked.Camp == nil, "open regions are never locked")
		local none = Rules.LockedKeys(nil, Progression.Ordered)
		assert(none.Beach and none.Volcano, "no summary yet = every gated region locked")
	end)

	it("selects quality tiers and drops one tier on a slow probe", function()
		expect(Rules.SelectTier(0, 16, 33)).to.equal("Full")
		expect(Rules.SelectTier(8, 40, 33)).to.equal("Reduced")
		expect(Rules.SelectTier(5, 20, 33)).to.equal("Reduced")
		expect(Rules.SelectTier(2, 20, 33)).to.equal("Minimal")
		expect(Rules.SelectTier(2, 50, 33)).to.equal("Minimal")
		near(Rules.Median({ 10, 30, 20 }), 20)
	end)

	it("keeps toys off carriers and cart seats", function()
		expect(Rules.ToyAllowed(false, false)).to.equal(true)
		expect(Rules.ToyAllowed(true, false)).to.equal(false)
		expect(Rules.ToyAllowed(false, true)).to.equal(false)
		local v = Rules.PushVelocity(Vector3.new(1, 0, 0), 55, 25, false)
		near(v.X, 55)
		near(v.Y, 25)
	end)

	it("discovers each POI once per session", function()
		local seen = {}
		local pois = { { name = "Funghi Ring", center = { 0, 0 }, radius = 10 } }
		expect(#Rules.Discover(pois, seen, 3, 3)).to.equal(1)
		expect(#Rules.Discover(pois, seen, 3, 3)).to.equal(0)
		expect(#Rules.Discover(pois, {}, 30, 30)).to.equal(0)
	end)

	it("predicts the Storm push only inside a locked region", function()
		local locked = { Beach = true }
		expect(Rules.PredictPush({}, Boundaries, Geometry, Vector3.new(-627, 3, -46))).to.equal(nil)
		expect(Rules.PredictPush(locked, Boundaries, Geometry, Vector3.new(-19, 3, -46))).to.equal(
			nil
		)
		local message = Rules.PredictPush(locked, Boundaries, Geometry, Vector3.new(-510, 3, -384))
		assert(message, "inside the Beach next to the Forest notch")
		expect(message.kind).to.equal("Push")
		expect(message.regionKey).to.equal("Beach")
		near(message.normal.X, 1)
		near(message.normal.Magnitude, 1)
		near(message.exit.X, -507)
		near(message.exit.Y, 3)
	end)

	it("keeps the island rim off natural-spawn ground and hides only perimeter visuals", function()
		-- Natural spawns sample the inner 80% of each floor part; the perimeter colliders sit at
		-- x -747..-739, x 701..709, z -654..-646 and z 522..562. Rim pieces stay behind these limits.
		local pieces = 0
		for _, key in { "Forest", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" } do
			local region = require(RS.Shared.Config.TerrainRegions[key])
			for _, block in region.rim or {} do
				pieces += 1
				local lo, hi = block.min, block.max
				local behind = hi[1] <= -732 or lo[1] >= 694 or hi[3] <= -644 or lo[3] >= 524
				assert(behind, key .. " rim piece reaches natural-spawn ground")
			end
			for _, name in region.hidesLegacy or {} do
				assert(
					string.match(name, "^EV2_Run_0[1234]"),
					key .. " hides a non-perimeter model " .. name
				)
			end
		end
		assert(pieces > 200, "island rim present on every edge")
	end)

	it("CP-B and CP-C regions use only their own stud-backed terrain materials", function()
		local Palette = require(RS.Shared.Config.TerrainPalette)
		-- Terrain materials without an AF2 stud override render their stock texture (Studio read, 9 Nov).
		local unstudded = { WoodPlanks = true, Brick = true, Pavement = true, Cobblestone = true }
		-- These render a rough or stud-snapped surface (Studio test fill, 9 Nov), so no region's
		-- ground (where the cart lanes run) may use them.
		local uneven =
			{ Rock = true, Slate = true, Basalt = true, CrackedLava = true, Pavement = true }
		for _, key in { "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" } do
			local region = require(RS.Shared.Config.TerrainRegions[key])
			assert(not uneven[region.materials.ground], key .. " ground material is uneven")
			-- The Glitch Zone's cliff faces are Pavement on purpose (no flat stud material is left).
			local allowed = if key == "GlitchZone" then { Pavement = true } else {}
			for _, list in
				{ region.terraces, region.wedges or {}, region.rocks or {}, region.rim or {} }
			do
				for _, shape in list do
					local material = shape.material
					expect(Palette.Owner[material]).to.equal(key)
					assert(
						allowed[material] or not unstudded[material],
						key .. " uses unstudded " .. material
					)
				end
			end
		end
	end)

	it("CP-B and CP-C palettes cover every kit role and meet the ground colour rules", function()
		local Palette = require(RS.Shared.Config.TerrainPalette)
		local kits = {}
		for _, m in RS.Shared.Config.TerrainKits:GetChildren() do
			kits[m.Name] = require(m)
		end
		local hue = {}
		for _, key in
			{ "Forest", "Camp", "Beach", "Swamp", "Jungle", "Arctic", "Volcano", "GlitchZone" }
		do
			local region = require(RS.Shared.Config.TerrainRegions[key])
			local h, sat, val = Color3.fromHex(region.palette.ground):ToHSV()
			hue[key] = h * 360
			if key ~= "Camp" and key ~= "Forest" then
				assert(sat >= 0.45 and val >= 0.6, key .. " ground saturation/value")
				local entries = { region.landmark }
				for _, group in { region.clusters, region.signs, region.secrets, region.toys } do
					for _, e in group or {} do
						table.insert(entries, e)
					end
				end
				for _, e in entries do
					local kit = kits[e.kit]
					assert(kit, key .. " unknown kit " .. tostring(e.kit))
					for _, b in kit.boxes do
						local hex = (e.palette and e.palette[b.role])
							or (kit.palette and kit.palette[b.role])
							or region.palette[b.role]
							or Palette.Shared[b.role]
						assert(hex, key .. " " .. e.kit .. " has no colour for role " .. b.role)
					end
				end
			end
		end
		local function gap(a, b)
			local d = math.abs(hue[a] - hue[b]) % 360
			return math.min(d, 360 - d)
		end
		-- Neighbouring region pairs (shared floor edges) keep a 25 degree hue gap (W5).
		for _, pair in
			{
				{ "Beach", "Forest" },
				{ "Beach", "Swamp" },
				{ "Swamp", "Forest" },
				{ "Swamp", "Jungle" },
				{ "Jungle", "Camp" },
				{ "Arctic", "Forest" },
				{ "Arctic", "Volcano" },
				{ "Volcano", "Camp" },
				{ "Volcano", "GlitchZone" },
				{ "GlitchZone", "Jungle" },
			}
		do
			assert(gap(pair[1], pair[2]) >= 24.5, pair[1] .. "/" .. pair[2] .. " hue gap")
		end
	end)

	it("builds kits and terrain deterministically", function()
		local kits = {}
		for _, m in RS.Shared.Config.TerrainKits:GetChildren() do
			kits[m.Name] = require(m)
		end
		local forest = require(RS.Shared.Config.TerrainRegions.Forest)
		local a = Builder.BuildKit(kits.Forest_HeroTree, CFrame.new(), 1, forest.palette)
		local b = Builder.BuildKit(kits.Forest_HeroTree, CFrame.new(), 1, forest.palette)
		local fa, fb = Builder.Fingerprint(a), Builder.Fingerprint(b)
		expect(fa.parts).to.equal(fb.parts)
		expect(fa.neon).to.equal(fb.neon)
		assert(fa.parts <= 220, "hero landmark part budget")
		for i, part in a:GetChildren() do
			local other = b:GetChildren()[i]
			if part:IsA("BasePart") then
				expect(part.Name).to.equal(other.Name)
				assert(
					part.CFrame == other.CFrame
						and part.Size == other.Size
						and part.Color == other.Color,
					part.Name
				)
			end
		end
		a:Destroy()
		b:Destroy()
		-- Terrain: shape a small off-map sample twice and compare material counts.
		local terrain = workspace.Terrain
		local sample = {
			key = "Sample",
			terraces = {
				{ min = { 2000, -8, 2000 }, max = { 2032, -2.2, 2032 }, material = "Grass" },
				{ min = { 2008, -2.2, 2008 }, max = { 2024, 6, 2024 }, material = "Rock" },
			},
		}
		local region = Region3.new(Vector3.new(1996, -12, 1996), Vector3.new(2036, 12, 2036))
			:ExpandToGrid(4)
		local function counts()
			local materials = terrain:ReadVoxels(region, 4)
			local c = {}
			for x = 1, materials.Size.X do
				for y = 1, materials.Size.Y do
					for z = 1, materials.Size.Z do
						local m = materials[x][y][z].Name
						c[m] = (c[m] or 0) + 1
					end
				end
			end
			return c
		end
		Builder.ShapeTerrain(terrain, sample, 100)
		local first = counts()
		terrain:FillRegion(region, 4, Enum.Material.Air)
		Builder.ShapeTerrain(terrain, sample, 100)
		local second = counts()
		terrain:FillRegion(region, 4, Enum.Material.Air)
		for m, n in first do
			expect(second[m]).to.equal(n)
		end
		assert((first.Rock or 0) > 0 and (first.Grass or 0) > 0, "sample shaped")
	end)

	it("retires the terrain flag and reports a missing V5 store without activating", function()
		expect((FeatureFlags :: any).TerrainRedesignEnabled).to.equal(nil)
		local store = game:GetService("ServerStorage"):FindFirstChild("TerrainRedesign")
		if not store then
			local ok, applied = pcall(Switch.Apply, Instance.new("Folder"))
			assert(ok, tostring(applied))
			expect(applied).to.equal(false)
			expect(workspace:GetAttribute("TerrainRedesignActive")).to.equal(nil)
		end
	end)

	-- CP-D: island edge and out-of-bounds sea mist.
	local Edge = require(RS.Shared.Config.IslandEdge)
	local EdgeMath = require(RS.Shared.Utility.IslandEdgeMath)
	local Mist = require(script.Parent.Parent.Services.OutOfBoundsResponse)

	it("classifies the island edge and points every escape back inward", function()
		local rect = Edge.Playable
		assert(not EdgeMath.IsOutside(rect, 4, 703, 0), "inside the collider overlap margin")
		assert(EdgeMath.IsOutside(rect, 4, 706, 0), "past the east collider")
		assert(EdgeMath.IsOutside(rect, 4, 0, -660), "past the north collider")
		local d, point, normal = EdgeMath.Nearest(rect, 720, 0)
		near(d, -19)
		near(point.X, 701)
		near(normal.X, -1)
		near(normal.Y, 0)
		d, point, normal = EdgeMath.Nearest(rect, 0, 500)
		near(d, 22)
		near(normal.Y, -1)
		-- Outside a corner the normal runs back along the diagonal.
		_, point, normal = EdgeMath.Nearest(rect, 711, 532)
		near(point.X, 701)
		near(point.Y, 522)
		near(normal.X, -math.sqrt(0.5))
		near(normal.Y, -math.sqrt(0.5))
		for _, probe in EdgeMath.Landings(rect, 900, 600, Edge.LandingInsets) do
			assert(not EdgeMath.IsOutside(rect, 0, probe.X, probe.Y), "landing stays on the island")
			assert(probe.X <= rect.max.X - 40 and probe.Y <= rect.max.Y - 40, "landing is inset")
		end
		local outline = EdgeMath.Outline(Edge.Coast, Edge.Mist.Offset)
		expect(#outline).to.equal(4)
		near(outline[1].X, Edge.Coast.min.X - Edge.Mist.Offset)
		-- The sea sits below the lane ground and the coast lies beyond every playable face.
		assert(Edge.Ocean.SurfaceY < -0.48, "ocean surface below the lane ground")
		assert(Edge.Coast.min.X < rect.min.X and Edge.Coast.max.X > rect.max.X, "coast outside x")
		assert(Edge.Coast.min.Y < rect.min.Y and Edge.Coast.max.Y > rect.max.Y, "coast outside z")
	end)

	local function mistRig(options)
		options = options or {}
		local log = { pushes = {}, moves = {}, records = {} }
		local clock = 0
		local response = Mist.new({
			Edge = Edge,
			Now = function()
				return clock
			end,
			Push = function(entity, normal, exit)
				table.insert(log.pushes, { entity = entity, normal = normal, exit = exit })
			end,
			ResolveLanding = function(_, point)
				if options.noShore then
					return nil
				end
				return Vector3.new(point.X, 0, point.Y)
			end,
			Move = function(entity, landing)
				table.insert(log.moves, landing)
				entity.position = landing
				return true
			end,
			Hub = function()
				return Vector3.new(-100, 0, -120)
			end,
			Storming = function(_entity)
				return options.storming == true
			end,
			Record = function(data)
				table.insert(log.records, data)
			end,
		})
		return response, log, function(dt)
			clock += dt
		end
	end

	it(
		"pushes an entity past the edge, then moves it to the shore after the grace period",
		function()
			local response, log, advance = mistRig()
			local carrying = { carried = "BRT_006" }
			local entity = {
				id = "p1",
				ready = true,
				alive = true,
				position = Vector3.new(0, 2, 0),
				carry = carrying,
			}
			expect(response:Handle(entity)).to.equal("Inside")
			entity.position = Vector3.new(730, 90, 100)
			expect(response:Handle(entity)).to.equal("Pushed")
			expect(#log.pushes).to.equal(1)
			near(log.pushes[1].normal.X, -1)
			advance(0.3)
			expect(response:Handle(entity)).to.equal("Waiting")
			advance(0.4)
			expect(response:Handle(entity)).to.equal("Shore")
			near(log.moves[1].X, 701 - 40)
			expect(entity.carry).to.equal(carrying)
			expect(entity.carry.carried).to.equal("BRT_006")
			expect(log.records[1].fallbackUsed).to.equal(true)
			expect(log.records[1].regionKey).to.equal("OutOfBounds")
		end
	)

	it("clears quietly when the client push alone returns the entity", function()
		local response, log, advance = mistRig()
		local entity = { id = "p2", ready = true, alive = true, position = Vector3.new(0, 0, -700) }
		expect(response:Handle(entity)).to.equal("Pushed")
		advance(0.2)
		entity.position = Vector3.new(0, 0, -600)
		expect(response:Handle(entity)).to.equal("Cleared")
		expect(#log.moves).to.equal(0)
		expect(log.records[1].fallbackUsed).to.equal(false)
	end)

	it("returns a fallen entity at once to its last safe point, then the hub", function()
		local response, log = mistRig({ noShore = true })
		local entity =
			{ id = "p3", ready = true, alive = true, position = Vector3.new(-200, 3, -400) }
		response:Handle(entity)
		entity.position = Vector3.new(-200, -60, -400)
		expect(response:Handle(entity)).to.equal("LastSafe")
		near(log.moves[1].Y, 3)
		local stranger =
			{ id = "p4", ready = true, alive = true, position = Vector3.new(0, -80, 0) }
		expect(response:Handle(stranger)).to.equal("Hub")
	end)

	it("never records a safe point while the Storm is handling the entity", function()
		local response, log = mistRig({ noShore = true, storming = true })
		local entity =
			{ id = "p5", ready = true, alive = true, position = Vector3.new(400, 0, -500) }
		response:Handle(entity)
		entity.position = Vector3.new(400, -60, -500)
		expect(response:Handle(entity)).to.equal("Hub")
		expect(#log.moves).to.equal(1)
	end)

	it("skips entities that are not ready and forgets departed ones", function()
		local response = mistRig()
		local entity = { id = "p6", ready = false, alive = true, position = Vector3.new(900, 0, 0) }
		expect(response:Handle(entity)).to.equal("Skipped")
		entity.ready = true
		response:Step({ entity })
		expect(response.active.p6 ~= nil).to.equal(true)
		response:Step({})
		expect(response.active.p6).to.equal(nil)
		expect(response.safe.p6).to.equal(nil)
	end)
end
