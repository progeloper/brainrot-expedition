--!nocheck
return function()
	-- Camp Rework: these specs cover the pre-Training profile/Speed contract; pin TrainingV1 off
	-- (it previews on in Studio). Training is covered by CampRework.spec.
	local CampFlagsForSpec = require(game:GetService("ReplicatedStorage").Shared.Config.CampReworkFlags)
	local trainingBeforeSpec = CampFlagsForSpec._SetForTests("TrainingV1Enabled", false) -- restored at the end (synchronous runner)
	local Carts = require(game.ReplicatedStorage.Shared.Config.Carts)
	local Resolver = require(game.ReplicatedStorage.Shared.Utility.CartMovementProfileResolver)
	local Controller = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CartMovementController)
	local function fixture(callback)
		local folder = Instance.new("Folder")
		folder.Name = "SPEC_CART_CLASS_REFRESH"
		folder.Parent = workspace
		local cart = Instance.new("Model")
		cart.Name = "InertClassRefresh"
		cart.Parent = folder
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Anchored = true
		root.Parent = cart
		cart.PrimaryPart = root
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local orientation = Instance.new("AlignOrientation")
		orientation.Attachment0 = attachment
		orientation.MaxAngularVelocity = math.rad(130)
		orientation.Parent = root
		cart:SetAttribute("CargoCapacity", 6)
		cart:SetAttribute("LongitudinalAuthorityEpoch", 91)
		local ok, why = xpcall(function()
			callback(cart, root, orientation)
		end, debug.traceback)
		folder:Destroy()
		assert(ok, why)
	end
	local function publish(cart, id, level)
		cart:SetAttribute("CartId", id)
		cart:SetAttribute("ResolvedMaxTravelSpeed", Carts[id].MaxTravelSpeed * (1 + 0.1 * level))
		cart:SetAttribute("PerformanceSpeedContribution", 0.1 * level)
		cart:SetAttribute("PerformanceRevision", (cart:GetAttribute("PerformanceRevision") or 0) + 1)
	end
	describe("Phase13 same-chassis class refresh", function()
		it(
			"applies each class and purchased stop square while preserving root, handshake, command and cargo",
			function()
				fixture(function(cart, root, orientation)
					publish(cart, "CRT_001", 0)
					local previous = Resolver.ResolveForCart(cart)
					local before = root.CFrame
					local velocity = root.AssemblyLinearVelocity
					for _, id in { "CRT_008", "CRT_011", "CRT_001" } do
						for _, level in { 0, 3, 5 } do
							publish(cart, id, level)
							local snapshot = Controller._TestRefreshPerformanceProfile(cart, previous, orientation)
							expect(snapshot.Profile.CartId).to.equal(id)
							expect(
								math.abs(snapshot.Profile.MaxTravelSpeed - Carts[id].MaxTravelSpeed * (1 + 0.1 * level))
									< 1e-8
							).to.equal(true)
							expect(
								math.abs(snapshot.Profile.Braking - Carts[id].Braking * (1 + 0.1 * level) ^ 2) < 1e-8
							).to.equal(true)
							expect(
								math.abs(
									snapshot.Profile.CoastDeceleration
										- Carts[id].CoastDeceleration * (1 + 0.1 * level) ^ 2
								) < 1e-8
							).to.equal(true)
							expect(snapshot.Profile.ControlReferenceSpeed).to.equal(36)
							expect(snapshot.Profile.ForwardAcceleration).to.equal(Carts[id].ForwardAcceleration)
							expect(snapshot.Profile.RecoveryBackupSpeed).to.equal(3.5)
							expect(
								math.abs(orientation.MaxAngularVelocity - math.rad(Carts[id].MaxAngularSpeed)) < 1e-5
							).to.equal(true)
							expect(snapshot.LongitudinalEpoch).to.equal(9)
							expect(snapshot.LongitudinalRevision).to.equal(4)
							expect(snapshot.InputSequence).to.equal(11)
							expect(snapshot.PendingRequests).to.equal(1)
							expect(snapshot.CommandedSpeed).to.equal(7)
							expect(snapshot.SchedulerConnections).to.equal(0)
							expect(cart.PrimaryPart).to.equal(root)
							expect(root.CFrame).to.equal(before)
							expect(root.AssemblyLinearVelocity).to.equal(velocity)
							expect(cart:GetAttribute("CargoCapacity")).to.equal(6)
							expect(cart:GetAttribute("LongitudinalAuthorityEpoch")).to.equal(91)
							previous = snapshot.Profile
						end
					end
				end)
			end
		)
		it("changes fitted axle alignment through legacy and wheel-free swaps without resetting movement state",function()
			fixture(function(cart,root,orientation)
				publish(cart,"CRT_001",0)
				local previous=Resolver.ResolveForCart(cart)
				local before=root.CFrame
				local geometries=require(game.ReplicatedStorage.Shared.Config.CartGeometry)
				for _,choice in {
					{Id="CRT_001",Geometry="CRT_001",Axis=Enum.AlignType.PrimaryAxisParallel},
					{Id="CRT_008",Geometry="CRT_008",Axis=Enum.AlignType.PrimaryAxisParallel},
					{Id="CRT_001",Axis=Enum.AlignType.AllAxes},
					{Id="CRT_001",Geometry="DEV_RUNNER_FIXTURE",Axis=Enum.AlignType.AllAxes},
					{Id="CRT_013",Geometry="CRT_013",Axis=Enum.AlignType.PrimaryAxisParallel},
				}do
					publish(cart,choice.Id,0)
					cart:SetAttribute("CartGeometryId",choice.Geometry)
					cart:SetAttribute("CartGeometryRevision",if choice.Geometry then geometries[choice.Geometry].Revision else nil)
					local snapshot=Controller._TestRefreshPerformanceProfile(cart,previous,orientation)
					expect(orientation.AlignType).to.equal(choice.Axis)
					expect(orientation.MaxTorque).to.equal(Carts[choice.Id].UprightTorque)
					expect(orientation.Responsiveness).to.equal(Carts[choice.Id].UprightResponsiveness)
					expect(snapshot.CommandedSpeed).to.equal(7)
					expect(snapshot.LongitudinalEpoch).to.equal(9)
					expect(snapshot.InputSequence).to.equal(11)
					expect(snapshot.PendingRequests).to.equal(1)
					expect(snapshot.SchedulerConnections).to.equal(0)
					expect(cart.PrimaryPart).to.equal(root)
					expect(root.CFrame).to.equal(before)
					expect(cart:GetAttribute("CargoCapacity")).to.equal(6)
					previous=snapshot.Profile
				end
			end)
		end)
		it("refuses a stale attach generation without changing the accepted profile or orientation", function()
			fixture(function(cart, _root, orientation)
				publish(cart, "CRT_001", 0)
				local previous = Resolver.ResolveForCart(cart)
				publish(cart, "CRT_011", 5)
				local angular = orientation.MaxAngularVelocity
				local snapshot = Controller._TestRefreshPerformanceProfile(cart, previous, orientation, true)
				expect(snapshot.Profile).to.equal(previous)
				expect(orientation.MaxAngularVelocity).to.equal(angular)
				expect(snapshot.LongitudinalEpoch).to.equal(9)
				expect(snapshot.PendingRequests).to.equal(1)
				expect(Controller.GetMovementDiagnosticSnapshot().Started).to.equal(false)
			end)
		end)
	end)
	CampFlagsForSpec._SetForTests("TrainingV1Enabled", trainingBeforeSpec)
end
