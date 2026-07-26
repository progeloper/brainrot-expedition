--!strict

export type CartSpawnId = string

export type CartSpawnDefinition = {
	Id: CartSpawnId,
	CartId: string,
	Priority: number,
	Enabled: boolean,
	DebugOnly: boolean,
	CFrame: CFrame,
}

export type SpawnedCartRecord = {
	OwnerUserId: number,
	CartId: string,
	SpawnId: CartSpawnId,
	Model: Model,
	SpawnCFrame: CFrame,
	CreatedAt: number,
}

return nil
