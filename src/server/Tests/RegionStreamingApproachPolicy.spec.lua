--!strict
return function()
	local Policy = require(game.ReplicatedStorage.Shared.Utility.RegionStreamingApproachPolicy)
	local gates = {
		{
			key = "Beach",
			regionId = "REGION_BEACH",
			exteriorRegion = "REGION_FOREST",
			position = Vector3.zero,
			normal = Vector3.xAxis,
		},
		{
			key = "Swamp",
			regionId = "REGION_SWAMP",
			exteriorRegion = "REGION_BEACH",
			position = Vector3.new(100, 0, 0),
			normal = Vector3.xAxis,
		},
	}
	local unlocked = { REGION_FOREST = true, REGION_BEACH = true, REGION_SWAMP = true }
	describe("Confirmed near-use streaming approach", function()
		it("requests the adjacent unlocked interior at64studs and none beyond", function()
			local selected = Policy.Select(Vector3.new(-64, 3, 0), "REGION_FOREST", unlocked, gates)
			expect(selected.destinationRegion).to.equal("REGION_BEACH")
			expect(selected.position).to.equal(Vector3.new(24, 0, 0))
			expect(Policy.Select(Vector3.new(-64.01, 0, 0), "REGION_FOREST", unlocked, gates)).to.equal(nil)
		end)
		it("supports legal return without granting an unconfirmed neighbor", function()
			expect(Policy.Select(Vector3.new(10, 0, 0), "REGION_BEACH", unlocked, gates).position).to.equal(
				Vector3.new(-24, 0, 0)
			)
			expect(Policy.Select(Vector3.new(-10, 0, 0), "REGION_FOREST", { REGION_FOREST = true }, gates)).to.equal(
				nil
			)
			expect(Policy.Select(Vector3.zero, "REGION_CAMP", unlocked, gates)).to.equal(nil)
		end)
		it("chooses only the nearest adjacent opening and rejects lateral walls or altitude", function()
			expect(Policy.Select(Vector3.new(40, 0, 0), "REGION_BEACH", unlocked, gates).gateKey).to.equal("Beach")
			expect(Policy.Select(Vector3.new(60, 0, 0), "REGION_BEACH", unlocked, gates).gateKey).to.equal("Swamp")
			expect(Policy.Select(Vector3.new(-10, 0, 24.01), "REGION_FOREST", unlocked, gates)).to.equal(nil)
			expect(Policy.Select(Vector3.new(-10, 24.01, 0), "REGION_FOREST", unlocked, gates)).to.equal(nil)
		end)
		it("rejects malformed coordinates and normals", function()
			expect(Policy.Select(Vector3.new(math.huge, 0, 0), "REGION_FOREST", unlocked, gates)).to.equal(nil)
			local invalid = {
				{
					key = "Beach",
					regionId = "REGION_BEACH",
					exteriorRegion = "REGION_FOREST",
					position = Vector3.zero,
					normal = Vector3.new(2, 0, 0),
				},
			}
			expect(Policy.Select(Vector3.zero, "REGION_FOREST", unlocked, invalid)).to.equal(nil)
		end)
	end)
end
