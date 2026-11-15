--!nocheck
local RS = game:GetService("ReplicatedStorage")
local C = require(RS.Shared.Config.PlaytestExact)
local M = require(RS.Shared.Config.PlaytestMeasurements)
local G = require(RS.Shared.Utility.WorldPresentationGeometry)
local API = {}
local function corners(frame, size)
	local out = {}
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(out, frame * Vector3.new(x * size.X / 2, 0, z * size.Z / 2))
		end
	end
	return out
end
local function rectangle(points, frame)
	local low = Vector3.one * math.huge
	local high = -low
	for _, p in points do
		local q = frame:PointToObjectSpace(p)
		low = low:Min(q)
		high = high:Max(q)
	end
	return low, high
end
function API.Place(display, slot)
	local marker = slot.Marker
	local pad = if marker:IsA("Attachment") then marker.Parent else marker
	local support = if marker:IsA("Attachment") then marker.WorldCFrame else marker.CFrame
	local meta = require(game:GetService("ReplicatedStorage").Shared.Utility.VoxelCreatureRegistry).ModelMeasurement(display, M.Species[display:GetAttribute("BrainrotId")])
	assert(meta, "Unmeasured display")
	local base = pad.Parent
	-- Native pad edges define protected aisle/wall boundaries; adjacent centres
	-- tighten the row extent at the exact midplane. No invented authoring marker.
	local half = pad:GetAttribute("PresentationAuthoredPadSize") or pad.Size
	pad:SetAttribute("PresentationAuthoredPadSize", half)
	local foundation = assert(base:FindFirstChild("Foundation"), "Missing native floor bounds")
	local floorLow, floorHigh = rectangle(corners(foundation.CFrame, foundation.Size), pad.CFrame)
	local cellLowX, cellHighX = floorLow.X, floorHigh.X
	local cellLowZ, cellHighZ = -half.Z / 2, half.Z / 2
	local joins = require(RS.Shared.Config.BaseJoinMetadata)
	local primary = base:FindFirstChild("Primary")
	if primary and primary:IsA("BasePart") then
		local shell = primary.CFrame * CFrame.new(0, -joins.PrimaryCentreY, 0)
		local localPad = shell:PointToObjectSpace(pad.Position)
		local inner = math.huge
		for _, band in joins.Bands do
			local slope = (band.r1 - band.r0) / (band.y1 - band.y0)
			local thickness = joins.Panels[1].thickness
			inner = math.min(
				inner,
				joins.PillarX
					+ math.min(band.r0, band.r1)
					- (C.Join.FaceSeparation + thickness) / math.sqrt(1 + slope * slope)
			)
		end
		local wall = shell * Vector3.new((if localPad.X < 0 then -1 else 1) * inner, localPad.Y, localPad.Z)
		cellHighZ = pad.CFrame:PointToObjectSpace(wall).Z
	end
	for _, other in base:GetChildren() do
		if
			other:IsA("BasePart")
			and other ~= pad
			and type(other:GetAttribute("SlotIndex")) == "number"
			and math.abs(other.Position.Y - pad.Position.Y) < C.BodyGroundClearanceStuds
		then
			local q = pad.CFrame:PointToObjectSpace(other.Position)
			if math.abs(q.Z) < half.Z / 2 then
				if q.X > 0 then
					cellHighX = math.min(cellHighX, q.X / 2)
				elseif q.X < 0 then
					cellLowX = math.max(cellLowX, q.X / 2)
				end
			end
		end
	end
	pad:SetAttribute("PresentationCellMin", Vector3.new(cellLowX, 0, cellLowZ))
	pad:SetAttribute("PresentationCellMax", Vector3.new(cellHighX, 0, cellHighZ))

	local h = M.ReferenceBodyHeight
	local offsets = {
		Vector3.zero,
		Vector3.new(C.BaseDisplay.OffsetHeightFraction * h, 0, 0),
		Vector3.new(-C.BaseDisplay.OffsetHeightFraction * h, 0, 0),
		Vector3.new(0, 0, C.BaseDisplay.OffsetHeightFraction * h),
		Vector3.new(0, 0, -C.BaseDisplay.OffsetHeightFraction * h),
	}
	local folder = base:FindFirstChild("StoredBrainrots")
	local chosen
	local conflict
	for _, yaw in { 0, C.BaseDisplay.SecondFacingRadians } do
		for _, offset in offsets do
			local candidate = support * CFrame.new(offset) * CFrame.Angles(0, yaw, 0)
			local low, high = rectangle(corners(candidate, meta.normalizedSize), support)
			local valid = low.X >= cellLowX + C.Cargo.RequiredRouteSideClearanceStuds
				and high.X <= cellHighX - C.Cargo.RequiredRouteSideClearanceStuds
				and low.Z >= cellLowZ + C.Cargo.RequiredRouteSideClearanceStuds
				and high.Z <= cellHighZ - C.Cargo.RequiredRouteSideClearanceStuds
			if valid and folder then
				for _, other in folder:GetChildren() do
					if other ~= display and other:IsA("Model") then
						local frame, size =
							other:GetAttribute("DisplayBodySupport"), other:GetAttribute("DisplayBodySize")
						if
							typeof(frame) == "CFrame"
							and typeof(size) == "Vector3"
							and math.abs(frame.Position.Y - candidate.Position.Y) < meta.normalizedSize.Y
						then
							local l, r = rectangle(corners(frame, size), support)
							local gap = C.Cargo.RequiredRouteSideClearanceStuds
							if
								low.X < r.X + gap
								and high.X > l.X - gap
								and low.Z < r.Z + gap
								and high.Z > l.Z - gap
							then
								valid = false
								break
							end
						end
					end
				end
			end
			if valid then
				chosen = { frame = candidate, offset = offset, yaw = yaw, low = low, high = high }
				break
			end
			conflict = Vector3.new(high.X - low.X, 0, high.Z - low.Z)
		end
		if chosen then
			break
		end
	end
	if not chosen then
		display:SetAttribute("BaseFitStatus", "BASE_FIT_CONFLICT")
		display:SetAttribute("BaseFitBodySize", conflict)
		-- Keep the logical slot and a full-size stable presentation; report the real
		-- fixed cell conflict instead of deforming the individual or moving its base.
		display:PivotTo(G.GroundPivot(display:GetAttribute("BrainrotId"), support))
		return support, meta.normalizedSize
	end
	display:SetAttribute("BaseFitStatus", "FIT")
	display:SetAttribute("DisplayVisualOffset", chosen.offset)
	display:SetAttribute("DisplayVisualYaw", chosen.yaw)
	display:SetAttribute("DisplayBodySupport", chosen.frame)
	display:SetAttribute("DisplayBodySize", meta.normalizedSize)
	display:PivotTo(G.GroundPivot(display:GetAttribute("BrainrotId"), chosen.frame))

	return chosen.frame, meta.normalizedSize
end
-- The staging path above changes only the unattached display. The support skin
-- is transferred through the existing slot-presentation owner after commit.
function API.CommitSupport(display, slot)
	if display:GetAttribute("BaseFitStatus") ~= "FIT" then
		API.ReleaseSupport(slot)
		return
	end
	local marker = slot.Marker
	local pad = if marker:IsA("Attachment") then marker.Parent else marker
	local support = if marker:IsA("Attachment") then marker.WorldCFrame else marker.CFrame
	local frame = display:GetAttribute("DisplayBodySupport")
	local size = display:GetAttribute("DisplayBodySize")
	local min, max = rectangle(corners(frame, size), support)
	local SlotPresentation = require(RS.Shared.Utility.BaseSlotPresentation)
	if pad:GetAttribute("PresentationOriginalTransparency") == nil then
		pad:SetAttribute(
			"PresentationOriginalTransparency",
			SlotPresentation.GetAuthoredProperty(pad, "Transparency") or pad.Transparency
		)
	end
	local cosmetic = pad:FindFirstChild("FullSizeSupportPad")
	if not cosmetic then
		cosmetic = Instance.new("Part")
		cosmetic.Name = "FullSizeSupportPad"
		cosmetic.Anchored = true
		cosmetic.CanCollide = false
		cosmetic.CanTouch = false
		cosmetic.CanQuery = false
		cosmetic.CastShadow = true
		cosmetic.Parent = pad
	end
	cosmetic.Color = pad.Color
	cosmetic.Material = pad.Material
	cosmetic.MaterialVariant = pad.MaterialVariant

	cosmetic.Size = Vector3.new(
		max.X - min.X + 2 * C.Cargo.RackEdgePaddingStuds,
		pad.Size.Y,
		max.Z - min.Z + 2 * C.Cargo.RackEdgePaddingStuds
	)
	cosmetic.CFrame = support * CFrame.new((min.X + max.X) / 2, -pad.Size.Y / 2, (min.Z + max.Z) / 2)
	cosmetic.Transparency = pad:GetAttribute("PresentationOriginalTransparency")
	SlotPresentation.Capture(cosmetic, { Transparency = cosmetic.Transparency })
	SlotPresentation.Capture(pad, { Transparency = 1 })
	pad.Transparency = 1
	SlotPresentation.ApplyGroup(pad, SlotPresentation.IsActive(pad) ~= false)
end
function API.ReleaseSupport(slot)
	local marker = slot.Marker
	local pad = if marker:IsA("Attachment") then marker.Parent else marker
	local original = pad:GetAttribute("PresentationOriginalTransparency")
	if original ~= nil then
		require(RS.Shared.Utility.BaseSlotPresentation).Capture(pad, { Transparency = original })
		pad.Transparency = original
		require(RS.Shared.Utility.BaseSlotPresentation).ApplyGroup(
			pad,
			require(RS.Shared.Utility.BaseSlotPresentation).IsActive(pad) ~= false
		)
	end
	local cosmetic = pad:FindFirstChild("FullSizeSupportPad")
	if cosmetic then
		cosmetic:Destroy()
	end
end
return API
