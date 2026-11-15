--!nocheck
-- Manual Development-only launcher; do not run beside the seven-region harness.
-- First load the exact source of scripts/studio-camp-return-closure.luau into a
-- DISABLED Script named ClosureCampReturnHarnessTemplate in ServerStorage.
-- This launcher clones that one fixture; it does not duplicate its route logic.
assert(game:GetService("RunService"):IsStudio(), "Studio only")
assert(
	require(game.ReplicatedStorage.Shared.Config.Environment).Name == "Development",
	"Development only"
)
for _, candidate in game.ServerScriptService:GetChildren() do
	if
		candidate:IsA("Script")
		and (
			candidate.Name == "ClosureFinalSevenRegions"
			or candidate.Name == "ClosureForestRerun"
			or candidate:GetAttribute("CampReturnClosureHarness") == true
		)
	then
		assert(candidate:GetAttribute("Done") == true, "An existing Camp-return harness is active")
		assert(
			candidate:GetAttribute("PreservedFailureItemId") == nil,
			"Inspect/clean the previously preserved failure through its world owner first"
		)
	end
end
local template = assert(
	game.ServerStorage:FindFirstChild("ClosureCampReturnHarnessTemplate"),
	"Load the disabled current closure fixture template first"
)
assert(template:IsA("Script") and template.Disabled, "Expected a disabled Script template")
assert(
	not game.ServerScriptService:FindFirstChild("ClosureForestRerun"),
	"Archive/remove the prior completed Forest harness before rerunning"
)
local runner = template:Clone()
runner.Name = "ClosureForestRerun"
runner:SetAttribute("ForestOnly", true)
runner:SetAttribute("PreserveOnFailure", true)
runner:SetAttribute("Done", nil)
runner.Disabled = false
runner.Parent = game.ServerScriptService
return runner:GetFullName()
