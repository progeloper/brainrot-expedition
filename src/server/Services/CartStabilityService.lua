--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)
local CartStabilityMath = require(ReplicatedStorage.Shared.Utility.CartStabilityMath)
local CartStabilityProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartStabilityProfileResolver)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local CartAssemblyValidationService = require(script.Parent.CartAssemblyValidationService)
local CartOccupantService = require(script.Parent.CartOccupantService)
local CartTerrainService = require(script.Parent.CartTerrainService)

type EffectiveStabilityProfile = CartStabilityTypes.EffectiveStabilityProfile
type StabilityStepResult = CartStabilityTypes.StabilityStepResult

export type StabilityStateSnapshot = {
	Cart: Model,
	Root: BasePart,
	Profile: EffectiveStabilityProfile,
	IsValid: boolean,
	Suspended: boolean,
	Driving: boolean,
	ActiveDriverUserId: number,
	Revision: number,
	Heading: Vector3,
	AppliedTorque: Vector3,
	Mode: string,
	RollAngle: number,
	PitchAngle: number,
	TiltAngle: number,
	RollAngularVelocity: number,
	PitchAngularVelocity: number,
	YawAngularVelocity: number,
	CorrectionStrength: number,
	SevereTilt: boolean,
}

type RuntimeRecord = {
	Cart: Model,
	Root: BasePart,
	OrientationAttachment: Attachment,
	Constraints: Folder,
	TorqueConstraint: Torque,
	Profile: EffectiveStabilityProfile,
	Invalid: boolean,
	Cleaning: boolean,
	Suspended: boolean,
	Driving: boolean,
	ActiveDriverUserId: number,
	Revision: number,
	LastDriverRevision: number,
	PreviousHeading: Vector3,
	PreviousTorque: Vector3,
	Mode: string,
	RollAngle: number,
	PitchAngle: number,
	TiltAngle: number,
	RollAngularVelocity: number,
	PitchAngularVelocity: number,
	YawAngularVelocity: number,
	CorrectionStrength: number,
	SevereTilt: boolean,
	LastSevereLogTime: number,
	Connections: { RBXScriptConnection },
}

type FatalHandler = (cart: Model, reason: string, revision: number) -> ()

local TORQUE_NAME = "CartStabilityTorque"
local SEVERE_LOG_INTERVAL_SECONDS = 2

local log = Logger.new("CartStabilityService")
local CartStabilityService = {}

local recordsByCart: { [Model]: RuntimeRecord } = {}
local preSimulationConnection: RBXScriptConnection? = nil
local driverChangedConnection: RBXScriptConnection? = nil
local fatalHandler: FatalHandler? = nil
local started = false

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function setConstraintTorque(record: RuntimeRecord, torque: Vector3): boolean
	if
		record.TorqueConstraint.Parent == nil
		or not record.TorqueConstraint:IsDescendantOf(record.Cart)
	then
		return false
	end

	local success = pcall(function()
		record.TorqueConstraint.Torque = torque
	end)

	if success then
		record.PreviousTorque = torque
	end

	return success
end

local function zeroConstraintTorque(record: RuntimeRecord, forceWrite: boolean?)
	local shouldWrite = forceWrite == true or record.PreviousTorque ~= Vector3.zero
	record.PreviousTorque = Vector3.zero

	if
		shouldWrite
		and record.TorqueConstraint.Parent ~= nil
		and record.TorqueConstraint:IsDescendantOf(record.Cart)
	then
		pcall(function()
			record.TorqueConstraint.Torque = Vector3.zero
		end)
	end
end

local function resolveHeading(root: BasePart, desiredUp: Vector3, fallback: Vector3?): Vector3
	local _, heading =
		CartStabilityMath.BuildHeadingFrame(root.CFrame.LookVector, desiredUp, fallback)

	return heading
end

local function formatContext(record: RuntimeRecord): string
	return string.format(
		"Cart=%s CartId=%s Revision=%d",
		record.Cart.Name,
		tostring(record.Cart:GetAttribute("CartId")),
		record.Revision
	)
end

local function invokeFatalHandler(record: RuntimeRecord, reason: string)
	local handler = fatalHandler

	if handler == nil then
		return
	end

	local cart = record.Cart
	local revision = record.Revision
	local success, errorMessage = pcall(function()
		handler(cart, reason, revision)
	end)

	if not success then
		log:Warn(
			"Fatal stability handler failed %s Error=%s",
			formatContext(record),
			tostring(errorMessage)
		)
	end
end

local function cleanupRecord(record: RuntimeRecord, reason: string, destroyHelper: boolean): boolean
	if recordsByCart[record.Cart] ~= record then
		return false
	end

	record.Cleaning = true
	record.Suspended = true
	record.Revision += 1
	recordsByCart[record.Cart] = nil
	disconnectAll(record.Connections)
	zeroConstraintTorque(record, true)

	if destroyHelper and record.TorqueConstraint.Parent ~= nil then
		record.TorqueConstraint:Destroy()
	end

	log:Debug("Cleaned stability state %s Reason=%s", formatContext(record), reason)

	return true
end

local function failRecord(record: RuntimeRecord, reason: string)
	if record.Invalid or record.Cleaning or recordsByCart[record.Cart] ~= record then
		return
	end

	record.Invalid = true
	record.Suspended = true
	record.Revision += 1
	record.Mode = "Invalid"
	zeroConstraintTorque(record, true)

	local authorityCallSucceeded, authoritySuspended = pcall(function()
		return CartOccupantService:SuspendControl(record.Cart, "fatal cart stability invalidation")
	end)

	if not authorityCallSucceeded or not authoritySuspended then
		log:Warn(
			"Could not confirm fail-closed driver suspension %s Error=%s",
			formatContext(record),
			if authorityCallSucceeded
				then "cart occupancy was not registered"
				else tostring(authoritySuspended)
		)
	end

	log:Warn("Fatal stability failure %s Reason=%s", formatContext(record), reason)
	invokeFatalHandler(record, reason)

	if recordsByCart[record.Cart] == record then
		cleanupRecord(record, "fatal stability fallback cleanup", true)
	end
end

local function validateLiveContract(record: RuntimeRecord): (boolean, string?)
	if record.Cart.Parent == nil then
		return false, "cart is no longer parented"
	end

	if record.Root.Parent == nil or not record.Root:IsDescendantOf(record.Cart) then
		return false, "Root is no longer inside the registered cart"
	end

	if
		record.OrientationAttachment.Parent ~= record.Root
		or not record.OrientationAttachment:IsDescendantOf(record.Cart)
	then
		return false, "Root.OrientationAttachment is no longer valid"
	end

	if record.Constraints.Parent ~= record.Cart or record.Constraints.Name ~= "Constraints" then
		return false, "Constraints folder is no longer the direct cart contract folder"
	end

	local torqueConstraint = record.TorqueConstraint

	if
		torqueConstraint.Parent ~= record.Constraints
		or torqueConstraint.Name ~= TORQUE_NAME
		or torqueConstraint.Attachment0 ~= record.OrientationAttachment
		or torqueConstraint.Attachment1 ~= nil
		or torqueConstraint.RelativeTo ~= Enum.ActuatorRelativeTo.World
		or not torqueConstraint.Enabled
	then
		return false, "CartStabilityTorque no longer matches the approved runtime contract"
	end

	if not isFiniteVector3(torqueConstraint.Torque) then
		return false, "CartStabilityTorque contains a non-finite torque"
	end

	return true, nil
end

local function deferContractCheck(record: RuntimeRecord, reason: string)
	local expectedRevision = record.Revision

	task.defer(function()
		if
			recordsByCart[record.Cart] ~= record
			or record.Cleaning
			or record.Revision ~= expectedRevision
		then
			return
		end

		local valid, contractReason = validateLiveContract(record)

		if not valid then
			failRecord(
				record,
				string.format("%s: %s", reason, contractReason or "invalid contract")
			)
		end
	end)
end

local function attachRecordConnections(record: RuntimeRecord)
	table.insert(
		record.Connections,
		record.Cart.Destroying:Connect(function()
			cleanupRecord(record, "cart destroying", false)
		end)
	)
	table.insert(
		record.Connections,
		record.Cart.AncestryChanged:Connect(function()
			if record.Cart.Parent == nil then
				task.defer(function()
					if recordsByCart[record.Cart] == record then
						cleanupRecord(record, "cart removed from hierarchy", true)
					end
				end)
			end
		end)
	)
	table.insert(
		record.Connections,
		record.Root.AncestryChanged:Connect(function()
			if not record.Root:IsDescendantOf(record.Cart) then
				deferContractCheck(record, "Root hierarchy changed")
			end
		end)
	)
	table.insert(
		record.Connections,
		record.OrientationAttachment.AncestryChanged:Connect(function()
			if not record.OrientationAttachment:IsDescendantOf(record.Cart) then
				deferContractCheck(record, "OrientationAttachment hierarchy changed")
			end
		end)
	)
	table.insert(
		record.Connections,
		record.TorqueConstraint.Destroying:Connect(function()
			deferContractCheck(record, "CartStabilityTorque was destroyed")
		end)
	)
	table.insert(
		record.Connections,
		record.TorqueConstraint.AncestryChanged:Connect(function()
			if record.TorqueConstraint.Parent ~= record.Constraints then
				deferContractCheck(record, "CartStabilityTorque hierarchy changed")
			end
		end)
	)

	for _, propertyName in { "Attachment0", "Attachment1", "RelativeTo", "Enabled" } do
		table.insert(
			record.Connections,
			record.TorqueConstraint:GetPropertyChangedSignal(propertyName):Connect(function()
				deferContractCheck(
					record,
					string.format("CartStabilityTorque.%s changed", propertyName)
				)
			end)
		)
	end
end

local function updateDiagnostics(record: RuntimeRecord, result: StabilityStepResult)
	local severeChanged = result.SevereTilt ~= record.SevereTilt

	record.PreviousHeading = result.Heading
	record.PreviousTorque = result.Torque
	record.Mode = result.Mode
	record.RollAngle = result.RollAngle
	record.PitchAngle = result.PitchAngle
	record.TiltAngle = result.TiltAngle
	record.RollAngularVelocity = result.RollAngularVelocity
	record.PitchAngularVelocity = result.PitchAngularVelocity
	record.YawAngularVelocity = result.YawAngularVelocity
	record.CorrectionStrength = result.CorrectionStrength
	record.SevereTilt = result.SevereTilt

	if not severeChanged then
		return
	end

	if result.SevereTilt then
		local now = os.clock()

		if now - record.LastSevereLogTime >= SEVERE_LOG_INTERVAL_SECONDS then
			record.LastSevereLogTime = now
			log:Warn(
				"Severe tilt recovery active %s Roll=%.1f Pitch=%.1f Tilt=%.1f Torque=%.1f",
				formatContext(record),
				math.deg(result.RollAngle),
				math.deg(result.PitchAngle),
				math.deg(result.TiltAngle),
				result.Torque.Magnitude
			)
		end
	else
		log:Debug("Severe tilt recovery cleared %s", formatContext(record))
	end
end

local function updateRecord(record: RuntimeRecord, deltaTime: number)
	if record.Cleaning or record.Invalid or recordsByCart[record.Cart] ~= record then
		return
	end

	local contractValid, contractReason = validateLiveContract(record)

	if not contractValid then
		failRecord(record, contractReason or "runtime stability contract is invalid")
		return
	end

	if
		record.Suspended
		or not record.Profile.Enabled
		or record.Root.Anchored
		or CartAssemblyValidationService:GetState(record.Cart) ~= "Valid"
	then
		zeroConstraintTorque(record)
		return
	end

	-- DriverChanged is emitted only after Phase 1E completes its ownership
	-- transition. Trust that authoritative event instead of querying network
	-- ownership for every vacant cart on every physics step.
	if record.Driving then
		return
	end

	if
		not isFiniteVector3(record.Root.AssemblyAngularVelocity)
		or not isFiniteNumber(record.Root.AssemblyMass)
		or record.Root.AssemblyMass <= 0
	then
		failRecord(record, "Root has invalid angular velocity or assembly mass")
		return
	end

	local terrain = CartTerrainService:GetSnapshot(record.Cart)

	if terrain == nil then
		failRecord(record, "terrain state is unavailable for server-owned stability")
		return
	end

	local computeSuccess, resultOrError = pcall(function()
		return CartStabilityMath.ComputeStep({
			RootCFrame = record.Root.CFrame,
			AngularVelocity = record.Root.AssemblyAngularVelocity,
			AssemblyMass = record.Root.AssemblyMass,
			DesiredUp = terrain.DesiredUp,
			IntendedHeading = record.Root.CFrame.LookVector,
			PreviousTorque = record.PreviousTorque,
			PreviousHeading = record.PreviousHeading,
			AssistanceMultiplier = record.Profile.StationaryAssistanceMultiplier
				* terrain.StabilityMultiplier,
			DeltaTime = deltaTime,
			Profile = record.Profile,
		})
	end)

	if not computeSuccess then
		failRecord(
			record,
			string.format("stability calculation failed: %s", tostring(resultOrError))
		)
		return
	end

	local result = resultOrError :: StabilityStepResult

	if
		not isFiniteVector3(result.Torque)
		or not isFiniteVector3(result.Heading)
		or not isFiniteNumber(result.RollAngle)
		or not isFiniteNumber(result.PitchAngle)
		or not isFiniteNumber(result.TiltAngle)
		or not isFiniteNumber(result.RollAngularVelocity)
		or not isFiniteNumber(result.PitchAngularVelocity)
		or not isFiniteNumber(result.YawAngularVelocity)
		or not isFiniteNumber(result.CorrectionStrength)
	then
		failRecord(record, "stability calculation returned non-finite output")
		return
	end

	if not setConstraintTorque(record, result.Torque) then
		failRecord(record, "failed to apply CartStabilityTorque")
		return
	end

	updateDiagnostics(record, result)
end

local function onDriverChanged(
	cart: Model,
	_previousDriver: Player?,
	nextDriver: Player?,
	reason: string,
	driverRevision: number
)
	local record = recordsByCart[cart]

	if
		record == nil
		or record.Cleaning
		or record.Invalid
		or driverRevision <= record.LastDriverRevision
	then
		return
	end

	record.LastDriverRevision = driverRevision
	record.Driving = nextDriver ~= nil
	record.ActiveDriverUserId = if nextDriver ~= nil then nextDriver.UserId else 0
	record.Revision += 1
	zeroConstraintTorque(record, true)

	if nextDriver == nil then
		local terrain = CartTerrainService:GetSnapshot(record.Cart)

		if terrain == nil then
			failRecord(record, "terrain state is unavailable after driver exit")
			return
		end

		local headingSuccess, headingOrError = pcall(function()
			return resolveHeading(record.Root, terrain.DesiredUp, record.PreviousHeading)
		end)

		if not headingSuccess then
			failRecord(
				record,
				string.format("could not resume server heading: %s", tostring(headingOrError))
			)
			return
		end

		record.PreviousHeading = headingOrError :: Vector3
	end

	record.Mode = if record.Suspended
		then "Suspended"
		elseif record.Driving then "Driving"
		elseif record.Profile.Enabled then "Stationary"
		else "Disabled"

	log:Debug(
		"Stability mode changed %s Mode=%s DriverUserId=%d Reason=%s",
		formatContext(record),
		record.Mode,
		record.ActiveDriverUserId,
		reason
	)
end

function CartStabilityService:Start()
	if started then
		assert(
			preSimulationConnection ~= nil and driverChangedConnection ~= nil,
			"started stability service lost its global connections"
		)
		return
	end

	started = true
	driverChangedConnection = CartOccupantService.DriverChanged:Connect(onDriverChanged)
	preSimulationConnection = RunService.PreSimulation:Connect(function(deltaTime)
		for _, record in recordsByCart do
			updateRecord(record, deltaTime)
		end
	end)

	log:Info("Cart stability service ready")
end

function CartStabilityService:RegisterCart(cart: Model): (boolean, string?)
	if cart:GetAttribute("CartArcadeVersion")==1 then return true,nil end
	if recordsByCart[cart] ~= nil then
		return false, "cart already has a stability state"
	end

	if fatalHandler == nil then
		return false, "cart stability fatal handler must be registered before carts"
	end

	if cart.Parent == nil or cart:GetAttribute("RuntimeCart") ~= true then
		return false, "cart must be a live runtime model"
	end

	if
		CartAssemblyValidationService:GetState(cart) ~= "Valid"
		or not CartAssemblyValidationService:IsCartValid(cart)
	then
		return false, "cart assembly must pass fatal validation before stability registration"
	end

	local resolveSuccess, profileOrError = pcall(function()
		return CartStabilityProfileResolver.ResolveForCart(cart)
	end)

	if not resolveSuccess then
		return false,
			string.format("stability profile resolution failed: %s", tostring(profileOrError))
	end

	local rootInstance = cart:FindFirstChild("Root")
	local constraintsInstance = cart:FindFirstChild("Constraints")

	if rootInstance == nil or not rootInstance:IsA("BasePart") then
		return false, "cart requires direct Root BasePart"
	end

	if constraintsInstance == nil or not constraintsInstance:IsA("Folder") then
		return false, "cart requires direct Constraints Folder"
	end

	local orientationAttachmentInstance = rootInstance:FindFirstChild("OrientationAttachment")

	if
		orientationAttachmentInstance == nil
		or not orientationAttachmentInstance:IsA("Attachment")
	then
		return false, "Root requires direct OrientationAttachment"
	end

	if cart:FindFirstChild(TORQUE_NAME, true) ~= nil then
		return false, "cart already contains CartStabilityTorque"
	end

	local mutationStarted, mutationRevision, mutationError =
		CartAssemblyValidationService:BeginMutation(cart, "stability helper initialisation")

	if not mutationStarted or mutationRevision == nil then
		return false, mutationError or "assembly mutation could not begin"
	end

	local torqueConstraint = Instance.new("Torque")
	local configured, configurationError = pcall(function()
		torqueConstraint.Name = TORQUE_NAME
		torqueConstraint.Attachment0 = orientationAttachmentInstance
		torqueConstraint.Attachment1 = nil
		torqueConstraint.RelativeTo = Enum.ActuatorRelativeTo.World
		torqueConstraint.Torque = Vector3.zero
		torqueConstraint.Enabled = true
		torqueConstraint.Parent = constraintsInstance
	end)

	if not configured then
		torqueConstraint:Destroy()
		return false,
			string.format(
				"CartStabilityTorque creation failed after assembly mutation began: %s",
				tostring(configurationError)
			)
	end

	local validationCallSucceeded, assemblyValidOrError, _, validationError = pcall(function()
		return CartAssemblyValidationService:CompleteMutation(
			cart,
			mutationRevision,
			"Runtime",
			"stability helper initialised",
			true
		)
	end)

	if not validationCallSucceeded or not assemblyValidOrError then
		return false,
			if validationCallSucceeded
				then validationError or "stability helper failed assembly validation"
				else string.format(
					"stability helper assembly validation errored: %s",
					tostring(assemblyValidOrError)
				)
	end

	if
		cart.Parent == nil
		or torqueConstraint.Parent ~= constraintsInstance
		or rootInstance.Parent == nil
	then
		return false, "cart was destroyed during stability initialisation"
	end

	local headingSuccess, headingOrError = pcall(function()
		local terrain = CartTerrainService:GetSnapshot(cart)

		if terrain == nil then
			error("terrain state is unavailable during stability registration")
		end

		return resolveHeading(rootInstance, terrain.DesiredUp, nil)
	end)

	if not headingSuccess then
		return false,
			string.format("initial stability heading failed: %s", tostring(headingOrError))
	end

	local activeDriver = CartOccupantService:GetDriver(cart)
	local profile = profileOrError :: EffectiveStabilityProfile
	local record: RuntimeRecord = {
		Cart = cart,
		Root = rootInstance,
		OrientationAttachment = orientationAttachmentInstance,
		Constraints = constraintsInstance,
		TorqueConstraint = torqueConstraint,
		Profile = profile,
		Invalid = false,
		Cleaning = false,
		Suspended = false,
		Driving = activeDriver ~= nil,
		ActiveDriverUserId = if activeDriver ~= nil then activeDriver.UserId else 0,
		Revision = 1,
		LastDriverRevision = -1,
		PreviousHeading = headingOrError :: Vector3,
		PreviousTorque = Vector3.zero,
		Mode = if activeDriver ~= nil
			then "Driving"
			elseif profile.Enabled then "Stationary"
			else "Disabled",
		RollAngle = 0,
		PitchAngle = 0,
		TiltAngle = 0,
		RollAngularVelocity = 0,
		PitchAngularVelocity = 0,
		YawAngularVelocity = 0,
		CorrectionStrength = 0,
		SevereTilt = false,
		LastSevereLogTime = -math.huge,
		Connections = {},
	}

	recordsByCart[cart] = record
	attachRecordConnections(record)

	log:Info(
		"Registered cart stability %s Enabled=%s MaxTorque=%.1f StationaryMultiplier=%.2f",
		formatContext(record),
		tostring(profile.Enabled),
		profile.MaxCorrectiveTorque,
		profile.StationaryAssistanceMultiplier
	)

	return true, nil
end

function CartStabilityService:SuspendCart(cart: Model, reason: string): (boolean, string?)
	if cart:GetAttribute("CartArcadeVersion")==1 then return true,nil end
	local record = recordsByCart[cart]

	if record == nil then
		return false, "cart has no stability state"
	end

	if record.Invalid or record.Cleaning then
		return false, "cart stability is unavailable"
	end

	if record.Suspended then
		return true, nil
	end

	record.Suspended = true
	record.Revision += 1
	record.Mode = "Suspended"
	zeroConstraintTorque(record, true)

	log:Debug("Suspended cart stability %s Reason=%s", formatContext(record), reason)

	return true, nil
end

function CartStabilityService:ResumeCart(cart: Model, reason: string): (boolean, string?)
	if cart:GetAttribute("CartArcadeVersion")==1 then return true,nil end
	local record = recordsByCart[cart]

	if record == nil then
		return false, "cart has no stability state"
	end

	if record.Invalid or record.Cleaning then
		return false, "cart stability is unavailable"
	end

	if not CartAssemblyValidationService:IsCartValid(cart) then
		return false, "cart assembly must be valid before stability resumes"
	end

	local contractValid, contractReason = validateLiveContract(record)

	if not contractValid then
		failRecord(record, contractReason or "stability contract invalid during resume")
		return false, contractReason
	end

	local headingSuccess, headingOrError = pcall(function()
		local terrain = CartTerrainService:GetSnapshot(cart)

		if terrain == nil then
			error("terrain state is unavailable during stability resume")
		end

		return resolveHeading(record.Root, terrain.DesiredUp, record.PreviousHeading)
	end)

	if not headingSuccess then
		local failureReason =
			string.format("stability heading could not resume: %s", tostring(headingOrError))
		failRecord(record, failureReason)
		return false, failureReason
	end

	record.PreviousHeading = headingOrError :: Vector3
	record.PreviousTorque = Vector3.zero
	record.Suspended = false
	record.Revision += 1
	record.Mode = if record.Driving
		then "Driving"
		elseif record.Profile.Enabled then "Stationary"
		else "Disabled"
	zeroConstraintTorque(record, true)

	log:Debug("Resumed cart stability %s Reason=%s", formatContext(record), reason)

	return true, nil
end

function CartStabilityService:UnregisterCart(cart: Model, reason: string?): boolean
	local record = recordsByCart[cart]

	if record == nil then
		return false
	end

	return cleanupRecord(record, reason or "cart stability unregistered", true)
end

function CartStabilityService:IsCartRegistered(cart: Model): boolean
	return recordsByCart[cart] ~= nil
end

function CartStabilityService:GetStateSnapshot(cart: Model): StabilityStateSnapshot?
	local record = recordsByCart[cart]

	if record == nil then
		return nil
	end

	return table.freeze({
		Cart = record.Cart,
		Root = record.Root,
		Profile = record.Profile,
		IsValid = not record.Invalid and not record.Cleaning,
		Suspended = record.Suspended,
		Driving = record.Driving,
		ActiveDriverUserId = record.ActiveDriverUserId,
		Revision = record.Revision,
		Heading = record.PreviousHeading,
		AppliedTorque = record.PreviousTorque,
		Mode = record.Mode,
		RollAngle = record.RollAngle,
		PitchAngle = record.PitchAngle,
		TiltAngle = record.TiltAngle,
		RollAngularVelocity = record.RollAngularVelocity,
		PitchAngularVelocity = record.PitchAngularVelocity,
		YawAngularVelocity = record.YawAngularVelocity,
		CorrectionStrength = record.CorrectionStrength,
		SevereTilt = record.SevereTilt,
	})
end

function CartStabilityService:GetDiagnostics()
	local recordCount = 0
	local recordConnectionCount = 0
	local retainedConnectionObjectCount = 0
	local managedTorqueCount = 0

	for _, record in recordsByCart do
		recordCount += 1
		retainedConnectionObjectCount += #record.Connections

		for _, connection in record.Connections do
			if connection.Connected then
				recordConnectionCount += 1
			end
		end

		if
			record.TorqueConstraint.Parent ~= nil
			and record.TorqueConstraint:IsDescendantOf(record.Cart)
		then
			managedTorqueCount += 1
		end
	end

	return table.freeze({
		Started = started,
		RecordCount = recordCount,
		RecordConnectionCount = recordConnectionCount,
		RetainedConnectionObjectCount = retainedConnectionObjectCount,
		SharedConnectionCount = (if preSimulationConnection ~= nil then 1 else 0)
			+ (if driverChangedConnection ~= nil then 1 else 0),
		SchedulerCount = if preSimulationConnection ~= nil then 1 else 0,
		ManagedTorqueCount = managedTorqueCount,
	})
end

function CartStabilityService:SetFatalHandler(handler: FatalHandler)
	assert(fatalHandler == nil, "Cart stability fatal handler is already registered")
	fatalHandler = handler
end

return CartStabilityService
