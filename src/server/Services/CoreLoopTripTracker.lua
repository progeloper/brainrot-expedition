--!strict
-- Core Loop V2 trip measurement (§3 Trip = Camp exit -> next auto-bank; §18.2 CL_Trip; A-4).
-- Server-side and passive: a trip starts when the player's own driven cart leaves Camp and ends at the next
-- bank commit for that player. Records seconds, KOs and loads (cargo increases) during the trip, plus the
-- time from "cargo full" to the bank. Runs whenever Core Loop V2 is on, or in Studio while
-- ServerStorage.CoreLoopQA is set (so flag-off trips can be compared on the same code).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Regions = require(ReplicatedStorage.Shared.Config.Regions)
local CoreLoopFlags = require(ReplicatedStorage.Shared.Config.CoreLoopFlags)

type Trip = {
	StartedAt: number,
	KOs: number,
	Loads: number,
	FullAt: number?,
	LastCargo: number,
}
type Record =
	{ Seconds: number, KOs: number, Loads: number, ReturnSeconds: number?, EndedAt: number }

local Tracker = {}

local deps: any = nil
local active: { [Player]: Trip } = {}
local inCampLast: { [Player]: boolean } = {}
local records: { [number]: { Record } } = {}
local started = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function drivenCart(player: Player): Model?
	local record = deps.CartService:GetCartRecord(player)
	local cart = record and record.Model
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return if cart and seat and cart:IsAncestorOf(seat) then cart else nil
end

local function inCamp(position: Vector3): boolean
	local RegionSpawnCatalog = require(script.Parent.Parent.Systems.RegionSpawnCatalog)
	return RegionSpawnCatalog.ContainsPosition(Regions.CampId, position, math.huge)
end

local function step()
	for _, player in Players:GetPlayers() do
		local cart = drivenCart(player)
		local trip = active[player]
		if cart then
			local camp = inCamp(cart:GetPivot().Position)
			if not camp and inCampLast[player] ~= false and not trip then
				-- Camp exit in the player's own driven cart: a trip starts.
				active[player] = {
					StartedAt = now(),
					KOs = 0,
					Loads = 0,
					FullAt = nil,
					LastCargo = cart:GetAttribute("CargoCount") or 0,
				}
			end
			inCampLast[player] = camp
			trip = active[player]
			if trip then
				local count = cart:GetAttribute("CargoCount") or 0
				local capacity = cart:GetAttribute("CargoCapacity") or 3
				if count > trip.LastCargo then
					trip.Loads += count - trip.LastCargo
				end
				trip.LastCargo = count
				if count >= capacity and not trip.FullAt then
					trip.FullAt = now()
				end
			end
		end
	end
end

local function onBank(player: Player)
	local trip = active[player]
	if not trip then
		return
	end
	active[player] = nil
	local t = now()
	local record: Record = {
		Seconds = t - trip.StartedAt,
		KOs = trip.KOs,
		Loads = trip.Loads,
		ReturnSeconds = if trip.FullAt then t - trip.FullAt else nil,
		EndedAt = t,
	}
	local list = records[player.UserId]
	if not list then
		list = {}
		records[player.UserId] = list
	end
	table.insert(list, record)
	if deps.Analytics and CoreLoopFlags.Enabled() then
		pcall(deps.Analytics.Record, deps.Analytics, player, "CL_Trip", record.Seconds, nil)
	end
end

function Tracker.Start(options: any): boolean
	if started then
		return false
	end
	local qa = RunService:IsStudio() and ServerStorage:GetAttribute("CoreLoopQA") == true
	if not CoreLoopFlags.Enabled() and not qa then
		return false
	end
	started = true
	deps = options
	if options.SleepSystem and options.SleepSystem.AddHitSubscriber then
		options.SleepSystem.AddHitSubscriber(function(player: Player, _model: Model, slept: boolean)
			local trip = active[player]
			if trip and slept then
				trip.KOs += 1
			end
		end)
	end
	if options.Banked and options.Banked.SubscribeBankCommitted then
		options.Banked:SubscribeBankCommitted(function(player: Player)
			onBank(player)
		end)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.25 then
			elapsed = 0
			pcall(step)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		inCampLast[player] = nil
	end)
	return true
end

function Tracker.GetTrips(userId: number): { Record }
	return table.clone(records[userId] or {})
end

function Tracker.Reset(userId: number)
	records[userId] = nil
end

function Tracker.Active(player: Player): any
	local trip = active[player]
	return if trip
		then { Seconds = now() - trip.StartedAt, KOs = trip.KOs, Loads = trip.Loads }
		else nil
end

return Tracker
