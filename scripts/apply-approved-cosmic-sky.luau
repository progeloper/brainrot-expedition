-- PLUGIN/Edit authoring helper. Uses the same validated owner/descriptor as runtime;
-- respects artist-owned Lighting instances and the existing Rojo exclusions.
local Run = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
assert(Run:IsStudio() and not Run:IsRunning(), "Edit authoring only")
assert(game.PlaceId == 91958083796436 and game.GameId == 10548905405, "Verified Development only")
-- Edit requires can retain cached source. Read the current descriptor through an
-- ephemeral copy, then destroy that copy; no stale draft values become the baseline.
local current = RS.Shared.Config.ApprovedSky:Clone()
current.Name = "ApprovedSky_Authoring_Read_QA"
current.Parent = RS.Shared.Config
local ok, descriptor = pcall(require, current)
current:Destroy()
assert(ok, tostring(descriptor))
local ownerCopy = RS.Shared.Utility.ApprovedEnvironment:Clone()
ownerCopy.Name, ownerCopy.Parent = "ApprovedEnvironment_Authoring_Read_QA", RS.Shared.Utility
local ownerLoaded, Environment = pcall(require, ownerCopy)
ownerCopy:Destroy()
assert(ownerLoaded, tostring(Environment))
local applied, reason = Environment.ApplyBaseline(descriptor)
assert(applied, tostring(reason))
return game:GetService("HttpService"):JSONEncode({
	applied = true,
	version = descriptor.Version,
	artistInstancesReused = true,
	geometryWrites = false,
	audioWrites = false,
	installedReferencesRequireNormalClientFetch = true,
	diagnostics = Environment.GetDiagnostics(),
})
