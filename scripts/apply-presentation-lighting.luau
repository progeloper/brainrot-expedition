-- Development edit-time authoring only. Not part of Bootstrap or the save loop.
assert(not game:GetService("RunService"):IsRunning(), "Apply in Edit mode")
assert(game.PlaceId == 91958083796436, "Development place only")
local lighting = game:GetService("Lighting")
local corrections = {}
for _, effect in lighting:GetChildren() do
	if effect:IsA("ColorCorrectionEffect") then
		table.insert(corrections, effect)
	end
end
assert(#corrections <= 1, "Inspect duplicate ColorCorrectionEffects before applying")
local bloom = lighting:FindFirstChild("Bloom")
assert(bloom and bloom:IsA("BloomEffect"), "Inspect the existing Bloom effect")
lighting.LightingStyle = Enum.LightingStyle.Soft
lighting.GlobalShadows = true
lighting.PrioritizeLightingQuality = false
lighting.ClockTime = 14
lighting.ExposureCompensation = 0.05
local correction = corrections[1] or Instance.new("ColorCorrectionEffect")
correction.Name = "GameplayColorCorrection"
correction.Enabled = true
correction.Brightness = 0.02
correction.Contrast = 0.08
correction.Saturation = 0.15
correction.TintColor = Color3.new(1, 1, 1)
correction.Parent = lighting
bloom.Intensity = 0.075
bloom.Size = 15
bloom.Threshold = 1.2
return "Applied requested presentation candidate; motion/performance acceptance is separate."
