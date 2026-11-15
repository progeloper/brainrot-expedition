--!nocheck
-- MenusV2 "go there" pointer: a client-only bouncing arrow (BillboardGui, AlwaysOnTop) over a world
-- target plus an optional Beam from the player. View only: it never fires a remote.
--   WorldPointer.show(target: BasePart | Model | Attachment, seconds?, label?) -> boolean
-- Only one pointer exists at a time; it removes itself after `seconds` (default 6), on respawn,
-- or when its target leaves the world.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Juice = require(ReplicatedStorage.Shared.UI.Juice)

local P = Theme.Plate
local player = Players.LocalPlayer

local WorldPointer = {}

local current: { clean: () -> () }? = nil
local token = 0

local ARROW_COLOR = Color3.fromHex("#FFE14A")

-- A BasePart or Attachment the Billboard/Beam can hang on.
local function resolve(target: Instance?): Instance?
	if not target or not target:IsDescendantOf(workspace) then
		return nil
	end
	if target:IsA("BasePart") or target:IsA("Attachment") then
		return target
	end
	if target:IsA("Model") then
		if target.PrimaryPart then
			return target.PrimaryPart
		end
		local best, bestY = nil, -math.huge
		for _, d in target:GetDescendants() do
			if d:IsA("BasePart") and d.Position.Y > bestY then
				best, bestY = d, d.Position.Y
			end
		end
		return best
	end
	return nil
end

local function textLabel(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.FontFace = P.Font.Title
	t.TextColor3 = ARROW_COLOR
	t.TextScaled = true
	t.Size = size
	t.Position = position
	t.AnchorPoint = Vector2.new(0.5, 0)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = textSize
	c.MinTextSize = 14
	c.Parent = t
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = P.Color.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	t.Parent = parent
	return t
end

function WorldPointer.hide()
	token += 1
	if current then
		local c = current
		current = nil
		c.clean()
	end
end

function WorldPointer.show(target: Instance?, seconds: number?, label: string?): boolean
	WorldPointer.hide()
	local anchor = resolve(target)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not anchor or not playerGui then
		return false
	end
	token += 1
	local mine = token
	local items: { any } = {}
	local function add(x)
		table.insert(items, x)
		return x
	end
	local entry = {
		clean = function()
			for i = #items, 1, -1 do
				local x = items[i]
				if typeof(x) == "Instance" then
					if x:IsA("Tween") then
						x:Cancel()
					else
						x:Destroy()
					end
				elseif typeof(x) == "RBXScriptConnection" then
					x:Disconnect()
				end
			end
			table.clear(items)
		end,
	}
	current = entry

	-- arrow billboard
	local height = if anchor:IsA("BasePart") then anchor.Size.Y / 2 + 4 else 5
	local bb = add(Instance.new("BillboardGui"))
	bb.Name = "MenusV2WorldPointer"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Size = UDim2.fromOffset(120, 120)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bb.MaxDistance = 2000
	bb.Adornee = anchor
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = bb
	if label and label ~= "" then
		textLabel(holder, label, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0), 26)
	end
	local arrow = textLabel(holder, utf8.char(0x25BC), UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.5, 0.3), 80)
	arrow.TextColor3 = ARROW_COLOR
	bb.Parent = playerGui

	if not Juice.reduced() then
		local bounce = add(TweenService:Create(
			bb,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ StudsOffsetWorldSpace = Vector3.new(0, height + 2, 0) }
		))
		bounce:Play()
	end

	-- optional beam from the player's root to the target
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local a0 = add(Instance.new("Attachment"))
		a0.Name = "MenusV2PointerFrom"
		a0.Parent = root
		local a1: Attachment
		if anchor:IsA("Attachment") then
			a1 = anchor
		else
			a1 = add(Instance.new("Attachment"))
			a1.Name = "MenusV2PointerTo"
			a1.Parent = anchor
		end
		local beam = add(Instance.new("Beam"))
		beam.Name = "MenusV2PointerBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Width0 = 0.6
		beam.Width1 = 0.6
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(ARROW_COLOR)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		beam.Segments = 12
		beam.Parent = root
	end

	add(player.CharacterRemoving:Connect(function()
		if mine == token then
			WorldPointer.hide()
		end
	end))
	add(anchor.AncestryChanged:Connect(function()
		if mine == token and not anchor:IsDescendantOf(workspace) then
			WorldPointer.hide()
		end
	end))
	task.delay(seconds or 6, function()
		if mine == token then
			WorldPointer.hide()
		end
	end)
	return true
end

------------------------------------------------------------------ world lookups (read-only)
-- Same places the server's ValidateContext measures from (Phase13RuntimeService).

local function mapBlockout(): Instance?
	return workspace:FindFirstChild("MapBlockout")
end

local function hasCategory(prompt: ProximityPrompt, category: string): boolean
	if prompt:GetAttribute("CampCategory") == category then
		return true
	end
	local node = prompt.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("CampCategory") == category then
			return true
		end
		node = node.Parent
	end
	return false
end

-- The stall's Phase13ShopPrompt and its anchor part ("Weapon" | "Cart" | "Training").
function WorldPointer.stallPrompt(category: string): (ProximityPrompt?, BasePart?)
	local scope = mapBlockout() or workspace
	for _, d in scope:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "Phase13ShopPrompt" and hasCategory(d, category) then
			local parent = d.Parent
			if parent and parent:IsA("BasePart") then
				return d, parent
			end
		end
	end
	return nil, nil
end

-- MapBlockout.ServiceStallPatches.SellStall (the server's sale point), else the Model tagged Sell.
function WorldPointer.sellStall(): Instance?
	local map = mapBlockout()
	local patches = map and map:FindFirstChild("ServiceStallPatches")
	local point = patches and patches:FindFirstChild("SellStall")
	if point then
		return point
	end
	for _, d in (map or workspace):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("CampCategory") == "Sell" then
			return d
		end
	end
	return nil
end

-- The local player's base Model (PlayerBasePatches child owned by them).
function WorldPointer.ownBase(): Model?
	local map = mapBlockout()
	local patches = map and map:FindFirstChild("PlayerBasePatches")
	if not patches then
		return nil
	end
	local assigned = player:GetAttribute("AssignedBaseId")
	for _, base in patches:GetChildren() do
		if base:IsA("Model") then
			if base:GetAttribute("OwnerUserId") == player.UserId then
				return base
			end
			if assigned ~= nil and base:GetAttribute("BaseId") == assigned then
				return base
			end
		end
	end
	return nil
end

-- Own base entrance (Foundation.Phase13UpgradeEntrance, where Phase13BaseUpgradePrompt lives).
function WorldPointer.baseEntrance(): Attachment?
	local base = WorldPointer.ownBase()
	local foundation = base and base:FindFirstChild("Foundation")
	local entrance = foundation and foundation:FindFirstChild("Phase13UpgradeEntrance")
	return if entrance and entrance:IsA("Attachment") then entrance else nil
end

function WorldPointer.positionOf(x: Instance?): Vector3?
	if not x then
		return nil
	end
	if x:IsA("BasePart") then
		return x.Position
	elseif x:IsA("Attachment") then
		return x.WorldPosition
	elseif x:IsA("Model") then
		return x:GetPivot().Position
	end
	return nil
end

-- Distance from the local player's root to `x` (math.huge when unknown).
function WorldPointer.distanceTo(x: Instance?): number
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = WorldPointer.positionOf(x)
	if not root or not pos then
		return math.huge
	end
	return (root.Position - pos).Magnitude
end

return WorldPointer
