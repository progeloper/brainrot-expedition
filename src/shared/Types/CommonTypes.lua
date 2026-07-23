--!strict

export type BrainrotId = string
export type CartId = string
export type HarpoonId = string
export type GadgetId = string
export type ZoneId = string
export type KeeperId = string

export type MutationId = "None" | "Shiny" | "Golden" | "Glitched" | "Radioactive" | "Celestial"

export type ExpeditionRole = "Sprinter" | "Tracker" | "Wrangler" | "Hauler" | "Trickster" | "Lucky"

export type TeamStats = {
	SpeedBonus: number,
	AccelerationBonus: number,
	HandlingBonus: number,
	TetherStabilityBonus: number,
	DetectionBonus: number,
	GadgetCooldownReduction: number,
	CargoValueBonus: number,
	MutationChanceBonus: number,
}

return nil
