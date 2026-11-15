--!nocheck
-- MenusV2 Training stall (from "Trail Shop"). Opened only by the Training stall prompt (server
-- Phase13Update {kind="Open", category="Training"}); Phase13ShopController keeps every remote call:
--   Roller (buy if unowned, select if owned) -> ctx.trainingRoller(rollerId)
--                                             = {action="TrainingRoller", rollerId, operationId}
--   2× Training (Robux pass TRAINING_2X)      -> ctx.prompt(offerId) = {action="Prompt", offerId}
--   Train!                                    -> closes the window and points at the roller deck
-- Every number comes from snapshot.training (TrainingService.Snapshot) or Config/Training.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local TrainingConfig = require(ReplicatedStorage.Shared.Config.Training)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)
local PlaytestFlags = require(ReplicatedStorage.Shared.Config.PlaytestFixesFlags)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)

local Plate, Theme = Common.Plate, Common.Theme
local P = Theme.Plate
local px = Theme.px
local INK = P.Color.Ink

local Screen = {}

local ctx = nil
local window = nil
local renderBag = nil
local arrowGui = nil -- world arrow over the roller deck (outlives the window for 6 s, then removes itself)

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- Card colours and roller icon colour per roller id (Training.dc.html R[]).
local ROLLER_STYLE = {
	Wooden = { bg = { hex("#C98A4B"), hex("#7A4A22") }, roll = hex("#C98A4B") },
	Steel = { bg = P.Tier.T1, roll = hex("#C3C7D8") },
	Turbo = { bg = { hex("#FF8A2A"), hex("#C2560A") }, roll = hex("#FF8A2A") },
	Rocket = { bg = P.Tier.T5, roll = hex("#FF4B67") },
	Rift = { bg = P.Tier.T8, roll = hex("#FF49E1"), rainbow = true },
}
local GAUGE_COLORS =
	{ hex("#3BD16F"), hex("#FFD447"), hex("#FF8A2A"), hex("#FF4B67"), hex("#FF49E1") }

-- Needle angle: CampStallController.NeedleDegrees (pure). Fallback copies its formula
-- (CampStallController.lua:34-37): 225 - 270 * clamp(level, 0, Max) / Max.
local needleDegrees = function(level: number): number
	local clamped = math.clamp(level, 0, TrainingConfig.MaxLevel)
	return 225 - 270 * (clamped / TrainingConfig.MaxLevel)
end
do
	local controllers = script.Parent.Parent.Parent:FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("CampStallController")
	if module then
		local ok, camp = pcall(require, module)
		if ok and type(camp) == "table" and type(camp.NeedleDegrees) == "function" then
			needleDegrees = camp.NeedleDegrees
		end
	end
end

local function snapshot()
	return ctx and ctx.snapshot()
end

local function shortName(name: string): string
	local s = string.gsub(name or "", "%s*[Rr]ollers?$", "")
	return s
end

local function roundCorner(inst: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if scale then UDim.new(scale, 0) else UDim.new(0, px(3))
	c.Parent = inst
	return c
end

local function inkStroke(inst: GuiObject, thickness: number, color: Color3?)
	local st = Instance.new("UIStroke")
	st.Color = color or INK
	st.Thickness = math.max(1, thickness)
	st.Parent = inst
	return st
end

------------------------------------------------------------------ roller deck lookup + arrow
local function trainingStall(): Instance?
	local map = workspace:FindFirstChild("MapBlockout")
	local art = map and map:FindFirstChild("MapArt")
	local services = art and art:FindFirstChild("Services")
	if services then
		for _, child in services:GetChildren() do
			if
				child:GetAttribute("CampCategory") == "Training"
				or child.Name == "Kiosk_TrainingStall"
			then
				return child
			end
		end
	end
	return workspace:FindFirstChild("Kiosk_TrainingStall", true)
end

local function rollerTrigger(): BasePart?
	local stall = trainingStall()
	local slots = stall and stall:FindFirstChild("CampSlots")
	local trigger = slots and slots:FindFirstChild("RollerTrigger")
	if trigger and trigger:IsA("BasePart") then
		return trigger
	end
	return nil
end

-- Copy of TrainingService.InsideTrigger (TrainingService.lua:36-42; lenient box).
local function insideTrigger(trigger: CFrame, size: Vector3, point: Vector3): boolean
	local alongRollers = math.max(size.X + 6, 10)
	local acrossRollers = math.max(size.Z + 4, 8)
	local local3 = trigger:PointToObjectSpace(point)
	return math.abs(local3.X) <= alongRollers / 2
		and math.abs(local3.Z) <= acrossRollers / 2
		and math.abs(local3.Y) <= size.Y / 2
end

-- Already training: server attribute TrainingActive, or seated with the seat inside the trigger box.
local function onRollers(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	if player:GetAttribute("TrainingActive") == true then
		return true
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return false
	end
	local trigger = rollerTrigger()
	return trigger ~= nil and insideTrigger(trigger.CFrame, trigger.Size, seat.Position)
end

local function arrowOver(part: BasePart, text: string)
	if arrowGui then
		arrowGui:Destroy()
		arrowGui = nil
	end
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MenusV2_GuideArrow"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Size = UDim2.fromOffset(110, 140)
	bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 4, 0)
	local box = Plate.frame(bb, "Bounce", { Size = UDim2.fromScale(1, 1) })
	Plate.Label(box, text, { size = 18, frameSize = UDim2.fromScale(1, 0.24), z = 3 })
	local head = Plate.frame(box, "Head", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#FFE14A"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(46, 46),
		Rotation = 45,
		ZIndex = 1,
	})
	inkStroke(head, 4)
	local stem = Plate.frame(box, "Stem", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#FFE14A"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.new(0, 24, 0.4, 0),
		ZIndex = 2,
	})
	inkStroke(stem, 4)
	bb.Parent = playerGui
	arrowGui = bb
	if not Juice.reduced() then
		Plate.loop(
			nil,
			box,
			0.35,
			{ Position = UDim2.fromOffset(0, -18) },
			true,
			0,
			Enum.EasingStyle.Quad
		)
	end
	task.delay(6, function()
		bb:Destroy() -- also cancels the bounce tween
		if arrowGui == bb then
			arrowGui = nil
		end
	end)
end

local function goTrain()
	local trigger = rollerTrigger()
	if ctx then
		ctx.close()
	end
	-- Playtest Fixes D1: ask the server to put this player's cart on the rollers (it validates and
	-- seats; refusals come back as a toast). The window is already closed.
	if PlaytestFlags.Part("TrainPlace") then
		if onRollers() then
			return
		end
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild(RemoteNames.DriveAndHuntRequest)
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer("TrainPlace")
			return
		end
	end
	if trigger then
		arrowOver(trigger, "Rollers")
	else
		Plate.Toast(MenusV2.Gui(), "Drive onto the rollers at the Training stall")
	end
end

------------------------------------------------------------------ speedometer (Frames only)
local function speedometer(parent: Frame, level: number, maxLevel: number)
	local holder = Plate.frame(parent, "Speedometer", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	})
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = holder
	if Theme.Images.Rays ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = Theme.Images.Rays
		rays.ImageTransparency = 0.75
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.5, 1.5)
		rays.ZIndex = 5
		rays.Parent = holder
		if not Juice.reduced() then
			Plate.loop(
				renderBag,
				rays,
				P.Motion.Rays,
				{ Rotation = 360 },
				false,
				0,
				Enum.EasingStyle.Linear
			)
		end
	end
	-- 270° arc (225° -> -45°, the in-world gauge's sweep) in 5 colour bands, each bar on an ink backing
	local radius, bars = 0.4, 30
	local step = 270 / bars
	local barLen = 2 * math.pi * radius * (270 / 360) / bars * 1.18
	for i = 0, bars - 1 do
		local theta = 225 - step * (i + 0.5)
		local r = math.rad(theta)
		local pos = UDim2.fromScale(0.5 + radius * math.cos(r), 0.5 - radius * math.sin(r))
		local color = GAUGE_COLORS[math.floor(i / (bars / #GAUGE_COLORS)) + 1]
		Plate.frame(holder, "ArcInk" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromScale(barLen + 0.02, 0.15),
			Rotation = 90 - theta,
			ZIndex = 6,
		})
		Plate.frame(holder, "Arc" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromScale(barLen, 0.1),
			Rotation = 90 - theta,
			ZIndex = 7,
		})
	end
	-- readout "LV n"
	local readout = Plate.frame(holder, "Readout", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.46, 0.2),
		ZIndex = 8,
	})
	roundCorner(readout)
	inkStroke(readout, px(2), hex("#46A7FF"))
	Plate.Label(readout, "LV " .. level, { size = 20, color = hex("#6DF6FF"), z = 9 })
	-- needle: a square pivot rotated about its centre (GuiObject rotation is about the centre)
	local base = 90 - needleDegrees(math.clamp(level, 0, maxLevel))
	local pivot = Plate.frame(holder, "NeedlePivot", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Rotation = base,
		ZIndex = 10,
	})
	local needle = Plate.frame(pivot, "Needle", {
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.075, 0.44),
		ZIndex = 10,
	})
	roundCorner(needle, 0.5)
	local red = Plate.frame(needle, "Red", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#FF4B67"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.45, 0.9),
		ZIndex = 11,
	})
	roundCorner(red, 0.5)
	if not Juice.reduced() then
		pivot.Rotation = base - 2.5
		Plate.loop(renderBag, pivot, 0.12, { Rotation = base + 2.5 }, true)
	end
	local hub = Plate.frame(holder, "Hub", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#F7F5FC"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.11, 0.11),
		ZIndex = 12,
	})
	roundCorner(hub, 0.5)
	inkStroke(hub, px(3))
	-- red blinking lamp (top-right)
	local lamp = Plate.frame(holder, "Lamp", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#FF4B67"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.9, 0.1),
		Size = UDim2.fromScale(0.085, 0.085),
		ZIndex = 9,
	})
	roundCorner(lamp, 0.5)
	inkStroke(lamp, px(3))
	if not Juice.reduced() then
		Plate.loop(renderBag, lamp, 0.45, { BackgroundColor3 = hex("#5A1020") }, true)
	end
end

------------------------------------------------------------------ roller card art
local function rollerIcon(area: Frame, color: Color3, rollerId: string, index: number)
	local holder = Plate.frame(area, "Rollers", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.95),
		ZIndex = 7,
	})
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 112 / 40
	ar.Parent = holder
	local deck = Plate.frame(holder, "Deck", {
		BackgroundTransparency = 0,
		BackgroundColor3 = hex("#2A2F45"),
		Position = UDim2.fromScale(2 / 112, 26 / 40),
		Size = UDim2.fromScale(108 / 112, 10 / 40),
		ZIndex = 7,
	})
	roundCorner(deck)
	inkStroke(deck, px(2))
	local degPerSec = TrainingConfig.RollerSpinDegrees
			and TrainingConfig.RollerSpinDegrees[rollerId]
		or 300
	for i, cx in { 22, 56, 90 } do
		local roll = Plate.frame(holder, "Roll" .. i, {
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx / 112, 19 / 40),
			Size = UDim2.fromScale(22 / 112, 22 / 40),
			ZIndex = 8,
		})
		roundCorner(roll, 0.5)
		inkStroke(roll, px(2))
		local hl = Plate.frame(roll, "Highlight", {
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.28),
			Size = UDim2.fromScale(0.62, 0.2),
			ZIndex = 9,
		})
		roundCorner(hl, 0.5)
		if not Juice.reduced() then
			Plate.loop(
				renderBag,
				roll,
				360 / degPerSec,
				{ Rotation = 360 },
				false,
				(index + i) * 0.05,
				Enum.EasingStyle.Linear
			)
		end
	end
end

------------------------------------------------------------------ render
local function passRow(s)
	local passes = s.commerce and s.commerce.Passes or {}
	for _, p in passes do
		if p.id == TrainingConfig.PassId then
			return p
		end
	end
	return nil
end

local function render(pop: boolean)
	if not window then
		return
	end
	local s = snapshot()
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local old = window.Content:FindFirstChild("TrainingBody")
	if old then
		old:Destroy()
	end
	local body =
		Plate.frame(window.Content, "TrainingBody", { Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	local t = s and s.training
	if not s then
		window.setStat(nil)
		Plate.Label(
			body,
			"Loading…",
			{
				size = 20,
				frameSize = UDim2.new(1, 0, 0, px(40)),
				position = UDim2.fromOffset(0, px(60)),
			}
		)
		return
	end
	if type(t) ~= "table" then
		window.setStat(nil)
		Plate.Label(
			body,
			"Training is unavailable",
			{
				size = 22,
				frameSize = UDim2.new(1, 0, 0, px(40)),
				position = UDim2.fromOffset(0, px(80)),
			}
		)
		return
	end
	local level = t.level or 0
	local maxLevel = t.maxLevel or TrainingConfig.MaxLevel
	local maxed = level >= maxLevel
	window.setStat("Level " .. level .. "/" .. maxLevel)
	local rollers = if type(t.rollers) == "table" then t.rollers else {}
	local balance = s.balance or 0
	local training = onRollers()

	-- hero: speedometer (left) + roller / level / XP (right)
	local hero = Plate.frame(body, "Hero", { Size = UDim2.fromScale(1, 0.4), ZIndex = 5 })
	local left = Plate.frame(
		hero,
		"Gauge",
		{ Position = UDim2.fromScale(0.02, 0), Size = UDim2.fromScale(0.34, 1), ZIndex = 5 }
	)
	speedometer(left, level, maxLevel)
	local right = Plate.frame(
		hero,
		"Info",
		{ Position = UDim2.fromScale(0.38, 0), Size = UDim2.fromScale(0.6, 1), ZIndex = 6 }
	)
	local rl = Instance.new("UIListLayout")
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0, px(3))
	rl.Parent = right
	local selected = nil
	for _, r in rollers do
		if r.selected then
			selected = r
		end
	end
	if selected then
		Plate.Label(
			right,
			string.format(
				"~ %s ROLLER ×%s ~",
				string.upper(shortName(selected.name)),
				tostring(selected.multiplier)
			),
			{
				size = 18,
				min = 14,
				color = P.Color.RollerLine,
				frameSize = UDim2.fromScale(1, 0.2),
				order = 1,
				font = P.Font.Title,
			}
		)
	end
	local levelText = if maxed then "MAX LEVEL!" else "LV " .. level .. " → " .. (level + 1)
	local levelSlot = Plate.frame(
		right,
		"LevelLine",
		{ Size = UDim2.fromScale(1, 0.34), LayoutOrder = 2, ZIndex = 6 }
	)
	local back = Plate.Label(
		levelSlot,
		levelText,
		{
			size = 40,
			color = INK,
			strokePx = 0,
			font = P.Font.Title,
			position = UDim2.fromOffset(0, px(3)),
			z = 6,
		}
	)
	local front =
		Plate.Label(levelSlot, levelText, { size = 40, strokePx = 0, font = P.Font.Title, z = 7 })
	for _, l in { back, front } do
		l.TextScaled = false -- big hero number (the mockup's 'LV 12 -> 13')
		l.TextSize = px(40)
	end
	Plate.gradient(front, P.LevelGradient)
	local xpToNext = t.xpToNext or 0
	local frac = if maxed
		then 1
		elseif xpToNext > 0 and xpToNext < math.huge then math.clamp(
			(t.xp or 0) / xpToNext,
			0,
			1
		)
		else 0
	Plate.StripedProgress(right, {
		frac = frac,
		text = if maxed then maxLevel .. " / " .. maxLevel else math.floor(frac * 100) .. "%",
		size = UDim2.fromScale(0.86, 0.17),
		order = 3,
		bag = renderBag,
	})
	Plate.Label(right, "Drive onto the rollers to train", {
		size = 15,
		min = 14,
		color = P.Color.Hint,
		strokePx = 0,
		frameSize = UDim2.fromScale(1, 0.15),
		order = 4,
	})

	-- the ONE breathing primary: "Train!"; while already training, the cheapest affordable roller
	local trainPrimary = not training and not maxed
	local primaryId, cheapest = nil, math.huge
	if not trainPrimary then
		for _, r in rollers do
			if not r.owned and r.price <= balance and r.price < cheapest then
				primaryId, cheapest = r.id, r.price
			end
		end
	end

	-- roller row: 5 cards
	local row = Plate.frame(
		body,
		"RollerRow",
		{ Position = UDim2.fromScale(0, 0.41), Size = UDim2.fromScale(1, 0.41), ZIndex = 5 }
	)
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, px(6))
	rowList.Parent = row
	local count = math.max(1, #rollers)
	for i, r in rollers do
		local style = ROLLER_STYLE[r.id] or { bg = P.Tier.T1, roll = hex("#C3C7D8") }
		local card = Plate.ItemCard(row, {
			name = i .. ". " .. shortName(r.name),
			image = nil,
			background = style.bg,
			rainbow = style.rainbow,
			ring = if r.selected then P.Color.WellRim else nil,
			size = UDim2.new(1 / count, -px(6), 1, 0),
			imageHeight = 0.3,
			index = i,
			bag = renderBag,
			pop = pop,
		})
		for _, child in card.ImageArea:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy() -- no display shot: drop the TODO placeholder
			end
		end
		rollerIcon(card.ImageArea, style.roll, r.id, i)
		Plate.Label(card.Footer, "×" .. tostring(r.multiplier), {
			size = 20,
			color = hex("#FFE14A"),
			font = P.Font.Title,
			frameSize = UDim2.new(0.9, 0, 0, px(20)),
			order = 1,
			z = 9,
		})
		if r.selected then
			Common.Action(card, { kind = "well", text = "Using", bag = renderBag, height = 28 })
		elseif r.owned then
			Common.Action(card, {
				kind = "info",
				text = "Use",
				bag = renderBag,
				height = 28,
				onClick = function()
					ctx.trainingRoller(r.id)
				end,
			})
		elseif r.price <= balance then
			Common.Action(card, {
				kind = "go",
				text = Common.money(r.price),
				icon = Theme.Icons.Cash,
				primary = r.id == primaryId,
				bag = renderBag,
				height = 28,
				onClick = function()
					ctx.trainingRoller(r.id)
				end,
			})
		else
			Common.Action(
				card,
				{ kind = "locked", text = Common.money(r.price), bag = renderBag, height = 28 }
			)
		end
	end

	-- bottom: 2× Training pass + Train!
	local bottom = Plate.frame(
		body,
		"Bottom",
		{ Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(1, 0.16), ZIndex = 6 }
	)
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Padding = UDim.new(0, px(12))
	bl.Parent = bottom
	local passSize = UDim2.fromOffset(px(160), px(36))
	local passHost: GuiObject
	local pass = passRow(s)
	local price = pass and pass.enabled and ctx.regionalPrice(pass)
	if t.pass then
		passHost = Plate.StateWell(
			bottom,
			"2× Owned",
			{ size = passSize, order = 1, bag = renderBag, textSize = 18 }
		)
	elseif pass and pass.enabled and price then
		passHost = Plate.Button(bottom, {
			variant = "robux",
			text = "2× Training " .. utf8.char(0xE002) .. " " .. tostring(price),
			size = passSize,
			order = 1,
			textSize = 18,
			bag = renderBag,
			onClick = function()
				local result = ctx.prompt(pass.id)
				if result and not result.ok then
					Screen.notify(result, ctx.message(result))
				end
			end,
		}).Root
	else
		-- honest: Robux sales are not open (no platform id / delivery disabled)
		passHost = Plate.Button(bottom, {
			variant = "locked",
			text = "Robux soon",
			lockedReason = "Robux soon",
			size = passSize,
			order = 1,
			textSize = 18,
			bag = renderBag,
		}).Root
	end
	Plate.Starburst(
		passHost,
		"2×",
		renderBag,
		{ size = 30, position = UDim2.fromOffset(px(4), px(2)) }
	)
	local trainSize = UDim2.fromOffset(px(200), px(40))
	if maxed then
		Plate.StateWell(
			bottom,
			"Maxed!",
			{ size = trainSize, order = 2, bag = renderBag, textSize = 22 }
		)
	elseif training then
		Plate.Button(bottom, {
			variant = "info",
			text = "Training…",
			size = trainSize,
			order = 2,
			textSize = 22,
			bag = renderBag,
			onClick = function()
				ctx.close()
			end,
		})
	else
		Plate.Button(
			bottom,
			{
				variant = "go",
				text = "Train!",
				primary = true,
				size = trainSize,
				order = 2,
				textSize = 24,
				bag = renderBag,
				onClick = goTrain,
			}
		)
	end
end

function Screen.open(context, _category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Training",
			title = "Training",
			icon = Theme.Icons.Bolt,
			particles = "streaks",
			aspect = 860 / 505, -- Training.dc.html window
			maxSize = Vector2.new(860 / 1.5, 505 / 1.5),
			onClose = function()
				ctx.close()
			end,
		})
	end
	window.open()
	window.clearContent()
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

function Screen.notify(result, text)
	Common.notify(MenusV2.Gui(), result, text)
end

function Screen.close(instant: boolean?)
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	if window then
		window.close(instant)
	end
end

return Screen
