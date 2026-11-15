--!strict
-- TerrainRedesign (V5 world) builder. The ONLY code that writes Terrain or creates world props.
-- Deterministic: the same region data and kits always produce the same instances and voxels.
-- Run in Studio Edit mode (tools/terrain/BuildRegion.server.luau); never at runtime.
local TerrainPalette = require(script.Parent.Parent.Config.TerrainPalette)

local TerrainBuilder = {}

export type Box = {
	slot: string,
	min: { number },
	max: { number },
	role: string,
	relief: (boolean | { string })?, -- stud texture faces ("Top" default when true)
	emissive: boolean?, -- Neon glow accent
	walkable: boolean?, -- keeps collision (stairs, lookout floors, bridge decks)
	transparency: number?,
	rot: { number }?, -- degrees {pitch, yaw, roll} about the box centre (slides only)
}
export type Kit = { name: string, boxes: { Box }, palette: { [string]: string }?, sign: any? }

local STUD_TEXTURE = TerrainPalette.StudTexture
local SHADOW_MIN_VOLUME = 8

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function colour(
	role: string,
	kitPalette: { [string]: string }?,
	regionPalette: { [string]: string }
): Color3
	local hex = (kitPalette and kitPalette[role])
		or regionPalette[role]
		or TerrainPalette.Shared[role]
	assert(hex, "TerrainBuilder: unknown colour role " .. role)
	return Color3.fromHex(hex)
end

local function addStuds(part: BasePart, faces: { string })
	for _, face in faces do
		local texture = Instance.new("Texture")
		texture.Name = "Studs_" .. face
		texture.Texture = STUD_TEXTURE.ColorMap
		texture.Face = (Enum.NormalId :: any)[face]
		texture.StudsPerTileU = STUD_TEXTURE.StudsPerTile
		texture.StudsPerTileV = STUD_TEXTURE.StudsPerTile
		texture.Transparency = STUD_TEXTURE.Transparency
		texture.Parent = part
	end
end

-- One kit -> one anchored Model. `cframe` places the kit origin (ground centre); scale is uniform.
function TerrainBuilder.BuildKit(
	kit: Kit,
	cframe: CFrame,
	scale: number,
	regionPalette: { [string]: string },
	name: string?,
	signText: string?
): Model
	local model = Instance.new("Model")
	model.Name = name or kit.name
	model:SetAttribute("Kit", kit.name)
	for index, box in kit.boxes do
		local lo, hi = v3(box.min) * scale, v3(box.max) * scale
		local size = hi - lo
		assert(
			size.X > 0 and size.Y > 0 and size.Z > 0,
			"TerrainBuilder: empty box " .. kit.name .. "." .. box.slot
		)
		local part = Instance.new("Part")
		part.Name = string.format("%03d_%s", index, box.slot)
		part.Size = size
		local rot = box.rot
		part.CFrame = cframe
			* CFrame.new((lo + hi) / 2)
			* (
				if rot
					then CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					else CFrame.identity
			)
		part.Anchored = true
		part.Color = colour(box.role, kit.palette, regionPalette)
		part.Material = if box.emissive then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = box.transparency or 0
		part.CanCollide = box.walkable == true
		part.CanQuery = box.walkable == true
		part.CanTouch = false
		part.CastShadow = not box.emissive and size.X * size.Y * size.Z > SHADOW_MIN_VOLUME
		if box.relief and not box.emissive then
			addStuds(
				part,
				if type(box.relief) == "table" then box.relief :: { string } else { "Top" }
			)
		end
		part.Parent = model
	end
	if kit.sign then
		TerrainBuilder.AddSignText(model, {
			board = kit.sign.board,
			text = signText or kit.sign.text,
			faces = kit.sign.faces,
		})
	end
	local first = model:FindFirstChildWhichIsA("BasePart")
	if first then
		model.PrimaryPart = first
	end
	model.WorldPivot = cframe
	return model
end

-- White text with a black stroke on the named board box (both faces).
function TerrainBuilder.AddSignText(
	model: Model,
	sign: { board: string, text: string, faces: { string }? }
)
	local board: BasePart? = nil
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 5) == sign.board then
			board = child
		end
	end
	assert(board, "TerrainBuilder: sign board missing " .. sign.board)
	for _, face in sign.faces or { "Front", "Back" } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignText_" .. face
		gui.Face = (Enum.NormalId :: any)[face]
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.MaxDistance = 600
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = sign.text
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 4
		stroke.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)
		padding.PaddingTop = UDim.new(0.1, 0)
		padding.PaddingBottom = UDim.new(0.1, 0)
		padding.Parent = label
		label.Parent = gui
		gui.Parent = board
	end
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

function TerrainBuilder.ApplyMaterialColours(terrain: Terrain, regionKey: string)
	for materialName, hex in TerrainPalette.Materials[regionKey] or {} do
		terrain:SetMaterialColor(material(materialName), Color3.fromHex(hex))
	end
end

-- Terrain only: terraces, wedges, water, carves. Yields between batches.
function TerrainBuilder.ShapeTerrain(terrain: Terrain, region: any, yieldEvery: number?)
	TerrainBuilder.ApplyMaterialColours(terrain, region.key)
	local batch = yieldEvery or 24
	local count = 0
	local function step()
		count += 1
		if count % batch == 0 then
			task.wait()
		end
	end
	for _, terrace in region.terraces or {} do
		local lo, hi = v3(terrace.min), v3(terrace.max)
		terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, material(terrace.material))
		step()
	end
	for _, wedge in region.wedges or {} do
		terrain:FillWedge(wedge.cframe, v3(wedge.size), material(wedge.material))
		step()
	end
	for _, rock in region.rocks or {} do
		terrain:FillBall(v3(rock.center), rock.radius, material(rock.material))
		step()
	end
	-- Carves before water so a carved bed can be filled.
	for _, carve in region.carves or {} do
		local lo, hi = v3(carve.min), v3(carve.max)
		terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, Enum.Material.Air)
		step()
	end
	for _, water in region.water or {} do
		local lo, hi = v3(water.min), v3(water.max)
		terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, Enum.Material.Water)
		step()
	end
end

-- Seam interleave patches and the island rim; run after every region is shaped, so neighbouring
-- ground fills, pools and bogs never cut into them.
function TerrainBuilder.ShapeSeams(terrain: Terrain, region: any)
	for index, block in region.rim or {} do
		local lo, hi = v3(block.min), v3(block.max)
		terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, material(block.material))
		if index % 24 == 0 then
			task.wait()
		end
	end
	for index, terrace in region.seamTerraces or {} do
		local lo, hi = v3(terrace.min), v3(terrace.max)
		terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, material(terrace.material))
		if index % 24 == 0 then
			task.wait()
		end
	end
end

-- The four XZ strips of the ring between an inner and an outer rect (Vector2.Y = world Z).
local function ring(inner: any, outer: any): { { lo: Vector2, hi: Vector2 } }
	return {
		{ lo = outer.min, hi = Vector2.new(outer.max.X, inner.min.Y) }, -- north
		{ lo = Vector2.new(outer.min.X, inner.max.Y), hi = outer.max }, -- south
		{ lo = Vector2.new(outer.min.X, inner.min.Y), hi = Vector2.new(inner.min.X, inner.max.Y) }, -- west
		{ lo = Vector2.new(inner.max.X, inner.min.Y), hi = Vector2.new(outer.max.X, inner.max.Y) }, -- east
	}
end

-- Ocean beyond the island coast (IslandEdge config): a sand bed, open water to SurfaceY and a
-- shallow sand shelf at the foot of the rim. Written in tiles of at most 256 studs.
function TerrainBuilder.ShapeOcean(terrain: Terrain, edge: any)
	local ocean = edge.Ocean
	local coast = edge.Coast
	local function grow(rect: any, by: number): any
		return { min = rect.min - Vector2.one * by, max = rect.max + Vector2.one * by }
	end
	local count = 0
	local function fill(strip: any, y0: number, y1: number, mat: Enum.Material)
		local x = strip.lo.X
		while x < strip.hi.X do
			local x1 = math.min(x + 256, strip.hi.X)
			local z = strip.lo.Y
			while z < strip.hi.Y do
				local z1 = math.min(z + 256, strip.hi.Y)
				local lo, hi = Vector3.new(x, y0, z), Vector3.new(x1, y1, z1)
				terrain:FillBlock(CFrame.new((lo + hi) / 2), hi - lo, mat)
				count += 1
				if count % 16 == 0 then
					task.wait()
				end
				z = z1
			end
			x = x1
		end
	end
	local open = ring(coast, grow(coast, ocean.Reach))
	for _, strip in open do
		fill(strip, ocean.BedBottomY, ocean.DeepFloorY, Enum.Material.Sand)
	end
	for _, strip in open do
		fill(strip, ocean.DeepFloorY, ocean.SurfaceY, Enum.Material.Water)
	end
	for _, strip in ring(coast, grow(coast, ocean.ShelfWidth)) do
		fill(strip, ocean.DeepFloorY, ocean.ShelfFloorY, Enum.Material.Sand)
	end
	for _, islet in ocean.Islets or {} do
		local radius = islet[3]
		terrain:FillBall(
			Vector3.new(islet[1], ocean.SurfaceY + (ocean.IsletCap or 3) - radius, islet[2]),
			radius,
			Enum.Material.Sand
		)
		count += 1
	end
	return count
end

local function placement(entry: any): CFrame
	local p = entry.position
	return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(entry.yaw or 0), 0)
end

-- Props from kits. Each cluster is its own Atomic-streamed model; the landmark is Persistent.
-- The region root is a Folder so streaming stays per cluster model, never per region.
function TerrainBuilder.Dress(
	region: any,
	kits: { [string]: Kit },
	parent: Instance,
	yieldEvery: number?
): Folder
	local root = Instance.new("Folder")
	root.Name = region.key
	root:SetAttribute("TerrainRegionVersion", region.version)
	-- Parent first so every model below is a small, separate insertion.
	root.Parent = parent
	local batch = yieldEvery or 8
	local built = 0
	local function add(kind: string, entry: any, index: number, streaming: Enum.ModelStreamingMode)
		local kit = kits[entry.kit]
		assert(kit, "TerrainBuilder: unknown kit " .. tostring(entry.kit))
		local palette = region.palette
		if entry.palette then
			palette = table.clone(region.palette)
			for role, hex in entry.palette do
				palette[role] = hex
			end
		end
		local model = TerrainBuilder.BuildKit(
			kit,
			placement(entry),
			entry.scale or 1,
			palette,
			string.format("%s_%02d_%s", kind, index, entry.name or entry.kit),
			entry.text
		)
		model.ModelStreamingMode = streaming
		model:SetAttribute("Role", kind)
		if entry.name then
			model:SetAttribute("DisplayName", entry.name)
		end
		model.Parent = root
		built += 1
		if built % batch == 0 then
			task.wait()
		end
		return model
	end
	if region.landmark then
		local hero = add("Landmark", region.landmark, 1, Enum.ModelStreamingMode.Persistent)
		hero:SetAttribute("HeroLandmark", region.key)
		hero:AddTag("CriticalBoundary")
	end
	for index, entry in region.clusters or {} do
		add("Cluster", entry, index, Enum.ModelStreamingMode.Atomic)
	end
	for index, entry in region.signs or {} do
		add("Sign", entry, index, Enum.ModelStreamingMode.Atomic)
	end
	for index, entry in region.secrets or {} do
		add("Secret", entry, index, Enum.ModelStreamingMode.Atomic)
	end
	for index, entry in region.toys or {} do
		local model = add("Toy", entry, index, Enum.ModelStreamingMode.Atomic)
		model:SetAttribute("ToyType", entry.type)
		for key, value in entry.params or {} do
			model:SetAttribute(key, value)
		end
		model:AddTag("TraversalToy")
	end
	if region.rims and #region.rims > 0 then
		-- Dark lip bands (V4 rule 3) as one small static model.
		local rims = Instance.new("Model")
		rims.Name = "Rims"
		rims.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		rims:SetAttribute("Role", "Rims")
		for index, rim in region.rims do
			local lo, hi = v3(rim.min), v3(rim.max)
			local part = Instance.new("Part")
			part.Name = string.format("Rim_%03d", index)
			part.Size = hi - lo
			part.CFrame = CFrame.new((lo + hi) / 2)
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow =
				true, false, false, false, false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.fromHex(TerrainPalette.Shared.JointDark)
			part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			part.Parent = rims
		end
		rims.Parent = root
	end
	return root
end

-- Deterministic fingerprint used by tests and verification.
function TerrainBuilder.Fingerprint(
	model: Instance
): { parts: number, neon: number, textures: number, models: number }
	local parts, neon, textures, models = 0, 0, 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d.Material == Enum.Material.Neon then
				neon += 1
			end
		elseif d:IsA("Texture") then
			textures += 1
		elseif d:IsA("Model") then
			models += 1
		end
	end
	return { parts = parts, neon = neon, textures = textures, models = models }
end

return TerrainBuilder
