--!strict

export type InputDevice = "KeyboardMouse" | "Touch" | "Gamepad"

export type CartInputState = {
	Throttle: number,
	Steering: number,
	Brake: boolean,
	ResetHeld: boolean,
	InputDevice: InputDevice,
}

export type LocalVelocity = {
	ForwardSpeed: number,
	LateralSpeed: number,
	AbsoluteSpeed: number,
	NormalizedForwardSpeed: number,
}

export type LongitudinalIntent = "None" | "Forward" | "Reverse"

export type LongitudinalControlAction =
	"ForwardPropulsion"
	| "Coast"
	| "Brake"
	| "ReversePropulsion"

export type LongitudinalState =
	"Idle"
	| "Accelerating"
	| "Cruising"
	| "Coasting"
	| "Braking"
	| "Stopped"
	| "Reverse"

export type LongitudinalTransition = {
	TargetState: LongitudinalState,
	StartedAt: number,
}

export type LongitudinalSnapshot = {
	CurrentState: LongitudinalState,
	PreviousState: LongitudinalState,
	CurrentTransition: LongitudinalTransition?,
	StateEnteredAt: number,
}

export type EffectiveMovementProfile = {
	CartId: string,

	HuntingSpeed: number,
	MaxTravelSpeed: number,
	-- Immutable baseline used by acceleration, braking, grip and steering curves.
	-- Purchased speed changes the ceiling without retuning those curves.
	ControlReferenceSpeed: number,
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
	DriveForceLimit: number,
	UprightResponsiveness: number,
	UprightTorque: number,
	MaxAngularSpeed: number,

	GroundFriction: number,
	GroundFrictionWeight: number,
}

return nil
