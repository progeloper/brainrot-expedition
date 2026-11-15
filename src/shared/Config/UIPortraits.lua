--!strict
-- Front-view brainrot portraits for menus (Stud Pop UI). Static 512² transparent PNGs captured from the
-- approved templates in ServerStorage.Phase13CreatureAssets (Normal mutation, idle, no FX) and uploaded
-- to the DEV place. Sources: assets/ui/portraits/<ID>.png; pipeline: scripts/ui_stud_pop/.
-- Menus show a mutation with its label colour + frame glow over the Normal portrait.

local UIPortraits = {}

-- Lock silhouette for unknown or undiscovered species (Stud Pop lock icon).
UIPortraits.Locked = "rbxassetid://70711614023180"

UIPortraits.Ids = table.freeze({
	BRT_001 = "rbxassetid://72173100043404",
	BRT_002 = "rbxassetid://119349334057195",
	BRT_003 = "rbxassetid://95533036122139",
	BRT_004 = "rbxassetid://80262487007020",
	BRT_005 = "rbxassetid://106797240276153",
	BRT_006 = "rbxassetid://91698784535047",
	BRT_007 = "rbxassetid://74547925078284",
	BRT_008 = "rbxassetid://77839298512718",
	BRT_009 = "rbxassetid://90219676417640",
	BRT_010 = "rbxassetid://115259961044603",
	BRT_011 = "rbxassetid://122493709785830",
	BRT_012 = "rbxassetid://137946022567799",
	BRT_013 = "rbxassetid://120486527441517",
	BRT_014 = "rbxassetid://123227159295528",
	BRT_015 = "rbxassetid://100450014194471",
	BRT_016 = "rbxassetid://130186406059879",
	BRT_017 = "rbxassetid://133154141374917",
	BRT_018 = "rbxassetid://70622439524705",
	BRT_019 = "rbxassetid://94436508920802",
	BRT_020 = "rbxassetid://135270461702516",
	BRT_021 = "rbxassetid://122827113949266",
	BRT_022 = "rbxassetid://128192029684229",
	BRT_023 = "rbxassetid://79803067094737",
	BRT_024 = "rbxassetid://83090077025721",
	BRT_025 = "rbxassetid://129832938268977",
	BRT_026 = "rbxassetid://108691004742256",
	BRT_027 = "rbxassetid://128436977213036",
	BRT_028 = "rbxassetid://136593363488496",
	BRT_029 = "rbxassetid://102488264561829",
	BRT_030 = "rbxassetid://139789761291673",
	BRT_031 = "rbxassetid://137394715735829",
	BRT_032 = "rbxassetid://71310884257935",
	BRT_033 = "rbxassetid://79728592629899",
	BRT_034 = "rbxassetid://99874352345992",
	BRT_035 = "rbxassetid://94209811354847",
} :: { [string]: string })

-- Portrait for a species, or the lock silhouette when the id is unknown or `discovered == false`.
function UIPortraits.get(speciesId: unknown, discovered: boolean?): string
	if discovered == false or type(speciesId) ~= "string" then
		return UIPortraits.Locked
	end
	return UIPortraits.Ids[speciesId] or UIPortraits.Locked
end

function UIPortraits.has(speciesId: unknown): boolean
	return type(speciesId) == "string" and UIPortraits.Ids[speciesId] ~= nil
end

return table.freeze(UIPortraits)
