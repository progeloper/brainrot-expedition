--!strict
-- Server-wide Mutation Storm (P15). Bought with Gems or Robux; the durable purchase
-- is recorded first and this service only applies the shared, temporary effect.
-- State is one Workspace attribute (server time); spawners read it per roll.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)

local Service = {}
local Storm = Economy.MutationStorm

function Service.Remaining(at: number?): number
	local now = at or Workspace:GetServerTimeNow()
	local untilAt = Workspace:GetAttribute(Storm.Attribute)
	return if type(untilAt) == "number" and untilAt > now then untilAt - now else 0
end

local function announce(player: Player?, seconds: number, total: number)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild(RemoteNames.WorldAnnouncement)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients({
			kind = "MutationStorm",
			userId = if player then player.UserId else nil,
			playerName = if player then player.DisplayName else "Someone",
			addedSeconds = seconds,
			remainingSeconds = total,
			multiplier = Storm.ChanceMultiplier,
		})
	end
end

-- Extends the storm. Time past the cap is not added (the shop blocks a full storm).
function Service.Activate(player: Player?, seconds: number, source: string?): number
	if type(seconds) ~= "number" or seconds <= 0 then
		return Service.Remaining()
	end
	local now = Workspace:GetServerTimeNow()
	local start = now + Service.Remaining(now)
	local untilAt = math.min(start + seconds, now + Storm.MaxSeconds)
	Workspace:SetAttribute(Storm.Attribute, untilAt)
	if player then
		Workspace:SetAttribute(Storm.BuyerAttribute, player.DisplayName)
	end
	announce(player, seconds, untilAt - now)
	return untilAt - now
end

function Service.CanAdd(seconds: number): boolean
	return Service.Remaining() + seconds <= Storm.MaxSeconds + 1
end

function Service.IsPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
end

return Service
