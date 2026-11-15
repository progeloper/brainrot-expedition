--!nocheck
-- Core Loop V2 pure modules (§18.4): HerdComposer, StarGrade, OddsText, MutationRoller, RushClock,
-- DespawnPolicy, LifecycleRules. Monte-Carlo checks use fixed seeds.
return function()
	local Shared = game:GetService("ReplicatedStorage").Shared
	local CoreLoop = require(Shared.Config.CoreLoop)
	local Composer = require(Shared.CoreLoop.HerdComposer)
	local Grade = require(Shared.CoreLoop.StarGrade)
	local Odds = require(Shared.CoreLoop.OddsText)
	local Roller = require(Shared.CoreLoop.MutationRoller)
	local Rush = require(Shared.CoreLoop.RushClock)
	local Despawn = require(Shared.CoreLoop.DespawnPolicy)
	local Lifecycle = require(Shared.CoreLoop.LifecycleRules)
	local Luck = require(Shared.CoreLoop.LuckState)
	local Combo = require(Shared.CoreLoop.ComboState)
	local Flee = require(Shared.CoreLoop.FleePlanner)
	local PriceCurve = require(Shared.CoreLoop.PriceCurve)

	local function near(actual, expected, tolerance)
		expect(math.abs(actual - expected) <= tolerance).to.equal(true)
	end

	describe("StarGrade (B-2)", function()
		it("matches the §3 grade lines within 1 workbook unit", function()
			local lines = {
				REGION_FOREST = { 3.2, 9.3, 22.4 },
				REGION_BEACH = { 4.9, 14.2, 34.3 },
				REGION_SWAMP = { 12.6, 36.5, 88.2 },
				REGION_JUNGLE = { 19.9, 57.7, 139 },
				REGION_ARCTIC = { 31.9, 92.5, 223 },
				REGION_VOLCANO = { 60.5, 175, 424 },
				REGION_GLITCH = { 95.3, 276, 667 },
			}
			for region, line in lines do
				local mean, super, jackpot = Grade.Thresholds(region)
				near(mean, line[1], 1)
				near(super, line[2], 1)
				near(jackpot, line[3], 1)
			end
		end)
		it("reveals a Golden Trenostruzzo in Forest as Jackpot", function()
			expect(Grade.Visible("REGION_FOREST", "BRT_019")).to.equal("Super")
			expect(Grade.True("REGION_FOREST", "BRT_019", "Golden")).to.equal("Jackpot")
		end)
	end)

	describe("HerdComposer (B-1, A5)", function()
		it("Star tier distribution matches A5 within 1 point", function()
			local expected = {
				REGION_FOREST = { Wild = { Common = 46, Uncommon = 42, Rare = 12 }, Village = { Common = 31, Uncommon = 52, Rare = 17 } },
				REGION_SWAMP = { Wild = { Common = 2, Uncommon = 18, Rare = 52, Epic = 28 }, Village = { Uncommon = 9, Rare = 52, Epic = 39 } },
				REGION_GLITCH = { Wild = { Epic = 16, Legendary = 84 }, Village = { Epic = 6, Legendary = 94 } },
			}
			local rng = Random.new(1)
			for region, kinds in expected do
				for kind, tiers in kinds do
					local counts, n = {}, 100000
					for _ = 1, n do
						local tier = Composer.BestTier(region, Composer.StarDraws(kind, "Idle"), rng)
						counts[tier] = (counts[tier] or 0) + 1
					end
					for tier, pct in tiers do
						near((counts[tier] or 0) / n * 100, pct, 1)
					end
				end
			end
		end)
		it("forced Stars reach the minimum true grade", function()
			local rng = Random.new(7)
			for _ = 1, 50 do
				local herd = Composer.Compose("REGION_BEACH", "Wild", "Idle", rng, { minTrueGrade = "Super" })
				expect(Grade.Rank(herd.trueGrade) >= 2).to.equal(true)
			end
			local herd = Composer.Compose("REGION_FOREST", "Village", "Idle", rng, { minTrueGrade = "Jackpot" })
			expect(herd.trueGrade).to.equal("Jackpot")
		end)
		it("herd sizes stay within 3-5 wild and 4-6 village, Star first", function()
			local rng = Random.new(3)
			for _ = 1, 500 do
				local wild = Composer.Compose("REGION_FOREST", "Wild", "Idle", rng)
				local village = Composer.Compose("REGION_FOREST", "Village", "Idle", rng)
				expect(wild.size >= 3 and wild.size <= 5).to.equal(true)
				expect(village.size >= 4 and village.size <= 6).to.equal(true)
				expect(wild.members[1].star).to.equal(true)
			end
		end)
	end)

	describe("MutationRoller (K-1, K-3)", function()
		it("rates per source within 0.5 pt and the 30% cap", function()
			local rng = Random.new(11)
			for _, case in { { "Snack", "Idle", 0.04 }, { "WildStar", "Idle", 0.08 }, { "VillageStar", "Idle", 0.12 }, { "Snack", "Rush", 0.06 }, { "VillageStar", "Mega", 0.20 } } do
				local chance = Roller.Chance(case[1], case[2], 1)
				near(chance, case[3], 1e-9)
				local hits = 0
				for _ = 1, 100000 do
					if Roller.Roll(chance, case[2] == "Mega", rng) ~= "None" then
						hits += 1
					end
				end
				near(hits / 100000, case[3], 0.005)
			end
			expect(Roller.Chance("VillageStar", "Mega", 3)).to.equal(CoreLoop.Mutation.Cap)
		end)
		it("MEGA doubles Radioactive and Astral then renormalises", function()
			local shares = {}
			for _, row in Roller.Shares(true) do
				shares[row.id] = row.share
			end
			near(shares.Radioactive, 0.175 / 1.15, 1e-9)
			near(shares.Astral, 0.125 / 1.15, 1e-9)
			near(shares.Shiny, 0.45 / 1.15, 1e-9)
		end)
		it("Mutation Rain never yields Radioactive or Astral", function()
			local rng = Random.new(5)
			for _ = 1, 20000 do
				local id = Roller.RainOutcome(rng)
				expect(id == "Shiny" or id == "Golden" or id == "Glitched").to.equal(true)
			end
		end)
	end)

	describe("OddsText (B-4)", function()
		it("formats natural odds with two significant figures", function()
			expect(Odds.ForIndividual("REGION_FOREST", "BRT_019", "None")).to.equal("1 in 17")
			expect(Odds.ForIndividual("REGION_FOREST", "BRT_019", "Golden")).to.equal("1 in 1.7K")
			expect(Odds.ForMutation("Shiny")).to.equal("1 in 56")
			expect(Odds.ForMutation("Golden")).to.equal("1 in 100")
			expect(Odds.ForMutation("Astral")).to.equal("1 in 400")
			expect(Odds.FormatOneIn(34000)).to.equal("1 in 34K")
			expect(Odds.FormatOneIn(1234)).to.equal("1 in 1.2K")
		end)
	end)

	describe("RushClock (H1)", function()
		it("RUSH 60/300 s, MEGA 90/900 s, warning 60 s before", function()
			expect(Rush.At(0, 0).state).to.equal("Idle")
			expect(Rush.At(180, 0).state).to.equal("Warning")
			expect(Rush.At(240, 0).state).to.equal("Rush")
			expect(Rush.At(300, 0).state).to.equal("Idle")
			expect(Rush.At(750, 0).state).to.equal("Warning")
			expect(Rush.At(810, 0).state).to.equal("Mega")
			expect(Rush.At(810, 0).megaIndex).to.equal(1)
			expect(Rush.At(900, 0).state).to.equal("Idle")
		end)
		it("never exposes a cycle id that the reset path could read", function()
			expect(Rush.At(1000, 0).cycleId).to.equal(nil)
		end)
	end)

	describe("DespawnPolicy (A7, A-6)", function()
		local base = { now = 100, nearestHunterDistance = 300, unseenSince = 80 }
		local function facts(extra)
			local f = table.clone(base)
			for k, v in extra do
				f[k] = v
			end
			return f
		end
		it("never retires near a hunter or while protected", function()
			expect(Despawn.Decide(facts({ role = "Snack", nearestHunterDistance = 140 }))).to.equal("Keep")
			expect(Despawn.Decide(facts({ role = "Snack", asleep = true }))).to.equal("Keep")
			expect(Despawn.Decide(facts({ role = "Snack", lastHitAt = 95 }))).to.equal("Keep")
		end)
		it("retires unseen snacks after 8 s and ambient after 20 s", function()
			expect(Despawn.Decide(facts({ role = "Snack", unseenSince = 93 }))).to.equal("Keep")
			expect(Despawn.Decide(facts({ role = "Snack", unseenSince = 92 }))).to.equal("Retire")
			expect(Despawn.Decide(facts({ role = "Ambient", unseenSince = 85 }))).to.equal("Keep")
			expect(Despawn.Decide(facts({ role = "Ambient", unseenSince = 80 }))).to.equal("Retire")
		end)
		it("Stars warn at 100 s after first seen and dive at 120 s", function()
			expect(Despawn.Decide(facts({ role = "Star", starFirstSeenAt = 10 }))).to.equal("Keep") -- 90 s old
			expect(Despawn.Decide(facts({ role = "Star", starFirstSeenAt = -5 }))).to.equal("StartLeaving") -- 105 s
			expect(Despawn.Decide(facts({ role = "Star", starFirstSeenAt = -5, leavingSince = 95 }))).to.equal("Keep")
			expect(Despawn.Decide(facts({ role = "Star", starFirstSeenAt = -20, nearestHunterDistance = 20 }))).to.equal("Dive")
			expect(Despawn.Decide(facts({ role = "Star", starFirstSeenAt = -20, asleep = true }))).to.equal("Keep")
		end)
	end)

	describe("LifecycleRules (§4)", function()
		it("follows the documented transitions", function()
			expect(Lifecycle.Next("Ordered", "Placed")).to.equal("Pop")
			expect(Lifecycle.Next("Pop", "PopDone")).to.equal("Calm")
			expect(Lifecycle.Next("Calm", "Spotted")).to.equal("Flee")
			expect(Lifecycle.Next("Asleep", "OverflowNearFullCart")).to.equal("Saved")
			expect(Lifecycle.Next("Saved", "Scooped")).to.equal("Cargo")
			expect(Lifecycle.Next("Calm", "OwnerGone")).to.equal("Ambient")
			expect(Lifecycle.Next("Leaving", "DiveStart")).to.equal("Dive")
			expect(Lifecycle.Next("Dive", "DiveDone")).to.equal("Retired")
			expect(Lifecycle.Next("Cargo", "Bank")).to.equal("Banked")
			expect(Lifecycle.Next("Banked", "Wake")).to.equal(nil)
			expect(Lifecycle.IsProtected("Asleep")).to.equal(true)
		end)
	end)

	describe("LuckState (C1, C3)", function()
		it("gains per C1 with combo, rush and first-session multipliers", function()
			local m = CoreLoop.Meter -- gains tuned for C-1; the multipliers are the prompt's
			expect(Luck.GainFor("SnackKO", {})).to.equal(m.Snack)
			expect(Luck.GainFor("SnackKO", { combo = 3 })).to.equal(m.Snack * 2)
			expect(Luck.GainFor("StarKO", { combo = 2 })).to.equal(m.Star)
			expect(Luck.GainFor("SuperKO", { combo = 4, rush = true })).to.equal(m.Super * 2 * 1.5)
			expect(Luck.GainFor("JackpotKO", {})).to.equal(0)
			expect(Luck.GainFor("SneakShot", { combo = 6 })).to.equal(m.SneakShot) -- not a KO gain
			expect(Luck.GainFor("CleanEscape", { firstSession = true })).to.equal(m.CleanEscape * 2)
		end)
		it("credits each individual once and reports full once", function()
			local s = Luck.New(false)
			expect(Luck.Apply(s, "SnackKO", "a")).to.equal(CoreLoop.Meter.Snack)
			expect(Luck.Apply(s, "SnackKO", "a")).to.equal(0)
			for i = 1, math.ceil(CoreLoop.Meter.Max / CoreLoop.Meter.Snack) do
				Luck.Apply(s, "SnackKO", "b" .. i)
			end
			expect(Luck.IsFull(s)).to.equal(true)
			local gained, full = Luck.Apply(s, "SnackKO", "late")
			expect(gained).to.equal(0)
			expect(full).to.equal(false)
		end)
		it("pity: Super at 300 s, Jackpot at 900 s, mutation at 180 s; spawns reset them", function()
			local s = Luck.New(false)
			Luck.AddHunting(s, 179)
			expect(Luck.DueMutation(s)).to.equal(false)
			Luck.AddHunting(s, 1)
			expect(Luck.DueMutation(s)).to.equal(true)
			Luck.AddHunting(s, 120)
			expect(Luck.DueStar(s)).to.equal("Super")
			Luck.OnSpawn(s, "Super", true)
			expect(Luck.DueStar(s)).to.equal(nil)
			expect(Luck.DueMutation(s)).to.equal(false)
			Luck.AddHunting(s, 600)
			expect(Luck.DueStar(s)).to.equal("Jackpot")
			Luck.OnSpawn(s, "Jackpot", false)
			expect(Luck.DueStar(s)).to.equal(nil)
		end)
		it("first session uses 150 / 600 / 90 s", function()
			local s = Luck.New(true)
			Luck.AddHunting(s, 90)
			expect(Luck.DueMutation(s)).to.equal(true)
			Luck.AddHunting(s, 60)
			expect(Luck.DueStar(s)).to.equal("Super")
		end)
	end)

	describe("ComboState (D1)", function()
		it("chains within 4 s, caps at x6, resets after the window", function()
			local c = Combo.New()
			expect(Combo.OnKO(c, 0)).to.equal(1)
			expect(Combo.OnKO(c, 3.9)).to.equal(2)
			for i = 1, 10 do
				Combo.OnKO(c, 3.9 + i)
			end
			expect(Combo.Current(c, 13.9)).to.equal(6)
			expect(Combo.MagnetActive(c, 13.9)).to.equal(true)
			expect(Combo.Step(c, 18)).to.equal(6)
			expect(Combo.ShowsEnd(6)).to.equal(true)
			expect(Combo.ShowsEnd(2)).to.equal(false)
			expect(Combo.OnKO(c, 30)).to.equal(1)
		end)
	end)

	describe("FleePlanner (E1, E3, E6)", function()
		it("assigns temperaments", function()
			expect(Flee.Temperament("Wanderer", "Common")).to.equal("Docile")
			expect(Flee.Temperament("ReactiveRunner", "Uncommon")).to.equal("Curious")
			expect(Flee.Temperament("Wanderer", "Epic")).to.equal("Zigzag")
			expect(Flee.Temperament("LegendaryPursuit", "Legendary")).to.equal("Showoff")
			expect(Flee.Temperament("Camouflage", "Epic")).to.equal("Camouflage")
		end)
		it("applies awareness multipliers", function()
			expect(Flee.Awareness("Docile", {})).to.equal(0)
			expect(Flee.Awareness("Sprinter", { hunterCartSpeed = 30 })).to.equal(37.5)
			expect(Flee.Awareness("Sprinter", { hunterFootSpeed = 8 })).to.equal(18)
			expect(Flee.Awareness("Sprinter", { hunterCartSpeed = 30, behind = true })).to.equal(18.75)
			near(Flee.Awareness("Showoff", { hunterFootSpeed = 16, star = true, mutated = true }), 50 * 0.8 * 1.15, 1e-9)
		end)
		it("clamps flee to 0.85 x hunter speed and counts exhaustion", function()
			expect(Flee.ClampSpeed(18, 16)).to.equal(13.6)
			expect(Flee.ClampSpeed(10, 43.2)).to.equal(10)
			expect(Flee.IsExhausted("Sprinter", 3, 2)).to.equal(true)
			expect(Flee.IsExhausted("Curious", 1, 10)).to.equal(true)
			expect(Flee.IsExhausted("Showoff", 3, 5)).to.equal(false)
		end)
		it("sprinter bursts then recovers; zigzag sweeps", function()
			local bolt = Flee.Bolt("Sprinter", 1, Random.new(1))
			expect(Flee.SpeedAt("Sprinter", bolt, 0.5)).to.equal(18)
			expect(Flee.SpeedAt("Sprinter", bolt, 2)).to.equal(4)
			expect(Flee.ZigzagOffset(0.2)).to.equal(30)
			expect(Flee.ZigzagOffset(1.0)).to.equal(0)
			expect(Flee.ZigzagOffset(1.6)).to.equal(-30)
		end)
	end)

	describe("PriceCurve (C4 lever b)", function()
		it("is the identity with factor 1 (flag off)", function()
			for _, price in { 0, 12000000, 500000000, 2500000000, 10000000000000 } do
				expect(PriceCurve.Apply(price, 1)).to.equal(price)
			end
		end)
		it("scales and rounds to three significant figures", function()
			expect(PriceCurve.Apply(500000000, 4.33)).to.equal(2170000000)
			expect(PriceCurve.Apply(4000000000, 4.33)).to.equal(17300000000)
			expect(PriceCurve.Apply(12500000000, 4.33)).to.equal(54100000000)
			expect(PriceCurve.Apply(10000000000000, 4.33)).to.equal(43300000000000)
			expect(PriceCurve.Apply(0, 4.33)).to.equal(0)
		end)
		it("keeps the approved factor in config and 1 with the flag off", function()
			expect(CoreLoop.Economy.PriceCurveFactor).to.equal(4.33)
			expect(PriceCurve.Factor()).to.equal(1)
		end)
	end)

	describe("Mutation Rain outcome (K4)", function()
		it("rolls Shiny 80 / Golden 18 / Glitched 2 and never Radioactive or Astral (100k)", function()
			local Rain = require(game:GetService("ServerScriptService").Server.Services.CoreLoopMutationRain)
			local counts = {}
			local random = Random.new(42)
			local n = 100000
			for _ = 1, n do
				local id = Rain.RollOutcome(random)
				counts[id] = (counts[id] or 0) + 1
			end
			expect(counts.Radioactive).to.equal(nil)
			expect(counts.Astral).to.equal(nil)
			near(counts.Shiny / n, 0.80, 0.005)
			near(counts.Golden / n, 0.18, 0.005)
			near(counts.Glitched / n, 0.02, 0.005)
		end)
	end)
end
