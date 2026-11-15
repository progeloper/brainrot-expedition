--!strict
-- TerrainRedesign (V5 world) colours. Every hex traces to VoxelCreaturePalette (V4 library) or a
-- same-hue cleaned variant noted inline. Terrain:SetMaterialColor is global per material, so each
-- terrain material belongs to exactly one region (see Materials; Owner lists the claim).
local function freezeAll(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freezeAll(v)
		end
	end
	return table.freeze(t)
end

return freezeAll({
	Version = 1,
	-- Reused stud image (VoxelCreaturePalette.Studs.ColorMap; same image as Bingus_Saved_Studs). Never re-uploaded.
	StudTexture = {
		ColorMap = "rbxassetid://126387978066468",
		StudsPerTile = 0.5,
		Transparency = 0.8, -- subtle relief; lower values wash out the V4 colours
	},
	-- Roles every kit may use regardless of region.
	Shared = {
		JointDark = "#1D2133", -- V4 JointDark
		JointDark2 = "#2A2F45", -- V4 JointDark2
		White = "#F7F5FC", -- V4 BrightWhite
		Wood = "#C9894A", -- V4 WarmWood
		WoodDark = "#8A5528", -- V4 WarmWoodDark
		Steel = "#9AA6C8", -- V4 Steel
		SteelDark = "#5D6788", -- V4 SteelDark
		Sun = "#FFD447", -- V4 Sun
		Cyan = "#2EE9FF", -- V4 Cyan
		HotPink = "#FF3D9E", -- V4 HotPink
		Lime = "#8DFF3A", -- V4 Lime
		Sky = "#46A7FF", -- V4 Sky
		Tangerine = "#FF8A2A", -- V4 Tangerine
		Magenta = "#FF49E1", -- V4 GlitchZone upper
		Headlight = "#BFF8FF", -- V4 Headlight
		Cherry = "#F0283C", -- V4 Cherry
		Grape = "#8A4DFF", -- V4 Grape
		StormViolet = "#2B0F52", -- V4 GlitchZone lower (Storm body)
		Mist = "#DFF9FF", -- cleaned Headlight (out-of-bounds sea mist)
	},
	-- Terrain water is global (one colour for brooks, swamp and the ocean): V4 Cyan.
	WaterColour = "#2EE9FF",
	-- Terrain material colours per region. Material names are Enum.Material names.
	Materials = {
		Camp = {
			Salt = "#8DFF3A", -- V4 Lime; camp ground (hue 95, S 0.77, V 1.0)
			Cobblestone = "#FFE7A3", -- cleaned Sun (plaza ring), matches the existing yellow lanes
		},
		-- Forest avoids the Grass material: its terrain decoration (grass blades) cannot be turned off
		-- from scripts and costs budget phones; LeafyGrass carries the ground instead.
		Forest = {
			LeafyGrass = "#3BD16F", -- V4 Leaf (hue 141, S 0.72, V 0.82)
			Concrete = "#2FBF5A", -- V4 WatermelonGreen (deeper flat patches)
			Rock = "#5D6788", -- V4 SteelDark (cliff faces and stream bed; reads against green)
		},
		Beach = {
			Sand = "#FFF07A", -- cleaned V4 Banana, lighter (hue 54, S 0.52, V 1.0) so the #FFB443 lanes read on it
			Sandstone = "#FFF4CD", -- V4 Golden-palette "lower" cream (dune tops, bluff treads)
			Limestone = "#E5A520", -- V4 "skin2" ochre (dune faces, bluff cliffs, pool beds)
		},
		Swamp = {
			Mud = "#14C79F", -- V4 Teal (hue 166, S 0.90, V 0.78)
			Ground = "#0E8F73", -- cleaned Teal, darker (moss patches, stack treads)
			Slate = "#2A2F45", -- V4 JointDark2 (stack cliffs, bog beds)
		},
		-- The brief's Jungle pair (LeafyGrass / Grass) is taken by the Forest and Grass is avoided. Only
		-- materials with an AF2 stud override in MaterialService render as V4 studs (WoodPlanks, Brick,
		-- Concrete, Pavement and Cobblestone show their stock textures), so the Jungle owns Asphalt + Ice.
		-- 10 Nov: BuildWorld now overrides Concrete, Pavement and Cobblestone too, so every palette
		-- material renders the saved AF2 studs (water excepted: it takes no MaterialVariant).
		Jungle = {
			Asphalt = "#1EA845", -- cleaned WatermelonGreen, deeper (hue 137, S 0.82, V 0.66); ground and treads
			Ice = "#2A3A20", -- V4 dark moss trim (cliff and terrace faces)
		},
		-- Ground materials must render flat (Studio test fill, 9 Nov): Rock, Slate, Basalt and CrackedLava
		-- are rough (up to +-0.9, normals down to 0.69) and Pavement snaps to whole studs (0.0 or -1.0), so
		-- they carry cliffs only. That leaves Glacier, Snow and Grass as flat stud-backed materials. Grass
		-- blades show while Terrain.Decoration is on (orange blades read as scorched grass); that property
		-- is not scriptable, so the owner unticks it in Studio (brief section 8 wants it off).
		Arctic = {
			Snow = "#7FE8FF", -- V4 Ocean bright (hue 191, S 0.50, V 1.0); ground and ridge treads
			Basalt = "#2B6FD6", -- cleaned V4 Sky, deeper (hue 215, S 0.80, V 0.84); rugged ice cliffs
		},
		Volcano = {
			Glacier = "#E2531E", -- cleaned V4 Tangerine, deeper (hue 17, S 0.87, V 0.89); flat ground and treads
			CrackedLava = "#2B2238", -- V4 JointDark2, warmed (rugged cliffs, mesa faces, the river bands)
		},
		GlitchZone = {
			Grass = "#6B2EE6", -- V4 Grape, deepened (hue 263, S 0.80, V 0.90); ground, treads and rim caps
			Pavement = "#3E1E99", -- V4 Grape, dark (hue 255, S 0.80, V 0.60); stepped pixel cliff faces
		},
	},
	Owner = {
		Salt = "Camp",
		Cobblestone = "Camp",
		LeafyGrass = "Forest",
		Concrete = "Forest",
		Rock = "Forest",
		Sand = "Beach",
		Sandstone = "Beach",
		Limestone = "Beach",
		Mud = "Swamp",
		Ground = "Swamp",
		Slate = "Swamp",
		Asphalt = "Jungle",
		Ice = "Jungle",
		Snow = "Arctic",
		Basalt = "Arctic",
		Glacier = "Volcano",
		CrackedLava = "Volcano",
		Grass = "GlitchZone",
		Pavement = "GlitchZone",
	},
})
