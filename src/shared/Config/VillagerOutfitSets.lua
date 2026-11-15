--!strict
-- Outfit sets by name (v1.1 section 3.4). A villager row's `outfit` names its set; the set's
-- `outfits[kit]` layer is applied after the kit's regional variant.
local Outfits = script.Parent.VillagerOutfits

local sets = {
	Forest = require(Outfits.Forest),
	Beach = require(Outfits.Beach),
	Swamp = require(Outfits.Swamp),
	Jungle = require(Outfits.Jungle),
	Arctic = require(Outfits.Arctic),
	Volcano = require(Outfits.Volcano),
	Glitch = require(Outfits.Glitch),
}

local OutfitSets = {}

function OutfitSets.Get(setName: string?): any?
	return if setName then sets[setName] else nil
end

-- Outfit key inside a set: the kit, or "<kit>.<style>" when the row names a style
-- (for example "Sprinter.Women" for women's dress on the Sprinter body).
local function key(row: any): string
	return if row.outfitStyle then row.kit .. "." .. row.outfitStyle else row.kit
end

-- The outfit layer for one villager row, or nil when the row has no outfit yet.
function OutfitSets.ForRow(row: any): any?
	local set = OutfitSets.Get(row.outfit)
	return if set then set.outfits[key(row)] else nil
end

-- Template token for the row's outfit, e.g. "Forest" or "Jungle.Women".
function OutfitSets.Token(row: any): string?
	if not row.outfit then
		return nil
	end
	return if row.outfitStyle then row.outfit .. "." .. row.outfitStyle else row.outfit
end

function OutfitSets.All(): { [string]: any }
	return sets
end

return table.freeze(OutfitSets)
