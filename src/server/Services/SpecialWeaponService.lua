--!strict
-- Camp Rework (12 Nov 2026): server-only grants for the Won special weapons. Behind
-- CampReworkV1Enabled. Every grant goes through the existing Phase13 critical transaction, so it
-- shares the durable save/receipt path of every other ownership change. Clients never name a grant.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CampFlags = require(RS.Shared.Config.CampReworkFlags)
local Rules = require(RS.Shared.Utility.SpecialWeaponRules)
local Profiles = require(script.Parent.PlayerDataService)
local Transactions = require(script.Parent.Phase13Service)

local Service = {}
local started = false
local pendingEscapes: { [Player]: number } = {}
local CHECK_SECONDS = 5

local function opId(kind: string): string
	return kind .. ":" .. HttpService:GenerateGUID(false)
end

local function onGranted(player: Player, result: any)
	local granted = type(result) == "table" and result.result and result.result.granted
	if type(granted) == "table" and #granted > 0 then
		player:SetAttribute("CampSpecialGranted", table.concat(granted, ","))
	end
end

-- Grant any Won special this profile has earned. Safe to call often; no-op when nothing is due.
function Service:CheckPlayer(player: Player)
	if not CampFlags.CampRework() or Profiles:GetStatus(player) ~= "Ready" or Transactions:IsBusy(player) then
		return
	end
	local data = Profiles:GetReadableData(player)
	if not data or #Rules.Earned(data) == 0 then
		return
	end
	local result = Transactions:CommitCritical(player, opId("SpecialWeaponGrant"), "SpecialWeaponGrant", function(current)
		return Rules.ApplyEarned(current)
	end)
	onGranted(player, result)
end

-- Clean escapes are counted durably (they unlock the Getaway Crossbow at 25).
function Service:RecordCleanEscape(player: Player)
	if not CampFlags.CampRework() then
		return
	end
	if Profiles:GetStatus(player) ~= "Ready" or Transactions:IsBusy(player) then
		pendingEscapes[player] = (pendingEscapes[player] or 0) + 1
		return
	end
	local result = Transactions:CommitCritical(player, opId("CleanEscape"), "CleanEscape", function(current)
		return Rules.ApplyCleanEscape(current)
	end)
	if type(result) == "table" and result.ok == false and result.code == "BUSY" then
		pendingEscapes[player] = (pendingEscapes[player] or 0) + 1
	end
	onGranted(player, result)
end

function Service:Start()
	if started or not CampFlags.CampRework() then
		return false
	end
	started = true
	local ok, Villagers = pcall(require, script.Parent.VillagerGuardService)
	if ok and type(Villagers) == "table" then
		local villagers: any = Villagers
		villagers.onCleanEscape = function(player: Player)
			self:RecordCleanEscape(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		pendingEscapes[player] = nil
	end)
	task.spawn(function()
		while started do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local queued = pendingEscapes[player]
				if queued and queued > 0 and not Transactions:IsBusy(player) then
					pendingEscapes[player] = queued - 1
					self:RecordCleanEscape(player)
				else
					self:CheckPlayer(player)
				end
			end
		end
	end)
	return true
end

return Service
