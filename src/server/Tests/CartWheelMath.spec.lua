--!strict
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Math = require(RS.Shared.Utility.CartWheelMath)
	local function near(actual: number, expected: number, epsilon: number?)
		expect(math.abs(actual - expected) < (epsilon or 0.0001)).to.equal(true)
	end
	local hub = CFrame.new(3, 1, 0) * CFrame.Angles(0, math.pi, 0)
	describe("Cosmetic wheel contact travel", function()
		it("rolls one circumference once, independent of frame partition and chassis width", function()
			local radius = 2
			for _, steps in { 30, 60, 120 } do
				local angle = 0
				for i = 1, steps do
					local before = CFrame.new(0, 0, -math.pi * 2 * radius * (i - 1) / steps)
					local after = CFrame.new(0, 0, -math.pi * 2 * radius * i / steps)
					local delta, reset = Math.Delta(before, after, hub, Vector3.xAxis, radius, 1 / steps)
					expect(reset).to.equal(false)
					angle += delta
				end
				near(angle, math.pi * 2)
				near(Math.Wrap(angle), 0)
			end
		end)
		it("derives the opposite scalar sign for mirrored axes with identical physical rolling", function()
			local before, after = CFrame.identity, CFrame.new(0, 0, -1)
			local a = Math.Delta(before, after, hub, Vector3.xAxis, 2, 1 / 30)
			local b = Math.Delta(before, after, CFrame.new(-3, 1, 0), Vector3.xAxis, 2, 1 / 30)
			near(a, 0.5)
			near(b, -0.5)
		end)
		it("uses each hub's turning path, rather than root speed for both wheels", function()
			local left = CFrame.new(-3, 1, 0) * CFrame.Angles(0, math.pi, 0)
			local right = CFrame.new(3, 1, 0) * CFrame.Angles(0, math.pi, 0)
			local turn = CFrame.Angles(0, 0.1, 0)
			local a = Math.Delta(CFrame.identity, turn, left, Vector3.xAxis, 2, 1 / 30)
			local b = Math.Delta(CFrame.identity, turn, right, Vector3.xAxis, 2, 1 / 30)
			expect(a < 0).to.equal(true)
			expect(b > 0).to.equal(true)
			near(a, -b)
			near(math.abs(a), 3 * math.sin(0.05), 0.0002)
		end)
		it("ignores pure vertical bobbing and stationary samples", function()
			local a, reset = Math.Delta(CFrame.identity, CFrame.new(0, 0.05, 0), hub, Vector3.xAxis, 2, 1 / 60)
			near(a, 0)
			expect(reset).to.equal(false)
			local accumulated = 0
			for _ = 1, 600 do
				accumulated += Math.Delta(CFrame.identity, CFrame.identity, hub, Vector3.xAxis, 2, 1 / 60)
			end
			near(accumulated, 0)
		end)
		it("projects travel onto a sloped wheel/contact direction", function()
			local before = CFrame.Angles(math.rad(10), 0, 0)
			local after = before + before.LookVector * 0.8
			local delta, reset = Math.Delta(before, after, hub, Vector3.xAxis, 2, 1 / 30)
			near(delta, 0.4)
			expect(reset).to.equal(false)
		end)
		it("resynchronizes teleports, long pauses and invalid wheel dimensions without angular jumps", function()
			for _, case in {
				{ CFrame.new(100, 0, 0), 2, 1 / 60 },
				{ CFrame.Angles(0, math.pi, 0), 2, 1 / 60 },
				{ CFrame.new(0, 0, -1), 2, 1 },
				{ CFrame.new(0, 0, -1), 0, 1 / 60 },
			} do
				local delta, reset = Math.Delta(CFrame.identity, case[1], hub, Vector3.xAxis, case[2], case[3])
				near(delta, 0)
				expect(reset).to.equal(true)
			end
			local initial, reset = Math.Delta(nil, CFrame.identity, hub, Vector3.xAxis, 2, 1 / 60)
			near(initial, 0)
			expect(reset).to.equal(true)
		end)
	end)
end
