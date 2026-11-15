--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollisionGroups = require(ReplicatedStorage.Shared.Config.CollisionGroups)
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local SeatContract = require(ReplicatedStorage.Shared.Utility.CartSeatContract)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartAssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)

type ValidationIssue = CartAssemblyValidator.ValidationIssue
type ValidationResult = CartAssemblyValidator.ValidationResult
type ValidationStage = CartAssemblyValidator.ValidationStage

export type AssemblyValidationState = "Preparing" | "Valid" | "Invalid" | "Destroying"

export type ControlledImpulseResult = {
	Passed: boolean,
	Code: string,
	Message: string,
	ValidationResult: ValidationResult?,
}

type RuntimeRecord = {
	Cart: Model,
	State: AssemblyValidationState,
	Result: ValidationResult?,
	Revision: number,
	RequireManagedStabilityConstraint: boolean,
	SuppressSignals: boolean,
	TestInProgress: boolean,
	LastWarningSignature: string?,
	Connections: { RBXScriptConnection },
	ObservedInstances: { [Instance]: { RBXScriptConnection } },
	ObservedProperties: { [Instance]: { [string]: any } },
	ValidationCount: number,
	FailedMutationRevision: number?,
}

type FatalHandler = (
	cart: Model,
	result: ValidationResult,
	reason: string,
	revision: number
) -> ()

local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local MAX_INITIAL_LINEAR_SPEED = 0.5
local MAX_INITIAL_ANGULAR_SPEED = 0.25
local IMPULSE_DELTA_SPEED = 2
local IMPULSE_OBSERVATION_FRAMES = 6
local MINIMUM_IMPULSE_DISPLACEMENT = 0.02
local MINIMUM_PART_DISPLACEMENT = 0.01
local RELATIVE_POSITION_TOLERANCE = 0.01
local RELATIVE_AXIS_DOT_TOLERANCE = 0.999

local log = Logger.new("CartAssemblyValidator")
local fatalValidationEvent = Instance.new("BindableEvent")
local CartAssemblyValidationService = {}

local recordsByCart: { [Model]: RuntimeRecord } = {}
local started = false
local fatalHandler: FatalHandler? = nil
local NIL_PROPERTY = table.freeze({})

CartAssemblyValidationService.FatalValidation = fatalValidationEvent.Event

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function setReplicatedState(cart: Model, state: AssemblyValidationState)
	local success, errorMessage = pcall(function()
		cart:SetAttribute(ASSEMBLY_STATE_ATTRIBUTE, state)
	end)

	if not success then
		log:Warn(
			"Could not replicate assembly state Cart=%s CartId=%s State=%s Reason=%s",
			cart.Name,
			tostring(cart:GetAttribute("CartId")),
			state,
			tostring(errorMessage)
		)
	end
end

local function setState(record: RuntimeRecord, state: AssemblyValidationState)
	record.State = state
	setReplicatedState(record.Cart, state)
end

local function logResult(result: ValidationResult, reason: string)
	for _, issue in result.FatalErrors do
		log:Warn(
			"Fatal Cart=%s CartId=%s Stage=%s Code=%s Path=%s Message=%s Expected=%s Actual=%s Remediation=%s Reason=%s",
			result.ModelName,
			result.CartId,
			result.Stage,
			issue.Code,
			issue.InstancePath or "none",
			issue.Message,
			issue.Expected or "none",
			issue.Actual or "none",
			issue.Remediation or "none",
			reason
		)
	end

	if not Environment.IsProduction then
		for _, issue in result.Warnings do
			log:Warn(
				"Warning Cart=%s CartId=%s Stage=%s Code=%s Path=%s Message=%s Expected=%s Actual=%s Remediation=%s Reason=%s",
				result.ModelName,
				result.CartId,
				result.Stage,
				issue.Code,
				issue.InstancePath or "none",
				issue.Message,
				issue.Expected or "none",
				issue.Actual or "none",
				issue.Remediation or "none",
				reason
			)
		end
	end
end

local function getWarningSignature(result: ValidationResult): string
	local warningParts: { string } = {}

	for _, issue in result.Warnings do
		table.insert(
			warningParts,
			string.format("%s:%s:%s", issue.Code, issue.InstancePath or "", issue.Actual or "")
		)
	end

	return table.concat(warningParts, "|")
end

local function publishFatal(
	record: RuntimeRecord,
	result: ValidationResult,
	reason: string,
	deferHandler: boolean?
)
	fatalValidationEvent:Fire(record.Cart, result, reason, record.Revision)

	if fatalHandler ~= nil then
		local handler = fatalHandler
		local revision = record.Revision

		if deferHandler then
			task.defer(function()
				if
					recordsByCart[record.Cart] == record
					and record.State == "Invalid"
					and record.Revision == revision
				then
					handler(record.Cart, result, reason, revision)
				end
			end)
		else
			handler(record.Cart, result, reason, revision)
		end
	end
end

local function validateAndStore(
	record: RuntimeRecord,
	stage: ValidationStage,
	reason: string,
	deferFatalHandler: boolean?
): ValidationResult
	record.ValidationCount += 1
	local previousWarningSignature = record.LastWarningSignature
	local result = CartAssemblyValidator.Validate(record.Cart, {
		Stage = stage,
		ExpectedCollisionGroup = CollisionGroups.Carts,
		RequireManagedStabilityConstraint = record.RequireManagedStabilityConstraint,
	})

	record.Result = result
	record.LastWarningSignature = getWarningSignature(result)

	if result.IsValid then
		setState(record, "Valid")
		log:Debug(
			"Passed runtime assembly validation Cart=%s CartId=%s Stage=%s Descendants=%d Warnings=%d Reason=%s",
			result.ModelName,
			result.CartId,
			stage,
			#record.Cart:GetDescendants(),
			#result.Warnings,
			reason
		)

		if #result.Warnings > 0 and record.LastWarningSignature ~= previousWarningSignature then
			logResult(result, reason)
		end
	else
		setState(record, "Invalid")
		logResult(result, reason)
		publishFatal(record, result, reason, deferFatalHandler)
	end

	return result
end

local function handleObservedMutation(record: RuntimeRecord, reason: string)
	if
		record.SuppressSignals
		or record.State == "Destroying"
		or recordsByCart[record.Cart] ~= record
	then
		return
	end

	record.Revision += 1
	validateAndStore(record, "Runtime", reason)
end

local observeInstance: (record: RuntimeRecord, instance: Instance) -> ()

local function deferObservedMutation(
	record: RuntimeRecord,
	reason: string,
	instanceToObserve: Instance?
)
	if
		record.SuppressSignals
		or record.State == "Destroying"
		or recordsByCart[record.Cart] ~= record
	then
		return
	end

	record.Revision += 1
	local expectedRevision = record.Revision
	setState(record, "Preparing")

	task.defer(function()
		if
			recordsByCart[record.Cart] ~= record
			or record.Revision ~= expectedRevision
			or record.SuppressSignals
			or record.State == "Destroying"
		then
			return
		end

		if instanceToObserve ~= nil and instanceToObserve:IsDescendantOf(record.Cart) then
			observeInstance(record, instanceToObserve)
		end

		validateAndStore(record, "Runtime", reason)
	end)
end

local function isExactCurrentSeatConnection(cart: Model, instance: Instance): boolean
	return SeatContract.IsCurrentJoint(cart, instance)
end

local function shouldObserveAncestry(instance: Instance): boolean
	return instance:IsA("BasePart")
		or instance:IsA("Attachment")
		or instance:IsA("JointInstance")
		or instance:IsA("WeldConstraint")
		or instance:IsA("Constraint")
		or instance:IsA("NoCollisionConstraint")
end

local function observeProperty(record: RuntimeRecord, instance: Instance, propertyName: string)
	local values = record.ObservedProperties[instance]
	local function read(): any
		local value = (instance :: any)[propertyName]
		return if value == nil then NIL_PROPERTY else value
	end
	values[propertyName] = read()
	table.insert(
		record.ObservedInstances[instance],
		instance:GetPropertyChangedSignal(propertyName):Connect(function()
			if
				record.ObservedProperties[instance] ~= values
				or not instance:IsDescendantOf(record.Cart)
			then
				return
			end
			local value = read()
			if values[propertyName] == value then
				return -- Already checked by a synchronous mutation's final validation.
			end
			values[propertyName] = value
			handleObservedMutation(
				record,
				string.format("%s changed for %s", propertyName, instance:GetFullName())
			)
		end)
	)
end

observeInstance = function(record: RuntimeRecord, instance: Instance)
	if record.ObservedInstances[instance] or not instance:IsDescendantOf(record.Cart) then
		return
	end

	if isExactCurrentSeatConnection(record.Cart, instance) then
		return
	end

	local connections: { RBXScriptConnection } = {}
	record.ObservedInstances[instance] = connections
	record.ObservedProperties[instance] = {}

	if instance:IsA("BasePart") then
		observeProperty(record, instance, "Anchored")
		observeProperty(record, instance, "Massless")
		observeProperty(record, instance, "CollisionGroup")
		observeProperty(record, instance, "CustomPhysicalProperties")
		observeProperty(record, instance, "Material")
		observeProperty(record, instance, "RootPriority")
		observeProperty(record, instance, "Size")
	elseif instance:IsA("Attachment") then
		observeProperty(record, instance, "CFrame")
	elseif
		instance:IsA("JointInstance")
		or instance:IsA("WeldConstraint")
		or instance:IsA("NoCollisionConstraint")
	then
		observeProperty(record, instance, "Enabled")
		observeProperty(record, instance, "Part0")
		observeProperty(record, instance, "Part1")
	elseif instance:IsA("Constraint") then
		observeProperty(record, instance, "Name")
		observeProperty(record, instance, "Enabled")
		observeProperty(record, instance, "Attachment0")
		observeProperty(record, instance, "Attachment1")

		if instance:IsA("Torque") then
			observeProperty(record, instance, "RelativeTo")
		end
	end

	-- Own handles with their descendant, not with the lifetime of the whole cart.
	-- AncestryChanged runs after removal, so validation sees the final hierarchy.
	do
		table.insert(
			connections,
			instance.AncestryChanged:Connect(function()
				if record.ObservedInstances[instance] ~= connections then
					return
				end
				if instance.Parent == nil or not instance:IsDescendantOf(record.Cart) then
					record.ObservedInstances[instance] = nil
					record.ObservedProperties[instance] = nil
					disconnectAll(connections)
					if shouldObserveAncestry(instance) then
						handleObservedMutation(
							record,
							string.format("Physical descendant removed: %s", instance.Name)
						)
					end
				end
			end)
		)
	end
end

local function attachObservers(record: RuntimeRecord)
	for _, descendant in record.Cart:GetDescendants() do
		observeInstance(record, descendant)
	end

	table.insert(
		record.Connections,
		record.Cart.DescendantAdded:Connect(function(descendant)
			if
				record.ObservedInstances[descendant] or not descendant:IsDescendantOf(record.Cart)
			then
				return -- A deferred signal may describe an already checked/removed visual.
			end
			local reason = string.format(
				"Physical descendant added: %s (%s)",
				descendant.Name,
				descendant.ClassName
			)
			local possibleSeatConnection = descendant:IsA("JointInstance")
				and SeatContract.SeatForJoint(record.Cart, descendant) ~= nil

			if
				possibleSeatConnection and not isExactCurrentSeatConnection(record.Cart, descendant)
			then
				deferObservedMutation(record, reason, descendant)
			else
				observeInstance(record, descendant)
				handleObservedMutation(record, reason)
			end
		end)
	)
	table.insert(
		record.Connections,
		record.Cart.AncestryChanged:Connect(function()
			if record.Cart.Parent == nil then
				CartAssemblyValidationService:ForgetCart(record.Cart, "cart removed from hierarchy")
			end
		end)
	)
	table.insert(
		record.Connections,
		record.Cart.Destroying:Connect(function()
			CartAssemblyValidationService:ForgetCart(record.Cart, "cart destroying")
		end)
	)
end

local function freezeImpulseResult(
	passed: boolean,
	code: string,
	message: string,
	validationResult: ValidationResult?
): ControlledImpulseResult
	return table.freeze({
		Passed = passed,
		Code = code,
		Message = message,
		ValidationResult = validationResult,
	})
end

local function getSortedParts(cart: Model): { BasePart }
	local parts: { BasePart } = {}

	for _, descendant in cart:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	table.sort(parts, function(first, second)
		return first:GetFullName() < second:GetFullName()
	end)

	return parts
end

local function setAllAnchored(cart: Model, anchored: boolean)
	for _, part in getSortedParts(cart) do
		part.Anchored = anchored
	end
end

local function zeroVelocities(cart: Model)
	for _, part in getSortedParts(cart) do
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

local function restoreAfterImpulse(
	cart: Model,
	originalPivot: CFrame,
	originalCanCollide: { [BasePart]: boolean },
	driverSeat: VehicleSeat,
	originalSeatDisabled: boolean
): (boolean, string?, boolean)
	local skippedOccupiedRestore = false
	local success, errorMessage = pcall(function()
		local root = cart:FindFirstChild("Root")

		assert(root ~= nil and root:IsA("BasePart"), "Cart Root was removed during impulse test")

		root:SetNetworkOwner(nil)

		if driverSeat.Occupant ~= nil then
			for part, canCollide in originalCanCollide do
				if part.Parent ~= nil and part:IsDescendantOf(cart) then
					part.CanCollide = canCollide
				end
			end

			zeroVelocities(cart)
			driverSeat.Disabled = originalSeatDisabled
			skippedOccupiedRestore = true
			return
		end

		setAllAnchored(cart, true)
		zeroVelocities(cart)
		cart:PivotTo(originalPivot)

		for part, canCollide in originalCanCollide do
			if part.Parent ~= nil and part:IsDescendantOf(cart) then
				part.CanCollide = canCollide
			end
		end

		setAllAnchored(cart, false)
		zeroVelocities(cart)
		root:SetNetworkOwner(nil)

		if driverSeat.Parent ~= nil and driverSeat:IsDescendantOf(cart) then
			driverSeat.Disabled = originalSeatDisabled
		end
	end)

	if not success then
		return false, tostring(errorMessage), false
	elseif skippedOccupiedRestore then
		return false,
			"Cart became occupied; pivot restoration was skipped to protect the occupant.",
			true
	end

	return true, nil, false
end

local function relativeTransformsMatch(expected: CFrame, actual: CFrame): boolean
	return (expected.Position - actual.Position).Magnitude <= RELATIVE_POSITION_TOLERANCE
		and expected.RightVector:Dot(actual.RightVector) >= RELATIVE_AXIS_DOT_TOLERANCE
		and expected.UpVector:Dot(actual.UpVector) >= RELATIVE_AXIS_DOT_TOLERANCE
		and expected.LookVector:Dot(actual.LookVector) >= RELATIVE_AXIS_DOT_TOLERANCE
end

local function appendImpulseFailure(
	baseResult: ValidationResult,
	cart: Model,
	code: string,
	message: string
): ValidationResult
	local fatalErrors: { ValidationIssue } = {}

	for _, existingIssue in baseResult.FatalErrors do
		table.insert(fatalErrors, existingIssue)
	end

	local issue: ValidationIssue = table.freeze({
		Code = code,
		Severity = "Fatal",
		InstancePath = string.format("%s.Root", cart.Name),
		Message = message,
		Expected = "Complete cart responds coherently to a small Root impulse",
		Actual = "Controlled impulse proof failed",
		Remediation = "Inspect anchoring, connectivity, mass, and effective assembly root.",
	})
	table.insert(fatalErrors, issue)
	table.sort(fatalErrors, function(first, second)
		if first.Code == second.Code then
			return (first.InstancePath or "") < (second.InstancePath or "")
		end

		return first.Code < second.Code
	end)

	return table.freeze({
		IsValid = false,
		Stage = baseResult.Stage,
		CartId = baseResult.CartId,
		ModelName = baseResult.ModelName,
		FatalErrors = table.freeze(fatalErrors),
		Warnings = baseResult.Warnings,
	})
end

function CartAssemblyValidationService:RegisterCart(
	cart: Model
): (boolean, ValidationResult?, string?)
	if recordsByCart[cart] ~= nil then
		return false, recordsByCart[cart].Result, "cart already has an assembly validation record"
	end

	local record: RuntimeRecord = {
		Cart = cart,
		State = "Preparing",
		Result = nil,
		Revision = 1,
		RequireManagedStabilityConstraint = false,
		SuppressSignals = false,
		TestInProgress = false,
		LastWarningSignature = nil,
		Connections = {},
		ObservedInstances = {},
		ObservedProperties = {},
		ValidationCount = 0,
		FailedMutationRevision = nil,
	}
	recordsByCart[cart] = record
	setState(record, "Preparing")
	attachObservers(record)

	local result = validateAndStore(record, "Runtime", "runtime cart registration")

	return result.IsValid, result, if result.IsValid then nil else "fatal assembly validation"
end

function CartAssemblyValidationService:GetState(cart: Model): AssemblyValidationState?
	local record = recordsByCart[cart]

	return if record ~= nil then record.State else nil
end

-- A deferred owner callback must not destroy a successfully restored revision.
function CartAssemblyValidationService:IsCurrentFailure(cart: Model,result: ValidationResult,revision: number): boolean
	local record=recordsByCart[cart]
	return record~=nil and record.State=="Invalid" and record.Revision==revision and record.Result==result
end

function CartAssemblyValidationService:GetResult(cart: Model): ValidationResult?
	local record = recordsByCart[cart]

	return if record ~= nil then record.Result else nil
end

function CartAssemblyValidationService:IsCartValid(cart: Model): boolean
	local record = recordsByCart[cart]

	return record ~= nil
		and record.State == "Valid"
		and record.Result ~= nil
		and record.Result.IsValid
end

function CartAssemblyValidationService:SetFatalHandler(handler: FatalHandler)
	assert(fatalHandler == nil, "Cart assembly fatal handler is already registered")
	fatalHandler = handler
end

function CartAssemblyValidationService:RevalidateCart(
	cart: Model,
	reason: string
): (boolean, ValidationResult?, string?)
	local record = recordsByCart[cart]

	if record == nil then
		return false, nil, "cart has no assembly validation record"
	end

	if record.State == "Destroying" or record.SuppressSignals or record.TestInProgress then
		return false, record.Result, "cart assembly is unavailable for validation"
	end

	record.Revision += 1
	local result = validateAndStore(record, "Runtime", reason, true)

	return result.IsValid, result, if result.IsValid then nil else "fatal assembly validation"
end

function CartAssemblyValidationService:BeginMutation(
	cart: Model,
	reason: string,
	failedMutationRevision: number?
): (boolean, number?, string?)
	local record = recordsByCart[cart]

	if record == nil then
		return false, nil, "cart has no assembly validation record"
	end

	local retryFailedMutation=failedMutationRevision~=nil and record.State=="Invalid" and record.Revision==failedMutationRevision and record.FailedMutationRevision==failedMutationRevision
	if record.TestInProgress or (if failedMutationRevision~=nil then not retryFailedMutation else record.State~="Valid") then
		return false, nil, "cart is unavailable for mutation"
	end

	record.FailedMutationRevision=nil
	record.Revision += 1
	record.SuppressSignals = true
	setState(record, "Preparing")

	log:Debug(
		"Assembly mutation started Cart=%s CartId=%s Revision=%d Reason=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		record.Revision,
		reason
	)

	return true, record.Revision, nil
end

function CartAssemblyValidationService:CompleteMutation(
	cart: Model,
	revision: number,
	stage: ValidationStage,
	reason: string,
	requireManagedStabilityConstraint: boolean?
): (boolean, ValidationResult?, string?)
	local record = recordsByCart[cart]

	if record == nil or record.Revision ~= revision or record.State == "Destroying" then
		return false, nil, "stale or missing assembly mutation record"
	end

	if requireManagedStabilityConstraint ~= nil then
		record.RequireManagedStabilityConstraint = requireManagedStabilityConstraint
	end

	-- Reconcile once at the synchronous boundary, including Studio's Deferred
	-- signals. Queued add/property notifications then observe the validated values
	-- instead of rescanning the same finished assembly once per descendant.
	for instance, connections in record.ObservedInstances do
		if not instance:IsDescendantOf(cart) then
			disconnectAll(connections)
			record.ObservedInstances[instance] = nil
			record.ObservedProperties[instance] = nil
		else
			for propertyName in record.ObservedProperties[instance] do
				local value = (instance :: any)[propertyName]
				record.ObservedProperties[instance][propertyName] = if value == nil
					then NIL_PROPERTY
					else value
			end
		end
	end
	for _, descendant in cart:GetDescendants() do
		observeInstance(record, descendant)
	end
	record.SuppressSignals = false
	local result = validateAndStore(record, stage, reason)
	record.FailedMutationRevision=if result.IsValid then nil else revision

	return result.IsValid, result, if result.IsValid then nil else "fatal assembly validation"
end

function CartAssemblyValidationService:ForgetCart(cart: Model, reason: string?): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	record.Revision += 1
	record.SuppressSignals = true
	setState(record, "Destroying")
	recordsByCart[cart] = nil
	disconnectAll(record.Connections)
	for _, connections in record.ObservedInstances do
		disconnectAll(connections)
	end
	table.clear(record.ObservedInstances)
	table.clear(record.ObservedProperties)

	log:Debug(
		"Forgot assembly validation Cart=%s CartId=%s Reason=%s",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		reason or "unspecified"
	)

	return true
end

function CartAssemblyValidationService:RunControlledImpulseTest(
	cart: Model
): ControlledImpulseResult
	if
		Environment.Name ~= "Development"
		or not Environment.EnableDebugTools
		or not RunService:IsStudio()
	then
		return freezeImpulseResult(
			false,
			"IMPULSE_NOT_AVAILABLE",
			"Controlled cart impulse validation is Development Studio only.",
			nil
		)
	end

	local record = recordsByCart[cart]

	if
		record == nil
		or record.State ~= "Valid"
		or record.Result == nil
		or not record.Result.IsValid
	then
		return freezeImpulseResult(
			false,
			"IMPULSE_CART_INVALID",
			"Cart must have a current valid runtime assembly result.",
			if record ~= nil then record.Result else nil
		)
	end

	if record.TestInProgress then
		return freezeImpulseResult(
			false,
			"IMPULSE_ALREADY_RUNNING",
			"A controlled impulse test is already running for this cart.",
			record.Result
		)
	end

	local rootInstance = cart:FindFirstChild("Root")
	local seatInstance = cart:FindFirstChild("DriverSeat")

	if
		cart.Parent == nil
		or rootInstance == nil
		or not rootInstance:IsA("BasePart")
		or seatInstance == nil
		or not seatInstance:IsA("VehicleSeat")
	then
		return freezeImpulseResult(
			false,
			"IMPULSE_CART_INVALID",
			"Cart physical contract is no longer live.",
			record.Result
		)
	end

	local root = rootInstance :: BasePart
	local seat = seatInstance :: VehicleSeat

	if seat.Occupant ~= nil or cart:GetAttribute("ActiveDriverUserId") ~= 0 then
		return freezeImpulseResult(
			false,
			"IMPULSE_CART_OCCUPIED",
			"Controlled impulse cannot run while the cart has an occupant or active driver.",
			record.Result
		)
	end

	local networkOwner: Player? = nil
	local ownershipSuccess, ownershipError = pcall(function()
		networkOwner = root:GetNetworkOwner()
	end)

	if not ownershipSuccess or networkOwner ~= nil then
		return freezeImpulseResult(
			false,
			"IMPULSE_NETWORK_OWNERSHIP_INVALID",
			if ownershipSuccess
				then "Controlled impulse requires server network ownership."
				else string.format(
					"Could not query network ownership: %s",
					tostring(ownershipError)
				),
			record.Result
		)
	end

	if
		root.AssemblyLinearVelocity.Magnitude > MAX_INITIAL_LINEAR_SPEED
		or root.AssemblyAngularVelocity.Magnitude > MAX_INITIAL_ANGULAR_SPEED
	then
		return freezeImpulseResult(
			false,
			"IMPULSE_CART_MOVING",
			"Controlled impulse requires a nearly stationary cart.",
			record.Result
		)
	end

	record.TestInProgress = true
	record.Revision += 1
	local testRevision = record.Revision
	record.SuppressSignals = true
	setState(record, "Preparing")

	local originalPivot = cart:GetPivot()
	local originalSeatDisabled = seat.Disabled
	local initialRootPosition = root.Position
	local initialPartPositions: { [BasePart]: Vector3 } = {}
	local initialRelativeTransforms: { [BasePart]: CFrame } = {}
	local originalCanCollide: { [BasePart]: boolean } = {}
	local parts = getSortedParts(cart)

	for _, part in parts do
		initialPartPositions[part] = part.Position
		initialRelativeTransforms[part] = root.CFrame:ToObjectSpace(part.CFrame)
		originalCanCollide[part] = part.CanCollide
	end

	local horizontalLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local impulseDirection = if horizontalLook.Magnitude > 0.001
		then horizontalLook.Unit
		else Vector3.xAxis
	local failureCode: string? = nil
	local failureMessage: string? = nil
	local isolated, isolationError = pcall(function()
		seat.Disabled = true
		root:SetNetworkOwner(nil)

		for _, part in parts do
			part.CanCollide = false
		end

		zeroVelocities(cart)
	end)

	if not isolated then
		failureCode = "IMPULSE_ISOLATION_FAILED"
		failureMessage = tostring(isolationError)
	elseif seat.Occupant ~= nil or cart:GetAttribute("ActiveDriverUserId") ~= 0 then
		failureCode = "IMPULSE_CANCELLED"
		failureMessage = "Cart occupancy changed before the diagnostic isolation lock completed."
	end

	local applied = false
	local applyError: unknown = nil

	if failureCode == nil then
		applied, applyError = pcall(function()
			root:ApplyImpulse(impulseDirection * root.AssemblyMass * IMPULSE_DELTA_SPEED)
		end)
	end

	if failureCode == nil and not applied then
		failureCode = "IMPULSE_APPLICATION_FAILED"
		failureMessage = tostring(applyError)
	elseif failureCode == nil then
		for _ = 1, IMPULSE_OBSERVATION_FRAMES do
			RunService.Heartbeat:Wait()

			if
				recordsByCart[cart] ~= record
				or record.Revision ~= testRevision
				or cart.Parent == nil
			then
				failureCode = "IMPULSE_CANCELLED"
				failureMessage = "Cart was destroyed, replaced, or invalidated during the test."
				break
			end

			if seat.Occupant ~= nil or cart:GetAttribute("ActiveDriverUserId") ~= 0 then
				failureCode = "IMPULSE_CANCELLED"
				failureMessage = "Cart occupancy changed during the controlled test."
				break
			end
		end
	end

	local observedRootDisplacement = if root.Parent ~= nil
		then (root.Position - initialRootPosition):Dot(impulseDirection)
		else 0

	if failureCode == nil and observedRootDisplacement < MINIMUM_IMPULSE_DISPLACEMENT then
		failureCode = "IMPULSE_ROOT_NO_RESPONSE"
		failureMessage = "Named Root did not move by the minimum diagnostic displacement."
	end

	if failureCode == nil then
		for _, part in parts do
			if part.Parent == nil or not part:IsDescendantOf(cart) then
				failureCode = "IMPULSE_PART_SEPARATED"
				failureMessage = string.format("%s left the cart during the impulse.", part.Name)
				break
			end

			local partDisplacement = (part.Position - initialPartPositions[part]):Dot(
				impulseDirection
			)

			if partDisplacement < MINIMUM_PART_DISPLACEMENT then
				failureCode = "IMPULSE_PART_NO_RESPONSE"
				failureMessage = string.format("%s did not follow the Root impulse.", part.Name)
				break
			end

			local currentRelative = root.CFrame:ToObjectSpace(part.CFrame)

			if not relativeTransformsMatch(initialRelativeTransforms[part], currentRelative) then
				failureCode = "IMPULSE_PART_SEPARATED"
				failureMessage =
					string.format("%s changed its rigid transform relative to Root.", part.Name)
				break
			end
		end
	end

	local restored, restoreError, occupiedRestoreSkipped =
		restoreAfterImpulse(cart, originalPivot, originalCanCollide, seat, originalSeatDisabled)

	if not restored and failureCode == nil then
		failureCode = if occupiedRestoreSkipped
			then "IMPULSE_CANCELLED"
			else "IMPULSE_CLEANUP_FAILED"
		failureMessage = restoreError or "Unknown controlled impulse cleanup error."
	end

	if recordsByCart[cart] ~= record or record.Revision ~= testRevision then
		return freezeImpulseResult(
			false,
			"IMPULSE_CANCELLED",
			failureMessage or "Cart validation record changed before cleanup completed.",
			nil
		)
	end

	record.TestInProgress = false
	record.SuppressSignals = false
	local finalResult = validateAndStore(record, "Runtime", "controlled impulse cleanup")

	if not finalResult.IsValid then
		return freezeImpulseResult(
			false,
			"IMPULSE_POST_VALIDATION_FAILED",
			"Cart failed runtime validation after controlled impulse cleanup.",
			finalResult
		)
	end

	if failureCode ~= nil and failureCode ~= "IMPULSE_CANCELLED" then
		local failedResult =
			appendImpulseFailure(finalResult, cart, failureCode, failureMessage or failureCode)
		record.Result = failedResult
		setState(record, "Invalid")
		logResult(failedResult, "controlled impulse failure")
		publishFatal(record, failedResult, "controlled impulse failure")

		return freezeImpulseResult(
			false,
			failureCode,
			failureMessage or "Controlled impulse proof failed.",
			failedResult
		)
	elseif failureCode == "IMPULSE_CANCELLED" then
		return freezeImpulseResult(
			false,
			failureCode,
			failureMessage or "Controlled impulse was cancelled.",
			finalResult
		)
	end

	log:Info(
		"Controlled impulse passed Cart=%s CartId=%s Displacement=%.3f Parts=%d",
		cart.Name,
		tostring(cart:GetAttribute("CartId")),
		observedRootDisplacement,
		#parts
	)

	return freezeImpulseResult(
		true,
		"IMPULSE_PASSED",
		"Named Root and every required cart part responded coherently; test state was restored.",
		finalResult
	)
end

function CartAssemblyValidationService:Start()
	if started then
		return
	end

	started = true
	log:Info("Cart assembly validation service ready")
end

function CartAssemblyValidationService:GetDiagnostics()
	local recordCount = 0
	local recordConnectionCount = 0
	local retainedConnectionObjectCount = 0
	local observedInstanceCount = 0
	local retainedObservedInstanceCount = 0
	local validationCount = 0

	for _, record in recordsByCart do
		recordCount += 1
		validationCount += record.ValidationCount
		retainedConnectionObjectCount += #record.Connections

		for _, connection in record.Connections do
			if connection.Connected then
				recordConnectionCount += 1
			end
		end

		for instance, connections in record.ObservedInstances do
			retainedObservedInstanceCount += 1
			retainedConnectionObjectCount += #connections
			for _, connection in connections do
				if connection.Connected then
					recordConnectionCount += 1
				end
			end

			if instance.Parent ~= nil and instance:IsDescendantOf(record.Cart) then
				observedInstanceCount += 1
			end
		end
	end

	return table.freeze({
		Started = started,
		RecordCount = recordCount,
		RecordConnectionCount = recordConnectionCount,
		RetainedConnectionObjectCount = retainedConnectionObjectCount,
		ObservedInstanceCount = observedInstanceCount,
		RetainedObservedInstanceCount = retainedObservedInstanceCount,
		ValidationCount = validationCount,
	})
end

return CartAssemblyValidationService
