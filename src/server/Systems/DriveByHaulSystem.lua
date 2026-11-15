--!strict
-- Drive-by haul (owner decision, 10 Nov 2026). The server watches each driven
-- owner cart: a sleeping brainrot beside it is loaded, and on arrival at the
-- owner's base the cargo is banked onto free platforms. Clients send nothing;
-- every transfer goes through the existing validated cargo and storage paths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HuntFlow = require(ReplicatedStorage.Shared.Config.HuntFlow)
-- Drive-and-Hunt Part D (12 Nov 2026), only while its flag is on: reach is measured from the
-- cart's edge, and a full-cargo toast is mirrored to the client for the home arrow.
local DriveAndHunt = require(ReplicatedStorage.Shared.Config.DriveAndHunt)
local DriveAndHuntFlags = require(ReplicatedStorage.Shared.Config.DriveAndHuntFlags)
local DriveAndHuntRules = require(ReplicatedStorage.Shared.Utility.DriveAndHuntRules)
local CartGeometry = require(ReplicatedStorage.Shared.Utility.CartGeometry)

type Dependencies = {
	World: any,
	Interaction: any,
	Cargo: any,
	GetDrivenCart: (Player) -> Model?,
	GetBase: (Player) -> Model?,
	Feedback: ((Player, string) -> ())?,
}

local System = {}
local dependencies: Dependencies? = nil
local connection: RBXScriptConnection? = nil
local elapsed = 0
local nextBankAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastFeedback: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local baseBounds: { [Model]: { Frame: CFrame, Size: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
local stats = { Scooped = 0, Banked = 0, LastScoopReason = "", LastBankReason = "" }

local function tell(player: Player, key: string, text: string)
	local deps = dependencies
	if not deps or not deps.Feedback then
		return
	end
	local sent = lastFeedback[player]
	if not sent then
		sent = {}
		lastFeedback[player] = sent
	end
	local now = os.clock()
	if now - (sent[key] or -math.huge) < HuntFlow.FeedbackCooldown then
		return
	end
	sent[key] = now
	pcall(deps.Feedback, player, text)
	if key == "full" and DriveAndHuntFlags.Part("ScoopFx") then
		player:SetAttribute("DriveAndHuntCargoFullAt", workspace:GetServerTimeNow())
	end
end

local scoopShapes: { [string]: DriveAndHuntRules.ScoopShape } = {}

-- nil keeps the original pivot radius (flag off, or a cart without a geometry profile).
local function scoopShape(cart: Model): DriveAndHuntRules.ScoopShape?
	if not DriveAndHuntFlags.Part("ScoopFx") then
		return nil
	end
	local profile = CartGeometry.Get(cart)
	if not profile then
		return nil
	end
	local shape = scoopShapes[profile.Id]
	if not shape then
		shape = DriveAndHuntRules.ScoopShape(profile.BodySize, DriveAndHunt.Scoop.Reach)
		scoopShapes[profile.Id] = shape
	end
	return shape
end

local function atBase(base: Model, position: Vector3): boolean
	local bounds = baseBounds[base]
	if not bounds then
		local frame, size = base:GetBoundingBox()
		bounds = { Frame = frame, Size = size }
		baseBounds[base] = bounds
	end
	local localPoint = bounds.Frame:PointToObjectSpace(position)
	return math.abs(localPoint.X) <= bounds.Size.X * 0.5 + HuntFlow.BankMargin
		and math.abs(localPoint.Z) <= bounds.Size.Z * 0.5 + HuntFlow.BankMargin
end

local function scoop(player: Player, cart: Model)
	local deps = dependencies :: Dependencies
	local origin = cart:GetPivot().Position
	local radius = HuntFlow.ScoopRadius
	local shape = scoopShape(cart)
	local broad = if shape then shape.HalfLength + shape.Reach else radius
	local full = not deps.Cargo:CanAcceptCargo(cart)
	for _, model in deps.World.GetWorldModels() do
		local offset = model:GetPivot().Position - origin
		if offset.X * offset.X + offset.Z * offset.Z > (broad + 6) * (broad + 6) then
			continue
		end
		local _, state = deps.World.GetWorldRecord(model)
		if state ~= "WorldSleeping" then
			continue
		end
		if full then
			tell(player, "full", "Cargo full - drive home to bank")
			return
		end
		local ok, reason = deps.Interaction.TryScoopIntoCargo(player, cart, model, radius, shape)
		if ok then
			stats.Scooped += 1
			return -- one per tick keeps the cargo transaction strictly serial
		end
		stats.LastScoopReason = tostring(reason)
		if reason == "NO_SPACE" then
			tell(player, "full", "Cargo full - drive home to bank")
			return
		end
	end
end

local function bank(player: Player, cart: Model)
	local deps = dependencies :: Dependencies
	local now = os.clock()
	if now < (nextBankAt[player] or 0) then
		return
	end
	local base = deps.GetBase(player)
	if not base or not atBase(base, cart:GetPivot().Position) then
		return
	end
	local cargo = deps.Cargo:GetCargoSnapshot(cart)
	local item = cargo[1]
	if not item then
		return
	end
	nextBankAt[player] = now + HuntFlow.BankInterval
	local ok, reason = deps.Interaction.TryBankCargoItem(player, cart, item.ItemId)
	if ok then
		stats.Banked += 1
		return
	end
	stats.LastBankReason = tostring(reason)
	if reason == "NO_SPACE" or reason == "STORAGE_FULL" or reason == "NO_FREE_SLOT" or reason == "FULL" then
		tell(player, "basefull", "Base full - sell or expand to bank more")
		nextBankAt[player] = now + 2
	end
end

local function step(dt: number)
	local deps = dependencies
	if not deps then
		return
	end
	elapsed += dt
	if elapsed < 1 / HuntFlow.ScoopHz then
		return
	end
	elapsed = 0
	for _, player in Players:GetPlayers() do
		local cart = deps.GetDrivenCart(player)
		if cart and cart.Parent then
			if HuntFlow.ScoopEnabled then
				local ok, failure = pcall(scoop, player, cart)
				if not ok then
					warn("[DriveByHaul] Scoop error: " .. tostring(failure))
				end
			end
			if HuntFlow.AutoBankEnabled then
				local ok, failure = pcall(bank, player, cart)
				if not ok then
					warn("[DriveByHaul] Bank error: " .. tostring(failure))
				end
			end
		end
	end
end

function System.Start(deps: Dependencies)
	if connection then
		return
	end
	dependencies = deps
	connection = RunService.Heartbeat:Connect(step)
	-- Studio-only automation hook, present only while ServerStorage.DriveByHaulQA is set.
	local ServerStorage = game:GetService("ServerStorage")
	if RunService:IsStudio() and ServerStorage:GetAttribute("DriveByHaulQA") == true then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DriveByHaulQA"
		hook.OnInvoke = function(verb: string, player: Player?)
			if verb == "Stats" then
				return {
					Haul = table.clone(stats),
					Spawner = if deps.World.GetHuntFlowDiagnostics then deps.World.GetHuntFlowDiagnostics() else nil,
				}
			elseif verb == "SleepBesideCart" and player then
				local cart = deps.GetDrivenCart(player)
				if not cart then
					return "NOT_DRIVING"
				end
				local origin = cart:GetPivot()
				local best, bestDistance = nil, math.huge
				for _, model in deps.World.GetWorldModels() do
					local _, state = deps.World.GetWorldRecord(model)
					local distance = (model:GetPivot().Position - origin.Position).Magnitude
					if state == "WorldAwake" and distance < bestDistance then
						best, bestDistance = model, distance
					end
				end
				if not best then
					return "NO_TARGET"
				end
				best:PivotTo(best:GetPivot().Rotation + (origin * CFrame.new(9, 0, 0)).Position)
				local slept, reason = deps.World.TrySleep(best)
				return if slept then "SLEPT:" .. best.Name else "SLEEP_FAILED:" .. tostring(reason)
			elseif verb == "RareWave" then
				return deps.World.BeginRareWave(HuntFlow.RareWaveSeconds)
			end
			return "UNKNOWN_VERB"
		end
		hook.Parent = ServerStorage
	end
end

function System.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	dependencies = nil
end

function System.GetDiagnostics(): any
	return table.clone(stats)
end

return System
