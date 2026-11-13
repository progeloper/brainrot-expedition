--!strict
-- Studio-only review pen for draft animations (rig + animation brief v5, E.3).
-- Builds a platform above the Camp with: one looping copy per villager body animation on a
-- neutral skin and on Nonna Pina, a behaviour demo (a dummy cart drives past three villager
-- types playing the whole chase), a chatting pair and a waver. Everything is local.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.AnimationReview)
local Builder = require(ReplicatedStorage.Shared.Utility.VillagerBodyBuilder)
local UprightProp = require(ReplicatedStorage.Shared.Utility.VillagerUprightProp)
local Skins = ReplicatedStorage.Shared.Config.VillagerSkins
-- The villager skin shown in the back row of the plinths. Change it when the next skin goes
-- to review; Nonna Pina stays in the behaviour demo.
local REVIEW_SKIN = { module = "Beach_SurfistaSara", villager = "VIL_BEACH_SARA", region = "Beach" }
local ForestVillagers = require(ReplicatedStorage.Shared.Config.Villagers.Forest)

local Pen = {}
local started = false

type Actor = {
	model: Model,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	current: string?,
}

local ORDER = {
	"Idle",
	"Walk",
	"WalkGrumble",
	"Curious",
	"Shout",
	"RunSprint",
	"Tired",
	"RunTrot",
	"Alarm",
	"Reach",
	"Tag",
	"TantrumStomp",
	"TantrumFlail",
	"TantrumSquawk",
	"Wave",
	"Chat",
	"Chop",
	"Sweep",
	"Fish",
	"Knead",
	"Stir",
	"Skate",
	"Lookout",
	"Fiddle",
}

local function block(parent: Instance, size: Vector3, cframe: CFrame, colour: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function sign(parent: Instance, text: string, cframe: CFrame, size: Vector3)
	local board = block(parent, size, cframe, Color3.fromRGB(20, 22, 34))
	board.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(size.X * 60, size.Y * 60)
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
end

local function bubble(model: Model): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(70, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.Adornee = model:FindFirstChild("Head") :: BasePart
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex("#FFD447")
	label.TextStrokeTransparency = 0
	label.Text = ""
	label.Parent = gui
	return label
end

function Pen.Start()
	if started or not Config.IsOn() then
		return
	end
	started = true
	local sources = ReplicatedStorage:WaitForChild(Config.SourcesName, 30)
	local bodySources = sources and sources:FindFirstChild("VillagerBody")
	if not bodySources then
		warn("[AnimationReview] no draft animations to show")
		return
	end
	local animations: { [string]: Animation } = {}
	local lengths: { [string]: number } = {}
	local looped: { [string]: boolean } = {}
	for _, sequence in bodySources:GetChildren() do
		if sequence:IsA("KeyframeSequence") then
			local animation = Instance.new("Animation")
			animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			animations[sequence.Name] = animation
			lengths[sequence.Name] = (sequence:GetAttribute("Length") :: number?) or 1
			looped[sequence.Name] = sequence.Loop
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "AnimationReviewPen"
	folder.Parent = Workspace
	local origin = Config.Origin
	local floor = block(
		folder,
		Vector3.new(150, 1, 110),
		CFrame.new(origin - Vector3.new(0, 0.5, 0)),
		Color3.fromRGB(150, 196, 132)
	)
	floor.Name = "PenFloor"
	for _, edge in { { 0, 55.5, 150, 1 }, { 75.5, 0, 1, 110 }, { -75.5, 0, 1, 110 } } do
		block(
			folder,
			Vector3.new(edge[3], 4, edge[4]),
			CFrame.new(origin + Vector3.new(edge[1], 2, edge[2])),
			Color3.fromRGB(70, 80, 110)
		)
	end

	local neutralSkin = require(Skins.Neutral) :: any
	local pinaSkin = require(Skins.Forest_NonnaPina) :: any
	local pinaPalette = neutralSkin.palette
	-- The skin under review fills the back row of the plinths (REVIEW_SKIN at the top).
	local reviewSkin = require(Skins[REVIEW_SKIN.module]) :: any
	local reviewPalette = neutralSkin.palette
	for _, row in ForestVillagers.villagers do
		if row.id == "VIL_FOREST_PINA" then
			pinaPalette = row.palette
		end
	end
	-- the review skin's palette comes from its own region's villager list
	local regionRows = require(ReplicatedStorage.Shared.Config.Villagers[REVIEW_SKIN.region]) :: any
	for _, row in regionRows.villagers do
		if row.id == REVIEW_SKIN.villager then
			reviewPalette = row.palette
		end
	end

	local function actor(skin: any, palette: any, cframe: CFrame): Actor
		local model = Builder.Build(skin, palette)
		model:PivotTo(cframe)
		model.Parent = folder
		if model:GetAttribute("UprightProp") then
			UprightProp.Bind(model)
		end
		local controller = model:FindFirstChildOfClass("AnimationController") :: AnimationController
		local animator = controller:FindFirstChildOfClass("Animator") :: Animator
		return { model = model, animator = animator, tracks = {}, current = nil }
	end
	local function track(who: Actor, name: string): AnimationTrack
		local existing = who.tracks[name]
		if not existing then
			existing = who.animator:LoadAnimation(animations[name])
			who.tracks[name] = existing
		end
		return existing :: AnimationTrack
	end
	local function switch(who: Actor, name: string, fade: number?)
		if who.current == name then
			return
		end
		if who.current then
			track(who, who.current):Stop(fade or 0.15)
		end
		who.current = name
		track(who, name):Play(fade or 0.15)
	end

	-- 1. One copy per animation: neutral skin in front, Nonna Pina behind.
	sign(
		folder,
		"VILLAGER BODY: every animation (front row neutral skin, back row "
			.. reviewSkin.name
			.. ")",
		CFrame.new(origin + Vector3.new(0, 9, 40)),
		Vector3.new(60, 3, 0.3)
	)
	local plinths: { { who: Actor, name: string } } = {}
	for index, name in ORDER do
		local column = (index - 1) % 12
		local bank = math.floor((index - 1) / 12)
		local x = -55 + column * 10
		local z = 10 + bank * 22
		for layer, skin in { neutralSkin, reviewSkin } do
			local spot = origin + Vector3.new(x, 0.6, z + (layer - 1) * 7)
			block(
				folder,
				Vector3.new(6, 0.6, 5),
				CFrame.new(spot - Vector3.new(0, 0.3, 0)),
				Color3.fromRGB(96, 104, 140)
			)
			local who = actor(
				skin,
				if layer == 1 then neutralSkin.palette else reviewPalette,
				CFrame.new(spot)
			)
			table.insert(plinths, { who = who, name = name })
		end
		sign(
			folder,
			name,
			CFrame.new(origin + Vector3.new(x, 1.2, z - 3.2)) * CFrame.Angles(math.rad(-25), 0, 0),
			Vector3.new(7, 1.4, 0.2)
		)
	end
	for _, entry in plinths do
		local animationTrack = track(entry.who, entry.name)
		if looped[entry.name] then
			animationTrack:Play(0)
		else
			-- One-shots replay every 2 seconds.
			task.spawn(function()
				while folder.Parent do
					animationTrack:Play(0.05)
					task.wait(math.max(2, lengths[entry.name] + 0.6))
				end
			end)
		end
	end

	-- 2. Behaviour demo: Idle/Activity -> "?" Curious -> "!" Shout -> chase -> Reach -> Tag
	-- -> tantrum -> WalkGrumble home. Speeds are scaled down to fit the lane.
	sign(
		folder,
		"BEHAVIOUR DEMO: Sprinter (left), Plodder as Nonna Pina (middle), Shouter (right). 18 s loop.",
		CFrame.new(origin + Vector3.new(0, 9, -52)) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(70, 3, 0.3)
	)
	local laneZ = -30
	local cart = block(
		folder,
		Vector3.new(7, 3, 5),
		CFrame.new(origin + Vector3.new(-60, 1.5, laneZ)),
		Color3.fromRGB(240, 120, 40)
	)
	cart.Name = "DummyCart"
	cart.CanCollide = false
	local demo = {
		{
			who = actor(neutralSkin, neutralSkin.palette, CFrame.new()),
			kind = "Sprinter",
			home = Vector3.new(-48, 0, laneZ + 12),
			activity = "Sweep",
			tantrum = "TantrumFlail",
		},
		{
			who = actor(pinaSkin, pinaPalette, CFrame.new()),
			kind = "Plodder",
			home = Vector3.new(-36, 0, laneZ + 14),
			activity = "Knead",
			tantrum = "TantrumStomp",
		},
		{
			who = actor(neutralSkin, neutralSkin.palette, CFrame.new()),
			kind = "Shouter",
			home = Vector3.new(-24, 0, laneZ + 12),
			activity = "Lookout",
			tantrum = "TantrumSquawk",
		},
	}
	local bubbles: { TextLabel } = {}
	for index, entry in demo do
		bubbles[index] = bubble(entry.who.model)
	end
	local CYCLE = 18
	local function demoStep(now: number)
		local t = now % CYCLE
		-- The cart waits, loads at 5 s and drives off; it resets for the next loop.
		local cartX = if t < 5.75 then -60 else math.min(60, -60 + (t - 5.75) * 16)
		cart.CFrame = CFrame.new(origin + Vector3.new(cartX, 1.5, laneZ))
		for index, entry in demo do
			local who = entry.who
			local home = origin + entry.home
			local notice = origin + Vector3.new(-56 + index * 5, 0, laneZ + 5)
			local position, facing, clip, mark = home, Vector3.new(0, 0, -1), entry.activity, ""
			if t < 2 then
				clip = entry.activity
			elseif t < 5 then
				local alpha = math.clamp((t - 2) / 2.6, 0, 1)
				position = home:Lerp(notice, alpha)
				facing = notice - home
				clip, mark = if alpha < 1 then "Curious" else "Idle", "?"
			elseif t < 5.75 then
				position, facing, clip, mark = notice, Vector3.new(-1, 0, -0.4), "Shout", "!"
			elseif t < 13.5 then
				local chase = t - 5.75
				mark = "!"
				if entry.kind == "Shouter" then
					position, facing = notice, Vector3.new(cartX + 56, 0, -5)
					clip = if chase < 7 then "Alarm" else entry.tantrum
					mark = if chase < 7 then "!" else ""
				else
					local burst = if entry.kind == "Sprinter" then 3 else 0
					local speed = if entry.kind == "Sprinter"
						then (if chase < burst then 19 else 12)
						else 12.5
					local travelled = if entry.kind == "Sprinter"
						then math.min(chase, burst) * 19 + math.max(0, chase - burst) * 12
						else chase * speed
					local caught = entry.kind == "Sprinter" and chase >= 2.6
					local stopAt = if entry.kind == "Sprinter" then 2.6 * 19 else 6 * speed
					local x = notice.X + math.min(travelled, stopAt)
					position =
						Vector3.new(x, origin.Y, origin.Z + laneZ + 5 - math.min(1, chase) * 3)
					facing = Vector3.new(1, 0, 0)
					if caught then
						clip = if chase < 2.95
							then "Tag"
							elseif chase < 4.45 then entry.tantrum
							else "Idle"
						mark = if chase < 2.95 then "BONK!" else ""
					elseif entry.kind == "Plodder" and chase >= 6 then
						clip = if chase < 7.5 then entry.tantrum else "Idle"
						mark = ""
					else
						clip = if entry.kind == "Sprinter" then "RunSprint" else "RunTrot"
						if math.abs(cartX - (x - origin.X)) < 8 then
							track(who, "Reach"):Play(0.1)
						end
					end
				end
			else
				-- Walk home grumbling.
				local from = if entry.kind == "Shouter"
					then notice
					else Vector3.new(
						notice.X + (if entry.kind == "Sprinter" then 49.4 else 75),
						origin.Y,
						origin.Z + laneZ + 2
					)
				local alpha = math.clamp((t - 13.5) / 4.2, 0, 1)
				position = from:Lerp(home, alpha)
				facing = home - from
				clip = if alpha < 1 then "WalkGrumble" else entry.activity
			end
			if clip ~= "RunSprint" and clip ~= "RunTrot" then
				local reach = who.tracks.Reach
				if reach and reach.IsPlaying then
					reach:Stop(0.1)
				end
			end
			local flat = Vector3.new(facing.X, 0, facing.Z)
			if flat.Magnitude < 1e-3 then
				flat = Vector3.new(0, 0, -1)
			end
			local goal = CFrame.lookAt(
				Vector3.new(position.X, origin.Y, position.Z),
				Vector3.new(position.X, origin.Y, position.Z) + flat
			)
			who.model:PivotTo(who.model:GetPivot():Lerp(goal, 0.35))
			switch(who, clip, if clip == "Shout" or clip == "Tag" then 0.05 else 0.15)
			bubbles[index].Text = mark
		end
	end

	-- 3. Chatting pair and a waver.
	sign(
		folder,
		"CHAT pair and WAVE (walk up to the waver)",
		CFrame.new(origin + Vector3.new(52, 6, -52)) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(30, 2, 0.3)
	)
	local chatA = actor(
		pinaSkin,
		pinaPalette,
		CFrame.lookAt(origin + Vector3.new(44, 0, -40), origin + Vector3.new(49, 0, -40))
	)
	local chatB = actor(
		neutralSkin,
		neutralSkin.palette,
		CFrame.lookAt(origin + Vector3.new(49, 0, -40), origin + Vector3.new(44, 0, -40))
	)
	track(chatA, "Chat"):Play()
	local second = track(chatB, "Chat")
	second:Play()
	second.TimePosition = 1.1
	local waver =
		actor(neutralSkin, neutralSkin.palette, CFrame.new(origin + Vector3.new(62, 0, -40)))
	track(waver, "Idle"):Play()
	local nextWave = 0

	-- 4. Brainrots: every species with baked drafts gets a row behind the behaviour demo.
	local walkers: {
		{
			model: Model,
			walk: AnimationTrack,
			run: AnimationTrack,
			centre: Vector3,
			walkSpeed: number,
			runSpeed: number,
			scale: number,
			angle: number,
		}
	} =
		{}
	local brainrotSources = sources and sources:FindFirstChild("Brainrots")
	if brainrotSources and #brainrotSources:GetChildren() > 0 then
		local VoxelBuilder = require(ReplicatedStorage.Shared.Utility.VoxelCreatureBuilder)
		local Registry = require(ReplicatedStorage.Shared.Utility.VoxelCreatureRegistry)
		local area = origin + Vector3.new(0, 0, -150)
		block(
			folder,
			Vector3.new(30, 1, 42),
			CFrame.new(origin + Vector3.new(0, -0.5, -75)),
			Color3.fromRGB(150, 196, 132)
		)
		local row = 0
		for _, speciesFolder in brainrotSources:GetChildren() do
			local data = Registry.GetData(speciesFolder.Name)
			if not data or not data.rig then
				continue
			end
			local scale = VoxelBuilder.GameplayScale(data)
			local function creature(cframe: CFrame, factor: number): (Model, Animator)
				local model = VoxelBuilder.Build(data)
				model:ScaleTo(scale * factor)
				model:PivotTo(cframe)
				model.Parent = folder
				local controller =
					model:FindFirstChildOfClass("AnimationController") :: AnimationController
				return model, controller:FindFirstChildOfClass("Animator") :: Animator
			end
			local clips: { [string]: Animation } = {}
			local names = {}
			for _, sequence in speciesFolder:GetChildren() do
				if sequence:IsA("KeyframeSequence") then
					local animation = Instance.new("Animation")
					animation.AnimationId =
						KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
					clips[sequence.Name] = animation
					table.insert(names, sequence.Name)
				end
			end
			table.sort(names)
			local z = 30 - row * 40
			sign(
				folder,
				speciesFolder.Name
					.. ": every animation, then 0.6x / 1.0x / 1.6x scale test (Celebrate), then walk and run at real speed",
				CFrame.new(area + Vector3.new(0, 12, z + 12)),
				Vector3.new(90, 3, 0.3)
			)
			for index, name in names do
				local spot = area + Vector3.new(-85 + (index - 1) * 14, 0, z)
				local _, animator = creature(CFrame.new(spot), 1)
				sign(
					folder,
					name,
					CFrame.new(spot + Vector3.new(0, 1, -7)) * CFrame.Angles(math.rad(-25), 0, 0),
					Vector3.new(9, 1.6, 0.2)
				)
				local sequence = speciesFolder:FindFirstChild(name) :: KeyframeSequence
				local animationTrack = animator:LoadAnimation(clips[name])
				if sequence.Loop then
					animationTrack:Play(0)
				else
					local length = (sequence:GetAttribute("Length") :: number?) or 1
					task.spawn(function()
						while folder.Parent do
							animationTrack:Play(0.05)
							task.wait(math.max(2, length + 0.6))
						end
					end)
				end
			end
			if clips.Celebrate then
				for index, factor in { 0.6, 1.0, 1.6 } do
					local spot = area + Vector3.new(-60 + index * 22, 0, z - 22)
					local _, animator = creature(CFrame.new(spot), factor)
					sign(
						folder,
						string.format("scale x%.1f", factor),
						CFrame.new(spot + Vector3.new(0, 1, -9))
							* CFrame.Angles(math.rad(-25), 0, 0),
						Vector3.new(8, 1.6, 0.2)
					)
					local animationTrack = animator:LoadAnimation(clips.Celebrate)
					task.spawn(function()
						while folder.Parent do
							animationTrack:Play(0.05)
							task.wait(2)
						end
					end)
				end
			end
			if clips.Walk and clips.Run then
				local model, animator = creature(CFrame.new(area + Vector3.new(55, 0, z - 22)), 1)
				local walkSequence = speciesFolder:FindFirstChild("Walk") :: KeyframeSequence
				local runSequence = speciesFolder:FindFirstChild("Run") :: KeyframeSequence
				table.insert(walkers, {
					model = model,
					walk = animator:LoadAnimation(clips.Walk),
					run = animator:LoadAnimation(clips.Run),
					centre = area + Vector3.new(55, 0, z - 22),
					walkSpeed = (walkSequence:GetAttribute("AuthoredSpeed") :: number?) or 6,
					runSpeed = (runSequence:GetAttribute("AuthoredSpeed") :: number?) or 12,
					scale = scale,
					angle = 0,
				})
			end
			row += 1
		end
		-- One floor under every species row (each row is 40 studs deep).
		local depth = 70 + math.max(1, row) * 40
		block(
			folder,
			Vector3.new(190, 1, depth),
			CFrame.new(area + Vector3.new(0, -0.5, 55 - depth / 2)),
			Color3.fromRGB(150, 196, 132)
		)
	end

	local player = Players.LocalPlayer
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)
		task.wait(2)
		if rootPart and rootPart:IsA("BasePart") then
			character:PivotTo(
				CFrame.lookAt(origin + Vector3.new(0, 5, -8), origin + Vector3.new(0, 5, 30))
			)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not folder.Parent then
			return
		end
		local now = os.clock()
		demoStep(now)
		for _, walker in walkers do
			-- 8 s of Walk then 4 s of Run around a 12-stud circle, at the authored ground speeds.
			local phase = now % 12
			local running = phase >= 8
			local speed = if running then walker.runSpeed else walker.walkSpeed
			walker.angle += speed / 12 * (1 / 60)
			local angle = walker.angle
			local position = walker.centre
				+ Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			walker.model:PivotTo(CFrame.lookAt(position, position + tangent))
			if running and not walker.run.IsPlaying then
				walker.walk:Stop(0.12)
				walker.run:Play(0.12)
			elseif not running and not walker.walk.IsPlaying then
				walker.run:Stop(0.2)
				walker.walk:Play(0.2)
			end
		end
		local character = player.Character
		if character and now >= nextWave then
			local distance = (character:GetPivot().Position - waver.model:GetPivot().Position).Magnitude
			if distance <= 15 then
				nextWave = now + 3
				local facing = character:GetPivot().Position - waver.model:GetPivot().Position
				waver.model:PivotTo(
					CFrame.lookAt(
						waver.model:GetPivot().Position,
						waver.model:GetPivot().Position + Vector3.new(facing.X, 0, facing.Z)
					)
				)
				track(waver, "Wave"):Play(0.1)
			end
		end
	end)
end

return Pen
