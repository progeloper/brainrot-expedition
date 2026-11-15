--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartAssetValidator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)

	local function connectToRoot(root: BasePart, part: BasePart)
		local weld = Instance.new("WeldConstraint")
		weld.Name = string.format("%sWeld", part.Name)
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	local function addPart(parent: Instance, name: string, root: BasePart): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = false
		part.Massless = true
		part.Parent = parent
		connectToRoot(root, part)

		return part
	end

	local function createValidCart(): Model
		local cart = Instance.new("Model")
		cart.Name = "TestCart"
		cart:SetAttribute("CartId", "TEST_CART")

		local root = Instance.new("Part")
		root.Name = "Root"
		root.Anchored = false
		root.Massless = false
		root.Parent = cart
		cart.PrimaryPart = root

		local movementAttachment = Instance.new("Attachment")
		movementAttachment.Name = "MovementAttachment"
		movementAttachment.Parent = root

		local orientationAttachment = Instance.new("Attachment")
		orientationAttachment.Name = "OrientationAttachment"
		orientationAttachment.Parent = root

		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriverSeat"
		seat.Anchored = false
		seat.Massless = true
		seat.Parent = cart
		connectToRoot(root, seat)

		addPart(cart, "CameraTarget", root)
		local harpoonOrigin = addPart(cart, "HarpoonOrigin", root)
		local muzzleAttachment = Instance.new("Attachment")
		muzzleAttachment.Name = "MuzzleAttachment"
		muzzleAttachment.Parent = harpoonOrigin

		local cargoSlots = Instance.new("Folder")
		cargoSlots.Name = "CargoSlots"
		cargoSlots.Parent = cart

		for index = 1, 3 do
			local slot = addPart(cargoSlots, string.format("Slot%d", index), root)
			slot.Position = Vector3.new(index * 2, 0, 0)
			local attachment = Instance.new("Attachment")
			attachment.Name = "CargoAttachment"
			attachment.Parent = slot
		end

		local formationSlots = Instance.new("Folder")
		formationSlots.Name = "FormationSlots"
		formationSlots.Parent = cart

		for index = 1, 6 do
			local slot = addPart(formationSlots, string.format("Slot%d", index), root)
			local attachment = Instance.new("Attachment")
			attachment.Name = "FormationAttachment"
			attachment.Parent = slot
		end

		local visual = Instance.new("Model")
		visual.Name = "Visual"
		visual.Parent = cart

		local constraints = Instance.new("Folder")
		constraints.Name = "Constraints"
		constraints.Parent = cart

		return cart
	end

	describe("CartAssetValidator", function()
		for _, seatClass in { "Seat", "VehicleSeat" } do
			for _, nested in { false, true } do
				it(
					string.format(
						"rejects an additional %s nested=%s even when disabled and invisible",
						seatClass,
						tostring(nested)
					),
					function()
						local cart = createValidCart()
						local seat = Instance.new(seatClass) :: Seat | VehicleSeat
						seat.Name = "RetiredHumanSeat"
						seat.Massless = true
						seat.Disabled = true
						seat.Transparency = 1
						seat.Parent = if nested then cart.Visual else cart
						connectToRoot(cart.Root, seat)
						local result = CartAssetValidator.Validate(cart)
						expect(result.IsValid).to.equal(false)
						expect(
							table.find(
								result.Errors,
								seat:GetFullName() .. " is an additional human seat"
							)
						).never.to.equal(nil)
						cart:Destroy()
					end
				)
			end
		end

		it(
			"rejects duplicate direct DriverSeat names without accepting an ambiguous seat",
			function()
				local cart = createValidCart()
				local duplicate = cart.DriverSeat:Clone()
				duplicate.Parent = cart
				local result = CartAssetValidator.Validate(cart)
				expect(result.IsValid).to.equal(false)
				expect(
					table.find(
						result.Errors,
						"Cart requires exactly one direct VehicleSeat named DriverSeat"
					)
				).never.to.equal(nil)
				cart:Destroy()
			end
		)

		it("returns all three canonical cargo anchors in numeric order", function()
			local cart = createValidCart()
			local map = assert(CartAssetValidator.GetCargoSlotMap(cart, 3))
			for i, slot in map do
				expect(slot.Id).to.equal("Slot" .. i)
				expect(slot.Part).to.equal(cart.CargoSlots[slot.Id])
				expect(slot.Attachment).to.equal(slot.Part.CargoAttachment)
			end
			expect(#map).to.equal(3)
			cart:Destroy()
		end)
		it("rejects missing and duplicate anchors without reducing capacity", function()
			local cart = createValidCart()
			local copy = cart.CargoSlots.Slot3:Clone()
			copy.Parent = cart.CargoSlots
			expect(CartAssetValidator.GetCargoSlotMap(cart, 3)).to.equal(nil)
			copy:Destroy()
			cart.CargoSlots.Slot3.CargoAttachment:Destroy()
			expect(CartAssetValidator.GetCargoSlotMap(cart, 3)).to.equal(nil)
			cart:Destroy()
		end)
		it(
			"validates the exact required layout without unlocking extra authored positions",
			function()
				local cart = createValidCart()
				local root = cart.Root
				local fourth = addPart(cart.CargoSlots, "Slot4", root)
				fourth.Position = Vector3.new(8, 0, 0)
				local attachment = Instance.new("Attachment")
				attachment.Name = "CargoAttachment"
				attachment.Parent = fourth

				local baseLayout = CartAssetValidator.ValidateCargoLayout(cart, 3)
				expect(baseLayout.status).to.equal("Ready")
				expect(#baseLayout.positions).to.equal(3)
				expect(baseLayout.positions[3].Id).to.equal("Slot3")

				local upgradedLayout = CartAssetValidator.ValidateCargoLayout(cart, 4)
				expect(upgradedLayout.status).to.equal("Ready")
				expect(#upgradedLayout.positions).to.equal(4)
				expect(upgradedLayout.positions[4].Part).to.equal(fourth)
				cart:Destroy()
			end
		)

		it("reports a missing upgraded position instead of clamping capacity", function()
			local cart = createValidCart()
			local layout = CartAssetValidator.ValidateCargoLayout(cart, 4)
			expect(layout.status).to.equal("LayoutNotReady")
			expect(layout.requiredCapacity).to.equal(4)
			expect(#layout.positions).to.equal(0)
			expect(string.find(layout.errors[1], "Slot4", 1, true) ~= nil).to.equal(true)
			cart:Destroy()
		end)

		it("rejects coincident presentation anchors", function()
			local cart = createValidCart()
			cart.CargoSlots.Slot3.Position = cart.CargoSlots.Slot2.Position
			local layout = CartAssetValidator.ValidateCargoLayout(cart, 3, 0.25)
			expect(layout.status).to.equal("LayoutNotReady")
			expect(table.find(layout.errors, "Slot3 overlaps Slot2")).never.to.equal(nil)
			cart:Destroy()
		end)
		it("accepts an off-world cart connected by stored weld constraints", function()
			local cart = createValidCart()
			local result = CartAssetValidator.Validate(cart)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)

			cart:Destroy()
		end)

		it("rejects a BasePart disconnected from Root", function()
			local cart = createValidCart()
			local cameraTarget = cart:FindFirstChild("CameraTarget") :: BasePart
			local weld = cameraTarget:FindFirstChild("CameraTargetWeld")

			assert(weld ~= nil, "Expected CameraTarget weld")
			weld:Destroy()

			local result = CartAssetValidator.Validate(cart)

			expect(result.IsValid).to.equal(false)
			expect(
				table.find(
					result.Errors,
					string.format(
						"%s is not connected to Root's assembly",
						cameraTarget:GetFullName()
					)
				)
			).never.to.equal(nil)

			cart:Destroy()
		end)

		it("rejects a missing or wrong-class CameraTarget explicitly", function()
			local missingCart = createValidCart()
			local missingTarget = missingCart:FindFirstChild("CameraTarget")

			assert(missingTarget ~= nil, "Expected CameraTarget")
			missingTarget:Destroy()

			local missingResult = CartAssetValidator.Validate(missingCart)

			expect(missingResult.IsValid).to.equal(false)
			expect(table.find(missingResult.Errors, "Missing required child CameraTarget")).never.to.equal(
				nil
			)
			missingCart:Destroy()

			local wrongClassCart = createValidCart()
			local target = wrongClassCart:FindFirstChild("CameraTarget")

			assert(target ~= nil, "Expected CameraTarget")
			target:Destroy()

			local wrongTarget = Instance.new("Folder")
			wrongTarget.Name = "CameraTarget"
			wrongTarget.Parent = wrongClassCart

			local wrongClassResult = CartAssetValidator.Validate(wrongClassCart)

			expect(wrongClassResult.IsValid).to.equal(false)
			expect(
				table.find(wrongClassResult.Errors, "CameraTarget must be a BasePart, got Folder")
			).never.to.equal(nil)
			wrongClassCart:Destroy()
		end)

		it("does not count a disabled weld as a rigid connection", function()
			local cart = createValidCart()
			local cameraTarget = cart:FindFirstChild("CameraTarget") :: BasePart
			local weld = cameraTarget:FindFirstChild("CameraTargetWeld") :: WeldConstraint

			weld.Enabled = false

			local result = CartAssetValidator.Validate(cart)

			expect(result.IsValid).to.equal(false)
			expect(
				table.find(
					result.Errors,
					string.format(
						"%s is not connected to Root's assembly",
						cameraTarget:GetFullName()
					)
				)
			).never.to.equal(nil)

			cart:Destroy()
		end)

		it("accepts a current cart without retired launcher anchors", function()
			local cart = createValidCart()
			local marker = cart:FindFirstChild("HarpoonOrigin")
			assert(marker, "Expected the accepted fitted marker in this fixture")
			marker:Destroy()
			local result = CartAssetValidator.Validate(cart)
			expect(result.IsValid).to.equal(true)
			cart:Destroy()
		end)
	end)
end
