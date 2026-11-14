--!strict
-- The one villager animation set (rig + animation brief v5, C.4). Every villager plays
-- these on the one body (Config/VillagerBody); skins never get their own animations.
-- Owner approved the body and all 24 drafts on 13 November 2026 (round 1).
--
-- `id` is the uploaded Animation asset id, owned by the experience owner. 0 = not uploaded
-- yet: the client must not create an Animator for villagers while any id it needs is 0.
-- Sources: ServerStorage.AnimationSources.VillagerBody (baked from
-- ServerAssets.AnimationAuthoring.VillagerBodyAnimations); upload files in
-- assets/animations/villager_body. `speed` is the ground speed (studs/s) a cycle was
-- authored for, used to match playback speed to movement.
local VillagerAnimations = {
	approved = true,
	approvedOn = "2026-11-13",
	rigVersion = 1,
	animations = table.freeze({
		Idle = { id = 132050449541909, length = 3.6, loop = true, priority = "Idle" },
		Walk = { id = 86867223118398, length = 0.8, loop = true, priority = "Movement", speed = 3 },
		WalkGrumble = {
			id = 71181160016680,
			length = 0.5,
			loop = true,
			priority = "Movement",
			speed = 10,
		},
		Curious = {
			id = 84626233047839,
			length = 1.2,
			loop = true,
			priority = "Movement",
			speed = 13,
		},
		Shout = { id = 113668782692571, length = 0.75, loop = false, priority = "Action" },
		RunSprint = {
			id = 125597764755003,
			length = 0.28,
			loop = true,
			priority = "Movement",
			speed = 30,
		},
		Tired = {
			id = 101903446962005,
			length = 1.12,
			loop = true,
			priority = "Movement",
			speed = 24,
		},
		RunTrot = {
			id = 83549659903296,
			length = 0.42,
			loop = true,
			priority = "Movement",
			speed = 24,
		},
		Alarm = { id = 88911542690824, length = 0.5, loop = true, priority = "Movement" },
		Reach = { id = 87982975493426, length = 0.4, loop = true, priority = "Action" },
		Tag = { id = 140595468415967, length = 0.35, loop = false, priority = "Action" },
		TantrumStomp = { id = 70483592333788, length = 1.5, loop = false, priority = "Action" },
		TantrumFlail = { id = 102427149443125, length = 1.5, loop = false, priority = "Action" },
		TantrumSquawk = { id = 121784781600097, length = 1.5, loop = false, priority = "Action" },
		Wave = { id = 128419404383540, length = 1, loop = false, priority = "Action" },
		Chat = { id = 134283360566165, length = 2.4, loop = true, priority = "Idle" },
		Chop = { id = 109694863738664, length = 1.2, loop = true, priority = "Idle" },
		Sweep = { id = 86336857484721, length = 1.4, loop = true, priority = "Idle" },
		Fish = { id = 129059018929731, length = 3, loop = true, priority = "Idle" },
		Knead = { id = 115046346641207, length = 0.9, loop = true, priority = "Idle" },
		Stir = { id = 139785420975900, length = 1.2, loop = true, priority = "Idle" },
		Skate = {
			id = 130434994898642,
			length = 1.6,
			loop = true,
			priority = "Movement",
			speed = 3,
		},
		Lookout = { id = 102860181644582, length = 3, loop = true, priority = "Idle" },
		Fiddle = { id = 137987512392624, length = 1.6, loop = true, priority = "Idle" },
	}),
}

-- True once every animation has an uploaded id.
function VillagerAnimations.Ready(): boolean
	for _, animation in VillagerAnimations.animations do
		if animation.id == 0 then
			return false
		end
	end
	return true
end

return table.freeze(VillagerAnimations)
