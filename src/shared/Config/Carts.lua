--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Handling = require(script.Parent.CartHandlingConfig)
local Ids = require(ReplicatedStorage.Shared.Constants.Ids)
local CartTypes = require(ReplicatedStorage.Shared.Types.CartTypes)
local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)
local CartTerrainTypes = require(ReplicatedStorage.Shared.Types.CartTerrainTypes)

local scrapChariotStability: CartStabilityTypes.BaseStabilityProfile = {
	-- Phase 1G Development tuning. These values are not workbook-locked and
	-- require Roblox Studio physical validation.
	Enabled = true,

	OrientationErrorDeadZoneDegrees = 1,
	FreeRollAngleDegrees = 6,
	FreePitchAngleDegrees = 4,
	ModerateRollAngleDegrees = 18,
	ModeratePitchAngleDegrees = 14,
	StrongRollAngleDegrees = 55,
	StrongPitchAngleDegrees = 45,

	UprightStrength = 1,
	RollCorrectionStrength = 1,
	PitchCorrectionStrength = 0.75,
	RollDamping = 0.42,
	PitchDamping = 0.5,
	MaxCorrectiveTorque = 42000,
	MaxCorrectiveAngularResponseDegreesPerSecond = 120,
	ResponseSpeed = 12,

	StationaryAssistanceMultiplier = 0.85,
	DrivingAssistanceMultiplier = 1,
	SevereTiltRecoveryMultiplier = 1.35,

	ExtremeYawDamping = 0,
	ExtremeYawThresholdDegreesPerSecond = 240,
}

table.freeze(scrapChariotStability)

local scrapChariotTerrain: CartTerrainTypes.BaseTerrainProfile = {
	-- Phase 1H Development tuning. The workbook defines no terrain-physics
	-- values, so these require Roblox Studio terrain validation.
	Enabled = true,

	ProbeOriginHeight = 2,
	GroundDetectionDistance = 6,
	MaximumSupportGap = 1.25,
	MaximumSupportPenetration = 0.35,
	LateralProbeFraction = 0.42,
	ForwardProbeFraction = 0.3,
	FullGroundedHitCount = 2,

	GroundedReacquireDelay = 0.08,
	AirborneDelay = 0.18,
	NormalResponseSpeed = 10,
	MaximumNormalChangeDegreesPerSecond = 120,
	AirborneWorldUpResponseSpeed = 2.5,
	NormalOutlierAngleDegrees = 35,

	SlopeEffectStartDegrees = 3,
	FullSlopeEffectDegrees = 35,
	MaximumClimbAngleDegrees = 45,
	MaximumGroundAngleDegrees = 65,
	MaximumUphillAccelerationReduction = 0.25,
	MaximumDownhillAcceleration = 3,
	MaximumDownhillCoastReduction = 0.2,

	PartialSupportStabilityMultiplier = 0.7,
	AirborneStabilityMultiplier = 0.35,

	DrivenSampleRate = 15,
	ServerMovingSampleRate = 10,
	ServerSettledSampleRate = 4,
	ServerSettledSpeedThreshold = 1,
}

table.freeze(scrapChariotTerrain)

local scrapChariot: CartTypes.CartDefinition = {
	Id = Ids.Carts.ScrapChariot,
	DisplayName = "Scrap Chariot",
	AssetName = "ScrapChariot",

	TeamSlots = 2, -- Starting entitlement; purchased capacity is player-wide ChariotTeam data.
	CargoSlots = 3,
	CargoCapacity = 3,

	-- Hunting-cart movement tuning introduced by the Phase 1C movement revision.
	-- These physical-control values remain centralized development tuning pending
	-- Roblox Studio validation.
	HuntingSpeed = 20, -- legacy reference; mounted hunting now holds position
	MaxTravelSpeed = Handling.StarterSpeed,
	ForwardAcceleration = Handling.ForwardAcceleration,
	HighSpeedAccelerationMultiplier = 1,
	AccelerationCurveExponent = 1.35,
	CoastDeceleration = Handling.Braking,
	HighSpeedCoastDecelerationMultiplier = 1,
	Braking = Handling.Braking,
	HighSpeedBrakingMultiplier = 1,
	RecoveryBackupSpeed = 3.5,
	RecoveryBackupAcceleration = 6,
	RecoveryBackupDeceleration = 12,
	RecoveryInputDelay = 0.45,
	NearZeroSpeedThreshold = 0.6,
	-- Phase 1I centralizes the controller's existing threshold; this is not a retune.
	LongitudinalInputDeadzone = 0.05,
	-- Phase 1I protocol retry timing; this does not change cart force or balance.
	LongitudinalTransitionRetryInterval = 0.1,
	LongitudinalTransitionMaximumRetryInterval = 1,
	TurnRate = Handling.LowTurnDegrees,
	StationarySteeringThreshold = 0.5,
	LowSpeedSteeringMultiplier = 1,
	HighSpeedSteeringMultiplier = Handling.CruiseTurnDegrees / Handling.LowTurnDegrees,
	SteeringInterpolationExponent = 1.35,
	LateralGrip = 10,
	HighSpeedLateralGripMultiplier = 1.25,
	UprightResponsiveness = Handling.OrientationResponsiveness,
	UprightTorque = 42000,
	MaxAngularSpeed = Handling.LowTurnDegrees,
	DriveForceLimit = 180,
	GroundFriction = 0.08,
	GroundFrictionWeight = 100,

	Stability = scrapChariotStability,
	Terrain = scrapChariotTerrain,

	TeamSpeedCap = 0.04,
	TeamUtilityCap = 0.08,
}

local Phase13 = require(script.Parent.Phase13)
local Carts: { [string]: any } = {}
for _, row in Phase13.CartRows do
	local definition = table.clone(scrapChariot)
	local class = Phase13.Classes[row.classId]
	definition.Id = row.id
	definition.DisplayName = row.displayName
	definition.AssetName = row.assetName
	definition.ClassId = row.classId
	definition.Price = row.price
	definition.price = row.price
	definition.StarterEntitlement = row.starter == true
	definition.MaxTravelSpeed = Handling.StarterSpeed * class.speed
	definition.ControlReferenceSpeed = Handling.StarterSpeed
	definition.ForwardAcceleration = Handling.ForwardAcceleration * class.acceleration
	definition.Braking = Handling.Braking * class.braking
	definition.CoastDeceleration = Handling.Braking * class.braking
	definition.TurnRate = Handling.LowTurnDegrees * class.steering
	definition.MaxAngularSpeed = Handling.LowTurnDegrees * class.steering
	Carts[row.id] = table.freeze(definition)
end
return table.freeze(Carts)
