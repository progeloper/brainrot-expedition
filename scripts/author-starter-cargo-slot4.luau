--!strict

-- Run in Development Studio Edit mode. The default performs an off-world
-- preview only. Inspect the returned normalized visual bounds and the live
-- four-cargo presentation before changing APPLY_REVIEWED_CANDIDATE to true.
-- This authors one optional position; it never grants Cargo I or changes the
-- three-slot baseline. Re-running after a successful application is a no-op.
local APPLY_REVIEWED_CANDIDATE = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Validator = require(ReplicatedStorage.Shared.Validation.CartAssetValidator)
local AssemblyValidator = require(ReplicatedStorage.Shared.Validation.CartAssemblyValidator)
local Scale = require(ReplicatedStorage.Shared.Utility.BrainrotVisualScale)

assert(RunService:IsStudio() and not RunService:IsRunning(), "Studio Edit mode required")
assert(Environment.Name == "Development", "Development environment required")
local assets = assert(ReplicatedStorage:FindFirstChild("StudioAssets"))
local source = assert(assert(assets:FindFirstChild("Carts")):FindFirstChild("ScrapChariot"))
assert(
	source:IsA("Model") and source:GetAttribute("CartId") == "CRT_001",
	"Expected CRT_001 source"
)
local root = assert(source:FindFirstChild("Root"))
assert(root:IsA("BasePart") and source.PrimaryPart == root, "Expected primary Root BasePart")
Validator.AssertValid(source)

local expected = {
	Vector3.new(-2, 2, 3.5),
	Vector3.new(0, 2, 3.5),
	Vector3.new(2, 2, 3.5),
}
local sourceSlots = assert(Validator.GetCargoSlotMap(source, 3))
for index, slot in sourceSlots do
	local localFrame = root.CFrame:ToObjectSpace(slot.Part.CFrame)
	assert(
		(localFrame.Position - expected[index]).Magnitude < 0.001,
		"Unexpected starter slot formation"
	)
	assert(slot.Part.Size == Vector3.one and slot.Part.Transparency == 1, "Unexpected anchor shape")
	assert(slot.Attachment.CFrame == CFrame.identity, "Unexpected cargo attachment offset")
	assert(localFrame.Rotation == CFrame.identity, "Unexpected cargo anchor orientation")
end
local rowSpacing = (expected[2] - expected[1]).Magnitude
assert(
	math.abs(rowSpacing - (expected[3] - expected[2]).Magnitude) < 0.001,
	"Unequal existing spacing"
)
local candidateFrame = sourceSlots[2].Part.CFrame * CFrame.new(0, 0, rowSpacing)
local existing = source.CargoSlots:FindFirstChild("Slot4")
if existing then
	local slot = assert(Validator.GetCargoSlot(source, 4))
	assert(
		(slot.Part.CFrame.Position - candidateFrame.Position).Magnitude < 0.001,
		"Slot4 already exists at another authored position; preserve it for review"
	)
	assert(Validator.ValidateCargoLayout(source, 4).status == "Ready", "Existing Slot4 is invalid")
	AssemblyValidator.AssertValid(source, { Stage = "Static" })
	return { status = "ALREADY_AUTHORED", source = source:GetFullName(), changed = false }
end
assert(#source.CargoSlots:GetChildren() == 3, "Unexpected extra cargo source children")

-- Build and validate an isolated candidate first. Nothing is parented into the
-- live world, and all source objects and existing slot transforms stay intact.
local candidate = source:Clone()
local fourth: BasePart? = nil
local report: any = nil
local ok, failure = xpcall(function()
	local clonedRoot = candidate.Root :: BasePart
	local clonedSlots = assert(Validator.GetCargoSlotMap(candidate, 3))
	fourth = clonedSlots[2].Part:Clone()
	local slot = fourth :: BasePart
	slot.Name = "Slot4"
	slot.CFrame = clonedSlots[2].Part.CFrame * CFrame.new(0, 0, rowSpacing)
	local weld = slot:FindFirstChild("RootWeld")
	assert(weld and weld:IsA("WeldConstraint"), "Slot2 must use the existing RootWeld contract")
	weld.Part0, weld.Part1 = clonedRoot, slot
	slot.Parent = candidate.CargoSlots
	Validator.AssertValid(candidate)
	AssemblyValidator.AssertValid(candidate, { Stage = "Static" })
	local layout = Validator.ValidateCargoLayout(candidate, 4)
	assert(layout.status == "Ready", table.concat(layout.errors, "; "))
	local rows = {}
	local prototypes = assert(assets:FindFirstChild("Brainrots"))
	for index, id in { "BRT_007", "BRT_010", "BRT_016", "BRT_028" } do
		local template = assert(prototypes:FindFirstChild(id), "Missing exact visual " .. id)
		assert(template:IsA("Model"))
		local visual = template:Clone()
		local scaled, _, reason = Scale.ApplyCanonicalScale(visual, "Slot4AuthoringPreview")
		if not scaled then
			visual:Destroy()
			error(reason or "Canonical cargo scale failed")
		end
		-- Production mountCargoVisual uses this exact pivot placement.
		visual:PivotTo(layout.positions[index].Attachment.WorldCFrame)
		local bounds, size = Scale.GetVisualBounds(visual)
		assert(bounds and size, "Canonical visual bounds are unavailable")
		table.insert(rows, {
			id = id,
			slot = "Slot" .. index,
			rootLocalBounds = clonedRoot.CFrame:ToObjectSpace(visual:GetPivot() * bounds),
			size = size,
		})
		visual:Destroy()
	end
	report = {
		status = "PREVIEW_REQUIRES_FIT_REVIEW",
		source = source:GetFullName(),
		candidateRootLocalFrame = clonedRoot.CFrame:ToObjectSpace(slot.CFrame),
		layoutReady = true,
		assemblyReady = true,
		visualBounds = rows,
		changed = false,
	}
	if APPLY_REVIEWED_CANDIDATE then
		-- Only the reviewed fourth anchor crosses from staging into the source.
		slot.Parent = nil
		weld.Part0, weld.Part1 = root, slot
		slot.Parent = source.CargoSlots
		local valid, validationError = pcall(function()
			Validator.AssertValid(source)
			AssemblyValidator.AssertValid(source, { Stage = "Static" })
			assert(
				Validator.ValidateCargoLayout(source, 4).status == "Ready",
				"Authored layout invalid"
			)
		end)
		if not valid then
			slot:Destroy()
			error(validationError)
		end
		report.status, report.changed = "AUTHORED_SLOT4", true
	end
end, debug.traceback)
candidate:Destroy()
assert(ok, failure)
return report
