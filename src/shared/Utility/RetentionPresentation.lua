--!strict
-- Client presentation only. Amounts, eligibility and paid state come from the server.
local View = {}
local Cash = require(script.Parent.CurrencyFormatter)
View.QuestOrder = table.freeze({ "bring_them_home", "field_research", "camp_payday" })

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function View.AcceptSnapshot(current: any, incoming: any): boolean
	if
		type(incoming) ~= "table"
		or not finite(incoming.revision)
		or not finite(incoming.retentionRevision)
	then
		return false
	end
	if not current then
		return true
	end
	if incoming.revision ~= current.revision then
		return incoming.revision > current.revision
	end
	if incoming.retentionRevision ~= current.retentionRevision then
		return incoming.retentionRevision > current.retentionRevision
	end
	-- Saving and its covering Ready acknowledgement can share profile revisions
	-- and an os.time second. The server stream sequence orders those observations.
	if incoming.snapshotSequence ~= nil or current.snapshotSequence ~= nil then
		return finite(incoming.snapshotSequence)
			and finite(current.snapshotSequence)
			and incoming.snapshotSequence > current.snapshotSequence
	end
	-- A later read can report availability without changing saved progress.
	return finite(incoming.serverTime) and incoming.serverTime >= (current.serverTime or 0)
end

function View.Remaining(resetAt: any, serverTime: any, elapsed: any): string
	if not finite(resetAt) or not finite(serverTime) or not finite(elapsed) then
		return "--:--:--"
	end
	local seconds = math.max(0, math.ceil(resetAt - serverTime - math.max(0, elapsed)))
	return string.format(
		"%02d:%02d:%02d",
		math.floor(seconds / 3600),
		math.floor(seconds / 60) % 60,
		seconds % 60
	)
end

function View.Row(snapshot: any, row: any, confirmed: any?): any
	-- A later covering save cannot revoke an earlier confirmed payment from
	-- this UTC day. Only prior server-confirmed rows can use this presentation.
	local prior = confirmed and confirmed.daily and row.id and confirmed.daily[row.id]
	if
		snapshot.status == "Saving"
		and confirmed
		and snapshot.dayKey == confirmed.dayKey
		and prior
		and prior.paid == true
		and prior.state == "Completed"
		and confirmed.status == "Ready"
	then
		return View.Row(confirmed, prior)
	end
	local available = snapshot.available == true
		and (snapshot.status == "Ready" or snapshot.status == "Saving")
	local target = if finite(row.target) and row.target > 0 then row.target else 1
	local count = if finite(row.count) then math.clamp(row.count, 0, target) else 0
	-- Never turn threshold progress into a paid checkbox on the client.
	local paid = available
		and snapshot.status == "Ready"
		and row.paid == true
		and row.state == "Completed"
	local state = if not available or row.state == "Unavailable"
		then "Unavailable"
		elseif paid then "Completed"
		elseif snapshot.status == "Saving" or row.state == "Saving" or count >= target then "Saving"
		else "InProgress"
	return { count = count, target = target, ratio = count / target, state = state, paid = paid }
end

function View.Completed(snapshot: any, confirmed: any?): number
	local total = 0
	for _, id in View.QuestOrder do
		local row = snapshot.daily and snapshot.daily[id]
		if row and View.Row(snapshot, row, confirmed).paid then
			total += 1
		end
	end
	return total
end

function View.OpenTab(snapshot: any, previous: string?): string
	local supplies = snapshot and snapshot.supplies
	if
		snapshot
		and snapshot.available == true
		and snapshot.status == "Ready"
		and supplies
		and supplies.claimable == true
	then
		return "Supplies"
	end
	return if previous == "Supplies" or previous == "Collection" then previous else "Dailies"
end

function View.Supply(snapshot: any, pending: boolean): any
	local supply = snapshot and snapshot.supplies
	local available = snapshot
		and snapshot.available == true
		and snapshot.status == "Ready"
		and type(supply) == "table"
	if
		pending
		or (supply and supply.state == "Saving")
		or (snapshot and snapshot.status == "Saving")
	then
		return { enabled = false, text = "Saving…", state = "Saving" }
	end
	if not available then
		return { enabled = false, text = "Supplies unavailable", state = "Unavailable" }
	end
	if supply.claimedToday then
		return { enabled = false, text = "Claimed today", state = "Claimed" }
	end
	return {
		enabled = supply.claimable == true,
		text = "Claim " .. (if finite(supply.rewardCash)
			then Cash.FormatExactCash(supply.rewardCash) .. " Cash"
			else "unavailable"),
		state = "Available",
	}
end

function View.CollectionPage(collection: any, page: number): ({ any }, number, number)
	local entries = if type(collection) == "table" and type(collection.entries) == "table"
		then collection.entries
		else {}
	local pages = math.max(1, math.ceil(#entries / 12))
	local selected = math.clamp(math.floor(if finite(page) then page else 1), 1, pages)
	local result = {}
	for index = (selected - 1) * 12 + 1, math.min(selected * 12, #entries) do
		table.insert(result, entries[index])
	end
	return result, selected, pages
end

function View.Thumbnail(item: any, catalog: any): string?
	if type(item) ~= "table" or item.hidden == true or type(item.id) ~= "string" then
		return nil
	end
	local value = item.thumbnail or (type(catalog) == "table" and catalog[item.id])
	return if type(value) == "string" and value:match("^rbxassetid://%d+$") then value else nil
end

function View.GoalText(goal: any): string
	if type(goal) ~= "table" then
		return "Choose one progression goal. Pinning never purchases or sacrifices."
	end
	if goal.completed then
		return tostring(goal.name) .. " · Completed. Choose your next goal when ready."
	end
	local p = goal.prerequisites or {}
	local result = {}
	if goal.currency == "Cash" then
		local heading = if goal.cashSacrificeAll then "Cash threshold " else "Price "
		table.insert(
			result,
			heading
				.. Cash.FormatExactCash(goal.price or 0)
				.. " · "
				.. (if goal.cashSacrificeAll then "Eligible Cash " else "Wallet ")
				.. Cash.FormatExactCash(goal.balance or 0)
		)
		table.insert(result, "Remaining " .. Cash.FormatExactCash(goal.shortfall or 0) .. " Cash")
	else
		table.insert(
			result,
			string.format(
				"Qualifying owned %s individuals %d/%d",
				tostring(p.minimumRarity or "brainrot"),
				p.qualifyingIndividuals or goal.balance or 0,
				p.requiredIndividuals or goal.price or 0
			)
		)
		table.insert(
			result,
			string.format(
				"Owned %d · Base %s",
				p.ownedCount or 0,
				if p.full then "full" else "must be full"
			)
		)
	end
	if p.satisfied == false then
		table.insert(result, "Previous level " .. tostring(p.previousLevel) .. " required")
	end
	if p.code == "PreviousRegionRequired" then
		table.insert(
			result,
			"Unlock " .. tostring(p.previousRegion or "the previous region") .. " first"
		)
	end
	if p.banking == false then
		local branches = {}
		for _, branch in { p.branchA, p.branchB } do
			if branch then
				table.insert(
					branches,
					string.format(
						"%s species %d/%d",
						tostring(branch.rarity),
						branch.count or 0,
						branch.required or 0
					)
				)
			end
		end
		table.insert(result, "Banked proof: " .. table.concat(branches, " OR "))
	end
	if goal.warning then
		table.insert(result, goal.warning)
	end
	return table.concat(result, "\n")
end

function View.PushNotice(queue: { any }, item: any)
	for _, queued in queue do
		if queued.key == item.key then
			queued.text, queued.duration, queued.expires = item.text, item.duration, item.expires
			return
		end
	end
	if #queue >= 3 then
		table.remove(queue, 1)
	end
	table.insert(queue, item)
end

function View.ReturnLines(snapshot: any): { string }
	local result = {}
	for _, row in snapshot.returnRows or {} do
		if #result >= 3 then
			break
		end
		if row.kind == "Refresher" then
			table.insert(
				result,
				row.text or "Shoot to sleep → pick up → bank → collect platform earnings."
			)
		elseif row.kind == "Goal" and row.goal then
			table.insert(
				result,
				tostring(row.goal.name)
					.. " · "
					.. (
						if row.goal.completed
							then "Completed"
							else "Remaining " .. (if row.goal.currency == "Cash"
								then Cash.FormatExactCash(row.goal.shortfall or 0) .. " Cash"
								else tostring(row.goal.shortfall or 0)
									.. " qualifying owned individuals")
					)
			)
		elseif row.kind == "Supply" and row.supplies then
			table.insert(
				result,
				"Supply claim "
					.. tostring(row.supplies.nextLifetimeClaim or 1)
					.. (
						if row.supplies.claimedToday
							then " · Next UTC date"
							else " · Available in Brainrots › Quests"
					)
			)
		elseif row.kind == "Milestone" and row.milestone then
			table.insert(
				result,
				tostring(row.milestone.label)
					.. " · "
					.. tostring(row.count or 0)
					.. "/"
					.. tostring(row.milestone.required or 0)
					.. " species"
			)
		end
	end
	return result
end

-- Measured existing right-HUD stack feeds this small desktop/compact preset.
-- Insets are already applied by ScreenGui.DeviceSafeInsets, exactly once.
function View.Layout(
	width: number,
	height: number,
	stackBottom: number,
	touch: boolean,
	safeTop: number?
): any
	local compact = width < 900 or height < 600
	local entryWidth = if touch or compact then 112 else 132
	local entryTop = math.max(16, stackBottom + 8)
	local reservedBottom = if touch and not compact then 156 else 16
	local panelWidth = math.max(1, math.min(400, width - (if compact then 24 else 32)))
	local top = if compact then math.max(12, safeTop or 0) else entryTop + 44 + 8
	local available = math.max(1, height - reservedBottom - top - (if compact then 12 else 0))
	local panelHeight = math.min(560, available)
	return {
		compact = compact,
		entryWidth = entryWidth,
		entryTop = entryTop,
		entryLeft = width - 16 - entryWidth,
		panelLeft = if compact then (width - panelWidth) / 2 else width - 16 - panelWidth,
		panelTop = top,
		panelWidth = panelWidth,
		panelHeight = panelHeight,
		reservedBottom = reservedBottom,
		-- Header/tabs/edges use 128px; keep one complete 44px control visible.
		usable = panelHeight >= 128 + 44 and panelWidth >= 240,
	}
end

return table.freeze(View)
