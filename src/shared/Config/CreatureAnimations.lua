--!strict
-- Approved brainrot animation sets, one per species (rig + animation brief v5, B.3 / E.4).
-- A species gets an Animator only when it is listed here with approved = true AND every id
-- is uploaded; otherwise it renders exactly as before, even with CreatureAnimationEnabled on.
--
-- `id` is the uploaded Animation asset id, owned by the experience owner (0 = not uploaded
-- yet). `speed` is the ground speed in studs/s a cycle was authored for at gameplay scale.
-- Sources: ServerStorage.AnimationSources.Brainrots.<id>, baked from
-- ServerAssets.AnimationAuthoring.Brainrots.<id>; upload files in assets/animations/brainrots.
local CreatureAnimations: { [string]: any } = {
	BRT_019 = table.freeze({
		approved = true,
		approvedOn = "2026-11-13",
		animations = table.freeze({
			IdleDisplay = { id = 0, length = 3, loop = true, priority = "Idle" },
			IdleWild = { id = 0, length = 3.6, loop = true, priority = "Idle" },
			IdleWild2 = { id = 0, length = 2, loop = false, priority = "Idle" },
			Walk = { id = 0, length = 0.6, loop = true, priority = "Movement", speed = 7.26 },
			Run = { id = 0, length = 0.36, loop = true, priority = "Movement", speed = 13 },
			Alert = { id = 0, length = 0.4, loop = false, priority = "Action" },
			Hit = { id = 0, length = 0.25, loop = false, priority = "Action" },
			Carried = { id = 0, length = 1, loop = true, priority = "Movement" },
			Sleep = { id = 0, length = 4, loop = true, priority = "Idle" },
			Celebrate = { id = 0, length = 1.2, loop = false, priority = "Action" },
			Signature = { id = 0, length = 1.4, loop = false, priority = "Action" },
		}),
	}),
	BRT_011 = table.freeze({
		approved = true,
		approvedOn = "2026-11-13",
		animations = table.freeze({
			IdleDisplay = { id = 0, length = 3, loop = true, priority = "Idle" },
			IdleWild = { id = 0, length = 3.6, loop = true, priority = "Idle" },
			IdleWild2 = { id = 0, length = 2, loop = false, priority = "Idle" },
			Walk = { id = 0, length = 0.7, loop = true, priority = "Movement", speed = 6.6 },
			Run = { id = 0, length = 0.34, loop = true, priority = "Movement", speed = 11 },
			Alert = { id = 0, length = 0.4, loop = false, priority = "Action" },
			Hit = { id = 0, length = 0.25, loop = false, priority = "Action" },
			Carried = { id = 0, length = 1, loop = true, priority = "Movement" },
			Sleep = { id = 0, length = 4, loop = true, priority = "Idle" },
			Celebrate = { id = 0, length = 1.2, loop = false, priority = "Action" },
			Signature = { id = 0, length = 1.6, loop = false, priority = "Action" },
		}),
	}),
	BRT_013 = table.freeze({
		approved = true,
		approvedOn = "2026-11-13",
		animations = table.freeze({
			IdleDisplay = { id = 0, length = 3, loop = true, priority = "Idle" },
			IdleWild = { id = 0, length = 3.6, loop = true, priority = "Idle" },
			IdleWild2 = { id = 0, length = 2, loop = false, priority = "Idle" },
			Walk = { id = 0, length = 0.7, loop = true, priority = "Movement", speed = 6.6 },
			Run = { id = 0, length = 0.36, loop = true, priority = "Movement", speed = 11 },
			Alert = { id = 0, length = 0.4, loop = false, priority = "Action" },
			Hit = { id = 0, length = 0.25, loop = false, priority = "Action" },
			Carried = { id = 0, length = 1, loop = true, priority = "Movement" },
			Sleep = { id = 0, length = 4, loop = true, priority = "Idle" },
			Celebrate = { id = 0, length = 1.2, loop = false, priority = "Action" },
			Signature = { id = 0, length = 1.6, loop = false, priority = "Action" },
		}),
	}),
	BRT_001 = table.freeze({
		approved = true,
		approvedOn = "2026-11-13",
		animations = table.freeze({
			IdleDisplay = { id = 0, length = 3, loop = true, priority = "Idle" },
			IdleWild = { id = 0, length = 3.6, loop = true, priority = "Idle" },
			IdleWild2 = { id = 0, length = 2, loop = false, priority = "Idle" },
			Walk = { id = 0, length = 0.7, loop = true, priority = "Movement", speed = 6 },
			Run = { id = 0, length = 0.34, loop = true, priority = "Movement", speed = 10.8 },
			Alert = { id = 0, length = 0.4, loop = false, priority = "Action" },
			Hit = { id = 0, length = 0.25, loop = false, priority = "Action" },
			Carried = { id = 0, length = 1, loop = true, priority = "Movement" },
			Sleep = { id = 0, length = 4, loop = true, priority = "Idle" },
			Celebrate = { id = 0, length = 1.2, loop = false, priority = "Action" },
			Signature = { id = 0, length = 1.6, loop = false, priority = "Action" },
		}),
	}),
}

local Module = { Species = table.freeze(CreatureAnimations) }

-- True when a species is approved and every animation has an uploaded id.
function Module.Ready(speciesId: string): boolean
	local entry = CreatureAnimations[speciesId]
	if not entry or entry.approved ~= true then
		return false
	end
	for _, animation in entry.animations do
		if animation.id == 0 then
			return false
		end
	end
	return true
end

return table.freeze(Module)
