--!strict
local SeatContract = require(script.Parent.Parent.Utility.CartSeatContract)

export type ValidationStage = "Static" | "Runtime" | "PostReset"
export type ValidationSeverity = "Fatal" | "Warning"

export type ValidationIssue = {
	Code: string,
	Severity: ValidationSeverity,
	InstancePath: string?,
	Message: string,
	Expected: string?,
	Actual: string?,
	Remediation: string?,
}

export type ValidationResult = {
	IsValid: boolean,
	Stage: ValidationStage,
	CartId: string,
	ModelName: string,
	FatalErrors: { ValidationIssue },
	Warnings: { ValidationIssue },
}

export type PartObservation = {
	CFrame: CFrame,
	AssemblyLinearVelocity: Vector3,
	AssemblyAngularVelocity: Vector3,
	AssemblyRootPart: BasePart?,
	Mass: number,
	Density: number,
	Friction: number,
	Elasticity: number,
	FrictionWeight: number,
	ElasticityWeight: number,
	CollisionGroup: string,
	Anchored: boolean,
	Massless: boolean,
}

export type RuntimeObservation = {
	GetPartObservation: ((part: BasePart) -> PartObservation)?,
	GetConnectedParts: ((root: BasePart) -> { BasePart })?,
	CanSetNetworkOwnership: ((root: BasePart) -> (boolean, string?))?,
	AssemblyMass: number?,
}

export type ValidationOptions = {
	Stage: ValidationStage,
	ExpectedCollisionGroup: string?,
	RuntimeObservation: RuntimeObservation?,
	RequireManagedStabilityConstraint: boolean?,
}

type IssueFields = {
	Instance: Instance?,
	Message: string,
	Expected: string?,
	Actual: string?,
	Remediation: string?,
}

local MOVEMENT_CONSTRAINT_CLASSES: { [string]: "Propulsion" | "Orientation" } = {
	AlignPosition = "Propulsion",
	AlignOrientation = "Orientation",
	AngularVelocity = "Orientation",
	BodyAngularVelocity = "Orientation",
	BodyForce = "Propulsion",
	BodyGyro = "Orientation",
	BodyPosition = "Propulsion",
	BodyThrust = "Propulsion",
	BodyVelocity = "Propulsion",
	LineForce = "Propulsion",
	LinearVelocity = "Propulsion",
	RocketPropulsion = "Propulsion",
	Torque = "Orientation",
	VectorForce = "Propulsion",
}

local MANAGED_STABILITY_CONSTRAINT_NAME = "CartStabilityTorque"

local PHYSICAL_PROPERTY_LIMITS = {
	Density = {
		Minimum = 0.01,
		Maximum = 100,
	},
	Friction = {
		Minimum = 0,
		Maximum = 2,
	},
	Elasticity = {
		Minimum = 0,
		Maximum = 1,
	},
	FrictionWeight = {
		Minimum = 0,
		Maximum = 100,
	},
	ElasticityWeight = {
		Minimum = 0,
		Maximum = 100,
	},
}

local CartAssemblyValidator = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector2(value: Vector2): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y)
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function isFiniteCFrame(value: CFrame): boolean
	local x, y, z, xx, yx, zx, xy, yy, zy, xz, yz, zz = value:GetComponents()

	return isFiniteNumber(x)
		and isFiniteNumber(y)
		and isFiniteNumber(z)
		and isFiniteNumber(xx)
		and isFiniteNumber(yx)
		and isFiniteNumber(zx)
		and isFiniteNumber(xy)
		and isFiniteNumber(yy)
		and isFiniteNumber(zy)
		and isFiniteNumber(xz)
		and isFiniteNumber(yz)
		and isFiniteNumber(zz)
end

local function getRelativePath(cartModel: Model, instance: Instance?): string?
	if instance == nil then
		return nil
	end

	if instance == cartModel then
		return cartModel.Name
	end

	local pathParts: { string } = {}
	local current: Instance? = instance

	while current ~= nil and current ~= cartModel do
		table.insert(pathParts, 1, current.Name)
		current = current.Parent
	end

	if current ~= cartModel then
		return instance:GetFullName()
	end

	table.insert(pathParts, 1, cartModel.Name)

	return table.concat(pathParts, ".")
end

local function createIssue(
	cartModel: Model,
	code: string,
	severity: ValidationSeverity,
	fields: IssueFields
): ValidationIssue
	return {
		Code = code,
		Severity = severity,
		InstancePath = getRelativePath(cartModel, fields.Instance),
		Message = fields.Message,
		Expected = fields.Expected,
		Actual = fields.Actual,
		Remediation = fields.Remediation,
	}
end

local function addFatal(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	code: string,
	fields: IssueFields
)
	table.insert(fatalErrors, createIssue(cartModel, code, "Fatal", fields))
end

local function addWarning(
	cartModel: Model,
	warnings: { ValidationIssue },
	code: string,
	fields: IssueFields
)
	table.insert(warnings, createIssue(cartModel, code, "Warning", fields))
end

local function compareIssues(first: ValidationIssue, second: ValidationIssue): boolean
	if first.Code ~= second.Code then
		return first.Code < second.Code
	end

	local firstPath = first.InstancePath or ""
	local secondPath = second.InstancePath or ""

	if firstPath ~= secondPath then
		return firstPath < secondPath
	end

	return first.Message < second.Message
end

local function freezeIssues(issues: { ValidationIssue }): { ValidationIssue }
	table.sort(issues, compareIssues)

	for _, issue in issues do
		table.freeze(issue)
	end

	return table.freeze(issues)
end

local function getSortedDescendants(cartModel: Model): { Instance }
	local descendants = cartModel:GetDescendants()

	table.sort(descendants, function(first, second)
		local firstPath = getRelativePath(cartModel, first) or first.Name
		local secondPath = getRelativePath(cartModel, second) or second.Name

		if firstPath == secondPath then
			return first.ClassName < second.ClassName
		end

		return firstPath < secondPath
	end)

	return descendants
end

local function getSortedParts(cartModel: Model): { BasePart }
	local parts: { BasePart } = {}

	for _, descendant in getSortedDescendants(cartModel) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getAttachmentPart(attachment: Attachment?): BasePart?
	local parent = if attachment ~= nil then attachment.Parent else nil

	return if parent ~= nil and parent:IsA("BasePart") then parent else nil
end

local function addRigidConnection(
	adjacency: { [BasePart]: { BasePart } },
	first: BasePart?,
	second: BasePart?
)
	if first == nil or second == nil or adjacency[first] == nil or adjacency[second] == nil then
		return
	end

	table.insert(adjacency[first], second)
	table.insert(adjacency[second], first)
end

local function validatePartReference(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	instance: Instance,
	propertyName: string,
	part: BasePart?,
	allowedExternalPart: BasePart?
): boolean
	if part == nil then
		addFatal(
			cartModel,
			fatalErrors,
			if propertyName == "Part0" then "JOINT_PART0_MISSING" else "JOINT_PART1_MISSING",
			{
				Instance = instance,
				Message = string.format("%s has no %s", instance.ClassName, propertyName),
				Expected = string.format("%s references a cart BasePart", propertyName),
				Actual = "nil",
				Remediation = "Author the joint with both required cart-local part references.",
			}
		)
		return false
	end

	if not part:IsDescendantOf(cartModel) and part ~= allowedExternalPart then
		addFatal(cartModel, fatalErrors, "JOINT_EXTERNAL_REFERENCE", {
			Instance = instance,
			Message = string.format("%s references a BasePart outside the cart", propertyName),
			Expected = "Referenced part is a descendant of this cart",
			Actual = part:GetFullName(),
			Remediation = "Remove the external reference and reconnect only cart descendants.",
		})
		return false
	end

	return true
end

local function getAllowedSeatedJointExternalPart(
	cartModel: Model,
	joint: JointInstance,
	first: BasePart?,
	second: BasePart?,
	stage: ValidationStage
): BasePart?
	if stage == "Static" then
		return nil
	end

	local driverSeatInstance = SeatContract.SeatForJoint(cartModel, joint)
	if not driverSeatInstance then
		return nil
	end

	local occupant = driverSeatInstance.Occupant
	local character = if occupant ~= nil then occupant.Parent else nil

	if character == nil or not character:IsA("Model") then
		return nil
	end

	if first == driverSeatInstance and second ~= nil and second:IsDescendantOf(character) then
		return second
	elseif second == driverSeatInstance and first ~= nil and first:IsDescendantOf(character) then
		return first
	end

	return nil
end

local function validateAttachmentReference(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	instance: Instance,
	propertyName: string,
	attachment: Attachment?
): boolean
	if attachment == nil then
		addFatal(cartModel, fatalErrors, "CONSTRAINT_ATTACHMENT_MISSING", {
			Instance = instance,
			Message = string.format("%s has no %s", instance.ClassName, propertyName),
			Expected = string.format("%s references an Attachment", propertyName),
			Actual = "nil",
			Remediation = "Assign the required attachment before using this constraint.",
		})
		return false
	end

	if not attachment:IsDescendantOf(cartModel) then
		addFatal(cartModel, fatalErrors, "CONSTRAINT_EXTERNAL_ATTACHMENT", {
			Instance = instance,
			Message = string.format("%s references an Attachment outside the cart", propertyName),
			Expected = "Referenced attachment is a descendant of this cart",
			Actual = attachment:GetFullName(),
			Remediation = "Use an attachment owned by this cart.",
		})
		return false
	end

	local attachmentPart = getAttachmentPart(attachment)

	if attachmentPart == nil then
		addFatal(cartModel, fatalErrors, "CONSTRAINT_ATTACHMENT_PARENT_INVALID", {
			Instance = attachment,
			Message = "Constraint attachment is not parented to a BasePart",
			Expected = "Attachment parent is a cart BasePart",
			Actual = if attachment.Parent ~= nil then attachment.Parent.ClassName else "unparented",
			Remediation = "Parent the attachment to its intended cart BasePart.",
		})
		return false
	end

	return true
end

local function validateAttachmentTransforms(cartModel: Model, fatalErrors: { ValidationIssue })
	for _, descendant in getSortedDescendants(cartModel) do
		if descendant:IsA("Attachment") and not isFiniteCFrame(descendant.CFrame) then
			addFatal(cartModel, fatalErrors, "ATTACHMENT_TRANSFORM_NONFINITE", {
				Instance = descendant,
				Message = "Attachment transform contains NaN or infinity",
				Expected = "Finite attachment CFrame",
				Actual = tostring(descendant.CFrame),
				Remediation = "Correct the authored attachment transform.",
			})
		end
	end
end

local function addNonFiniteConstraintValue(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	constraint: Instance,
	propertyName: string,
	actual: string
)
	addFatal(cartModel, fatalErrors, "CONSTRAINT_VALUE_NONFINITE", {
		Instance = constraint,
		Message = string.format("%s.%s is not finite", constraint.ClassName, propertyName),
		Expected = "Finite physical value",
		Actual = actual,
		Remediation = "Replace the malformed force, torque, velocity, or transform value.",
	})
end

local function validateMovementConstraintValues(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	constraint: Instance
)
	if constraint:IsA("LinearVelocity") then
		if not isFiniteVector3(constraint.VectorVelocity) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"VectorVelocity",
				tostring(constraint.VectorVelocity)
			)
		end

		if not isFiniteNumber(constraint.LineVelocity) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"LineVelocity",
				tostring(constraint.LineVelocity)
			)
		end

		if not isFiniteVector2(constraint.PlaneVelocity) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"PlaneVelocity",
				tostring(constraint.PlaneVelocity)
			)
		end

		if not isFiniteNumber(constraint.MaxForce) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"MaxForce",
				tostring(constraint.MaxForce)
			)
		end

		if not isFiniteVector3(constraint.MaxAxesForce) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"MaxAxesForce",
				tostring(constraint.MaxAxesForce)
			)
		end
	elseif constraint:IsA("VectorForce") then
		if not isFiniteVector3(constraint.Force) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"Force",
				tostring(constraint.Force)
			)
		end
	elseif constraint:IsA("AngularVelocity") then
		if not isFiniteVector3(constraint.AngularVelocity) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"AngularVelocity",
				tostring(constraint.AngularVelocity)
			)
		end

		if not isFiniteNumber(constraint.MaxTorque) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"MaxTorque",
				tostring(constraint.MaxTorque)
			)
		end
	elseif constraint:IsA("AlignOrientation") then
		if not isFiniteCFrame(constraint.CFrame) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"CFrame",
				tostring(constraint.CFrame)
			)
		end

		if not isFiniteNumber(constraint.MaxTorque) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"MaxTorque",
				tostring(constraint.MaxTorque)
			)
		end

		if not isFiniteNumber(constraint.MaxAngularVelocity) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"MaxAngularVelocity",
				tostring(constraint.MaxAngularVelocity)
			)
		end

		if not isFiniteNumber(constraint.Responsiveness) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"Responsiveness",
				tostring(constraint.Responsiveness)
			)
		end
	elseif constraint:IsA("Torque") then
		if not isFiniteVector3(constraint.Torque) then
			addNonFiniteConstraintValue(
				cartModel,
				fatalErrors,
				constraint,
				"Torque",
				tostring(constraint.Torque)
			)
		end
	end
end

local function validateMovementConstraintReferences(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	constraint: Instance
)
	if constraint:IsA("AlignOrientation") then
		if constraint.Mode == Enum.OrientationAlignmentMode.TwoAttachment then
			validateAttachmentReference(
				cartModel,
				fatalErrors,
				constraint,
				"Attachment1",
				constraint.Attachment1
			)
		end
	elseif constraint:IsA("AlignPosition") then
		if constraint.Mode == Enum.PositionAlignmentMode.TwoAttachment then
			validateAttachmentReference(
				cartModel,
				fatalErrors,
				constraint,
				"Attachment1",
				constraint.Attachment1
			)
		end
	elseif constraint:IsA("LineForce") then
		validateAttachmentReference(
			cartModel,
			fatalErrors,
			constraint,
			"Attachment1",
			constraint.Attachment1
		)
	end

	local requiresAttachment0 = constraint:IsA("AlignPosition")
		or constraint:IsA("LinearVelocity")
		or constraint:IsA("VectorForce")
		or constraint:IsA("AngularVelocity")
		or constraint:IsA("AlignOrientation")
		or constraint:IsA("LineForce")
		or constraint:IsA("Torque")

	if requiresAttachment0 then
		local attachment0 = (constraint :: any).Attachment0 :: Attachment?

		validateAttachmentReference(cartModel, fatalErrors, constraint, "Attachment0", attachment0)
	end
end

local function validateManagedStabilityConstraint(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	constraint: Torque
)
	local constraints = cartModel:FindFirstChild("Constraints")
	local root = cartModel:FindFirstChild("Root")
	local orientationAttachment = if root ~= nil and root:IsA("BasePart")
		then root:FindFirstChild("OrientationAttachment")
		else nil

	if constraints == nil or not constraints:IsA("Folder") or constraint.Parent ~= constraints then
		addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_PARENT_INVALID", {
			Instance = constraint,
			Message = "Managed stability Torque is outside the cart Constraints folder",
			Expected = string.format("%s.Constraints", cartModel.Name),
			Actual = if constraint.Parent ~= nil then constraint.Parent:GetFullName() else "nil",
			Remediation = "Create the managed stability Torque directly under Constraints.",
		})
	end

	if
		orientationAttachment == nil
		or not orientationAttachment:IsA("Attachment")
		or constraint.Attachment0 ~= orientationAttachment
		or constraint.Attachment1 ~= nil
	then
		addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_ATTACHMENT_INVALID", {
			Instance = constraint,
			Message = "Managed stability Torque does not use the single approved attachment",
			Expected = string.format(
				"Attachment0=%s.Root.OrientationAttachment Attachment1=nil",
				cartModel.Name
			),
			Actual = string.format(
				"Attachment0=%s Attachment1=%s",
				if constraint.Attachment0 ~= nil
					then constraint.Attachment0:GetFullName()
					else "nil",
				if constraint.Attachment1 ~= nil
					then constraint.Attachment1:GetFullName()
					else "nil"
			),
			Remediation = "Attach the managed stability Torque to the established orientation attachment.",
		})
	end

	if constraint.RelativeTo ~= Enum.ActuatorRelativeTo.World then
		addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_REFERENCE_FRAME_INVALID", {
			Instance = constraint,
			Message = "Managed stability Torque uses the wrong reference frame",
			Expected = tostring(Enum.ActuatorRelativeTo.World),
			Actual = tostring(constraint.RelativeTo),
			Remediation = "Use a world-relative Torque so roll and pitch correction axes are explicit.",
		})
	end

	if not constraint.Enabled then
		addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_DISABLED", {
			Instance = constraint,
			Message = "Managed stability Torque is disabled",
			Expected = "Enabled=true",
			Actual = "Enabled=false",
			Remediation = "Keep the validated Torque enabled and suspend assistance by applying zero torque.",
		})
	end

	validateMovementConstraintReferences(cartModel, fatalErrors, constraint)
	validateMovementConstraintValues(cartModel, fatalErrors, constraint)
end

local function validateJointsAndConstraints(
	cartModel: Model,
	fatalErrors: { ValidationIssue },
	adjacency: { [BasePart]: { BasePart } },
	options: ValidationOptions
)
	local movementConstraintCounts = {
		Orientation = 0,
		Propulsion = 0,
	}
	local managedStabilityConstraintCount = 0

	for _, descendant in getSortedDescendants(cartModel) do
		local movementCategory = MOVEMENT_CONSTRAINT_CLASSES[descendant.ClassName]
		local isManagedStabilityConstraint = options.Stage ~= "Static"
			and options.RequireManagedStabilityConstraint == true
			and descendant:IsA("Torque")
			and descendant.Name == MANAGED_STABILITY_CONSTRAINT_NAME

		if descendant:IsA("JointInstance") then
			if not descendant.Enabled then
				addFatal(cartModel, fatalErrors, "JOINT_DISABLED", {
					Instance = descendant,
					Message = "Rigid cart joint is disabled",
					Expected = "Enabled=true",
					Actual = "Enabled=false",
					Remediation = "Enable the authored cart joint or remove it.",
				})
			end

			local allowedExternalPart = getAllowedSeatedJointExternalPart(
				cartModel,
				descendant,
				descendant.Part0,
				descendant.Part1,
				options.Stage
			)
			local firstValid = validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part0",
				descendant.Part0,
				allowedExternalPart
			)
			local secondValid = validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part1",
				descendant.Part1,
				allowedExternalPart
			)

			if descendant.Enabled and firstValid and secondValid then
				addRigidConnection(adjacency, descendant.Part0, descendant.Part1)
			end
		elseif descendant:IsA("WeldConstraint") then
			if not descendant.Enabled then
				addFatal(cartModel, fatalErrors, "JOINT_DISABLED", {
					Instance = descendant,
					Message = "WeldConstraint is disabled",
					Expected = "Enabled=true",
					Actual = "Enabled=false",
					Remediation = "Enable the authored weld or remove it.",
				})
			end

			local firstValid = validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part0",
				descendant.Part0,
				nil
			)
			local secondValid = validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part1",
				descendant.Part1,
				nil
			)

			if descendant.Enabled and firstValid and secondValid then
				addRigidConnection(adjacency, descendant.Part0, descendant.Part1)
			end
		elseif descendant:IsA("RigidConstraint") then
			if not descendant.Enabled then
				addFatal(cartModel, fatalErrors, "CONSTRAINT_DISABLED", {
					Instance = descendant,
					Message = "RigidConstraint is disabled",
					Expected = "Enabled=true",
					Actual = "Enabled=false",
					Remediation = "Enable the authored constraint or remove it.",
				})
			end

			local firstValid = validateAttachmentReference(
				cartModel,
				fatalErrors,
				descendant,
				"Attachment0",
				descendant.Attachment0
			)
			local secondValid = validateAttachmentReference(
				cartModel,
				fatalErrors,
				descendant,
				"Attachment1",
				descendant.Attachment1
			)

			if descendant.Enabled and firstValid and secondValid then
				addRigidConnection(
					adjacency,
					getAttachmentPart(descendant.Attachment0),
					getAttachmentPart(descendant.Attachment1)
				)
			end
		elseif descendant:IsA("Constraint") and movementCategory == nil then
			if not descendant.Enabled then
				addFatal(cartModel, fatalErrors, "CONSTRAINT_DISABLED", {
					Instance = descendant,
					Message = string.format("%s is disabled", descendant.ClassName),
					Expected = "Enabled=true",
					Actual = "Enabled=false",
					Remediation = "Enable the authored constraint or remove it.",
				})
			end

			validateAttachmentReference(
				cartModel,
				fatalErrors,
				descendant,
				"Attachment0",
				descendant.Attachment0
			)
			validateAttachmentReference(
				cartModel,
				fatalErrors,
				descendant,
				"Attachment1",
				descendant.Attachment1
			)
		elseif descendant:IsA("NoCollisionConstraint") then
			if not descendant.Enabled then
				addFatal(cartModel, fatalErrors, "CONSTRAINT_DISABLED", {
					Instance = descendant,
					Message = "NoCollisionConstraint is disabled",
					Expected = "Enabled=true",
					Actual = "Enabled=false",
					Remediation = "Enable the authored collision constraint or remove it.",
				})
			end

			validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part0",
				descendant.Part0,
				nil
			)
			validatePartReference(
				cartModel,
				fatalErrors,
				descendant,
				"Part1",
				descendant.Part1,
				nil
			)
		end

		if isManagedStabilityConstraint then
			managedStabilityConstraintCount += 1
			validateManagedStabilityConstraint(cartModel, fatalErrors, descendant :: Torque)
		elseif cartModel:GetAttribute("CartArcadeVersion") == 1
            and descendant.Parent == cartModel:FindFirstChild("Constraints")
            and ((descendant:IsA("VectorForce") and descendant.Name == "ArcadeDrive")
                or (descendant:IsA("AlignOrientation") and descendant.Name == "ArcadeOrientation")) then
            movementConstraintCounts[movementCategory] += 1
            validateMovementConstraintReferences(cartModel,fatalErrors,descendant)
            validateMovementConstraintValues(cartModel,fatalErrors,descendant)
        elseif movementCategory ~= nil then
			movementConstraintCounts[movementCategory] += 1
			addFatal(cartModel, fatalErrors, "MOVEMENT_CONSTRAINT_CONFLICT", {
				Instance = descendant,
				Message = "Pre-authored movement actuator conflicts with the client movement controller",
				Expected = "Movement actuators are created by Phase 1C after driver authorization",
				Actual = descendant.ClassName,
				Remediation = "Remove the pre-authored actuator from the source cart.",
			})
			validateMovementConstraintReferences(cartModel, fatalErrors, descendant)
			validateMovementConstraintValues(cartModel, fatalErrors, descendant)
		end
	end

	if options.Stage ~= "Static" and options.RequireManagedStabilityConstraint == true and cartModel:GetAttribute("CartArcadeVersion") ~= 1 then
		if managedStabilityConstraintCount == 0 then
			addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_MISSING", {
				Instance = cartModel:FindFirstChild("Constraints"),
				Message = "Runtime cart has no managed stability Torque",
				Expected = string.format(
					"One Torque named %s under Constraints",
					MANAGED_STABILITY_CONSTRAINT_NAME
				),
				Actual = "Count=0",
				Remediation = "Initialise Phase 1G stability before enabling driver occupancy.",
			})
		elseif managedStabilityConstraintCount > 1 then
			addFatal(cartModel, fatalErrors, "STABILITY_CONSTRAINT_DUPLICATE", {
				Instance = cartModel:FindFirstChild("Constraints"),
				Message = "Runtime cart has duplicate managed stability Torque constraints",
				Expected = string.format(
					"Exactly one Torque named %s",
					MANAGED_STABILITY_CONSTRAINT_NAME
				),
				Actual = string.format("Count=%d", managedStabilityConstraintCount),
				Remediation = "Keep one stability-owned Torque for the runtime cart.",
			})
		end
	end

    if cartModel:GetAttribute("CartArcadeVersion")==1 then
        for category,count in pairs(movementConstraintCounts) do
            if count~=1 then addFatal(cartModel,fatalErrors,"ARCADE_MOTOR_COUNT_INVALID",{Message="Arcade cart requires one known writer per movement category",Expected="One VectorForce and one AlignOrientation",Actual=category.."="..tostring(count)}) end
        end
    end
	for category, count in movementConstraintCounts do
		if count > 1 then
			addFatal(cartModel, fatalErrors, "MOVEMENT_CONSTRAINT_DUPLICATE", {
				Instance = cartModel:FindFirstChild("Constraints"),
				Message = string.format(
					"Multiple %s movement actuators are pre-authored",
					category
				),
				Expected = "No pre-authored movement actuators",
				Actual = string.format("Count=%d", count),
				Remediation = "Remove duplicate or conflicting movement actuators.",
			})
		end
	end
end

local function getRigidlyConnectedParts(
	root: BasePart,
	adjacency: { [BasePart]: { BasePart } }
): { [BasePart]: boolean }
	local connected: { [BasePart]: boolean } = {
		[root] = true,
	}
	local pending: { BasePart } = { root }

	while #pending > 0 do
		local part = table.remove(pending) :: BasePart

		for _, neighbour in adjacency[part] or {} do
			if connected[neighbour] then
				continue
			end

			connected[neighbour] = true
			table.insert(pending, neighbour)
		end
	end

	return connected
end

local function observePart(part: BasePart): PartObservation
	local physicalProperties = part.CurrentPhysicalProperties

	return {
		CFrame = part.CFrame,
		AssemblyLinearVelocity = part.AssemblyLinearVelocity,
		AssemblyAngularVelocity = part.AssemblyAngularVelocity,
		AssemblyRootPart = part.AssemblyRootPart,
		Mass = part:GetMass(),
		Density = physicalProperties.Density,
		Friction = physicalProperties.Friction,
		Elasticity = physicalProperties.Elasticity,
		FrictionWeight = physicalProperties.FrictionWeight,
		ElasticityWeight = physicalProperties.ElasticityWeight,
		CollisionGroup = part.CollisionGroup,
		Anchored = part.Anchored,
		Massless = part.Massless,
	}
end

local function validatePartPhysicalState(
	cartModel: Model,
	part: BasePart,
	observation: PartObservation,
	options: ValidationOptions,
	fatalErrors: { ValidationIssue },
	warnings: { ValidationIssue }
)
	local isNamedRoot = part == cartModel:FindFirstChild("Root")

	if not isFiniteCFrame(observation.CFrame) then
		addFatal(
			cartModel,
			fatalErrors,
			if isNamedRoot then "ROOT_TRANSFORM_NONFINITE" else "PART_TRANSFORM_NONFINITE",
			{
				Instance = part,
				Message = "Cart part transform contains NaN or infinity",
				Expected = "Finite CFrame",
				Actual = tostring(observation.CFrame),
				Remediation = "Correct the authored transform before spawning the cart.",
			}
		)
	end

	if not isFiniteVector3(observation.AssemblyLinearVelocity) then
		addFatal(cartModel, fatalErrors, "LINEAR_VELOCITY_NONFINITE", {
			Instance = part,
			Message = "Cart part linear velocity contains NaN or infinity",
			Expected = "Finite Vector3",
			Actual = tostring(observation.AssemblyLinearVelocity),
			Remediation = "Remove the malformed physical state before enabling control.",
		})
	end

	if not isFiniteVector3(observation.AssemblyAngularVelocity) then
		addFatal(cartModel, fatalErrors, "ANGULAR_VELOCITY_NONFINITE", {
			Instance = part,
			Message = "Cart part angular velocity contains NaN or infinity",
			Expected = "Finite Vector3",
			Actual = tostring(observation.AssemblyAngularVelocity),
			Remediation = "Remove the malformed physical state before enabling control.",
		})
	end

	local massInvalid = not isFiniteNumber(observation.Mass)
		or observation.Mass < 0
		or ((isNamedRoot or not observation.Massless) and observation.Mass == 0)

	if massInvalid then
		addFatal(
			cartModel,
			fatalErrors,
			if isNamedRoot then "ROOT_MASS_INVALID" else "PART_MASS_INVALID",
			{
				Instance = part,
				Message = "Cart part mass is invalid for its mass policy",
				Expected = if observation.Massless and not isNamedRoot
					then "Mass >= 0 and finite for a massless non-root part"
					else "Mass > 0 and finite",
				Actual = tostring(observation.Mass),
				Remediation = "Correct the part size, material, or physical properties.",
			}
		)
	end

	local properties = {
		Density = observation.Density,
		Friction = observation.Friction,
		Elasticity = observation.Elasticity,
		FrictionWeight = observation.FrictionWeight,
		ElasticityWeight = observation.ElasticityWeight,
	}

	for propertyName, value in properties do
		local limits = PHYSICAL_PROPERTY_LIMITS[propertyName]

		if
			not isFiniteNumber(value)
			or limits == nil
			or value < limits.Minimum
			or value > limits.Maximum
		then
			addFatal(cartModel, fatalErrors, "PHYSICAL_PROPERTY_INVALID", {
				Instance = part,
				Message = string.format("%s is not a valid physical value", propertyName),
				Expected = if limits ~= nil
					then string.format(
						"Finite Roblox physical range %.2f..%.2f",
						limits.Minimum,
						limits.Maximum
					)
					else "Known finite Roblox physical property",
				Actual = tostring(value),
				Remediation = "Correct the part's CustomPhysicalProperties.",
			})
		end
	end

	if options.Stage == "Static" then
		if not isNamedRoot and observation.Anchored then
			addFatal(cartModel, fatalErrors, "PART_ANCHORED", {
				Instance = part,
				Message = "Source cart moving descendant is anchored",
				Expected = "Anchored=false",
				Actual = "Anchored=true",
				Remediation = "Unanchor the authored descendant; only source Root may be anchored.",
			})
		end
	elseif observation.Anchored then
		addFatal(cartModel, fatalErrors, if isNamedRoot then "ROOT_ANCHORED" else "PART_ANCHORED", {
			Instance = part,
			Message = "Runtime cart moving part is anchored",
			Expected = "Anchored=false after spawn preparation",
			Actual = "Anchored=true",
			Remediation = "Fix the asset or lifecycle path that left the runtime part anchored.",
		})
	end

	if not isNamedRoot and not observation.Massless then
		addWarning(cartModel, warnings, "NON_ROOT_PART_HAS_MASS", {
			Instance = part,
			Message = "Non-root cart part contributes physical mass",
			Expected = "Massless=true under the current single-root mass policy",
			Actual = "Massless=false",
			Remediation = "Review the authored mass distribution; do not auto-normalize it.",
		})
	end

	if
		options.Stage ~= "Static"
		and options.ExpectedCollisionGroup ~= nil
		and observation.CollisionGroup ~= options.ExpectedCollisionGroup
		-- Playtest Fixes D4: a cart on the shared Training bay rides in TrainingCarts (set only by
		-- TrainingService while PlaytestFixesV1 TrainPlace is on, which flags the cart first).
		and not (
			observation.CollisionGroup == "TrainingCarts"
			and cartModel:GetAttribute("PlaytestTrainingBay") == true
		)
	then
		addFatal(cartModel, fatalErrors, "COLLISION_GROUP_MISMATCH", {
			Instance = part,
			Message = "Runtime cart part is assigned to the wrong collision group",
			Expected = options.ExpectedCollisionGroup,
			Actual = observation.CollisionGroup,
			Remediation = "Ensure CollisionService assigns every cart BasePart before validation.",
		})
	end
end

local function getExactSeatedCharacters(cartModel: Model): { Model }
	local characters: { Model } = {}
	local seat = SeatContract.GetDriverSeat(cartModel)
	if seat ~= nil then
		for _, joint in seat:GetChildren() do
			if SeatContract.IsCurrentJoint(cartModel, joint) then
				local occupant = seat.Occupant
				local character = if occupant ~= nil then occupant.Parent else nil
				if character ~= nil and character:IsA("Model") then
					table.insert(characters, character)
				end
				break
			end
		end
	end
	return characters
end

local function validateHumanSeats(cartModel: Model, fatalErrors: { ValidationIssue })
	local driver = SeatContract.GetDriverSeat(cartModel)
	if driver == nil then
		addFatal(cartModel, fatalErrors, "DRIVER_SEAT_INVALID", {
			Instance = cartModel,
			Message = "Cart requires exactly one direct VehicleSeat named DriverSeat",
			Expected = "One direct VehicleSeat DriverSeat",
			Actual = "Missing, wrong-class, or ambiguous DriverSeat",
			Remediation = "Restore the existing DriverSeat and remove duplicate seats.",
		})
	end
	for _, descendant in getSortedDescendants(cartModel) do
		if (descendant:IsA("Seat") or descendant:IsA("VehicleSeat")) and descendant ~= driver then
			addFatal(cartModel, fatalErrors, "EXTRA_HUMAN_SEAT", {
				Instance = descendant,
				Message = "Cart contains an additional human seat",
				Expected = "Only the direct DriverSeat VehicleSeat",
				Actual = descendant.ClassName,
				Remediation = "Remove this seat and its dedicated components from the authored cart.",
			})
		end
	end
end

local function validateRuntimeAssembly(
	cartModel: Model,
	root: BasePart,
	_driverSeat: VehicleSeat?,
	parts: { BasePart },
	partObservations: { [BasePart]: PartObservation },
	options: ValidationOptions,
	fatalErrors: { ValidationIssue }
)
	local runtimeObservation = options.RuntimeObservation
	local seatedCharacters = getExactSeatedCharacters(cartModel)
	local function isSeatedCharacterPart(part: BasePart): boolean
		for _, character in seatedCharacters do
			if part:IsDescendantOf(character) then
				return true
			end
		end
		return false
	end
	local getConnectedParts = if runtimeObservation ~= nil
			and runtimeObservation.GetConnectedParts ~= nil
		then runtimeObservation.GetConnectedParts
		else function(assemblyRoot: BasePart): { BasePart }
			return assemblyRoot:GetConnectedParts(true)
		end
	local connectedParts: { BasePart } = {}
	local connectedSuccess, connectedError = pcall(function()
		connectedParts = getConnectedParts(root)
	end)

	if not connectedSuccess then
		addFatal(cartModel, fatalErrors, "CONNECTED_PARTS_QUERY_FAILED", {
			Instance = root,
			Message = "Roblox connected-parts query failed",
			Expected = "Root:GetConnectedParts(true) succeeds",
			Actual = tostring(connectedError),
			Remediation = "Inspect the runtime assembly and joint state.",
		})
	else
		local connectedSet: { [BasePart]: boolean } = {
			[root] = true,
		}

		for _, connectedPart in connectedParts do
			connectedSet[connectedPart] = true

			if
				not connectedPart:IsDescendantOf(cartModel)
				and not isSeatedCharacterPart(connectedPart)
			then
				addFatal(cartModel, fatalErrors, "EXTERNAL_CONNECTED_PART", {
					Instance = root,
					Message = "Runtime cart assembly is physically connected outside the cart",
					Expected = "Only cart parts, or the exact current seated character",
					Actual = connectedPart:GetFullName(),
					Remediation = "Remove the external joint or constraint reference.",
				})
			end
		end

		for _, part in parts do
			if not connectedSet[part] then
				addFatal(cartModel, fatalErrors, "PART_DISCONNECTED_RUNTIME", {
					Instance = part,
					Message = "Required cart part is outside Root's runtime connected set",
					Expected = "Physically connected to named Root",
					Actual = "Not returned by Root:GetConnectedParts(true)",
					Remediation = "Author a valid cart-local rigid connection.",
				})
			end
		end
	end

	local reportedExternalJoints: { [Instance]: boolean } = {}

	for _, part in parts do
		for _, joint in part:GetJoints() do
			if not joint:IsDescendantOf(cartModel) and not reportedExternalJoints[joint] then
				reportedExternalJoints[joint] = true
				addFatal(cartModel, fatalErrors, "JOINT_EXTERNAL_REFERENCE", {
					Instance = part,
					Message = "Runtime cart part is connected by a joint owned outside the cart",
					Expected = "Cart-local joint, including an exact authored seat occupant connection",
					Actual = joint:GetFullName(),
					Remediation = "Remove the external joint and keep cart construction self-contained.",
				})
			end
		end
	end

	local rootAssembly = partObservations[root].AssemblyRootPart

	for _, part in parts do
		local actualAssemblyRoot = partObservations[part].AssemblyRootPart
		local expectedAssemblyRoot = if #seatedCharacters > 0 then rootAssembly else root

		if actualAssemblyRoot ~= expectedAssemblyRoot then
			addFatal(cartModel, fatalErrors, "ASSEMBLY_ROOT_MISMATCH", {
				Instance = part,
				Message = "Required cart part does not use the intended effective assembly root",
				Expected = if expectedAssemblyRoot ~= nil
					then expectedAssemblyRoot:GetFullName()
					else "named Root assembly",
				Actual = if actualAssemblyRoot ~= nil
					then actualAssemblyRoot:GetFullName()
					else "nil",
				Remediation = "Correct mass and rigid connectivity so named Root governs the cart assembly.",
			})
		end
	end

	local assemblyMass = if runtimeObservation ~= nil
			and runtimeObservation.AssemblyMass ~= nil
		then runtimeObservation.AssemblyMass
		else root.AssemblyMass

	if not isFiniteNumber(assemblyMass) or assemblyMass <= 0 then
		addFatal(cartModel, fatalErrors, "TOTAL_MASS_INVALID", {
			Instance = root,
			Message = "Runtime assembly mass is not finite and positive",
			Expected = "AssemblyMass > 0 and finite",
			Actual = tostring(assemblyMass),
			Remediation = "Correct the root and cart physical properties.",
		})
	end

	local canSetNetworkOwnership: boolean
	local ownershipReason: string?
	local ownershipSuccess, ownershipError = pcall(function()
		if runtimeObservation ~= nil and runtimeObservation.CanSetNetworkOwnership ~= nil then
			canSetNetworkOwnership, ownershipReason =
				runtimeObservation.CanSetNetworkOwnership(root)
		else
			canSetNetworkOwnership, ownershipReason = root:CanSetNetworkOwnership()
		end
	end)

	if not ownershipSuccess then
		addFatal(cartModel, fatalErrors, "NETWORK_OWNERSHIP_QUERY_FAILED", {
			Instance = root,
			Message = "Network ownership capability query failed",
			Expected = "Root:CanSetNetworkOwnership() succeeds",
			Actual = tostring(ownershipError),
			Remediation = "Ensure the named Root is live, unanchored, and server-owned.",
		})
	elseif not canSetNetworkOwnership then
		addFatal(cartModel, fatalErrors, "NETWORK_OWNERSHIP_UNAVAILABLE", {
			Instance = root,
			Message = "Named Root cannot receive network ownership",
			Expected = "CanSetNetworkOwnership=true",
			Actual = ownershipReason or "false",
			Remediation = "Remove anchoring or invalid external assembly connections.",
		})
	end
end

local function validateRootPrerequisites(
	cartModel: Model,
	root: BasePart,
	observation: PartObservation,
	fatalErrors: { ValidationIssue }
)
	if cartModel.PrimaryPart ~= root then
		addFatal(cartModel, fatalErrors, "ROOT_NOT_PRIMARY_PART", {
			Instance = root,
			Message = "Cart PrimaryPart is not named Root",
			Expected = root:GetFullName(),
			Actual = if cartModel.PrimaryPart ~= nil
				then cartModel.PrimaryPart:GetFullName()
				else "nil",
			Remediation = "Set the cart Model.PrimaryPart to Root.",
		})
	end

	if observation.Massless then
		addFatal(cartModel, fatalErrors, "ROOT_MASSLESS", {
			Instance = root,
			Message = "Named Root is Massless",
			Expected = "Massless=false",
			Actual = "Massless=true",
			Remediation = "Make Root the cart's meaningful physical mass.",
		})
	end

	local movementAttachment = root:FindFirstChild("MovementAttachment")

	if movementAttachment == nil or not movementAttachment:IsA("Attachment") then
		addFatal(cartModel, fatalErrors, "MOVEMENT_ATTACHMENT_MISSING", {
			Instance = root,
			Message = "Root is missing MovementAttachment",
			Expected = "Direct Attachment named MovementAttachment",
			Actual = if movementAttachment ~= nil then movementAttachment.ClassName else "nil",
			Remediation = "Restore the established movement attachment contract.",
		})
	end

	local orientationAttachment = root:FindFirstChild("OrientationAttachment")

	if orientationAttachment == nil or not orientationAttachment:IsA("Attachment") then
		addFatal(cartModel, fatalErrors, "ORIENTATION_ATTACHMENT_MISSING", {
			Instance = root,
			Message = "Root is missing OrientationAttachment",
			Expected = "Direct Attachment named OrientationAttachment",
			Actual = if orientationAttachment ~= nil
				then orientationAttachment.ClassName
				else "nil",
			Remediation = "Restore the established orientation attachment contract.",
		})
	end
end

function CartAssemblyValidator.ObservePart(part: BasePart): PartObservation
	return observePart(part)
end

function CartAssemblyValidator.IsFiniteNumber(value: number): boolean
	return isFiniteNumber(value)
end

function CartAssemblyValidator.Validate(
	cartModel: Model,
	options: ValidationOptions
): ValidationResult
	local fatalErrors: { ValidationIssue } = {}
	local warnings: { ValidationIssue } = {}
	local cartIdAttribute = cartModel:GetAttribute("CartId")
	local cartId = if type(cartIdAttribute) == "string" and cartIdAttribute ~= ""
		then cartIdAttribute
		else "unknown"

	if cartId == "unknown" then
		addFatal(cartModel, fatalErrors, "CART_ID_MISSING", {
			Instance = cartModel,
			Message = "Cart has no non-empty string CartId",
			Expected = "Server-approved CartId string",
			Actual = tostring(cartIdAttribute),
			Remediation = "Restore the configured CartId on the source or runtime clone.",
		})
	end

	local rootInstance = cartModel:FindFirstChild("Root")

	if rootInstance == nil then
		addFatal(cartModel, fatalErrors, "ROOT_MISSING", {
			Instance = cartModel,
			Message = "Cart has no direct child named Root",
			Expected = "Direct BasePart named Root",
			Actual = "nil",
			Remediation = "Restore the established cart Root contract.",
		})
	elseif not rootInstance:IsA("BasePart") then
		addFatal(cartModel, fatalErrors, "ROOT_INVALID_CLASS", {
			Instance = rootInstance,
			Message = "Cart Root has the wrong class",
			Expected = "BasePart",
			Actual = rootInstance.ClassName,
			Remediation = "Replace Root with the established BasePart contract.",
		})
	end

	if options.Stage ~= "Static" then
		if cartModel.Parent == nil then
			addFatal(cartModel, fatalErrors, "RUNTIME_CART_UNPARENTED", {
				Instance = cartModel,
				Message = "Runtime validation was requested for an unparented cart",
				Expected = "Live runtime cart parented in the DataModel",
				Actual = "Parent=nil",
				Remediation = "Validate only after runtime parenting and placement.",
			})
		end

		if cartModel:GetAttribute("RuntimeCart") ~= true then
			addFatal(cartModel, fatalErrors, "RUNTIME_ATTRIBUTE_MISSING", {
				Instance = cartModel,
				Message = "Runtime cart marker is missing",
				Expected = "RuntimeCart=true assigned by the server",
				Actual = tostring(cartModel:GetAttribute("RuntimeCart")),
				Remediation = "Use the established CartService spawn lifecycle.",
			})
		end
	end

	local parts = getSortedParts(cartModel)
	local adjacency: { [BasePart]: { BasePart } } = {}

	validateHumanSeats(cartModel, fatalErrors)

	for _, part in parts do
		adjacency[part] = {}
	end

	validateAttachmentTransforms(cartModel, fatalErrors)
	validateJointsAndConstraints(cartModel, fatalErrors, adjacency, options)

	local runtimeObservation = options.RuntimeObservation
	local getPartObservation = if runtimeObservation ~= nil
			and runtimeObservation.GetPartObservation ~= nil
		then runtimeObservation.GetPartObservation
		else observePart
	local partObservations: { [BasePart]: PartObservation } = {}
	local totalMeaningfulMass = 0

	for _, part in parts do
		local observation = getPartObservation(part)
		partObservations[part] = observation
		validatePartPhysicalState(cartModel, part, observation, options, fatalErrors, warnings)

		if not observation.Massless and isFiniteNumber(observation.Mass) then
			totalMeaningfulMass += observation.Mass
		end
	end

	if not isFiniteNumber(totalMeaningfulMass) or totalMeaningfulMass <= 0 then
		addFatal(cartModel, fatalErrors, "TOTAL_MEANINGFUL_MASS_INVALID", {
			Instance = cartModel,
			Message = "Cart has no finite positive non-massless physical mass",
			Expected = "Total non-massless part mass > 0 and finite",
			Actual = tostring(totalMeaningfulMass),
			Remediation = "Keep Root non-massless with valid physical properties.",
		})
	end

	if rootInstance ~= nil and rootInstance:IsA("BasePart") then
		local root = rootInstance :: BasePart
		local rootObservation = partObservations[root]

		if rootObservation ~= nil then
			validateRootPrerequisites(cartModel, root, rootObservation, fatalErrors)
		end

		local rigidlyConnected = getRigidlyConnectedParts(root, adjacency)

		for _, part in parts do
			if not rigidlyConnected[part] then
				addFatal(cartModel, fatalErrors, "PART_DISCONNECTED", {
					Instance = part,
					Message = "Required cart BasePart is not rigidly connected to Root",
					Expected = "Enabled cart-local JointInstance, WeldConstraint, or RigidConstraint path",
					Actual = "No rigid path to Root",
					Remediation = "Author an explicit rigid connection; Model parenting is not physical.",
				})
			end
		end

		if options.Stage ~= "Static" and rootObservation ~= nil then
			local driverSeatInstance = cartModel:FindFirstChild("DriverSeat")
			local driverSeat = if driverSeatInstance ~= nil
					and driverSeatInstance:IsA("VehicleSeat")
				then driverSeatInstance
				else nil

			validateRuntimeAssembly(
				cartModel,
				root,
				driverSeat,
				parts,
				partObservations,
				options,
				fatalErrors
			)
		end
	end

	local frozenFatalErrors = freezeIssues(fatalErrors)
	local frozenWarnings = freezeIssues(warnings)
	local result: ValidationResult = {
		IsValid = #frozenFatalErrors == 0,
		Stage = options.Stage,
		CartId = cartId,
		ModelName = cartModel.Name,
		FatalErrors = frozenFatalErrors,
		Warnings = frozenWarnings,
	}

	return table.freeze(result)
end

function CartAssemblyValidator.FormatIssue(issue: ValidationIssue): string
	return string.format(
		"[%s] Path=%s Message=%s Expected=%s Actual=%s Remediation=%s",
		issue.Code,
		issue.InstancePath or "none",
		issue.Message,
		issue.Expected or "none",
		issue.Actual or "none",
		issue.Remediation or "none"
	)
end

function CartAssemblyValidator.AssertValid(
	cartModel: Model,
	options: ValidationOptions
): ValidationResult
	local result = CartAssemblyValidator.Validate(cartModel, options)

	if not result.IsValid then
		local formattedErrors: { string } = {}

		for _, issue in result.FatalErrors do
			table.insert(formattedErrors, CartAssemblyValidator.FormatIssue(issue))
		end

		error(
			string.format(
				"Invalid cart assembly Cart=%s CartId=%s Stage=%s:\n- %s",
				result.ModelName,
				result.CartId,
				result.Stage,
				table.concat(formattedErrors, "\n- ")
			),
			2
		)
	end

	return result
end

return CartAssemblyValidator
