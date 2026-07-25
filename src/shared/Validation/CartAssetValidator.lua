--!strict

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
	HarpoonOrigin = "BasePart",
	CargoSlots = "Folder",
	FormationSlots = "Folder",
	Visual = "Model",
	Constraints = "Folder",
}

local REQUIRED_CARGO_SLOT_COUNT = 3
local REQUIRED_FORMATION_SLOT_COUNT = 6

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
	for _, descendant in cartModel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
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
