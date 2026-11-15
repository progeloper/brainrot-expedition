--!strict
-- UI projection only. MutationAppearanceCatalogue is the sole authored material
-- and palette authority supplied by the separate mutation texture package.
local Source = require(script.Parent.MutationAppearanceCatalogue)
local rarities, mutations = {}, {}
local function colour(value: any): Color3
	return if typeof(value) == "Color3"
		then value
		else Color3.fromHex(tostring(value):gsub("#", ""))
end
for id, family in Source.NormalRarityReference.palettes do
	rarities[id] = table.freeze({
		shadow = colour(family[1]),
		primary = colour(family[2]),
		highlight = colour(family[3]),
	})
end
local installed = true
for id, definition in Source.Mutations do
	if id ~= "Normal" then
		local presets = definition.presets.Default or definition.presets.Revealed
		mutations[id] = table.freeze({
			palette = table.freeze({
				shadow = colour(presets.Secondary.color),
				primary = colour(presets.Primary.color),
				highlight = colour(presets.Accent.color),
			}),
		})
		for _, state in definition.presets do
			for _, preset in state do
				if preset.installed ~= true then
					installed = false
				end
			end
		end
	end
end
return table.freeze({
	Source = Source,
	Rarities = table.freeze(rarities),
	Mutations = table.freeze(mutations),
	SavedStudMaterial = "Bingus_Saved_Studs_13719188279",
	MaterialPresetsInstalled = installed,
	TextureReferencesInstalled = installed,
	TextureAssetsInstalled = installed,
	TextureRenderingVerified = false,
	AssetStatus = "Native P12 material/map references installed; per-client fetch and rendered quality observations are recorded separately",
})
