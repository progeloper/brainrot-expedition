--!strict
local SeatContract = require(script.Parent.Parent.Utility.CartSeatContract)

export type ValidationResult = {
	IsValid: boolean,
	Errors: { string },
	Warnings: { string },
}

local CartAssetValidator = {}

type RequiredChildren = {
	[string]: string,
}

local REQUIRED_DIRECT_CHILDREN: RequiredChildren = {
	Root = "BasePart",
	DriverSeat = "VehicleSeat",
	CameraTarget = "BasePart",
	CargoSlots = "Folder",
	FormationSlots = "Folder",
	Visual = "Model",
	Constraints = "Folder",
}

local REQUIRED_CARGO_SLOT_COUNT = 3
local REQUIRED_FORMATION_SLOT_COUNT = 6

local function finiteVector(vector: Vector3): boolean
	return vector.X == vector.X
		and math.abs(vector.X) < math.huge
		and vector.Y == vector.Y
		and math.abs(vector.Y) < math.huge
		and vector.Z == vector.Z
		and math.abs(vector.Z) < math.huge
end

-- Resolve one authored position by stable ID without implying that the position
-- is currently unlocked. Entitlement remains the capacity resolver's concern.
function CartAssetValidator.GetCargoSlot(cart: Model, index: number): (any?, string?)
	if index < 1 or index % 1 ~= 0 then
		return nil, "Invalid cargo slot index"
	end
	local folder = cart:FindFirstChild("CargoSlots")
	if not folder or not folder:IsA("Folder") then
		return nil, "Invalid CargoSlots folder"
	end
	local id = "Slot" .. index
	local slot, count = nil, 0
	for _, child in folder:GetChildren() do
		if child.Name == id then
			slot, count = child, count + 1
		end
	end
	if count ~= 1 or not slot or not slot:IsA("BasePart") then
		return nil, id .. ": expected one BasePart anchor"
	end
	local attachment, anchors = nil, 0
	for _, child in slot:GetChildren() do
		if child.Name == "CargoAttachment" then
			attachment, anchors = child, anchors + 1
		end
	end
	if anchors ~= 1 or not attachment or not attachment:IsA("Attachment") then
		return nil, id .. ": expected one CargoAttachment"
	end
	return { Id = id, Index = index, Part = slot, Attachment = attachment }, nil
end

-- One ordered physical slot contract for cargo custody and local presentation.
-- Fail closed on an incomplete/ambiguous map; capacity is never silently reduced.
function CartAssetValidator.GetCargoSlotMap(cart: Model, capacity: number): ({ any }?, string?)
	local folder = cart:FindFirstChild("CargoSlots")
	if not folder or not folder:IsA("Folder") or capacity < 1 or capacity % 1 ~= 0 then
		return nil, "Invalid CargoSlots folder/capacity"
	end
	local result = {}
	for index = 1, capacity do
		local slot, reason = CartAssetValidator.GetCargoSlot(cart, index)
		if slot == nil then
			return nil, reason
		end
		table.insert(result, slot)
	end
	return result, nil
end

-- Validate the exact positions required by an effective capacity. Extra authored
-- anchors are intentionally ignored: their presence never unlocks entitlement.
function CartAssetValidator.ValidateCargoLayout(
	cart: Model,
	requiredCapacity: number,
	minimumSeparation: number?
): any
	local map, reason = CartAssetValidator.GetCargoSlotMap(cart, requiredCapacity)
	if map == nil then
		return table.freeze({
			status = "LayoutNotReady",
			requiredCapacity = requiredCapacity,
			positions = table.freeze({}),
			errors = table.freeze({ reason or "Invalid cargo slot map" }),
		})
	end
	local errors = {}
	local separation = minimumSeparation or 0.25
	if type(separation) ~= "number" or separation ~= separation or separation < 0 then
		table.insert(errors, "Invalid cargo slot separation")
		separation = 0.25
	end
	for index, slot in map do
		local position = slot.Attachment.WorldPosition
		if not finiteVector(position) then
			table.insert(errors, slot.Id .. ": non-finite CargoAttachment position")
		end
		for priorIndex = 1, index - 1 do
			local prior = map[priorIndex]
			if (position - prior.Attachment.WorldPosition).Magnitude < separation then
				table.insert(errors, slot.Id .. " overlaps " .. prior.Id)
			end
		end
	end
	return table.freeze({
		status = if #errors == 0 then "Ready" else "LayoutNotReady",
		requiredCapacity = requiredCapacity,
		positions = table.freeze(map),
		errors = table.freeze(errors),
	})
end

local function addConnection(
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

local function getAttachmentPart(attachment: Attachment?): BasePart?
	local parent = if attachment ~= nil then attachment.Parent else nil

	return if parent ~= nil and parent:IsA("BasePart") then parent else nil
end

local function getJointParts(joint: JointInstance): (BasePart?, BasePart?)
	if joint.Enabled then
		return joint.Part0, joint.Part1
	end

	return nil, nil
end

local function getWeldConstraintParts(weld: WeldConstraint): (BasePart?, BasePart?)
	if weld.Enabled then
		return weld.Part0, weld.Part1
	end

	return nil, nil
end

local function getRigidlyConnectedParts(cartModel: Model, root: BasePart): { [BasePart]: boolean }
	local adjacency: { [BasePart]: { BasePart } } = {}

	for _, descendant in cartModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			adjacency[descendant] = {}
		end
	end

	for _, descendant in cartModel:GetDescendants() do
		local first: BasePart? = nil
		local second: BasePart? = nil

		if descendant:IsA("JointInstance") then
			first, second = getJointParts(descendant)
		elseif descendant:IsA("WeldConstraint") then
			first, second = getWeldConstraintParts(descendant)
		elseif descendant:IsA("RigidConstraint") then
			if descendant.Enabled then
				first = getAttachmentPart(descendant.Attachment0)
				second = getAttachmentPart(descendant.Attachment1)
			end
		end

		addConnection(adjacency, first, second)
	end

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

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

local function addWarning(warnings: { string }, message: string)
	table.insert(warnings, message)
end

local function validateDirectChildren(cartModel: Model, errors: { string })
	for childName: string, expectedClass: string in REQUIRED_DIRECT_CHILDREN do
		local child = cartModel:FindFirstChild(childName)

		if child == nil then
			addError(errors, string.format("Missing required child %s", childName))
			continue
		end

		if not child:IsA(expectedClass) then
			addError(
				errors,
				string.format("%s must be a %s, got %s", childName, expectedClass, child.ClassName)
			)
		end
	end
end

local function validateHumanSeats(cartModel: Model, errors: { string })
	local driver = SeatContract.GetDriverSeat(cartModel)
	if driver == nil then
		addError(errors, "Cart requires exactly one direct VehicleSeat named DriverSeat")
	end
	for _, descendant in cartModel:GetDescendants() do
		if (descendant:IsA("Seat") or descendant:IsA("VehicleSeat")) and descendant ~= driver then
			addError(
				errors,
				string.format("%s is an additional human seat", descendant:GetFullName())
			)
		end
	end
end

local function validateSlotFolder(
	folder: Folder?,
	slotPrefix: string,
	requiredCount: number,
	requiredAttachmentName: string,
	errors: { string }
)
	if folder == nil then
		return
	end

	for index = 1, requiredCount do
		local slotName = string.format("%s%d", slotPrefix, index)
		local slot = folder:FindFirstChild(slotName)

		if slot == nil then
			addError(errors, string.format("%s is missing %s", folder.Name, slotName))
			continue
		end

		if not slot:IsA("BasePart") then
			addError(errors, string.format("%s.%s must be a BasePart", folder.Name, slotName))
			continue
		end

		local attachment = slot:FindFirstChild(requiredAttachmentName)

		if attachment == nil or not attachment:IsA("Attachment") then
			addError(
				errors,
				string.format(
					"%s.%s requires Attachment %s",
					folder.Name,
					slotName,
					requiredAttachmentName
				)
			)
		end
	end
end

local function validateParts(
	cartModel: Model,
	root: BasePart?,
	errors: { string },
	warnings: { string }
)
	local connectedAssembly: { [BasePart]: boolean } = {}

	if root ~= nil then
		connectedAssembly = getRigidlyConnectedParts(cartModel, root)
	end

	for _, descendant in cartModel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if root ~= nil and not connectedAssembly[descendant] then
			addError(
				errors,
				string.format("%s is not connected to Root's assembly", descendant:GetFullName())
			)
		end

		if descendant ~= root and descendant.Anchored then
			addError(errors, string.format("%s must not be anchored", descendant:GetFullName()))
		end

		if descendant ~= root and not descendant.Massless then
			addWarning(
				warnings,
				string.format("%s should normally be Massless", descendant:GetFullName())
			)
		end
	end
end

function CartAssetValidator.Validate(cartModel: Model): ValidationResult
	local errors: { string } = {}
	local warnings: { string } = {}

	validateDirectChildren(cartModel, errors)
	validateHumanSeats(cartModel, errors)

	local rootInstance = cartModel:FindFirstChild("Root")
	local root: BasePart? = nil

	if rootInstance and rootInstance:IsA("BasePart") then
		root = rootInstance

		if cartModel.PrimaryPart ~= rootInstance then
			addError(errors, "Cart PrimaryPart must be Root")
		end

		if rootInstance.Massless then
			addError(errors, "Root must not be Massless")
		end

		local movementAttachment = rootInstance:FindFirstChild("MovementAttachment")

		if movementAttachment == nil or not movementAttachment:IsA("Attachment") then
			addError(errors, "Root requires Attachment MovementAttachment")
		end

		local orientationAttachment = rootInstance:FindFirstChild("OrientationAttachment")

		if orientationAttachment == nil or not orientationAttachment:IsA("Attachment") then
			addError(errors, "Root requires Attachment OrientationAttachment")
		end
	end

	local cartId = cartModel:GetAttribute("CartId")

	if type(cartId) ~= "string" or cartId == "" then
		addError(errors, "Cart model requires non-empty CartId attribute")
	end

	local cargoSlotsInstance = cartModel:FindFirstChild("CargoSlots")

	local cargoSlots: Folder? = nil

	if cargoSlotsInstance and cargoSlotsInstance:IsA("Folder") then
		cargoSlots = cargoSlotsInstance
	end

	validateSlotFolder(cargoSlots, "Slot", REQUIRED_CARGO_SLOT_COUNT, "CargoAttachment", errors)

	local formationSlotsInstance = cartModel:FindFirstChild("FormationSlots")

	local formationSlots: Folder? = nil

	if formationSlotsInstance and formationSlotsInstance:IsA("Folder") then
		formationSlots = formationSlotsInstance
	end

	validateSlotFolder(
		formationSlots,
		"Slot",
		REQUIRED_FORMATION_SLOT_COUNT,
		"FormationAttachment",
		errors
	)

	validateParts(cartModel, root, errors, warnings)

	return {
		IsValid = #errors == 0,
		Errors = errors,
		Warnings = warnings,
	}
end

function CartAssetValidator.AssertValid(cartModel: Model)
	local result = CartAssetValidator.Validate(cartModel)

	for _, warningMessage in result.Warnings do
		warn(string.format("[CartAssetValidator] %s", warningMessage))
	end

	if not result.IsValid then
		error("Invalid cart asset:\n- " .. table.concat(result.Errors, "\n- "), 2)
	end
end

return CartAssetValidator
