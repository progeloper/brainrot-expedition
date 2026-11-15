--!strict
local C = require(script.Parent.PlaytestExact)
local Afternoon = require(script.Parent.AfternoonRepair)
local Deployment = require(script.Parent.Deployment)
return table.freeze({
	Enabled = true,
	Version = Deployment.ReleaseId,
	SkyMode = C.Sky.Mode,
	Faces = Afternoon.Sky,
	SkyboxOrientation = Vector3.zero,
	SkySettings = Afternoon.SkySettings,
	OwnedNames = table.freeze({
		Sky = "Sky",
		Atmosphere = "BR_MapAtmosphere",
		BloomEffect = "BR_MapBloom",
		ColorCorrectionEffect = "BR_MapColorCorrection",
		SunRaysEffect = "SunRays",
		DepthOfFieldEffect = "DepthOfField",
		BlurEffect = "PlaytestBaselineBlur",
	}),
	Lighting = C.Lighting,
	Atmosphere = C.Atmosphere,
	BloomEffect = C.BloomEffect,
	ColorCorrectionEffect = C.ColorCorrectionEffect,
	SunRaysEffect = table.freeze({ Enabled = false, Intensity = 0, Spread = 0.1 }),
	DepthOfFieldEffect = table.freeze({
		Enabled = false,
		FarIntensity = 0.1,
		NearIntensity = 0.75,
		FocusDistance = 0.05,
		InFocusRadius = 30,
	}),
	BlurEffect = table.freeze({ Enabled = false }),
})
