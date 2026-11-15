--!strict
local Config=require(script.Parent.Parent.Config.WorldProgression)
local Catalog=require(script.Parent.Parent.Config.BrainrotCatalog)
local Money=require(script.Parent.CurrencyFormatter)
local Presentation={}
local previews={Beach={"BRT_012","BRT_014","BRT_015"},Swamp={"BRT_021","BRT_026","BRT_030"},
	Jungle={"BRT_027","BRT_023","BRT_028"},Arctic={"BRT_029","BRT_025","BRT_030"},
	Volcano={"BRT_031","BRT_026","BRT_028"},GlitchZone={"BRT_032","BRT_028","BRT_030"}}
function Presentation.Exact(amount: number): string
	return Money.FormatExactCash(amount):sub(2)
end
function Presentation.PendingLabel(submittedAt: number,now: number): string
	return if now-submittedAt>=Config.CLIENT_PENDING_NOTICE_SECONDS then "Still saving your unlock…" else "Saving your unlock…"
end
function Presentation.ResultMessage(code: string): string
	local messages={InsufficientCash="Collect more wallet cash to cover the shortfall.",
		BankedRequirementMissing="Complete one of the banking requirements shown above.",
		PreviousRegionRequired="Personally unlock the previous region first.",
		TooFarFromGate="Move closer to this region's gate.",CharacterUnavailable="Your character must be alive to purchase.",
		ProfileNotReady="Loading your progress…",ProfileNotWritable="Your progress is temporarily unavailable.",
		CurrencyNotReady="Your currency transition is not ready.",RegionUnavailable="Region temporarily unavailable.",
		RateLimited="Please wait a moment before trying again.",PurchasePending="Still saving your unlock…",
		UnknownRegion="This region is unavailable.",InvalidRequest="The purchase request was rejected.",
		PersistenceFailure="The save could not be confirmed. Your progress will be reconciled."}
	return messages[code] or "The purchase was not completed. Refresh your progress."
end
function Presentation.Build(key: string,summary: any,confirming: boolean): any
	local definition=Config.ByKey[key]
	if not definition then return {title="Unavailable",body="Unknown region",enabled=false,action="Unavailable"} end
	local result={title=definition.displayName,enabled=false,action="Unavailable",body="Loading your progress…"}
	if not summary or not summary.ready then return result end
	local gate=summary.gates[key]
	if not gate then return result end
	local names={}
	for _,id in previews[key] or {} do
		local species=Catalog.Get(id)
		if species then table.insert(names,species.displayName) end
	end
	local lines={"New species • Better rarity chances",table.concat(names," • ")}
	if definition.predecessor then
		local priorName=Config.ByKey[definition.predecessor].displayName
		table.insert(lines,if summary.personalUnlocks[definition.predecessor] then priorName.." personally unlocked" else "Personally unlock "..priorName.." first")
	end
	local function branch(value)
		if value then table.insert(lines,tostring(value.count).." / "..tostring(value.required).." "..value.rarity.."+ species banked") end
	end
	branch(gate.branchA)
	if gate.branchB then table.insert(lines,"OR") branch(gate.branchB) end
	if gate.wallet then
		table.insert(lines,"Wallet: "..Presentation.Exact(gate.wallet))
		table.insert(lines,"Cost: "..Presentation.Exact(definition.price))
		if gate.code~="AlreadyUnlocked" and gate.code~="FreeStarterRegion" and gate.shortfall and gate.shortfall>0 then table.insert(lines,"Shortfall: "..Presentation.Exact(gate.shortfall)) end
	end

	local code=gate.code
	if code=="AlreadyUnlocked" or code=="FreeStarterRegion" then
		result.action="Permanently unlocked" table.insert(lines,"Permanently unlocked")
	elseif code=="RegionUnavailable" then table.insert(lines,"Region temporarily unavailable")
	elseif code=="PreviousRegionRequired" then result.action="Previous personal region required"
	elseif code=="BankedRequirementMissing" then result.action="Banking requirement missing"
	elseif code=="InsufficientCash" then result.action="More wallet cash required"
	elseif code=="PurchasePending" then result.action="Saving your unlock…"
	elseif gate.eligible then
		result.enabled=true result.action="Unlock "..definition.displayName
		if confirming then
			result.title="Unlock "..definition.displayName.." permanently?"
			lines={"Cost: "..Presentation.Exact(definition.price),"Your wallet after purchase: "..Presentation.Exact(gate.wallet-definition.price),
				"Banked achievements are kept. No Brainrots are consumed."}
			result.action="Pay "..Presentation.Exact(definition.price).." & Unlock"
		end
	else result.action="Progress unavailable" end
	result.body=table.concat(lines,"\n\n")
	return result
end
return Presentation
