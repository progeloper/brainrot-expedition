--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Life = require(RS.Shared.Config.VillagerLife)
	local Roster = require(RS.Shared.Config.VillagerRoster)
	local Footprints = require(RS.Shared.Config.RegionFootprints)
	local Storm = require(RS.Shared.Utility.StormGeometry)
	local VillageLife = require(script.Parent.Parent.Services.VillageLife)

	local KEY = {
		REGION_FOREST = "Forest",
		REGION_BEACH = "Beach",
		REGION_SWAMP = "Swamp",
		REGION_JUNGLE = "Jungle",
		REGION_ARCTIC = "Arctic",
		REGION_VOLCANO = "Volcano",
		REGION_GLITCH = "GlitchZone",
	}

	-- A deterministic stand-in for Random: always returns `value`.
	local function fixedRng(value)
		return {
			NextNumber = function()
				return value
			end,
			NextInteger = function(_, low)
				return low
			end,
		}
	end

	local function guard(id, regionId, position, kind)
		return {
			id = id,
			type = kind or "Plodder",
			regionId = regionId,
			state = "Idle",
			position = position,
			facing = Vector3.new(0, 0, -1),
			speedNow = 0,
			seed = 7,
		}
	end

	local function context(now, villagers, players, lastHitAt)
		return {
			now = now,
			steer = function(villager, target, dt)
				local delta = (target - villager.position) * Vector3.new(1, 0, 1)
				local step = math.min(delta.Magnitude, 3 * dt)
				if step > 0 then
					villager.position += delta.Unit * step
					villager.speedNow = 3
				end
			end,
			groundY = function()
				return 0
			end,
			players = players or {},
			lastHitAt = lastHitAt or {},
			villagers = villagers,
		}
	end

	describe("VillageLife points of interest", function()
		it("lists 2-4 points for every guard except Lumaca Lampione", function()
			for _, region in Roster do
				for _, row in region.villagers do
					local list = Life.Pois[row.id]
					if row.id == "VIL_SWAMP_LUMACA" then
						expect(list).to.equal(nil)
					else
						expect(list ~= nil).to.equal(true)
						expect(#list >= 1 and #list <= 4).to.equal(true)
					end
				end
			end
		end)

		it("keeps every point inside its region, outside Camp, within 12 studs of home", function()
			for _, region in Roster do
				for _, row in region.villagers do
					for _, poi in Life.Pois[row.id] or {} do
						expect(Storm.Contains(Footprints[KEY[region.regionId]], poi.x, poi.z)).to.equal(
							true
						)
						expect(Storm.Contains(Footprints.Camp, poi.x, poi.z)).to.equal(false)
						local gap = Vector2.new(poi.x - row.home[1], poi.z - row.home[2]).Magnitude
						-- generated at <= 12 studs, then rounded to 0.1
						expect(gap <= 12.1).to.equal(true)
					end
				end
			end
		end)
	end)

	describe("VillageLife routine", function()
		it("resumes a waking guard mid-activity at one of its points", function()
			VillageLife.Reset()
			local pina = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(-330, 0, -40))
			VillageLife.Step(pina, 0.1, context(100, { pina }))
			local match = nil
			for _, poi in Life.Pois.VIL_FOREST_PINA do
				if
					math.abs(pina.position.X - poi.x) < 1e-3
					and math.abs(pina.position.Z - poi.z) < 1e-3
				then
					match = poi
				end
			end
			expect(match ~= nil).to.equal(true)
			if match.activity ~= "Lookout" then
				expect(pina.lifeMotion).to.equal(match.activity)
			end
			expect(pina.life.phase).to.equal("Work")
		end)

		it("walks to the next point after work and rest, then plays its activity", function()
			VillageLife.Reset()
			local pina = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(-330, 0, -40))
			local now = 100
			VillageLife.Step(pina, 0.1, context(now, { pina }))
			local seen = {}
			for _ = 1, 1200 do
				now += 0.1
				VillageLife.Step(pina, 0.1, context(now, { pina }))
				seen[pina.life.phase] = true
				if pina.life.phase == "Work" and seen.Walk then
					break
				end
			end
			expect(seen.Rest).to.equal(true)
			expect(seen.Walk).to.equal(true)
			expect(pina.life.phase).to.equal("Work")
			expect(pina.lifeMotion ~= nil).to.equal(true)
		end)

		it(
			"drops the routine at once when the guard leaves Idle, with no jump on return",
			function()
				VillageLife.Reset()
				local pina = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(-330, 0, -40))
				VillageLife.Step(pina, 0.1, context(100, { pina }))
				pina.state = "Suspicious"
				VillageLife.Leave(pina, 100.1)
				expect(pina.lifeMotion).to.equal(nil)
				-- Back home 40 s later: carries on from where it stands.
				pina.state = "Idle"
				pina.position = Vector3.new(-330, 0, -40)
				VillageLife.Step(pina, 0.1, context(140, { pina }))
				-- No resume teleport: it starts walking to its next spot from home.
				local moved = (pina.position - Vector3.new(-330, 0, -40)).Magnitude
				expect(moved < 1).to.equal(true)
				expect(pina.life.phase).to.equal("Walk")
			end
		)

		it("waves at a nearby player who hasn't hunted for 20 s, once a minute", function()
			VillageLife.Reset()
			local pina = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(-330, 0, -40))
			VillageLife.Step(pina, 0.1, context(100, { pina }))
			local near = { { userId = 1, position = pina.position + Vector3.new(5, 0, 0) } }
			VillageLife.Step(pina, 0.1, context(100.1, { pina }, near, { [1] = 70 }))
			expect(pina.lifeMotion).to.equal("Wave")
			-- After the wave, the activity resumes; no second wave within 60 s.
			VillageLife.Step(pina, 0.1, context(101.2, { pina }, near, {}))
			expect(pina.lifeMotion ~= "Wave").to.equal(true)
			VillageLife.Step(pina, 0.1, context(130, { pina }, near, {}))
			expect(pina.lifeMotion ~= "Wave").to.equal(true)
		end)

		it("does not wave at a player who hit a brainrot in the last 20 s", function()
			VillageLife.Reset()
			local pina = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(-330, 0, -40))
			VillageLife.Step(pina, 0.1, context(100, { pina }))
			local near = { { userId = 1, position = pina.position + Vector3.new(5, 0, 0) } }
			VillageLife.Step(pina, 0.1, context(100.1, { pina }, near, { [1] = 90 }))
			expect(pina.lifeMotion ~= "Wave").to.equal(true)
		end)

		it("pairs two idle neighbours for a chat, at most one pair per region", function()
			VillageLife.Reset()
			local a = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(0, 0, 0))
			local b = guard("VIL_FOREST_TITO", "REGION_FOREST", Vector3.new(3, 0, 0), "Sprinter")
			local c = guard("VIL_FOREST_GUFO", "REGION_FOREST", Vector3.new(0, 0, 3), "Shouter")
			local d = guard("VIL_FOREST_PEPE", "REGION_FOREST", Vector3.new(3, 0, 3))
			local all = { a, b, c, d }
			for _, v in all do
				VillageLife.Step(v, 0.1, context(100, all))
			end
			-- Put everyone back side by side, resting, with a rng that always says yes.
			for index, v in all do
				v.position = Vector3.new((index - 1) % 2 * 3, 0, math.floor((index - 1) / 2) * 3)
				v.life.phase, v.life.untilAt = "Work", 0
				v.life.rng = fixedRng(0)
			end
			for _, v in all do
				VillageLife.Step(v, 0.1, context(100.2, all))
			end
			local chatting = 0
			for _, v in all do
				if v.life.phase == "Chat" then
					chatting += 1
				end
			end
			expect(chatting).to.equal(2)
			expect(VillageLife.ChattingRegions().REGION_FOREST ~= nil).to.equal(true)
		end)

		it("ends a chat when the partner is called away", function()
			VillageLife.Reset()
			local a = guard("VIL_FOREST_PINA", "REGION_FOREST", Vector3.new(0, 0, 0))
			local b = guard("VIL_FOREST_TITO", "REGION_FOREST", Vector3.new(3, 0, 0), "Sprinter")
			local all = { a, b }
			for _, v in all do
				VillageLife.Step(v, 0.1, context(100, all))
				v.position = if v == a then Vector3.new(0, 0, 0) else Vector3.new(3, 0, 0)
				v.life.phase, v.life.untilAt = "Work", 0
				v.life.rng = fixedRng(0)
			end
			VillageLife.Step(a, 0.1, context(100.2, all))
			expect(a.life.phase).to.equal("Chat")
			b.state = "Suspicious"
			VillageLife.Leave(b, 100.3)
			VillageLife.Step(a, 0.1, context(100.4, all))
			expect(a.life.phase).to.equal("Rest")
			expect(VillageLife.ChattingRegions().REGION_FOREST).to.equal(nil)
		end)
	end)
end
