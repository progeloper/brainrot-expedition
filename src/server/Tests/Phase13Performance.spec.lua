--!nocheck
return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config.Phase13)
	local Carts = require(RS.Shared.Config.Carts)
	local Upgrades = require(RS.Shared.Config.Upgrades)
	local Rules = require(RS.Shared.Utility.Phase13Rules)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Performance = require(RS.Shared.Utility.CartPerformanceResolver)
	local Team = require(RS.Shared.Utility.CartTeamPerformance)
	local Movement = require(RS.Shared.Utility.CartMovementProfileResolver)
	local Cargo = require(RS.Shared.Utility.CargoCapacityResolver)
	local Eligibility = require(RS.Shared.Utility.UpgradeEligibility)
	local function state(level, cargo)
		return { status = "Ready", userId = 123, phase13 = { SpeedLevel = level, CargoLevel = cargo or 0 }, ownedOfferIds = {} }
	end
	local function near(a, b)
		expect(math.abs(a - b) < 1e-8).to.equal(true)
	end
	describe("Phase13 authoritative cart progression", function()
		it("uses nine stable IDs, all three class factors and every sequential speed level", function()
			local count = 0
			for _, row in Config.CartRows do
				count += 1
				local def = Carts[row.id]
				local class = Config.Classes[row.classId]
				near(def.MaxTravelSpeed, 36 * class.speed)
				for level = 0, 5 do
					local base = Performance.Resolve(state(level), { cartId = row.id, ownerUserId = 123 })
					expect(base.status).to.equal("Ready")
					near(base.resolvedSpeed, 36 * class.speed * (1 + 0.1 * level))
					local boosted = Team.Resolve(base, { speedMultiplier = 1.1, burstCapacity = 8 }, true)
					near(boosted.resolvedSpeed, 36 * class.speed * (1 + 0.1 * level) * 1.1 * 1.25)
					local movement = Movement.Resolve(row.id, boosted)
					near(movement.ForwardAcceleration, 16 * class.acceleration)
					near(movement.Braking, 48 * class.braking * (1 + 0.1 * level) ^ 2)
					near(movement.CoastDeceleration, 20 * class.braking * (1 + 0.1 * level) ^ 2)
					near(movement.TurnRate, 105 * class.steering)
					expect(movement.ControlReferenceSpeed).to.equal(36)
					expect(movement.RecoveryBackupSpeed).to.equal(3.5)
					expect(movement.RecoveryBackupAcceleration).to.equal(6)
					expect(movement.RecoveryBackupDeceleration).to.equal(12)
				end
			end
			expect(count).to.equal(9)
			near(Performance.Resolve(state(5), { cartId = "CRT_001", ownerUserId = 123 }).resolvedSpeed, 54)
			local scout = Performance.Resolve(state(5), { cartId = "CRT_008", ownerUserId = 123 })
			near(Team.Resolve(scout, { speedMultiplier = 99, burstCapacity = 8 }, true).resolvedSpeed, 81.675)
		end)
		it("retains the outer150 safety clamp and denies invalid owner snapshots", function()
			local capped = Team.Resolve(
				{ status = "Ready", resolvedSpeed = 149, purchasedSpeedContribution = 0 },
				{ speedMultiplier = 1.1, burstCapacity = 8 },
				true
			)
			expect(capped.resolvedSpeed).to.equal(150)
			local wrong = state(1)
			wrong.userId = 999
			expect(Performance.Resolve(wrong, { cartId = "CRT_001", ownerUserId = 123 }).status).to.equal(
				"InvalidOwner"
			)
			expect(Cargo.Resolve(wrong, { cartId = "CRT_001", ownerUserId = 123 }).status).to.equal("InvalidOwner")
			wrong = state(1)
			wrong.status = "Loading"
			expect(Performance.Resolve(wrong, { cartId = "CRT_001", ownerUserId = 123 }).status).to.equal("NotReady")
		end)
		it("enforces cargo3–6 player-wide and rejects a fourth cargo level", function()
			for _, row in Config.CartRows do
				for level = 0, 3 do
					local result = Cargo.Resolve(state(0, level), { cartId = row.id, ownerUserId = 123 })
					expect(result.status).to.equal("Ready")
					expect(result.effectiveCapacity).to.equal(3 + level)
				end
			end
			expect(Cargo.Resolve(state(0, 4), { cartId = "CRT_001", ownerUserId = 123 }).status).to.equal("NotReady")
		end)
		it("uses canonical sequential upgrade ownership rather than counting duplicate legacy booleans", function()
			local d = Schema.CreateDefault()
			local offer = Upgrades.Get("CART_SPEED_2")
			expect(Rules.GrantUpgrade(d, offer)).to.equal(false)
			expect(Rules.GrantUpgrade(d, Upgrades.Get("CART_SPEED_1"))).to.equal(true)
			expect(Rules.GrantUpgrade(d, offer)).to.equal(true)
			expect(Rules.GrantUpgrade(d, offer)).to.equal(false)
			local snapshot = state(2)
			snapshot.phase13 = d.Phase13
			expect(Eligibility.ResolveOwnership(offer, snapshot, { cartId = "CRT_001", ownerUserId = 123 }).owned).to.equal(
				true
			)
			expect(Rules.GrantUpgrade(d, Upgrades.Get("OFFROAD_1"))).to.equal(false)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
