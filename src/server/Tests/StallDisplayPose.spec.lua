--!nocheck
-- Playtest Fixes Part B: pure pose resolver (bounding box in -> CFrame out) for all 30 display IDs.
-- Sizes/families are the WeaponDisplays bounding boxes measured in the DEV place on 13 Nov 2026.

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Pose = require(RS.Shared.Utility.StallDisplayPose)
	local Config = require(RS.Shared.Config.PlaytestFixes).StallPoses

	local DISPLAYS = {
		{ "HRP_001", "Bow", Vector3.new(0.59, 6.90, 3.15) },
		{ "WPN_B02", "Bow", Vector3.new(0.64, 6.90, 3.16) },
		{ "WPN_B03", "Bow", Vector3.new(0.86, 6.90, 4.06) },
		{ "WPN_B04", "Bow", Vector3.new(1.39, 6.90, 4.09) },
		{ "WPN_B05", "Bow", Vector3.new(0.85, 6.71, 4.43) },
		{ "WPN_B06", "Bow", Vector3.new(2.84, 6.96, 4.13) },
		{ "WPN_B07", "Bow", Vector3.new(5.11, 7.33, 4.78) },
		{ "WPN_B08", "Bow", Vector3.new(0.89, 7.48, 3.73) },
		{ "WPN_SP_COLLECTORSBOW", "Bow", Vector3.new(1.06, 7.59, 4.92) },
		{ "WPN_C01", "Crossbow", Vector3.new(5.40, 2.82, 3.97) },
		{ "WPN_C02", "Crossbow", Vector3.new(6.49, 3.41, 7.50) },
		{ "WPN_C03", "Crossbow", Vector3.new(5.29, 2.99, 7.50) },
		{ "WPN_C04", "Crossbow", Vector3.new(5.42, 3.30, 7.50) },
		{ "WPN_C05", "Crossbow", Vector3.new(7.53, 4.61, 6.47) },
		{ "WPN_C06", "Crossbow", Vector3.new(7.38, 5.63, 6.00) },
		{ "WPN_C07", "Crossbow", Vector3.new(7.50, 5.29, 5.34) },
		{ "WPN_C08", "Crossbow", Vector3.new(8.19, 2.63, 5.20) },
		{ "WPN_SP_GETAWAY", "Crossbow", Vector3.new(7.63, 5.40, 8.26) },
		{ "WPN_SP_CRYSTALLANCE", "Crossbow", Vector3.new(5.62, 3.34, 8.25) },
		{ "WPN_G01", "Gun", Vector3.new(1.35, 2.54, 3.73) },
		{ "WPN_G02", "Gun", Vector3.new(1.35, 2.96, 6.30) },
		{ "WPN_G03", "Gun", Vector3.new(1.71, 2.30, 5.66) },
		{ "WPN_G04", "Gun", Vector3.new(2.62, 2.68, 6.31) },
		{ "WPN_G05", "Gun", Vector3.new(3.50, 4.20, 6.15) },
		{ "WPN_G06", "Gun", Vector3.new(3.79, 6.11, 6.20) },
		{ "WPN_G07", "Gun", Vector3.new(5.87, 6.37, 5.80) },
		{ "WPN_G08", "Gun", Vector3.new(2.11, 5.50, 6.93) },
		{ "WPN_SP_RIFTBLASTER", "Gun", Vector3.new(2.40, 4.29, 6.93) },
		{ "WPN_SP_PRISMREPEATER", "Crossbow", Vector3.new(7.37, 4.19, 8.25) }, -- posed as a Gun
		{ "WPN_SP_SECRETHUNTER", "Gun", Vector3.new(1.53, 4.89, 6.92) },
	}
	-- Authored display frame: guns/crossbows/lance fire along -Z with +Y up; bows' limbs run along Y and
	-- their thin side is X. These are what the poses must resolve to.
	local EXPECT = {
		Bow = { along = "Y", face = "X" },
		Gun = { along = "Z", up = "Y" },
		Crossbow = { along = "Z", up = "Y" },
		Lance = { along = "Z", up = "Y" },
	}
	local function near(a, b)
		return math.abs(a - b) < 1e-3
	end
	local CUSTOMER = Vector3.new(0, 0, -1)
	local rackSlot = Pose.SlotFrame(Vector3.new(54.74, 4.86, -51.79), CUSTOMER, 0)
	local wallSlot = Pose.SlotFrame(Vector3.new(42, 9.15, -38.46), CUSTOMER, Config.WallLeanDegrees)

	describe("StallDisplayPose slot frames", function()
		it("runs the rail to the customer's left and faces the customer", function()
			expect(Pose.CheckSlot(rackSlot, CUSTOMER, 0)).to.equal(nil)
			expect(Pose.CheckSlot(wallSlot, CUSTOMER, Config.WallLeanDegrees)).to.equal(nil)
			expect(near(rackSlot.LookVector.X, 1)).to.equal(true)
			expect(near(Pose.LeanDegrees(wallSlot, CUSTOMER), 12)).to.equal(true)
		end)
		it("flags a backwards or mis-leaned slot", function()
			local backwards = CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, 0))
			expect(Pose.CheckSlot(backwards, CUSTOMER, 0)).never.to.equal(nil)
			expect(Pose.CheckSlot(rackSlot, CUSTOMER, 12)).to.equal("lean differs from its group")
		end)
	end)

	describe("StallDisplayPose family poses", function()
		for _, row in DISPLAYS do
			local id, displayFamily, size = row[1], row[2], row[3]
			it(id .. " resolves to its family pose", function()
				local family = Pose.Family(id, displayFamily)
				local axes = Pose.Axes(size, family, id)
				local want = EXPECT[family]
				expect(axes.along).to.equal(want.along)
				if want.face then
					expect(axes.face).to.equal(want.face)
				end
				if want.up then
					expect(axes.up).to.equal(want.up)
				end
				local box = Pose.BoxInSlot(size, axes, 0.6)
				local rot = box - box.Position
				-- a proper rotation
				expect(near(rot.RightVector:Cross(rot.UpVector):Dot(-rot.LookVector), 1)).to.equal(
					true
				)
				-- along: model -along end points at the slot Look (customer's left)
				local alongUnit = ({ X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis })[axes.along]
				expect(near(rot:VectorToWorldSpace(-alongUnit):Dot(Vector3.new(0, 0, -1)), 1)).to.equal(
					true
				)
				-- the box is pushed toward the customer, never into the board
				expect(box.Position.X <= 0).to.equal(true)
				if family == "Crossbow" then
					-- leaned back 25 degrees around the rail
					local up = rot:VectorToWorldSpace(Vector3.yAxis)
					expect(near(math.deg(math.atan2(up.X, up.Y)), Config.Families.Crossbow.tilt)).to.equal(
						true
					)
				elseif family ~= "Bow" then
					expect(near(rot:VectorToWorldSpace(Vector3.yAxis).Y, 1)).to.equal(true)
				end
				-- scale: 1.5x when it fits the rack rail, never below 1.2x
				local fit = Pose.Scale((size :: any)[axes.along], Config.RailLength.Rack)
				expect(fit.multiplier >= Config.MinMultiplier - 1e-6).to.equal(true)
				expect(fit.multiplier <= Config.TargetMultiplier + 1e-6).to.equal(true)
			end)
		end
		it("maps Crystal Lance to Lance and Prism Repeater to Gun", function()
			expect(Pose.Family("WPN_SP_CRYSTALLANCE", "Crossbow")).to.equal("Lance")
			expect(Pose.Family("WPN_SP_PRISMREPEATER", "Crossbow")).to.equal("Gun")
		end)
	end)

	describe("StallDisplayPose rack rows (two per board)", function()
		it("keeps every display inside its row height unless it hits the 1.2x floor", function()
			for _, row in DISPLAYS do
				local id, displayFamily, size = row[1], row[2], row[3]
				local axes = Pose.Axes(size, Pose.Family(id, displayFamily), id)
				local fit = Pose.Fit(size, axes, Config.RailLength.Rack, Config.RowHeight)
				local ext = Pose.Extents(size * fit.scale, Pose.Rotation(axes))
				expect(fit.multiplier >= Config.MinMultiplier - 1e-6).to.equal(true)
				if fit.fits then
					expect(ext.Y <= Config.RowHeight * (1 + Config.OverrunTolerance) + 1e-6).to.equal(
						true
					)
					expect(ext.Z <= Config.RailLength.Rack * (1 + Config.OverrunTolerance) + 1e-6).to.equal(
						true
					)
				else
					expect(fit.multiplier).to.equal(Config.MinMultiplier)
				end
			end
		end)
		it("fits every display on a two-slot wall at 1.2x or more", function()
			for _, row in DISPLAYS do
				local id, displayFamily, size = row[1], row[2], row[3]
				local axes = Pose.Axes(size, Pose.Family(id, displayFamily), id)
				expect(Pose.Fit(size, axes, Config.RailLength.Wall, nil).fits).to.equal(true)
			end
			local n = 0
			for _ in Config.WallSlots do
				n += 1
			end
			expect(n).to.equal(2)
		end)
		it("uses four rack slots, two per board", function()
			local n = 0
			for _ in Config.RackRows do
				n += 1
			end
			expect(n).to.equal(4)
		end)
	end)

	describe("StallDisplayPose scale", function()
		it("keeps 1.5x when within 5% of the rail", function()
			local fit = Pose.Scale(8.5, 8.2)
			expect(fit.multiplier).to.equal(1.5)
			expect(fit.shrunk).to.equal(false)
		end)
		it("shrinks to fit but never below 1.2x", function()
			local fit = Pose.Scale(9, 8.2)
			expect(fit.shrunk).to.equal(true)
			expect(near(fit.multiplier, 8.2 / 9 * 1.5)).to.equal(true)
			local floor = Pose.Scale(20, 8.2)
			expect(floor.multiplier).to.equal(1.2)
			expect(floor.fits).to.equal(false)
		end)
	end)
end
