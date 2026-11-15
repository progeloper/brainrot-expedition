--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)
local CartSpawnValidator = require(ReplicatedStorage.Shared.Validation.CartSpawnValidator)

local log = Logger.new("PlayerBaseSystem")

type BaseRecord = {
	Id: string,
	Model: Model,
	PlayerSpawn: SpawnLocation,
	Owner: Player?,
	Generation: number,
}

export type AssignmentHandle = {
	Player: Player,
	Base: Model,
	BaseId: string,
	Generation: number,
}

local SlotPresentation = require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation)
local PlayerBaseSystem = {}
local hasStarted = false
local records: { BaseRecord } = {}
local recordsByBase: { [Model]: BaseRecord } = {}
local assignmentsByUserId: { [number]: BaseRecord } = {}
local departingPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local assignmentListeners: {
	[any]: {
		Assigned: (Player, Model, AssignmentHandle) -> (),
		Releasing: (Player, Model, AssignmentHandle) -> (),
	},
} =
	{}
local sessionClosingListeners: { [any]: (Player) -> () } = {}

-- The existing departure owner calls these before releasing a base. Income settles
-- and then closes its wallet here, not in a racing PlayerRemoving connection.
function PlayerBaseSystem:SubscribeSessionClosing(callback: (Player) -> ())
	local connection = {}
	sessionClosingListeners[connection] = callback
	function connection.Disconnect()
		sessionClosingListeners[connection] = nil
	end
	return connection
end

local function notifySessionClosing(player: Player)
	for _, callback in sessionClosingListeners do
		local ok, failure = pcall(callback, player)
		if not ok then
			log:Warn(
				"Pre-release session settlement failed for %s: %s",
				player.Name,
				tostring(failure)
			)
		end
	end
end

-- Internal lifecycle listeners must not yield. Release runs before the plot becomes free.
function PlayerBaseSystem:SubscribeAssignments(
	onAssigned: (Player, Model, AssignmentHandle) -> (),
	onReleasing: (Player, Model, AssignmentHandle) -> ()
)
	local connection = {}
	assignmentListeners[connection] = { Assigned = onAssigned, Releasing = onReleasing }
	function connection.Disconnect()
		assignmentListeners[connection] = nil
	end
	return connection
end

local function makeHandle(record: BaseRecord, player: Player): AssignmentHandle
	return table.freeze({
		Player = player,
		Base = record.Model,
		BaseId = record.Id,
		Generation = record.Generation,
	})
end

local function notifyAssignment(kind: string, player: Player, base: Model, handle: AssignmentHandle)
	for _, listener in assignmentListeners do
		local callback = if kind == "Assigned" then listener.Assigned else listener.Releasing
		local ok, failure = pcall(callback, player, base, handle)
		if not ok then
			log:Warn(
				"Base %s lifecycle listener failed for %s: %s",
				kind,
				base:GetFullName(),
				tostring(failure)
			)
		end
	end
end

function PlayerBaseSystem:GetRegisteredBases(): { Model }
	local bases = {}
	for _, record in records do
		table.insert(bases, record.Model)
	end
	return bases
end

local function validateBase(base: Instance, idCounts: { [string]: number }): string?
	local errors: { string } = {}
	local id = base:GetAttribute("BaseId")
	if not base:IsA("Model") then
		table.insert(errors, "base must be a Model")
	end
	if type(id) ~= "string" or id == "" then
		table.insert(errors, "missing non-empty BaseId")
	elseif idCounts[id] ~= 1 then
		table.insert(errors, string.format("duplicate BaseId %s", id))
	end

	for _, name in { "CartSpawn", "PlayerSpawn" } do
		local count = 0
		for _, child in base:GetChildren() do
			if child.Name == name then
				count += 1
			end
		end
		local marker = base:FindFirstChild(name)
		if count ~= 1 or marker == nil or not marker:IsA("BasePart") then
			table.insert(errors, string.format("requires exactly one direct %s BasePart", name))
			continue
		end
		if not marker.Anchored or marker.CanCollide or marker.CanTouch or marker.CanQuery then
			table.insert(
				errors,
				name .. " must be anchored with collision, touch and query disabled"
			)
		end
		if name == "PlayerSpawn" then
			if not marker:IsA("SpawnLocation") then
				table.insert(errors, "PlayerSpawn must be a SpawnLocation")
			elseif not marker.Neutral or marker.AllowTeamChangeOnTouch or marker.Duration ~= 0 then
				table.insert(
					errors,
					"PlayerSpawn requires Neutral=true, AllowTeamChangeOnTouch=false, Duration=0"
				)
			end
		else
			local validation = CartSpawnValidator.Validate(marker)
			for _, message in validation.Errors do
				table.insert(errors, "CartSpawn: " .. message)
			end
		end
	end

	return if #errors > 0 then table.concat(errors, "; ") else nil
end

function PlayerBaseSystem:GetBase(player: Player): Model?
	local record = assignmentsByUserId[player.UserId]
	if player.Parent ~= Players or record == nil or record.Owner ~= player then
		return nil
	end
	return record.Model
end

function PlayerBaseSystem:GetAssignment(player: Player): AssignmentHandle?
	local record = assignmentsByUserId[player.UserId]
	if player.Parent ~= Players or record == nil or record.Owner ~= player then
		return nil
	end
	return makeHandle(record, player)
end

function PlayerBaseSystem:IsCurrentAssignment(handle: any): boolean
	if type(handle) ~= "table" then
		return false
	end
	local player = handle.Player
	local base = handle.Base
	if typeof(player) ~= "Instance" and type(player) ~= "table" then
		return false
	end
	if typeof(base) ~= "Instance" or not base:IsA("Model") then
		return false
	end
	local record = recordsByBase[base]
	return record ~= nil
		and record.Owner == player
		and assignmentsByUserId[player.UserId] == record
		and record.Id == handle.BaseId
		and record.Generation == handle.Generation
end

function PlayerBaseSystem:IsOwner(player: Player, base: Instance): boolean
	if not base:IsA("Model") then
		return false
	end
	local record = recordsByBase[base]
	return player.Parent == Players
		and record ~= nil
		and record.Owner == player
		and assignmentsByUserId[player.UserId] == record
end

function PlayerBaseSystem:AssignBase(player: Player): (Model?, string?)
	if player.Parent ~= Players or departingPlayers[player] then
		return nil, "Player is no longer in this server"
	end
	if not hasStarted then
		return nil, "Base registry is not ready"
	end

	local existing = assignmentsByUserId[player.UserId]
	if existing ~= nil then
		if existing.Owner == player then
			return existing.Model, nil
		end
		return nil, "UserId already has an assignment for another Player instance"
	end

	-- Selection and claim never yield. Replicated attributes are not ownership authority.
	for _, record in records do
		if record.Owner == nil then
			record.Generation += 1
			SlotPresentation.Invalidate(record.Model, player.UserId, record.Generation)
			record.Model:SetAttribute("BaseOwnershipRevision", record.Generation)
			record.Owner = player
			assignmentsByUserId[player.UserId] = record
			record.Model:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("AssignedBaseId", record.Id)
			player:SetAttribute("BaseAssignmentGeneration", record.Generation)
			local handle = makeHandle(record, player)
			log:Info("Assigned %s to %s (UserId=%d)", record.Id, player.Name, player.UserId)
			notifyAssignment("Assigned", player, record.Model, handle)
			return record.Model, nil
		end
	end
	return nil, string.format("No valid free base available (%d registered)", #records)
end

function PlayerBaseSystem:ReleaseBase(player: Player, expectedHandle: AssignmentHandle?): boolean
	local record = assignmentsByUserId[player.UserId]
	-- An old Player callback must never clear a later Player's assignment.
	if record == nil or record.Owner ~= player then
		return false
	end
	local handle = makeHandle(record, player)
	if
		expectedHandle ~= nil
		and (
			expectedHandle.Player ~= player
			or expectedHandle.Base ~= record.Model
			or expectedHandle.Generation ~= record.Generation
		)
	then
		return false
	end
	SlotPresentation.Invalidate(record.Model, 0, record.Generation)
	notifyAssignment("Releasing", player, record.Model, handle)
	assignmentsByUserId[player.UserId] = nil
	record.Owner = nil
	record.Model:SetAttribute("OwnerUserId", 0)
	record.PlayerSpawn.Enabled = false
	player:SetAttribute("AssignedBaseId", nil)
	player:SetAttribute("BaseAssignmentGeneration", nil)
	log:Info("Released %s from %s (UserId=%d)", record.Id, player.Name, player.UserId)
	return true
end

function PlayerBaseSystem:BeginPlayerDeparture(player: Player)
	if departingPlayers[player] then
		return
	end
	departingPlayers[player] = true
	notifySessionClosing(player)
end

function PlayerBaseSystem:Start(options: any?): boolean
	if hasStarted then
		return true
	end

	-- These are existing edit-time bases, not a runtime generator. No readiness polling.
	local map = Workspace:FindFirstChild("MapBlockout")
	local folder = if map ~= nil then map:FindFirstChild("PlayerBasePatches") else nil
	if folder == nil then
		log:Warn("Base registry unavailable: missing Workspace.MapBlockout.PlayerBasePatches")
		return false
	end

	local bases = folder:GetChildren()
	local idCounts: { [string]: number } = {}
	for _, base in bases do
		local id = base:GetAttribute("BaseId")
		if type(id) == "string" and id ~= "" then
			idCounts[id] = (idCounts[id] or 0) + 1
		end
	end
	for _, base in bases do
		local problem = validateBase(base, idCounts)
		if problem ~= nil then
			log:Warn("Excluded base %s: %s", base:GetFullName(), problem)
			continue
		end
		local model = base :: Model
		local spawn = model:FindFirstChild("PlayerSpawn") :: SpawnLocation
		local record: BaseRecord = {
			Id = model:GetAttribute("BaseId") :: string,
			Model = model,
			PlayerSpawn = spawn,
			Owner = nil,
			Generation = 0,
		}
		SlotPresentation.Invalidate(model, 0, 0)
		model:SetAttribute("BaseOwnershipRevision", 0)
		model:SetAttribute("OwnerUserId", 0)
		spawn.Enabled = false -- Phase 5A-2 will enable only the assigned home location.
		table.insert(records, record)
		recordsByBase[model] = record
	end
	table.sort(records, function(left, right)
		return left.Id < right.Id
	end)
	hasStarted = true

	local function assignJoiningPlayer(player: Player)
		local base, reason = self:AssignBase(player)
		if base == nil then
			log:Warn(
				"Cannot assign base to %s (UserId=%d): %s",
				player.Name,
				player.UserId,
				reason or "unknown error"
			)
		end
	end
	Players.PlayerAdded:Connect(assignJoiningPlayer)
	if not (options and options.ExternalLifecycle == true) then
		Players.PlayerRemoving:Connect(function(player: Player)
			self:BeginPlayerDeparture(player)
			self:ReleaseBase(player)
		end)
		game:BindToClose(function()
			for _, player in Players:GetPlayers() do
				self:BeginPlayerDeparture(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		assignJoiningPlayer(player)
	end
	log:Info("Base registry ready: %d valid bases", #records)
	return true
end

return PlayerBaseSystem
