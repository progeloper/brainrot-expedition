--!nocheck
-- Playtest Fixes Part F: the NEWS board frame sits on the kiosk's customer front at standing height (pure).

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Stalls = require(script.Parent.Parent.Systems.PlaytestCampStalls)
	local Board = require(RS.Shared.Config.PlaytestFixes).NewsBoard

	local function near(a, b)
		return math.abs(a - b) < 1e-3
	end

	describe("NEWS board frame", function()
		it("faces the customer front and clears the kiosk box", function()
			local pivot = CFrame.new(-52, 0, -46) -- LookVector -Z
			local box = CFrame.new(-52, 4, -46)
			local frame = Stalls.BoardFrame(pivot, box, Vector3.new(10, 8, 6), 0)
			expect(near(frame.LookVector.Z, -1)).to.equal(true)
			expect(near(frame.Position.Z, -46 - 3 - 0.15)).to.equal(true)
			expect(near(frame.Position.X, -52)).to.equal(true)
			expect(near(frame.Position.Y, Board.PanelCentreHeight)).to.equal(true)
		end)
		it("follows a turned kiosk and uses the box depth along the look", function()
			local pivot = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0) -- LookVector -X
			local frame = Stalls.BoardFrame(pivot, CFrame.new(), Vector3.new(10, 8, 6), 2)
			expect(near(frame.LookVector.X, -1)).to.equal(true)
			expect(near(frame.Position.X, -(5 + 0.15))).to.equal(true)
			expect(near(frame.Position.Y, 2 + Board.PanelCentreHeight)).to.equal(true)
		end)
	end)
end
