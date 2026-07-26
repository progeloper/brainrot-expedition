--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local Carts = require(ReplicatedStorage.Shared.Config.Carts)

local CartSpawnValidator = require(ReplicatedStorage.Shared.Validation.CartSpawnValidator)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("CartSpawnRegistry")

local CART_OCCUPANCY_RADIUS = 12

export type CartSpawnRecord = {
	Id: string,
	CartId: string,
	Priority: number,
	Enabled: boolean,
	DebugOnly: boolean,
	Part: BasePart,
	CFrame: CFrame,
}

local CartSpawnRegistry = {}

local spawnRecords: { [string]: CartSpawnRecord } = {}
local hasStarted = false

local function getSpawnFolder(): Folder
	local instance = Workspace:WaitForChild("CartSpawns")

	assert(instance:IsA("Folder"), "Workspace.CartSpawns must be a Folder")

	return instance
end

local function registerSpawn(spawnPart: BasePart)
	CartSpawnValidator.AssertValid(spawnPart)

	local spawnId = spawnPart:GetAttribute("SpawnId") :: string

	local cartId = spawnPart:GetAttribute("CartId") :: string

	local enabled = spawnPart:GetAttribute("Enabled") :: boolean

	local priority = spawnPart:GetAttribute("Priority") :: number

	local debugOnlyAttribute = spawnPart:GetAttribute("DebugOnly")

	local debugOnly = if type(debugOnlyAttribute) == "boolean" then debugOnlyAttribute else false

	assert(spawnRecords[spawnId] == nil, string.format("Duplicate cart SpawnId %s", spawnId))

	assert(
		Carts[cartId] ~= nil,
		string.format("Cart spawn %s references unknown CartId %s", spawnId, cartId)
	)

	if debugOnly and Environment.IsProduction then
		log:Debug("Skipping debug-only spawn %s", spawnId)

		return
	end

	spawnRecords[spawnId] = {
		Id = spawnId,
		CartId = cartId,
		Priority = priority,
		Enabled = enabled,
		DebugOnly = debugOnly,
		Part = spawnPart,
		CFrame = spawnPart.CFrame,
	}

	log:Info("Registered cart spawn %s for %s", spawnId, cartId)
end

local function isSpawnOccupied(record: CartSpawnRecord): boolean
	local runtime = Workspace:FindFirstChild("Runtime")

	if runtime == nil then
		return false
	end

	local carts = runtime:FindFirstChild("Carts")

	if carts == nil or not carts:IsA("Folder") then
		return false
	end

	for _, child in carts:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local root = child:FindFirstChild("Root")

		if root == nil or not root:IsA("BasePart") then
			continue
		end

		local distance = (root.Position - record.CFrame.Position).Magnitude

		if distance <= CART_OCCUPANCY_RADIUS then
			return true
		end
	end

	return false
end

function CartSpawnRegistry:Start()
	if hasStarted then
		log:Warn("Cart spawn registry already started")

		return
	end

	local folder = getSpawnFolder()

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			registerSpawn(child)
		else
			log:Warn("Ignoring non-BasePart in CartSpawns: %s", child:GetFullName())
		end
	end

	assert(next(spawnRecords) ~= nil, "No valid cart spawn points were registered")

	hasStarted = true

	log:Info("Cart spawn registry ready")
end

function CartSpawnRegistry:GetById(spawnId: string): CartSpawnRecord?
	assert(hasStarted, "CartSpawnRegistry has not started in this server execution context")

	return spawnRecords[spawnId]
end

function CartSpawnRegistry:GetDefaultForCart(cartId: string): CartSpawnRecord?
	assert(hasStarted, "CartSpawnRegistry has not started in this server execution context")

	local candidates: { CartSpawnRecord } = {}

	for _, record in spawnRecords do
		if not record.Enabled then
			continue
		end

		if record.CartId ~= cartId then
			continue
		end

		table.insert(candidates, record)
	end

	table.sort(candidates, function(a: CartSpawnRecord, b: CartSpawnRecord): boolean
		return a.Priority < b.Priority
	end)

	if #candidates == 0 then
		log:Warn("No enabled spawn candidates found for CartId %s", cartId)

		return nil
	end

	for _, record in candidates do
		if not isSpawnOccupied(record) then
			return record
		end
	end

	-- Every valid spawn is currently occupied.
	-- Fall back to the highest-priority spawn.
	return candidates[1]
end

function CartSpawnRegistry:GetAll(): { CartSpawnRecord }
	local result: { CartSpawnRecord } = {}

	for _, record in spawnRecords do
		table.insert(result, record)
	end

	table.sort(result, function(a: CartSpawnRecord, b: CartSpawnRecord): boolean
		return a.Priority < b.Priority
	end)

	return result
end

return CartSpawnRegistry
