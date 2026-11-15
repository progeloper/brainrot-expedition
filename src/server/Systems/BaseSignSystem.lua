--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerBaseSystem = require(script.Parent.PlayerBaseSystem)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local log = Logger.new("BaseSignSystem")

local BaseSignSystem = {}
local started = false
local generation = 0
local connection: any = nil
local template: Model? = nil
local registered: { [Model]: boolean } = {}
local MANAGED_BY = "BaseSignSystem"

-- The imported board and post both have the name Part. Identify the editable
-- board by its actual SurfaceGui, never by an ambiguous Part-name lookup.
local function display(sign: Model): (BasePart?, SurfaceGui?, TextLabel?)
	for _, child in sign:GetChildren() do
		if child:IsA("BasePart") then
			local gui = child:FindFirstChild("SurfaceGui")
			local label = if gui then gui:FindFirstChild("TextLabel") else nil
			if gui and gui:IsA("SurfaceGui") and label and label:IsA("TextLabel") then
				return child, gui, label
			end
		end
	end
	return nil, nil, nil
end

local function placeSign(sign: Model, board: BasePart, foundation: BasePart, cartDisplay: BasePart)
	-- The inspected imported GUI uses Front (-Z); the foundation's -Z faces camp.
	local rotation = foundation.CFrame.Rotation
		* board.CFrame.Rotation:Inverse()
		* sign:GetPivot().Rotation
	sign:PivotTo(rotation)
	local bounds, size = sign:GetBoundingBox()
	-- Beside the approach, outside both cart deck and ramp. All twelve inspected
	-- camp floors meet the deck's bottom datum (not the raised foundation top).
	local ground = cartDisplay.CFrame:PointToWorldSpace(
		Vector3.new(
			-cartDisplay.Size.X / 2 - 8,
			-cartDisplay.Size.Y / 2,
			-cartDisplay.Size.Z / 2 - 11
		)
	)
	local shift = Vector3.new(
		ground.X - bounds.Position.X,
		ground.Y - (bounds.Position.Y - size.Y / 2),
		ground.Z - bounds.Position.Z
	)
	sign:PivotTo(sign:GetPivot() + shift)
end

function BaseSignSystem:EnsureSign(base: Model): (Model?, TextLabel?)
	if not started or not registered[base] or template == nil then
		return nil, nil
	end
	local sign: Model? = nil
	for _, child in base:GetChildren() do
		if
			child:IsA("Model")
			and child:GetAttribute("ManagedBy") == MANAGED_BY
			and child:GetAttribute("BaseId") == base:GetAttribute("BaseId")
		then
			if sign == nil then
				sign = child
			else
				child:Destroy() -- Only this feature's verified duplicate for this base.
			end
		end
	end
	if sign == nil then
		local foundation = base:FindFirstChild("Foundation")
		local cartDisplay = base:FindFirstChild("CartDisplay")
		if
			foundation == nil
			or not foundation:IsA("BasePart")
			or cartDisplay == nil
			or not cartDisplay:IsA("BasePart")
		then
			log:Warn("No sign for %s: missing static Foundation/CartDisplay", base:GetFullName())
			return nil, nil
		end
		sign = template:Clone()
		sign.Name = "OwnershipSign"
		sign:SetAttribute("ManagedBy", MANAGED_BY)
		sign:SetAttribute("BaseId", base:GetAttribute("BaseId"))
		for _, child in sign:GetDescendants() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				if
					(child.Part0 and not child.Part0:IsDescendantOf(sign))
					or (child.Part1 and not child.Part1:IsDescendantOf(sign))
				then
					child:Destroy()
				end
			elseif child:IsA("Constraint") then
				if
					(child.Attachment0 and not child.Attachment0:IsDescendantOf(sign))
					or (child.Attachment1 and not child.Attachment1:IsDescendantOf(sign))
				then
					child:Destroy()
				end
			end
		end
		for _, child in sign:GetDescendants() do
			if child:IsA("BasePart") then
				child.Anchored = true
				child.CanCollide, child.CanTouch, child.CanQuery = false, false, false
			end
		end
		local board = display(sign)
		assert(board, "Inspected sign template lost its display board")
		placeSign(sign, board, foundation, cartDisplay)
		sign.Parent = base
	end
	local board, gui, label = display(sign)
	if board == nil or gui == nil or label == nil then
		log:Warn("Managed sign %s is missing its imported text surface", sign:GetFullName())
		return sign, nil
	end
	gui.Adornee = board
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(800, 400)
	gui.Enabled = true
	label.BackgroundTransparency = 1
	label.Size, label.Position = UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1)
	-- Roblox disables TextScaled when TextWrapped is set false.
	label.TextWrapped, label.TextScaled = true, true
	return sign, label
end

function BaseSignSystem:SetOwnerText(base: Model, player: Player?)
	local _, label = self:EnsureSign(base)
	if label == nil then
		return
	end
	local owner = player
	if owner == nil or not PlayerBaseSystem:IsOwner(owner, base) then
		owner = nil
		for _, candidate in Players:GetPlayers() do
			if PlayerBaseSystem:IsOwner(candidate, base) then
				owner = candidate
				break
			end
		end
	end
	label.Text = if owner then owner.Name else "Unclaimed"
end

function BaseSignSystem:RefreshBase(base: Model)
	self:SetOwnerText(base, nil)
end

function BaseSignSystem:Start(): boolean
	if started then
		return true
	end
	local assets = ReplicatedStorage:FindFirstChild("StudioAssets")
	local signs = if assets then assets:FindFirstChild("BaseSigns") else nil
	local source = if signs then signs:FindFirstChild("Sell Sign") else nil
	if source == nil or not source:IsA("Model") or display(source) == nil then
		log:Warn(
			"Signs unavailable: expected ReplicatedStorage.StudioAssets.BaseSigns.Sell Sign with Part.SurfaceGui.TextLabel; spawning remains enabled"
		)
		return false
	end
	template = source
	started = true
	generation += 1
	local currentGeneration = generation
	connection = PlayerBaseSystem:SubscribeAssignments(function(player, base)
		self:SetOwnerText(base, player)
	end, function(_, base)
		-- Releasing is notified before the authority clears its record. Refresh after
		-- that synchronous release, and resolve again so an old callback cannot clear a new owner.
		task.defer(function()
			if started and generation == currentGeneration then
				self:RefreshBase(base)
			end
		end)
	end)
	local bases = PlayerBaseSystem:GetRegisteredBases()
	for _, base in bases do
		registered[base] = true
		self:RefreshBase(base)
	end
	log:Info("Ownership signs ready for %d registered bases", #bases)
	return true
end

function BaseSignSystem:Destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	started = false
	generation += 1
	template = nil
	table.clear(registered)
end

return BaseSignSystem
