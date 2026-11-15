--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
	local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
	local WeaponStats = require(ReplicatedStorage.Shared.Utility.WeaponStats)

	local function near(actual: number, expected: number, tolerance: number?): boolean
		return math.abs(actual - expected) <= (tolerance or 1e-9)
	end

	local syntheticBasic = {
		id = "TEST_BASIC",
		definitionRevision = 1,
		stats = {
			rangeStuds = 60,
			fireIntervalSeconds = 0.8,
			projectileSpeedStudsPerSecond = 80,
			projectileSpeedAuthority = "Gameplay",
			assistAcquireHalfAngleRadians = math.rad(12),
			assistRetainHalfAngleRadians = math.rad(18),
		},
	}
	local syntheticLongshot = {
		id = "TEST_LONGSHOT",
		definitionRevision = 1,
		baseWeaponId = syntheticBasic.id,
		modifiers = {
			rangeFactor = 1.35,
			fireIntervalFactor = 1.35,
			projectileSpeedFactor = 1.10,
			-- Only the explicitly named acquisition dimension changes. Retention,
			-- lock delay, correction strength and hit validation are not inferred.
			assistAcquireAngleFactor = 0.72,
		},
	}
	local definitions = {
		[syntheticBasic.id] = syntheticBasic,
		[syntheticLongshot.id] = syntheticLongshot,
	}

	describe("Phase 7E pure weapon-stat resolution", function()
		it("preserves the live Basic source profile", function()
			local resolved = WeaponStats.Resolve(Weapons.StarterWeaponId)
			expect(resolved.status).to.equal("Ready")
			expect(resolved.weaponId).to.equal(Ids.Harpoons.Basic)
			expect(resolved.rangeStuds).to.equal(100)
			expect(resolved.fireIntervalSeconds).to.equal(0.75)
			expect(resolved.projectileSpeedStudsPerSecond).to.equal(500)
			expect(resolved.projectileSpeedAuthority).to.equal("PresentationOnly")
		end)

		it("resolves an explicitly supplied sidegrade fixture without representation mistakes", function()
			local resolved = WeaponStats.Resolve(syntheticLongshot.id, { definitions = definitions })
			expect(resolved.status).to.equal("Ready")
			expect(near(resolved.rangeStuds, 81)).to.equal(true)
			expect(near(resolved.fireIntervalSeconds, 1.08)).to.equal(true)
			expect(near(resolved.projectileSpeedStudsPerSecond, 88)).to.equal(true)
			expect(near(math.deg(resolved.assistAcquireHalfAngleRadians), 8.64)).to.equal(true)
			expect(near(math.deg(resolved.assistRetainHalfAngleRadians), 18)).to.equal(true)
		end)

		it("scales the angle before converting to a minimum dot threshold", function()
			local resolved = WeaponStats.Resolve(syntheticLongshot.id, { definitions = definitions })
			local expectedDot = math.cos(math.rad(12) * 0.72)
			expect(near(math.cos(resolved.assistAcquireHalfAngleRadians), expectedDot)).to.equal(true)
			expect(near(resolved.assistAcquireHalfAngleRadians, math.rad(12) * 0.72)).to.equal(true)
		end)

		it("is idempotent and does not mutate source definitions", function()
			for _ = 1, 100 do
				local resolved = WeaponStats.Resolve(syntheticLongshot.id, { definitions = definitions })
				expect(near(resolved.rangeStuds, 81)).to.equal(true)
			end
			expect(syntheticBasic.stats.rangeStuds).to.equal(60)
			expect(syntheticLongshot.modifiers.rangeFactor).to.equal(1.35)
		end)

		it("captures an immutable accepted-shot profile", function()
			local resolved = WeaponStats.Resolve(syntheticLongshot.id, { definitions = definitions })
			local shot = assert(WeaponStats.CaptureShotProfile(resolved, 7))
			expect(table.isfrozen(shot)).to.equal(true)
			expect(shot.weaponId).to.equal(syntheticLongshot.id)
			expect(shot.equipmentRevision).to.equal(7)
			syntheticLongshot.modifiers.rangeFactor = 2
			expect(shot.rangeStuds).to.equal(81)
			syntheticLongshot.modifiers.rangeFactor = 1.35
		end)

		it("fails closed for unknown, mixed or non-finite profiles", function()
			expect(WeaponStats.Resolve("UNKNOWN").status).to.equal("Unavailable")
			local mixed = table.clone(syntheticLongshot)
			mixed.id = "MIXED"
			mixed.stats = syntheticBasic.stats
			local invalidDefinitions = table.clone(definitions)
			invalidDefinitions.MIXED = mixed
			expect(WeaponStats.Resolve("MIXED", { definitions = invalidDefinitions }).code).to.equal(
				"MIXED_ABSOLUTE_AND_DERIVED_STATS"
			)
			local invalid = table.clone(syntheticBasic)
			invalid.id = "NON_FINITE"
			invalid.stats = table.clone(syntheticBasic.stats)
			invalid.stats.rangeStuds = 0 / 0
			invalidDefinitions.NON_FINITE = invalid
			expect(WeaponStats.Resolve("NON_FINITE", { definitions = invalidDefinitions }).status).to.equal("Invalid")
		end)
	end)
end
