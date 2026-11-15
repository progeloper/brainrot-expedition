--!strict
-- Core Loop V2, Parts C, D and K (server): Lucky Meter + pity, combo + magnet, and the mutation reveal.
-- Server-authoritative; clients only receive CoreLoopEvent payloads for presentation. Session-only state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CoreLoop = require(Shared.Config.CoreLoop)
local CoreLoopFlags = require(Shared.Config.CoreLoopFlags)
local LuckState = require(Shared.CoreLoop.LuckState)
local ComboState = require(Shared.CoreLoop.ComboState)
local OddsText = require(Shared.CoreLoop.OddsText)
local StarGrade = require(Shared.CoreLoop.StarGrade)
local BrainrotDisplayMetadata = require(Shared.Utility.BrainrotDisplayMetadata)

type PlayerState = {
	Luck: LuckState.State,
	Combo: ComboState.State,
	LuckyPending: boolean, -- a Lucky Star is owed: the next herd's Star (meteor, Village if possible)
	PityStar: ("Super" | "Jackpot")?,
	MutationPityPending: boolean,
	LastComboSent: number,
	NextMagnetAt: number,
	HerdScatterAt: { [string]: number },
	-- Session-only measurement for checks C-1..C-3 (read through GetState; never saved).
	Measure: {
		Hunting: number,
		Fills: { number },
		MaxSuper: number,
		MaxJackpot: number,
		MaxMutation: number,
	},
}

export type ComposeOptions = {
	minTrueGrade: ("Super" | "Jackpot")?,
	mutatedSnack: boolean?,
	preferVillage: boolean?,
	arrival: string?, -- "Meteor" (Lucky / Super pity), "Rift" (Jackpot), nil = beam drop
	source: string?, -- "Lucky" | "SuperPity" | "JackpotPity" | nil
}

local Progress = {}

local deps: any = nil
local players: { [Player]: PlayerState } = {}
local remote: RemoteEvent? = nil
local started = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(player: Player, payload: any)
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function stateFor(player: Player): PlayerState
	local state = players[player]
	if not state then
		state = {
			Luck = LuckState.New(false),
			Combo = ComboState.New(),
			LuckyPending = false,
			PityStar = nil,
			MutationPityPending = false,
			LastComboSent = 0,
			NextMagnetAt = 0,
			HerdScatterAt = {},
			Measure = { Hunting = 0, Fills = {}, MaxSuper = 0, MaxJackpot = 0, MaxMutation = 0 },
		}
		players[player] = state
	end
	return state
end

local function rushActive(): boolean
	return deps.RushKind ~= nil and deps.RushKind() ~= "Idle"
end

local function publishMeter(player: Player, state: PlayerState)
	player:SetAttribute("LuckyMeter", LuckState.Percent(state.Luck))
end

-- Apply a meter event; on full, owe a Lucky Star and reset.
local function gainMeter(
	player: Player,
	state: PlayerState,
	event: LuckState.Event,
	individualId: string?,
	reason: string
)
	if not CoreLoopFlags.Part("LuckyMeter") then
		return
	end
	local gained, full = LuckState.Apply(state.Luck, event, individualId, {
		combo = ComboState.Current(state.Combo, os.clock()),
		rush = rushActive(),
	})
	if gained <= 0 then
		return
	end
	publishMeter(player, state)
	send(
		player,
		{ kind = "Meter", gain = gained, reason = reason, value = LuckState.Percent(state.Luck) }
	)
	if full then
		state.LuckyPending = true
		send(player, { kind = "LuckyFull" })
		table.insert(state.Measure.Fills, state.Measure.Hunting)
		if deps.Analytics then
			pcall(deps.Analytics.Record, deps.Analytics, player, "CL_MeterFull", 1, nil)
		end
		if deps.Director then
			deps.Director.RequestForcedStar(player, "Super")
		end
		LuckState.Reset(state.Luck)
		task.delay(1.5, function()
			publishMeter(player, state)
		end)
	end
end

------------------------------------------------------------------ director hooks

-- Called every director tick while the player is a Hunter. Returns the forced Star (pity) if one is due.
function Progress.OnHunting(player: Player, dt: number): ("Super" | "Jackpot")?
	local state = stateFor(player)
	if not CoreLoopFlags.Part("Pity") then
		return if state.LuckyPending then "Super" else nil
	end
	LuckState.AddHunting(state.Luck, dt)
	local measure = state.Measure
	measure.Hunting += dt
	local luck = state.Luck :: any
	for key, field in
		{ MaxSuper = "sinceSuper", MaxJackpot = "sinceJackpot", MaxMutation = "sinceMutation" }
	do
		local value = luck[field]
		if type(value) == "number" and value < math.huge and value > (measure :: any)[key] then
			(measure :: any)[key] = value
		end
	end
	local due = LuckState.DueStar(state.Luck)
	if due and state.PityStar ~= due then
		state.PityStar = due
		if deps.Analytics then
			pcall(
				deps.Analytics.Record,
				deps.Analytics,
				player,
				"CL_Pity",
				if due == "Jackpot" then 2 else 1,
				nil
			)
		end
	end
	if LuckState.DueMutation(state.Luck) then
		state.MutationPityPending = true
	end
	if state.LuckyPending and due == nil then
		return "Super"
	end
	return due
end

-- Options for this player's next herd (Lucky Star > Jackpot pity > Super pity; mutation pity separate).
function Progress.ComposeOptions(player: Player): ComposeOptions
	local state = stateFor(player)
	local options: ComposeOptions = {}
	if state.PityStar == "Jackpot" then
		options.minTrueGrade, options.arrival, options.source = "Jackpot", "Rift", "JackpotPity"
	elseif state.LuckyPending then
		options.minTrueGrade, options.arrival, options.source, options.preferVillage =
			"Super", "Meteor", "Lucky", true
	elseif state.PityStar == "Super" then
		options.minTrueGrade, options.arrival, options.source = "Super", "Meteor", "SuperPity"
	end
	options.mutatedSnack = state.MutationPityPending or nil
	return options
end

-- A herd was placed for this player: reset the matching pity timers ("since it last SPAWNED").
function Progress.OnHerdComposed(player: Player, herd: any, options: ComposeOptions)
	local state = stateFor(player)
	local mutated = false
	for _, member in herd.members do
		if member.mutationId ~= "None" then
			mutated = true
		end
	end
	LuckState.OnSpawn(state.Luck, herd.trueGrade, mutated)
	if options.source == "Lucky" then
		state.LuckyPending = false
	end
	if LuckState.DueStar(state.Luck) == nil then
		state.PityStar = nil
	end
	if mutated then
		state.MutationPityPending = false
	end
end

-- A loner spawned (mutation pity counts any mutated spawn).
function Progress.OnLonerSpawned(player: Player, mutationId: string)
	local state = stateFor(player)
	if mutationId ~= "None" then
		LuckState.OnSpawn(state.Luck, nil, true)
		state.MutationPityPending = false
	end
end

------------------------------------------------------------------ hits, KOs, reveal

local function revealMutation(player: Player, model: Model, entry: any)
	if model:GetAttribute("CoreLoopMutationHidden") ~= true then
		return nil
	end
	local record = deps.Spawner.GetWorldRecord(model)
	model:SetAttribute("CoreLoopMutationHidden", nil)
	model:SetAttribute("CoreLoopShimmer", nil)
	if record then
		BrainrotDisplayMetadata.SetIdentity(model, record)
	end
	local mutationId = record and record.Metadata and record.Metadata.MutationId or "None"
	if mutationId == "None" then
		return nil
	end
	local reveal = {
		kind = "Reveal",
		model = model,
		mutationId = mutationId,
		odds = OddsText.ForMutation(mutationId),
		gems = if deps.MutationGemPreview then deps.MutationGemPreview(player, mutationId) else nil,
		upgradedTo = nil :: string?,
	}
	if entry and entry.Role == "Star" and entry.VisibleGrade and entry.TrueGrade then
		if StarGrade.Rank(entry.TrueGrade) > StarGrade.Rank(entry.VisibleGrade) then
			reveal.upgradedTo = entry.TrueGrade
		end
	end
	if deps.Analytics then
		pcall(
			deps.Analytics.Record,
			deps.Analytics,
			player,
			"CL_Reveal",
			if reveal.upgradedTo then 2 else 1,
			nil
		)
	end
	return reveal
end

local function sneakShot(model: Model): boolean
	local temperament = model:GetAttribute("CoreLoopTemperament")
	if temperament == nil or temperament == "Docile" then
		return false
	end
	local alertAt = model:GetAttribute("CoreLoopAlertAt")
	return type(alertAt) ~= "number" or now() - alertAt > CoreLoop.Behaviour.SneakWindowSeconds
end

local function scatterHerd(state: PlayerState, model: Model, player: Player)
	local herdId = model:GetAttribute("CoreLoopHerdId")
	if type(herdId) ~= "string" then
		return
	end
	local t = now()
	local last = state.HerdScatterAt[herdId]
	if last and t - last < CoreLoop.Behaviour.Herd.ScatterRepeat then
		return
	end
	state.HerdScatterAt[herdId] = t
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
	for _, other in deps.Spawner.GetWorldModels() do
		if other ~= model and other:GetAttribute("CoreLoopHerdId") == herdId then
			other:SetAttribute("CoreLoopScatterFrom", from) -- the threat: members flee away from it
			other:SetAttribute("CoreLoopScatterOrigin", model:GetPivot().Position) -- E5: radius from the hit member
			other:SetAttribute("CoreLoopScatterAt", t)
		end
	end
end

-- Called by the director for every accepted hit (slept = KO).
function Progress.OnHit(player: Player, model: Model, slept: boolean, entry: any)
	local state = stateFor(player)
	local record = deps.Spawner.GetWorldRecord(model)
	local itemId = if record then record.ItemId else model:GetAttribute("ItemId")
	local sneak = CoreLoopFlags.Part("Temperaments") and sneakShot(model)
	if sneak then
		gainMeter(player, state, "SneakShot", tostring(itemId), "SNEAK SHOT")
	end
	if CoreLoopFlags.Part("Temperaments") then
		scatterHerd(state, model, player)
	end
	if not slept then
		model:SetAttribute("CoreLoopStaggerUntil", now() + CoreLoop.Behaviour.StaggerSeconds)
		send(player, { kind = "Hit", model = model, sneak = sneak })
		return
	end
	pcall(require(script.Parent.Parent.Systems.Behaviours.CoreLoopTemperament).OnKO, model) -- E-3 QA timing
	local t = os.clock()
	local combo = if CoreLoopFlags.Part("Combo") then ComboState.OnKO(state.Combo, t) else 1
	local grade = if entry and entry.Role == "Star"
		then (entry.TrueGrade or entry.VisibleGrade or "Star")
		else nil
	local event: LuckState.Event = if grade == "Jackpot"
		then "JackpotKO"
		elseif grade == "Super" then "SuperKO"
		elseif grade == "Star" then "StarKO"
		else "SnackKO"
	gainMeter(player, state, event, tostring(itemId), if grade then string.upper(grade) else "KO")
	local reveal = if CoreLoopFlags.Part("MutationReveal")
		then revealMutation(player, model, entry)
		else nil
	if CoreLoopFlags.Part("Combo") then
		state.LastComboSent = t
		send(player, { kind = "Combo", n = combo, expiresIn = CoreLoop.Combo.WindowSeconds })
	end
	send(player, {
		kind = "KO",
		model = model,
		role = if entry then entry.Role else "Wild",
		grade = grade,
		combo = combo,
		sneak = sneak,
		odds = model:GetAttribute("StarOdds"),
	})
	if reveal then
		send(player, reveal)
	end
	if deps.Analytics then
		pcall(deps.Analytics.Record, deps.Analytics, player, "CL_KO", combo, nil)
	end
end

------------------------------------------------------------------ per-tick: combo expiry + magnet

function Progress.Step()
	local t = os.clock()
	for player, state in players do
		if player.Parent ~= Players then
			players[player] = nil
			continue
		end
		local ended = ComboState.Step(state.Combo, t)
		if ComboState.ShowsEnd(ended) then
			send(player, { kind = "ComboEnd", n = ended })
		end
		if
			CoreLoopFlags.Part("Combo")
			and ComboState.MagnetActive(state.Combo, t)
			and t >= state.NextMagnetAt
			and deps.GetDrivenCart
		then
			state.NextMagnetAt = t + CoreLoop.Combo.MagnetInterval
			local cart = deps.GetDrivenCart(player)
			if cart then
				local origin = cart:GetPivot().Position
				local radius = CoreLoop.Combo.MagnetRadius
				for _, model in deps.Spawner.GetWorldModels() do
					if
						model:GetAttribute("CoreLoopOwnerUserId") == player.UserId
						and model:GetAttribute("CoreLoopHerdId") ~= nil
					then
						local offset = model:GetPivot().Position - origin
						if offset.X * offset.X + offset.Z * offset.Z <= radius * radius then
							local _, worldState = deps.Spawner.GetWorldRecord(model)
							if worldState == "WorldSleeping" then
								local ok = deps.Interaction.TryScoopIntoCargo(
									player,
									cart,
									model,
									radius,
									nil
								)
								if ok then
									send(player, { kind = "Magnet", model = model })
									break -- one per interval keeps the cargo transaction serial
								end
							end
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ start

function Progress.Start(options: any): boolean
	if started then
		return false
	end
	started = true
	deps = options
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local existing = remotes:FindFirstChild("CoreLoopEvent")
		if existing and existing:IsA("RemoteEvent") then
			remote = existing
		else
			local created = Instance.new("RemoteEvent")
			created.Name = "CoreLoopEvent"
			created.Parent = remotes
			remote = created
		end
	end
	if options.SleepSystem and options.SleepSystem.AddNotYoursSubscriber then
		options.SleepSystem.AddNotYoursSubscriber(function(player: Player, model: Model)
			local untilAt = model:GetAttribute("StarExclusiveUntil")
			send(player, {
				kind = "NotYours",
				model = model,
				seconds = if type(untilAt) == "number"
					then math.max(0, math.ceil(untilAt - now()))
					else 0,
			})
		end)
	end
	if options.Villagers then
		if options.Villagers.AddCleanEscapeSubscriber then
			options.Villagers.AddCleanEscapeSubscriber(function(player: Player)
				gainMeter(player, stateFor(player), "CleanEscape", nil, "ESCAPED")
			end)
		end
		if options.Villagers.AddSneakySubscriber then
			options.Villagers.AddSneakySubscriber(function(player: Player)
				gainMeter(player, stateFor(player), "Sneaky", nil, "SNEAKY")
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		players[player] = nil
	end)
	return true
end

-- QA (Studio): force the meter value (C-1 / review pen).
function Progress._ForceMeterForQA(player: Player, value: number)
	local state = stateFor(player)
	if value >= CoreLoop.Meter.Max then
		state.Luck.value = CoreLoop.Meter.Max - 1
		gainMeter(player, state, "CleanEscape", nil, "QA") -- crosses Max through the normal path
		return
	end
	state.Luck.value = math.clamp(value, 0, CoreLoop.Meter.Max)
	publishMeter(player, state)
end

function Progress._ForcePityForQA(player: Player, kind: string)
	local state = stateFor(player)
	if kind == "Jackpot" then
		state.Luck.sinceJackpot = math.huge
	elseif kind == "Super" then
		state.Luck.sinceSuper = math.huge
	elseif kind == "Mutation" then
		state.Luck.sinceMutation = math.huge
	end
end

function Progress.GetState(player: Player): any
	local state = players[player]
	return if state
		then {
			Meter = state.Luck.value,
			Combo = ComboState.Current(state.Combo, os.clock()),
			LuckyPending = state.LuckyPending,
			PityStar = state.PityStar,
			MutationPity = state.MutationPityPending,
			SinceSuper = state.Luck.sinceSuper,
			SinceJackpot = state.Luck.sinceJackpot,
			SinceMutation = state.Luck.sinceMutation,
			Measure = state.Measure,
		}
		else nil
end

return Progress
