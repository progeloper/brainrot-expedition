--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config.VillagerGuards)
	local FeatureFlags = require(RS.Shared.Config.FeatureFlags)
	local Rules = require(RS.Shared.Utility.VillagerChaseRules)
	local Builder = require(RS.Shared.Utility.VillagerKitBuilder)
	local Roster = require(RS.Shared.Config.VillagerRoster)
	local Carts = require(RS.Shared.Config.Carts)
	local Service = require(script.Parent.Parent.Services.VillagerGuardService)

	-- Fake world: flat ground at y = 0, everything x > 1000 is a safe zone (base/Camp),
	-- everything z > 2000 is a region the player hasn't unlocked.
	local function makeWorld(options)
		options = options or {}
		local world = {
			time = 0,
			fired = {},
			slows = {},
			records = {},
			cargo = { "ITEM_1" },
			carry = { carrying = true },
			seats = { driver = 1 },
			cartPosition = Vector3.new(0, 0, 0),
			playerPosition = Vector3.new(0, 0, 0),
			rarity = options.rarity or "Common",
		}
		local player = { UserId = 101, Name = "Tester", Parent = true }
		local cart = { Parent = true }
		world.player, world.cart = player, cart
		Service.Reset()
		Service.onCleanEscape = nil
		Service.Configure({
			now = function()
				return world.time
			end,
			getCart = function()
				return if world.noCart then nil else cart
			end,
			cartPosition = function()
				return world.cartPosition
			end,
			cartTopSpeed = function()
				return 48
			end,
			cargoProfile = function()
				return world.rarity, "#FFFFFF"
			end,
			playerPosition = function()
				return world.playerPosition
			end,
			isSafePosition = function(position)
				return position.X > 1000
			end,
			canEnter = function(_, position)
				return position.Z <= 2000
			end,
			regionAt = function()
				return "REGION_FOREST"
			end,
			groundY = function()
				return 0
			end,
			applySlow = function(target, factor, untilTime)
				table.insert(world.slows, { cart = target, factor = factor, untilTime = untilTime })
			end,
			recipients = function(p)
				return { p }
			end,
			fire = function(p, payload)
				table.insert(world.fired, { player = p, payload = payload })
			end,
			publish = function() end,
			record = function(_, name, value, category, result)
				table.insert(
					world.records,
					{ name = name, value = value, category = category, result = result }
				)
			end,
			players = function()
				return { player }
			end,
		})
		local villagers = options.villagers
			or {
				{
					id = "S",
					name = "Sprinter",
					type = "Sprinter",
					kit = "Sprinter",
					home = { 30, 0 },
				},
				{
					id = "P",
					name = "Plodder",
					type = "Plodder",
					kit = "Plodder",
					home = { -30, 0 },
				},
			}
		Service.LoadRoster({ { regionId = "REGION_FOREST", villagers = villagers } })
		function world.advance(seconds)
			local step = 0.1
			local elapsed = 0
			while elapsed < seconds - 1e-6 do
				world.time += step
				elapsed += step
				Service.Step(step)
			end
		end
		function world.kinds()
			local out = {}
			for _, entry in world.fired do
				table.insert(out, entry.payload.kind)
			end
			return table.concat(out, ",")
		end
		function world.last(kind)
			for index = #world.fired, 1, -1 do
				if world.fired[index].payload.kind == kind then
					return world.fired[index].payload
				end
			end
			return nil
		end
		return world
	end

	describe("ring radius by rarity", function()
		it("grows with rarity and uses the largest rarity in the cart", function()
			local previous = 0
			for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
				local radius = Rules.RingRadius(rarity, false)
				expect(radius > previous).to.equal(true)
				previous = radius
			end
			expect(Rules.RingRadius("Celestial", false)).to.equal(Rules.RingRadius("Mythic", false))
			expect(Config.highestRarity({ "Common", "Epic", "Uncommon" })).to.equal("Epic")
			expect(Rules.RingRadius("Common", true)).to.equal(
				Config.RingRadiusByRarity.Common * 1.15
			)
		end)

		it("takes 4-10 s to cross from rest on every real cart", function()
			for _, cart in Carts do
				for rarity, radius in Config.RingRadiusByRarity do
					local seconds =
						Rules.CrossingSeconds(radius, cart.MaxTravelSpeed, cart.ForwardAcceleration)
					expect(seconds >= 4 and seconds <= 10).to.equal(true)
					expect(rarity ~= nil).to.equal(true)
				end
			end
		end)

		it("keeps a reasonably driven cart faster than a Plodder", function()
			local plodder = Rules.ChaseSpeed("Plodder", 5, 43.2, false)
			expect(plodder < 43.2).to.equal(true)
			local sprinterLate = Rules.ChaseSpeed("Sprinter", 4, 48, false)
			expect(sprinterLate < 48).to.equal(true)
			expect(Rules.ChaseSpeed("Shouter", 0, 48, false)).to.equal(0)
		end)
	end)

	describe("state machine", function()
		it("hit inside the notice radius makes villagers suspicious; outside stays idle", function()
			local world = makeWorld({
				villagers = {
					{
						id = "NEAR",
						name = "Near",
						type = "Plodder",
						kit = "Plodder",
						home = { 50, 0 },
					},
					{
						id = "FAR",
						name = "Far",
						type = "Plodder",
						kit = "Plodder",
						home = { 200, 0 },
					},
				},
			})
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			expect(Service.GetVillager("NEAR").state).to.equal("Suspicious")
			expect(Service.GetVillager("FAR").state).to.equal("Idle")
			-- "?" never tags: walk toward the player but stop at the standoff.
			world.advance(10)
			local near = Service.GetVillager("NEAR")
			expect(near.state).to.equal("Suspicious")
			expect(
				Rules.FlatDistance(near.position, world.playerPosition)
					>= Config.SuspiciousStandoff - 0.01
			).to.equal(true)
			expect(#world.slows).to.equal(0)
		end)

		it("another nearby hit refreshes a villager's '?' timer", function()
			local world = makeWorld({
				villagers = {
					{ id = "P", name = "P", type = "Plodder", kit = "Plodder", home = { 40, 0 } },
				},
			})
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			world.advance(Config.SuspiciousTimeoutSeconds - 5)
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			world.advance(10)
			expect(Service.GetVillager("P").state).to.equal("Suspicious")
		end)

		it("no '?' means a silent load with SNEAKY!", function()
			local world = makeWorld()
			Service.OnCargoLoaded(world.player)
			expect(world.kinds()).to.equal("Sneaky")
			expect(Service.GetChase(101)).to.equal(nil)
			expect(world.records[1].name).to.equal("SneakyLoad")
		end)

		it("load after '?' winds up for 0.75 s then chases, ring centred on the load", function()
			local world = makeWorld({ rarity = "Rare" })
			world.cartPosition = Vector3.new(5, 0, 5)
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			Service.OnCargoLoaded(world.player)
			local started = world.last("ChaseStarted")
			expect(started ~= nil).to.equal(true)
			expect(started.center).to.equal(Vector3.new(5, 0, 5))
			expect(started.radius).to.equal(Config.RingRadiusByRarity.Rare)
			expect(Service.GetVillager("S").state).to.equal("WindUp")
			world.advance(0.5)
			expect(Service.GetVillager("S").state).to.equal("WindUp")
			world.advance(0.3)
			expect(Service.GetVillager("S").state).to.equal("Chase")
		end)

		it("crossing the ring ends with ESCAPED, chasers tantrum and an 8 s cooldown", function()
			local world = makeWorld()
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			world.cartPosition = Vector3.new(0, 0, -60) -- loaded a little away from the villagers
			Service.OnCargoLoaded(world.player)
			world.advance(1)
			world.cartPosition = Vector3.new(0, 0, -60 - (Config.RingRadiusByRarity.Common + 1))
			world.advance(0.1)
			local ended = world.last("ChaseEnded")
			expect(ended.result).to.equal("Escaped")
			expect(ended.clean).to.equal(true)
			expect(Service.GetVillager("S").state).to.equal("GiveUp")
			world.advance(Config.TantrumSeconds + 0.1)
			expect(Service.GetVillager("S").state).to.equal("Return")
			-- Cooldown: a fresh hit right next to them is ignored for 8 s...
			world.cartPosition = Vector3.new(0, 0, 0)
			Service.OnHit(world.player, Service.GetVillager("S").position)
			expect(Service.GetVillager("S").state ~= "Suspicious").to.equal(true)
			-- ...and noticed again after it expires.
			world.advance(Config.GiveUpCooldownSeconds)
			Service.OnHit(world.player, Service.GetVillager("S").position)
			expect(Service.GetVillager("S").state).to.equal("Suspicious")
		end)

		it(
			"a tag slows the cart only, never touches cargo/carry/seats, and the villager gives up",
			function()
				local world = makeWorld({
					villagers = {
						{
							id = "S",
							name = "S",
							type = "Sprinter",
							kit = "Sprinter",
							home = { 20, 0 },
						},
					},
				})
				local cargoBefore = table.concat(world.cargo, ",")
				Service.OnHit(world.player, Vector3.new(0, 0, 0))
				Service.OnCargoLoaded(world.player)
				-- Boarding grace: nobody tags a parked cart while the player climbs in.
				world.advance(Config.Tag.GraceSeconds - 0.3)
				expect(#world.slows).to.equal(0)
				-- Cart still parked after the grace: step until the sprinter reaches it.
				local waited = 0
				while #world.slows == 0 and waited < 3 do
					world.advance(0.1)
					waited += 0.1
				end
				expect(#world.slows).to.equal(1)
				expect(world.slows[1].factor).to.equal(Config.Tag.SpeedMultiplier)
				expect(
					math.abs(world.slows[1].untilTime - (world.time + Config.Tag.SlowSeconds))
						< 1e-6
				).to.equal(true)
				expect(world.last("ChaseTag").villagerId).to.equal("S")
				expect(Service.GetVillager("S").state).to.equal("GiveUp")
				expect(table.concat(world.cargo, ",")).to.equal(cargoBefore)
				expect(world.carry.carrying).to.equal(true)
				expect(world.seats.driver).to.equal(1)
				-- Once per chase: no second slow from the same villager.
				world.advance(3)
				expect(#world.slows).to.equal(1)
				world.cartPosition = Vector3.new(0, 0, 500)
				world.advance(0.2)
				expect(world.last("ChaseEnded").clean).to.equal(false)
			end
		)

		it("no chase lasts longer than 12 s", function()
			local world = makeWorld({
				villagers = {
					{ id = "P", name = "P", type = "Shouter", kit = "Shouter", home = { 20, 0 } },
				},
			})
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			Service.OnCargoLoaded(world.player)
			world.advance(11.5)
			expect(Service.GetChase(101) ~= nil).to.equal(true)
			world.advance(0.6)
			expect(Service.GetChase(101)).to.equal(nil)
			expect(world.last("ChaseEnded").result).to.equal("Timeout")
		end)

		it("a second load during a chase re-centres the ring and refreshes the timer", function()
			local world = makeWorld()
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			Service.OnCargoLoaded(world.player)
			world.advance(8)
			world.cartPosition = Vector3.new(60, 0, 0)
			world.rarity = "Epic"
			Service.OnCargoLoaded(world.player)
			local recentred = world.last("ChaseRecentred")
			expect(recentred.center).to.equal(Vector3.new(60, 0, 0))
			expect(recentred.radius).to.equal(Config.RingRadiusByRarity.Epic)
			world.advance(8)
			expect(Service.GetChase(101) ~= nil).to.equal(true)
		end)

		it(
			"ends instantly when the cart reaches a safe zone and villagers never step into one",
			function()
				local world = makeWorld({
					villagers = {
						{
							id = "P",
							name = "P",
							type = "Plodder",
							kit = "Plodder",
							home = { 990, 0 },
						},
					},
				})
				world.cartPosition = Vector3.new(985, 0, 0)
				world.playerPosition = Vector3.new(985, 0, 0)
				Service.OnHit(world.player, Vector3.new(990, 0, 0))
				Service.OnCargoLoaded(world.player)
				world.advance(0.8)
				world.cartPosition = Vector3.new(1010, 0, 0) -- into the base
				world.advance(0.1)
				expect(world.last("ChaseEnded").result).to.equal("ReachedSafeZone")
				expect(Service.GetVillager("P").position.X <= 1000).to.equal(true)
			end
		)

		it("villagers stop at a locked region (Storm edge) and give up", function()
			local world = makeWorld({
				villagers = {
					{ id = "P", name = "P", type = "Plodder", kit = "Plodder", home = { 0, 1990 } },
				},
			})
			world.cartPosition = Vector3.new(0, 0, 1985)
			world.playerPosition = world.cartPosition
			Service.OnHit(world.player, Vector3.new(0, 0, 1990))
			Service.OnCargoLoaded(world.player)
			world.advance(0.8)
			world.cartPosition = Vector3.new(0, 0, 2100)
			world.advance(0.3)
			expect(Service.GetVillager("P").position.Z <= 2000).to.equal(true)
			expect(Service.GetVillager("P").state).to.equal("GiveUp")
		end)

		it("never crosses a locked region and gives up at its edge, however it turns", function()
			-- Holds with natural motion on (turn-rate limit and ease-in) as well as off.
			local world = makeWorld({
				villagers = {
					{ id = "P", name = "P", type = "Plodder", kit = "Plodder", home = { 0, 1990 } },
				},
			})
			world.cartPosition = Vector3.new(0, 0, 1985)
			world.playerPosition = world.cartPosition
			Service.OnHit(world.player, Vector3.new(0, 0, 1990))
			Service.OnCargoLoaded(world.player)
			world.advance(0.8)
			world.cartPosition = Vector3.new(0, 0, 2100)
			local gaveUp = false
			for _ = 1, 30 do
				world.advance(0.1)
				expect(Service.GetVillager("P").position.Z <= 2000).to.equal(true)
				if Service.GetVillager("P").state == "GiveUp" then
					gaveUp = true
					break
				end
			end
			expect(gaveUp).to.equal(true)
		end)

		it("shouters alarm nearby villagers straight to '?'", function()
			local world = makeWorld({
				villagers = {
					{
						id = "SH",
						name = "Shouter",
						type = "Shouter",
						kit = "Shouter",
						home = { 20, 0 },
					},
					{
						id = "LATE",
						name = "Late",
						type = "Plodder",
						kit = "Plodder",
						home = { 75, 0 },
					},
				},
			})
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			expect(Service.GetVillager("LATE").state).to.equal("Idle")
			Service.OnCargoLoaded(world.player)
			expect(Service.GetVillager("LATE").state).to.equal("Suspicious")
			world.advance(0.8)
			expect(Service.GetVillager("LATE").state).to.equal("WindUp")
		end)
	end)

	describe("invisible assist", function()
		it("kicks in after two tagged chases and resets after a clean one", function()
			expect(
				Rules.IsAssisted(
					Rules.NextTaggedStreak(Rules.NextTaggedStreak(0, true, false), true, false)
				)
			).to.equal(true)
			expect(Rules.NextTaggedStreak(2, false, true)).to.equal(0)
			local world = makeWorld({
				villagers = {
					{ id = "S", name = "S", type = "Sprinter", kit = "Sprinter", home = { 20, 0 } },
				},
			})
			local function taggedChase()
				Service.OnHit(world.player, Vector3.new(0, 0, 0))
				Service.OnCargoLoaded(world.player)
				world.advance(3)
				world.cartPosition = Vector3.new(0, 0, 1000 + world.time)
				world.advance(0.2)
				world.cartPosition = Vector3.new(0, 0, 0)
				world.advance(Config.GiveUpCooldownSeconds + 20)
			end
			taggedChase()
			taggedChase()
			expect(Service.GetTaggedStreak(101)).to.equal(2)
			Service.OnHit(world.player, Vector3.new(0, 0, 0))
			Service.OnCargoLoaded(world.player)
			expect(world.last("ChaseStarted").radius).to.equal(
				Config.RingRadiusByRarity.Common * 1.15
			)
			expect(Service.GetChase(101).assisted).to.equal(true)
			world.cartPosition = Vector3.new(0, 0, -400) -- clean escape before anyone arrives
			world.advance(0.1)
			expect(Service.GetTaggedStreak(101)).to.equal(0)
		end)
	end)

	describe("roster, kits and flag", function()
		it("ships behind a single boolean flag", function()
			-- Owner authorised CP-D (flag on) on 10 Nov 2026; false removes the feature.
			expect(type(FeatureFlags.VillagerGuardsEnabled)).to.equal("boolean")
		end)

		it("every region has 4-6 villagers with every type, and kits stay within budget", function()
			local Footprints = require(RS.Shared.Config.RegionFootprints)
			local Storm = require(RS.Shared.Utility.StormGeometry)
			local footprintKey = {
				REGION_FOREST = "Forest",
				REGION_BEACH = "Beach",
				REGION_SWAMP = "Swamp",
				REGION_JUNGLE = "Jungle",
				REGION_ARCTIC = "Arctic",
				REGION_VOLCANO = "Volcano",
				REGION_GLITCH = "GlitchZone",
			}
			local ids = {}
			expect(#Roster >= 4).to.equal(true)
			for _, region in Roster do
				local types = {}
				expect(#region.villagers >= 4 and #region.villagers <= 6).to.equal(true)
				local points = Footprints[footprintKey[region.regionId]]
				expect(points ~= nil).to.equal(true)
				for _, row in region.villagers do
					expect(ids[row.id]).to.equal(nil)
					ids[row.id] = true
					types[row.type] = true
					local kit = require(RS.Shared.Config.VillagerKits:FindFirstChild(row.kit))
					expect(Builder.CountBoxes(kit, row.variant) <= 60).to.equal(true)
					local height = Builder.Height(kit, row.variant)
					expect(height >= 5.3 and height <= 6.1).to.equal(true)
					-- Home is inside its own region and never inside Camp.
					expect(Storm.Contains(points, row.home[1], row.home[2])).to.equal(true)
					expect(Storm.Contains(Footprints.Camp, row.home[1], row.home[2])).to.equal(
						false
					)
					for _, role in
						{
							"skin",
							"skin2",
							"cloth",
							"cloth2",
							"cloth3",
							"trim",
							"hair",
							"hat",
							"hat2",
							"shoe",
							"prop",
							"prop2",
							"glow",
						}
					do
						expect(type(row.palette[role])).to.equal("string")
					end
				end
				expect(types.Sprinter and types.Plodder and types.Shouter).to.equal(true)
			end
		end)

		it(
			"V15: dressed villagers wear all five outfit slots in card colours, one glow trim",
			function()
				local OutfitSets = require(RS.Shared.Config.VillagerOutfitSets)
				local dressed, total = 0, 0
				for _, region in Roster do
					for _, row in region.villagers do
						total += 1
						local outfit = OutfitSets.ForRow(row)
						if row.outfit then
							expect(outfit ~= nil).to.equal(true)
						end
						if outfit then
							dressed += 1
							local set = OutfitSets.Get(row.outfit)
							expect(set.regionId).to.equal(region.regionId)
							expect(type(set.reference)).to.equal("string")
							local kit =
								require(RS.Shared.Config.VillagerKits:FindFirstChild(row.kit))
							local boxes = Builder.Boxes(kit, row.variant, outfit)
							expect(#boxes <= 80).to.equal(true)
							local slots = Builder.OutfitSlots(boxes)
							for _, slot in { "headwear", "top", "bottom", "footwear", "accessory" } do
								expect(slots[slot]).to.equal(true)
							end
							-- Every clothing colour traces to the reference card palette.
							local allowed = {}
							for _, hex in set.palette do
								allowed[string.upper(hex)] = true
							end
							for _, role in outfit.outfitRoles do
								expect(allowed[string.upper(row.palette[role] or "")]).to.equal(
									true
								)
							end
							-- Region glow on exactly one trim line (props may glow).
							local glow = 0
							for _, item in boxes do
								if item.role == "glow" and item.group ~= "Prop" then
									glow += 1
								end
							end
							expect(glow).to.equal(1)
							expect(string.upper(row.palette.glow)).to.equal(string.upper(set.glow))
							local height = Builder.Height(kit, row.variant, outfit)
							expect(height >= 5.3 and height <= 6.1).to.equal(true)
						end
					end
				end
				-- v1.1: every villager in every region wears a full outfit.
				expect(dressed).to.equal(total)
			end
		)

		it("every kit variant hides only real slots and stays within budget", function()
			for _, module in RS.Shared.Config.VillagerKits:GetChildren() do
				local kit = require(module)
				local slots = {}
				for _, item in kit.boxes do
					slots[item.slot] = true
				end
				expect(Builder.CountBoxes(kit) <= 60).to.equal(true)
				for name, spec in kit.variants or {} do
					for _, slot in spec.hide or {} do
						expect(slots[slot]).to.equal(true)
					end
					expect(Builder.CountBoxes(kit, name) <= 60).to.equal(true)
					local model = Builder.Build(kit, {}, name)
					expect(model:GetAttribute("VillagerVariant")).to.equal(name)
					model:Destroy()
				end
			end
		end)

		it("builds a kit as non-colliding boxes with the stud variant on relief faces", function()
			local kit = require(RS.Shared.Config.VillagerKits.Plodder)
			local model = Builder.Build(kit, Roster[1].villagers[2].palette)
			local parts, studded = 0, 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "Root" then
					parts += 1
					expect(part.CanCollide or part.CanQuery or part.CanTouch).to.equal(false)
					if part.MaterialVariant ~= "" then
						studded += 1
					end
				end
			end
			expect(parts).to.equal(Builder.CountBoxes(kit))
			expect(studded > 0).to.equal(true)
			model:Destroy()
		end)
	end)
end
