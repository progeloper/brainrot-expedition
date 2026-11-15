--!strict
-- Retention logic owner (no view). Every amount, claim, discovery and selection comes from the
-- existing authoritative retention snapshot/request owner. The views live in
-- UI/Screens/BrainrotsScreen (Quests + Index tabs) and UI/Screens/DailyGiftScreen; they read
-- GetSnapshot/GetView and send the legacy payloads through Request().
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Environment = require(RS.Shared.Config.Environment)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)
local View = require(RS.Shared.Utility.RetentionPresentation)
local Cash = require(RS.Shared.Utility.CurrencyFormatter)
local RemoteBinding = require(script.Parent.Parent.Utility.RemoteDependencyBinding)
local player = Players.LocalPlayer
local Controller = {}
local started, generation = false, 0
local connections, bindings = {}, {}
local remote, updateRemote, snapshot, confirmed, receivedAt
local requestPending, requestSerial, lastRequestAt = nil, 0, -math.huge
local requestUnavailable = false
local returnPending = nil
local returnShown, resetRequestedDay = false, nil
local request
local criticalWarnings
-- Screens listen for snapshot / request-state changes (fired wherever the legacy panel re-rendered).
Controller.Changed = Instance.new("BindableEvent")
local function fireChanged()
	Controller.Changed:Fire()
end
-- The two warning labels hold back the return notice. Their lifetime and property
-- changes must re-check it even when no snapshot event follows.
function Controller.CreateCriticalWarningObserver(playerGui, changed)
	local stopped, root = false, nil
	local outer, rootConnections, labelConnections = {}, {}, {}
	local function clear(scope)
		for _, connection in scope do
			connection:Disconnect()
		end
		table.clear(scope)
	end
	local function notify()
		if not stopped then
			changed()
		end
	end
	local function bindLabels()
		if stopped then
			return
		end
		clear(labelConnections)
		for _, name in { "CriticalReturn", "FocusedEscapeWarning" } do
			local object = root and root:FindFirstChild(name)
			if object and object:IsA("TextLabel") then
				table.insert(labelConnections, object:GetPropertyChangedSignal("Visible"):Connect(notify))
				table.insert(labelConnections, object:GetPropertyChangedSignal("Text"):Connect(notify))
			end
		end
		notify()
	end
	local function bindRoot()
		if stopped then
			return
		end
		local current = playerGui:FindFirstChild("Phase12CriticalWarnings")
		if current == root then
			return
		end
		clear(rootConnections)
		root = current
		if root then
			local function childChanged(child)
				if child.Name == "CriticalReturn" or child.Name == "FocusedEscapeWarning" then
					bindLabels()
				end
			end
			table.insert(rootConnections, root.ChildAdded:Connect(childChanged))
			table.insert(rootConnections, root.ChildRemoved:Connect(childChanged))
		end
		bindLabels()
	end
	local function rootChanged(child)
		if child.Name == "Phase12CriticalWarnings" then
			bindRoot()
		end
	end
	table.insert(outer, playerGui.ChildAdded:Connect(rootChanged))
	table.insert(outer, playerGui.ChildRemoved:Connect(rootChanged))
	bindRoot()
	return {
		GetConnectionCount = function()
			return #outer + #rootConnections + #labelConnections
		end,
		Disconnect = function()
			stopped = true
			clear(outer)
			clear(rootConnections)
			clear(labelConnections)
			root = nil
		end,
	}
end
local function obstructed()
	if
		GuiService.MenuIsOpen
		or player:GetAttribute("Phase13ShopOpen") == true
		or player:GetAttribute("Phase13CinematicActive") == true
		or player:GetAttribute("Phase13ConsentDialogOpen") == true
		or player:GetAttribute("Phase13CompareDialogOpen") == true
	then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local warnings = playerGui and playerGui:FindFirstChild("Phase12CriticalWarnings")
	for _, name in { "CriticalReturn", "FocusedEscapeWarning" } do
		local object = warnings and warnings:FindFirstChild(name)
		if object and object:IsA("TextLabel") and object.Visible and object.Text ~= "" then
			return true
		end
	end
	return false
end
local function safeForNotice()
	if
		obstructed()
		or player:GetAttribute("MenusV2Open") ~= nil
		or UIS:GetFocusedTextBox() ~= nil
		or player:GetAttribute("CarriedItemId") ~= nil
	then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		return false
	end
	if character then
		for _, child in character:GetChildren() do
			if
				child:IsA("Tool") and (child:GetAttribute("BrainrotSleepLauncher") == true or child.Name == "Hunting")
			then
				return false
			end
		end
	end
	return true
end
local function notify(key, text, _duration)
	if key == "discovery" then
		return
	end
	if snapshot then
		local suffix = ""
		if key == "daily-paid" then
			for _, id in View.QuestOrder do
				if snapshot.daily and snapshot.daily[id] and View.Row(snapshot, snapshot.daily[id]).paid then
					suffix ..= ":" .. id
				end
			end
		elseif key == "supply-paid" then
			suffix = ":" .. tostring(snapshot.supplies and snapshot.supplies.lifetimeClaims)
		elseif key == "request" then
			suffix = ":" .. tostring(requestSerial)
		end
		key = tostring(snapshot.dayKey) .. ":" .. tostring(key) .. suffix
	end
	if text and text ~= "" then
		require(script.Parent.ExactHudController).Message(
			"retention:" .. tostring(key),
			string.gsub(text, "\n", " · "),
			false
		)
	end
end
local function pumpNotices()
	if safeForNotice() and returnPending and not returnShown then
		returnShown = true
		notify("return:" .. tostring(snapshot and snapshot.dayKey), table.concat(returnPending, " · "))
		returnPending = nil
	end
end
local function currentView()
	return if snapshot and snapshot.available == true then snapshot else confirmed or snapshot
end
local function canMutate()
	return remote ~= nil
		and updateRemote ~= nil
		and requestPending == nil
		and not requestUnavailable
		and snapshot ~= nil
		and snapshot.available == true
		and snapshot.status == "Ready"
end
local function apply(incoming)
	if type(incoming) == "table" and type(incoming.snapshot) == "table" then
		incoming = incoming.snapshot
	end
	if not started or not View.AcceptSnapshot(snapshot, incoming) then
		return false
	end
	local prior = confirmed
	snapshot, receivedAt = incoming, os.clock()
	if snapshot.available == true and snapshot.status == "Ready" then
		requestUnavailable = false
		confirmed = snapshot
		if not returnShown and not returnPending and snapshot.eligible == true then
			returnPending = View.ReturnLines(snapshot)
		end
		if prior and prior.dayKey == snapshot.dayKey then
			local amount, completed = 0, 0
			for _, id in View.QuestOrder do
				local row, old = snapshot.daily and snapshot.daily[id], prior.daily and prior.daily[id]
				if row and View.Row(snapshot, row).paid and not (old and View.Row(prior, old).paid) then
					amount += row.paidCash or row.rewardCash or 0
					completed += 1
				end
			end
			if completed > 0 then
				AudioCue.Play("J19", { bus = "Rewards" })
				notify(
					"daily-paid",
					tostring(completed)
						.. (if completed == 1 then " daily reward saved · " else " daily rewards saved · ")
						.. Cash.FormatExactCash(amount)
						.. " Cash",
					if completed > 1 then 4 else 3
				)
			end
			local oldClaims = prior.supplies and prior.supplies.lifetimeClaims or 0
			local supply = snapshot.supplies
			if supply and supply.lastPaid and supply.lifetimeClaims > oldClaims then
				-- every seventh claim is the big one
				AudioCue.Play(if supply.lifetimeClaims % 7 == 0 then "J18b" else "J18a", { bus = "Rewards" })
				notify(
					"supply-paid",
					"Supply claim "
						.. tostring(supply.lifetimeClaims)
						.. " saved"
						.. (if type(supply.lastAmountCash) == "number"
							then " · " .. Cash.FormatExactCash(supply.lastAmountCash) .. " Cash"
							else "")
						.. (
							if supply.lifetimeClaims == 7
								then " · Camp Regular unlocked"
								elseif supply.lifetimeClaims == 14 then " · Expedition Crest unlocked"
								else ""
						),
					3
				)
			end
			if snapshot.collection and prior.collection and snapshot.collection.count > prior.collection.count then
				AudioCue.Play("J6", { bus = "Rewards" })
				notify(
					"discovery",
					"Collection "
						.. tostring(snapshot.collection.count)
						.. "/"
						.. tostring(snapshot.collection.totalLive)
						.. " species saved",
					1.5
				)
			end
		end
	end
	fireChanged()
	pumpNotices()
	return true
end
local function cancelRequest()
	local pending = requestPending
	requestPending = nil
	if pending then
		if pending.timeout then
			pcall(task.cancel, pending.timeout)
			pending.timeout = nil
		end
		if pending.worker then
			pcall(task.cancel, pending.worker)
			pending.worker = nil
		end
	end
end
request = function(payload)
	if not remote or requestPending or os.clock() - lastRequestAt < 0.3 then
		return false
	end
	if payload.action ~= "Snapshot" and not canMutate() then
		return false
	end
	requestSerial += 1
	local serial, token, source = requestSerial, generation, remote
	local pending = { action = payload.action, serial = serial }
	requestPending, lastRequestAt = pending, os.clock()
	fireChanged()
	pending.timeout = task.delay(10, function()
		pending.timeout = nil
		if started and token == generation and requestPending == pending then
			cancelRequest()
			requestUnavailable = true
			player:SetAttribute("RetentionRequestState", "Unavailable")
			notify("request", "Quests confirmation delayed · last confirmed progress retained", 3)
			fireChanged()
			-- One bounded read reconciles a possibly committed mutation. A read
			-- timeout never recursively schedules another read or repeats a claim.
			if payload.action ~= "Snapshot" then
				task.defer(function()
					if started and token == generation and remote == source then
						request({ action = "Snapshot" })
					end
				end)
			end
		end
	end)
	pending.worker = task.spawn(function()
		local ok, result = pcall(source.InvokeServer, source, payload)
		pending.worker = nil
		if pending.timeout then
			pcall(task.cancel, pending.timeout)
			pending.timeout = nil
		end
		if not started or token ~= generation or source ~= remote then
			return
		end
		if requestPending == pending then
			requestPending = nil
		end
		requestUnavailable = not ok
		player:SetAttribute("RetentionRequestState", if ok then "Ready" else "Unavailable")
		if ok and type(result) == "table" then
			local accepted = apply(result)
			if (not accepted or result.ok == false) and result.code and result.code ~= "RATE_LIMITED" then
				notify("request", "Quests unavailable · " .. tostring(result.code):gsub("_", " "), 3)
			end
		else
			notify("request", "Quests connection unavailable · confirmed progress retained", 3)
		end
		fireChanged()
	end)
	return true
end
local function fetch()
	request({ action = "Snapshot" })
end
-- At the UTC reset one bounded read brings the new day's snapshot (once per dayKey).
local function updateClock()
	if not snapshot or not receivedAt then
		return
	end
	if
		snapshot.resetAt
		and snapshot.serverTime
		and snapshot.serverTime + os.clock() - receivedAt >= snapshot.resetAt
		and resetRequestedDay ~= snapshot.dayKey
	then
		if request({ action = "Snapshot" }) then
			resetRequestedDay = snapshot.dayKey
		end
	end
end
function Controller.GetDiagnostics()
	return {
		started = started,
		connections = #connections + (if criticalWarnings then criticalWarnings.GetConnectionCount() - 1 else 0),
		criticalWarningConnections = if criticalWarnings then criticalWarnings.GetConnectionCount() else 0,
		revision = snapshot and snapshot.revision,
		retentionRevision = snapshot and snapshot.retentionRevision,
		checkpoint = "PHASE14_CONNECTED_UI",
		returnShown = returnShown,
		requestPending = requestPending and requestPending.action,
		requestDependency = bindings.Request and bindings.Request.state,
		updateDependency = bindings.Update and bindings.Update.state,
	}
end
function Controller.Start()
	if started then
		return false
	end
	started, generation = true, generation + 1
	local token = generation
	local playerGui = player:WaitForChild("PlayerGui")
	if not started or generation ~= token then
		return false
	end
	criticalWarnings = Controller.CreateCriticalWarningObserver(playerGui, pumpNotices)
	table.insert(connections, criticalWarnings)
	bindings.Update = RemoteBinding.new({
		Root = RS,
		Name = "RetentionUpdate",
		OnRemote = function(value)
			updateRemote = value
			if not value then
				return nil
			end
			local connection = value.OnClientEvent:Connect(apply)
			task.defer(fetch)
			return connection
		end,
		OnState = fireChanged,
	})
	bindings.Request = RemoteBinding.new({
		Root = RS,
		Name = "RetentionRequest",
		ClassName = "RemoteFunction",
		OnRemote = function(value)
			remote = value
			if not value then
				cancelRequest()
			else
				task.defer(fetch)
			end
			return nil
		end,
		OnState = fireChanged,
	})
	task.spawn(function()
		while started and generation == token do
			updateClock()
			pumpNotices()
			task.wait(1)
		end
	end)
	fireChanged()
	return true
end
function Controller.IsAvailable()
	return started and snapshot ~= nil and snapshot.eligible == true
end
function Controller.Stop()
	started, generation = false, generation + 1
	cancelRequest()
	for _, binding in bindings do
		binding:Destroy()
	end
	table.clear(bindings)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	criticalWarnings = nil
	remote, updateRemote, snapshot, confirmed, receivedAt, requestPending = nil, nil, nil, nil, nil, nil
	returnPending, returnShown, resetRequestedDay = nil, false, nil
	lastRequestAt, requestUnavailable = -math.huge, false
	fireChanged()
end
-- Read access for the screens + the one request() owner (legacy payloads, pending and rate limiting).
function Controller.GetSnapshot()
	return snapshot
end
-- What the legacy panel rendered from: the live snapshot while available, else the last confirmed one.
function Controller.GetView()
	return currentView()
end
function Controller.GetConfirmed()
	return confirmed
end
-- The legacy gate on every mutating button (remotes bound, nothing pending, snapshot Ready).
-- ignoreRead = true looks past a pending {action="Snapshot"} read so views do not flicker to
-- "locked" during a refresh; request() itself still refuses to overlap it.
function Controller.CanMutate(ignoreRead: boolean?)
	if not started then
		return false
	end
	if ignoreRead and requestPending ~= nil and requestPending.action == "Snapshot" then
		return remote ~= nil
			and updateRemote ~= nil
			and not requestUnavailable
			and snapshot ~= nil
			and snapshot.available == true
			and snapshot.status == "Ready"
	end
	return canMutate()
end
-- Availability line the legacy panel showed above its content ("" when everything is ready).
function Controller.GetServiceText(): string
	if not remote or not updateRemote then
		return "Quests unavailable · "
			.. string.gsub(
				tostring(
					(bindings.Request and bindings.Request.reason)
						or (bindings.Update and bindings.Update.reason)
						or "server registration"
				),
				"_",
				" "
			)
	elseif not snapshot or snapshot.available ~= true then
		return "Unavailable · "
			.. tostring(snapshot and snapshot.reason or "profile dependency")
			.. " · last confirmed state retained"
	elseif snapshot.status == "Saving" then
		return "Saving · awaiting confirmed state"
	end
	return ""
end
-- "UTC reset in HH:MM:SS" from the snapshot's server clock (nil before the first snapshot).
function Controller.GetResetText(): string?
	if not snapshot or not receivedAt then
		return nil
	end
	return "UTC reset in " .. View.Remaining(snapshot.resetAt, snapshot.serverTime, os.clock() - receivedAt)
end
function Controller.Request(payload)
	if not started then
		return false
	end
	return request(payload)
end
function Controller.IsRequestPending(action)
	return requestPending ~= nil and (action == nil or requestPending.action == action)
end
-- Local lifecycle probes only. They do not grant, mutate profiles, alter
-- server dates or construct a remote; production clients cannot invoke them.
local function testAllowed()
	return RunService:IsStudio() and not Environment.IsProduction and started
end
function Controller._GetSnapshotForTesting()
	assert(testAllowed(), "Isolated DEV Studio UI required")
	return snapshot
end
function Controller._RejectStaleForTesting(value)
	assert(testAllowed(), "Isolated DEV Studio UI required")
	return apply(value)
end
return Controller
