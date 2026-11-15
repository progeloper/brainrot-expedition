--!strict

return function()
	local Preview = require(game:GetService("ReplicatedStorage").Shared.Utility.MountedShotPreview)
	local function near(left: Vector3, right: Vector3): boolean
		return (left - right).Magnitude < 1e-4
	end

	describe("Mounted free-aim impact preview", function()
		it("keeps the far endpoint on the camera line and inside the muzzle range sphere", function()
			local muzzle = Vector3.new(2, 0, 0)
			local camera = Ray.new(Vector3.new(0, 1, 10), -Vector3.zAxis)
			local queries = {}
			local result = assert(Preview.Resolve(muzzle, camera, 50, function(origin, direction)
				table.insert(queries, { Origin = origin, Direction = direction })
				return nil
			end))
			expect(result.Valid).to.equal(true)
			expect(result.Blocked).to.equal(false)
			expect(math.abs((result.AimPoint - muzzle).Magnitude - 50) < 1e-4).to.equal(true)
			expect(result.AimPoint.X).to.equal(camera.Origin.X)
			expect(result.AimPoint.Y).to.equal(camera.Origin.Y)
			expect(near(result.Endpoint, result.AimPoint)).to.equal(true)
			expect(#queries).to.equal(2)
			expect(near(queries[2].Origin, muzzle)).to.equal(true)
			expect(queries[2].Direction.Magnitude <= 50.00001).to.equal(true)
		end)

		it("shows the actual muzzle obstruction instead of the unobstructed camera target", function()
			local calls = 0
			local result = assert(Preview.Resolve(Vector3.zero, Ray.new(Vector3.new(0, 2, 8), -Vector3.zAxis), 50,
				function()
					calls += 1
					return { Position = if calls == 1 then Vector3.new(0, 2, -20) else Vector3.new(0, 0.4, -4) }
				end))
			expect(result.Valid).to.equal(true)
			expect(result.Blocked).to.equal(true)
			expect(near(result.Endpoint, Vector3.new(0, 0.4, -4))).to.equal(true)
			expect(near(result.AimPoint, Vector3.new(0, 2, -20))).to.equal(true)
		end)

		it("keeps an unobstructed surface hit clear within server surface tolerance", function()
			local calls = 0
			local target = Vector3.new(0, 0, -20)
			local result = assert(Preview.Resolve(Vector3.zero, Ray.new(Vector3.new(0, 0, 8), -Vector3.zAxis), 50,
				function()
					calls += 1
					return { Position = target + (if calls == 1 then Vector3.zero else Vector3.zAxis * 0.005) }
				end))
			expect(result.Blocked).to.equal(false)
		end)

		it("marks camera cover behind the muzzle as blocked without inventing a forward shot", function()
			local calls = 0
			local result, reason = Preview.Resolve(Vector3.zero, Ray.new(Vector3.new(0, 0, 10), -Vector3.zAxis), 50,
				function()
					calls += 1
					return { Position = Vector3.new(0, 0, 5) }
				end)
			expect((result :: any).Valid).to.equal(false)
			expect((result :: any).Blocked).to.equal(true)
			expect(reason).to.equal("camera obstruction behind muzzle")
			expect(calls).to.equal(1)
		end)

		it("rejects close lateral geometry using the existing forward-plane rule", function()
			local result, reason = Preview.Resolve(Vector3.zero, Ray.new(Vector3.new(10, 0, 10), -Vector3.zAxis), 50,
				function()
					return { Position = Vector3.new(10, 0, -1) }
				end)
			expect((result :: any).Valid).to.equal(false)
			expect(reason).to.equal("aim point too close to muzzle plane")
		end)

		it("does not cast or substitute a point when the camera ray misses the range sphere", function()
			local calls = 0
			local result, reason = Preview.Resolve(Vector3.zero, Ray.new(Vector3.new(80, 0, 0), -Vector3.zAxis), 50,
				function()
					calls += 1
					return nil
				end)
			expect(result).to.equal(nil)
			expect(reason).to.equal("camera ray misses weapon range")
			expect(calls).to.equal(0)
		end)

		it("rejects invalid directions and non-finite ranges before querying", function()
			local calls = 0
			local function cast()
				calls += 1
				return nil
			end
			expect(Preview.Resolve(Vector3.zero, Ray.new(Vector3.zero, Vector3.zero), 50, cast)).to.equal(nil)
			expect(Preview.Resolve(Vector3.zero, Ray.new(Vector3.zero, -Vector3.zAxis), math.huge, cast)).to.equal(nil)
			expect(calls).to.equal(0)
		end)
	end)
end
