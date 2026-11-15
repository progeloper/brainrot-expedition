--!strict
-- Synthetic starting conditions, not real player exports or balance rules.
-- Seed only confirmed-new disposable Development/Sandbox profiles, then save
-- and acquire a fresh session before measuring returning-state reconstruction.
local Schema = require(script.Parent.Parent.Parent.Data.PlayerProfileSchema)
local Catalog = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotCatalog)
local World = require(game:GetService("ReplicatedStorage").Shared.Config.WorldProgression)
local Fixtures = {}

function Fixtures.Create(cohort: string): any
	local data = Schema.CreateDefault()
	local species = {}
	if cohort == "PartialReturning" then
		species = { "BRT_001", "BRT_002", "BRT_011", "BRT_012" }
		data.Economy.Balance = 100.5
		data.Base.Slots["1"].accumulatedCash = 120.25
		data.Base.Slots["4"].accumulatedCash = 8.75
	elseif cohort == "DevelopedReturning" then
		for index = 1, 12 do
			table.insert(species, string.format("BRT_%03d", index))
		end
		data.Economy.Balance = 100.5
		data.Base.Slots["1"].accumulatedCash = 120.25
		data.Progression.Upgrades.CART_SPEED_1 = true
	elseif cohort == "StartingCashStock" then
		species = { "BRT_001" }
		data.Base.Slots["1"].accumulatedCash = 600.25
	else
		assert(cohort == "Fresh", "Unknown progression fixture cohort")
	end
	for slotIndex, speciesId in species do
		local definition = assert(Catalog.GetDefinition(speciesId))
		assert(definition.launchStatus == "Live", "Fixture requires current Live species")
		local individualId = "7g1-" .. cohort .. "-" .. tostring(slotIndex)
		data.Collection.BrainrotInstances[individualId] = { speciesId = speciesId, metadata = {} }
		data.Base.Slots[tostring(slotIndex)].brainrotId = individualId
		data.WorldProgression.BankedSpecies[speciesId] = {
			rarityAtFirstBank = definition.tier,
			source = "legacy_bank_record",
		}
	end
	assert(Schema.ValidateLoaded(data))
	return data
end

-- Explicit synthetic bank-history fixtures. Branch A for Volcano/Glitch models
-- legacy/guest proof, never claims a first-time solo Legendary route.
function Fixtures.CreateGate(key: string,branch: string,case: string): any
	local definition=assert(World.ByKey[key],"Unknown exact logical region key")
	assert(definition.index>1,"Paid region fixture required")
	assert(not (key=="Beach" and case=="MissingPredecessor"),"Forest is a starter grant; use Swamp or later for this case")
	local proofs={
		Beach={A={"BRT_011"}},Swamp={A={"BRT_019"},B={"BRT_011","BRT_012","BRT_013"}},
		Jungle={A={"BRT_026"},B={"BRT_019","BRT_020","BRT_021","BRT_022"}},
		Arctic={A={"BRT_026","BRT_027"},B={"BRT_019","BRT_020","BRT_021","BRT_022","BRT_023"}},
		Volcano={A={"BRT_031"},B={"BRT_026","BRT_027","BRT_029"}},
		GlitchZone={A={"BRT_031","BRT_032"},B={"BRT_026","BRT_027","BRT_028","BRT_029"}},
	}
	local ids=assert(proofs[key][branch],"Unavailable fixture branch")
	assert(case=="Exact" or case=="Fractional" or case=="Underfunded" or case=="MissingProof"
		or case=="MissingPredecessor" or case=="Owned","Unknown fixture case")
	local data=Schema.CreateDefault()
	data.Economy.Balance=definition.price+(if case=="Fractional" then .125 elseif case=="Underfunded" then -.01 else 0)
	for _,prior in World.Ordered do
		if prior.index>=definition.index then break end
		if prior.index>1 and case~="MissingPredecessor" then data.WorldProgression.PersonalUnlocks[prior.key]={source="legacy_progress"} end
	end
	if case~="MissingProof" then
		for _,id in ids do
			local species=assert(Catalog.GetDefinition(id))
			assert(species.launchStatus=="Live","Fixture cannot activate teased species")
			data.WorldProgression.BankedSpecies[id]={rarityAtFirstBank=species.tier,source="legacy_bank_record"}
		end
	end
	if case=="Owned" then data.WorldProgression.PersonalUnlocks[key]={source="purchase",pricePaid=definition.price,transactionId="fixture-owned:"..key} end
	data.WorldProgression.TestFixture={region=key,branch=branch,case=case,label="Seeded functionality, not earned progress or pacing"}
	assert(Schema.ValidateLoaded(data))
	return data
end

return table.freeze(Fixtures)
