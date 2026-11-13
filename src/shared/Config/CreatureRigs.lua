--!strict
-- Body-plan archetype per species (rig + animation brief v5, B.1). Rigs in an archetype
-- share joint names and hierarchy, so a new species can start from an approved one.
-- The joints themselves live in each species' Voxel V4 data (Config/VoxelCreatures/<id>.rig,
-- planned by tools/voxel_v4/rig.js). Species are added here as they are classified.
--
-- Archetypes: Biped, Quadruped, Hopper, Flyer, VehicleHybrid.
return table.freeze({
	BRT_019 = table.freeze({
		archetype = "VehicleHybrid",
		rigVersion = 2,
		-- Motor6D chain, parent -> child (bone part names carry a "Rig" prefix).
		joints = table.freeze({
			"Root>Torso",
			"Torso>Neck",
			"Neck>Head",
			"Torso>RightLeg",
			"Torso>LeftLeg",
			"Torso>ToiletLid",
		}),
		signatureProp = "ToiletLid",
		notes = "Bogies are rigid boxes on the chassis (no wheel joints). Feet hinge at the heel and only lift.",
	}),
	BRT_011 = table.freeze({
		archetype = "Quadruped",
		rigVersion = 1,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Head",
			"Torso>FrontRightLeg",
			"Torso>FrontLeftLeg",
			"Torso>BackRightLeg",
			"Torso>BackLeftLeg",
			"Torso>Tail",
		}),
		notes = "First quadruped; the base for the others (AnimationAuthoring.Archetypes.Quadruped). Jaw is rigid with the head.",
	}),
	BRT_013 = table.freeze({
		archetype = "Biped",
		rigVersion = 2,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Neck",
			"Neck>Head",
			"Torso>RightLeg",
			"Torso>LeftLeg",
			"Torso>Tail",
		}),
		notes = "First biped; the base for the others (AnimationAuthoring.Archetypes.Biped). The piano lid is rigid: the neck passes through it.",
	}),
	BRT_001 = table.freeze({
		archetype = "Quadruped",
		rigVersion = 1,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Head",
			"Torso>FrontRightLeg",
			"Torso>FrontLeftLeg",
			"Torso>BackRightLeg",
			"Torso>BackLeftLeg",
			"Torso>Tail",
		}),
		notes = "Upright tail: it sways and leans instead of lifting.",
	}),
	BRT_002 = table.freeze({
		archetype = "Hopper",
		rigVersion = 1,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Head",
			"Torso>RightLeg",
			"Torso>LeftLeg",
			"Torso>RightArm",
			"Torso>LeftArm",
		}),
		notes = "First hopper; the base for the others (AnimationAuthoring.Archetypes.Hopper). Baked through the floor clamp: the belly rests on the ground.",
	}),
	BRT_003 = table.freeze({
		archetype = "Quadruped",
		rigVersion = 2,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Head",
			"Torso>FrontRightLeg",
			"Torso>FrontLeftLeg",
			"Torso>BackRightLeg",
			"Torso>BackLeftLeg",
			"Head>Cup",
		}),
		notes = "No tail. The cappuccino sits on its own Cup bone (signature prop) and is balanced against the head and body in every clip.",
	}),
	BRT_004 = table.freeze({
		archetype = "Biped",
		rigVersion = 2,
		joints = table.freeze({
			"Root>Torso",
			"Torso>RightLeg",
			"Torso>LeftLeg",
			"Torso>RightArm",
			"Torso>LeftArm",
			"Torso>Tutu",
		}),
		notes = "Face on the body: no head or neck joint. The tutu sits on its own bone (signature prop). Set written for her, not from a shared base.",
	}),
	BRT_005 = table.freeze({
		archetype = "Flyer",
		rigVersion = 1,
		joints = table.freeze({
			"Root>Torso",
			"Torso>Head",
			"Torso>RightWing",
			"Torso>LeftWing",
			"Torso>Tail",
			"Torso>RightLeg",
			"Torso>LeftLeg",
		}),
		notes = "First flyer; the base for the others (AnimationAuthoring.Archetypes.Flyer). Wings are rigid spread plates: they hang, they do not fold. Flees in the air (visual only).",
	}),
})
