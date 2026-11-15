--!strict

return function()
	local Shared = game:GetService("ReplicatedStorage").Shared
	local Performance = require(Shared.Utility.CartTeamPerformance)
	local Profiles = require(Shared.Utility.CartMovementProfileResolver)
	local Ids = require(Shared.Constants.Ids)
	local function base(speed: number): any
		return { status = "Ready", baseSpeed = 36, resolvedSpeed = speed, purchasedSpeedContribution = speed / 36 - 1 }
	end
	local function close(actual: number, expected: number)
		expect(math.abs(actual - expected) < 1e-7).to.equal(true)
	end
	describe("Team effects through the cart performance pipeline", function()
		it("applies passive speed then Burst once from the upgraded clean baseline", function()
			local clean = base(37.44)
			local stats = { speedMultiplier = 1.0772, hitMultiplier = 2.5, burstCapacity = 6 }
			local normal = Performance.Resolve(clean, stats, false)
			local burst = Performance.Resolve(clean, stats, true)
			close(normal.normalResolvedSpeed, 37.44 * 1.0772)
			close(burst.resolvedSpeed, normal.normalResolvedSpeed * 1.25)
			close(burst.baseResolvedSpeed, 37.44)
			close(burst.teamSpeedRatio, 1.0772)
			expect(burst.hitMultiplier).to.equal(2.5)
			expect(burst.burstCapacity).to.equal(6)
			close(Performance.Resolve(clean, stats, true).resolvedSpeed, burst.resolvedSpeed)
			expect(clean.resolvedSpeed).to.equal(37.44)
		end)
		it("preserves normal acceleration braking coasting steering and recovery during Burst", function()
			local normal = Profiles.Resolve(Ids.Carts.ScrapChariot)
			-- The profile resolver only accepts a baseline derived from the cart's current ceiling.
			local clean = { status = "Ready", baseSpeed = normal.MaxTravelSpeed, resolvedSpeed = normal.MaxTravelSpeed, purchasedSpeedContribution = 0 }
			local result = Performance.Resolve(clean, { speedMultiplier = 1.1, burstCapacity = 8 }, true)
			local burst = Profiles.Resolve(Ids.Carts.ScrapChariot, result)
			close(burst.MaxTravelSpeed, normal.MaxTravelSpeed * 1.1 * 1.25)
			-- Arcade contract: acceleration, braking and coasting scale with the resolved ceiling
			-- exactly once (no separate team/Burst multiplier); steering and recovery are untouched.
			local responseScale = burst.MaxTravelSpeed / normal.MaxTravelSpeed
			for _, field in { "ForwardAcceleration", "Braking", "CoastDeceleration" } do
				close((burst :: any)[field], (normal :: any)[field] * responseScale)
			end
			for _, field in { "ControlReferenceSpeed", "TurnRate", "RecoveryBackupSpeed" } do
				expect((burst :: any)[field]).to.equal((normal :: any)[field])
			end
			expect((result :: any).teamAccelerationMultiplier).to.equal(nil)
		end)
		it("honors absolute physical speed limits and reports actual passive effect", function()
			local result = Performance.Resolve(base(145), { speedMultiplier = 1.1, burstCapacity = 8 }, true)
			expect(result.normalResolvedSpeed).to.equal(150)
			expect(result.resolvedSpeed).to.equal(150)
			close(result.teamSpeedRatio, 150 / 145)
		end)
		it("a zero-capacity team cannot activate Burst", function()
			local result = Performance.Resolve(base(36), { speedMultiplier = 1.1, burstCapacity = 0 }, true)
			close(result.resolvedSpeed, 39.6)
			expect(result.burstActive).to.equal(false)
		end)
		it("removing effects restores purchased-upgrade speed and neutral Hit", function()
			local result = Performance.Resolve(base(37.44), nil, false)
			expect(result.resolvedSpeed).to.equal(37.44)
			expect(result.hitMultiplier).to.equal(1)
			expect(result.burstCapacity).to.equal(0)
		end)
		it("has independent defensive caps and never propagates invalid effect numbers", function()
			local capped = Performance.Resolve(base(36), { speedMultiplier = 8, hitMultiplier = 90, burstCapacity = 90 }, true)
			close(capped.normalResolvedSpeed, 39.6)
			expect(capped.hitMultiplier).to.equal(5)
			expect(capped.burstCapacity).to.equal(8)
			local invalid = Performance.Resolve(base(36), { speedMultiplier = 0 / 0, hitMultiplier = math.huge, burstCapacity = -1 }, true)
			expect(invalid.resolvedSpeed).to.equal(36)
			expect(invalid.hitMultiplier).to.equal(1)
			expect(invalid.burstCapacity).to.equal(0)
		end)
		it("leaves an unavailable baseline unavailable", function()
			local unavailable = { status = "Unavailable", code = "OWNER_NOT_READY" }
			expect(Performance.Resolve(unavailable, {}, true)).to.equal(unavailable)
		end)
	end)
end
