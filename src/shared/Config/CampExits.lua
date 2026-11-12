--!strict
-- Drive-and-Hunt launch lanes. MEASURED in Play on 12 Nov 2026 with the starter cart (CRT_001)
-- by DriveAndHuntService's Studio hook (ServerStorage.DriveAndHuntQA -> "MeasureLanes"): a lane
-- every ~40 studs along each camp edge, with cart positions 12 / 18 / 24 studs outside the edge,
-- facing outward. A position is kept only where the ground is drivable (slope <= 20 degrees), at
-- camp level, and the cart's full collider envelope passed CartLocalPlacement.ValidateAssignedSpawn.
-- Dropped: 9 lanes on the West (Forest cliffs) and East (Volcano rock) edges that have no clear,
-- level position. The server re-checks every position at launch, so a lane that is blocked later
-- (another cart, a villager, new scenery) is skipped rather than used. Re-measure after map edits.
-- View pass (12 Nov 2026): forest and jungle trees do not collide and cannot be queried, so the
-- cart camera (28 studs behind, 9 up) cannot avoid them. Positions whose camera line or cart
-- footprint passed through such scenery were removed; seven lanes with no clear position
-- (North_03, South_01, South_05, East_01, East_02, East_04, East_08) were moved 6-14 studs along
-- the edge. The moved positions passed a ground check but only North_03 was launch-tested.
export type Lane = { exit: string, region: string, normal: Vector3, points: { Vector3 } }

local function lane(exit: string, region: string, nx: number, nz: number, points: { Vector3 }): Lane
	return table.freeze({ exit = exit, region = region, normal = Vector3.new(nx, 0, nz), points = table.freeze(points) })
end

return table.freeze({
	MeasuredWith = "CRT_001",
	Lanes = table.freeze({
		lane("North_01", "REGION_FOREST", 0, -1, { Vector3.new(-243.0, -0.48, -306.0), Vector3.new(-243.0, -0.48, -312.0) }),
		lane("North_02", "REGION_FOREST", 0, -1, { Vector3.new(-202.3, -0.48, -306.0), Vector3.new(-202.3, -0.48, -312.0), Vector3.new(-202.3, -0.48, -318.0) }),
		lane("North_03", "REGION_FOREST", 0, -1, { Vector3.new(-171.5, -0.48, -306.0) }),
		lane("North_04", "REGION_FOREST", 0, -1, { Vector3.new(-120.8, -0.48, -306.0), Vector3.new(-120.8, -0.48, -312.0) }),
		lane("North_05", "REGION_FOREST", 0, -1, { Vector3.new(-80.1, -0.48, -306.0), Vector3.new(-80.1, -0.48, -312.0) }),
		lane("North_06", "REGION_FOREST", 0, -1, { Vector3.new(-39.4, -0.48, -306.0), Vector3.new(-39.4, -0.48, -312.0), Vector3.new(-39.4, -0.48, -318.0) }),
		lane("North_07", "REGION_FOREST", 0, -1, { Vector3.new(1.4, -0.48, -306.0), Vector3.new(1.4, -0.48, -312.0) }),
		lane("North_08", "REGION_FOREST", 0, -1, { Vector3.new(42.1, -0.48, -306.0), Vector3.new(42.1, -0.48, -312.0) }),
		lane("North_09", "REGION_FOREST", 0, -1, { Vector3.new(82.8, -0.48, -306.0), Vector3.new(82.8, -0.48, -312.0), Vector3.new(82.8, -0.48, -318.0) }),
		lane("North_10", "REGION_FOREST", 0, -1, { Vector3.new(123.5, -0.48, -306.0), Vector3.new(123.5, -0.48, -312.0), Vector3.new(123.5, -0.48, -318.0) }),
		lane("North_11", "REGION_FOREST", 0, -1, { Vector3.new(164.3, -0.48, -306.0) }),
		lane("North_12", "REGION_FOREST", 0, -1, { Vector3.new(205.0, -0.48, -306.0), Vector3.new(205.0, -0.48, -312.0), Vector3.new(205.0, -0.48, -318.0) }),
		lane("South_01", "REGION_JUNGLE", 0, 1, { Vector3.new(-257.0, -0.48, 214.0), Vector3.new(-257.0, -0.48, 220.0), Vector3.new(-257.0, -0.48, 226.0) }),
		lane("South_02", "REGION_JUNGLE", 0, 1, { Vector3.new(-202.3, -0.48, 214.0), Vector3.new(-202.3, -0.48, 220.0), Vector3.new(-202.3, -0.48, 226.0) }),
		lane("South_03", "REGION_JUNGLE", 0, 1, { Vector3.new(-161.5, -0.48, 214.0), Vector3.new(-161.5, -0.48, 220.0), Vector3.new(-161.5, -0.48, 226.0) }),
		lane("South_04", "REGION_JUNGLE", 0, 1, { Vector3.new(-120.8, -0.48, 214.0), Vector3.new(-120.8, -0.48, 220.0), Vector3.new(-120.8, -0.48, 226.0) }),
		lane("South_05", "REGION_JUNGLE", 0, 1, { Vector3.new(-74.1, -0.48, 220.0), Vector3.new(-74.1, -0.48, 226.0) }),
		lane("South_06", "REGION_JUNGLE", 0, 1, { Vector3.new(-39.4, -0.48, 226.0) }),
		lane("South_07", "REGION_JUNGLE", 0, 1, { Vector3.new(1.4, -0.48, 214.0), Vector3.new(1.4, -0.48, 220.0) }),
		lane("South_08", "REGION_JUNGLE", 0, 1, { Vector3.new(42.1, -0.48, 226.0) }),
		lane("South_09", "REGION_JUNGLE", 0, 1, { Vector3.new(82.8, -0.48, 226.0) }),
		lane("South_10", "REGION_JUNGLE", 0, 1, { Vector3.new(123.5, -0.48, 220.0) }),
		lane("South_11", "REGION_JUNGLE", 0, 1, { Vector3.new(164.3, -0.48, 214.0), Vector3.new(164.3, -0.48, 220.0), Vector3.new(164.3, -0.48, 226.0) }),
		lane("South_12", "REGION_JUNGLE", 0, 1, { Vector3.new(205.0, -0.48, 226.0) }),
		lane("West_01", "REGION_FOREST", -1, 0, { Vector3.new(-279.0, -0.48, -270.0), Vector3.new(-285.0, -0.48, -270.0), Vector3.new(-291.0, -0.48, -270.0) }),
		lane("West_02", "REGION_FOREST", -1, 0, { Vector3.new(-279.0, -0.48, -229.3), Vector3.new(-285.0, -0.48, -229.3), Vector3.new(-291.0, -0.48, -229.3) }),
		lane("West_08", "REGION_FOREST", -1, 0, { Vector3.new(-279.0, -0.48, 15.1) }),
		lane("East_01", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, -264.0), Vector3.new(247.0, -0.48, -264.0), Vector3.new(253.0, -0.48, -264.0) }),
		lane("East_02", "REGION_VOLCANO", 1, 0, { Vector3.new(253.0, -0.48, -235.3) }),
		lane("East_03", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, -188.5), Vector3.new(247.0, -0.48, -188.5) }),
		lane("East_04", "REGION_VOLCANO", 1, 0, { Vector3.new(247.0, -0.48, -157.8), Vector3.new(253.0, -0.48, -157.8) }),
		lane("East_05", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, -107.1), Vector3.new(247.0, -0.48, -107.1) }),
		lane("East_08", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, 25.1), Vector3.new(247.0, -0.48, 25.1), Vector3.new(253.0, -0.48, 25.1) }),
		lane("East_09", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, 55.8), Vector3.new(247.0, -0.48, 55.8) }),
		lane("East_12", "REGION_VOLCANO", 1, 0, { Vector3.new(241.0, -0.48, 178.0), Vector3.new(247.0, -0.48, 178.0), Vector3.new(253.0, -0.48, 178.0) }),
	}),
})
