--!strict
-- Weapon Tiers V2 pure-logic checks. Uses only explicit v2/legacy builders and the
-- v2Enabled override, so it never depends on the live flag or Studio preview attribute.
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags) :: any
	local Phase12 = require(ReplicatedStorage.Shared.Config.Phase12) :: any
	local TiersV2 = require(ReplicatedStorage.Shared.Config.WeaponTiersV2) :: any
	local Weapons = require(ReplicatedStorage.Shared.Config.Weapons) :: any
	local Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules) :: any
	local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats) :: any
	local WeaponCadence = require(ReplicatedStorage.Shared.Utility.WeaponCadence) :: any

	local REGIONS: { string } = {
		"REGION_FOREST",
		"REGION_BEACH",
		"REGION_SWAMP",
		"REGION_JUNGLE",
		"REGION_ARCTIC",
		"REGION_VOLCANO",
		"REGION_GLITCH",
	}
	local ON_CURVE_TIER: { [string]: number } = {
		REGION_FOREST = 2,
		REGION_BEACH = 3,
		REGION_SWAMP = 4,
		REGION_JUNGLE = 5,
		REGION_ARCTIC = 6,
		REGION_VOLCANO = 7,
		REGION_GLITCH = 8,
	}
	local RARITIES: { string } = {
		"Common",
		"Uncommon",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Celestial",
		"Astral",
		"Secret",
	}
	local LEGACY_HP: { [string]: number } = {
		Common = 1,
		Uncommon = 1,
		Rare = 2,
		Epic = 3,
		Legendary = 4,
		Mythic = 6,
		Celestial = 8,
		Astral = 8,
		Secret = 10,
	}
	-- Today's (flag-off) stats: { damage, fireIntervalSeconds, rangeStuds, profileId }.
	local LEGACY_STATS: { [string]: { any } } = {
		HRP_001 = { 1, 0.75, 100, "B1" },
		WPN_B02 = { 1, 0.65, 90, "B2" },
		WPN_B03 = { 1, 0.85, 115, "B3" },
		WPN_B04 = { 2, 1.40, 95, "B4" },
		WPN_B05 = { 1, 0.65, 90, "B2" },
		WPN_B06 = { 1, 0.85, 115, "B3" },
		WPN_B07 = { 2, 1.40, 95, "B4" },
		WPN_B08 = { 2, 1.40, 95, "B4" },
		WPN_C01 = { 2, 1.40, 110, "C1" },
		WPN_C02 = { 2, 1.20, 95, "C2" },
		WPN_C03 = { 2, 1.50, 125, "C3" },
		WPN_C04 = { 2, 1.30, 110, "C4" },
		WPN_C05 = { 2, 1.20, 95, "C2" },
		WPN_C06 = { 2, 1.50, 125, "C3" },
		WPN_C07 = { 2, 1.30, 110, "C4" },
		WPN_C08 = { 2, 1.30, 110, "C4" },
		WPN_G01 = { 1, 0.45, 70, "G1" },
		WPN_G02 = { 1, 0.35, 55, "G2" },
		WPN_G03 = { 1, 0.55, 90, "G3" },
		WPN_G04 = { 1, 0.40, 75, "G4" },
		WPN_G05 = { 1, 0.35, 55, "G2" },
		WPN_G06 = { 1, 0.55, 90, "G3" },
		WPN_G07 = { 1, 0.40, 75, "G4" },
		WPN_G08 = { 1, 0.40, 75, "G4" },
	}
	local FAMILY_IDS: { [string]: { string } } = {
		Bow = {
			"HRP_001",
			"WPN_B02",
			"WPN_B03",
			"WPN_B04",
			"WPN_B05",
			"WPN_B06",
			"WPN_B07",
			"WPN_B08",
		},
		Crossbow = {
			"WPN_C01",
			"WPN_C02",
			"WPN_C03",
			"WPN_C04",
			"WPN_C05",
			"WPN_C06",
			"WPN_C07",
			"WPN_C08",
		},
		Gun = {
			"WPN_G01",
			"WPN_G02",
			"WPN_G03",
			"WPN_G04",
			"WPN_G05",
			"WPN_G06",
			"WPN_G07",
			"WPN_G08",
		},
	}

	local v2Definitions = Weapons.BuildDefinitions(true)
	local legacyDefinitions = Weapons.BuildDefinitions(false)

	local function resolveV2(id: string): any
		local profile = WeaponStats.Resolve(id, { definitions = v2Definitions })
		assert(
			profile.status == "Ready",
			"V2 profile not ready: " .. id .. " " .. tostring(profile.code)
		)
		return profile
	end

	-- Seconds from the first shot to sleep: the first shot lands at t = 0.
	local function timeToSleep(hp: number, damage: number, interval: number): number
		return (math.ceil(hp / damage) - 1) * interval
	end

	describe("Weapon Tiers V2 (flag on)", function()
		it("ships with the flag off by default", function()
			expect(FeatureFlags.WeaponTiersV2Enabled).to.equal(false)
		end)

		it("maps every weapon ID to its tier and a distinct per-tier profile", function()
			for family, ids in FAMILY_IDS do
				for tier, id in ids do
					expect(TiersV2.TierFromWeaponId(id)).to.equal(tier)
					local p = resolveV2(id)
					local expected = TiersV2.ProfileFor(family, tier)
					expect(p.damage).to.equal(expected.damage)
					expect(p.fireIntervalSeconds).to.equal(expected.fireIntervalSeconds)
					expect(p.rangeStuds).to.equal(expected.rangeStuds)
					expect(p.definitionRevision).to.equal(TiersV2.DefinitionRevision)
					expect(p.projectileSpeedStudsPerSecond).to.equal(500)
					expect(math.abs(math.deg(p.assistAcquireHalfAngleRadians) - 10) < 1e-9).to.equal(
						true
					)
					expect(math.abs(math.deg(p.assistRetainHalfAngleRadians) - 16) < 1e-9).to.equal(
						true
					)
					expect(v2Definitions[id].price).to.equal(legacyDefinitions[id].price)
					expect(v2Definitions[id].displayName).to.equal(
						legacyDefinitions[id].displayName
					)
					expect(v2Definitions[id].family).to.equal(legacyDefinitions[id].family)
				end
			end
			expect(TiersV2.TierFromWeaponId("HRP_002")).to.equal(nil)
			expect(TiersV2.TierFromWeaponId("WPN_B09")).to.equal(nil)
		end)

		it("scales HP by spawn region; unknown or nil regions use x1", function()
			expect(Rules.HpForRarityInRegion("Legendary", "REGION_FOREST", true)).to.equal(4)
			expect(Rules.HpForRarityInRegion("Legendary", "REGION_BEACH", true)).to.equal(16)
			expect(Rules.HpForRarityInRegion("Secret", "REGION_GLITCH", true)).to.equal(5500)
			expect(Rules.HpForRarityInRegion("Common", nil, true)).to.equal(1)
			expect(Rules.HpForRarityInRegion("Epic", "REGION_CAMP", true)).to.equal(3)
			expect(Rules.HpForRarityInRegion("Epic", "NOT_A_REGION", true)).to.equal(3)
			expect(Rules.HpForRarityInRegion("NotARarity", "REGION_GLITCH", true)).to.equal(nil)
		end)

		it("(1) never makes a higher tier slower to sleep any rarity in any region", function()
			local failures = {}
			for _, ids in FAMILY_IDS do
				for tier = 2, #ids do
					local previous, current = resolveV2(ids[tier - 1]), resolveV2(ids[tier])
					for _, region in REGIONS do
						for _, rarity in RARITIES do
							local hp = Rules.HpForRarityInRegion(rarity, region, true)
							local before =
								timeToSleep(hp, previous.damage, previous.fireIntervalSeconds)
							local after =
								timeToSleep(hp, current.damage, current.fireIntervalSeconds)
							if after > before + 1e-9 then
								table.insert(failures, ids[tier] .. "/" .. region .. "/" .. rarity)
							end
						end
					end
				end
			end
			expect(table.concat(failures, ",")).to.equal("")
		end)

		it(
			"(2) the on-curve tier sleeps that region's Legendary in <= 2.5 s for every family",
			function()
				local failures = {}
				for _, region in REGIONS do
					local hp = Rules.HpForRarityInRegion("Legendary", region, true)
					for _, ids in FAMILY_IDS do
						local p = resolveV2(ids[ON_CURVE_TIER[region]])
						local seconds = timeToSleep(hp, p.damage, p.fireIntervalSeconds)
						if seconds > 2.5 + 1e-9 then
							table.insert(
								failures,
								string.format("%s/%s=%.2fs", p.weaponId, region, seconds)
							)
						end
					end
				end
				expect(table.concat(failures, ",")).to.equal("")
			end
		)

		it(
			"accepts the fastest 0.25 s interval through profile capture and server cadence",
			function()
				local fastest = resolveV2("WPN_G08")
				expect(fastest.fireIntervalSeconds).to.equal(0.25)
				expect(WeaponStats.IsReady(fastest)).to.equal(true)
				local captured = WeaponStats.CaptureShotProfile(fastest, 0)
				expect(captured ~= nil).to.equal(true)
				local state = WeaponCadence.Accept(10, captured.fireIntervalSeconds)
				expect((WeaponCadence.CanAccept(state, 10.25, captured.fireIntervalSeconds))).to.equal(
					true
				)
				expect((WeaponCadence.CanAccept(state, 10.2, captured.fireIntervalSeconds))).to.equal(
					false
				)
			end
		)

		it("keeps the V2 catalogue valid under the existing validator rules", function()
			local count = 0
			for id in v2Definitions do
				count += 1
				expect(WeaponStats.IsReady(resolveV2(id))).to.equal(true)
			end
			-- 24-row tier ladder + 6 Camp Rework specials (defined on both stat paths)
			expect(count).to.equal(24 + 6)
		end)
	end)

	describe("Weapon Tiers V2 (flag off) preserves today's HP and stats exactly", function()
		it("returns HpByRarity for every rarity in every region", function()
			for _, rarity in RARITIES do
				expect(Phase12.HpByRarity[rarity]).to.equal(LEGACY_HP[rarity])
				expect(Rules.HpForRarityInRegion(rarity, nil, false)).to.equal(LEGACY_HP[rarity])
				for _, region in REGIONS do
					expect(Rules.HpForRarityInRegion(rarity, region, false)).to.equal(
						LEGACY_HP[rarity]
					)
				end
			end
		end)

		it("builds the legacy weapon stats, profile IDs and revision exactly", function()
			local count = 0
			for id, row in LEGACY_STATS do
				count += 1
				local definition = legacyDefinitions[id]
				expect(definition.stats.damage).to.equal(row[1])
				expect(definition.stats.fireIntervalSeconds).to.equal(row[2])
				expect(definition.stats.rangeStuds).to.equal(row[3])
				expect(definition.profileId).to.equal(row[4])
				expect(definition.definitionRevision).to.equal(13)
			end
			expect(count).to.equal(24)
		end)

		it("uses the legacy catalogue and HP while the session flag is off", function()
			if TiersV2.Enabled() then
				return -- A Studio preview session deliberately runs the V2 path.
			end
			for id, row in LEGACY_STATS do
				local live = Weapons.Get(id)
				expect(live.stats.damage).to.equal(row[1])
				expect(live.stats.fireIntervalSeconds).to.equal(row[2])
				expect(live.stats.rangeStuds).to.equal(row[3])
				expect(live.definitionRevision).to.equal(13)
			end
			for _, rarity in RARITIES do
				expect(Rules.HpForRarityInRegion(rarity, "REGION_GLITCH")).to.equal(
					LEGACY_HP[rarity]
				)
			end
			expect(#Weapons.Validate()).to.equal(0)
		end)
	end)
end
