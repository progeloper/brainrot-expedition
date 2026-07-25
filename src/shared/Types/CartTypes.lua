--!strict

export type CartAssetContract = {
	Model: Model,
	Root: BasePart,
	DriverSeat: VehicleSeat,
	CameraTarget: BasePart,
	HarpoonOrigin: BasePart,
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

	BaseSpeed: number,
	Acceleration: number,
	Braking: number,
	TurnRate: number,
	ReverseSpeedMultiplier: number,

	TeamSpeedCap: number,
	TeamUtilityCap: number,
}

return nil
