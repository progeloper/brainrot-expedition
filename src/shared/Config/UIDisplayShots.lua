--!strict
-- Menus V2 display shots: transparent PNGs (camera slightly above, item facing right) for weapons,
-- carts, brainrots and base designs. Sources: assets/ui/display_shots/<ID>.png (uploads listed in
-- assets/ui/UPLOADED_ASSETS.md). get() never errors: brainrots fall back to UIPortraits, anything
-- else returns "" and the Plate card shows a labelled TODO SHOT placeholder.
local UIPortraits = require(script.Parent.UIPortraits)

local UIDisplayShots = {}

UIDisplayShots.Ids = table.freeze({
	BDS_001 = "rbxassetid://107427461510301",
	BDS_002 = "rbxassetid://132092369737129",
	BDS_003 = "rbxassetid://113817383226947",
	BDS_004 = "rbxassetid://70922945825236",
	BDS_005 = "rbxassetid://93388723459815",
	BDS_006 = "rbxassetid://123190969786091",
	BDS_007 = "rbxassetid://134036377768109",
	BDS_008 = "rbxassetid://108631708444517",
	BRT_001 = "rbxassetid://70484988877575",
	BRT_002 = "rbxassetid://120218492590480",
	BRT_003 = "rbxassetid://93668065218382",
	BRT_004 = "rbxassetid://77933497031530",
	BRT_005 = "rbxassetid://105153706889670",
	BRT_006 = "rbxassetid://112430412218698",
	BRT_007 = "rbxassetid://102211683986781",
	BRT_008 = "rbxassetid://128142855878646",
	BRT_009 = "rbxassetid://75661259681443",
	BRT_010 = "rbxassetid://90672511112025",
	BRT_011 = "rbxassetid://122570645128226",
	BRT_012 = "rbxassetid://118002275046015",
	BRT_013 = "rbxassetid://121176422297431",
	BRT_014 = "rbxassetid://71871117390423",
	BRT_015 = "rbxassetid://127685703049940",
	BRT_016 = "rbxassetid://123590962363981",
	BRT_017 = "rbxassetid://103547049821437",
	BRT_018 = "rbxassetid://107843606840527",
	BRT_019 = "rbxassetid://122896720259910",
	BRT_020 = "rbxassetid://124456808930004",
	BRT_021 = "rbxassetid://74674197176752",
	BRT_022 = "rbxassetid://74047779961590",
	BRT_023 = "rbxassetid://138641690242401",
	BRT_024 = "rbxassetid://119938668269760",
	BRT_025 = "rbxassetid://83725319735292",
	BRT_026 = "rbxassetid://115100297229821",
	BRT_027 = "rbxassetid://99669312425517",
	BRT_028 = "rbxassetid://119894303362838",
	BRT_029 = "rbxassetid://77114643537400",
	BRT_030 = "rbxassetid://89692579575440",
	BRT_031 = "rbxassetid://106550149675712",
	BRT_032 = "rbxassetid://117843937227994",
	BRT_033 = "rbxassetid://89985451159353",
	BRT_034 = "rbxassetid://96714531162236",
	BRT_035 = "rbxassetid://97297336793068",
	BastionWagon = "rbxassetid://80468660104411",
	CometSkimmer = "rbxassetid://104226402384741",
	DuneRunner = "rbxassetid://136911420792328",
	HRP_001 = "rbxassetid://70460705678698",
	IronHauler = "rbxassetid://108582673657585",
	NeonCruiser = "rbxassetid://116114033083132",
	ObsidianFortress = "rbxassetid://139230212050004",
	ScrapChariot = "rbxassetid://108698408071503",
	StarforgeChariot = "rbxassetid://115541155882403",
	VoltDasher = "rbxassetid://90986797792456",
	WPN_B02 = "rbxassetid://75386958142561",
	WPN_B03 = "rbxassetid://123162590644210",
	WPN_B04 = "rbxassetid://101801558696877",
	WPN_B05 = "rbxassetid://127197523209795",
	WPN_B06 = "rbxassetid://106767322895854",
	WPN_B07 = "rbxassetid://139617414103866",
	WPN_B08 = "rbxassetid://92422915578937",
	WPN_C01 = "rbxassetid://78458533313919",
	WPN_C02 = "rbxassetid://106243307465171",
	WPN_C03 = "rbxassetid://90163275086936",
	WPN_C04 = "rbxassetid://103329210273600",
	WPN_C05 = "rbxassetid://90384794949010",
	WPN_C06 = "rbxassetid://108155984990996",
	WPN_C07 = "rbxassetid://118147133128070",
	WPN_C08 = "rbxassetid://133134205573886",
	WPN_G01 = "rbxassetid://101920565068643",
	WPN_G02 = "rbxassetid://99609880156322",
	WPN_G03 = "rbxassetid://115326538682842",
	WPN_G04 = "rbxassetid://121911287644409",
	WPN_G05 = "rbxassetid://138098373571070",
	WPN_G06 = "rbxassetid://72935994518048",
	WPN_G07 = "rbxassetid://111854408711936",
	WPN_G08 = "rbxassetid://85152404331774",
	WPN_SP_COLLECTORSBOW = "rbxassetid://70595859114907",
	WPN_SP_CRYSTALLANCE = "rbxassetid://88017067461872",
	WPN_SP_GETAWAY = "rbxassetid://136748445780212",
	WPN_SP_PRISMREPEATER = "rbxassetid://131186591230612",
	WPN_SP_RIFTBLASTER = "rbxassetid://72088841613716",
	WPN_SP_SECRETHUNTER = "rbxassetid://79487582570183",
} :: { [string]: string })

function UIDisplayShots.get(itemId: unknown): string
	if type(itemId) ~= "string" then
		return ""
	end
	local id = UIDisplayShots.Ids[itemId]
	if id then
		return id
	end
	if string.match(itemId, "^BRT_%d%d%d$") and UIPortraits.has(itemId) then
		return UIPortraits.get(itemId)
	end
	return ""
end

function UIDisplayShots.has(itemId: unknown): boolean
	return type(itemId) == "string" and UIDisplayShots.Ids[itemId] ~= nil
end

return table.freeze(UIDisplayShots)
