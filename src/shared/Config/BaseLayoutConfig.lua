--!strict

-- The 36-by-32-stud footprint is a project visual estimate derived from the
-- compact reference layout, not an official published dimension.
local BaseLayoutConfig = {
	STANDARD_ROBLOX_PLAYER_HEIGHT_STUDS = 5.0,
	BRAINROT_TARGET_VISIBLE_HEIGHT_STUDS = 3.5,
	PLATFORM_DIAGONAL_STUDS = 3.0,
	PLATFORM_SIDE_STUDS = 3 / math.sqrt(2),

	BASE_FOOTPRINT_WIDTH_STUDS = 36,
	BASE_FOOTPRINT_DEPTH_STUDS = 32,
	BASE_WALL_HEIGHT_STUDS = 10,
	BASE_WALL_THICKNESS_STUDS = 1,
	PLATFORM_COUNT = 48,
	INITIAL_PLATFORM_COUNT = 12,
	PLATFORMS_PER_FLOOR = 12,
	FLOOR_PITCH_STUDS = 24,
	PLATFORMS_PER_SIDE = 6,
	PLATFORM_ROW_OFFSET_X = 7.25,
	PLATFORM_Z_CENTERS = table.freeze({ -11.25, -6.75, -2.25, 2.25, 6.75, 11.25 }),

	PLAQUE_INWARD_DEPTH_STUDS = 1.75,
	PLAQUE_TANGENTIAL_WIDTH_STUDS = 3.0,
	PLAQUE_HEIGHT_STUDS = 0.20,
	PLAQUE_PLATFORM_GAP_STUDS = 0.25,
	PLAQUE_VISIBLE_RISE_STUDS = 0.03,
	-- The visible plaque remains flush and non-colliding. This invisible vertical
	-- contact envelope reaches ordinary avatar feet, which rest above the floor.
	PLAQUE_TOUCH_HEIGHT_STUDS = 1.0,
	PLAQUE_TOUCH_COOLDOWN_SECONDS = 0.5,
}

return table.freeze(BaseLayoutConfig)
