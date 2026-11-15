--!nocheck
-- Actual controller/factory with isolated native carts; no ownership grants or
-- player/backend access. Moving-player screenshots are a separate native gate.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Factory = require(RS.Shared.Utility.Phase14TrailFactory)
	local Geometry = require(RS.Shared.Utility.CartGeometry)
	local Profiles = require(RS.Shared.Config.CartGeometry)
	local Config = require(RS.Shared.Config.Phase13)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Controller = require(
		game.StarterPlayer.StarterPlayerScripts.Client.Controllers.Phase14CosmeticController
	)
	local function create(folder, id)
		local cart, root = Instance.new("Model"), Instance.new("Part")
		root.Name, root.Parent, root.Anchored = "Root", cart, true
		cart.PrimaryPart = root
		cart:SetAttribute("CartGeometryId", id)
		cart:SetAttribute("CartGeometryRevision", assert(Geometry.GetById(id)).Revision)
		cart:SetAttribute("CartGeneration", 1)
		cart:SetAttribute("OwnerUserId", 8101)
		cart:SetAttribute("P14TrailId", "P14_TRAIL_STARFORGE")
		cart:SetAttribute("P14TrailBinding", Factory.Binding(cart, "P14_TRAIL_STARFORGE"))
		cart.Parent = folder
		return cart, root
	end
	local function step(folder, position, effects, visibility)
		Controller._StepForTesting(
			0.1,
			folder,
			position or Vector3.zero,
			effects ~= false,
			visibility or function()
				return true
			end
		)
	end
	local function trails(root)
		local values = {}
		for _, child in root:GetChildren() do
			if child:IsA("Trail") then
				table.insert(values, child)
			end
		end
		return values
	end
	describe("Phase14 fitted native trail generation lifecycle", function()
		for _, row in Config.CartRows do
			it(
				row.id .. " binds exactly two native rear ribbons without changing its geometry",
				function()
					local folder = Instance.new("Folder")
					local cart, root = create(folder, row.id)
					local profile = assert(Geometry.Get(cart))
					local before = Fixtures.Clone(profile)
					local ok, failure = xpcall(function()
						step(folder)
						local rendered = trails(root)
						expect(#rendered).to.equal(2)
						local left, right = Factory.MountFrames(profile)
						for index, frame in { left, right } do
							local a = root:FindFirstChild("P14Trail_" .. index .. "_0")
							local b = root:FindFirstChild("P14Trail_" .. index .. "_1")
							expect(
								((a.Position + b.Position) / 2 - frame.Position).Magnitude < 0.00001
							).to.equal(true)
						end
						for _ = 1, 20 do
							step(folder)
						end
						expect(#trails(root)).to.equal(2)
						expect(Controller.GetDiagnostics().connections).to.equal(0)
						Fixtures.AssertDeepEqual(profile, before)
					end, debug.traceback)
					Controller.Stop()
					folder:Destroy()
					assert(ok, failure)
				end
			)
		end
		it("derives rotated/displaced body anchors without requiring wheels", function()
			local profile = Fixtures.Clone(Profiles.CRT_001)
			profile.Wheels = {}
			profile.CoreBodyBounds.Frame = CFrame.new(8, 6, -4) * CFrame.Angles(0.1, 0.6, -0.2)
			local left, right = Factory.MountFrames(profile)
			local localLeft = profile.CoreBodyBounds.Frame:ToObjectSpace(left)
			local localRight = profile.CoreBodyBounds.Frame:ToObjectSpace(right)
			expect(math.abs(localLeft.X + profile.CoreBodyBounds.Size.X * 0.33) < 0.00001).to.equal(
				true
			)
			expect(math.abs(localRight.X - profile.CoreBodyBounds.Size.X * 0.33) < 0.00001).to.equal(
				true
			)
			expect(localLeft.Z > profile.CoreBodyBounds.Size.Z / 2).to.equal(true)
		end)
		it(
			"clears and replaces stale cart/root/geometry generations and removes beyond the range hysteresis",
			function()
				local folder = Instance.new("Folder")
				local cart, root = create(folder, "CRT_001")
				local ok, failure = xpcall(function()
					step(folder)
					local old = trails(root)[1]
					cart:SetAttribute("CartGeneration", 2)
					step(folder)
					expect(old.Parent).to.equal(nil)
					expect(#trails(root)).to.equal(0)
					cart:SetAttribute(
						"P14TrailBinding",
						Factory.Binding(cart, "P14_TRAIL_STARFORGE")
					)
					step(folder)
					expect(#trails(root)).to.equal(2)
					old = trails(root)[1]
					cart:SetAttribute("CartGeometryId", "CRT_008")
					step(folder)
					expect(old.Parent).to.equal(nil)
					cart:SetAttribute(
						"P14TrailBinding",
						Factory.Binding(cart, "P14_TRAIL_STARFORGE")
					)
					step(folder)
					local nextRoot = Instance.new("Part")
					nextRoot.Anchored, nextRoot.Parent, cart.PrimaryPart = true, cart, nextRoot
					step(folder)
					expect(#trails(root)).to.equal(0)
					expect(#trails(nextRoot)).to.equal(2)
					step(folder, Vector3.new(100, 0, 0))
					expect(#trails(nextRoot)).to.equal(2)
					step(folder, Vector3.new(100.01, 0, 0))
					expect(#trails(nextRoot)).to.equal(0)
					step(folder, Vector3.new(80.01, 0, 0))
					expect(#trails(nextRoot)).to.equal(0)
					step(folder, Vector3.new(80, 0, 0))
					expect(#trails(nextRoot)).to.equal(2)
				end, debug.traceback)
				Controller.Stop()
				folder:Destroy()
				assert(ok, failure)
			end
		)
		it(
			"cleans stream-out, visibility, reset and reduced effects without changing selected ownership metadata",
			function()
				local folder = Instance.new("Folder")
				local cart, root = create(folder, "CRT_001")
				local ok, failure = xpcall(function()
					step(folder)
					cart.Parent = nil
					step(folder)
					expect(#trails(root)).to.equal(0)
					cart.Parent = folder
					step(folder)
					expect(#trails(root)).to.equal(2)
					step(folder, nil, false)
					expect(#trails(root)).to.equal(0)
					expect(cart:GetAttribute("P14TrailId")).to.equal("P14_TRAIL_STARFORGE")
					step(folder)
					cart:SetAttribute("ResetActive", true)
					step(folder)
					expect(#trails(root)).to.equal(0)
					cart:SetAttribute("ResetActive", false)
					step(folder)
					step(folder, nil, true, function()
						return false
					end)
					for _, trail in trails(root) do
						expect(trail.Enabled).to.equal(false)
					end
					cart:SetAttribute("OwnerUserId", 8102)
					step(folder)
					expect(#trails(root)).to.equal(0)
					cart:SetAttribute(
						"P14TrailBinding",
						Factory.Binding(cart, "P14_TRAIL_STARFORGE")
					)
					step(folder)
					expect(#trails(root)).to.equal(2)
					expect(Controller.GetDiagnostics().trails).to.equal(2)
				end, debug.traceback)
				Controller.Stop()
				folder:Destroy()
				assert(ok, failure)
			end
		)
	end)
end
