--!nocheck
-- Plate catch reveal. Renders CatchRevealController.RevealData; computes nothing.
-- Non-blocking: no scrim and no input capture (villagers may be chasing); it dismisses itself after the
-- controller's hold time. Intensity scales with rarity: Rare+ rays and flash, Epic+ spinning rays,
-- Legendary+ shake. Reduced Motion: fade only.
-- Other HUD code reads this ScreenGui by name ("StudPopCatchReveal") and its ActiveBottom attribute.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)
local Plate = require(ReplicatedStorage.Shared.UI.Plate)
local StudPop = require(ReplicatedStorage.Shared.UI.StudPop)
local Shots = require(ReplicatedStorage.Shared.Config.UIDisplayShots)

local P = Theme.Plate
local px = Theme.px

-- baseline px (844x390)
local WIDTH, HEIGHT = 340, 140
local LIP = 6
local HEADER = 24
local WELL = 74

local Screen = {}
local gui: ScreenGui? = nil
local generation = 0
local activeBag = nil

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	gui = StudPop.ScreenGui("StudPopCatchReveal", 40)
	gui:SetAttribute("StudPopOwned", true)
	return gui
end

local function corner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px(radius))
	c.Parent = inst
end

local function layer(parent: Instance, name: string, color: Color3, inset: number, radius: number): Frame
	local f = Plate.frame(parent, name, {
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
	})
	corner(f, radius)
	return f
end

local function tile(parent: GuiObject, image: string, tilePx: number, transparency: number, radius: number)
	if image == "" then
		return
	end
	local t = Instance.new("ImageLabel")
	t.Name = "Studs"
	t.BackgroundTransparency = 1
	t.Image = image
	t.ImageTransparency = transparency
	t.ScaleType = Enum.ScaleType.Tile
	t.TileSize = UDim2.fromOffset(px(tilePx), px(tilePx))
	t.Size = UDim2.fromScale(1, 1)
	t.Active = false
	corner(t, radius)
	t.Parent = parent
end

local function line(parent: Instance, name: string, text: string, color: Color3, font: Font, size: number, height: number, order: number)
	local label = Plate.Label(parent, text, {
		name = name,
		size = size,
		font = font,
		color = color,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, px(height)),
		order = order,
		z = 6,
	})
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

-- data: CatchRevealController.RevealData (+ MutationColour, IncomeText)
function Screen.Show(data: any, holdSeconds: number, inSeconds: number, outSeconds: number)
	generation += 1
	local token = generation
	local screen = ensureGui()
	if activeBag then
		activeBag.clean()
	end
	screen:ClearAllChildren()
	local bag = Plate.Bag()
	activeBag = bag
	local reduced = Juice.reduced()
	local intensity = Theme.RarityIntensity[data.Tier] or 1
	local tierColour = Theme.Rarity[data.Tier] or Theme.Rarity.Common
	local mutationColour = data.MutationColour or tierColour

	-- below the HUD's top band (pills/chips/phone rail) so it never covers HUD chrome
	local hud = require(script.Parent.HudScreen)
	local hudGui = hud.Gui()
	local top = px(10)
	if hudGui then
		top = math.max(top, hudGui.AbsolutePosition.Y + hud.TopBand() - screen.AbsolutePosition.Y)
	end

	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, top)
	card.Size = UDim2.fromOffset(px(WIDTH), px(HEIGHT))
	card.BackgroundTransparency = 1
	card.GroupTransparency = 1
	card.Active = false
	card.Parent = screen

	-- Plate frame: bottom lip, ink 3 -> grey 3 -> ink 3 -> body with the body stud tile
	local L = px(P.FrameLayers)
	local lip = Plate.frame(card, "BottomLip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Position = UDim2.fromOffset(0, px(LIP)),
		Size = UDim2.new(1, 0, 1, -px(LIP)),
	})
	corner(lip, P.Radius.Window)
	local outer = Plate.frame(card, "Outer", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		Size = UDim2.new(1, 0, 1, -px(LIP)),
	})
	corner(outer, P.Radius.Window)
	local grey = layer(outer, "Grey", P.Color.FrameGrey, L, P.Radius.Window - 1)
	local ink = layer(grey, "Ink", P.Color.Ink, L, P.Radius.Window - 1)
	local body = layer(ink, "Body", P.Color.WindowBody, L, P.Radius.Window - 2)
	body.ClipsDescendants = true
	tile(body, P.Tiles.Body, P.Tiles.BodyTile, 0.35, P.Radius.Window - 2)

	-- header strip in the rarity colour: "Caught!"
	local headerH = px(HEADER)
	local header = Plate.frame(body, "Header", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, headerH),
		ZIndex = 4,
		ClipsDescendants = true,
	})
	Plate.gradient(header, {
		tierColour:Lerp(Color3.new(1, 1, 1), 0.3),
		tierColour,
		tierColour:Lerp(P.Color.Ink, 0.25),
	}, 0)
	tile(header, P.Tiles.Surface, P.Tiles.SurfaceTile, 0.45, 0)
	Plate.frame(header, "Line", {
		BackgroundTransparency = 0,
		BackgroundColor3 = P.Color.Ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, px(2)),
		ZIndex = 5,
	})
	Plate.Label(header, "Caught!", {
		name = "Shout",
		size = 19,
		font = P.Font.Title,
		strokePx = 3,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(px(8), 0),
		frameSize = UDim2.new(1, -px(16), 1, -px(2)),
		z = 6,
	})
	if not reduced then
		Plate.sweep(header, bag, P.Motion.HeaderShine, 0.42, 5)
		Plate.twinkle(header, bag, UDim2.fromScale(0.9, 0.45), 10, 0.3)
	end

	-- display shot in a rarity-tinted well, rays behind it for Rare+
	local area = Plate.frame(body, "Row", {
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.new(1, 0, 1, -headerH),
		ZIndex = 4,
	})
	local well = Plate.frame(area, "ShotWell", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, px(7), 0.5, 0),
		Size = UDim2.fromOffset(px(WELL), px(WELL)),
		ZIndex = 5,
		ClipsDescendants = true,
	})
	corner(well, P.Radius.Card)
	local wellStroke = Instance.new("UIStroke")
	wellStroke.Color = P.Color.Ink
	wellStroke.Thickness = px(P.Stroke.Outline)
	wellStroke.Parent = well
	Plate.gradient(well, { tierColour:Lerp(Color3.new(1, 1, 1), 0.2), tierColour:Lerp(P.Color.Ink, 0.55) })
	if intensity >= 2 and Theme.Images.Rays ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = Theme.Images.Rays
		rays.ImageTransparency = 0.4
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.7, 1.7)
		rays.ZIndex = 5
		rays.Parent = well
		if intensity >= 3 and not reduced then
			Plate.loop(bag, rays, P.Motion.Rays, { Rotation = 360 }, false, 0, Enum.EasingStyle.Linear)
		end
	end
	local shot = Instance.new("ImageLabel")
	shot.Name = "Shot"
	shot.BackgroundTransparency = 1
	shot.Image = Shots.get(data.SpeciesId)
	shot.ScaleType = Enum.ScaleType.Fit
	shot.AnchorPoint = Vector2.new(0.5, 0.5)
	shot.Position = UDim2.fromScale(0.5, 0.5)
	shot.Size = UDim2.fromScale(0.94, 0.94)
	shot.ZIndex = 6
	shot.Parent = well

	-- name-tag order: name, mutation + odds, tier + odds + region, income
	local col = Plate.frame(area, "Lines", {
		Position = UDim2.fromOffset(px(WELL + 15), 0),
		Size = UDim2.new(1, -px(WELL + 23), 1, 0),
		ZIndex = 5,
	})
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = col
	line(col, "Name", data.Name, P.Color.White, P.Font.Title, 22, 25, 1)
	if data.MutationName then
		line(col, "Mutation", data.MutationName .. (if data.MutationOdds then "  " .. data.MutationOdds else ""), mutationColour, P.Font.Label, 15, 18, 2)
	end
	line(
		col,
		"Rarity",
		data.Tier .. (if data.TierOdds then "  " .. data.TierOdds else "") .. (if data.RegionName then "  ·  " .. data.RegionName else ""),
		tierColour,
		P.Font.Label,
		15,
		18,
		3
	)
	if data.Income and data.IncomeText then
		line(col, "Income", "+" .. data.IncomeText .. "/s", P.Color.Cash, P.Font.Title, 20, 23, 4)
	end

	-- motion: fade in (always); pop, sparkles, flash and shake scale with rarity
	local scale = Juice.scaleOf(card)
	scale.Scale = if reduced then 1 else 0.6
	Juice.play(card, "fade", TweenInfo.new(inSeconds), { GroupTransparency = 0 })
	if not reduced then
		Juice.play(scale, "pop", TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		Juice.sparkles(well, 1 + intensity, mutationColour)
		if intensity >= 2 then
			local flash = Plate.frame(body, "Flash", {
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromScale(1, 1),
				ZIndex = 20,
			})
			Juice.play(flash, "flash", TweenInfo.new(0.25), { BackgroundTransparency = 1 }).Completed:Once(function()
				flash:Destroy()
			end)
		end
		if intensity >= 4 then
			Juice.shake(card, 3, 0.15)
		end
	end
	Juice.sound(if intensity >= 4 then "RewardBig" else "RewardSmall", 0)

	-- publish the card's bottom edge (absolute) so the HUD's rare card can sit below it
	task.defer(function()
		if token == generation and card.Parent then
			screen:SetAttribute("ActiveBottom", card.AbsolutePosition.Y + card.AbsoluteSize.Y)
		end
	end)
	task.delay(inSeconds + holdSeconds, function()
		if token ~= generation or not card.Parent then
			return
		end
		screen:SetAttribute("ActiveBottom", nil)
		Juice.play(card, "fade", TweenInfo.new(outSeconds), { GroupTransparency = 1 }).Completed:Once(function()
			if token == generation then
				bag.clean()
				if activeBag == bag then
					activeBag = nil
				end
				card:Destroy()
			end
		end)
	end)
	return card
end

return Screen
