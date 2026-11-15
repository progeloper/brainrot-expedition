--!strict
-- Chariot team ("Manage Team") controller: logic only. The view is the Plate window in
-- UI/Screens/TeamScreen.lua (MenusV2 id "Team"); it draws Controller.View() and calls the facade
-- built in `context()`. Every remote call, payload, timer and attribute stays here:
--   ChariotTeamRequest:InvokeServer({ operation, requestId, session, cartGeneration, expectedTeamRevision, ... })
--     Equip / Replace { slot, individualId, expectedIndividualId = id or false }
--     Unequip { slot, expectedIndividualId }     Buy { slot, configVersion }
--     Refresh { session, cartGeneration }        Close { session }        Open {}
--   ChariotTeamUpdate { kind = "Open" | "Close" | "State" | "Error" }
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Gui = game:GetService("GuiService")
local CAS = game:GetService("ContextActionService")
local Run = game:GetService("RunService")
local Http = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Rules = require(RS.Shared.Utility.ChariotTeamRules)
local Config = require(RS.Shared.Config.ChariotTeam)
local Money = require(RS.Shared.Utility.CurrencyFormatter)
local EffectText = require(RS.Shared.Utility.ChariotEffectText)
local ShieldPresentation = require(RS.Shared.Utility.CartShieldPresentation)
local SeatState = require(RS.Shared.Utility.HumanoidSeatState)
local InputUnstick = require(script.Parent.Parent.Utility.InputUnstick)
local WINDOW_ID = "Team"
local player = Players.LocalPlayer
local Controller = {}
local started = false
local connections = {}
local snapshot
local requestRemote
local updateRemote
local selectedSlot = 1
local candidate = nil
-- "Team": slots + roster. "Details": the in-window side panel for `candidate`.
local subview = "Team"
local open = false
local pending = false
local generation = 0
local controls
local priorControls
local previousFocus
local previousCamera
local status = ""
local deathConnection
local characterConnection
local messages = {
	OK = "Team updated.",
	ALREADY_APPLIED = "Already applied.",
	NOT_READY = "Management is temporarily unavailable while your profile loads.",
	CONTEXT_LOST = "Park your cart in Camp to manage your team.",
	WRONG_CART = "Your cart changed. Return to your parked cart.",
	STALE_STATE = "Your team changed. Choose again.",
	STALE_OFFER = "The offer changed. Review the current price.",
	SLOT_LOCKED = "Unlock the previous slot first.",
	ALREADY_EQUIPPED = "Already equipped in another slot. Choose another brainrot.",
	NOT_ON_PLATFORM = "That brainrot left its platform. Choose another.",
	NOT_OWNED = "That brainrot is no longer available.",
	INSUFFICIENT_CASH = "You need more collected cash.",
	RATE_LIMITED = "Please wait a moment and try again.",
	CATALOGUE_UNAVAILABLE = "That brainrot is temporarily unavailable.",
	INVALID_REQUEST = "Unable to complete this action.",
	TEAM_ENTITLEMENT_INVALID = "Slot data needs repair. Management is unavailable.",
	TEAM_SCHEMA_UNSUPPORTED = "Team data requires a newer game version.",
}
local EXPLANATION =
	"Your equipped brainrots stay at your base and keep earning.\nSlot upgrades work on all your carts."
local GUIDANCE =
	"Only the best matching providers count. Rare traits raise that limit. Extra members remain visible.\nThis selection does not change weapon sleep damage.\nCurrent Live species allow at most two Speed providers and one Burst provider to help immediately. Shield requires a future released provider."
local function number(v, precision)
	return (string.format("%." .. tostring(precision or 2) .. "f", v or 0):gsub("0+$", ""):gsub("%.$", ""))
end
-- The client UI modules are required on first use: specs load this module on the server for
-- CanShowManagementPrompt, where no Plate window may be built.
local function menus(): any
	return require(script.Parent.Parent.UI.MenusV2) :: any
end
local function teamScreen(): any
	return require(script.Parent.Parent.UI.Screens.TeamScreen) :: any
end
local function clearCandidate()
	candidate = nil
	subview = "Team"
end
local function accept(s)
	if not s then
		return
	end
	if
		snapshot
		and s.session == snapshot.session
		and (s.teamRevision < snapshot.teamRevision or s.rosterRevision < snapshot.rosterRevision)
	then
		return
	end
	if snapshot and s.session == snapshot.session then
		local reserve = ShieldPresentation.PreserveNewerReserve(
			snapshot.shield,
			s.shield,
			s.cartGeneration == snapshot.cartGeneration
		)
		if reserve ~= s.shield then
			s = table.clone(s)
			s.shield = reserve
		end
	end
	snapshot = s
	if candidate then
		local found = false
		for _, r in s.rows do
			if r.individualId == candidate.individualId then
				candidate = r
				found = true
				break
			end
		end
		if not found then
			clearCandidate()
			status = "That brainrot left its platform. Choose another."
		end
	end
end
local requestSequence = 0
local render
local close
local submit
local function back()
	if subview ~= "Team" then
		clearCandidate()
		render()
	else
		close(true)
	end
end
local function lock()
	previousFocus = Gui.SelectedObject
	local camera = workspace.CurrentCamera
	previousCamera = { camera = camera, kind = camera.CameraType, subject = camera.CameraSubject, cf = camera.CFrame }
	camera.CameraType = Enum.CameraType.Scriptable
	local pm = player.PlayerScripts:FindFirstChild("PlayerModule")
	if pm then
		local ok, module = pcall(require, pm)
		if ok then
			controls = module:GetControls()
			priorControls = controls.controlsEnabled
			if priorControls then
				controls:Disable()
			end
		end
	end
	CAS:BindActionAtPriority(
		"ChariotTeamModal",
		function(_, state, input)
			if
				state == Enum.UserInputState.Begin
				and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB)
			then
				back()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		4000,
		Enum.KeyCode.Escape,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.E,
		Enum.KeyCode.Q,
		Enum.KeyCode.T,
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonL3,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonL2
	)
	player:SetAttribute("ChariotTeamMenuOpen", true)
end
local function unlock()
	CAS:UnbindAction("ChariotTeamModal")
	player:SetAttribute("ChariotTeamMenuOpen", nil)
	if controls and priorControls then
		local dazeModule = script.Parent:FindFirstChild("PlayerDazeController")
		if dazeModule and dazeModule:IsA("ModuleScript") then
			(require(dazeModule) :: any).ResumeDefaultControlsWhenAllowed(controls)
		else
			controls:Enable()
		end
	end
	controls = nil
	priorControls = nil
	if
		previousCamera
		and workspace.CurrentCamera == previousCamera.camera
		and previousCamera.camera.CameraType == Enum.CameraType.Scriptable
	then
		previousCamera.camera.CameraType = previousCamera.kind
		previousCamera.camera.CameraSubject = previousCamera.subject
		previousCamera.camera.CFrame = previousCamera.cf
	end
	previousCamera = nil
	if InputUnstick.Enabled() then
		-- Playtest Fixes 2 A1: never hand back a HUD/orphaned selection (it blocked driving and firing).
		Gui.SelectedObject = nil
	else
		Gui.SelectedObject = if previousFocus and previousFocus.Parent then previousFocus else nil
	end
	previousFocus = nil
end
-- `notify` sends { operation = "Close", session } to the server; `instant` skips the window's
-- close animation (MenusV2 passes it when another window replaces this one).
close = function(notify, instant)
	if not open then
		return
	end
	open = false
	generation += 1
	pending = false
	clearCandidate()
	teamScreen().close(instant == true)
	menus().cleared(WINDOW_ID)
	unlock()
	if deathConnection then
		deathConnection:Disconnect()
		deathConnection = nil
	end
	if notify and snapshot then
		task.spawn(function()
			pcall(function()
				requestRemote:InvokeServer({ operation = "Close", session = snapshot.session })
			end)
		end)
	end
end

------------------------------------------------------------------ view model (text only; no instances)
local statuses = {
	contributing = "Contributing",
	below_limit = "Below contributor limit",
	capped = "Capped",
	unavailable = "Unavailable",
	future_hit = "Future Hit benefit",
}
local function speedLimits()
	return { speed = (require(RS.Shared.Config.CartMovementSafety) :: any).MaximumTravelSpeed }
end
local function memberText(detail, stats)
	if not detail then
		return "Unavailable"
	end
	local shieldText = EffectText.Member(detail, stats or snapshot and snapshot.stats)
	if shieldText then
		return shieldText
	end
	if detail.effect == "Speed" and detail.selected and snapshot then
		local effective = Rules.Effective({ speed = snapshot.baseSpeed or 0 }, stats or snapshot.stats, speedLimits())
		if effective.clipped.speed then
			return "Capped by physical limit"
		end
	end
	return statuses[detail.status] or "Unavailable"
end
-- The short member status used on slot cards.
local function slotStatus(detail)
	return if detail and detail.status == "below_limit"
		then "Below limit"
		elseif detail and detail.status == "future_hit" then "Future Hit"
		else memberText(detail)
end
local function effectiveText(stats)
	local e = Rules.Effective({ speed = snapshot and snapshot.baseSpeed or 0 }, stats, speedLimits())
	return EffectText.Totals(stats, e)
end
local function rowFor(id)
	if snapshot and id then
		for _, row in snapshot.rows do
			if row.individualId == id then
				return row
			end
		end
	end
	return nil
end
local function currentName(id)
	local row = rowFor(id)
	return if row then row.name else "Unavailable brainrot"
end
local function rate(row)
	return Money.FormatExactCash(math.floor(row.cps * 100 + 0.5) / 100) .. "/s"
end
local function effectLine(row)
	if not row.effect then
		return EffectText.Value(row.effect, row.contribution)
	end
	return tostring(row.effect) .. " " .. EffectText.Value(row.effect, row.contribution)
end
-- Why a slot cannot be bought now (nil when it can). Mirrors the legacy Buy gate.
local function buyBlock(slot)
	local cost = Config.Prices[slot]
	if slot ~= snapshot.capacity + 1 then
		return "Unlock Slot " .. (slot - 1) .. " First"
	elseif snapshot.disabled then
		return "Unavailable"
	elseif snapshot.balance < cost then
		return "Need " .. Money.FormatExactCash(cost - snapshot.balance) .. " More"
	end
	return nil
end
local function statusText()
	if status ~= "" then
		return status
	end
	if selectedSlot <= snapshot.capacity and #snapshot.rows > 0 then
		local allAssigned = true
		for _, row in snapshot.rows do
			if not row.equippedSlot then
				allAssigned = false
				break
			end
		end
		if allAssigned then
			return "All available brainrots are assigned. Unequip one to change slots."
		end
	end
	if snapshot.capacity == Config.MaxSlots then
		return "Maximum slots unlocked"
	end
	return ""
end
local function slotModels()
	local slots = {}
	for i = 1, Config.MaxSlots do
		local id = snapshot.assignments[tostring(i)]
		local locked = i > snapshot.capacity
		local selected = i == selectedSlot
		local slot: any = { index = i, selected = selected, locked = locked }
		if locked then
			local nextOffer = i == snapshot.capacity + 1
			local price = Money.FormatExactCash(Config.Prices[i])
			slot.state = "Locked"
			slot.title = if nextOffer then "Unlock Slot " .. i else "Locked"
			slot.line1 = price
			slot.line2 = if nextOffer then "Works on all your carts" else "Unlock slot " .. (i - 1) .. " first"
			if nextOffer then
				local block = buyBlock(i)
				slot.action = if block
					then { kind = "Blocked", text = block }
					else { kind = "Buy", text = price, enabled = not pending }
			end
		elseif id then
			local row = rowFor(id)
			slot.state = "Equipped"
			slot.individualId = id
			slot.speciesId = row and row.speciesId
			slot.rarity = row and row.classification
			slot.title = currentName(id)
			slot.line1 = if row then effectLine(row) else "Contributes no effect"
			slot.line2 = slotStatus(snapshot.stats.details[tostring(i)])
			if selected then
				slot.action = { kind = "Unequip", text = "Unequip", enabled = not pending }
			end
		else
			slot.state = "Empty"
			slot.title = "Empty"
			slot.line1 = "Choose brainrot"
		end
		if pending and selected then
			slot.line1 = "Pending…"
			slot.line2 = nil
		end
		slots[i] = slot
	end
	return slots
end
local function rowModels(assigned)
	local rows = {}
	for index, row in snapshot.rows do
		local member = row.equippedSlot and snapshot.stats.details[tostring(row.equippedSlot)]
		local action
		if row.equippedSlot then
			action = { kind = "OnTeam", text = "On Team" }
		elseif row.valid ~= true or snapshot.disabled then
			action = { kind = "Blocked", text = "Unavailable" }
		else
			action = {
				kind = if assigned then "Replace" else "Equip",
				text = if assigned then "Replace" else "Equip",
				enabled = not pending,
			}
		end
		rows[index] = {
			individualId = row.individualId,
			speciesId = row.speciesId,
			name = row.name,
			rarity = row.classification,
			platform = row.platform,
			equippedSlot = row.equippedSlot,
			inspected = subview == "Details" and candidate ~= nil and candidate.individualId == row.individualId,
			income = "+" .. rate(row),
			effect = (effectLine(row):gsub(" seconds", " s")),
			status = if row.equippedSlot
				then "Equipped in slot " .. row.equippedSlot .. " · " .. memberText(member)
				elseif row.valid then "Available"
				else "Unavailable",
			action = action,
		}
	end
	return rows
end
local function detailsModel(assigned)
	local chosen = candidate
	if subview ~= "Details" or not chosen then
		return nil
	end
	local elsewhere = chosen.equippedSlot and chosen.equippedSlot ~= selectedSlot
	local proposed = if elsewhere
		then snapshot.stats
		else Rules.Preview(snapshot.entries, selectedSlot, {
			individualId = chosen.individualId,
			speciesId = chosen.speciesId,
			definition = (require(RS.Shared.Config.BrainrotCatalog) :: any).Get(chosen.speciesId),
		})
	local factor = if elsewhere then nil else proposed.details[tostring(selectedSlot)]
	local own = chosen.equippedSlot and snapshot.stats.details[tostring(chosen.equippedSlot)]
	local now = workspace:GetServerTimeNow()
	local notes = {}
	if
		(snapshot.shield and snapshot.shield.protectedUntil or 0) > now
		and (proposed.shieldCapacity or 0) < (snapshot.stats.shieldCapacity or 0)
	then
		table.insert(notes, "Lower capacity does not end the existing protected window.")
	end
	table.insert(notes, "This selection does not change weapon sleep damage.")
	local ready = chosen.valid == true and chosen.equippedSlot == nil and not snapshot.disabled
	local action
	if assigned and chosen.individualId == assigned then
		-- Already this slot's member: the panel offers Unequip instead.
		action = {
			kind = "Blocked",
			text = "In Slot " .. selectedSlot,
			reason = "Equipped in slot " .. selectedSlot,
		}
	elseif chosen.equippedSlot and chosen.individualId ~= assigned then
		action = {
			kind = "Blocked",
			text = "In Slot " .. chosen.equippedSlot,
			reason = "Already equipped in slot " .. chosen.equippedSlot,
		}
	elseif not ready then
		action = { kind = "Blocked", text = "Select Another", reason = "Choose another brainrot" }
	else
		action = {
			kind = if assigned then "Replace" else "Equip",
			text = if assigned then "Replace" else "Equip",
			reason = (if assigned then "Replace slot " else "Equip to slot ") .. selectedSlot,
			enabled = not pending,
		}
	end
	return {
		individualId = chosen.individualId,
		speciesId = chosen.speciesId,
		name = chosen.name,
		rarity = chosen.classification,
		platform = "Platform " .. chosen.platform,
		income = rate(chosen) .. " unchanged",
		effect = effectLine(chosen) .. " · " .. EffectText.Trait(chosen),
		copy = (if chosen.effect == "Shield"
			then "Whole charge · no copy penalty"
			else "Copy factor " .. number(factor and factor.duplicateFactor or own and own.duplicateFactor))
			.. " · "
			.. memberText(factor or own, proposed),
		before = effectiveText(snapshot.stats),
		after = effectiveText(proposed),
		description = EffectText.Description(chosen),
		reserve = EffectText.Reserve(snapshot.shield, now),
		notes = notes,
		action = action,
		-- Unequip here only when the inspected brainrot is the one in the selected slot.
		unequip = if assigned and chosen.individualId == assigned then { enabled = not pending } else nil,
	}
end
local function offerModel()
	local cost = Config.Prices[selectedSlot]
	local nextOffer = selectedSlot == snapshot.capacity + 1
	local lines = {
		"Price " .. Money.FormatExactCash(cost),
		"Wallet " .. Money.FormatExactCash(snapshot.balance),
		if nextOffer
			then "New capacity: " .. selectedSlot .. " slots unlocked"
			else "Unlock slot " .. (selectedSlot - 1) .. " first",
		"Available on all your carts.",
	}
	local block = buyBlock(selectedSlot)
	return {
		slot = selectedSlot,
		title = "Unlock Slot " .. selectedSlot,
		lines = lines,
		shortfall = if snapshot.balance < cost
			then "Shortfall " .. Money.FormatExactCash(cost - snapshot.balance)
			else nil,
		action = if block
			then { kind = "Blocked", text = block }
			else {
				kind = "Buy",
				text = "Buy Slot " .. selectedSlot .. " · " .. Money.FormatExactCash(cost),
				enabled = not pending,
			},
	}
end
-- Everything TeamScreen draws, from the server snapshot and config only. nil while closed.
function Controller.View(): any
	if not open or not snapshot then
		return nil
	end
	local assigned = snapshot.assignments[tostring(selectedSlot)] or nil
	local lockedSlot = selectedSlot > snapshot.capacity
	local totals = effectiveText(snapshot.stats)
	local summary = {}
	for line in string.gmatch(totals, "[^\n]+") do
		table.insert(summary, { kind = "stat", text = string.match(line, "^(.-) · ") or line })
	end
	table.insert(summary, { kind = "cash", text = "Wallet " .. Money.FormatExactCash(snapshot.balance) })
	table.insert(summary, { kind = "info", text = tostring(snapshot.cartName) })
	if snapshot.stats.unavailable > 0 then
		table.insert(summary, { kind = "alert", text = snapshot.stats.unavailable .. " unavailable" })
	end
	return {
		source = snapshot,
		pending = pending,
		selectedSlot = selectedSlot,
		stat = "Slots " .. snapshot.stats.count .. "/" .. snapshot.capacity,
		summary = summary,
		status = statusText(),
		totals = totals
			.. "\n"
			.. EffectText.Reserve(snapshot.shield, workspace:GetServerTimeNow())
			.. "\nWeapon sleep damage is unchanged.",
		guidance = GUIDANCE,
		explanation = EXPLANATION,
		slots = slotModels(),
		offer = if lockedSlot then offerModel() else nil,
		rosterTitle = "Choose For Slot " .. selectedSlot,
		rosterEmpty = "Shoot a brainrot to sleep, pick it up and bank it on a base platform, then return here to equip it.",
		rows = if lockedSlot then {} else rowModels(assigned),
		details = if lockedSlot then nil else detailsModel(assigned),
	}
end
render = function()
	if not open or not snapshot then
		return
	end
	teamScreen().update()
end

------------------------------------------------------------------ requests
submit = function(operation, fields)
	if not open or pending then
		return
	end
	requestSequence += 1
	local requestToken = requestSequence
	pending = true
	status = "Checking…"
	local g = generation
	local p = fields or {}
	p.operation = operation
	p.requestId = Http:GenerateGUID(false)
	p.session = snapshot.session
	p.cartGeneration = snapshot.cartGeneration
	p.expectedTeamRevision = snapshot.teamRevision
	render()
	local done = false
	task.delay(2, function()
		if not done and open and generation == g and requestSequence == requestToken then
			status = "Still checking…"
			render()
		end
	end)
	task.delay(8, function()
		if done or not open or generation ~= g or requestSequence ~= requestToken then
			return
		end
		status = "Checking your current team…"
		render()
		task.spawn(function()
			local ok, r = pcall(function()
				return requestRemote:InvokeServer({
					operation = "Refresh",
					session = p.session,
					cartGeneration = p.cartGeneration,
				})
			end)
			if open and generation == g and requestSequence == requestToken and not done and ok and r and r.ok then
				accept(r.state)
				pending = false
				status = "Current team refreshed. Review before trying again."
				render()
			end
		end)
	end)
	task.spawn(function()
		local ok, r = pcall(function()
			return requestRemote:InvokeServer(p)
		end)
		done = true
		if not open or generation ~= g or requestSequence ~= requestToken then
			return
		end
		if ok and r then
			accept(r.state)
		end
		pending = false
		if not ok then
			status = "Connection delayed. Refreshing your team…"
			submit("Refresh", {})
			return
		end
		status = messages[r.code] or "Management is temporarily unavailable."
		if r.ok then
			if operation == "Buy" then
				selectedSlot = p.slot
				clearCandidate()
				status = "Slot " .. p.slot .. " unlocked."
			elseif operation == "Equip" or operation == "Replace" then
				status = (candidate and candidate.name or "Brainrot") .. " equipped."
				clearCandidate()
			elseif operation == "Unequip" then
				clearCandidate()
				status = "Brainrot unequipped."
			end
		else
			clearCandidate()
		end
		render()
	end)
end

------------------------------------------------------------------ view actions (TeamScreen calls these)
local function selectSlot(slot)
	if not open or pending or not snapshot then
		return
	end
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Config.MaxSlots then
		return
	end
	selectedSlot = slot
	clearCandidate()
	status = ""
	render()
end
-- Opens (or, tapped again, closes) the details side panel for a roster brainrot.
local function inspect(individualId)
	if not open or pending or not snapshot or selectedSlot > snapshot.capacity then
		return
	end
	local row = rowFor(individualId)
	if not row then
		return
	end
	if subview == "Details" and candidate and candidate.individualId == individualId then
		clearCandidate()
	else
		candidate = row
		subview = "Details"
	end
	status = ""
	render()
end
local function equip(individualId)
	if not open or pending or not snapshot or selectedSlot > snapshot.capacity then
		return
	end
	local row = rowFor(individualId)
	if not row or row.valid ~= true or row.equippedSlot ~= nil or snapshot.disabled then
		return
	end
	local id = snapshot.assignments[tostring(selectedSlot)]
	-- The chosen brainrot names the result message and is dropped if it leaves its platform.
	candidate = row
	submit(
		if id then "Replace" else "Equip",
		{ slot = selectedSlot, individualId = row.individualId, expectedIndividualId = id or false }
	)
end
local function unequip()
	if not open or pending or not snapshot then
		return
	end
	local id = snapshot.assignments[tostring(selectedSlot)]
	if not id then
		return
	end
	submit("Unequip", { slot = selectedSlot, expectedIndividualId = id })
end
local function buy(slot)
	if not open or pending or not snapshot then
		return
	end
	if type(slot) ~= "number" or slot <= snapshot.capacity or slot > Config.MaxSlots or buyBlock(slot) then
		return
	end
	selectedSlot = slot
	clearCandidate()
	submit("Buy", { slot = selectedSlot, configVersion = snapshot.configVersion })
end
local facade
local function context()
	if not facade then
		facade = table.freeze({
			view = Controller.View,
			selectSlot = selectSlot,
			inspect = inspect,
			closeDetails = function()
				if open and subview ~= "Team" then
					back()
				end
			end,
			equip = equip,
			unequip = unequip,
			buy = buy,
			-- ✕ / scrim: works while a request is pending, as the legacy Close button did.
			close = function()
				close(true)
			end,
		})
	end
	return facade
end

------------------------------------------------------------------ open
-- The ManageTeam prompt on the local player's own cart (the server's Open event doesn't name it).
local function ownCartPrompt(): ProximityPrompt?
	for _, prompt in CollectionService:GetTagged("ChariotTeamPrompt") do
		if prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(workspace) then
			local owner: Instance? = prompt.Parent
			while owner and owner ~= workspace and owner:GetAttribute("OwnerUserId") == nil do
				owner = owner.Parent
			end
			if owner and owner:GetAttribute("OwnerUserId") == player.UserId then
				return prompt
			end
		end
	end
	return nil
end
local function show(s, anchor: ProximityPrompt?)
	if open then
		accept(s)
		render()
		return
	end
	snapshot = s
	generation += 1
	open = true
	pending = false
	selectedSlot = 1
	clearCandidate()
	status = if s.disabled then messages[s.disabled] or "Equipment data needs repair." else ""
	lock()
	-- MenusV2 closes whatever window was open; an anchored window also closes (with the same
	-- Close payload) when the player leaves the cart, dies or drives off.
	menus().setOpen(WINDOW_ID, function(instant)
		close(true, instant)
	end, anchor)
	teamScreen().open(context())
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		deathConnection = h.Died:Connect(function()
			close(true)
		end)
	end
end
-- Presentation only. Server team eligibility remains authoritative.
function Controller.CanShowManagementPrompt(
	menuOpen: boolean,
	ownsCart: boolean,
	humanoid: Humanoid?,
	carrying: boolean
): boolean
	return not menuOpen
		and ownsCart
		and humanoid ~= nil
		and humanoid.Health > 0
		and not SeatState.IsSeated(humanoid)
		and not carrying
end
function Controller.Start()
	if started then
		return
	end
	started = true
	local remotes = RS:WaitForChild("Remotes")
	requestRemote = remotes:WaitForChild("ChariotTeamRequest")
	updateRemote = remotes:WaitForChild("ChariotTeamUpdate")
	table.insert(
		connections,
		updateRemote.OnClientEvent:Connect(function(value)
			if value.kind == "Open" then
				-- Sent after the cart's "Manage Team" prompt (T / ButtonY).
				show(value.state, ownCartPrompt())
			elseif value.kind == "Close" then
				close(false)
			elseif value.kind == "State" then
				if open and snapshot and value.state and value.state.session ~= snapshot.session then
					close(true)
				end
				accept(value.state)
				if open then
					render()
				end
			elseif value.kind == "Error" then
				status = messages[value.code] or "Management unavailable."
				if open then
					render()
				else
					pcall(function()
						game:GetService("StarterGui")
							:SetCore("SendNotification", { Title = "Manage Team", Text = status, Duration = 3 })
					end)
				end
			end
		end)
	)
	local function hideTeamWorldPrompt(prompt)
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end
	for _, prompt in CollectionService:GetTagged("ChariotTeamPrompt") do
		hideTeamWorldPrompt(prompt)
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal("ChariotTeamPrompt"):Connect(hideTeamWorldPrompt))
	characterConnection = player.CharacterAdded:Connect(function()
		close(true)
	end)
end
-- Playtest Fixes 2 A2 watchdog: the modal lock (attribute, CAS sink incl. R2, disabled controls)
-- outlived its window. Returns true when it healed something.
function Controller.HealStale(): boolean
	local locked = player:GetAttribute("ChariotTeamMenuOpen") == true
	if not locked then
		return false
	end
	if not open then
		unlock()
		return true
	end
	if menus().currentId() ~= WINDOW_ID then
		close(true, true)
		return true
	end
	return false
end

function Controller.Destroy()
	close(true, true)
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if characterConnection then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	if started then
		teamScreen().destroy()
	end
	started = false
end
function Controller.OpenFromMenu()
	if not started or not requestRemote then
		return false
	end
	requestSequence += 1
	local operation = requestSequence
	local ok, result = pcall(requestRemote.InvokeServer, requestRemote, { operation = "Open" })
	if ok and type(result) == "table" and result.ok then
		show(result.state)
		return true
	end
	local code = if ok and type(result) == "table" then result.code else "NOT_READY"
	require(script.Parent.ExactHudController).Feedback(
		messages[code] or "Management unavailable.",
		"team-open:" .. operation
	)
	return false
end
function Controller._StudioOpen()
	assert(Run:IsStudio() and not require(RS.Shared.Config.Environment).IsProduction, "Studio review only")
	local result = requestRemote:InvokeServer({ operation = "Open" })
	if result.ok then
		show(result.state)
	end
	return result.code
end
function Controller.Diagnostics()
	-- `previews` counted live ViewportFrame previews; the Plate window uses static display shots.
	return { open = open, pending = pending, previews = 0, selectedSlot = selectedSlot, subview = subview }
end
return Controller
