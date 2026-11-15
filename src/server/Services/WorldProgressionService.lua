--!strict
-- Narrow adapter over PlayerDataService. No store, wallet or save loop of its own.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Config.WorldProgression)
local Rules = require(ReplicatedStorage.Shared.Utility.WorldProgressionRules)
local Service = {}
Service.__index = Service

function Service.new(dependencies: any): any
	local self = setmetatable({
		profile = dependencies.Profile,
		context = dependencies.ValidateGateContext,
		now = dependencies.Now or os.clock,
		unixNow = dependencies.UnixNow or os.time,
		operationId = dependencies.OperationId or function() return HttpService:GenerateGUID(false) end,
		onResult = dependencies.OnResult or function() end,
		onEvent = dependencies.OnEvent or function() end,
		operations = {}, lastAttempt = {}, qualifications = {}, rejectedNotices = {}, requirementCounts = {},
	}, Service)
	self.connection = self.profile:SubscribeSaveConfirmed(function(player, savedRevision)
		self:ConfirmRevision(player, savedRevision)
	end)
	return self
end
function Service:InvalidateRequirements(player: Player)
	self.requirementCounts[player]=nil
end
function Service:GetCounts(player: Player,data: any): any
	local cached=self.requirementCounts[player]
	if not cached or cached.proof~=data.WorldProgression.BankedSpecies then
		cached={proof=data.WorldProgression.BankedSpecies,counts=Rules.Count(data)}
		self.requirementCounts[player]=cached
	end
	return cached.counts
end

function Service:Emit(name: string, player: Player, fields: any)
	local receipt = table.clone(fields)
	receipt.userId, receipt.at = player.UserId, self.unixNow()
	-- Observation must never change the outcome of an authoritative mutation.
	pcall(self.onEvent, name, receipt, player)
end

local function rejected(code: string): any
	return {code = code, state = "Rejected"}
end

function Service:GetPersonalAccess(player: Player, regionId: string): boolean
	local definition = Config.ById[regionId]
	if not definition or not self.profile:IsWritable(player) then return false end
	local data = self.profile:GetReadableData(player)
	if not data or data.CurrencyVersion ~= 2 then return false end
	if definition.index <= 1 then return true end
	local operation = self.operations[player]
	-- The coherent in-memory record may be ahead of durable storage. It is not
	-- runtime access until a covering save is confirmed for this exact session.
	if operation and operation.key == definition.key and operation.state ~= "ConfirmedSuccess" then return false end
	return data.WorldProgression.PersonalUnlocks[definition.key] ~= nil
end

-- Population eligibility and replication use the same confirmed-access boundary.
function Service:GetHighestPersonalIndex(player: Player): number?
	local highest = nil
	for _, definition in Config.Ordered do
		if self:GetPersonalAccess(player, definition.regionId) then
			highest = math.max(highest or 0, definition.index)
		end
	end
	return highest
end

function Service:GetSummary(player: Player, contextForRegion: (string) -> any): any
	local data = self.profile:GetReadableData(player)
	if not data then return {ready = false, personalUnlocks = {}, gates = {}} end
	local unlocks, gates = {}, {}
	local counts=self:GetCounts(player,data)
	for _, definition in Config.Ordered do
		if self:GetPersonalAccess(player, definition.regionId) then unlocks[definition.key] = true end
	end
	local visible = {CurrencyVersion = data.CurrencyVersion, Economy = data.Economy,
		WorldProgression = {PersonalUnlocks = unlocks, BankedSpecies = data.WorldProgression.BankedSpecies}}
	for _, definition in Config.Ordered do
		local context = contextForRegion(definition.key)
		local evaluation = Rules.Evaluate(visible, definition.key, context,counts)
		local operation = self.operations[player]
		if operation and operation.key == definition.key and operation.state ~= "ConfirmedSuccess" then
			evaluation.code, evaluation.eligible = "PurchasePending", false
		end
		gates[definition.key] = evaluation
		if definition.index > 1 and unlocks[definition.predecessor] and not unlocks[definition.key]
			and evaluation.wallet and context.operational then
			local observed = self.qualifications[player] or {}
			self.qualifications[player] = observed
			local previous = observed[definition.key] or {}
			if evaluation.bankingSatisfied and not previous.banking then
				previous.banking = true
				self:Emit("BankingRequirementEligible", player, {key=definition.key})
			end
			if evaluation.wallet >= definition.price and not previous.cash then
				previous.cash = true
				self:Emit("CashRequirementEligible", player, {key=definition.key, wallet=evaluation.wallet})
			end
			observed[definition.key] = previous
		end
	end
	-- Only aggregate counts and this player's grants/status leave this service.
	return {ready = self.profile:IsWritable(player), personalUnlocks = unlocks,
		counts = table.clone(counts), gates = gates}
end

function Service:ConfirmRevision(player: Player, savedRevision: number)
	local operation = self.operations[player]
	if not operation or operation.state == "ConfirmedSuccess" or not operation.revision then return end
	if not self.profile:IsCurrentSessionHandle(operation.handle) or savedRevision < operation.revision then return end
	local data = self.profile:GetReadableData(player)
	local grant = data and data.WorldProgression.PersonalUnlocks[operation.key]
	if not grant or grant.transactionId ~= operation.transactionId then return end
	operation.state, operation.code = "ConfirmedSuccess", "Success"
	self:InvalidateRequirements(player)
	self:Emit("GatePurchaseConfirmed", player, {key=operation.key, transactionId=operation.transactionId,
		price=grant.pricePaid, wallet=data.Economy.Balance, revision=operation.revision})
	self.onResult(player, {code = "Success", state = operation.state, key = operation.key,
		requestId = operation.requestId, wallet = data.Economy.Balance})
end

function Service:Request(player: Player, payload: any): any
	local function reject(code)
		local now = self.now()
		if now-(self.rejectedNotices[player] or -math.huge) >= Config.GATE_REQUEST_MIN_INTERVAL_SECONDS then
			self.rejectedNotices[player] = now
			self:Emit("GatePurchaseRejected", player, {code=code})
		end
		return rejected(code)
	end
	if type(payload) ~= "table" then return reject("InvalidRequest") end
	for key in payload do
		if key ~= "regionKey" and key ~= "requestId" then return reject("InvalidRequest") end
	end
	local key, requestId = payload.regionKey, payload.requestId
	if type(key) ~= "string" or #key == 0 or #key > Config.MAX_GATE_REGION_KEY_LENGTH_BYTES
		or type(requestId) ~= "string" or #requestId == 0 or #requestId > Config.MAX_GATE_REQUEST_ID_LENGTH_BYTES then
		return reject("InvalidRequest")
	end
	if not Config.ByKey[key] then return reject("UnknownRegion") end
	local prior = self.operations[player]
	if prior and prior.requestId == requestId then
		if prior.key ~= key then return reject("InvalidRequest") end
		return {code = prior.code, state = prior.state, key = key, requestId = requestId}
	end
	if prior and prior.state ~= "ConfirmedSuccess" then return {code = "PurchasePending", state = prior.state} end
	local now = self.now()
	if self.lastAttempt[player] and now - self.lastAttempt[player] < Config.GATE_REQUEST_MIN_INTERVAL_SECONDS then
		return reject("RateLimited")
	end
	self.lastAttempt[player] = now
	self:Emit("GatePurchaseSubmitted", player, {key=key})
	local context, failure = self.context(player, key)
	if not context then return reject(failure or "CharacterUnavailable") end
	local data = self.profile:GetWritableData(player)
	if not data then return reject("ProfileNotWritable") end
	local evaluation = Rules.Evaluate(data, key, context)
	if not evaluation.eligible then return reject(evaluation.code) end
	local operation = {key = key, requestId = requestId, transactionId = self.operationId(),
		handle = self.profile:GetSessionHandle(player), state = "Validating", code = "PurchasePending"}
	self.operations[player] = operation
	local result = self.profile:CommitMutation(player, function(current)
		-- Proximity, predecessor, proof and wallet can change after the preview.
		local commitContext, commitFailure = self.context(player, key, true)
		if not commitContext then return false, {code = commitFailure or "CharacterUnavailable"} end
		-- CommitMutation has already acquired this session's write authority.
		-- IsWritable deliberately returns false while its mutex is held; that
		-- reentrancy guard must not reject the callback that owns the mutex.
		local serializedContext = table.clone(commitContext)
		serializedContext.writable = true
		local check = Rules.Evaluate(current, key, serializedContext)
		if not check.eligible then return false, {code = check.code} end
		current.Economy.Balance -= check.price
		current.WorldProgression.PersonalUnlocks[key] = {source = "purchase", pricePaid = check.price,
			transactionId = operation.transactionId, purchasedAt = self.unixNow()}
		return true, {code = "PurchasePending"}
	end)
	if not result.ok then
		self.operations[player] = nil
		return reject(result.code or "PersistenceFailure")
	end
	operation.revision, operation.state = result.revision, "PendingCommit"
	self:Emit("GatePurchaseCommitted", player, {key=key, price=Config.ByKey[key].price,
		wallet=self.profile:GetReadableData(player).Economy.Balance, transactionId=operation.transactionId,
		revision=result.revision})
	self:Emit("GatePurchasePending", player, {key=key, transactionId=operation.transactionId})
	-- Save retries and ambiguous outcomes belong to the existing revisioned
	-- profile layer. No guessed refund or successful access is emitted here.
	self.profile:RequestSave(player, "WorldUnlock:" .. key)
	return {code = operation.code, state = operation.state, key = key, requestId = requestId}
end

function Service:RemovePlayer(player: Player)
	self.operations[player], self.lastAttempt[player] = nil, nil
	self.qualifications[player], self.rejectedNotices[player] = nil, nil
	self.requirementCounts[player]=nil
end

function Service:Destroy()
	self.connection:Disconnect()
	table.clear(self.operations)
	table.clear(self.lastAttempt)
	table.clear(self.qualifications) table.clear(self.rejectedNotices)
	table.clear(self.requirementCounts)
end

return Service
