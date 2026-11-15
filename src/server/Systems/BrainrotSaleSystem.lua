--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InteractionConfig = require(ReplicatedStorage.Shared.Config.BrainrotInteraction)
local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local Phase10 = require(ReplicatedStorage.Shared.Config.Phase10)
local Phase12Rules = require(ReplicatedStorage.Shared.Utility.Phase12Rules)
local Phase12Progress = require(script.Parent.Parent.Data.Phase12Progress)

local PREVIEW_LIFETIME_SECONDS = 20
-- Bulk sale of banked brainrots at the Sell stall: one request sells at most a full base.
local MAX_BATCH = 48
local MAX_ID_LENGTH = 128

type Dependencies = {
	Carry: any,
	Currency: any,
	Catalog: any,
	Banked: any?,
	-- BaseStorageSystem: the platform records and the exact-slot removal used by the carry pickup.
	Storage: any?,
	ResolveSalePoint: (() -> BasePart?)?,
	Now: (() -> number)?,
	GenerateSessionId: (() -> string)?,
	ActionValidator: ((Player) -> (boolean, string?))?,
	Feedback: ((Player, string) -> ())?,
	SessionClosingSignal: any?,
	BaseReleasingSignal: any?,
}

type SaleSession = {
	SessionId: string,
	IndividualId: string,
	CatalogueId: string,
	DisplayName: string,
	Rank: string,
	SellValue: number,
	MutationId: string,
	CreatedAt: number,
}

local BrainrotSaleSystem = {}
local dependencies: Dependencies? = nil
local started = false
local pendingSales: { [Player]: SaleSession } = {}
local saleInProgress: { [Player]: boolean } = {}
local warnedInvalidCatalogueIds: { [string]: boolean } = {}
local connections: { any } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local openRemote: RemoteEvent? = nil
local confirmRemote: RemoteFunction? = nil
local cancelRemote: RemoteEvent? = nil
local confirmHandler: ((Player, any) -> any)? = nil
local committedListeners: { [any]: (Player, any) -> () } = {}
local committedSequence = 0

local function notifyCommitted(player: Player, receipt: any)
	committedSequence += 1
	local session = PlayerDataService:GetSessionHandle(player)
	receipt.sessionGeneration = if session then session.Generation else nil
	receipt.stream = "Sale"
	receipt.operationSequence = committedSequence
	local immutable = table.freeze(receipt)
	for _, callback in committedListeners do
		local ok, observerFailure = pcall(callback, player, immutable)
		if not ok then
			warn("[BrainrotSaleSystem] Observer failed: " .. tostring(observerFailure))
		end
	end
end

function BrainrotSaleSystem.SubscribeCommitted(callback: (Player, any) -> ()): any
	local connection = {}
	committedListeners[connection] = callback
	function connection.Disconnect()
		committedListeners[connection] = nil
	end
	return connection
end

local function failure(code: string): any
	return { ok = false, code = code }
end

local function rejectionFeedback(player: Player, reason: string?)
	local deps = dependencies
	if not Phase10.Enabled or not deps or not deps.Feedback then return end
	if reason == "BankFirst" or reason == "BANK_FIRST" then deps.Feedback(player, "Bank this brainrot on a platform before selling it.")
	elseif reason == "Favourite" or reason == "FAVOURITE" then deps.Feedback(player, "This brainrot is a favourite. Unstar it to sell it.")
	elseif reason == "Dazed" or reason == "DAZED" then deps.Feedback(player, "Wait until your daze ends.") end
end

local function disconnectList(list: { any })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function disconnectAll()
	disconnectList(connections)
	for player, list in playerConnections do
		disconnectList(list)
		playerConnections[player] = nil
	end
end

local function now(): number
	local deps = dependencies :: Dependencies
	return if deps.Now then deps.Now() else Workspace:GetServerTimeNow()
end

local function resolveConfiguredSalePoint(): BasePart?
	local map = Workspace:FindFirstChild("MapBlockout")
	local patches = if map then map:FindFirstChild("ServiceStallPatches") else nil
	local sellStall = if patches then patches:FindFirstChild("SellStall") else nil
	return if sellStall and sellStall:IsA("BasePart") then sellStall else nil
end

local function getSalePoint(): BasePart?
	local deps = dependencies :: Dependencies
	local point = if deps.ResolveSalePoint
		then deps.ResolveSalePoint()
		else resolveConfiguredSalePoint()
	return if point and point:IsDescendantOf(Workspace) then point else nil
end

local function finitePosition(position: Vector3): boolean
	return position.X == position.X
		and math.abs(position.X) < math.huge
		and position.Y == position.Y
		and math.abs(position.Y) < math.huge
		and position.Z == position.Z
		and math.abs(position.Z) < math.huge
end

local function resolvePlayerContext(player: Player): (any?, string?)
	local deps = dependencies :: Dependencies
	if Phase10.Enabled and deps.ActionValidator then
		local allowed, actionReason = deps.ActionValidator(player)
		if not allowed then return nil, actionReason or "Dazed" end
	end
	if player.Parent ~= Players or not deps.Currency:IsReady(player) then
		return nil, "InvalidSession"
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if
		not character
		or not character:IsDescendantOf(Workspace)
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
		or not finitePosition(root.Position)
	then
		return nil, "InvalidSession"
	end
	return { Character = character, Root = root }, nil
end

local function resolveCarriedForContext(player: Player, context: any): (any?, string?)
	local deps = dependencies :: Dependencies
	local state = deps.Carry.GetCarriedState(player)
	if state == nil or state.Record == nil then
		return nil, "NothingCarried"
	end
	if state.CarrierUserId ~= player.UserId then
		return nil, "NotOwner"
	end
	if state.Character ~= context.Character or state.Root ~= context.Root then
		return nil, "NothingCarried"
	end
	if state.Busy or state.Returning then
		return nil, "Busy"
	end
	local record = state.Record
	if type(record.ItemId) ~= "string" or record.ItemId == "" then
		return nil, "NothingCarried"
	end
	if type(record.BrainrotId) ~= "string" or record.BrainrotId == "" then
		return nil, "InvalidCatalogue"
	end
	do
		if not deps.Banked or type(deps.Banked.ValidateSaleRecord) ~= "function" then
			return nil, "BankFirst"
		end
		local eligible, bankReason = deps.Banked:ValidateSaleRecord(player, record)
		if not eligible then
			return nil, if bankReason == "BANK_FIRST" then "BankFirst"
				elseif bankReason == "FAVOURITE" then "Favourite"
				else bankReason
		end
	end
	return {
		Record = record,
		IndividualId = record.ItemId,
		CatalogueId = record.BrainrotId,
		CarrierUserId = state.CarrierUserId,
	},
		nil
end

local function resolveEligibleCarriedBrainrot(player: Player): (any?, string?)
	local context, reason = resolvePlayerContext(player)
	if not context then
		return nil, reason
	end
	local carried, carriedReason = resolveCarriedForContext(player, context)
	if not carried then
		return nil, carriedReason
	end
	carried.Context = context
	return carried, nil
end

local function warnInvalidCatalogue(catalogueId: any, reason: string)
	local key = tostring(catalogueId)
	if warnedInvalidCatalogueIds[key] then
		return
	end
	warnedInvalidCatalogueIds[key] = true
	warn("[BrainrotSaleSystem] Invalid sale catalogue " .. key .. ": " .. reason)
end

local function resolveCatalogueSaleData(carriedRecord: any): (any?, string?)
	local deps = dependencies :: Dependencies
	local definition, reason = deps.Catalog.GetDefinition(carriedRecord.BrainrotId)
	if not definition then
		warnInvalidCatalogue(carriedRecord.BrainrotId, tostring(reason or "missing definition"))
		return nil, "InvalidCatalogue"
	end
	local displayName = definition.displayName
	local rank = definition.tier
	local sellValue = definition.sellValue
	if type(displayName) ~= "string" or not displayName:match("%S") then
		warnInvalidCatalogue(carriedRecord.BrainrotId, "missing display name")
		return nil, "InvalidCatalogue"
	end
	if type(rank) ~= "string" or not rank:match("%S") then
		warnInvalidCatalogue(carriedRecord.BrainrotId, "missing tier")
		return nil, "InvalidCatalogue"
	end
	if
		type(sellValue) ~= "number"
		or sellValue ~= sellValue
		or math.abs(sellValue) == math.huge
		or sellValue < 0
	then
		warnInvalidCatalogue(carriedRecord.BrainrotId, "invalid finite non-negative sellValue")
		return nil, "InvalidCatalogue"
	end
	local mutationId = Phase12Progress.MutationId(carriedRecord)
	local effectiveValue = sellValue * Phase12Rules.MutationMultiplier(mutationId)
	if effectiveValue == math.huge or effectiveValue > 9007199254740991 then return nil, "InvalidCatalogue" end
	return {
		DisplayName = displayName,
		Rank = rank,
		MutationId = mutationId,
		SellValue = effectiveValue,
	}, nil
end

local function isPlayerWithinSaleRange(context: any): boolean
	local salePoint = getSalePoint()
	if not salePoint then
		return false
	end
	local localPosition = salePoint.CFrame:PointToObjectSpace(context.Root.Position)
	local halfSize = salePoint.Size * 0.5
	local closestLocal = Vector3.new(
		math.clamp(localPosition.X, -halfSize.X, halfSize.X),
		math.clamp(localPosition.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorld = salePoint.CFrame:PointToWorldSpace(closestLocal)
	return (context.Root.Position - closestWorld).Magnitude
		<= InteractionConfig.SELL_INTERACTION_DISTANCE
			+ InteractionConfig.SELL_SERVER_DISTANCE_TOLERANCE
end

local function clearSaleSession(player: Player)
	pendingSales[player] = nil
end

function BrainrotSaleSystem:Init(deps: Dependencies)
	assert(not started, "Cannot replace BrainrotSaleSystem dependencies after Start")
	assert(deps and deps.Carry and deps.Currency and deps.Catalog, "Missing sale dependencies")
	dependencies = deps
end

function BrainrotSaleSystem:CancelPendingSale(player: Player, saleSessionId: any?): boolean
	local session = pendingSales[player]
	if session == nil then
		return false
	end
	if saleSessionId ~= nil and saleSessionId ~= session.SessionId then
		return false
	end
	if saleInProgress[player] then
		return false
	end
	clearSaleSession(player)
	return true
end

function BrainrotSaleSystem:CreatePreview(player: Player): (any?, string?)
	clearSaleSession(player)
	if not dependencies then
		return nil, "InvalidSession"
	end
	local carried, reason = resolveEligibleCarriedBrainrot(player)
	if not carried then
		rejectionFeedback(player, reason)
		return nil, reason
	end
	if not isPlayerWithinSaleRange(carried.Context) then
		return nil, "TooFarAway"
	end
	local saleData
	saleData, reason = resolveCatalogueSaleData(carried.Record)
	if not saleData then
		return nil, reason
	end
	local deps = dependencies :: Dependencies
	local createdAt = now()
	local sessionId = if deps.GenerateSessionId
		then deps.GenerateSessionId()
		else HttpService:GenerateGUID(false)
	local session: SaleSession = {
		SessionId = sessionId,
		IndividualId = carried.IndividualId,
		CatalogueId = carried.CatalogueId,
		DisplayName = saleData.DisplayName,
		Rank = saleData.Rank,
		SellValue = saleData.SellValue,
		MutationId = saleData.MutationId,
		CreatedAt = createdAt,
	}
	pendingSales[player] = session
	local preview = {
		SaleSessionId = session.SessionId,
		RuntimeBrainrotId = session.IndividualId,
		SpeciesId = session.CatalogueId,
		DisplayName = session.DisplayName,
		Rarity = session.Rank,
		Rank = session.Rank,
		SellValue = session.SellValue,
		MutationId = session.MutationId,
		ExpiresAtServerTime = session.CreatedAt + PREVIEW_LIFETIME_SECONDS,
		TrainAvailable = false,
		MutationAvailable = false,
	}
	if openRemote then
		openRemote:FireClient(player, preview)
	end
	return preview, nil
end

local function matchesPreview(session: SaleSession, carried: any, saleData: any): boolean
	return carried.IndividualId == session.IndividualId
		and carried.CatalogueId == session.CatalogueId
		and saleData.DisplayName == session.DisplayName
		and saleData.Rank == session.Rank
		and saleData.SellValue == session.SellValue
		and saleData.MutationId == session.MutationId
end

function BrainrotSaleSystem:ConfirmSale(player: Player, saleSessionId: any): any
	if not dependencies then
		return failure("InvalidSession")
	end
	if type(saleSessionId) ~= "string" or saleSessionId == "" then
		return failure("InvalidSession")
	end
	local session = pendingSales[player]
	if not session or session.SessionId ~= saleSessionId then
		return failure("InvalidSession")
	end
	if now() - session.CreatedAt >= PREVIEW_LIFETIME_SECONDS then
		clearSaleSession(player)
		return failure("PreviewExpired")
	end
	if saleInProgress[player] then
		return failure("Busy")
	end
	local context, reason = resolvePlayerContext(player)
	if not context then
		return failure(reason or "InvalidSession")
	end
	if not isPlayerWithinSaleRange(context) then
		return failure("TooFarAway")
	end
	local carried
	carried, reason = resolveCarriedForContext(player, context)
	if not carried then
		rejectionFeedback(player, reason)
		return failure(reason or "NothingCarried")
	end
	if carried.IndividualId ~= session.IndividualId then
		return failure("NothingCarried")
	end
	if carried.CatalogueId ~= session.CatalogueId then
		return failure("PreviewChanged")
	end
	local saleData
	saleData, reason = resolveCatalogueSaleData(carried.Record)
	if not saleData then
		return failure(reason or "InvalidCatalogue")
	end
	if not matchesPreview(session, carried, saleData) then
		clearSaleSession(player)
		return failure("PreviewChanged")
	end

	saleInProgress[player] = true
	local result = failure("ConsumeFailed")
	local committedAward: any = nil
	local ok, caught = xpcall(function()
		-- Lock first, then repeat current-character, distance, exact individual,
		-- ownership and catalogue checks before entering the non-yielding commit.
		local lockedContext, lockedReason = resolvePlayerContext(player)
		if not lockedContext then
			result = failure(lockedReason or "InvalidSession")
			return
		end
		if not isPlayerWithinSaleRange(lockedContext) then
			result = failure("TooFarAway")
			return
		end
		local lockedCarried
		lockedCarried, lockedReason = resolveCarriedForContext(player, lockedContext)
		if not lockedCarried then
			result = failure(lockedReason or "NothingCarried")
			return
		end
		local lockedData
		lockedData, lockedReason = resolveCatalogueSaleData(lockedCarried.Record)
		if not lockedData then
			result = failure(lockedReason or "InvalidCatalogue")
			return
		end
		if not matchesPreview(session, lockedCarried, lockedData) then
			clearSaleSession(player)
			result = failure("PreviewChanged")
			return
		end

		local awardFailed = false
		local consumed, consumeReason = (dependencies :: Dependencies).Carry.ConsumeCarriedBrainrot(
			player,
			session.IndividualId,
			"BrainrotSale",
			function(record)
				if
					record ~= lockedCarried.Record
					or record.ItemId ~= session.IndividualId
					or record.BrainrotId ~= session.CatalogueId
				then
					return false, "SOURCE_CHANGED"
				end
				local deps = dependencies :: Dependencies
				do
					local eligible, bankReason = deps.Banked:ValidateSaleRecord(player, record)
					if not eligible then return false, bankReason or "BANK_FIRST" end
				end
				local called, award
				if deps.Banked then
					called, award = pcall(
						deps.Banked.TryCommitSale,
						deps.Banked,
						player,
						record,
						lockedData.SellValue,
						true,
						deps.Catalog
					)
				elseif lockedData.SellValue == 0 then
					return true, nil
				else
					called, award = pcall(
						deps.Currency.AddCash,
						deps.Currency,
						player,
						lockedData.SellValue,
						"BrainrotSale"
					)
				end
				if not called or type(award) ~= "table" or award.committed ~= true then
					awardFailed = true
					return false, "AWARD_FAILED"
				end
				committedAward = award
				return true, nil
			end
		)
		if not consumed then
			result = failure(if awardFailed then "AwardFailed" else "ConsumeFailed")
			if consumeReason == "BUSY" then
				result = failure("Busy")
			elseif consumeReason == "BANK_FIRST" then
				result = failure("BankFirst")
			elseif consumeReason == "FAVOURITE" then
				result = failure("Favourite")
			end
			return
		end
		clearSaleSession(player)
		local currency = (dependencies :: Dependencies).Currency
		if currency.SyncBalance then
			pcall(currency.SyncBalance, currency, player)
		end
		result = {
			ok = true,
			code = "Sold",
			DisplayName = lockedData.DisplayName,
			Paid = lockedData.SellValue,
		}
		if committedAward and type(committedAward.revision) == "number" then
			local committedAt = now()
			notifyCommitted(player, {
				kind = "BrainrotSold",
				eventId = "sale:" .. session.SessionId,
				at = committedAt,
				individualId = session.IndividualId,
				speciesId = session.CatalogueId,
				amount = lockedData.SellValue,
				revision = committedAward.revision,
			})
		end
	end, debug.traceback)
	saleInProgress[player] = nil
	if not ok then
		warn("[BrainrotSaleSystem] Transaction error: " .. tostring(caught))
		return failure("AwardFailed")
	end
	if result.ok ~= true then rejectionFeedback(player, result.code) end
	return result
end

------------------------------------------------------------------ banked (platform) sales
-- A banked brainrot is sold from its platform without being carried. Nothing new is written here:
-- each item goes through the two existing server steps of a carried sale, in one non-yielding pass:
--   1. BaseStorageSystem:TryRemoveFromPlatform  (the carry pickup's exact-slot removal; settles income)
--   2. BankedBrainrotService:TryCommitSale      (consumes ownership and credits the wallet together)
-- If step 2 refuses, the individual goes straight back onto a free platform and nothing is paid.

local function teamAssignments(player: Player): { [string]: boolean }
	local onTeam = {}
	local ok, data = pcall(PlayerDataService.GetReadableData, PlayerDataService, player)
	local team = if ok and type(data) == "table" then data.ChariotTeam else nil
	local assignments = if type(team) == "table" then team.Assignments else nil
	if type(assignments) == "table" then
		for _, id in assignments do
			if type(id) == "string" then
				onTeam[id] = true
			end
		end
	end
	return onTeam
end

local function bankedStorage(player: Player): (any?, string?)
	local deps = dependencies
	if not deps or not deps.Storage or not deps.Banked then
		return nil, "Unavailable"
	end
	local storage = deps.Storage:GetStorageForPlayer(player)
	if not storage then
		return nil, "NotReady"
	end
	return storage, nil
end

-- Read-only: every brainrot standing on the player's own platforms, with the authoritative sale value.
function BrainrotSaleSystem:ListBanked(player: Player): any
	local storage, reason = bankedStorage(player)
	if not storage then
		return failure(reason or "NotReady")
	end
	local deps = dependencies :: Dependencies
	local onTeam = teamAssignments(player)
	local rows = {}
	for _, record in storage:GetSnapshot() do
		local saleData = resolveCatalogueSaleData(record)
		if saleData then
			table.insert(rows, {
				id = record.ItemId,
				speciesId = record.BrainrotId,
				displayName = saleData.DisplayName,
				tier = saleData.Rank,
				mutationId = saleData.MutationId,
				sellValue = saleData.SellValue,
				slot = record.SlotIndex,
				team = onTeam[record.ItemId] == true,
				favourite = deps.Banked.IsFavourite ~= nil and deps.Banked:IsFavourite(player, record.ItemId) == true,
				saving = deps.Banked.IsBankPending ~= nil and deps.Banked:IsBankPending(player, record.ItemId) == true,
			})
		end
	end
	return { ok = true, rows = rows, max = MAX_BATCH }
end

local function restoreToPlatform(player: Player, record: any)
	local deps = dependencies :: Dependencies
	local returned = deps.Banked:ReturnOwnedToAvailableSlot(player, record)
	local slotId = if type(returned) == "table" then returned.slotId else nil
	if type(slotId) ~= "string" then
		warn("[BrainrotSaleSystem] Unsold brainrot could not return to a platform: "
			.. tostring(if type(returned) == "table" then returned.code else returned))
		return
	end
	local bound, bindReason = deps.Storage:BindReturnedOwnedIndividual(player, slotId, record.ItemId)
	if not bound and bindReason ~= "ALREADY_BOUND" then
		warn("[BrainrotSaleSystem] Unsold brainrot was not rebound to its platform: " .. tostring(bindReason))
	end
end

-- `ids`: array of the player's own platform individuals. `expectedTotal`: the total the player was
-- shown; a different authoritative total sells nothing (QuoteChanged). All ids are validated before
-- anything changes; a refusal while executing stops the batch and reports what was already sold.
function BrainrotSaleSystem:SellBanked(player: Player, ids: any, expectedTotal: any): any
	if not dependencies then
		return failure("InvalidSession")
	end
	if
		type(ids) ~= "table"
		or type(expectedTotal) ~= "number"
		or expectedTotal ~= expectedTotal
		or expectedTotal < 0
		or expectedTotal == math.huge
	then
		return failure("InvalidRequest")
	end
	local count = 0
	for key in ids do
		if type(key) ~= "number" then
			return failure("InvalidRequest")
		end
		count += 1
		if count > MAX_BATCH then
			return failure("InvalidRequest")
		end
	end
	if count == 0 or count ~= #ids then
		return failure("InvalidRequest")
	end
	local seen = {}
	for index = 1, count do
		local id = ids[index]
		if type(id) ~= "string" or id == "" or #id > MAX_ID_LENGTH or seen[id] then
			return failure("InvalidRequest")
		end
		seen[id] = true
	end
	if saleInProgress[player] then
		return failure("Busy")
	end
	local context, reason = resolvePlayerContext(player)
	if not context then
		rejectionFeedback(player, reason)
		return failure(reason or "InvalidSession")
	end
	if not isPlayerWithinSaleRange(context) then
		return failure("TooFarAway")
	end
	local storage
	storage, reason = bankedStorage(player)
	if not storage then
		return failure(reason or "NotReady")
	end
	local deps = dependencies :: Dependencies
	local platforms = deps.Storage:GetRegisteredPlatforms(storage.Base)
	if type(platforms) ~= "table" then
		return failure("NotReady")
	end
	local platformByIndex = {}
	for _, slot in platforms do
		platformByIndex[slot.Index] = slot.Platform
	end
	local recordById = {}
	for _, record in storage:GetSnapshot() do
		recordById[record.ItemId] = record
	end
	local plan, total = {}, 0
	for index = 1, count do
		local record = recordById[ids[index]]
		local platform = if record then platformByIndex[record.SlotIndex] else nil
		if not record or not platform then
			return failure("NotOnPlatform")
		end
		if deps.Banked.IsBankPending and deps.Banked:IsBankPending(player, record.ItemId) then
			return failure("BankSavePending")
		end
		-- A favourite refuses the whole batch before anything changes (TryCommitSale refuses it too).
		if deps.Banked.IsFavourite and deps.Banked:IsFavourite(player, record.ItemId) then
			return failure("Favourite")
		end
		local saleData
		saleData, reason = resolveCatalogueSaleData(record)
		if not saleData then
			return failure(reason or "InvalidCatalogue")
		end
		total += saleData.SellValue
		plan[index] = {
			IndividualId = record.ItemId,
			CatalogueId = record.BrainrotId,
			Platform = platform,
			SellValue = saleData.SellValue,
		}
	end
	if math.abs(total - expectedTotal) > math.max(1e-9 * total, 1e-6) then
		return failure("QuoteChanged")
	end

	saleInProgress[player] = true
	local batchId = if deps.GenerateSessionId then deps.GenerateSessionId() else HttpService:GenerateGUID(false)
	local sold, paid, soldIds = 0, 0, {}
	local stoppedBy: string? = nil
	local inFlight: any = nil
	local ok, caught = xpcall(function()
		for index, step in plan do
			local removed, removeReason = deps.Storage:TryRemoveFromPlatform(player, step.Platform, step.IndividualId)
			if not removed then
				stoppedBy = removeReason or "ConsumeFailed"
				return
			end
			inFlight = removed
			local called, award =
				pcall(deps.Banked.TryCommitSale, deps.Banked, player, removed, step.SellValue, true, deps.Catalog)
			if not called or type(award) ~= "table" or award.committed ~= true then
				inFlight = nil
				restoreToPlatform(player, removed)
				stoppedBy = if called and type(award) == "table" and type(award.code) == "string"
					then award.code
					else "AwardFailed"
				return
			end
			inFlight = nil
			sold += 1
			paid += step.SellValue
			table.insert(soldIds, step.IndividualId)
			if type(award.revision) == "number" then
				notifyCommitted(player, {
					kind = "BrainrotSold",
					eventId = "sale:" .. batchId .. ":" .. index,
					at = now(),
					individualId = step.IndividualId,
					speciesId = step.CatalogueId,
					amount = step.SellValue,
					revision = award.revision,
				})
			end
		end
	end, debug.traceback)
	if not ok then
		warn("[BrainrotSaleSystem] Banked sale error: " .. tostring(caught))
		stoppedBy = stoppedBy or "AwardFailed"
		if inFlight then
			-- Removed from its platform but not sold: it is still owned, so put it back.
			local restored, restoreError = pcall(restoreToPlatform, player, inFlight)
			if not restored then
				warn("[BrainrotSaleSystem] Banked sale recovery failed: " .. tostring(restoreError))
			end
		end
	end
	saleInProgress[player] = nil
	if sold > 0 and deps.Currency.SyncBalance then
		pcall(deps.Currency.SyncBalance, deps.Currency, player)
	end
	if sold == 0 then
		return failure(stoppedBy or "ConsumeFailed")
	end
	return {
		ok = true,
		code = if sold == count then "Sold" else "PartlySold",
		sold = sold,
		requested = count,
		paid = paid,
		soldIds = soldIds,
		stoppedBy = stoppedBy,
	}
end

local function ensureRemote(className: string, remoteName: string): Instance
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name, remotes.Parent = "Remotes", ReplicatedStorage
	end
	local remote = remotes:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new(className)
		remote.Name, remote.Parent = remoteName, remotes
	end
	assert(remote.ClassName == className, remoteName .. " must be a " .. className)
	return remote
end

local function bindPlayer(player: Player)
	if playerConnections[player] then
		return
	end
	local list = {}
	playerConnections[player] = list
	table.insert(
		list,
		player.CharacterAdded:Connect(function()
			BrainrotSaleSystem:CancelPendingSale(player)
		end)
	)
	table.insert(
		list,
		player.CharacterRemoving:Connect(function()
			BrainrotSaleSystem:CancelPendingSale(player)
		end)
	)
end

function BrainrotSaleSystem:Start()
	if started then
		return
	end
	assert(dependencies, "BrainrotSaleSystem:Init must run before Start")
	started = true
	openRemote = ensureRemote("RemoteEvent", RemoteNames.OpenBrainrotSaleDialog) :: RemoteEvent
	confirmRemote =
		ensureRemote("RemoteFunction", RemoteNames.ConfirmBrainrotSale) :: RemoteFunction
	cancelRemote = ensureRemote("RemoteEvent", RemoteNames.CancelBrainrotSale) :: RemoteEvent
	confirmHandler = function(player, saleSessionId)
		return BrainrotSaleSystem:ConfirmSale(player, saleSessionId)
	end
	confirmRemote.OnServerInvoke = confirmHandler
	table.insert(
		connections,
		(cancelRemote :: RemoteEvent).OnServerEvent:Connect(function(player, saleSessionId)
			BrainrotSaleSystem:CancelPendingSale(player, saleSessionId)
		end)
	)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(bindPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			BrainrotSaleSystem:CancelPendingSale(player)
			local list = playerConnections[player]
			if list then
				disconnectList(list)
				playerConnections[player] = nil
			end
		end)
	)
	local sessionClosingSignal = (dependencies :: Dependencies).SessionClosingSignal
	if sessionClosingSignal then
		table.insert(
			connections,
			sessionClosingSignal(function(player)
				BrainrotSaleSystem:CancelPendingSale(player)
			end)
		)
	end
	local baseReleasingSignal = (dependencies :: Dependencies).BaseReleasingSignal
	if baseReleasingSignal then
		table.insert(
			connections,
			baseReleasingSignal(function(player)
				BrainrotSaleSystem:CancelPendingSale(player)
			end)
		)
	end
end

function BrainrotSaleSystem:Stop()
	if confirmRemote and confirmRemote.OnServerInvoke == confirmHandler then
		confirmRemote.OnServerInvoke = nil
	end
	disconnectAll()
	table.clear(pendingSales)
	table.clear(saleInProgress)
	table.clear(warnedInvalidCatalogueIds)
	openRemote, confirmRemote, cancelRemote, confirmHandler = nil, nil, nil, nil
	started = false
	dependencies = nil
end

return BrainrotSaleSystem
