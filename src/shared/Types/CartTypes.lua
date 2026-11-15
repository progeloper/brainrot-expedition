--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartStabilityTypes = require(ReplicatedStorage.Shared.Types.CartStabilityTypes)
local CartTerrainTypes = require(ReplicatedStorage.Shared.Types.CartTerrainTypes)

export type CartAssetContract = {
	Model: Model,
	Root: BasePart,
	MovementAttachment: Attachment,
	OrientationAttachment: Attachment,
	DriverSeat: VehicleSeat,
	CameraTarget: BasePart,
	CargoSlots: Folder,
	FormationSlots: Folder,
	Visual: Model,
	Constraints: Folder,
}

export type CartId = string

export type CartDefinition = {
	Id: CartId,
	DisplayName: string,
	AssetName: string,
	TeamSlots: number,
	CargoSlots: number,
	CargoCapacity: number,

	HuntingSpeed: number,
	MaxTravelSpeed: number,
	ForwardAcceleration: number,
	HighSpeedAccelerationMultiplier: number,
	AccelerationCurveExponent: number,
	CoastDeceleration: number,
	HighSpeedCoastDecelerationMultiplier: number,
	Braking: number,
	HighSpeedBrakingMultiplier: number,
	RecoveryBackupSpeed: number,
	RecoveryBackupAcceleration: number,
	RecoveryBackupDeceleration: number,
	RecoveryInputDelay: number,
	NearZeroSpeedThreshold: number,
	LongitudinalInputDeadzone: number,
	LongitudinalTransitionRetryInterval: number,
	LongitudinalTransitionMaximumRetryInterval: number,
	TurnRate: number,
	StationarySteeringThreshold: number,
	LowSpeedSteeringMultiplier: number,
	HighSpeedSteeringMultiplier: number,
	SteeringInterpolationExponent: number,
	LateralGrip: number,
	HighSpeedLateralGripMultiplier: number,
	UprightResponsiveness: number,
	UprightTorque: number,
	MaxAngularSpeed: number,
	DriveForceLimit: number,
	GroundFriction: number,
	GroundFrictionWeight: number,

	Stability: CartStabilityTypes.BaseStabilityProfile,
	Terrain: CartTerrainTypes.BaseTerrainProfile,

	TeamSpeedCap: number,
	TeamUtilityCap: number,
}

return nil
