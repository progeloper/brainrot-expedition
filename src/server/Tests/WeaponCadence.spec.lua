--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local WeaponCadence = require(ReplicatedStorage.Shared.Utility.WeaponCadence)

	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1e-9
	end

	describe("Phase 7E shared capture-weapon cadence", function()
		it("keeps the outstanding Longshot deadline when switching to Basic", function()
			local state = assert(WeaponCadence.Accept(10, 1.08))
			local ready, earliest = WeaponCadence.CanAccept(state, 10.2, 0.8)
			expect(ready).to.equal(false)
			expect(near(earliest :: number, 11.08)).to.equal(true)
			expect(select(1, WeaponCadence.CanAccept(state, 11.08, 0.8))).to.equal(true)
		end)

		it("applies the newly selected slower interval to the last accepted shot", function()
			local state = assert(WeaponCadence.Accept(10, 0.8))
			local ready, earliest = WeaponCadence.CanAccept(state, 10.8, 1.08)
			expect(ready).to.equal(false)
			expect(near(earliest :: number, 11.08)).to.equal(true)
		end)

		it("does not mutate cadence state while checking rejected attempts", function()
			local state = assert(WeaponCadence.Accept(10, 1))
			for _ = 1, 100 do
				expect(select(1, WeaponCadence.CanAccept(state, 10.5, 1))).to.equal(false)
			end
			expect(state.lastAcceptedShotAt).to.equal(10)
			expect(state.nextFireAt).to.equal(11)
		end)

		it("rejects invalid time and interval values", function()
			expect(WeaponCadence.Accept(0 / 0, 1)).to.equal(nil)
			expect(WeaponCadence.Accept(0, math.huge)).to.equal(nil)
			expect(select(1, WeaponCadence.CanAccept(nil, 0, 0))).to.equal(false)
		end)
	end)
end
