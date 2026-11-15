--!nocheck
-- Human seat contract only; equipped brainrot formations remain independent.
return function()
	local Contract = require(game.ReplicatedStorage.Shared.Utility.CartSeatContract)
	local Occupants = require(script.Parent.Parent.Services.CartOccupantService)

	describe("Solo cart human seat contract", function()
		it("accepts only the one direct authored VehicleSeat DriverSeat", function()
			local cart = Instance.new("Model")
			local driver = Instance.new("VehicleSeat")
			driver.Name, driver.Parent = "DriverSeat", cart
			local passenger = Instance.new("Seat")
			passenger.Name, passenger.Parent = "PassengerSeat1", cart
			local hunter = Instance.new("Seat")
			hunter.Name, hunter.Parent = "HunterSeat", cart
			expect(Contract.GetDriverSeat(cart)).to.equal(driver)
			expect(Contract.IsSeat(cart, driver)).to.equal(true)
			expect(Contract.IsSeat(cart, passenger)).to.equal(false)
			expect(Contract.IsSeat(cart, hunter)).to.equal(false)
			hunter.Name = "NearbySeat"
			expect(Contract.IsSeat(cart, hunter)).to.equal(false)
			local folder = Instance.new("Folder")
			folder.Parent, driver.Parent = cart, folder
			expect(Contract.GetDriverSeat(cart)).to.equal(nil)
			expect(Contract.IsSeat(cart, driver)).to.equal(false)
			cart:Destroy()
		end)

		it(
			"fails closed on duplicate DriverSeat names even when one has the wrong class",
			function()
				local cart = Instance.new("Model")
				local driver = Instance.new("VehicleSeat")
				driver.Name, driver.Parent = "DriverSeat", cart
				local duplicate = Instance.new("Part")
				duplicate.Name, duplicate.Parent = "DriverSeat", cart
				expect(Contract.GetDriverSeat(cart)).to.equal(nil)
				expect(Contract.IsSeat(cart, driver)).to.equal(false)
				duplicate:Destroy()
				expect(Contract.GetDriverSeat(cart)).to.equal(driver)
				cart:Destroy()
			end
		)

		it("rejects wrong driver classes and vacant or retired seat joints", function()
			local cart = Instance.new("Model")
			local wrong = Instance.new("Seat")
			wrong.Name, wrong.Parent = "DriverSeat", cart
			expect(Contract.IsSeat(cart, wrong)).to.equal(false)
			wrong:Destroy()
			local seat = Instance.new("VehicleSeat")
			seat.Name, seat.Parent = "DriverSeat", cart
			local weld = Instance.new("Weld")
			weld.Part0, weld.Parent = seat, seat
			local outsider = Instance.new("Part")
			weld.Part1 = outsider
			expect(Contract.IsCurrentJoint(cart, weld)).to.equal(false)
			seat.Name = "PassengerSeat2"
			expect(Contract.SeatForJoint(cart, weld)).to.equal(nil)
			outsider:Destroy()
			cart:Destroy()
		end)

		it("accepts only the current driver's native seat joint", function()
			local cart = Instance.new("Model")
			cart.Name, cart.Parent = "SPEC_SOLO_SEAT", workspace
			local seat = Instance.new("VehicleSeat")
			seat.Name, seat.Position, seat.Anchored, seat.Parent =
				"DriverSeat", Vector3.new(19000, 100, 19000), true, cart
			local character = Instance.new("Model")
			character.Name, character.Parent = "SPEC_SOLO_DRIVER", workspace
			local root = Instance.new("Part")
			root.Name, root.Position, root.Parent =
				"HumanoidRootPart", seat.Position + Vector3.new(0, 3, 0), character
			local torso = Instance.new("Part")
			torso.Name, torso.Position, torso.Parent = "Torso", root.Position, character
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = root, torso, root
			local humanoid = Instance.new("Humanoid")
			humanoid.RequiresNeck, humanoid.Parent = false, character
			local ok, failure = xpcall(function()
				seat:Sit(humanoid)
				task.wait(0.05)
				local joint = seat:FindFirstChild("SeatWeld")
				expect(seat.Occupant).to.equal(humanoid)
				expect(joint ~= nil).to.equal(true)
				expect(Contract.IsCurrentJoint(cart, joint)).to.equal(true)
				seat.Name = "HunterSeat"
				expect(Contract.IsCurrentJoint(cart, joint)).to.equal(false)
			end, debug.traceback)
			character:Destroy()
			cart:Destroy()
			if not ok then
				error(failure, 0)
			end
		end)

		it(
			"does not treat an unregistered cart owner or retired seat as actual occupants",
			function()
				local cart = Instance.new("Model")
				cart:SetAttribute("OwnerUserId", 123)
				local seat = Instance.new("Seat")
				seat.Name, seat.Parent = "PassengerSeat1", cart
				expect(#Occupants:GetOccupants(cart)).to.equal(0)
				cart:Destroy()
			end
		)
	end)
end
