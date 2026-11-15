--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)
local CartStabilityMath = require(ReplicatedStorage.Shared.Utility.CartStabilityMath)
local CartStabilityProfileResolver =
	require(ReplicatedStorage.Shared.Utility.CartStabilityProfileResolver)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

type EffectiveStabilityProfile = CartStabilityTypes.EffectiveStabilityProfile
type StabilityMode = CartStabilityTypes.StabilityMode
type StabilityStepResult = CartStabilityTypes.StabilityStepResult

export type DiagnosticSnapshot = {
	Enabled: boolean,
	Mode: StabilityMode,
	Torque: Vector3,
	Heading: Vector3,
	RollAngle: number,
	PitchAngle: number,
	TiltAngle: number,
	RollAngularVelocity: number,
	PitchAngularVelocity: number,
	YawAngularVelocity: number,
	CorrectionStrength: number,
	SevereTilt: boolean,
}

export type Controller = {
	SetEnabled: (self: Controller, enabled: boolean) -> (),
	Suspend: (self: Controller) -> (),
	Step: (
		self: Controller,
		deltaTime: number,
		intendedHeading: Vector3,
		desiredUp: Vector3,
		terrainAssistanceMultiplier: number
	) -> (),
	GetDiagnosticSnapshot: (self: Controller) -> DiagnosticSnapshot,
	Destroy: (self: Controller) -> (),
}

type ControllerPrivate = Controller & {
	_cart: Model,
	_root: BasePart,
	_torque: Torque,
	_profile: EffectiveStabilityProfile,
	_previousTorque: Vector3,
	_previousHeading: Vector3?,
	_lastResult: StabilityStepResult?,
	_enabled: boolean,
	_destroyed: boolean,
	_invalidOutputWarned: boolean,
	_lastModeLogTime: number,
	_lastSevereLogTime: number,
}

local STABILITY_CONSTRAINT_NAME = "CartStabilityTorque"
local ASSEMBLY_STATE_ATTRIBUTE = "AssemblyValidationState"
local MODE_LOG_INTERVAL_SECONDS = 0.5
local SEVERE_LOG_INTERVAL_SECONDS = 2

local log = Logger.new("CartStabilityController")

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local CartStabilityController = {}

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

local function warnTorqueWriteFailure(self: ControllerPrivate, action: string)
	if self._invalidOutputWarned then
		return
	end

	self._invalidOutputWarned = true
	log:Warn(
		"Could not %s local stability torque Cart=%s CartId=%s",
		action,
		self._cart.Name,
		self._profile.CartId
	)
end

local function zeroLocalTorque(self: ControllerPrivate): boolean
	self._previousTorque = Vector3.zero
	self._lastResult = nil

	if self._torque.Parent ~= nil then
		local cleared = pcall(function()
			self._torque.Torque = Vector3.zero
		end)

		if not cleared then
			warnTorqueWriteFailure(self, "clear")
			return false
		end
	end

	return true
end

local function assertContract(cart: Model, root: BasePart, torque: Torque)
	assert(cart.Parent ~= nil, "CartStabilityController requires a live cart")
	assert(root:IsDescendantOf(cart), "Stability Root must belong to the cart")

	local constraints = cart:FindFirstChild("Constraints")
	local orientationAttachment = root:FindFirstChild("OrientationAttachment")

	assert(
		constraints ~= nil and constraints:IsA("Folder"),
		"CartStabilityController requires the established Constraints folder"
	)
	assert(
		orientationAttachment ~= nil and orientationAttachment:IsA("Attachment"),
		"CartStabilityController requires Root.OrientationAttachment"
	)
	assert(torque.Name == STABILITY_CONSTRAINT_NAME, "Unexpected stability Torque name")
	assert(
		torque.Parent == constraints,
		"CartStabilityTorque must be a direct child of Constraints"
	)
	assert(
		torque.Attachment0 == orientationAttachment,
		"CartStabilityTorque must use Root.OrientationAttachment"
	)
	assert(torque.Attachment1 == nil, "CartStabilityTorque must not use Attachment1")
	assert(
		torque.RelativeTo == Enum.ActuatorRelativeTo.World,
		"CartStabilityTorque must operate in world space"
	)
	assert(torque.Enabled, "CartStabilityTorque must remain enabled")
end

function CartStabilityController.new(cart: Model, root: BasePart, torque: Torque): Controller
	assertContract(cart, root, torque)

	local profile = CartStabilityProfileResolver.ResolveForCart(cart)
	local self: ControllerPrivate = setmetatable({
		_cart = cart,
		_root = root,
		_torque = torque,
		_profile = profile,
		_previousTorque = Vector3.zero,
		_previousHeading = nil,
		_lastResult = nil,
		_enabled = false,
		_destroyed = false,
		_invalidOutputWarned = false,
		_lastModeLogTime = -math.huge,
		_lastSevereLogTime = -math.huge,
	}, ControllerMethods) :: any

	zeroLocalTorque(self)

	return self
end

function CartStabilityController.Attach(cart: Model, root: BasePart, torque: Torque): Controller
	return CartStabilityController.new(cart, root, torque)
end

function ControllerMethods.SetEnabled(self: ControllerPrivate, enabled: boolean)
	if self._destroyed then
		return
	end

	local shouldEnable = enabled and self._profile.Enabled

	if self._enabled == shouldEnable then
		if not shouldEnable then
			zeroLocalTorque(self)
		end

		return
	end

	self._enabled = shouldEnable
	self._lastResult = nil
	self._previousHeading = nil
	self._invalidOutputWarned = false
	zeroLocalTorque(self)
end

function ControllerMethods.Suspend(self: ControllerPrivate)
	self:SetEnabled(false)
end

function ControllerMethods.Step(
	self: ControllerPrivate,
	deltaTime: number,
	intendedHeading: Vector3,
	desiredUp: Vector3,
	terrainAssistanceMultiplier: number
)
	if self._destroyed or not self._enabled then
		return
	end

	local cart = self._cart
	local root = self._root
	local torque = self._torque

	if
		cart.Parent == nil
		or root.Parent == nil
		or torque.Parent == nil
		or not root:IsDescendantOf(cart)
		or cart:GetAttribute(ASSEMBLY_STATE_ATTRIBUTE) ~= "Valid"
		or root.Anchored
	then
		zeroLocalTorque(self)
		return
	end

	if
		not isFiniteNumber(deltaTime)
		or deltaTime <= 0
		or not isFiniteVector3(intendedHeading)
		or not isFiniteVector3(desiredUp)
		or desiredUp.Magnitude <= 1e-6
		or not isFiniteNumber(terrainAssistanceMultiplier)
		or terrainAssistanceMultiplier < 0
		or terrainAssistanceMultiplier > 1
	then
		zeroLocalTorque(self)
		return
	end

	local computeSuccess, resultOrError = pcall(function()
		return CartStabilityMath.ComputeStep({
			RootCFrame = root.CFrame,
			AngularVelocity = root.AssemblyAngularVelocity,
			AssemblyMass = root.AssemblyMass,
			DesiredUp = desiredUp,
			IntendedHeading = intendedHeading,
			PreviousTorque = self._previousTorque,
			PreviousHeading = self._previousHeading,
			AssistanceMultiplier = self._profile.DrivingAssistanceMultiplier
				* terrainAssistanceMultiplier,
			DeltaTime = deltaTime,
			Profile = self._profile,
		})
	end)

	if not computeSuccess then
		zeroLocalTorque(self)

		if not self._invalidOutputWarned then
			self._invalidOutputWarned = true
			log:Warn(
				"Stability calculation failed Cart=%s CartId=%s Error=%s",
				cart.Name,
				self._profile.CartId,
				tostring(resultOrError)
			)
		end

		return
	end

	local result = resultOrError :: StabilityStepResult

	if not isFiniteVector3(result.Torque) or not isFiniteVector3(result.Heading) then
		zeroLocalTorque(self)

		if not self._invalidOutputWarned then
			self._invalidOutputWarned = true
			log:Warn(
				"Rejected non-finite stability output Cart=%s CartId=%s",
				cart.Name,
				self._profile.CartId
			)
		end

		return
	end

	local previousResult = self._lastResult

	if previousResult == nil or previousResult.Mode ~= result.Mode then
		local now = os.clock()

		if result.SevereTilt and (previousResult == nil or not previousResult.SevereTilt) then
			if now - self._lastSevereLogTime >= SEVERE_LOG_INTERVAL_SECONDS then
				self._lastSevereLogTime = now
				log:Warn(
					"Severe tilt recovery active Cart=%s CartId=%s Roll=%.1f Pitch=%.1f Tilt=%.1f Torque=%.1f",
					cart.Name,
					self._profile.CartId,
					math.deg(result.RollAngle),
					math.deg(result.PitchAngle),
					math.deg(result.TiltAngle),
					result.Torque.Magnitude
				)
			end
		elseif now - self._lastModeLogTime >= MODE_LOG_INTERVAL_SECONDS then
			self._lastModeLogTime = now
			log:Debug(
				"Stability mode changed Cart=%s CartId=%s Mode=%s Roll=%.1f Pitch=%.1f Correction=%.2f",
				cart.Name,
				self._profile.CartId,
				result.Mode,
				math.deg(result.RollAngle),
				math.deg(result.PitchAngle),
				result.CorrectionStrength
			)
		end
	end

	self._previousTorque = result.Torque
	self._previousHeading = result.Heading
	self._lastResult = result

	local applied = pcall(function()
		torque.Torque = result.Torque
	end)

	if not applied then
		warnTorqueWriteFailure(self, "apply")
		zeroLocalTorque(self)
		return
	end

	self._invalidOutputWarned = false
end

function ControllerMethods.GetDiagnosticSnapshot(self: ControllerPrivate): DiagnosticSnapshot
	local result = self._lastResult

	if result == nil then
		return table.freeze({
			Enabled = self._enabled and not self._destroyed,
			Mode = "Free",
			Torque = self._previousTorque,
			Heading = self._previousHeading or Vector3.zero,
			RollAngle = 0,
			PitchAngle = 0,
			TiltAngle = 0,
			RollAngularVelocity = 0,
			PitchAngularVelocity = 0,
			YawAngularVelocity = 0,
			CorrectionStrength = 0,
			SevereTilt = false,
		})
	end

	return table.freeze({
		Enabled = self._enabled and not self._destroyed,
		Mode = result.Mode,
		Torque = result.Torque,
		Heading = result.Heading,
		RollAngle = result.RollAngle,
		PitchAngle = result.PitchAngle,
		TiltAngle = result.TiltAngle,
		RollAngularVelocity = result.RollAngularVelocity,
		PitchAngularVelocity = result.PitchAngularVelocity,
		YawAngularVelocity = result.YawAngularVelocity,
		CorrectionStrength = result.CorrectionStrength,
		SevereTilt = result.SevereTilt,
	})
end

function ControllerMethods.Destroy(self: ControllerPrivate)
	if self._destroyed then
		return
	end

	self._enabled = false
	zeroLocalTorque(self)
	self._destroyed = true
	self._lastResult = nil
	self._previousHeading = nil
end

return CartStabilityController
