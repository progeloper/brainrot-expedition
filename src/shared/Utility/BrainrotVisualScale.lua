--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotVisualScale = {}

BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO =
	require(ReplicatedStorage.Shared.Config.PlaytestExact).BrainrotHeightMultiplier
-- Body-only bounds of the project's intended default R15 gameplay rig, measured
-- once with a clean HumanoidDescription (no accessories, Tools or HumanoidRootPart).
BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS =
	require(ReplicatedStorage.Shared.Config.PlaytestMeasurements).ReferenceBodyHeight
BrainrotVisualScale.TARGET_HEIGHT_STUDS = BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS
	* BrainrotVisualScale.BRAINROT_PLAYER_HEIGHT_RATIO
BrainrotVisualScale.TOLERANCE_STUDS = math.max(0.03, BrainrotVisualScale.TARGET_HEIGHT_STUDS * 0.01)

-- Playtest Fixes Part E: size ladder by role (flag-gated; with it off every role keeps the one
-- shared height above). Roles come from the existing ApplyCanonicalScale `context` strings.
--   Wild   world, catch reveal, Index display shot, front team: HeightByRarity x ReferenceBodyHeight
--   Base   base display: ladder, capped to fit 92% of the slot, never below today's height
--   Carry  carried and cargo: today's height (carts, doorways and cargo slots unchanged)
local ROLE_BY_CONTEXT: { [string]: string } = {
	["CreaturePresentation:Awake"] = "Wild",
	["CreaturePresentation:Sleeping"] = "Wild",
	["CreaturePresentation:Deposited"] = "Base",
	["CreaturePresentation:Cart"] = "Carry",
	["CreaturePresentation:Carried"] = "Carry",
	WorldPrepared = "Wild",
	WorldAdopted = "Wild",
	Decoy = "Wild",
	FrontTeam = "Wild",
	CatchReveal = "Wild",
	IndexShot = "Wild",
	BaseDisplay = "Base",
	LightweightVisual = "Carry",
}

function BrainrotVisualScale.Role(context: string?): string?
	return if context then ROLE_BY_CONTEXT[context] else nil
end

local function ladderConfig(): any
	return require(ReplicatedStorage.Shared.Config.PlaytestFixes).SizeLadder
end

local function ladderOn(): boolean
	return require(ReplicatedStorage.Shared.Config.PlaytestFixesFlags).Part("SizeLadder")
end

-- Pure: ladder height (studs) for a rarity.
function BrainrotVisualScale.LadderHeight(rarity: string?): number
	local table_ = ladderConfig().HeightByRarity :: any
	local multiplier = table_[rarity or ""] or table_.Common
	return multiplier * BrainrotVisualScale.PLAYER_REFERENCE_HEIGHT_STUDS
end

-- Pure: base-display height. `aspectX`/`aspectZ` are the model's width/depth per stud of height
-- (scale-invariant). Fits 92% of the slot footprint, never below the floor (today's height).
function BrainrotVisualScale.BaseHeight(
	ladder: number,
	aspectX: number,
	aspectZ: number
): (number, string)
	local c = ladderConfig()
	local maxW = c.SlotFootprint.Width * c.SlotMargin
	local maxD = c.SlotFootprint.Depth * c.SlotMargin
	local height, reason = ladder, "ladder"
	if aspectX > 0 and maxW / aspectX < height then
		height, reason = maxW / aspectX, "width"
	end
	if aspectZ > 0 and maxD / aspectZ < height then
		height, reason = maxD / aspectZ, "depth"
	end
	if height < c.FloorHeight then
		height, reason = c.FloorHeight, "floor"
	end
	return height, reason
end

local function rarityOf(model: Model): string?
	local catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
	local id = model:GetAttribute("BrainrotId")
		or model:GetAttribute("CosmeticSpeciesId")
		or model.Name
	return catalog.GetRarity(id)
end

-- Target height for a model in a role (nil role = today's shared height). Width/depth come from
-- the current visual bounds, so it does not matter what scale the model is at now.
function BrainrotVisualScale.TargetHeightFor(model: Model, role: string?): (number, string)
	if role == nil or role == "Carry" then
		return BrainrotVisualScale.TARGET_HEIGHT_STUDS, "shared"
	end
	local ladder = BrainrotVisualScale.LadderHeight(rarityOf(model))
	if role ~= "Base" then
		return ladder, "ladder"
	end
	local _, size = BrainrotVisualScale.GetVisualBounds(model)
	if not size or size.Y <= 0 then
		return ladder, "ladder"
	end
	return BrainrotVisualScale.BaseHeight(ladder, size.X / size.Y, size.Z / size.Y)
end

-- Wild height for a species id (spawn envelopes and reports).
function BrainrotVisualScale.HeightForSpecies(speciesId: string?, role: string?): number
	if not ladderOn() or role == nil or role == "Carry" then
		return BrainrotVisualScale.TARGET_HEIGHT_STUDS
	end
	local catalog = require(ReplicatedStorage.Shared.Config.BrainrotCatalog)
	return BrainrotVisualScale.LadderHeight(catalog.GetRarity(speciesId))
end

local EXCLUDED_NAME_FRAGMENTS = {
	"hitbox",
	"proxy",
	"helper",
	"prompt",
	"indicator",
	"debug",
	"selection",
	"effect",
	"label",
	"capturednet",
	"carriedbrainrot",
	"cargovisual",
	"stored_",
}

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

-- This predicate deliberately does not depend on CanQuery/CanCollide. Carry,
-- cargo and storage presentations disable those properties after creation, but
-- their visible geometry must still measure identically to the world model.
function BrainrotVisualScale.IsVisualPart(part: BasePart, model: Model): boolean
	if not part:IsDescendantOf(model) or part.Transparency >= 1 then
		return false
	end
	local ancestor: Instance? = part
	while ancestor and ancestor ~= model do
		if ancestor:IsA("Tool") or ancestor:GetAttribute("BrainrotVisualHelper") == true then
			return false
		end
		local name = string.lower(ancestor.Name)
		for _, fragment in EXCLUDED_NAME_FRAGMENTS do
			if string.find(name, fragment, 1, true) then
				return false
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

-- Bounds attributes retain the original art envelope while an invisible server
-- proxy scales through the same native Model:ScaleTo path. Roblox attributes do
-- not scale automatically, so use the clone's native source-scale ratio.
function BrainrotVisualScale.GetProxyBounds(model: Model, kind: string): (CFrame?, Vector3?)
	if model:GetAttribute("CreatureProxy") ~= true then
		return nil, nil
	end
	local frame = model:GetAttribute("Creature" .. kind .. "BoundsFrame")
	local size = model:GetAttribute("Creature" .. kind .. "BoundsSize")
	local sourceScale = model:GetAttribute("CreatureBoundsSourceScale")
	if
		typeof(frame) ~= "CFrame"
		or typeof(size) ~= "Vector3"
		or type(sourceScale) ~= "number"
		or not finite(sourceScale)
		or sourceScale <= 0
	then
		return nil, nil
	end
	local ratio = model:GetScale() / sourceScale
	if not finite(ratio) or ratio <= 0 or size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return nil, nil
	end
	return CFrame.new(frame.Position * ratio) * frame.Rotation, size * ratio
end

-- Returns visual bounds in model-pivot space so callers can position the model
-- after scaling without allowing invisible gameplay geometry to affect contact.
function BrainrotVisualScale.GetVisualBounds(model: Model): (CFrame?, Vector3?, string?)
	local proxyFrame, proxySize = BrainrotVisualScale.GetProxyBounds(model, "Visual")
	if proxyFrame and proxySize then
		return proxyFrame, proxySize, nil
	end
	local metadata = require(ReplicatedStorage.Shared.Config.PlaytestMeasurements)
	local id = model:GetAttribute("BrainrotId")
		or model:GetAttribute("CosmeticSpeciesId")
		or model.Name
	-- Voxel V4 models measure from their own data, never a legacy sculpture's.
	local body = require(ReplicatedStorage.Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(
		model,
		metadata.Species[id]
	)
	if body and body.surfaceVerified then
		local ratio = model:GetScale() / body.s0
		return CFrame.new(
			Vector3.new(
				(body.xmin + body.xmax) / 2,
				(body.ymin + body.ymax) / 2,
				(body.zmin + body.zmax) / 2
			) * ratio
		),
			Vector3.new(body.xmax - body.xmin, body.ymax - body.ymin, body.zmax - body.zmin) * ratio,
			nil
	end
	local pivot = model:GetPivot()
	local low = Vector3.one * math.huge
	local high = Vector3.one * -math.huge
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and BrainrotVisualScale.IsVisualPart(descendant, model) then
			count += 1
			local frame = pivot:ToObjectSpace(descendant.CFrame)
			local half = descendant.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame * (half * Vector3.new(x, y, z))
						low = low:Min(point)
						high = high:Max(point)
					end
				end
			end
		end
	end
	if count == 0 then
		return nil, nil, "NO_VISIBLE_PARTS"
	end
	local size = high - low
	if not finite(size.X) or not finite(size.Y) or not finite(size.Z) or size.Y <= 0.0001 then
		return nil, nil, "INVALID_VISIBLE_BOUNDS"
	end
	return CFrame.new((low + high) / 2), size, nil
end

function BrainrotVisualScale.GetVisualHeight(model: Model): (number?, string?)
	local _, size, reason = BrainrotVisualScale.GetVisualBounds(model)
	if not size then
		return nil, reason
	end
	return size.Y, nil
end

function BrainrotVisualScale.GetCanonicalModelScale(model: Model): (number?, string?)
	local height, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not height then
		return nil, reason
	end
	local currentScale = model:GetScale()
	local scale = currentScale * (BrainrotVisualScale.TARGET_HEIGHT_STUDS / height)
	if not finite(scale) or scale <= 0 then
		return nil, "INVALID_CANONICAL_SCALE"
	end
	return scale, nil
end

-- Absolute and idempotent: correction is always derived from current visible
-- height, never from a previous lifecycle multiplier.
function BrainrotVisualScale.ApplyCanonicalScale(
	model: Model,
	context: string?
): (boolean, number?, string?)
	local metadata = require(ReplicatedStorage.Shared.Config.PlaytestMeasurements)
	local role = if ladderOn() then BrainrotVisualScale.Role(context) else nil
	local targetHeight = BrainrotVisualScale.TargetHeightFor(model, role)
	local ratio = targetHeight / BrainrotVisualScale.TARGET_HEIGHT_STUDS
	model:SetAttribute("PlaytestSizeRatio", if math.abs(ratio - 1) > 1e-4 then ratio else nil)
	model:SetAttribute("PlaytestSizeRole", role)
	local species = model:GetAttribute("BrainrotId") or model.Name
	local exactMeasurement =
		require(ReplicatedStorage.Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(
			model,
			metadata.Species[species]
		)
	if
		exactMeasurement
		and exactMeasurement.verified
		and type(metadata.ReferenceBodyHeight) == "number"
	then
		local multiplier =
			require(ReplicatedStorage.Shared.Config.PlaytestExact).BrainrotHeightMultiplier
		if role then
			multiplier = targetHeight / metadata.ReferenceBodyHeight
		end
		local accepted, target =
			require(ReplicatedStorage.Shared.Utility.ExactBodyPlacement).Normalize(
				model,
				exactMeasurement,
				metadata.ReferenceBodyHeight,
				multiplier
			)
		if not accepted then
			return false, nil, target
		end
		return true, multiplier * metadata.ReferenceBodyHeight, nil
	end
	model:SetAttribute("ExactScaleStatus", metadata.ReferenceRigStatus)

	local currentHeight, reason = BrainrotVisualScale.GetVisualHeight(model)
	if not currentHeight then
		return false, nil, reason
	end
	local currentScale = model:GetScale()
	local correction = targetHeight / currentHeight
	local newScale = currentScale * correction
	if
		not finite(currentScale)
		or currentScale <= 0
		or not finite(correction)
		or correction <= 0
		or not finite(newScale)
		or newScale <= 0
	then
		return false, nil, "INVALID_SCALE"
	end
	model:ScaleTo(newScale)
	local measured, measureReason = BrainrotVisualScale.GetVisualHeight(model)
	if not measured then
		return false, nil, measureReason
	end
	if ReplicatedStorage:GetAttribute("BrainrotScaleTrace") == true then
		print(
			string.format(
				"[BrainrotScale] context=%s model=%s item=%s before=%.6f target=%.6f correction=%.6f scale=%.6f after=%.6f",
				context or "unspecified",
				model:GetFullName(),
				tostring(model:GetAttribute("ItemId")),
				currentHeight,
				targetHeight,
				correction,
				model:GetScale(),
				measured
			)
		)
	end
	if
		math.abs(measured - targetHeight)
		> math.max(BrainrotVisualScale.TOLERANCE_STUDS, targetHeight * 0.01)
	then
		return false, measured, "TARGET_NOT_REACHED"
	end
	return true, measured, nil
end

return table.freeze(BrainrotVisualScale)
