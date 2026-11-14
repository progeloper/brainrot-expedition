--!strict
-- Natural movement for brainrots and villagers (rig + animation brief v5, Part A).
-- Travel style only: no speed caps, radii, timers or fairness values live here.
-- Gated by FeatureFlags.CreatureAnimationEnabled / VillagerAnimationEnabled. In Studio a
-- Play session can opt in without touching the flags by setting, before Play:
--   ReplicatedStorage.CreatureAnimationPreview = true
--   ReplicatedStorage.VillagerAnimationPreview = true
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FeatureFlags = require(script.Parent.FeatureFlags)

local CharacterMotion = {
	Brainrot = table.freeze({
		TurnRateDegrees = 140, -- max heading change per second while walking
		WanderDistance = 4, -- Reynolds wander circle, projected ahead of the goal direction
		WanderRadius = 1.5,
		WanderJitter = 2.5, -- radians/s random walk of the wander angle
		StopTurnDegrees = 100, -- sharper turns stop and turn on the spot
		StopTurnSeconds = 0.25,
		CornerRadius = 2, -- intermediate route points are rounded inside this radius
		ArriveRadius = 0.75,
		EaseInSeconds = 0.3,
		BrakeSeconds = 0.3,
		EaseOutDistance = 2,
		GroundSmoothSeconds = 0.15,
		GroundMaxLag = 0.4, -- smoothed height never trails the real ground by more
		LegStallSeconds = 2.5, -- no progress for this long: finish the leg in a straight line
		-- Rhythm. Durations stay inside the brief's ranges (walk 2-5 s, pause 1.5-4 s); the
		-- skews lean walks short and pauses long so the stationary share lands near 55-65%.
		WalkMin = 2,
		WalkMax = 5,
		WalkSkew = 2,
		PauseMin = 1.5,
		PauseMax = 4,
		PauseSkew = 2,
		SignatureEveryMin = 3,
		SignatureEveryMax = 4,
		SignatureEveryLegendary = 2,
		-- Notice beat.
		NoticeRadiusFactor = 1.2, -- x AwarenessRadius
		WandererNoticeRadius = 28,
		NoticeSeconds = 0.4,
		NoticeTurnRateDegrees = 360,
		NoticeRearmMargin = 6,
		NoticeCooldownSeconds = 6,
		AlertSeconds = 0.4,
		IdleDebounceSeconds = 0.3,
		LockedIdleDebounceSeconds = 1,
		MovingSpeed = 0.4, -- studs/s above which a creature counts as walking
	}),
	Villager = table.freeze({
		ChaseTurnRateDegrees = 270,
		TurnRateDegrees = 180,
		EaseInSeconds = 0.25,
		EaseOutSeconds = 0.3,
		WindUpBurstSeconds = 0.2, -- acceleration time on the first chase steps
		LeadSeconds = 0.6, -- chase aims at the cart's predicted position, capped
		SeparationDistance = 3,
		GroundSmoothSeconds = 0.15,
		MinAlignedSpeedFactor = 0.15, -- speed kept while turning hard, so no orbiting
		TagMotionSeconds = 0.35,
		MovingSpeed = 0.3,
	}),
}

local brainrots: boolean? = nil
local villagers: boolean? = nil

local function preview(name: string): boolean
	return RunService:IsStudio() and ReplicatedStorage:GetAttribute(name) == true
end

-- Read once per server/client session (flags and the preview attribute are set before Play).
function CharacterMotion.BrainrotsEnabled(): boolean
	if brainrots == nil then
		brainrots = (FeatureFlags :: any).CreatureAnimationEnabled == true
			or preview("CreatureAnimationPreview")
	end
	return brainrots :: boolean
end

function CharacterMotion.VillagersEnabled(): boolean
	if villagers == nil then
		villagers = (FeatureFlags :: any).VillagerAnimationEnabled == true
			or preview("VillagerAnimationPreview")
	end
	return villagers :: boolean
end

-- Village life (C.6): needs villager motion on as well.
--   ReplicatedStorage.VillagerLifePreview = true
local life: boolean? = nil
function CharacterMotion.LifeEnabled(): boolean
	if life == nil then
		life = CharacterMotion.VillagersEnabled()
			and (
				(FeatureFlags :: any).VillagerLifeEnabled == true
				or preview("VillagerLifePreview")
			)
	end
	return life :: boolean
end

-- Stable small integer per id, used to desynchronise loops and pick idle variants.
function CharacterMotion.SeedFor(id: string): number
	local hash = 5381
	for index = 1, #id do
		hash = (hash * 33 + string.byte(id, index)) % 65521
	end
	return hash
end

return table.freeze(CharacterMotion)
