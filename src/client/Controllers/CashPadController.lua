--!strict
-- Playtest Fixes 2, Part C (flag-gated "CashPads"): the cash stack and the claim beat. Presentation
-- only: the server owns every claim (BaseIncomePlaqueSystem) and every number shown comes from the
-- plaque's replicated attributes.
--   C2  a hovering bill/coin pile over each of the local player's pads with unclaimed cash:
--       <= 12 non-colliding, non-queryable parts in 3 size steps, a "$1.2K" billboard, hidden at 0,
--       culled beyond 80 studs. The bob is one looping engine tween per pile; the shared <= 10 Hz
--       CampAnimationScheduler refreshes the amount/step and pauses culled piles.
--   C3  on ClaimRevision (own claim, paid > 0): the pile pops 1 -> 1.25 -> 0 (0.2 s), pooled coin
--       images burst from the pad (or the nearest screen edge) and arc to the HUD cash counter,
--       which rolls up on the first landing and bumps (throttled) with a "+$1.2K" beside it.
--       Coin ticks on landings, a chime for claims worth >= 60 s of that pad's income.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.PlaytestFixes2).CashPads
local Flags = require(Shared.Config.PlaytestFixes2Flags)
local Rules = require(Shared.Utility.CashPadRules)
local CurrencyFormatter = require(Shared.Utility.CurrencyFormatter)
local Quality = require(Shared.Utility.ResolvedPresentationQuality)
local StudPop = require(Shared.UI.StudPop)
local Theme = require(Shared.UI.Theme)
local Juice = require(Shared.UI.Juice)
local Scheduler = require(script.Parent.Parent.Utility.CampAnimationScheduler)
local AudioCue = require(script.Parent.Parent.Utility.AudioCue)

local PLAQUE_TAG = "BrainrotIncomePlaque"
local HOVER = 2.6 -- studs above the plaque
local BOB = 0.35
local COLORS = {
	bill = Color3.fromHex("#3FCB5A"),
	billDark = Color3.fromHex("#1E8F3A"),
	coin = Color3.fromHex("#FFD43B"),
}
-- 12 slots: (offset, size, kind); a step shows the first 4 / 8 / 12.
local SLOTS = {
	{ Vector3.new(0, 0, 0), Vector3.new(1.6, 0.18, 0.8), "bill" },
	{ Vector3.new(0.1, 0.2, 0.05), Vector3.new(1.6, 0.18, 0.8), "billDark" },
	{ Vector3.new(-0.9, 0.05, 0.6), Vector3.new(0.2, 0.7, 0.7), "coin" },
	{ Vector3.new(0.95, 0.05, -0.5), Vector3.new(0.2, 0.7, 0.7), "coin" },
	{ Vector3.new(-0.05, 0.4, -0.05), Vector3.new(1.6, 0.18, 0.8), "bill" },
	{ Vector3.new(0.05, 0.6, 0.05), Vector3.new(1.6, 0.18, 0.8), "billDark" },
	{ Vector3.new(-0.95, 0.4, -0.55), Vector3.new(0.2, 0.7, 0.7), "coin" },
	{ Vector3.new(0.9, 0.45, 0.6), Vector3.new(0.2, 0.7, 0.7), "coin" },
	{ Vector3.new(0, 0.8, 0), Vector3.new(1.6, 0.18, 0.8), "bill" },
	{ Vector3.new(0.05, 1.0, -0.05), Vector3.new(1.6, 0.18, 0.8), "billDark" },
	{ Vector3.new(-0.5, 1.2, 0.2), Vector3.new(0.2, 0.7, 0.7), "coin" },
	{ Vector3.new(0.45, 1.25, -0.2), Vector3.new(0.2, 0.7, 0.7), "coin" },
}

local player = Players.LocalPlayer
local Controller = {}
local started = false

type Pile = {
	plaque: BasePart,
	root: Part,
	parts: { BasePart },
	label: TextLabel,
	billboard: BillboardGui,
	bob: Tween?,
	step: number,
	popping: boolean,
	lastRevision: number,
	shown: boolean,
}

local folder: Folder? = nil
local piles: { [BasePart]: Pile } = {}
local coinGui: ScreenGui? = nil
local coinPool: { ImageLabel } = {}
local lastBumpAt = 0
local startedAt = 0

local function lowQuality(): boolean
	return Quality.GetTier(player:GetAttribute("VFXQuality")) == "Low"
end

local function unclaimedOf(plaque: BasePart): (number, number)
	local rate = plaque:GetAttribute("IncomeRatePerSecond")
	local r = if type(rate) == "number" and rate > 0 then rate else 0
	return Rules.Unclaimed(
		plaque:GetAttribute("UnclaimedCashSnapshot"),
		r,
		plaque:GetAttribute("IncomeSnapshotServerTime"),
		Workspace:GetServerTimeNow()
	),
		r
end

local function owned(plaque: BasePart): boolean
	return plaque:GetAttribute("BaseOwnerUserId") == player.UserId
		and plaque:GetAttribute("LockedSlot") ~= true
		and plaque:GetAttribute("IncomeOccupied") == true
end

local function pileFrame(plaque: BasePart): CFrame
	return CFrame.new(plaque.Position + Vector3.new(0, HOVER, 0))
end

local function setStep(pile: Pile, step: number)
	if pile.step == step then
		return
	end
	pile.step = step
	local count = step * 4
	for i, part in pile.parts do
		part.Transparency = if i <= count then 0 else 1
	end
	pile.billboard.Enabled = step > 0
end

local function setShown(pile: Pile, shown: boolean)
	if pile.shown == shown then
		return
	end
	pile.shown = shown
	if not pile.popping then
		pile.root.Parent = if shown then folder else nil
	end
	if pile.bob then
		if shown then
			pile.bob:Play()
		else
			pile.bob:Pause()
		end
	end
end

local function buildPile(plaque: BasePart): Pile
	local root = Instance.new("Part")
	root.Name = "CashStack"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = pileFrame(plaque)
	local parts = {}
	for i, slot in SLOTS do
		local p = Instance.new("Part")
		p.Name = "Cash" .. i
		p.Shape = if slot[3] == "coin" then Enum.PartType.Cylinder else Enum.PartType.Block
		p.Size = slot[2]
		p.Color = COLORS[slot[3]]
		p.Material = if slot[3] == "coin" then Enum.Material.Metal else Enum.Material.SmoothPlastic
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.CFrame = root.CFrame * CFrame.new(slot[1]) * CFrame.Angles(0, math.rad(i * 23), 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = root
		table.insert(parts, p)
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashAmount"
	billboard.Size = UDim2.fromOffset(110, 34)
	billboard.StudsOffset = Vector3.new(0, 2.1, 0)
	billboard.MaxDistance = Config.StackCullStuds
	billboard.LightInfluence = 0
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Font.Display
	label.TextScaled = true
	label.TextColor3 = Theme.Color.Cash
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Theme.Color.Ink
	stroke.Parent = label
	label.Parent = billboard
	billboard.Adornee = root
	billboard.Parent = root
	local bob = TweenService:Create(
		root,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = root.CFrame * CFrame.new(0, BOB, 0) * CFrame.Angles(0, math.rad(25), 0) }
	)
	local revision = plaque:GetAttribute("ClaimRevision")
	return {
		plaque = plaque,
		root = root,
		parts = parts,
		label = label,
		billboard = billboard,
		bob = if Juice.reduced() then nil else bob,
		step = -1,
		popping = false,
		lastRevision = if type(revision) == "number" then revision else 0,
		shown = false,
	}
end

--------------------------------------------------------------------------------
-- C3: coins to the counter
--------------------------------------------------------------------------------

local function hud(): any
	return require(script.Parent.Parent.UI.Screens.HudScreen)
end

local function ensureCoinGui(): ScreenGui
	if coinGui and coinGui.Parent then
		return coinGui
	end
	local g = StudPop.ScreenGui("CashPadCoins", 45)
	coinGui = g
	for i = 1, Config.CoinsHigh do
		local coin = Instance.new("ImageLabel")
		coin.Name = "Coin" .. i
		coin.BackgroundTransparency = 1
		coin.Image = Theme.Icons.Cash
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Size = UDim2.fromOffset(Theme.px(34), Theme.px(34))
		coin.Visible = false
		coin.ZIndex = 5
		coin.Parent = g
		table.insert(coinPool, coin)
	end
	return g
end

local function counterTarget(g: ScreenGui): (Vector2?, GuiObject?)
	local ok, pill = pcall(function()
		return hud().CashPillRoot()
	end)
	if not ok or not pill then
		return nil, nil
	end
	local centre = pill.AbsolutePosition + pill.AbsoluteSize * Vector2.new(0.3, 0.5)
	return centre - g.AbsolutePosition, pill
end

local function plusLabel(g: ScreenGui, at: Vector2, amount: number)
	local t = Instance.new("TextLabel")
	t.Name = "PlusCash"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.fromOffset(at.X + Theme.px(70), at.Y)
	t.Size = UDim2.fromOffset(Theme.px(120), Theme.px(30))
	t.FontFace = Theme.Font.Display
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Theme.Color.Cash
	t.Text = "+" .. CurrencyFormatter.FormatCompactCash(math.floor(amount))
	t.ZIndex = 6
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.Color.Ink
	stroke.Parent = t
	t.Parent = g
	local out = TweenService:Create(
		t,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.35),
		{
			Position = UDim2.fromOffset(at.X + Theme.px(70), at.Y + Theme.px(28)),
			TextTransparency = 1,
		}
	)
	TweenService:Create(
		stroke,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.35),
		{
			Transparency = 1,
		}
	):Play()
	out.Completed:Once(function()
		t:Destroy()
	end)
	out:Play()
end

local function flyCoins(plaque: BasePart, amount: number, chime: boolean)
	local g = ensureCoinGui()
	local target, pill = counterTarget(g)
	local camera = Workspace.CurrentCamera
	if not target or not camera then
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(plaque.Position + Vector3.new(0, HOVER, 0))
	local screen = Vector2.new(point.X, point.Y)
	if point.Z < 0 then
		-- behind the camera: mirror so the edge chosen is the side the pad is on
		screen = camera.ViewportSize - screen
		onScreen = false
	end
	local origin = Rules.CoinOrigin(screen, onScreen, camera.ViewportSize, Theme.px(24))
		- g.AbsolutePosition
	local count =
		math.min(#coinPool, Rules.CoinCount(lowQuality(), Config.CoinsHigh, Config.CoinsLow))
	local reduced = Juice.reduced()
	local first = true
	-- the counter rolls up when the first coin lands (HudScreen holds the Cash change until then)
	pcall(function()
		hud().HoldCash(Config.CoinFlightSeconds[1] + 0.05)
	end)
	for i = 1, count do
		local coin = coinPool[i]
		local flight = Config.CoinFlightSeconds[1]
			+ (Config.CoinFlightSeconds[2] - Config.CoinFlightSeconds[1])
				* ((i - 1) / math.max(1, count - 1))
		local delayTime = (i - 1) * Config.CoinStaggerSeconds
		local spread = Vector2.new(math.random(-40, 40), math.random(-30, 10))
			* (Theme.px(100) / 100)
		task.delay(delayTime, function()
			coin.Position = UDim2.fromOffset(origin.X, origin.Y)
			coin.Visible = true
			coin.ImageTransparency = 0
			local burst = origin + spread
			local landed = function()
				coin.Visible = false
				if os.clock() - lastBumpAt > 0.08 then
					lastBumpAt = os.clock()
					if pill and not reduced then
						Juice.pop(pill, 1.12)
					end
					AudioCue.Play("E1_" .. (i % 3 + 1), { bus = "UI", cooldown = 0.06 })
				end
				if first then
					first = false
					pcall(function()
						hud().ReleaseCash()
					end)
					plusLabel(g, target, amount)
					if chime then
						AudioCue.Play("E2_1", { bus = "UI", cooldown = 0.5 })
					end
				end
			end
			if reduced then
				coin.Position = UDim2.fromOffset(target.X, target.Y)
				task.delay(flight, landed)
				return
			end
			-- burst out, then arc to the counter (two engine tweens, no per-frame script)
			local out = TweenService:Create(
				coin,
				TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(burst.X, burst.Y) }
			)
			out.Completed:Once(function()
				local home = TweenService:Create(
					coin,
					TweenInfo.new(flight - 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In),
					{ Position = UDim2.fromOffset(target.X, target.Y) }
				)
				home.Completed:Once(landed)
				home:Play()
			end)
			out:Play()
		end)
	end
end

local function popPile(pile: Pile)
	if pile.popping or pile.step <= 0 then
		return
	end
	pile.popping = true
	if pile.bob then
		pile.bob:Pause()
	end
	local value = Instance.new("NumberValue")
	value.Value = 1
	local model = Instance.new("Model")
	-- ScaleTo needs a Model: wrap the pile for the 0.2 s pop, then unwrap.
	pile.root.Parent = model
	model.PrimaryPart = pile.root
	model.Parent = folder
	value.Changed:Connect(function(v)
		model:ScaleTo(math.max(0.01, v))
	end)
	local up = TweenService:Create(
		value,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Value = 1.25,
		}
	)
	up.Completed:Once(function()
		local down = TweenService:Create(
			value,
			TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{
				Value = 0.01,
			}
		)
		down.Completed:Once(function()
			model:ScaleTo(1)
			setStep(pile, 0)
			pile.root.Parent = if pile.shown then folder else nil
			model:Destroy()
			value:Destroy()
			pile.popping = false
			if pile.bob and pile.shown then
				pile.bob:Play()
			end
		end)
		down:Play()
	end)
	up:Play()
end

local function onClaim(pile: Pile)
	local plaque = pile.plaque
	local revision = plaque:GetAttribute("ClaimRevision")
	local r = if type(revision) == "number" then revision else 0
	if r <= pile.lastRevision then
		return
	end
	pile.lastRevision = r
	if plaque:GetAttribute("LastClaimUserId") ~= player.UserId then
		return
	end
	local paid = plaque:GetAttribute("LastClaimAmount")
	local amount = if type(paid) == "number" then paid else 0
	if amount <= 0 then
		return
	end
	local rate = plaque:GetAttribute("IncomeRatePerSecond")
	local chime = type(rate) == "number" and rate > 0 and amount / rate >= Config.ChimeIncomeSeconds
	popPile(pile)
	flyCoins(plaque, amount, chime)
end

--------------------------------------------------------------------------------

local function refresh(pile: Pile)
	if pile.popping then
		return
	end
	if not owned(pile.plaque) then
		setStep(pile, 0)
		return
	end
	local unclaimed, rate = unclaimedOf(pile.plaque)
	setStep(pile, Rules.StackStep(unclaimed, rate, Config.StackSteps))
	if pile.step > 0 then
		local text = CurrencyFormatter.FormatCompactCash(math.floor(unclaimed))
		if pile.label.Text ~= text then
			pile.label.Text = text
		end
	end
end

local function track(plaque: Instance)
	if not plaque:IsA("BasePart") or piles[plaque] then
		return
	end
	local pile = buildPile(plaque)
	piles[plaque] = pile
	plaque:GetAttributeChangedSignal("ClaimRevision"):Connect(function()
		onClaim(pile)
	end)
	Scheduler.Register(pile, {
		position = function()
			return if pile.plaque.Parent and owned(pile.plaque) then pile.plaque.Position else nil
		end,
		radius = Config.StackCullStuds,
		always = true,
		step = function()
			setShown(pile, true)
			refresh(pile)
		end,
		hidden = function()
			setShown(pile, false)
		end,
	})
end

local function untrack(plaque: Instance)
	local pile = piles[plaque :: BasePart]
	if not pile then
		return
	end
	piles[plaque :: BasePart] = nil
	Scheduler.Unregister(pile)
	if pile.bob then
		pile.bob:Cancel()
	end
	pile.root:Destroy()
end

function Controller.Start()
	if started or not Flags.Part("CashPads") then
		return
	end
	started = true
	local f = Instance.new("Folder")
	f.Name = "CashStacks"
	f.Parent = Workspace
	folder = f
	ensureCoinGui()
	for _, plaque in CollectionService:GetTagged(PLAQUE_TAG) do
		track(plaque)
	end
	CollectionService:GetInstanceAddedSignal(PLAQUE_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(PLAQUE_TAG):Connect(untrack)
	startedAt = os.clock()
end

-- QA: piles shown, steps and coin pool size.
function Controller.Diagnostics(): any
	local shown, steps = 0, {}
	for _, pile in piles do
		if pile.shown then
			shown += 1
		end
		steps[pile.step] = (steps[pile.step] or 0) + 1
	end
	return { piles = shown, steps = steps, coinPool = #coinPool, since = os.clock() - startedAt }
end

return Controller
