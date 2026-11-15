--!strict
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")
	local RunService = game:GetService("RunService")
	local PhysicsService = game:GetService("PhysicsService")
	-- Disposable headless test places do not run CollisionService.Start.
	if not PhysicsService:IsCollisionGroupRegistered("Carts") then
		PhysicsService:RegisterCollisionGroup("Carts")
	end
	local Config = require(ReplicatedStorage.Shared.Config.CartLocalCorrection)
	local Stuck = require(ReplicatedStorage.Shared.Utility.CartStuckAttempt)
	local Placement = require(script.Parent.Parent.Utility.CartLocalPlacement)
	local Reset = require(script.Parent.Parent.Services.CartResetService)
	local Executor = require(script.Parent.Parent.Utility.CartResetExecutor)
	local CartService = require(script.Parent.Parent.Services.CartService)

	describe("Phase 10 server cart correction", function()
		it("uses elapsed five seconds and one stud while bounding retry to one second", function()
			local state = Stuck.Create()
			expect(Stuck.Step(state, Vector3.zero, true, 0, Config)).to.equal(false)
			expect(Stuck.Step(state, Vector3.new(0.4, 100, 0.1), true, 4.99, Config)).to.equal(false)
			expect(Stuck.Step(state, Vector3.new(0.4, 100, 0.1), true, 5, Config)).to.equal(true)
			expect(Stuck.Step(state, Vector3.zero, true, 5.99, Config)).to.equal(false)
			expect(Stuck.Step(state, Vector3.zero, true, 6, Config)).to.equal(true)
			expect(Stuck.Step(state, Vector3.new(1, 0, 0), true, 6.1, Config)).to.equal(false)
			expect(state.StartedAt).to.equal(6.1)
			expect(Stuck.Step(state, Vector3.new(1, 0, 0), false, 11.2, Config)).to.equal(false)
			expect(state.Reference).to.equal(nil)
		end)

		it("rejects every old manual server path without moving a cart", function()
			local cart = Instance.new("Model")
			local part = Instance.new("Part")
			part.Name = "Root"
			part.Anchored = true
			part.Parent = cart
			cart.PrimaryPart = part
			cart:PivotTo(CFrame.new(13, 7, 21))
			local before = cart:GetPivot()
			local player = {} :: any
			expect(select(1, Reset:BeginReset(player, cart))).to.equal(false)
			expect(select(1, CartService:ResetCart(player))).to.equal(false)
			expect(select(1, Executor.Execute(cart, CFrame.new(0, 4, 0), player))).to.equal(false)
			expect(cart:GetPivot()).to.equal(before)
			cart:Destroy()
		end)

		local fixtureCount = 0
		local function withFixture(callback: (any) -> ())
			-- Exercise the real bounded helper, preserving any active runtime context.
			Placement.ResetQueryBudgetForTesting()
			fixtureCount += 1
			local origin = Vector3.new(3000 + fixtureCount * 60, 6000, 3000)
			local folder = Instance.new("Folder")
			folder.Name = "Phase10CorrectionFixture"
			folder.Parent = Workspace
			local ground = Instance.new("Part")
			ground.Name = "DrivableFloor"
			ground.Size = Vector3.new(40, 2, 40)
			ground.CFrame = CFrame.new(origin - Vector3.yAxis)
			ground.Anchored = true
			ground:SetAttribute("CartDrivableGround", true)
			ground.Parent = folder
			local cart = Instance.new("Model")
			cart.Parent = folder
			local root = Instance.new("Part")
			root.Name = "Root"
			root.Size = Vector3.new(4, 2, 6)
			root.CFrame = CFrame.new(origin + Vector3.yAxis)
			root.Anchored = true
			root.Parent = cart
			cart.PrimaryPart = root
			local character = Instance.new("Model")
			character.Parent = folder
			local hrp = Instance.new("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.CanCollide = false
			hrp.Anchored = true
			hrp.CFrame = CFrame.new(origin + Vector3.yAxis * 8)
			hrp.Parent = character
			local core = Instance.new("Part")
			core.Name = "Torso"
			core.Size = Vector3.new(2, 6, 1)
			core.Anchored = true
			core.CanCollide = false
			core.CFrame = hrp.CFrame
			core.Parent = character
			local player = { Character = character } :: any
			local previous = Placement.Configure({
				Descriptors = {
					GetRegionAtPosition = function()
						return "REGION_FOREST"
					end,
					GetGate = function()
						return nil
					end,
				},
				Access = {
					GetEffectiveAccess = function()
						return true
					end,
				},
			})
			local succeeded, failure = pcall(callback, {
				origin = origin,
				folder = folder,
				ground = ground,
				cart = cart,
				root = root,
				player = player,
				character = character,
			})
			Placement.Configure(previous)
			folder:Destroy()
			if not succeeded then
				error(failure, 0)
			end
		end

		it(
			"prepares same X/Z and core-height/3 support lift, ignores accessories and revalidates dynamic blockage",
			function()
				withFixture(function(f)
					local accessory = Instance.new("Accessory")
					accessory.Parent = f.character
					local handle = Instance.new("Part")
					handle.Name = "Handle"
					handle.Size = Vector3.one * 50
					handle.Anchored = true
					handle.CanCollide = false
					handle.Parent = accessory
					expect(Placement.DriverBodyHeight(f.player)).to.equal(6)
					local plan, reason = Placement.Prepare(f.cart, f.player, -Vector3.zAxis)
					expect(reason).to.equal(nil)
					expect(plan ~= nil).to.equal(true)
					expect(plan.frame.Position.X).to.equal(f.origin.X)
					expect(plan.frame.Position.Z).to.equal(f.origin.Z)
					expect(math.abs(plan.frame.Position.Y + plan.measure.supportMinimum.Y - f.origin.Y - 2) < 1e-4).to.equal(
						true
					)
					expect(plan.frame.UpVector.Y > 0.999).to.equal(true)
					local blocker = Instance.new("Part")
					blocker.Name = "TransientCeiling"
					blocker.Size = Vector3.new(5, 1, 7)
					blocker.Anchored = true
					blocker.CFrame = plan.frame
					blocker.Parent = f.folder
					expect(select(1, Placement.Revalidate(plan))).to.equal(false)
					blocker:Destroy()
					expect(select(1, Placement.Revalidate(plan))).to.equal(true)
				end)
			end
		)

		it("recognizes supported overturned body and rejects airborne, decorative roof and missing support", function()
			withFixture(function(f)
				f.cart:PivotTo(f.root.CFrame * CFrame.Angles(0, 0, math.pi))
				expect(Placement.IsSupported(f.cart)).to.equal(true)
				f.cart:PivotTo(f.root.CFrame + Vector3.yAxis * 8)
				expect(Placement.IsSupported(f.cart)).to.equal(false)
				f.ground:SetAttribute("CartDrivableGround", false)
				expect(select(1, Placement.Prepare(f.cart, f.player, -Vector3.zAxis)) == nil).to.equal(true)
				f.ground:Destroy()
				expect(select(1, Placement.Prepare(f.cart, f.player, -Vector3.zAxis)) == nil).to.equal(true)
			end)
		end)

		it("uses authored Camp boundary independently of hunting access and validates the assigned spawn", function()
			withFixture(function(f)
				local previous = Placement.Configure({
					Descriptors = {
						GetRegionAtPosition = function()
							return nil
						end,
						GetGate = function()
							return nil
						end,
					},
					Access = {
						GetEffectiveAccess = function()
							return false
						end,
					},
					CampContains = function(position)
						return (position - f.origin).Magnitude < 30
					end,
				})
				local succeeded, failure = pcall(function()
					local plan, reason = Placement.Prepare(f.cart, f.player, -Vector3.zAxis)
					expect(reason).to.equal(nil)
					expect(plan ~= nil).to.equal(true)
					expect(select(1, Placement.ValidateAssignedSpawn(f.cart, f.root.CFrame + Vector3.yAxis * 4))).to.equal(
						true
					)
				end)
				Placement.Configure(previous)
				if not succeeded then
					error(failure, 0)
				end
			end)
		end)

		it(
			"authorizes the exact external assigned pad and own-base correction without weakening gates or clearance",
			function()
				withFixture(function(f)
					f.ground:Destroy()
					local base = Instance.new("Model")
					base.Name = "Base_01"
					base:SetAttribute("BaseId", "BASE_SPEC")
					base.Parent = f.folder
					-- Preserve native Base_01 relative geometry, translated into this
					-- isolated fixture's vertical/spatial neighborhood.
					local nativeMarker = Vector3.new(-132.399994, 1.50000095, -204.732208)
					local offset = f.origin - nativeMarker
					local function surface(name, position, size)
						local part = Instance.new("Part")
						part.Name = name
						part.Anchored = true
						part.Size = size
						part.CFrame = CFrame.new(position + offset)
						part:SetAttribute("LayoutRole", name)
						part.Parent = base
						return part
					end
					surface("CartDisplay", Vector3.new(-132.4, 0.55, -204.732208), Vector3.new(27.2, 1, 36))
					surface("CartRamp", Vector3.new(-132.4, 0.55, -180.93), Vector3.new(24, 1, 12))
					surface("Foundation", Vector3.new(-95.27, 0.55, -226.46), Vector3.new(46.66, 1, 79.46))
					surface("HouseRamp", Vector3.new(-95.27, 0.55, -180.93), Vector3.new(20, 1, 12))
					local marker = surface("CartSpawn", nativeMarker, Vector3.one)
					marker.CanCollide, marker.CanQuery, marker.CanTouch = false, false, false
					marker:SetAttribute("Enabled", true)
					marker:SetAttribute("SpawnId", "BASE_SPEC_CART")
					marker:SetAttribute("CartId", "CRT_001")
					f.player.UserId = 920001
					f.cart:SetAttribute("CartId", "CRT_001")
					f.cart:SetAttribute("SpawnId", "BASE_SPEC_CART")
					f.cart:SetAttribute("OwnerUserId", f.player.UserId)
					local currentBase = base
					local crossing = nil
					local campContains = false
					local previous = Placement.Configure({
						Descriptors = {
							GetRegionAtPosition = function()
								return nil
							end,
							GetGate = function(_, id)
								return if crossing and id == "REGION_BEACH" then { crossing = crossing } else nil
							end,
						},
						Access = {
							GetEffectiveAccess = function()
								return false
							end,
						},
						CampContains = function()
							return campContains
						end,
						GetAssignedBase = function(player)
							return if player == f.player then currentBase else nil
						end,
					})
					local identity = {
						Base = base,
						Marker = marker,
						Player = f.player,
						CurrentBase = function()
							return currentBase
						end,
					}
					local frame = marker.CFrame * CFrame.new(0, 4, 0)
					local succeeded, failure = pcall(function()
						expect(select(1, Placement.ValidateAssignedSpawn(f.cart, frame))).to.equal(false)
						-- Match the observed native support failure even when Camp
						-- admits this centre: CartDisplay needs assigned-base authority.
						campContains = true
						local withoutIdentity, nativeReason = Placement.ValidateAssignedSpawn(f.cart, frame)
						expect(withoutIdentity).to.equal(false)
						expect(nativeReason).to.equal("InvalidDrivableSupport")
						campContains = false
						local clear, reason = Placement.ValidateAssignedSpawn(f.cart, frame, identity)
						expect(reason).to.equal(nil)
						expect(clear).to.equal(true)
						expect(select(1, Placement.ValidateAssignedSpawn(f.cart, frame + Vector3.xAxis, identity))).to.equal(
							false
						)
						currentBase = nil
						expect(select(1, Placement.ValidateAssignedSpawn(f.cart, frame, identity))).to.equal(false)
						currentBase = base
						local plan, correctionReason = Placement.Prepare(f.cart, f.player, -Vector3.zAxis)
						expect(correctionReason).to.equal(nil)
						expect(plan ~= nil).to.equal(true)
						expect(plan.frame.Position.X).to.equal(f.root.Position.X)
						expect(plan.frame.Position.Z).to.equal(f.root.Position.Z)
						local otherPlayer = { Character = f.character, UserId = 920002 } :: any
						expect(select(1, Placement.Prepare(f.cart, otherPlayer, -Vector3.zAxis)) == nil).to.equal(true)
						local obstruction = Instance.new("Part")
						obstruction.Name = "DynamicPadOccupant"
						obstruction.Anchored = true
						obstruction.Size = Vector3.new(6, 2, 8)
						obstruction.CFrame = frame
						obstruction.Parent = f.folder
						expect(select(1, Placement.ValidateAssignedSpawn(f.cart, frame, identity))).to.equal(false)
						obstruction:Destroy()
						crossing = Instance.new("Part")
						crossing.Name = "DeniedExternalThreshold"
						crossing.Anchored = true
						crossing.CanCollide, crossing.CanQuery = false, false
						crossing.Size = Vector3.new(8, 12, 10)
						crossing.CFrame = frame
						crossing.Parent = f.folder
						expect(select(1, Placement.ValidateAssignedSpawn(f.cart, frame, identity))).to.equal(false)
						expect(select(1, Placement.Prepare(f.cart, f.player, -Vector3.zAxis)) == nil).to.equal(true)
					end)
					Placement.Configure(previous)
					if not succeeded then
						error(failure, 0)
					end
				end)
			end
		)

		it("rejects a semantic nonqueryable denied gate", function()
			withFixture(function(f)
				local crossing = Instance.new("Part")
				crossing.Name = "DeniedThreshold"
				crossing.CanCollide = false
				crossing.CanQuery = false
				crossing.Anchored = true
				crossing.Size = Vector3.new(8, 10, 2)
				crossing.CFrame = f.root.CFrame
				crossing.Parent = f.folder
				local previous = Placement.Configure({
					Descriptors = {
						GetRegionAtPosition = function()
							return "REGION_FOREST"
						end,
						GetGate = function(_, id)
							return if id == "REGION_BEACH" then { crossing = crossing } else nil
						end,
					},
					Access = {
						GetEffectiveAccess = function(_, _, id)
							return id == "REGION_FOREST"
						end,
					},
				})
				expect(select(1, Placement.Prepare(f.cart, f.player, -Vector3.zAxis)) == nil).to.equal(true)
				Placement.Configure(previous)
			end)
		end)

		it("refines a partial terrain support voxel and rejects actual terrain ceiling", function()
			-- Terrain collision meshing requires native simulation, matching the
			-- established CartCameraOcclusion terrain fixture harness.
			local wasRunning = RunService:IsRunning()
			if not wasRunning then
				RunService:Run()
			end
			local ok, simulationFailure = pcall(function()
				withFixture(function(f)
					local cleanupFrame = CFrame.new(f.origin + Vector3.yAxis * 15)
					local cleanupSize = Vector3.new(40, 44, 40)
					local succeeded, failure = pcall(function()
						f.ground:Destroy()
						Workspace.Terrain:FillBlock(
							CFrame.new(f.origin - Vector3.yAxis * 3),
							Vector3.new(30, 8, 30),
							Enum.Material.Grass
						)
						RunService.Heartbeat:Wait()
						local plan, reason = Placement.Prepare(f.cart, f.player, -Vector3.zAxis)
						expect(reason).to.equal(nil)
						expect(plan ~= nil).to.equal(true)
						Workspace.Terrain:FillBlock(cleanupFrame, cleanupSize, Enum.Material.Air)
						Workspace.Terrain:FillBlock(
							CFrame.new(f.origin - Vector3.yAxis * 3) * CFrame.Angles(0, 0, math.rad(7)),
							Vector3.new(30, 8, 30),
							Enum.Material.Grass
						)
						RunService.Heartbeat:Wait()
						local slopePlan, slopeReason = Placement.Prepare(f.cart, f.player, -Vector3.zAxis)
						expect(slopeReason).to.equal(nil)
						expect(slopePlan ~= nil).to.equal(true)
						Workspace.Terrain:FillBlock(
							CFrame.new(plan.frame.Position + Vector3.yAxis),
							Vector3.new(10, 3, 12),
							Enum.Material.Rock
						)
						RunService.Heartbeat:Wait()
						expect(select(1, Placement.Revalidate(plan))).to.equal(false)
					end)
					Workspace.Terrain:FillBlock(cleanupFrame, cleanupSize, Enum.Material.Air)
					if not succeeded then
						error(failure, 0)
					end
				end)
			end)
			if not wasRunning then
				RunService:Pause()
			end
			if not ok then
				error(simulationFailure, 0)
			end
		end)
	end)
end
