--!strict
-- All six gate foot centres are 30 studs apart, each foot spans 6.
-- This proves the gate straight aperture; swept route turns remain separate.
return table.freeze({
	RiftSource = {
		SpawnLift = 70,
		SecondaryScale = 0.36,
		LeftX = -34,
		RightX = 32,
		Ymin = -3,
		Ymax = 6,
		Zmin = -6,
		Zmax = 6,
		Source = "Source_Before.zip Phase12PresentationController.beginSky / SpaceRiftRenderer.Create.Start",
	},

	FrontHitch = {
		CrossSection = 0.07,
		BodyHeightFraction = 0.55 / 3,
		EdgeOffset = 0.06,
		Colour = Color3.fromRGB(102, 65, 33),
		Material = Enum.Material.SmoothPlastic,
		Source = "Source_Before.zip ChariotFormationController.tracePart/update: section .07, rise .55 for fitted height3",
	},
	PreviousCarryTargetHeight = 5.457267761230469 * 0.64,
	PreviousCarryOffset = Vector3.new(1.75, 0.75, -3.5),
	SeatedBodyRearFromSeat = 0.8829830884933472,
	SeatedSource = "phase14/evidence/variable_rig/20261023_native_fit1/baseline/Native_Seated_Measurements.json",
	Route = table.freeze({
		MinimumStraightClearWidth = 11.58880615234375,
		GateClearWidth = 24,
		SamplePosition = Vector3.new(402.4392395019531, 3.4478530883789064, -284.2055969238281),
		SampleSideAxis = Vector3.zAxis,
		SampleNearestSideDistance = 5.794403076171875,
		Source = "Centred Volcano approach at Paths.Surface_0032: native ray to EV2_Run_08_Cliff_01 collider=5.794403076171875; gate foot aperture30-6=24. No route geometry changed.",
		TurnStatus = "NOT_VERIFIED",
	}),
})
