--!nocheck
-- Native wedge prisms provide exact recessed planes without a mesh-upload dependency.
local RS = game:GetService("ReplicatedStorage")
local M = require(RS.Shared.Config.BaseJoinMetadata)
local C = require(RS.Shared.Config.PlaytestExact)
local Adapter = {}
local function triangle(parent, id, a, b, c, normal, thickness, source, frame, decorative)
	local ab, ac, bc = b - a, c - a, c - b
	if ab:Dot(ab) > ac:Dot(ac) and ab:Dot(ab) > bc:Dot(bc) then
		c, a = a, c
	elseif ac:Dot(ac) > bc:Dot(bc) then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local back = bc.Unit
	local up = back:Cross(right).Unit
	local height = math.abs(ab:Dot(up))
	local function wedge(n, position, axis, z, length)
		if length <= 0 or height <= 0 then
			return
		end
		local p = Instance.new("WedgePart")
		p.Name = id .. "_" .. n
		p:SetAttribute("ComponentIdentity", p.Name)
		p:SetAttribute("JoinPlaneNormal", frame:VectorToWorldSpace(normal))
		p:SetAttribute("JoinReferencePoint", frame * (a + normal * C.Join.FaceSeparation))
		p:SetAttribute("JoinFaceSeparation", C.Join.FaceSeparation)
		p.Size = Vector3.new(thickness, height, length)
		p.CFrame = frame * CFrame.fromMatrix(position - normal * thickness / 2, axis, up, z)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = not decorative
		p:SetAttribute("JoinRole", if decorative then "Decoration" else "StructuralPanel")
		p.Color = source.Color
		p.Material = source.Material
		p.MaterialVariant = source.MaterialVariant
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
	end
	wedge(1, (a + b) / 2, right, back, math.abs(ab:Dot(back)))
	wedge(2, (a + c) / 2, -right, -back, math.abs(ac:Dot(back)))
end
local function quad(parent, id, a, b, c, d, n, t, source, frame, decorative)
	local ab, ad = b - a, d - a
	if ab == c - d and ad == c - b and ab:Dot(ad) == 0 then
		local p = Instance.new("Part")
		p.Name = id
		p.Size = Vector3.new(ab.Magnitude, ad.Magnitude, t)
		p.CFrame = frame * CFrame.fromMatrix((a + c) / 2 - n * t / 2, ab.Unit, ad.Unit, ab.Unit:Cross(ad.Unit))
		p:SetAttribute("ComponentIdentity", id)
		p:SetAttribute("JoinPlaneNormal", frame:VectorToWorldSpace(n))
		p:SetAttribute("JoinReferencePoint", frame * (a + n * C.Join.FaceSeparation))
		p:SetAttribute("JoinFaceSeparation", C.Join.FaceSeparation)
		p:SetAttribute("JoinRole", if decorative then "Decoration" else "StructuralPanel")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = not decorative
		p.Color = source.Color
		p.Material = source.Material
		p.MaterialVariant = source.MaterialVariant
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
	else
		triangle(parent, id .. "_A", a, b, c, n, t, source, frame, decorative)
		triangle(parent, id .. "_B", a, c, d, n, t, source, frame, decorative)
	end
end

function Adapter.Apply(base)
	local source = base:FindFirstChild("Primary")
	local support = base:FindFirstChild("Support")
	if not source or not support or not source:IsA("MeshPart") or not support:IsA("MeshPart") then
		return false, "NO_AUTHORED_SHELL"
	end
	source.Material = Enum.Material.SmoothPlastic
	source.MaterialVariant = ""
	local current = base:FindFirstChild("RecessedInfill")
	if current and current:GetAttribute("Version") == C.Version then
		for _, p in current:GetChildren() do
			if p:IsA("BasePart") then
				p.Color = source.Color
				p.Material = source.Material
				p.MaterialVariant = source.MaterialVariant
			end
		end
		source.Transparency = 1
		return true
	end
	local container = Instance.new("Folder")
	container.Name = "RecessedInfill"
	container:SetAttribute("Version", C.Version)
	local frame = source.CFrame * CFrame.new(0, -M.PrimaryCentreY, 0)
	for _, panel in M.Panels do
		for bi, band in M.Bands do
			local y0, y1 = band.y0, math.min(panel.height, band.y1)
			if y1 <= y0 then
				continue
			end
			local slope = (band.r1 - band.r0) / (band.y1 - band.y0)
			local function radius(y)
				return band.r0 + slope * (y - band.y0)
			end
			local normal = Vector3.new(panel.side, -slope, 0).Unit
			-- Split at actual pillar bays; no infill passes through a door or beyond a pillar outer face.
			for bay = 1, #M.PillarZ - 1 do
				local left, right = M.PillarZ[bay], M.PillarZ[bay + 1]
				local function limits(y)
					local r = radius(y)
					return math.max(panel.z0, left + r), math.min(panel.z1, right - r)
				end
				local l0, r0 = limits(y0)
				local l1, r1 = limits(y1)
				if r0 <= l0 or r1 <= l1 then
					continue
				end
				local function point(y, z)
					return Vector3.new(
						panel.side * (M.PillarX + radius(y) - C.Join.FaceSeparation * math.sqrt(1 + slope * slope)),
						y,
						z
					)
				end
				quad(
					container,
					panel.id .. "_band" .. bi .. "_bay" .. bay,
					point(y0, l0),
					point(y0, r0),
					point(y1, r1),
					point(y1, l1),
					normal,
					panel.thickness,
					source,
					frame
				)
				for _, isLeft in { true, false } do
					local pillar = if isLeft then left else right
					local spanSign = if isLeft then 1 else -1
					local factor = 2 - M.PillarChamferFraction
					local bevelNormal = Vector3.new(panel.side, -factor * slope, spanSign).Unit
					local function tabPoint(y, inner)
						local r = radius(y)
						local overlap = math.min(C.Join.EndpointOverlap, r)
						local z = pillar + spanSign * (r - (if inner then overlap else 0))
						local radial = factor * r
							- math.abs(z - pillar)
							- C.Join.FaceSeparation * math.sqrt(2 + (factor * slope) ^ 2)
						return Vector3.new(panel.side * (M.PillarX + radial), y, z)
							- bevelNormal * C.Join.FaceSeparation
					end
					local p0, p1 = tabPoint(y0, false), tabPoint(y1, false)
					if p0.Z >= panel.z0 and p0.Z <= panel.z1 and p1.Z >= panel.z0 and p1.Z <= panel.z1 then
						quad(
							container,
							panel.id .. "_tab" .. bi .. "_" .. bay .. "_" .. tostring(isLeft),
							tabPoint(y0, true),
							p0,
							p1,
							tabPoint(y1, true),
							bevelNormal,
							panel.thickness,
							source,
							frame
						)
					end
				end
			end
		end
	end
	for bi, band in M.Bands do
		local y0, y1 = band.y0, math.min(M.RearHeight, band.y1)
		if y1 <= y0 then
			continue
		end
		local slope = (band.r1 - band.r0) / (band.y1 - band.y0)
		local function radius(y)
			return band.r0 + slope * (y - band.y0)
		end
		local normal = Vector3.new(0, -slope, 1).Unit
		local function point(y, side)
			local r = radius(y)
			return Vector3.new(
				side * (M.PillarX - r),
				y,
				M.PillarZ[3] + r - C.Join.FaceSeparation * math.sqrt(1 + slope * slope)
			)
		end
		quad(
			container,
			"rear_band" .. bi,
			point(y0, -1),
			point(y0, 1),
			point(y1, 1),
			point(y1, -1),
			normal,
			M.RearThickness,
			source,
			frame
		)
	end
	for bi, band in M.Bands do
		local y0, y1 = band.y0, math.min(M.RearHeight, band.y1)
		if y1 <= y0 then
			continue
		end
		local slope = (band.r1 - band.r0) / (band.y1 - band.y0)
		local function radius(y)
			return band.r0 + slope * (y - band.y0)
		end
		for _, side in { -1, 1 } do
			local factor = 2 - M.PillarChamferFraction
			local normal = Vector3.new(-side, -factor * slope, 1).Unit
			local function point(y, inner)
				local r = radius(y)
				local overlap = math.min(C.Join.EndpointOverlap, r)
				local x = side * (M.PillarX - r + (if inner then overlap else 0))
				local radial = factor * r
					- math.abs(x - side * M.PillarX)
					- C.Join.FaceSeparation * math.sqrt(2 + (factor * slope) ^ 2)
				return Vector3.new(x, y, M.PillarZ[3] + radial)
			end
			quad(
				container,
				"rear_tab" .. bi .. "_" .. side,
				point(y0, false),
				point(y0, true),
				point(y1, true),
				point(y1, false),
				normal,
				M.RearThickness,
				source,
				frame
			)
		end
	end

	-- Preserve the eight authored interior reliefs as clipped, recessed skins.
	for _, relief in M.Reliefs do
		for bi, band in M.Bands do
			local y0, y1 = math.max(relief.ymin, band.y0), math.min(relief.ymax, band.y1)
			if y1 <= y0 then
				continue
			end
			local slope = (band.r1 - band.r0) / (band.y1 - band.y0)
			local function radius(y)
				return band.r0 + slope * (y - band.y0)
			end
			local outward = Vector3.new(0, -slope, 1).Unit
			local function point(y, right)
				local r = radius(y)
				local x = if right then math.min(relief.xmax, M.PillarX - r) else math.max(relief.xmin, -M.PillarX + r)
				return Vector3.new(x, y, M.PillarZ[3] + r)
					- outward * (C.Join.FaceSeparation + M.RearThickness + relief.projection)
			end
			if point(y0, true).X > point(y0, false).X and point(y1, true).X > point(y1, false).X then
				quad(
					container,
					relief.id .. "_band" .. bi,
					point(y0, false),
					point(y0, true),
					point(y1, true),
					point(y1, false),
					-outward,
					relief.thickness,
					source,
					frame,
					true
				)
			end
		end
	end
	-- Preserve the previous valid visual until the complete replacement exists.
	if current then
		current:Destroy()
	end
	container.Parent = base
	source.Transparency = 1
	source:SetAttribute("InfillReplacedBy", "RecessedInfill")
	base:SetAttribute("PanelJoinRepairVersion", C.Version)
	return true
end
return Adapter
