--!strict
-- Prices below are FINAL denomination 2; never apply the source-table multiplier.
-- Explicit Phase 8 pools; central data does not activate a region.
local poolRows = {
	Forest = {weights={0.68,0.26,0.06,0,0,0}, exclusive="BRT_007", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_007","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_013"},
		Rare={"BRT_019"},
		Epic={},
		Legendary={},
		Mythic={},
	}},
	Beach = {weights={0.4,0.4,0.2,0,0,0}, exclusive="BRT_012", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_012","BRT_013","BRT_014","BRT_015"},
		Rare={"BRT_019","BRT_020"},
		Epic={},
		Legendary={},
		Mythic={},
	}},
	Swamp = {weights={0.15,0.3,0.4,0.15,0,0}, exclusive="BRT_021", species={
		Common={"BRT_001","BRT_002","BRT_003","BRT_004","BRT_005","BRT_006","BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_011","BRT_013","BRT_014","BRT_015","BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_019","BRT_020","BRT_021","BRT_022"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	Jungle = {weights={0.05,0.15,0.45,0.35,0,0}, exclusive="BRT_027", species={
		Common={"BRT_008","BRT_009","BRT_010"},
		Uncommon={"BRT_014","BRT_015","BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_019","BRT_020","BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_027","BRT_028","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	Arctic = {weights={0,0.05,0.25,0.7,0,0}, exclusive="BRT_029", species={
		Common={},
		Uncommon={"BRT_016","BRT_017","BRT_018"},
		Rare={"BRT_020","BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_029","BRT_030"},
		Legendary={},
		Mythic={},
	}},
	-- Phase 13 explicitly adds BRT_031 to Glitch, superseding its former exclusivity.
	Volcano = {weights={0,0,0.1,0.65,0.25,0}, species={
		Common={},
		Uncommon={},
		Rare={"BRT_022","BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={"BRT_031"},
		Mythic={},
	}},
	GlitchZone = {weights={0,0,0.05,0.35,0.6,0}, exclusive="BRT_032", species={
		Common={},
		Uncommon={},
		Rare={"BRT_023","BRT_024","BRT_025"},
		Epic={"BRT_026","BRT_028","BRT_030"},
		Legendary={"BRT_031","BRT_032"},
		Mythic={},
	}},
}
local homeKeys = {
	BRT_001="Forest",
	BRT_002="Forest",
	BRT_003="Forest",
	BRT_004="Forest",
	BRT_005="Forest",
	BRT_006="Forest",
	BRT_007="Forest",
	BRT_008="Forest",
	BRT_009="Forest",
	BRT_010="Forest",
	BRT_011="Forest",
	BRT_012="Beach",
	BRT_013="Forest",
	BRT_014="Beach",
	BRT_015="Beach",
	BRT_016="Swamp",
	BRT_017="Swamp",
	BRT_018="Swamp",
	BRT_019="Forest",
	BRT_020="Beach",
	BRT_021="Swamp",
	BRT_022="Swamp",
	BRT_023="Jungle",
	BRT_024="Jungle",
	BRT_025="Arctic",
	BRT_026="Swamp",
	BRT_027="Jungle",
	BRT_028="Jungle",
	BRT_029="Arctic",
	BRT_030="Jungle",
	BRT_031="Volcano",
	BRT_032="GlitchZone",
}
local rows = {
	{ "Camp", "REGION_CAMP", "Camp", 0, nil, 0, nil, nil, {0,0} },
	{ "Forest", "REGION_FOREST", "Forest", 1, nil, 0, nil, nil, {0,0} },
	{ "Beach", "REGION_BEACH", "Beach", 2, "Forest", 4000000000, {"Uncommon",1}, nil, {15,25} },
	{ "Swamp", "REGION_SWAMP", "Swamp", 3, "Beach", 60000000000, {"Rare",1}, {"Uncommon",3}, {45,60} },
	{ "Jungle", "REGION_JUNGLE", "Jungle", 4, "Swamp", 300000000000, {"Epic",1}, {"Rare",4}, {45,75} },
	{ "Arctic", "REGION_ARCTIC", "Arctic", 5, "Jungle", 1500000000000, {"Epic",2}, {"Rare",5}, {60,90} },
	{ "Volcano", "REGION_VOLCANO", "Volcano", 6, "Arctic", 4000000000000, {"Legendary",1}, {"Epic",3}, {60,90} },
	{ "GlitchZone", "REGION_GLITCH", "Glitch Zone", 7, "Volcano", 10000000000000, {"Legendary",2}, {"Epic",4}, {90,120} },
}
local byKey, byId, ordered = {}, {}, {}
-- Core Loop V2 lever (b): gate prices scale with the global price curve (factor 1 when off).
local priceCurve = require(game:GetService("ReplicatedStorage").Shared.CoreLoop.PriceCurve)
for _, row in rows do
	row[6] = priceCurve.Scale(row[6])
	local definition = {
		key=row[1], regionId=row[2], displayName=row[3], index=row[4], predecessor=row[5],
		price=row[6], branchA=row[7], branchB=row[8], targetMinutes=row[9],
	}
	if definition.branchA then table.freeze(definition.branchA) end
	if definition.branchB then table.freeze(definition.branchB) end
	table.freeze(definition.targetMinutes)
	table.freeze(definition)
	byKey[definition.key], byId[definition.regionId] = definition, definition
	table.insert(ordered, definition)
end
local pools, allowed, homes = {}, {}, {}
local tierOrder={"Common","Uncommon","Rare","Epic","Legendary","Mythic"}
for _,definition in ordered do
	local source=poolRows[definition.key]
	if not source then continue end
	local weights={Secret=0}
	for index,tier in tierOrder do
		weights[tier]=source.weights[index]
		for _,id in source.species[tier] do
			allowed[id]=allowed[id] or {} table.insert(allowed[id],definition.regionId)
		end
		table.freeze(source.species[tier])
	end
	pools[definition.regionId]=table.freeze({species=table.freeze(source.species),
		tierWeights=table.freeze(weights),exclusive=source.exclusive,
		speciesWeightOverrides=table.freeze(if definition.key=="GlitchZone" then {BRT_031=2999,BRT_032=1} else {})})
end
for id,key in homeKeys do homes[id]=byKey[key].regionId end
for _,regions in allowed do table.freeze(regions) end
return table.freeze({
	Pools=table.freeze(pools), HomeBySpecies=table.freeze(homes), AllowedBySpecies=table.freeze(allowed),
	OperationalKeys=table.freeze({"Beach","Swamp","Jungle","Arctic","Volcano","GlitchZone"}), -- Added sequentially only after each area checkpoint.
	ByKey=table.freeze(byKey), ById=table.freeze(byId), Ordered=table.freeze(ordered),
	OrdinaryRarity=table.freeze({Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6}),
	REGION_GUARD_INTERVAL_SECONDS=0.10, UNAUTHORIZED_NOTICE_COOLDOWN_SECONDS=2,
	ACCESS_NOTICE_SECONDS=5, GATE_PROMPT_DISTANCE_STUDS=12,
	GATE_PURCHASE_MAX_DISTANCE_STUDS=16, GATE_PROMPT_HOLD_SECONDS=0.35,
	GATE_REQUEST_MIN_INTERVAL_SECONDS=1, MAX_GATE_REQUEST_ID_LENGTH_BYTES=64,
	MAX_GATE_REGION_KEY_LENGTH_BYTES=32, CLIENT_PENDING_NOTICE_SECONDS=8,
	UNLOCK_CELEBRATION_SECONDS=1.5,
})
