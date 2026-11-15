--!strict
-- Extra bank celebration layered on the existing Phase12 "Bank" batch event (same remote,
-- same server values; the existing celebration still runs untouched):
--   * the banked brainrot hops onto its pedestal with a squash-pop,
--   * a coin fountain in its rarity/mutation colours,
--   * an income roll-up to the batch's +$X/s (server value),
--   * a trip streak banner (x2, x3...) with this trip's Clean Escape stars flying in.
-- Visual and session-only. Started only when VillagerGuardsEnabled is true.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Palette = require(ReplicatedStorage.Shared.Config.VoxelCreaturePalette)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local CurrencyFormatter = require(ReplicatedStorage.Shared.Utility.CurrencyFormatter)

local player = Players.LocalPlayer
local Controller = {}

local FONT = Enum.Font.FredokaOne
local STROKE = Color3.fromRGB(8, 8, 10)
local TRIP_GAP_SECONDS = 45 -- banks closer together than this count as one trip

local started = false
local gui: ScreenGui? = nil
local streakLabel: TextLabel? = nil
local incomeLabel: TextLabel? = nil
local starsLabel: TextLabel? = nil
local streak = 0
local lastBankAt = -math.huge
local tripStars = 0 -- Clean Escape stars earned since the last bank (session-only)
local coinPool: { BasePart } = {}

local function reducedMotion(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

local function lowDetail(): boolean
	local tier = player:GetAttribute("WorldDetailTier")
	return tier == "Reduced" or tier == "Minimal" or player:GetAttribute("VFXQuality") == "Low"
end

local function hexColour(rarity: any, mutationId: any): Color3
	local hex = (type(mutationId) == "string" and Palette.MutationTag[mutationId]) or nil
	if not hex then
		local tier = Palette.RarityTiers[rarity :: any]
		hex = if tier then tier.primary else "#FFD447"
	end
	local ok, colour = pcall(Color3.fromHex, hex :: string)
	return if ok then colour else Color3.fromHex("#FFD447")
end

local function text(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	stroke: number
): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = position
	item.Size = size
	item.Font = FONT
	item.TextScaled = true
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Visible = false
	local outline = Instance.new("UIStroke")
	outline.Thickness = stroke
	outline.Color = STROKE
	outline.Parent = item
	item.Parent = parent
	return item
end

local function ensureGui()
	if gui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "VillagerBankFx"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 42
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	streakLabel = text(screen, "Streak", UDim2.fromScale(0.5, 0.44), UDim2.fromScale(0.34, 0.09), 3)
	incomeLabel =
		text(screen, "Income", UDim2.fromScale(0.5, 0.53), UDim2.fromScale(0.3, 0.065), 2.5)
	starsLabel = text(screen, "Stars", UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.3, 0.05), 2);
	(incomeLabel :: TextLabel).TextColor3 = Color3.fromHex(Palette.IncomeColor);
	(starsLabel :: TextLabel).TextColor3 = Color3.fromHex("#FFD447")
end

local function borrowCoin(): BasePart
	local coin = table.remove(coinPool)
	if coin then
		return coin
	end
	local part = Instance.new("Part")
	part.Name = "BankCoin"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.18, 0.9, 0.9)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function coinFountain(position: Vector3, colour: Color3)
	local count = if lowDetail() then 8 else 18
	for index = 1, count do
		local coin = borrowCoin()
		coin.Color = if index % 3 == 0 then Color3.fromHex("#FFD447") else colour
		coin.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
		coin.Transparency = 0
		coin.Parent = Workspace
		local angle = (index / count) * math.pi * 2 + math.random() * 0.4
		local out = 2.5 + math.random() * 3
		local peak = position
			+ Vector3.new(
				math.cos(angle) * out * 0.5,
				7 + math.random() * 4,
				math.sin(angle) * out * 0.5
			)
		local land = position + Vector3.new(math.cos(angle) * out, 0.5, math.sin(angle) * out)
		local up = TweenService:Create(
			coin,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				CFrame = CFrame.new(peak) * CFrame.Angles(0, angle, math.pi / 2),
			}
		)
		up:Play()
		up.Completed:Once(function()
			local down = TweenService:Create(
				coin,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					CFrame = CFrame.new(land) * CFrame.Angles(0, angle * 2, math.pi / 2),
					Transparency = 1,
				}
			)
			down:Play()
			down.Completed:Once(function()
				coin.Parent = nil
				table.insert(coinPool, coin)
			end)
		end)
	end
end

-- Squash-pop the creature visual standing on the pedestal (nearest local visual).
local function pedestalPop(position: Vector3)
	if reducedMotion() then
		return
	end
	local folder = Workspace:FindFirstChild("Phase13CreatureVisuals")
	if not folder then
		return
	end
	local best: Model? = nil
	local bestDistance = 8
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local distance = (model:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	if not best then
		return
	end
	local model = best :: Model
	local base = model:GetScale()
	local pivot = model:GetPivot()
	local start = os.clock()
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local t = (os.clock() - start) / 0.45
		if t >= 1 or model.Parent == nil then
			connection:Disconnect()
			if model.Parent then
				model:ScaleTo(base)
				model:PivotTo(pivot)
			end
			return
		end
		local hop = math.sin(t * math.pi) * 1.6
		local squash = 1 + math.sin(t * math.pi * 2) * 0.12
		model:ScaleTo(base * squash)
		model:PivotTo(pivot * CFrame.new(0, hop, 0))
	end)
end

local function rollIncome(target: number)
	-- Same compact formatter as the existing bank celebration ("$1.9M/s").
	local label = incomeLabel :: TextLabel
	label.Visible = true
	local start = os.clock()
	local duration = 0.9
	task.spawn(function()
		while os.clock() - start < duration do
			local t = (os.clock() - start) / duration
			label.Text = "+"
				.. CurrencyFormatter.FormatCompactCash(target * (1 - (1 - t) ^ 3))
				.. "/s"
			task.wait()
		end
		label.Text = "+" .. CurrencyFormatter.FormatCompactCash(target) .. "/s"
		task.wait(1.6)
		label.Visible = false
	end)
end

local function showStreak(count: number, stars: number)
	local label = streakLabel :: TextLabel
	local starLine = starsLabel :: TextLabel
	if count >= 2 then
		label.Text = "RUN STREAK x" .. count
		label.Visible = true
		if not reducedMotion() then
			label.Size = UDim2.fromScale(0.16, 0.04)
			TweenService
				:Create(
					label,
					TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						Size = UDim2.fromScale(0.34, 0.09),
					}
				)
				:Play()
		end
	end
	if stars > 0 then
		starLine.Text = string.rep("⭐", math.min(stars, 8))
		starLine.Visible = true
		if not reducedMotion() then
			starLine.Position = UDim2.fromScale(0.5, 0.9)
			TweenService
				:Create(
					starLine,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromScale(0.5, 0.6),
					}
				)
				:Play()
		end
	end
	task.delay(2.6, function()
		label.Visible = false
		starLine.Visible = false
	end)
end

local function onBank(payload: any)
	if payload.userId ~= player.UserId then
		return
	end
	ensureGui()
	local records = if type(payload.records) == "table" then payload.records else { payload }
	local now = os.clock()
	if now - lastBankAt > TRIP_GAP_SECONDS then
		streak = 0
	end
	lastBankAt = now
	streak += #records
	for index, record in records do
		local position = record.platformPosition or record.position
		if typeof(position) == "Vector3" then
			task.delay((index - 1) * 0.18, function()
				pedestalPop(position)
				coinFountain(position, hexColour(record.rarity, record.mutationId))
			end)
		end
	end
	if type(payload.cashPerSecond) == "number" and payload.cashPerSecond > 0 then
		rollIncome(payload.cashPerSecond)
	end
	showStreak(streak, tripStars)
	tripStars = 0
end

-- Called by EscapeRingController when a chase ends.
function Controller.AddEscape(clean: boolean)
	if clean then
		tripStars += 1
	end
end

function Controller.Start(escapeCompleted: BindableEvent?)
	if started then
		return
	end
	started = true
	if escapeCompleted then
		escapeCompleted.Event:Connect(function(clean)
			Controller.AddEscape(clean == true)
		end)
	end
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		local remote = remotes and remotes:WaitForChild(RemoteNames.Phase12Event, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(payload)
				if
					type(payload) == "table"
					and payload.kind == "Bank"
					and payload.batchReady == true
				then
					onBank(payload)
				end
			end)
		end
	end)
end

return Controller
