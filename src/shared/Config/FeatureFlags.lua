--!strict

export type FeatureFlags = {
	WorldProgressionEnabled: boolean,
	CartEnabled: boolean,
	BankingEnabled: boolean,
	KeepersEnabled: boolean,
	EquippedTeamsEnabled: boolean,
	MutationsEnabled: boolean,
	GadgetsEnabled: boolean,
	TheftEnabled: boolean,
	WorldEventsEnabled: boolean,
	MonetisationEnabled: boolean,
	VoxelCreaturesV4Enabled: boolean,
	VillagerGuardsEnabled: boolean,
	GameAudioEnabled: boolean,
	TrendAudioTest: boolean,
	TrendAudioShare: number,
	WeaponTiersV2Enabled: boolean,
	CampReworkV1Enabled: boolean,
	TrainingV1Enabled: boolean,
	RebirthUiV2Enabled: boolean,
	DriveAndHuntV1Enabled: boolean,
	PlaytestFixesV1Enabled: boolean,
	CreatureAnimationEnabled: boolean,
	VillagerAnimationEnabled: boolean,
	VillagerLifeEnabled: boolean,
}

local FeatureFlags: FeatureFlags = {
	WorldProgressionEnabled = true, -- Existing Main uses the explicit environment rollout gate in Bootstrap.
	CartEnabled = true,
	BankingEnabled = false,
	KeepersEnabled = false,
	EquippedTeamsEnabled = require(script.Parent.Environment).MainGameplayEnabled
		or not require(script.Parent.Environment).IsProduction,
	MutationsEnabled = false,
	GadgetsEnabled = false,
	TheftEnabled = false,
	WorldEventsEnabled = false,
	MonetisationEnabled = false,
	-- Voxel V4 creature visuals (presentation only). Off until the owner authorises CP-E;
	-- legacy templates stay archived and load while this is false.
	VoxelCreaturesV4Enabled = false,
	-- The V5 terrain world + Storm boundary is permanent (owner, 10 Nov 2026); the legacy map and
	-- its flag were retired. See TerrainRedesignSwitch.
	-- Villager guards + Escape Ring (NPC/presentation only). Owner authorised CP-D on
	-- 10 Nov 2026. Set false to remove villagers, chases and their remote entirely.
	VillagerGuardsEnabled = true,
	-- v2 game audio (client presentation only; AudioController + AudioCatalog). On for DEV. When false
	-- no BE_ sounds or SoundGroups are created and the game sounds exactly as before.
	GameAudioEnabled = true,
	-- Trend audio A/B test (phonk intro/chase, rare-catch BOOM, brainrot voices). TrendAudioShare of
	-- players get "Trend"; with TrendAudioTest = false everyone is "Current" and hears the v2 audio.
	TrendAudioTest = true,
	TrendAudioShare = 0.5,
	-- Weapon Tiers V2: region-scaled brainrot HP + a distinct stat profile per weapon tier (server-
	-- authoritative). Off until the owner approves. When false, HP and weapon stats are exactly as before.
	-- See Config/WeaponTiersV2.
	WeaponTiersV2Enabled = false,
	-- Camp Rework (owner-approved 11–12 Nov 2026). All three stay false live until the owner flips
	-- them; Studio previews them by default (see Config/CampReworkFlags).
	-- New stalls, seeded camp layout, continuous camp floor, special weapons, sell-back.
	CampReworkV1Enabled = false,
	-- Training stall + 25 Training levels replace the cart Speed upgrades.
	TrainingV1Enabled = false,
	-- "Rebirth" naming, YOU LOSE / YOU GET window, payback line and READY glow.
	RebirthUiV2Enabled = false,
	-- Drive-and-Hunt (12 Nov 2026): gate launch, HOP OUT / CART / LOAD & GO switch button, auto-lock
	-- aiming, scoop feedback and first-time hints. Off until the owner approves; when false the game
	-- behaves exactly as before. Parts are switched individually in Config/DriveAndHunt.
	DriveAndHuntV1Enabled = true, -- CP-D, owner authorised 12 Nov 2026
	-- Playtest Fixes v1 (12 Nov playtest): stall weapon poses, weapon VFX, Train-to-rollers, brainrot
	-- size ladder, Gems stall. Off until the owner approves; when false the game behaves as before.
	-- Parts are switched individually in Config/PlaytestFixes. Map studs are an authored world change
	-- (scripts/RevertMapStuds.server.lua restores the backup).
	PlaytestFixesV1Enabled = false,
	-- Rig + animation brief v5 (13 Nov 2026). All three stay false until the owner approves;
	-- with them off, movement, packets, templates and villagers are exactly as before.
	-- Brainrots: natural roaming (Config/CharacterMotion) and, per approved species, rigs + animations.
	CreatureAnimationEnabled = false,
	-- Villagers: steering movement, the one villager body and its skins.
	VillagerAnimationEnabled = false,
	-- Village life while Idle (work spots, chat, wave). Never changes noticing or chasing.
	VillagerLifeEnabled = false,
}

return table.freeze(FeatureFlags)
