--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartReset = require(ReplicatedStorage.Shared.Config.CartReset)
	local CartResetMath = require(ReplicatedStorage.Shared.Utility.CartResetMath)

	local function horizontalUnit(direction: Vector3): Vector3
		return Vector3.new(direction.X, 0, direction.Z).Unit
	end

	local function isFiniteNumber(value: number): boolean
		return value == value and math.abs(value) < math.huge
	end

	local function isFiniteCFrame(value: CFrame): boolean
		for _, component in { value:GetComponents() } do
			if not isFiniteNumber(component) then
				return false
			end
		end

		return true
	end

	local function createInvalidHeadingCFrame(position: Vector3, invalid: number): CFrame
		return CFrame.new(position.X, position.Y, position.Z, 1, 0, invalid, 0, 1, 0, 0, 0, 1)
	end

	describe("CartResetMath", function()
		it("uses the registered spawn position while preserving current yaw", function()
			local spawn = CFrame.new(100, 8, -40) * CFrame.Angles(0, math.rad(-90), 0)
			local current = CFrame.new(-20, 50, 30)
				* CFrame.Angles(math.rad(24), math.rad(37), math.rad(-18))
			local result = CartResetMath.ResolveSpawnCFrame(spawn, current)

			expect((result.Position - spawn.Position).Magnitude < 1e-6).to.equal(true)
			expect(result.LookVector:Dot(horizontalUnit(current.LookVector)) > 0.9999).to.equal(
				true
			)
			expect(result.UpVector:Dot(Vector3.yAxis) > 0.9999).to.equal(true)
		end)

		it("removes roll and pitch from the recovery orientation", function()
			local spawn = CFrame.new(0, 4, 0)
			local tilted = CFrame.new(0, 100, 0)
				* CFrame.Angles(math.rad(55), math.rad(120), math.rad(65))
			local result = CartResetMath.ResolveSpawnCFrame(spawn, tilted)

			expect(math.abs(result.LookVector.Y) < 1e-6).to.equal(true)
			expect(math.abs(result.RightVector.Y) < 1e-6).to.equal(true)
			expect(result.UpVector:Dot(Vector3.yAxis) > 0.9999).to.equal(true)
		end)

		it("falls back deterministically to spawn yaw for a vertical heading", function()
			local spawn = CFrame.new(12, 4, 18) * CFrame.Angles(0, math.rad(72), 0)
			local vertical = CFrame.lookAt(Vector3.zero, Vector3.yAxis, Vector3.zAxis)
			local first = CartResetMath.ResolveSpawnCFrame(spawn, vertical)
			local second = CartResetMath.ResolveSpawnCFrame(spawn, vertical)

			expect(first.LookVector:Dot(horizontalUnit(spawn.LookVector)) > 0.9999).to.equal(true)
			expect(first).to.equal(second)
		end)

		it("rejects non-finite current headings and falls back to finite spawn yaw", function()
			local spawn = CFrame.new(12, 4, 18) * CFrame.Angles(0, math.rad(72), 0)

			for _, invalid in { 0 / 0, math.huge, -math.huge } do
				local current = createInvalidHeadingCFrame(Vector3.zero, invalid)
				local result = CartResetMath.ResolveSpawnCFrame(spawn, current)

				expect(isFiniteCFrame(result)).to.equal(true)
				expect(result.LookVector:Dot(horizontalUnit(spawn.LookVector)) > 0.9999).to.equal(
					true
				)
			end
		end)

		it(
			"uses the deterministic default when current and spawn headings are non-finite",
			function()
				for _, invalid in { 0 / 0, math.huge, -math.huge } do
					local spawn = createInvalidHeadingCFrame(Vector3.new(12, 4, 18), invalid)
					local current = createInvalidHeadingCFrame(Vector3.zero, invalid)
					local result = CartResetMath.ResolveSpawnCFrame(spawn, current)

					expect(isFiniteCFrame(result)).to.equal(true)
					expect(result.LookVector:Dot(-Vector3.zAxis) > 0.9999).to.equal(true)
				end
			end
		)

		it("keeps the approved hold and reset-security timing centralised", function()
			expect(CartReset.HoldDuration).to.equal(1)
			expect(CartReset.RequestAttemptInterval).to.equal(5)
			expect(CartReset.SuccessfulResetCooldown).to.equal(30)
			expect(CartReset.SuspiciousRejectionThreshold).to.equal(3)
			expect(CartReset.SuspiciousRejectionWindow).to.equal(30)
			expect(table.isfrozen(CartReset)).to.equal(true)
		end)
	end)
end
