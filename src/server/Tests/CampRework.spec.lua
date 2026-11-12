--!nocheck
-- Camp Rework (12 Nov 2026): layout constraints, Training maths + migration, special weapons,
-- Prism Repeater drum, sell-back and rebirth payback. Pure logic; no live world or profiles.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Generator = require(RS.Shared.Utility.CampLayoutGenerator)
	local Layout = require(RS.Shared.Config.CampLayout)
	local Training = require(RS.Shared.Config.Training)
	local Weapons = require(RS.Shared.Config.Weapons)
	local TiersV2 = require(RS.Shared.Config.WeaponTiersV2)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local SpecialRules = require(RS.Shared.Utility.SpecialWeaponRules)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)

	-- Stall footprints/offsets as built (Kiosk_* FootprintSize/FootprintOffset attributes, 12 Nov 2026).
	local FOOTPRINTS = {
		Weapons = { size = Vector2.new(27.82, 12.83), offset = Vector2.new(0, 1.41) },
		Carts = { size = Vector2.new(34.76, 22.82), offset = Vector2.new(1.0, -5.62) },
		Sell = { size = Vector2.new(12.61, 6.21), offset = Vector2.new(0, 0.16) },
		Training = { size = Vector2.new(15.65, 12.91), offset = Vector2.new(1.52, -0.65) },
	}
	local CENTER = Vector2.new(Layout.Center.X, Layout.Center.Z)

	local function syntheticInput(seed)
		local stalls = {}
		for key, sector in { Sell = 225, Weapons = 0, Carts = 90, Training = 315 } do
			local fp = FOOTPRINTS[key]
			table.insert(stalls, {
				key = key,
				sector = sector,
				footprint = fp.size,
				offset = fp.offset,
				signLocal = Vector3.new(0, 11, -1),
				height = 13,
				faceOutward = key == "Training",
			})
		end
		table.sort(stalls, function(a, b)
			return a.key < b.key
		end)
		return {
			seed = seed,
			candidates = 120,
			center = CENTER,
			radiusMin = 32,
			radiusMax = 58,
			maxPairDistance = 80,
			spacing = 12,
			sectorJitter = 14,
			yawJitter = 15,
			rampClear = 18,
			apron = 20,
			corridorWidth = 30,
			eyeHeight = 5,
			stalls = stalls,
			landmark = { size = Vector2.new(12, 10), height = 14.5, topY = 14.4 },
			kiosk = { size = Vector2.new(18, 24), height = 20.4, radii = { 24, 28, 32, 36 } },
			bases = {
				{ name = "N", entrance = Vector3.new(-6, 3.5, -189), frontCenter = Vector2.new(-22, -175.5), frontAxis = Vector2.new(0, 1), frontHalfWidth = 39 },
				{ name = "S", entrance = Vector3.new(-32, 3.5, 97), frontCenter = Vector2.new(-16, 83.5), frontAxis = Vector2.new(0, -1), frontHalfWidth = 39 },
				{ name = "E", entrance = Vector3.new(124, 3.5, -33), frontCenter = Vector2.new(117, -49), frontAxis = Vector2.new(-1, 0), frontHalfWidth = 39 },
				{ name = "W", entrance = Vector3.new(-162, 3.5, -59), frontCenter = Vector2.new(-155, -43), frontAxis = Vector2.new(1, 0), frontHalfWidth = 39 },
			},
			exits = { Vector2.new(-267, -250), Vector2.new(175, -294), Vector2.new(229, -22), Vector2.new(229, 182), Vector2.new(-267, 184) },
		}
	end

	describe("CampLayout generator", function()
		it("is deterministic for a seed", function()
			local a = Generator.Generate(syntheticInput(20261112))
			local b = Generator.Generate(syntheticInput(20261112))
			expect(#a.ranked).to.equal(#b.ranked)
			for i = 1, #a.ranked do
				for key, p in a.ranked[i].placed do
					local q = b.ranked[i].placed[key]
					expect(p.pos).to.equal(q.pos)
					expect(p.yaw).to.equal(q.yaw)
				end
			end
		end)

		it("never lets a rule 2/4/7 breaker survive", function()
			local input = syntheticInput(77)
			local result = Generator.Generate(input)
			for _, layout in result.ranked do
				local keys = {}
				for key, p in layout.placed do
					table.insert(keys, key)
					local r = (p.pos - CENTER).Magnitude
					expect(r >= 32 - 1e-6 and r <= 58 + 1e-6).to.equal(true)
				end
				for i = 1, #keys do
					for j = i + 1, #keys do
						local a, b = layout.placed[keys[i]], layout.placed[keys[j]]
						expect((a.pos - b.pos).Magnitude <= 80).to.equal(true)
						local ra = Generator.Rect(a.pos, a.yaw, a.spec.offset, a.spec.footprint)
						local rb = Generator.Rect(b.pos, b.yaw, b.spec.offset, b.spec.footprint)
						expect(Generator.RectDistance(ra, rb) >= 12).to.equal(true)
					end
				end
				local t = layout.placed.Training
				local look = Generator.Rotate(Vector2.new(0, -1), t.yaw)
				expect(look:Dot((t.pos - CENTER).Unit) >= math.cos(math.rad(45))).to.equal(true)
			end
		end)

		it("keeps the committed winner inside rules 2 and 4", function()
			local winner = Layout.Selection()
			local placed = {}
			for key, row in winner.stalls do
				local pos = Vector2.new(row.x, row.z)
				local r = (pos - CENTER).Magnitude
				expect(r >= 32 and r <= 58).to.equal(true)
				placed[key] = { pos = pos, yaw = math.rad(row.yawDegrees) }
			end
			for a, pa in placed do
				for b, pb in placed do
					if a < b then
						expect((pa.pos - pb.pos).Magnitude <= 80).to.equal(true)
						local ra = Generator.Rect(pa.pos, pa.yaw, FOOTPRINTS[a].offset, FOOTPRINTS[a].size)
						local rb = Generator.Rect(pb.pos, pb.yaw, FOOTPRINTS[b].offset, FOOTPRINTS[b].size)
						expect(Generator.RectDistance(ra, rb) >= 12).to.equal(true)
					end
				end
			end
			local t = placed.Training
			local look = Generator.Rotate(Vector2.new(0, -1), t.yaw)
			expect(look:Dot((t.pos - CENTER).Unit) > 0.7).to.equal(true)
			expect(Layout.Seed).to.equal(20261112)
		end)
	end)

	describe("Training maths and migration", function()
		it("maps old Speed n to Training 5n and interpolates geometrically", function()
			for n = 0, 5 do
				expect(math.abs(Training.SpeedMultiplier(5 * n) - (1 + 0.1 * n)) < 1e-9).to.equal(true)
			end
			local previous = 0
			for level = 0, 25 do
				local m = Training.SpeedMultiplier(level)
				expect(m > previous).to.equal(true)
				previous = m
			end
			local mid = Training.SpeedMultiplier(2)
			expect(math.abs(mid - 1.1 ^ (2 / 5)) < 1e-9).to.equal(true)
		end)

		it("grows XP to next ×1.35 per level from ~60", function()
			expect(Training.XpToNext(0)).to.equal(60)
			expect(Training.XpToNext(1)).to.equal(81)
			for level = 1, 23 do
				local ratio = Training.XpToNext(level + 1) / Training.XpToNext(level)
				expect(math.abs(ratio - 1.35) < 0.02).to.equal(true)
			end
			expect(Training.XpToNext(25)).to.equal(math.huge)
			expect(Training.XpPerTick("Rift", true)).to.equal(300)
			expect(Training.XpPerTick("Wooden", false)).to.equal(1)
		end)

		it("levels up across thresholds and stops at 25", function()
			local data = Schema.CreateDefault()
			Rules.MigrateTraining(data, true)
			local ok, out = Rules.ApplyTrainingTick(data, 60 + 81 + 5)
			expect(ok).to.equal(true)
			expect(out.levels).to.equal(2)
			expect(data.Phase13.TrainingLevel).to.equal(2)
			expect(data.Phase13.TrainingXp).to.equal(5)
			data.Phase13.TrainingLevel = 24
			data.Phase13.TrainingXp = Training.XpToNext(24) - 1
			expect((Rules.ApplyTrainingTick(data, 10_000))).to.equal(true)
			expect(data.Phase13.TrainingLevel).to.equal(25)
			expect(data.Phase13.TrainingXp).to.equal(0)
			expect(select(1, Rules.ApplyTrainingTick(data, -1))).to.equal(false)
		end)

		it("migrates SpeedLevel n to TrainingLevel 5n, idempotently, never lowering", function()
			local data = Schema.CreateDefault()
			data.Phase13.SpeedLevel = 3
			expect(Rules.MigrateTraining(data, true)).to.equal(true)
			expect(data.Phase13.TrainingLevel).to.equal(15)
			expect(data.Phase13.TrainingVersion).to.equal(Training.Version)
			expect(data.Phase13.OwnedRollers.Wooden).to.equal(true)
			expect(Rules.MigrateTraining(data, true)).to.equal(false)
			data.Phase13.TrainingLevel = 20 -- trained past the migrated level
			Rules.MigrateTraining(data, true)
			expect(data.Phase13.TrainingLevel).to.equal(20)
			expect(Rules.Validate(data)).to.equal(true)
		end)

		it("sells rollers as permanent Cash purchases", function()
			local data = Schema.CreateDefault()
			Rules.MigrateTraining(data, true)
			data.Economy.Balance = 3_000_000_000
			local ok = Rules.ApplyRollerPurchase(data, "Steel")
			expect(ok).to.equal(true)
			expect(data.Phase13.OwnedRollers.Steel).to.equal(true)
			expect(data.Phase13.SelectedRoller).to.equal("Steel")
			expect(data.Economy.Balance).to.equal(500_000_000)
			expect(select(1, Rules.ApplyRollerPurchase(data, "Rift"))).to.equal(false)
		end)
	end)

	describe("Special weapons", function()
		it("stay off the tier ladder and the family counts", function()
			expect(#Weapons.GetAll()).to.equal(24)
			expect(#Weapons.GetSpecials()).to.equal(6)
			expect(#Weapons.Validate()).to.equal(0)
			for _, d in Weapons.GetSpecials() do
				expect(TiersV2.TierFromWeaponId(d.id)).to.equal(nil)
				expect(string.sub(d.id, 1, 7)).to.equal("WPN_SP_")
			end
			local prism = Weapons.Get("WPN_SP_PRISMREPEATER").stats
			expect(prism.damage).to.equal(12)
			expect(prism.fireIntervalSeconds).to.equal(0.56)
			expect(prism.rangeStuds).to.equal(125)
		end)

		it("are never sellable (nor the starter, Robux, Gem or won items)", function()
			for _, d in Weapons.GetSpecials() do
				expect(Weapons.IsSellable(d.id)).to.equal(false)
				expect(Rules.SellBackValue("Weapon", d.id)).to.equal(nil)
			end
			expect(Weapons.IsSellable("HRP_001")).to.equal(false)
			expect(Rules.SellBackValue("Cart", "CRT_001")).to.equal(nil)
			expect(Rules.SellBackValue("Weapon", "WPN_B02")).to.equal(100_000_000)
		end)

		it("cannot be bought with Cash; only server grants add them", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 10 ^ 15
			local ok, result = Rules.ApplyPurchase(data, "Weapon", "WPN_SP_GETAWAY")
			expect(ok).to.equal(false)
			expect(result.code).to.equal("NOT_FOR_SALE")
			expect(data.Phase13.OwnedWeaponIds.WPN_SP_GETAWAY).to.equal(nil)
			-- milestone grant (server transaction mutator)
			data.Phase13.CleanEscapes = 24
			local granted
			ok, granted = SpecialRules.ApplyCleanEscape(data)
			expect(ok).to.equal(true)
			expect(data.Phase13.CleanEscapes).to.equal(25)
			expect(table.find(granted.granted, "WPN_SP_GETAWAY") ~= nil).to.equal(true)
			expect(data.Phase13.OwnedWeaponIds.WPN_SP_GETAWAY).to.equal(true)
			expect(select(1, SpecialRules.ApplyEarned(data))).to.equal(false) -- idempotent
		end)

		it("sells back owned Cash weapons at 25% but never the equipped one", function()
			local data = Schema.CreateDefault()
			data.Phase13.OwnedWeaponIds.WPN_B02 = true
			data.Phase13.SelectedWeaponId = "WPN_B02"
			expect(select(2, Rules.ApplySellBack(data, "Weapon", "WPN_B02")).code).to.equal("EQUIPPED")
			data.Phase13.SelectedWeaponId = "HRP_001"
			local ok, out = Rules.ApplySellBack(data, "Weapon", "WPN_B02")
			expect(ok).to.equal(true)
			expect(out.refund).to.equal(100_000_000)
			expect(data.Phase13.OwnedWeaponIds.WPN_B02).to.equal(nil)
		end)
	end)

	describe("Prism Repeater drum", function()
		it("rotates exactly one 60° slot per fire event", function()
			local controllers = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client")
			local module = controllers and controllers:FindFirstChild("Controllers")
				and controllers.Controllers:FindFirstChild("WeaponArtController")
			if not module then
				return -- client tree absent in this place build
			end
			local Art = require(module)
			local angle = 0
			for shot = 1, 7 do
				local nextAngle = Art.NextDrumAngle(angle)
				expect((nextAngle - angle) % 360).to.equal(60)
				angle = nextAngle
				expect(angle).to.equal((60 * shot) % 360)
			end
		end)
	end)

	describe("Rebirth payback", function()
		it("divides lost Cash by income after the +10%", function()
			local data = Schema.CreateDefault()
			-- no income: no payback line
			expect(Rules.PaybackSeconds(data, 1_000_000, 0)).to.equal(nil)
			-- 0 rebirths -> 1.10x after; 1,000 cash/s base -> 1,100/s; 1.1M lost -> 1,000 s
			local seconds = Rules.PaybackSeconds(data, 1_100_000, 1_000)
			expect(math.abs(seconds - 1000) < 1e-6).to.equal(true)
		end)
	end)
end
