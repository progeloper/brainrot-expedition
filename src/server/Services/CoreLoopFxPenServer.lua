--!strict
-- Core Loop V2 visual review pen (L6), server side. Studio-only, driven by the CoreLoopQA "FxPen" verb
-- (which also sets ReplicatedStorage.CoreLoopFxPen so clients render every group's full look).
-- A fenced, lit platform next to the animation review pen with one labelled plinth per effect. Each plinth
-- loops its effect every 3 s on a real brainrot template by setting the same attributes the director and
-- temperaments set live, so clients run the exact live FX code paths. Event-only effects (SNEAK SHOT,
-- NOT YOURS YET, magnet) are sent through the live CoreLoopEvent remote.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AnimationReview = require(Shared.Config.AnimationReview)
local Theme = require(Shared.UI.Theme)
local CreatureAssets = require(script.Parent.Parent.Utility.CreatureAssetService)
local OddsText = require(Shared.CoreLoop.OddsText)
local WorldProgression = require(Shared.Config.WorldProgression)

-- Board 3 tag data: the live odds text and a rolling 14 s exclusivity window (YOURS / NOT YOURS YET).
local function odds(species: string, mutation: string?): string
	local home = WorldProgression.HomeBySpecies[species] or "REGION_FOREST"
	return OddsText.ForIndividual(home, species, mutation or "None")
end
local function exclusive(m: Model)
	m:SetAttribute("StarExclusiveUntil", Workspace:GetServerTimeNow() + 14)
end

local function fireAll(payload: any)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("CoreLoopEvent")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(payload)
	end
end

local Pen = {}

local LOOP = 3
local SPACING = 26
local function ownerId(): number
	local first = Players:GetPlayers()[1]
	return if first then first.UserId else 0
end

type Plinth = {
	Group: string,
	Name: string,
	Species: string,
	Setup: (Model, number) -> ()?,
	Loop: (Model, number) -> (),
	Recreate: boolean?,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local PLINTHS: { Plinth } = {
	-- Group 2 · Star kit
	{
		Group = "2 · Star kit",
		Name = "Star pillar (yours, guarded)",
		Species = "BRT_019",
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Star")
			m:SetAttribute("Guarded", true)
			m:SetAttribute("StarOwnerUserId", ownerId())
			m:SetAttribute("StarOdds", odds("BRT_019"))
			exclusive(m)
		end,
		Loop = function(m)
			exclusive(m)
		end,
	},
	{
		Group = "2 · Star kit",
		Name = "Super Star pillar",
		Species = "BRT_026",
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Super")
			m:SetAttribute("Guarded", true)
			m:SetAttribute("StarOwnerUserId", ownerId())
			m:SetAttribute("StarOdds", odds("BRT_026"))
		end,
		Loop = function() end,
	},
	{
		Group = "2 · Star kit",
		Name = "JACKPOT sky beam",
		Species = "BRT_019",
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Jackpot")
			m:SetAttribute("BrainrotMutationId", "Golden")
			m:SetAttribute("StarOwnerUserId", ownerId())
			m:SetAttribute("StarOdds", odds("BRT_019", "Golden"))
		end,
		Loop = function() end,
	},
	{
		Group = "2 · Star kit",
		Name = "Other player's Star (50%)",
		Species = "BRT_022",
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Star")
			m:SetAttribute("StarOwnerUserId", -1)
			exclusive(m)
		end,
		Loop = function(m)
			exclusive(m)
		end,
	},
	{
		Group = "2 · Star kit",
		Name = "LEAVING (last 20 s)",
		Species = "BRT_024",
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Star")
			m:SetAttribute("StarOwnerUserId", ownerId())
		end,
		Loop = function(m, cycle)
			-- Restart the 20 s drain every ~6 loops so the clock, flicker and ticks are all visible.
			if cycle % 6 == 0 then
				m:SetAttribute("StarLeavingUntil", now() + 18)
			end
		end,
	},
	{
		Group = "2 · Star kit",
		Name = "Dive",
		Species = "BRT_020",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Star")
			m:SetAttribute("StarOwnerUserId", ownerId())
		end,
		Loop = function(m)
			task.delay(1.2, function()
				m:SetAttribute("StarDiving", now())
			end)
		end,
	},
	-- Group 3 · Arrivals
	{
		Group = "3 · Arrivals",
		Name = "Herd pop",
		Species = "BRT_003",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopRole", "Snack")
		end,
		Loop = function() end,
	},
	{
		Group = "3 · Arrivals",
		Name = "Beam drop (Star)",
		Species = "BRT_019",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Star")
			m:SetAttribute("Arrival", "Beam")
			m:SetAttribute("StarOwnerUserId", ownerId())
		end,
		Loop = function() end,
	},
	{
		Group = "3 · Arrivals",
		Name = "Meteor (Lucky Star)",
		Species = "BRT_023",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Super")
			m:SetAttribute("Arrival", "Meteor")
			m:SetAttribute("StarOwnerUserId", ownerId())
		end,
		Loop = function() end,
	},
	{
		Group = "3 · Arrivals",
		Name = "Rift (Jackpot)",
		Species = "BRT_031",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopStar", true)
			m:SetAttribute("VisibleGrade", "Jackpot")
			m:SetAttribute("Arrival", "Rift")
			m:SetAttribute("StarOwnerUserId", ownerId())
		end,
		Loop = function() end,
	},
	-- Group 4 · Mutations
	{
		Group = "4 · Mutations",
		Name = "Shimmer (type hidden)",
		Species = "BRT_013",
		Setup = function(m)
			m:SetAttribute("CoreLoopRole", "Snack")
			m:SetAttribute("CoreLoopShimmer", true)
		end,
		Loop = function() end,
	},
}
for _, mutation in { "Shiny", "Golden", "Glitched", "Radioactive", "Astral" } do
	table.insert(PLINTHS, {
		Group = "4 · Mutations",
		Name = "Reveal: " .. mutation,
		Species = "BRT_019",
		Recreate = true,
		Setup = function(m)
			m:SetAttribute("CoreLoopRole", "Snack")
			m:SetAttribute("CoreLoopShimmer", true)
			m:SetAttribute("BrainrotMutationId", "None")
		end,
		Loop = function(m)
			task.delay(1, function()
				m:SetAttribute("CoreLoopShimmer", nil)
				m:SetAttribute("BrainrotMutationId", mutation)
			end)
		end,
	})
end
table.insert(PLINTHS, {
	Group = "4 · Mutations",
	Name = "Upgrade → JACKPOT",
	Species = "BRT_019",
	Recreate = true,
	Setup = function(m)
		m:SetAttribute("CoreLoopStar", true)
		m:SetAttribute("VisibleGrade", "Super")
		m:SetAttribute("StarOwnerUserId", ownerId())
		m:SetAttribute("CoreLoopShimmer", true)
	end,
	Loop = function(m)
		task.delay(1, function()
			m:SetAttribute("CoreLoopShimmer", nil)
			m:SetAttribute("BrainrotMutationId", "Golden")
			m:SetAttribute("TrueGrade", "Jackpot")
			-- Board 2: the live reveal event (shout, odds pill, gem sticker, UPGRADED ribbon).
			fireAll({
				kind = "Reveal",
				model = m,
				mutationId = "Golden",
				odds = OddsText.ForMutation("Golden"),
				gems = 15,
				upgradedTo = "Jackpot",
			})
		end)
	end,
})
table.insert(PLINTHS, {
	Group = "4 · Mutations",
	Name = "Mutation Rain strike",
	Species = "BRT_027",
	Setup = function(m)
		m:SetAttribute("CoreLoopRole", "Snack")
	end,
	Loop = function(m, cycle)
		-- The live K4 presentation event; cycles the three Rain outcomes (Shiny / Golden / Glitched).
		local outcomes = { "Shiny", "Golden", "Glitched" }
		fireAll({
			kind = "Rain",
			model = m,
			mutation = outcomes[(cycle % 3) + 1],
			owner = "Pen",
			species = "Tralalero",
		})
	end,
})
-- Group 5 · Behaviour reads
local function read(name: string, species: string, loop: (Model) -> ())
	table.insert(PLINTHS, {
		Group = "5 · Behaviour",
		Name = name,
		Species = species,
		Setup = function(m)
			m:SetAttribute("CoreLoopRole", "Snack")
		end,
		Loop = function(m)
			loop(m)
		end,
	})
end
read('"!" spotted', "BRT_014", function(m)
	m:SetAttribute("CoreLoopAlertAt", now())
end)
read('Notice "?"', "BRT_011", function(m)
	m:SetAttribute("CoreLoopNoticeAt", now())
end)
read("Bolt dust", "BRT_021", function(m)
	m:SetAttribute("Motion", "Run")
	task.delay(1.6, function()
		m:SetAttribute("Motion", "Idle")
	end)
end)
read("Exhausted", "BRT_022", function(m)
	m:SetAttribute("CoreLoopExhaustedUntil", now() + 2.5)
end)
read("Groggy", "BRT_009", function(m)
	m:SetAttribute("CoreLoopGroggyUntil", now() + 1.2)
end)
read("Taunt (NYAH!)", "BRT_031", function(m)
	m:SetAttribute("CoreLoopTauntAt", now())
end)
read("Stagger", "BRT_016", function(m)
	m:SetAttribute("CoreLoopStaggerUntil", now() + 0.6)
end)
read("Herd scatter", "BRT_005", function(m)
	m:SetAttribute("CoreLoopHerdId", "pen" .. tostring(math.random(1, 1e6)))
	m:SetAttribute("CoreLoopScatterFrom", m:GetPivot().Position + Vector3.new(0, 0, 10))
	m:SetAttribute("CoreLoopScatterAt", now())
end)
read("SNEAK SHOT!", "BRT_018", function(m)
	fireAll({ kind = "Hit", model = m, sneak = true })
end)
read("NOT YOURS YET", "BRT_025", function(m)
	fireAll({ kind = "NotYours", model = m, seconds = 14 })
end)
read("Saved sleeper", "BRT_001", function(m)
	m:SetAttribute("Captured", true)
	m:SetAttribute("BrainrotDisplayState", "Sleeping")
	m:SetAttribute("SavedOwnerUserId", ownerId())
	m:SetAttribute("SavedUntil", now() + 45)
end)
read("Magnet +1", "BRT_006", function(m)
	fireAll({ kind = "Magnet", model = m })
end)

------------------------------------------------------------------ build

local folder: Folder? = nil
local stage: Folder? = nil
local running = false

local function template(species: string): Model?
	return CreatureAssets.GetTemplate(species)
end

local function label(parent: BasePart, text: string, size: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, size * 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, -1, 7)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Text = text
	textLabel.FontFace = Theme.Font.Body
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Ink
	stroke.Thickness = 2
	stroke.Parent = textLabel
	textLabel.Parent = billboard
	billboard.Parent = parent
end

local function spawnDummy(plinth: Plinth, base: CFrame): Model?
	local source = template(plinth.Species)
	if not source then
		return nil
	end
	local model = source:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model:SetAttribute("CoreLoopPen", true)
	model:SetAttribute("BrainrotId", plinth.Species)
	model:SetAttribute("Phase12EmergenceReadyAt", now())
	local _, size = model:GetBoundingBox()
	model:PivotTo(base * CFrame.new(0, size.Y * 0.5 + 1.2, 0))
	if plinth.Setup then
		plinth.Setup(model, 0)
	end
	model.Parent = stage
	return model
end

local function build()
	local origin = CFrame.new(AnimationReview.Origin + Vector3.new(0, 0, 140))
	local root = Instance.new("Folder")
	root.Name = "CoreLoopPenWorld"
	local groups: { string } = {}
	local byGroup: { [string]: { Plinth } } = {}
	for _, plinth in PLINTHS do
		if not byGroup[plinth.Group] then
			byGroup[plinth.Group] = {}
			table.insert(groups, plinth.Group)
		end
		table.insert(byGroup[plinth.Group], plinth)
	end
	local maxRow = 0
	for _, group in groups do
		maxRow = math.max(maxRow, #byGroup[group])
	end
	local width, depth = (maxRow + 1) * SPACING, (#groups + 1) * SPACING * 1.4
	local floor = Instance.new("Part")
	floor.Name = "PenFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(width, 1, depth)
	floor.CFrame = origin * CFrame.new(width / 2 - SPACING, -0.5, depth / 2 - SPACING)
	floor.Color = Color3.fromRGB(70, 140, 70)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = root
	for i, side in
		{ Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }
	do
		local fence = Instance.new("Part")
		fence.Name = "Fence" .. i
		fence.Anchored = true
		fence.Color = Theme.Color.Panel
		fence.Size = if side.X ~= 0 then Vector3.new(1, 3, depth) else Vector3.new(width, 3, 1)
		fence.CFrame = floor.CFrame * CFrame.new(side.X * width / 2, 1.5, side.Z * depth / 2)
		fence.Parent = root
	end
	local lightPart = Instance.new("Part")
	lightPart.Anchored, lightPart.Transparency, lightPart.CanCollide = true, 1, false
	lightPart.CFrame = floor.CFrame * CFrame.new(0, 40, 0)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness = 60, 1.5
	light.Parent = lightPart
	lightPart.Parent = root
	root.Parent = Workspace
	local pen = Instance.new("Folder")
	pen.Name = "CoreLoopPen"
	pen.Parent = Workspace
	folder, stage = root, pen
	-- Plinths
	local slots = {}
	for row, group in groups do
		local header = Instance.new("Part")
		header.Anchored, header.Transparency, header.CanCollide = true, 1, false
		header.Size = Vector3.one
		header.CFrame = origin * CFrame.new(-SPACING * 0.7, 1, (row - 1) * SPACING * 1.4)
		header.Parent = root
		label(header, "GROUP " .. group, 26)
		for col, plinth in byGroup[group] do
			local base = Instance.new("Part")
			base.Name = "Plinth"
			base.Anchored = true
			base.Size = Vector3.new(8, 1.2, 8)
			base.Color = Theme.Color.Ink2
			base.CFrame = origin * CFrame.new((col - 1) * SPACING, 0.6, (row - 1) * SPACING * 1.4)
			base.Parent = root
			label(base, plinth.Name, 16)
			table.insert(slots, {
				Plinth = plinth,
				Base = base.CFrame * CFrame.new(0, 0.6, 0),
				Model = nil :: Model?,
			})
		end
	end
	return slots, floor
end

function Pen.SetActive(on: boolean)
	if not RunService:IsStudio() then
		return
	end
	if on and not running then
		running = true
		local slots, floor = build()
		ReplicatedStorage:SetAttribute("CoreLoopFxPenCentre", floor.Position)
		task.spawn(function()
			local cycle = 0
			while running do
				cycle += 1
				for _, slot in slots do
					local ok, err = pcall(function()
						if
							slot.Plinth.Recreate
							or slot.Model == nil
							or slot.Model.Parent == nil
						then
							if slot.Model then
								slot.Model:Destroy()
							end
							slot.Model = spawnDummy(slot.Plinth, slot.Base)
						end
						if slot.Model then
							slot.Plinth.Loop(slot.Model, cycle)
						end
					end)
					if not ok then
						warn("[CoreLoopFxPen] " .. slot.Plinth.Name .. ": " .. tostring(err))
					end
				end
				task.wait(LOOP)
			end
		end)
	elseif not on and running then
		running = false
		if folder then
			folder:Destroy()
		end
		if stage then
			stage:Destroy()
		end
		folder, stage = nil, nil
	end
end

return Pen
