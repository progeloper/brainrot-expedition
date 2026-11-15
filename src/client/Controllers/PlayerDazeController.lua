--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Style = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
local Presentation = require(ReplicatedStorage.Shared.Utility.DazePresentation)
local Config = require(ReplicatedStorage.Shared.Config.Phase10)
local InputPolicy = require(script.Parent.Parent.Utility.Phase10InputPolicy)
local ControlRestore = require(script.Parent.Parent.Utility.Phase10ControlRestore)

local Controller = {}
local INPUT_LOCK = "Phase10DazeMovement"
local started = false
local connections: { RBXScriptConnection } = {}
local views: { [Player]: any } = {}
local controls: any = nil
local controlsDisabled = false
local startGeneration = 0
local controlRestore = ControlRestore.new(function()
	local localPlayer = Players.LocalPlayer
	local modal = localPlayer
		and (
			localPlayer:GetAttribute("Phase13CinematicActive") == true
			or localPlayer:GetAttribute("Phase13ConsentDialogOpen") == true
			or localPlayer:GetAttribute("Phase13CompareDialogOpen") == true
		)
	return modal == true
		or (
			started
			and Config.Enabled
			and InputPolicy.IsBlocked(localPlayer, game:GetService("GuiService"), game:GetService("UserInputService"))
		)
end)

-- A closing menu calls this only for its previously enabled controls. Daze
-- retains that restoration permission until both its deadline and UI allow it.
function Controller.ResumeDefaultControlsWhenAllowed(value: any)
	controlRestore:ResumeWhenAllowed(value)
end

local function disconnect(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

-- The view owns only these instances. Absolute server time also covers late
-- replication, Camp recovery, hitches and stale attribute callbacks.
function Controller.CreateView(player: any, playerGui: PlayerGui, clock: (() -> number)?): any
	local now = clock or function()
		return Workspace:GetServerTimeNow()
	end
	local character: Model? = nil
	local labelGui: BillboardGui? = nil
	local label: TextLabel? = nil
	local stroke: UIStroke? = nil
	local film: Highlight? = nil
	local revision: any = nil
	local observedDeadline = 0
	local completionAt: number? = nil
	local hiddenRevision: any = nil
	local view: any = {}

	local function removeLabel()
		if labelGui then
			labelGui:Destroy()
		end
		labelGui, label, stroke, completionAt = nil, nil, nil, nil
	end
	local function clear()
		removeLabel()
		if film then
			film:Destroy()
		end
		film = nil
	end

	local function createLabel(head: BasePart)
		local gui = Instance.new("BillboardGui")
		gui.Name, gui.Adornee = "Phase10DazeCountdown", head
		gui.Size = UDim2.fromScale(2.4, 0.7)
		-- Leave the standard avatar name at its normal lower position.
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2.75, 0)
		gui.MaxDistance, gui.AlwaysOnTop, gui.LightInfluence = Style.Presentation.Awake.MaxDistance, false, 0
		gui.Brightness, gui.Parent = 1, playerGui
		gui.ClipsDescendants = false
		local text = Instance.new("TextLabel")
		text.Name, text.Size, text.BackgroundTransparency = "Countdown", UDim2.fromScale(1, 1), 1
		text.Font, text.TextScaled, text.TextSize =
			Style.Typography.Font, true, math.round(Style.Typography.NameMaxTextSize * Config.CountdownScale)
		text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
		text.Text, text.TextColor3, text.Parent = "3.00", Presentation.Red, gui
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MinTextSize = math.round(Style.Typography.NameMinTextSize * Config.CountdownScale)
		constraint.MaxTextSize = math.round(Style.Typography.NameMaxTextSize * Config.CountdownScale)
		constraint.Parent = text
		local outline = Instance.new("UIStroke")
		outline.Color, outline.Thickness, outline.Parent =
			Style.Colors.TextStroke, Style.Typography.NameStrokeThickness, text
		labelGui, label, stroke = gui, text, outline
	end

	function view:Update(): boolean
		local current: Model? = player.Character
		if current ~= character then
			clear()
			character, revision, hiddenRevision, observedDeadline = current, nil, nil, 0
		end
		local humanoid = if current then current:FindFirstChildOfClass("Humanoid") else nil
		local head = if current then current:FindFirstChild("Head") else nil
		if
			not current
			or not current.Parent
			or not humanoid
			or humanoid.Health <= 0
			or not head
			or not head:IsA("BasePart")
		then
			clear()
			return false
		end
		local time = now()
		local value = player:GetAttribute("Phase10DazeEnd")
		local deadline = if type(value) == "number" then value else 0
		local protection = player:GetAttribute("Phase10ProtectionEnd")
		local nextRevision = player:GetAttribute("Phase10DazeRevision")
		local hitCharacterGeneration = player:GetAttribute("Phase10DazeCharacterGeneration")
		local currentGeneration = current:GetAttribute("Phase10CharacterGeneration")
		local matchesCharacter = hitCharacterGeneration == nil or hitCharacterGeneration == currentGeneration
		local dazed = matchesCharacter and deadline > time
		if revision ~= nextRevision then
			removeLabel()
			revision, hiddenRevision, observedDeadline = nextRevision, nil, 0
		end
		if dazed then
			if not labelGui then
				createLabel(head)
			end
			observedDeadline, completionAt = deadline, nil
			local text, outline =
				assert(label, "Countdown label unavailable"), assert(stroke, "Countdown outline unavailable")
			text.Text = Presentation.Text(deadline, time)
			text.TextColor3 = Presentation.Color(deadline, time)
			text.TextTransparency = 0
			outline.Transparency = 0
		elseif
			matchesCharacter
			and hiddenRevision ~= revision
			and (
				labelGui ~= nil
				or (deadline > 0 and time < deadline + Presentation.ZeroHold + Presentation.FadeDuration)
			)
		then
			-- Deadline reduction ends at receipt time, otherwise finish on the
			-- scheduled deadline. A late frame never prolongs natural recovery.
			if not completionAt then
				completionAt = if deadline == 0
						and type(protection) == "number"
						and protection > 0
					then math.min(time, protection - Config.ProtectionSeconds)
					elseif observedDeadline > 0 and deadline < observedDeadline then time
					else deadline
			end
			if not labelGui then
				createLabel(head)
			end
			local elapsed = time - (completionAt :: number)
			if elapsed >= Presentation.ZeroHold + Presentation.FadeDuration then
				hiddenRevision = revision
				removeLabel()
			else
				local text, outline =
					assert(label, "Countdown label unavailable"), assert(stroke, "Countdown outline unavailable")
				text.Text, text.TextColor3 = "0.00", Presentation.Green
				local alpha = math.clamp((elapsed - Presentation.ZeroHold) / Presentation.FadeDuration, 0, 1)
				text.TextTransparency, outline.Transparency = alpha, alpha
			end
		else
			removeLabel()
		end
		local showFilm = not dazed and type(protection) == "number" and protection > time
		if showFilm and not film then
			film = Instance.new("Highlight")
			film.Name, film.Adornee = "Phase10ProtectionFilm", current
			film.FillColor, film.FillTransparency = Presentation.Film, Config.FilmTransparency
			film.OutlineTransparency, film.DepthMode = 1, Enum.HighlightDepthMode.Occluded
			film.Parent = current
		elseif not showFilm and film then
			film:Destroy()
			film = nil
		end
		return dazed
	end

	function view:Destroy()
		clear()
		character = nil
	end
	return view
end

local function setLocalDaze(dazed: boolean)
	if dazed and not controlsDisabled then
		controlsDisabled = true
		controlRestore:Hold(controls)
		ContextActionService:BindActionAtPriority(
			INPUT_LOCK,
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 5,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	elseif not dazed and controlsDisabled then
		ContextActionService:UnbindAction(INPUT_LOCK)
		-- Return default controls only in the current permitted UI context.
		if
			InputPolicy.IsMenuOpen(
				Players.LocalPlayer,
				game:GetService("GuiService"),
				game:GetService("UserInputService")
			)
		then
			return
		end
		controlsDisabled = false
	end
	controlRestore:ReleaseWhenAllowed()
end

function Controller.Start()
	if started or not Config.Enabled then
		return
	end
	started = true
	startGeneration += 1
	local currentGeneration = startGeneration
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function add(player: Player)
		views[player] = Controller.CreateView(player, gui)
	end
	for _, player in Players:GetPlayers() do
		add(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(add))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			if views[player] then
				views[player]:Destroy()
				views[player] = nil
			end
		end)
	)
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			local localDazed = false
			for player, view in views do
				local active = view:Update()
				if player == Players.LocalPlayer then
					localDazed = active
				end
			end
			setLocalDaze(localDazed)
		end)
	)
	task.spawn(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 10)
		local module = if scripts then scripts:WaitForChild("PlayerModule", 10) else nil
		if not module or not module:IsA("ModuleScript") or not started or startGeneration ~= currentGeneration then
			return
		end
		local ok, result = pcall(function()
			return require(module):GetControls()
		end)
		if ok and started and startGeneration == currentGeneration then
			controls = result
			if controlsDisabled then
				controlRestore:Hold(controls)
			end
		end
	end)
end

function Controller.Stop()
	if not started then
		return
	end
	started = false
	startGeneration += 1
	disconnect(connections)
	for _, view in views do
		view:Destroy()
	end
	table.clear(views)
	setLocalDaze(false)
	ContextActionService:UnbindAction(INPUT_LOCK)
	controlRestore:ReleaseWhenAllowed()
	controlsDisabled = false
	controls = nil
end

return Controller
