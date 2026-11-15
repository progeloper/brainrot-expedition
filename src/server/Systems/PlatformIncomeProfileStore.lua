--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local log = Logger.new("PlatformIncomeProfileStore")
local MAX_SAFE_INTEGER = 9007199254740991
local PLATFORM_COUNT = 12
local AUTOSAVE_SECONDS = 60

local Store = {}
local sessions: { [Player]: any } = {}
local byUserId: { [number]: Player } = {}
local developmentProfiles: { [number]: any } = {}
local dataStore: any? = nil
local started = false
local lastAutosaveAt = 0

local function finiteNonNegative(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and math.abs(value) < math.huge
end

local function copyProfile(source: any): (any?, string?)
	if source ~= nil and type(source) ~= "table" then return nil, "INVALID_PLATFORM_PROFILE" end
	if source and source.Version ~= nil and source.Version ~= 0 and source.Version ~= 1 then
		return nil, "UNSUPPORTED_PLATFORM_PROFILE_VERSION"
	end
	if source and source.CurrencyVersion ~= nil then return nil, "UNSUPPORTED_LEGACY_CURRENCY_RECORD" end
	local sourceIncome = if source then source.PlatformIncome else nil
	if sourceIncome ~= nil and type(sourceIncome) ~= "table" then return nil, "INVALID_PLATFORM_INCOME" end
	if source and source.Version == 1 and sourceIncome == nil then return nil, "INVALID_PLATFORM_INCOME" end
	local platformIncome = {}
	for platformId = 1, PLATFORM_COUNT do
		local record = if sourceIncome then sourceIncome[platformId] or sourceIncome[tostring(platformId)] else nil
		local exact = 0
		if record ~= nil then
			if type(record) ~= "table" or not finiteNonNegative(record.UnclaimedCashExact) then
				return nil, "INVALID_PLATFORM_CASH"
			end
			exact = record.UnclaimedCashExact
		end
		platformIncome[tostring(platformId)] = {UnclaimedCashExact = exact}
	end
	return { Version = 1, PlatformIncome = platformIncome }, nil
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

function Store:Start(dependencies: any?): boolean
	if started then
		return false
	end
	local deps = dependencies or {}
	if deps.DataStore ~= nil then
		dataStore = deps.DataStore
	elseif Environment.EnableDataSaving then
		dataStore =
			DataStoreService:GetDataStore(Environment.DataStorePrefix .. "_platform_income_v1")
	else
		dataStore = nil
	end
	lastAutosaveAt = deps.Now or 0
	started = true
	return true
end

function Store:Load(player: Player): (boolean, string?)
	local existing = sessions[player]
	if existing and byUserId[player.UserId] == player then
		return true, nil
	end
	if byUserId[player.UserId] ~= nil then
		return false, "SESSION_CONFLICT"
	end
	local raw
	if dataStore == nil then
		raw = developmentProfiles[player.UserId]
	else
		local ok, value = pcall(dataStore.GetAsync, dataStore, keyFor(player.UserId))
		if not ok then
			log:Warn("Platform income load failed for %d: %s", player.UserId, tostring(value))
			return false, "LOAD_FAILED"
		end
		raw = value
	end
	local normalized, reason = copyProfile(raw)
	if not normalized then
		log:Warn("Platform income validation failed for %d: %s", player.UserId, tostring(reason))
		return false, reason
	end
	sessions[player] = { Data = normalized, Dirty = false, Mutation = 0, Saving = false }
	byUserId[player.UserId] = player
	return true, nil
end

function Store:Get(player: Player): any?
	local session = sessions[player]
	if session == nil or byUserId[player.UserId] ~= player then
		return nil
	end
	local normalized = copyProfile(session.Data)
	return normalized
end

function Store:MarkDirty(player: Player, data: any): (boolean, string?)
	local session = sessions[player]
	if session == nil or byUserId[player.UserId] ~= player then
		return false, "PROFILE_NOT_READY"
	end
	local normalized, reason = copyProfile(data)
	if not normalized then return false, reason end
	session.Data = normalized
	session.Mutation += 1
	session.Dirty = true
	return true, nil
end

function Store:Save(player: Player): (boolean, string?)
	local session = sessions[player]
	if session == nil or byUserId[player.UserId] ~= player then
		return false, "PROFILE_NOT_READY"
	end
	if session.Saving then
		return false, "SAVE_BUSY"
	end
	if not session.Dirty then
		return true, nil
	end
	local snapshot, reason = copyProfile(session.Data)
	if not snapshot then return false, reason end
	session.Saving = true
	local mutation = session.Mutation
	local ok, failure
	if dataStore == nil then
		developmentProfiles[player.UserId] = snapshot
		ok = true
	else
		ok, failure = pcall(function()
			dataStore:UpdateAsync(keyFor(player.UserId), function()
				return snapshot
			end)
		end)
	end
	session.Saving = false
	if not ok then
		return false, tostring(failure)
	end
	if session.Mutation == mutation then
		session.Dirty = false
	end
	return true, nil
end

function Store:Autosave(at: number): boolean
	if not started or at - lastAutosaveAt < AUTOSAVE_SECONDS then
		return false
	end
	lastAutosaveAt = at
	local stablePlayers = {}
	for player, session in sessions do
		if session.Dirty and not session.Saving then
			table.insert(stablePlayers, player)
		end
	end
	for _, player in stablePlayers do
		local saved, reason = self:Save(player)
		if not saved then
			log:Warn("Platform income autosave failed for %d: %s", player.UserId, tostring(reason))
		end
	end
	return true
end

function Store:Release(player: Player): (boolean, string?)
	local session = sessions[player]
	if session == nil or byUserId[player.UserId] ~= player then
		return false, "PROFILE_NOT_READY"
	end
	local saved, reason = self:Save(player)
	if not saved then
		log:Warn("Final platform income save failed for %d: %s", player.UserId, tostring(reason))
	end
	sessions[player] = nil
	byUserId[player.UserId] = nil
	return saved, reason
end

function Store:Stop(): boolean
	started = false
	dataStore = nil
	lastAutosaveAt = 0
	table.clear(sessions)
	table.clear(byUserId)
	return true
end

return Store
