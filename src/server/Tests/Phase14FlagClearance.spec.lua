--!nocheck
-- Native measured baseline fixtures; actual persisted templates are additionally
-- checked by VerifyNativeCosmeticFits. No species factory or profile session runs.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Catalog = require(RS.Shared.Config.BrainrotCatalog)
	local Config = require(RS.Shared.Config.Phase13)
	local Geometry = require(RS.Shared.Utility.CartGeometry)
	local Presenter = require(script.Parent.Parent.Utility.Phase14CosmeticPresenter)
	local Bounds = require(script.Parent.Support.Phase14CosmeticNativeBounds)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local function near(actual, expected)
		expect(math.abs(actual - expected) < 0.00001).to.equal(true)
	end
	local function extent(frame, size)
		local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local point = frame * (size / 2 * Vector3.new(x, y, z))
					low, high = low:Min(point), high:Max(point)
				end
			end
		end
		return low, high
	end
	local function separation(a, aSize, b, bSize)
		local aa = { a.RightVector, a.UpVector, a.LookVector }
		local ba = { b.RightVector, b.UpVector, b.LookVector }
		local ah, bh = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }, { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
		local candidates = { aa[1], aa[2], aa[3], ba[1], ba[2], ba[3] }
		for _, x in aa do
			for _, y in ba do
				local axis = x:Cross(y)
				if axis.Magnitude > 0.00001 then
					table.insert(candidates, axis.Unit)
				end
			end
		end
		local delta, gap = b.Position - a.Position, -math.huge
		for _, axis in candidates do
			local ar, br = 0, 0
			for i = 1, 3 do
				ar += math.abs(axis:Dot(aa[i])) * ah[i]
				br += math.abs(axis:Dot(ba[i])) * bh[i]
			end
			gap = math.max(gap, math.abs(delta:Dot(axis)) - ar - br)
		end
		return gap
	end
	local function verifyRail(profile, flagFrame)
		local railFrame, railSize = Presenter.FlagRail(profile, flagFrame)
		expect(railFrame ~= nil).to.equal(true)
		near(railSize.Y, 0.10)
		near(railSize.Z, 0.30)
		local _, railHigh = extent(railFrame, railSize)
		expect(math.abs(railHigh.Y - flagFrame.Position.Y) < 0.00001).to.equal(true)
		local floor
		for _, collider in profile.Colliders do
			if collider.Name == "Floor" then
				floor = collider
			end
		end
		expect(separation(railFrame, railSize, floor.Frame, floor.Size) < 0).to.equal(true)
		for _, world in
			{
				CFrame.new(),
				CFrame.new(100, 7, -30) * CFrame.Angles(0, math.rad(137), 0),
				CFrame.new(-80, 12, 150) * CFrame.Angles(math.rad(21), math.rad(-65), math.rad(13)),
			}
		do
			local placedRail = world * railFrame
			for _, slot in profile.CargoSlots do
				for _, cargo in Bounds.Cargo do
					expect(separation(placedRail, railSize, world * slot * cargo.Frame, cargo.Size) > 0.01).to.equal(
						true
					)
				end
			end
			local rider = profile.RiderClearance
			expect(separation(placedRail, railSize, world * rider.Frame, rider.Size) > 0).to.equal(true)
			expect(separation(placedRail, railSize, world * profile.HarpoonOrigin, Vector3.one * 0.5) > 0).to.equal(
				true
			)
		end
	end
	local function verify(profile, includeRail)
		local original = Fixtures.Clone(profile)
		local frame = Presenter.FlagFrame(profile)
		local old = profile.CoreBodyBounds
		near(frame.Position.Y, 1.65)
		near(frame.Position.Z, old.Frame.Position.Z + old.Size.Z / 2 - 0.65)
		expect(frame.Rotation).to.equal(CFrame.new())
		local count = 0
		for _, flag in Bounds.Flags do
			local flagLow = extent(frame * flag.Frame, flag.Size)
			for _, body in { profile.CoreBodyBounds, profile.VisualBounds, profile.RiderClearance } do
				local _, bodyHigh = extent(body.Frame, body.Size)
				expect(flagLow.X - bodyHigh.X >= 0.25 - 0.00001).to.equal(true)
			end
			expect(flagLow.X - (profile.HarpoonOrigin.Position.X + 0.25) >= 0.25 - 0.00001).to.equal(true)
			for _, slot in profile.CargoSlots do
				for _, cargo in Bounds.Cargo do
					local _, cargoHigh = extent(slot * cargo.Frame, cargo.Size)
					expect(flagLow.X - cargoHigh.X >= 0.25 - 0.00001).to.equal(true)
					count += 1
				end
			end
		end
		expect(count).to.equal(3 * 6 * 32)
		if includeRail ~= false then
			verifyRail(profile, frame)
		end
		Fixtures.AssertDeepEqual(profile, original)
	end
	describe("Phase14 source-proved canonical cargo flag clearance", function()
		it("covers exactly the 32 currently live species and three approved flag envelopes", function()
			local live, measured = 0, 0
			for _, row in Catalog.GetAll() do
				if row.launchStatus == "Live" then
					expect(Bounds.Cargo[row.id] ~= nil).to.equal(true)
					live += 1
				end
			end
			for _ in Bounds.Cargo do
				measured += 1
			end
			expect(live).to.equal(32)
			expect(measured).to.equal(live)
			local flags = 0
			for _ in Bounds.Flags do
				flags += 1
			end
			expect(flags).to.equal(3)
		end)
		for _, row in Config.CartRows do
			it(row.id .. " clears all 576 flag/slot/species pairs and preserves fitted data", function()
				verify(assert(Geometry.GetById(row.id)))
			end)
		end
		it("projects the full cargo envelope through rotated and displaced authored slot frames", function()
			local profile = Fixtures.Clone(assert(Geometry.GetById("CRT_008")))
			profile.CargoSlots[6] = CFrame.new(11, 3, -2) * CFrame.Angles(0.2, math.rad(70), 0.1)
			profile.VisualBounds.Frame = CFrame.new(6, 2, 0) * CFrame.Angles(0, math.rad(40), 0)
			profile.RiderClearance.Frame = CFrame.new(14, 4, 0) * CFrame.Angles(0, math.rad(20), 0)
			verify(profile, false)
		end)
		it("clones exactly one inert saved-stud mounting rail and removes it with the flag", function()
			local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
			local cart, root = Instance.new("Model"), Instance.new("Part")
			root.Name, root.Parent = "Root", cart
			root.CFrame = CFrame.new(18, 9, -27) * CFrame.Angles(0, math.rad(65), 0)
			cart.PrimaryPart = root
			local profile = assert(Geometry.GetById("CRT_008"))
			cart:SetAttribute("CartGeometryId", profile.Id)
			cart:SetAttribute("CartGeometryRevision", profile.Revision)
			cart:SetAttribute("OwnerUserId", 8101)
			local player, data = { UserId = 8101 }, Schema.CreateDefault()
			data.Commerce.Entitlements.P14_FLAG_CAMP = true
			data.Commerce.Appearance.Flag = "P14_FLAG_CAMP"
			local originalRoot =
				{ Size = root.Size, CFrame = root.CFrame, Massless = root.Massless, CanCollide = root.CanCollide }
			local before = Fixtures.Clone(data)
			local ok, failure = xpcall(function()
				expect(Presenter.Ready("P14_FLAG_CAMP")).to.equal(true)
				Presenter.Reconcile(player, data, nil, cart)
				local model = assert(cart:FindFirstChild("P14CartFlag"), "Actual approved flag did not render")
				local rail = assert(model:FindFirstChild("P14FlagMountingRail"), "Mounting rail missing")
				local source = RS.StudioAssets.Cosmetics.P14_FLAG_CAMP
				local approvedParts = 0
				for _, part in source:GetDescendants() do
					if part:IsA("BasePart") then
						local copy = assert(model:FindFirstChild(part.Name, true), "Approved native part missing")
						for _, key in { "Size", "Color", "Material", "MaterialVariant", "PivotOffset" } do
							expect(copy[key]).to.equal(part[key])
						end
						approvedParts += 1
					end
				end
				expect(approvedParts).to.equal(1)
				expect(rail:GetAttribute("P14MountingRail")).to.equal(true)
				expect(rail.Material).to.equal(Enum.Material.Glacier)
				expect(rail.MaterialVariant).to.equal("Bingus_Saved_Studs_13719188279")
				expect(rail:GetAttribute("StudsPerTile")).to.equal(0.25)
				expect(rail.Color).to.equal(Color3.fromRGB(42, 46, 54))
				near(rail.Size.Y, 0.10)
				near(rail.Size.Z, 0.30)
				expect(rail.Anchored or rail.CanCollide or rail.CanTouch or rail.CanQuery).to.equal(false)
				expect(rail.Massless).to.equal(true)
				expect(rail.CollisionGroup).to.equal(root.CollisionGroup)
				local weld = assert(rail:FindFirstChild("P14CosmeticWeld"), "Rail host weld missing")
				expect(weld.Part0).to.equal(root)
				expect(weld.Part1).to.equal(rail)
				local expectedFrame, expectedSize = Presenter.FlagRail(profile)
				expect((root.CFrame:ToObjectSpace(rail.CFrame).Position - expectedFrame.Position).Magnitude < 0.0001).to.equal(
					true
				)
				expect((rail.Size - expectedSize).Magnitude < 0.00001).to.equal(true)
				for _ = 1, 3 do
					Presenter.Reconcile(player, data, nil, cart)
				end
				expect(cart:FindFirstChild("P14CartFlag")).to.equal(model)
				local rails = 0
				for _, descendant in model:GetDescendants() do
					if descendant:GetAttribute("P14MountingRail") then
						rails += 1
					end
				end
				expect(rails).to.equal(1)
				Fixtures.AssertDeepEqual(data, before)
				-- Replace an already-equipped old mount through the existing
				-- assembly boundary without changing ownership or selection.
				model:SetAttribute("P14FlagMountVersion", nil)
				Presenter.Reconcile(player, data, nil, cart)
				expect(model.Parent).to.equal(nil)
				expect(rail.Parent).to.equal(nil)
				model = assert(cart:FindFirstChild("P14CartFlag"), "Old mount was not replaced")
				rail = assert(model:FindFirstChild("P14FlagMountingRail"), "Replacement rail missing")
				expect(model:GetAttribute("P14FlagMountVersion")).to.equal(2)
				Fixtures.AssertDeepEqual(data, before)
				data.Commerce.Appearance.Flag = "None"
				Presenter.Reconcile(player, data, nil, cart)
				expect(cart:FindFirstChild("P14CartFlag")).to.equal(nil)
				expect(rail.Parent).to.equal(nil)
				for key, value in originalRoot do
					expect(root[key]).to.equal(value)
				end
			end, debug.traceback)
			cart:Destroy()
			assert(ok, failure)
		end)
		it("reproduces the old chassis-only obstruction on every measured cart/flag combination", function()
			local obstructed = 0
			for _, row in Config.CartRows do
				local profile = assert(Geometry.GetById(row.id))
				local b = profile.CoreBodyBounds
				local old =
					CFrame.new(b.Frame.Position.X + b.Size.X / 2 + 0.60, 1.65, b.Frame.Position.Z + b.Size.Z / 2 - 0.65)
				for _, flag in Bounds.Flags do
					local low, high = extent(old * flag.Frame, flag.Size)
					local hit = false
					for _, slot in profile.CargoSlots do
						for _, cargo in Bounds.Cargo do
							local cargoLow, cargoHigh = extent(slot * cargo.Frame, cargo.Size)
							if
								low.X < cargoHigh.X
								and high.X > cargoLow.X
								and low.Y < cargoHigh.Y
								and high.Y > cargoLow.Y
								and low.Z < cargoHigh.Z
								and high.Z > cargoLow.Z
							then
								hit = true
							end
						end
					end
					if hit then
						obstructed += 1
					end
				end
			end
			expect(obstructed).to.equal(27)
		end)
	end)
end
