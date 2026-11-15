--!strict
-- Carried-brainrot sale dialog (server quote -> confirm / cancel). This controller owns the sale
-- session: preview validation, expiry, ConfirmBrainrotSale / CancelBrainrotSale and the result
-- messages. The only view is the Plate window below (MenusV2 id "sale"). Specs inject dependencies
-- through Init: the controller then runs headless, or drives the injected `View`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

type Preview = {
	SaleSessionId: string,
	RuntimeBrainrotId: string,
	SpeciesId: string,
	DisplayName: string,
	Rarity: string,
	SellValue: number,
	ExpiresAtServerTime: number,
}

-- What a view may call back into (it never touches a remote).
type ViewActions = {
	Confirm: () -> (),
	Cancel: () -> (),
	IsBusy: () -> boolean,
	Clock: () -> number,
}

type SaleView = {
	Open: (preview: Preview, actions: ViewActions) -> (),
	Close: (reason: string) -> (),
	SetSubmitEnabled: (enabled: boolean) -> (),
	ShowError: (message: string) -> (),
}

type Dependencies = {
	Player: any,
	OpenRemote: any,
	ConfirmRemote: any,
	CancelRemote: any,
	InputBegan: any,
	View: SaleView?,
	Clock: () -> number,
	Spawn: (() -> ()) -> (),
	Delay: (number, () -> ()) -> (),
	Warn: (string) -> (),
}

local INVALID_PREVIEW_WARNING = "Rejected invalid OpenBrainrotSaleDialog preview"

local Controller = {}
local log = Logger.new("BrainrotSaleController")
local configuredDependencies: any? = nil
local dependencies: Dependencies? = nil
local view: SaleView? = nil
local currentPreview: Preview? = nil
local connections: { any } = {}
local started = false
local requestInFlight = false
local submitEnabled = true
local lastError: string? = nil
local menuState = "Closed"
local generation = 0
local requestRevision = 0
local invalidPreviewWarned = false

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function nonEmptyString(value: any): boolean
	return type(value) == "string" and value:match("%S") ~= nil
end

local function validatePreview(value: any, currentTime: number): Preview?
	if type(value) ~= "table" then
		return nil
	end
	local rarity = value.Rarity or value.Rank
	if
		not nonEmptyString(value.SaleSessionId)
		or not nonEmptyString(value.RuntimeBrainrotId)
		or not nonEmptyString(value.SpeciesId)
		or not nonEmptyString(value.DisplayName)
		or not nonEmptyString(rarity)
		or not finiteNumber(value.SellValue)
		or value.SellValue < 0
		or value.SellValue % 1 ~= 0
		or not finiteNumber(value.ExpiresAtServerTime)
		or value.ExpiresAtServerTime <= currentTime
	then
		return nil
	end
	return {
		SaleSessionId = value.SaleSessionId,
		RuntimeBrainrotId = value.RuntimeBrainrotId,
		SpeciesId = value.SpeciesId,
		DisplayName = value.DisplayName,
		Rarity = rarity,
		SellValue = value.SellValue,
		ExpiresAtServerTime = value.ExpiresAtServerTime,
	}
end

------------------------------------------------------------------ Plate view
-- View only: its buttons call ViewActions (the same confirm / cancel paths as every other input).
local plateWindow: any = nil
local plateState: any = nil -- { bag, sell, error, value } while the window shows a preview

local function plateModules(): (any, any, any, any)
	return require((script.Parent.Parent :: any).UI.MenusV2) :: any,
		require(ReplicatedStorage.Shared.UI.Plate) :: any,
		require(ReplicatedStorage.Shared.UI.Theme) :: any,
		require(ReplicatedStorage.Shared.Config.UIDisplayShots) :: any
end

local PlateView = {}

function PlateView.Close(reason: string)
	local state = plateState
	if not state then
		return
	end
	plateState = nil
	state.bag.clean()
	if plateWindow then
		plateWindow.close()
	end
	local MenusV2, Plate, Theme = plateModules()
	MenusV2.cleared("sale")
	if reason == "Sold" then
		Plate.Toast(MenusV2.Gui(), "+" .. CurrencyFormatter.FormatWholeCash(state.value) .. "!", { icon = Theme.Icons.Cash })
	end
end

function PlateView.SetSubmitEnabled(enabled: boolean)
	if plateState and plateState.sell then
		if enabled then
			plateState.sell.setVariant("stop")
		else
			plateState.sell.setVariant("locked", "Selling…")
		end
	end
end

function PlateView.ShowError(message: string)
	if plateState and plateState.error then
		plateState.error.Text = message
		plateState.error.Visible = message ~= ""
	end
end

function PlateView.Open(preview: Preview, actions: ViewActions)
	local MenusV2, Plate, Theme, Shots = plateModules()
	local P = Theme.Plate
	local px = Theme.px
	local function cancel()
		if not actions.IsBusy() then
			actions.Cancel()
		end
	end
	if not plateWindow then
		plateWindow = Plate.Window(MenusV2.Gui(), {
			key = "Sell",
			title = "Sell Brainrot",
			icon = Theme.Icons.Cash,
			aspect = 1.9,
			widthScale = 0.62,
			heightScale = 0.66,
			maxSize = Vector2.new(480, 260),
			onClose = function()
				-- reads the live state so a reused window always cancels the preview on screen
				if plateState then
					plateState.cancel()
				end
			end,
		})
	end
	local window = plateWindow
	window.open()
	window.clearContent()
	-- Back / gamepad B / another window opening: MenusV2 closes this one through the controller
	MenusV2.setOpen("sale", function()
		actions.Cancel()
	end)
	local bag = Plate.Bag()
	local state = { bag = bag, value = preview.SellValue, sell = nil :: any, error = nil :: any, cancel = cancel }
	plateState = state
	local content = window.Content
	local size = window.contentSize()
	local cardH = math.max(px(140), size.Y - px(4))
	local cardW = math.floor(cardH * 0.8)
	Plate.ItemCard(content, {
		name = preview.DisplayName,
		sub = preview.Rarity,
		image = Shots.get(preview.SpeciesId),
		background = P.Tier.Dark,
		ring = Theme.Rarity[preview.Rarity],
		rays = true,
		size = UDim2.fromOffset(cardW, cardH),
		imageHeight = 0.6,
		index = 1,
		bag = bag,
	})
	local right = Plate.frame(content, "Info", {
		Position = UDim2.fromOffset(cardW + px(12), 0),
		Size = UDim2.new(1, -(cardW + px(12)), 1, 0),
		ZIndex = 5,
	})
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, px(6))
	list.Parent = right
	Plate.Label(right, "You get", { size = 20, frameSize = UDim2.new(1, 0, 0, px(26)), order = 1 })
	Plate.Label(right, CurrencyFormatter.FormatWholeCash(preview.SellValue), {
		size = 34,
		font = P.Font.Title,
		color = P.Color.Cash,
		frameSize = UDim2.new(1, 0, 0, px(42)),
		order = 2,
	})
	local countdown = Plate.Label(right, "", { size = 16, min = 14, color = P.Color.Hint, frameSize = UDim2.new(1, 0, 0, px(22)), order = 3 })
	local errorLabel = Plate.Label(right, "", {
		size = 15,
		min = 14,
		wrap = true,
		color = Color3.fromHex("#FF6B7A"),
		frameSize = UDim2.new(1, 0, 0, px(36)),
		order = 4,
	})
	errorLabel.Visible = false
	state.error = errorLabel
	local row = Plate.frame(right, "Buttons", { Size = UDim2.new(1, 0, 0, px(50)), LayoutOrder = 5, ZIndex = 5 })
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, px(10))
	rowLayout.Parent = row
	Plate.Button(row, {
		variant = "tabOff",
		text = "Cancel",
		size = UDim2.fromOffset(px(110), px(44)),
		order = 1,
		bag = bag,
		onClick = cancel,
	})
	state.sell = Plate.Button(row, {
		variant = "stop",
		text = "Sell",
		icon = Theme.Icons.Cash,
		primary = true,
		size = UDim2.fromOffset(px(140), px(44)),
		order = 2,
		bag = bag,
		onClick = actions.Confirm,
	})
	-- countdown from ExpiresAtServerTime (the expiry itself stays with scheduleExpiry)
	local alive = true
	bag.add(function()
		alive = false
	end)
	task.spawn(function()
		while alive do
			local left = math.max(0, math.ceil(preview.ExpiresAtServerTime - actions.Clock()))
			countdown.Text = string.format("Offer ends in %ds", left)
			task.wait(0.25)
		end
	end)
end

function PlateView.Destroy()
	if plateWindow then
		plateWindow.destroy()
		plateWindow = nil
	end
	plateState = nil
end

------------------------------------------------------------------ sale session
local confirmCurrentPreview: () -> ()

local function buildDependencies(overrides: any?): Dependencies?
	local supplied = overrides or {}
	local player = supplied.Player or Players.LocalPlayer
	if player == nil then
		return nil
	end
	local remotes = supplied.Remotes or ReplicatedStorage:WaitForChild("Remotes", 10)
	local openRemote = supplied.OpenRemote
		or (remotes and remotes:WaitForChild(RemoteNames.OpenBrainrotSaleDialog, 10))
	local confirmRemote = supplied.ConfirmRemote
		or (remotes and remotes:WaitForChild(RemoteNames.ConfirmBrainrotSale, 10))
	local cancelRemote = supplied.CancelRemote
		or (remotes and remotes:WaitForChild(RemoteNames.CancelBrainrotSale, 10))
	if
		openRemote == nil
		or confirmRemote == nil
		or cancelRemote == nil
		or openRemote.OnClientEvent == nil
		or confirmRemote.InvokeServer == nil
		or cancelRemote.FireServer == nil
	then
		return nil
	end
	-- Live client: the Plate view. Injected dependencies (specs): their `View`, or none (headless).
	local nextView: SaleView? = if overrides == nil then PlateView :: any else supplied.View
	return {
		Player = player,
		OpenRemote = openRemote,
		ConfirmRemote = confirmRemote,
		CancelRemote = cancelRemote,
		InputBegan = supplied.InputBegan or UserInputService.InputBegan,
		View = nextView,
		Clock = supplied.Clock or function()
			return Workspace:GetServerTimeNow()
		end,
		Spawn = supplied.Spawn or task.spawn,
		Delay = supplied.Delay or task.delay,
		Warn = supplied.Warn or function(message)
			log:Warn("%s", message)
		end,
	}
end

local function setSubmitEnabled(enabled: boolean)
	submitEnabled = enabled
	if view then
		view.SetSubmitEnabled(enabled)
	end
end

local function sendCancellation(preview: Preview?)
	if not dependencies or not preview then
		return
	end
	pcall(function()
		(dependencies :: Dependencies).CancelRemote:FireServer(preview.SaleSessionId)
	end)
end

local function close(reason: string, cancelQuote: boolean?)
	local preview = currentPreview
	requestRevision += 1
	requestInFlight = false
	currentPreview = nil
	menuState = "Closing"
	if cancelQuote then
		sendCancellation(preview)
	end
	lastError = nil
	submitEnabled = true
	if view then
		view.Close(reason)
	end
	menuState = "Closed"
	log:Debug("Sale menu closed: %s", reason)
end

local function scheduleExpiry(sessionId: string, expiresAt: number, expectedGeneration: number)
	if not dependencies then
		return
	end
	local activeDependencies = dependencies :: Dependencies
	local remaining = math.max(0, expiresAt - activeDependencies.Clock())
	activeDependencies.Delay(remaining, function()
		local preview = currentPreview
		if
			not started
			or generation ~= expectedGeneration
			or not dependencies
			or not preview
			or preview.SaleSessionId ~= sessionId
		then
			return
		end
		if (dependencies :: Dependencies).Clock() >= expiresAt then
			close("PreviewExpired", true)
		else
			scheduleExpiry(sessionId, expiresAt, expectedGeneration)
		end
	end)
end

local function showError(message: string)
	lastError = message
	if view then
		view.ShowError(message)
	end
end

local function resultMessage(code: any): string
	if code == "BankFirst" or code == "BANK_FIRST" then
		return "Bank this brainrot on a platform before selling it."
	elseif code == "Dazed" or code == "DAZED" then
		return "Wait until your daze ends."
	elseif code == "Busy" then
		return "Sale already in progress."
	elseif code == "AwardFailed" then
		return "Unable to award currency. Try again."
	end
	return "Unable to complete sale. Try again."
end

function Controller.Init(nextDependencies: any?): boolean
	if started then
		return false
	end
	configuredDependencies = nextDependencies
	return true
end

function Controller.Open(previewValue: any): boolean
	if not started or not dependencies then
		return false
	end
	local activeDependencies = dependencies :: Dependencies
	local preview = validatePreview(previewValue, activeDependencies.Clock())
	if not preview then
		close("InvalidPreview", true)
		if not invalidPreviewWarned then
			invalidPreviewWarned = true
			activeDependencies.Warn(INVALID_PREVIEW_WARNING)
		end
		return false
	end
	close("Replaced", true)
	menuState = "Opening"
	currentPreview = preview
	if view then
		view.Open(preview, {
			Confirm = confirmCurrentPreview,
			Cancel = function()
				close("CloseButton", true)
			end,
			IsBusy = function()
				return requestInFlight
			end,
			Clock = activeDependencies.Clock,
		})
	end
	menuState = "Open"
	scheduleExpiry(preview.SaleSessionId, preview.ExpiresAtServerTime, generation)
	return true
end

function Controller.Close(reason: string?)
	close(reason or "Closed", true)
end

function confirmCurrentPreview()
	if not started or not dependencies or not currentPreview or requestInFlight then
		return
	end
	local preview = currentPreview :: Preview
	if (dependencies :: Dependencies).Clock() >= preview.ExpiresAtServerTime then
		close("PreviewExpired", true)
		return
	end
	requestInFlight = true
	menuState = "SubmittingSell"
	setSubmitEnabled(false)
	showError("")
	lastError = nil
	requestRevision += 1
	local expectedRevision = requestRevision
	local expectedGeneration = generation
	local sessionId = preview.SaleSessionId
	local activeDependencies = dependencies :: Dependencies
	activeDependencies.Spawn(function()
		local invokeSucceeded, result = pcall(function()
			return activeDependencies.ConfirmRemote:InvokeServer(sessionId)
		end)
		if
			not started
			or generation ~= expectedGeneration
			or requestRevision ~= expectedRevision
			or not currentPreview
			or currentPreview.SaleSessionId ~= sessionId
		then
			return
		end
		if invokeSucceeded and type(result) == "table" then
			if result.ok == true and result.code == "Sold" then
				close("Sold", false)
				return
			elseif result.ok == false then
				local code = result.code
				if
					code == "PreviewExpired"
					or code == "PreviewChanged"
					or code == "NothingCarried"
					or code == "InvalidSession"
					or code == "TooFarAway"
				then
					close(tostring(code), true)
					return
				end
				requestInFlight = false
				menuState = "Open"
				setSubmitEnabled(true)
				showError(resultMessage(code))
				return
			end
		end
		requestInFlight = false
		menuState = "Open"
		setSubmitEnabled(true)
		showError("Unable to complete sale.")
		activeDependencies.Warn("Brainrot sale confirmation could not be completed")
	end)
end

function Controller.Start(): boolean
	if started then
		return false
	end
	local nextDependencies = buildDependencies(configuredDependencies)
	if not nextDependencies then
		log:Warn("Sale remotes were unavailable; the brainrot sale dialog was not started")
		return false
	end
	dependencies = nextDependencies
	view = nextDependencies.View
	started = true
	generation += 1
	table.insert(
		connections,
		nextDependencies.OpenRemote.OnClientEvent:Connect(function(preview)
			Controller.Open(preview)
		end)
	)
	table.insert(
		connections,
		nextDependencies.InputBegan:Connect(function(input)
			if
				currentPreview
				and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB)
			then
				close("CancelInput", true)
			end
		end)
	)
	table.insert(
		connections,
		nextDependencies.Player.CharacterAdded:Connect(function()
			close("CharacterAdded", true)
		end)
	)
	return true
end

function Controller.Stop()
	if not started then
		return
	end
	close("Stop", true)
	started = false
	generation += 1
	disconnectAll()
	if view == (PlateView :: any) then
		PlateView.Destroy()
	end
	dependencies = nil
	view = nil
	invalidPreviewWarned = false
end

function Controller._TestGetState(): any
	return {
		Started = started,
		Open = currentPreview ~= nil,
		State = menuState,
		SessionId = if currentPreview then currentPreview.SaleSessionId else nil,
		RuntimeBrainrotId = if currentPreview then currentPreview.RuntimeBrainrotId else nil,
		SpeciesId = if currentPreview then currentPreview.SpeciesId else nil,
		DisplayName = if currentPreview then currentPreview.DisplayName else nil,
		Rarity = if currentPreview then currentPreview.Rarity else nil,
		SellValue = if currentPreview then currentPreview.SellValue else nil,
		RequestInFlight = requestInFlight,
		SubmitEnabled = submitEnabled,
		Error = lastError,
	}
end

function Controller._TestConfirm()
	confirmCurrentPreview()
end

function Controller._TestCancel()
	close("TestCancel", true)
end

return Controller
