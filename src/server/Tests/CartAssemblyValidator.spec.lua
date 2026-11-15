--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")

	local CartAssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)

	type PartObservation = CartAssemblyValidator.PartObservation
	type RuntimeObservation = CartAssemblyValidator.RuntimeObservation
	type ValidationOptions = CartAssemblyValidator.ValidationOptions
	type ValidationResult = CartAssemblyValidator.ValidationResult

	type CartFixture = {
		Cart: Model,
		Root: BasePart,
		DriverSeat: VehicleSeat,
		CameraTarget: BasePart,
		VisualBody: BasePart,
		Constraints: Folder,
		Parts: { BasePart },
	}

	type RuntimeOverrides = {
		AssemblyMass: number?,
		CanSetNetworkOwnership: ((root: BasePart) -> (boolean, string?))?,
		GetConnectedParts: ((root: BasePart) -> { BasePart })?,
		GetPartObservation: ((part: BasePart, observation: PartObservation) -> PartObservation)?,
		RequireManagedStabilityConstraint: boolean?,
	}

	local function connectToRoot(root: BasePart, part: BasePart): WeldConstraint
		local weld = Instance.new("WeldConstraint")

		weld.Name = string.format("%sWeld", part.Name)
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part

		return weld
	end

	local function addPart(
		parts: { BasePart },
		parent: Instance,
		name: string,
		root: BasePart
	): Part
		local part = Instance.new("Part")

		part.Name = name
		part.Anchored = false
		part.Massless = true
		part.Parent = parent
		connectToRoot(root, part)
		table.insert(parts, part)

		return part
	end

	local function createValidCart(): CartFixture
		local cart = Instance.new("Model")
		local parts: { BasePart } = {}

		cart.Name = "AssemblyTestCart"
		cart:SetAttribute("CartId", "CRT_TEST")

		local root = Instance.new("Part")

		root.Name = "Root"
		root.Anchored = false
		root.Massless = false
		root.Parent = cart
		cart.PrimaryPart = root
		table.insert(parts, root)

		local movementAttachment = Instance.new("Attachment")

		movementAttachment.Name = "MovementAttachment"
		movementAttachment.Parent = root

		local orientationAttachment = Instance.new("Attachment")

		orientationAttachment.Name = "OrientationAttachment"
		orientationAttachment.Parent = root

		local driverSeat = Instance.new("VehicleSeat")

		driverSeat.Name = "DriverSeat"
		driverSeat.Anchored = false
		driverSeat.Massless = true
		driverSeat.Parent = cart
		connectToRoot(root, driverSeat)
		table.insert(parts, driverSeat)

		local cameraTarget = addPart(parts, cart, "CameraTarget", root)
		local harpoonOrigin = addPart(parts, cart, "HarpoonOrigin", root)
		local muzzleAttachment = Instance.new("Attachment")

		muzzleAttachment.Name = "MuzzleAttachment"
		muzzleAttachment.Parent = harpoonOrigin

		local cargoSlots = Instance.new("Folder")

		cargoSlots.Name = "CargoSlots"
		cargoSlots.Parent = cart

		for index = 1, 3 do
			local slot = addPart(parts, cargoSlots, string.format("Slot%d", index), root)
			local attachment = Instance.new("Attachment")

			attachment.Name = "CargoAttachment"
			attachment.Parent = slot
		end

		local formationSlots = Instance.new("Folder")

		formationSlots.Name = "FormationSlots"
		formationSlots.Parent = cart

		for index = 1, 6 do
			local slot = addPart(parts, formationSlots, string.format("Slot%d", index), root)
			local attachment = Instance.new("Attachment")

			attachment.Name = "FormationAttachment"
			attachment.Parent = slot
		end

		local visual = Instance.new("Model")

		visual.Name = "Visual"
		visual.Parent = cart

		local visualBody = addPart(parts, visual, "VisualBody", root)
		local constraints = Instance.new("Folder")

		constraints.Name = "Constraints"
		constraints.Parent = cart

		return {
			Cart = cart,
			Root = root,
			DriverSeat = driverSeat,
			CameraTarget = cameraTarget,
			VisualBody = visualBody,
			Constraints = constraints,
			Parts = parts,
		}
	end

	local function createObservedPart(fixture: CartFixture, part: BasePart): PartObservation
		return {
			CFrame = part.CFrame,
			AssemblyLinearVelocity = Vector3.zero,
			AssemblyAngularVelocity = Vector3.zero,
			AssemblyRootPart = fixture.Root,
			Mass = 10,
			Density = 0.7,
			Friction = 0.3,
			Elasticity = 0.5,
			FrictionWeight = 1,
			ElasticityWeight = 1,
			CollisionGroup = "Carts",
			Anchored = part.Anchored,
			Massless = part.Massless,
		}
	end

	local function createRuntimeOptions(
		fixture: CartFixture,
		overrides: RuntimeOverrides?
	): ValidationOptions
		local selectedOverrides = overrides or {}
		local runtimeObservation: RuntimeObservation = {
			GetPartObservation = function(part: BasePart): PartObservation
				local observation = createObservedPart(fixture, part)

				if selectedOverrides.GetPartObservation ~= nil then
					return selectedOverrides.GetPartObservation(part, observation)
				end

				return observation
			end,
			GetConnectedParts = selectedOverrides.GetConnectedParts or function(): { BasePart }
				return table.clone(fixture.Parts)
			end,
			CanSetNetworkOwnership = selectedOverrides.CanSetNetworkOwnership
				or function(): (boolean, string?)
					return true
				end,
			AssemblyMass = if selectedOverrides.AssemblyMass ~= nil
				then selectedOverrides.AssemblyMass
				else 100,
		}

		return {
			Stage = "Runtime",
			ExpectedCollisionGroup = "Carts",
			RuntimeObservation = runtimeObservation,
			RequireManagedStabilityConstraint = selectedOverrides.RequireManagedStabilityConstraint,
		}
	end

	local function createManagedStabilityTorque(fixture: CartFixture): Torque
		local torque = Instance.new("Torque")

		torque.Name = "CartStabilityTorque"
		torque.Attachment0 = fixture.Root:FindFirstChild("OrientationAttachment") :: Attachment
		torque.RelativeTo = Enum.ActuatorRelativeTo.World
		torque.Torque = Vector3.zero
		torque.Enabled = true
		torque.Parent = fixture.Constraints

		return torque
	end

	local function prepareRuntime(fixture: CartFixture)
		fixture.Cart:SetAttribute("RuntimeCart", true)
		fixture.Cart.Parent = Workspace
	end

	local function findFatal(
		result: ValidationResult,
		code: string,
		instancePath: string?
	): CartAssemblyValidator.ValidationIssue?
		for _, issue in result.FatalErrors do
			if
				issue.Code == code and (instancePath == nil or issue.InstancePath == instancePath)
			then
				return issue
			end
		end

		return nil
	end

	local function expectFatal(result: ValidationResult, code: string, instancePath: string?)
		expect(result.IsValid).to.equal(false)
		expect(findFatal(result, code, instancePath)).never.to.equal(nil)
	end

	describe("CartAssemblyValidator", function()
		for _, stage in { "Static", "Runtime", "PostReset" } do
			for _, seatClass in { "Seat", "VehicleSeat" } do
				it(
					string.format("rejects nested extra %s during %s validation", seatClass, stage),
					function()
						local fixture = createValidCart()
						local seat = Instance.new(seatClass) :: Seat | VehicleSeat
						seat.Name = "RetiredHumanSeat"
						seat.Massless = true
						seat.Disabled = true
						seat.Transparency = 1
						seat.Parent = fixture.Cart.Visual
						connectToRoot(fixture.Root, seat)
						table.insert(fixture.Parts, seat)
						local options = createRuntimeOptions(fixture)
						options.Stage = stage :: CartAssemblyValidator.ValidationStage
						if stage ~= "Static" then
							prepareRuntime(fixture)
						end
						local result = CartAssemblyValidator.Validate(fixture.Cart, options)
						expectFatal(
							result,
							"EXTRA_HUMAN_SEAT",
							fixture.Cart.Name .. ".Visual.RetiredHumanSeat"
						)
						fixture.Cart:Destroy()
					end
				)
			end
		end

		it("rejects a missing or ambiguous direct DriverSeat", function()
			local fixture = createValidCart()
			fixture.DriverSeat.Name = "FormerDriverSeat"
			local missing = CartAssemblyValidator.Validate(fixture.Cart, { Stage = "Static" })
			expectFatal(missing, "DRIVER_SEAT_INVALID", fixture.Cart.Name)
			fixture.DriverSeat.Name = "DriverSeat"
			local duplicate = Instance.new("Part")
			duplicate.Name = "DriverSeat"
			duplicate.Massless = true
			duplicate.Parent = fixture.Cart
			connectToRoot(fixture.Root, duplicate)
			local ambiguous = CartAssemblyValidator.Validate(fixture.Cart, { Stage = "Static" })
			expectFatal(ambiguous, "DRIVER_SEAT_INVALID", fixture.Cart.Name)
			fixture.Cart:Destroy()
		end)

		it("accepts zero reported mass for massless non-root runtime parts", function()
			local fixture = createValidCart()

			prepareRuntime(fixture)

			local result = CartAssemblyValidator.Validate(
				fixture.Cart,
				createRuntimeOptions(fixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part ~= fixture.Root and observation.Massless then
							observation.Mass = 0
						end

						return observation
					end,
				})
			)

			expect(result.IsValid).to.equal(true)
			expect(#result.FatalErrors).to.equal(0)

			fixture.Cart:Destroy()
		end)

		it("still rejects zero reported mass for the runtime Root", function()
			local fixture = createValidCart()

			prepareRuntime(fixture)

			local result = CartAssemblyValidator.Validate(
				fixture.Cart,
				createRuntimeOptions(fixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part == fixture.Root then
							observation.Mass = 0
						end

						return observation
					end,
				})
			)

			expectFatal(result, "ROOT_MASS_INVALID", string.format("%s.Root", fixture.Cart.Name))

			fixture.Cart:Destroy()
		end)

		it("returns a deterministic immutable result for a valid static cart", function()
			local fixture = createValidCart()
			local first = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})
			local second = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expect(first.IsValid).to.equal(true)
			expect(first.Stage).to.equal("Static")
			expect(first.CartId).to.equal("CRT_TEST")
			expect(first.ModelName).to.equal(fixture.Cart.Name)
			expect(#first.FatalErrors).to.equal(0)
			expect(#first.Warnings).to.equal(0)
			expect(table.isfrozen(first)).to.equal(true)
			expect(table.isfrozen(first.FatalErrors)).to.equal(true)
			expect(table.isfrozen(first.Warnings)).to.equal(true)
			expect(first.IsValid).to.equal(second.IsValid)
			expect(first.Stage).to.equal(second.Stage)
			expect(first.CartId).to.equal(second.CartId)
			expect(first.ModelName).to.equal(second.ModelName)
			expect(#first.FatalErrors).to.equal(#second.FatalErrors)
			expect(#first.Warnings).to.equal(#second.Warnings)

			local mutationSucceeded = pcall(function()
				(first :: any).IsValid = false
			end)

			expect(mutationSucceeded).to.equal(false)

			fixture.Cart:Destroy()
		end)

		it("sorts equivalent failures independently of descendant insertion order", function()
			local firstFixture = createValidCart()
			local secondFixture = createValidCart()
			local secondVisual = secondFixture.VisualBody.Parent

			firstFixture.CameraTarget.Anchored = true
			firstFixture.VisualBody.Anchored = true
			secondFixture.CameraTarget.Anchored = true
			secondFixture.VisualBody.Anchored = true
			secondFixture.VisualBody.Parent = nil
			secondFixture.VisualBody.Parent = secondVisual

			local first = CartAssemblyValidator.Validate(firstFixture.Cart, {
				Stage = "Static",
			})
			local second = CartAssemblyValidator.Validate(secondFixture.Cart, {
				Stage = "Static",
			})

			expect(first.IsValid).to.equal(false)
			expect(#first.FatalErrors).to.equal(#second.FatalErrors)
			expect(table.isfrozen(first.FatalErrors[1])).to.equal(true)

			for index, firstIssue in first.FatalErrors do
				local secondIssue = second.FatalErrors[index]

				expect(firstIssue.Code).to.equal(secondIssue.Code)
				expect(firstIssue.InstancePath).to.equal(secondIssue.InstancePath)
			end

			firstFixture.Cart:Destroy()
			secondFixture.Cart:Destroy()
		end)

		it("allows only source Root anchoring and reports non-root mass as a warning", function()
			local fixture = createValidCart()

			fixture.Root.Anchored = true
			fixture.CameraTarget.Massless = false

			local result = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expect(result.IsValid).to.equal(true)
			expect(#result.FatalErrors).to.equal(0)
			expect(#result.Warnings).to.equal(1)
			expect(result.Warnings[1].Code).to.equal("NON_ROOT_PART_HAS_MASS")

			fixture.Cart:Destroy()
		end)

		it("rejects a missing named Root", function()
			local fixture = createValidCart()

			fixture.Root:Destroy()

			local result = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expectFatal(result, "ROOT_MISSING", fixture.Cart.Name)

			fixture.Cart:Destroy()
		end)

		it("rejects an anchored runtime moving part", function()
			local fixture = createValidCart()

			prepareRuntime(fixture)
			fixture.VisualBody.Anchored = true

			local result =
				CartAssemblyValidator.Validate(fixture.Cart, createRuntimeOptions(fixture))

			expectFatal(
				result,
				"PART_ANCHORED",
				string.format("%s.Visual.VisualBody", fixture.Cart.Name)
			)

			fixture.Cart:Destroy()
		end)

		it("rejects a disconnected required part", function()
			local fixture = createValidCart()
			local weld = fixture.CameraTarget:FindFirstChild("CameraTargetWeld")

			assert(weld ~= nil, "Expected CameraTargetWeld")
			weld:Destroy()

			local result = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				result,
				"PART_DISCONNECTED",
				string.format("%s.CameraTarget", fixture.Cart.Name)
			)

			fixture.Cart:Destroy()
		end)

		it(
			"reports missing Part0, missing Part1, external, and disabled weld references",
			function()
				local missingPart0Fixture = createValidCart()
				local missingPart0Weld = missingPart0Fixture.CameraTarget:FindFirstChild(
					"CameraTargetWeld"
				) :: WeldConstraint

				missingPart0Weld.Part0 = nil

				local missingPart0Result =
					CartAssemblyValidator.Validate(missingPart0Fixture.Cart, {
						Stage = "Static",
					})

				expectFatal(
					missingPart0Result,
					"JOINT_PART0_MISSING",
					string.format("%s.CameraTarget.CameraTargetWeld", missingPart0Fixture.Cart.Name)
				)

				missingPart0Fixture.Cart:Destroy()

				local missingFixture = createValidCart()
				local missingWeld =
					missingFixture.CameraTarget:FindFirstChild("CameraTargetWeld") :: WeldConstraint

				missingWeld.Part1 = nil

				local missingResult = CartAssemblyValidator.Validate(missingFixture.Cart, {
					Stage = "Static",
				})

				expectFatal(
					missingResult,
					"JOINT_PART1_MISSING",
					string.format("%s.CameraTarget.CameraTargetWeld", missingFixture.Cart.Name)
				)

				missingFixture.Cart:Destroy()

				local externalFixture = createValidCart()
				local externalWeld =
					externalFixture.CameraTarget:FindFirstChild("CameraTargetWeld") :: WeldConstraint
				local externalPart = Instance.new("Part")

				externalPart.Name = "ExternalPart"
				externalPart.Parent = Workspace
				externalWeld.Part1 = externalPart

				local externalResult = CartAssemblyValidator.Validate(externalFixture.Cart, {
					Stage = "Static",
				})

				expectFatal(
					externalResult,
					"JOINT_EXTERNAL_REFERENCE",
					string.format("%s.CameraTarget.CameraTargetWeld", externalFixture.Cart.Name)
				)

				externalFixture.Cart:Destroy()
				externalPart:Destroy()

				local disabledFixture = createValidCart()
				local disabledWeld =
					disabledFixture.CameraTarget:FindFirstChild("CameraTargetWeld") :: WeldConstraint

				disabledWeld.Enabled = false

				local disabledResult = CartAssemblyValidator.Validate(disabledFixture.Cart, {
					Stage = "Static",
				})

				expectFatal(
					disabledResult,
					"JOINT_DISABLED",
					string.format("%s.CameraTarget.CameraTargetWeld", disabledFixture.Cart.Name)
				)

				disabledFixture.Cart:Destroy()
			end
		)

		it("rejects RigidConstraints with missing or external attachments", function()
			local missingFixture = createValidCart()
			local missingConstraint = Instance.new("RigidConstraint")

			missingConstraint.Name = "MissingAttachmentConstraint"
			missingConstraint.Attachment0 =
				missingFixture.Root:FindFirstChild("MovementAttachment") :: Attachment
			missingConstraint.Attachment1 = nil
			missingConstraint.Parent = missingFixture.Constraints

			local missingResult = CartAssemblyValidator.Validate(missingFixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				missingResult,
				"CONSTRAINT_ATTACHMENT_MISSING",
				string.format(
					"%s.Constraints.MissingAttachmentConstraint",
					missingFixture.Cart.Name
				)
			)

			missingFixture.Cart:Destroy()

			local externalFixture = createValidCart()
			local externalPart = Instance.new("Part")
			local externalAttachment = Instance.new("Attachment")
			local externalConstraint = Instance.new("RigidConstraint")

			externalPart.Name = "ExternalConstraintPart"
			externalPart.Parent = Workspace
			externalAttachment.Name = "ExternalAttachment"
			externalAttachment.Parent = externalPart
			externalConstraint.Name = "ExternalAttachmentConstraint"
			externalConstraint.Attachment0 =
				externalFixture.Root:FindFirstChild("MovementAttachment") :: Attachment
			externalConstraint.Attachment1 = externalAttachment
			externalConstraint.Parent = externalFixture.Constraints

			local externalResult = CartAssemblyValidator.Validate(externalFixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				externalResult,
				"CONSTRAINT_EXTERNAL_ATTACHMENT",
				string.format(
					"%s.Constraints.ExternalAttachmentConstraint",
					externalFixture.Cart.Name
				)
			)

			externalFixture.Cart:Destroy()
			externalPart:Destroy()
		end)

		it("rejects a disabled or externally connected NoCollisionConstraint", function()
			local disabledFixture = createValidCart()
			local disabledConstraint = Instance.new("NoCollisionConstraint")

			disabledConstraint.Name = "DisabledNoCollision"
			disabledConstraint.Part0 = disabledFixture.Root
			disabledConstraint.Part1 = disabledFixture.VisualBody
			disabledConstraint.Enabled = false
			disabledConstraint.Parent = disabledFixture.Constraints

			local disabledResult = CartAssemblyValidator.Validate(disabledFixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				disabledResult,
				"CONSTRAINT_DISABLED",
				string.format("%s.Constraints.DisabledNoCollision", disabledFixture.Cart.Name)
			)
			disabledFixture.Cart:Destroy()

			local externalFixture = createValidCart()
			local externalPart = Instance.new("Part")
			local externalConstraint = Instance.new("NoCollisionConstraint")

			externalPart.Name = "ExternalCollisionPart"
			externalPart.Parent = Workspace
			externalConstraint.Name = "ExternalNoCollision"
			externalConstraint.Part0 = externalFixture.Root
			externalConstraint.Part1 = externalPart
			externalConstraint.Parent = externalFixture.Constraints

			local externalResult = CartAssemblyValidator.Validate(externalFixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				externalResult,
				"JOINT_EXTERNAL_REFERENCE",
				string.format("%s.Constraints.ExternalNoCollision", externalFixture.Cart.Name)
			)
			externalFixture.Cart:Destroy()
			externalPart:Destroy()
		end)

		it("rejects a pre-authored movement constraint conflict", function()
			local fixture = createValidCart()
			local movementConstraint = Instance.new("LinearVelocity")

			movementConstraint.Name = "UnexpectedDriveVelocity"
			movementConstraint.Attachment0 =
				fixture.Root:FindFirstChild("MovementAttachment") :: Attachment
			movementConstraint.Parent = fixture.Constraints

			local result = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				result,
				"MOVEMENT_CONSTRAINT_CONFLICT",
				string.format("%s.Constraints.UnexpectedDriveVelocity", fixture.Cart.Name)
			)

			fixture.Cart:Destroy()
		end)

		it("reports duplicate pre-authored propulsion constraints", function()
			local fixture = createValidCart()
			local movementAttachment =
				fixture.Root:FindFirstChild("MovementAttachment") :: Attachment

			for index = 1, 2 do
				local movementConstraint = Instance.new("LinearVelocity")

				movementConstraint.Name = string.format("UnexpectedDriveVelocity%d", index)
				movementConstraint.Attachment0 = movementAttachment
				movementConstraint.Parent = fixture.Constraints
			end

			local result = CartAssemblyValidator.Validate(fixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				result,
				"MOVEMENT_CONSTRAINT_DUPLICATE",
				string.format("%s.Constraints", fixture.Cart.Name)
			)

			fixture.Cart:Destroy()
		end)

		it("accepts exactly one required managed runtime stability Torque", function()
			local fixture = createValidCart()

			prepareRuntime(fixture)
			createManagedStabilityTorque(fixture)

			local result = CartAssemblyValidator.Validate(
				fixture.Cart,
				createRuntimeOptions(fixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expect(result.IsValid).to.equal(true)
			expect(#result.FatalErrors).to.equal(0)

			fixture.Cart:Destroy()
		end)

		it("rejects a missing or duplicate required managed stability Torque", function()
			local missingFixture = createValidCart()

			prepareRuntime(missingFixture)

			local missingResult = CartAssemblyValidator.Validate(
				missingFixture.Cart,
				createRuntimeOptions(missingFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				missingResult,
				"STABILITY_CONSTRAINT_MISSING",
				string.format("%s.Constraints", missingFixture.Cart.Name)
			)
			missingFixture.Cart:Destroy()

			local duplicateFixture = createValidCart()

			prepareRuntime(duplicateFixture)
			createManagedStabilityTorque(duplicateFixture)
			createManagedStabilityTorque(duplicateFixture)

			local duplicateResult = CartAssemblyValidator.Validate(
				duplicateFixture.Cart,
				createRuntimeOptions(duplicateFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				duplicateResult,
				"STABILITY_CONSTRAINT_DUPLICATE",
				string.format("%s.Constraints", duplicateFixture.Cart.Name)
			)
			duplicateFixture.Cart:Destroy()
		end)

		it("rejects malformed managed stability constraint ownership", function()
			local attachmentFixture = createValidCart()

			prepareRuntime(attachmentFixture)

			local attachmentTorque = createManagedStabilityTorque(attachmentFixture)

			attachmentTorque.Attachment0 =
				attachmentFixture.Root:FindFirstChild("MovementAttachment") :: Attachment

			local attachmentResult = CartAssemblyValidator.Validate(
				attachmentFixture.Cart,
				createRuntimeOptions(attachmentFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				attachmentResult,
				"STABILITY_CONSTRAINT_ATTACHMENT_INVALID",
				string.format("%s.Constraints.CartStabilityTorque", attachmentFixture.Cart.Name)
			)
			attachmentFixture.Cart:Destroy()

			local secondAttachmentFixture = createValidCart()

			prepareRuntime(secondAttachmentFixture)

			local secondAttachmentTorque = createManagedStabilityTorque(secondAttachmentFixture)
			local unexpectedAttachment = Instance.new("Attachment")

			unexpectedAttachment.Name = "UnexpectedStabilityAttachment"
			unexpectedAttachment.Parent = secondAttachmentFixture.Root
			secondAttachmentTorque.Attachment1 = unexpectedAttachment

			local secondAttachmentResult = CartAssemblyValidator.Validate(
				secondAttachmentFixture.Cart,
				createRuntimeOptions(secondAttachmentFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				secondAttachmentResult,
				"STABILITY_CONSTRAINT_ATTACHMENT_INVALID",
				string.format(
					"%s.Constraints.CartStabilityTorque",
					secondAttachmentFixture.Cart.Name
				)
			)
			secondAttachmentFixture.Cart:Destroy()

			local frameFixture = createValidCart()

			prepareRuntime(frameFixture)

			local frameTorque = createManagedStabilityTorque(frameFixture)

			frameTorque.RelativeTo = Enum.ActuatorRelativeTo.Attachment0

			local frameResult = CartAssemblyValidator.Validate(
				frameFixture.Cart,
				createRuntimeOptions(frameFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				frameResult,
				"STABILITY_CONSTRAINT_REFERENCE_FRAME_INVALID",
				string.format("%s.Constraints.CartStabilityTorque", frameFixture.Cart.Name)
			)
			frameFixture.Cart:Destroy()

			local disabledFixture = createValidCart()

			prepareRuntime(disabledFixture)

			local disabledTorque = createManagedStabilityTorque(disabledFixture)

			disabledTorque.Enabled = false

			local disabledResult = CartAssemblyValidator.Validate(
				disabledFixture.Cart,
				createRuntimeOptions(disabledFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				disabledResult,
				"STABILITY_CONSTRAINT_DISABLED",
				string.format("%s.Constraints.CartStabilityTorque", disabledFixture.Cart.Name)
			)
			disabledFixture.Cart:Destroy()
		end)

		it("limits the managed stability exception to the exact runtime contract", function()
			local staticFixture = createValidCart()

			createManagedStabilityTorque(staticFixture)

			local staticResult = CartAssemblyValidator.Validate(staticFixture.Cart, {
				Stage = "Static",
			})

			expectFatal(
				staticResult,
				"MOVEMENT_CONSTRAINT_CONFLICT",
				string.format("%s.Constraints.CartStabilityTorque", staticFixture.Cart.Name)
			)
			staticFixture.Cart:Destroy()

			local wrongClassFixture = createValidCart()

			prepareRuntime(wrongClassFixture)

			local wrongClass = Instance.new("LinearVelocity")

			wrongClass.Name = "CartStabilityTorque"
			wrongClass.Attachment0 =
				wrongClassFixture.Root:FindFirstChild("MovementAttachment") :: Attachment
			wrongClass.Parent = wrongClassFixture.Constraints

			local wrongClassResult = CartAssemblyValidator.Validate(
				wrongClassFixture.Cart,
				createRuntimeOptions(wrongClassFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				wrongClassResult,
				"MOVEMENT_CONSTRAINT_CONFLICT",
				string.format("%s.Constraints.CartStabilityTorque", wrongClassFixture.Cart.Name)
			)
			expectFatal(
				wrongClassResult,
				"STABILITY_CONSTRAINT_MISSING",
				string.format("%s.Constraints", wrongClassFixture.Cart.Name)
			)
			wrongClassFixture.Cart:Destroy()

			local wrongParentFixture = createValidCart()

			prepareRuntime(wrongParentFixture)

			local wrongParentTorque = createManagedStabilityTorque(wrongParentFixture)

			wrongParentTorque.Parent = wrongParentFixture.Cart

			local wrongParentResult = CartAssemblyValidator.Validate(
				wrongParentFixture.Cart,
				createRuntimeOptions(wrongParentFixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				wrongParentResult,
				"STABILITY_CONSTRAINT_PARENT_INVALID",
				string.format("%s.CartStabilityTorque", wrongParentFixture.Cart.Name)
			)
			wrongParentFixture.Cart:Destroy()
		end)

		it("rejects a non-finite managed stability Torque value", function()
			local fixture = createValidCart()

			prepareRuntime(fixture)

			local torque = createManagedStabilityTorque(fixture)

			torque.Torque = Vector3.new(0 / 0, 0, 0)

			local result = CartAssemblyValidator.Validate(
				fixture.Cart,
				createRuntimeOptions(fixture, {
					RequireManagedStabilityConstraint = true,
				})
			)

			expectFatal(
				result,
				"CONSTRAINT_VALUE_NONFINITE",
				string.format("%s.Constraints.CartStabilityTorque", fixture.Cart.Name)
			)
			fixture.Cart:Destroy()
		end)

		it("rejects runtime collision, ownership, and assembly-root violations", function()
			local collisionFixture = createValidCart()

			prepareRuntime(collisionFixture)

			local collisionResult = CartAssemblyValidator.Validate(
				collisionFixture.Cart,
				createRuntimeOptions(collisionFixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part == collisionFixture.VisualBody then
							observation.CollisionGroup = "Default"
						end

						return observation
					end,
				})
			)

			expectFatal(
				collisionResult,
				"COLLISION_GROUP_MISMATCH",
				string.format("%s.Visual.VisualBody", collisionFixture.Cart.Name)
			)
			collisionFixture.Cart:Destroy()

			local ownershipFixture = createValidCart()

			prepareRuntime(ownershipFixture)

			local ownershipResult = CartAssemblyValidator.Validate(
				ownershipFixture.Cart,
				createRuntimeOptions(ownershipFixture, {
					CanSetNetworkOwnership = function(): (boolean, string?)
						return false, "test root cannot receive ownership"
					end,
				})
			)

			expectFatal(
				ownershipResult,
				"NETWORK_OWNERSHIP_UNAVAILABLE",
				string.format("%s.Root", ownershipFixture.Cart.Name)
			)
			ownershipFixture.Cart:Destroy()

			local assemblyFixture = createValidCart()

			prepareRuntime(assemblyFixture)

			local assemblyResult = CartAssemblyValidator.Validate(
				assemblyFixture.Cart,
				createRuntimeOptions(assemblyFixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part == assemblyFixture.DriverSeat then
							observation.AssemblyRootPart = assemblyFixture.VisualBody
						end

						return observation
					end,
				})
			)

			expectFatal(
				assemblyResult,
				"ASSEMBLY_ROOT_MISMATCH",
				string.format("%s.DriverSeat", assemblyFixture.Cart.Name)
			)
			assemblyFixture.Cart:Destroy()
		end)

		it("rejects NaN and positive or negative infinity in runtime observations", function()
			local cases = {
				{ Value = 0 / 0, Label = "NaN" },
				{ Value = math.huge, Label = "positive infinity" },
				{ Value = -math.huge, Label = "negative infinity" },
			}

			for _, case in cases do
				local fixture = createValidCart()

				prepareRuntime(fixture)

				local result = CartAssemblyValidator.Validate(
					fixture.Cart,
					createRuntimeOptions(fixture, {
						AssemblyMass = case.Value,
					})
				)

				expectFatal(
					result,
					"TOTAL_MASS_INVALID",
					string.format("%s.Root", fixture.Cart.Name)
				)

				fixture.Cart:Destroy()
			end

			local observationFixture = createValidCart()

			prepareRuntime(observationFixture)

			local observationResult = CartAssemblyValidator.Validate(
				observationFixture.Cart,
				createRuntimeOptions(observationFixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part == observationFixture.Root then
							observation.AssemblyLinearVelocity =
								Vector3.new(0 / 0, math.huge, -math.huge)
						end

						return observation
					end,
				})
			)

			expectFatal(
				observationResult,
				"LINEAR_VELOCITY_NONFINITE",
				string.format("%s.Root", observationFixture.Cart.Name)
			)

			observationFixture.Cart:Destroy()

			local physicalFixture = createValidCart()

			prepareRuntime(physicalFixture)

			local physicalResult = CartAssemblyValidator.Validate(
				physicalFixture.Cart,
				createRuntimeOptions(physicalFixture, {
					GetPartObservation = function(
						part: BasePart,
						observation: PartObservation
					): PartObservation
						if part == physicalFixture.Root then
							observation.Density = -math.huge
						end

						return observation
					end,
				})
			)

			expectFatal(
				physicalResult,
				"PHYSICAL_PROPERTY_INVALID",
				string.format("%s.Root", physicalFixture.Cart.Name)
			)

			physicalFixture.Cart:Destroy()
		end)
	end)
end
