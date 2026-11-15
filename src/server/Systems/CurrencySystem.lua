--!strict
-- The player profile is authoritative. Cash is a presentation mirror only.

local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local PlayerDataConfig = require(script.Parent.Parent.Config.PlayerDataConfig)

local Currency = {}
local profileOwner: any = PlayerDataService
local committedListeners: { [any]: (Player, any) -> () } = {}
local committedSequence = 0
local now = function(): number
	return workspace:GetServerTimeNow()
end

local function notifyCommitted(player: Player, receipt: any)
	committedSequence += 1
	local session = if profileOwner.GetSessionHandle then profileOwner:GetSessionHandle(player) else nil
	receipt.sessionGeneration = if session then session.Generation else nil
	receipt.stream = "Currency"
	receipt.operationSequence = committedSequence
	local immutable = table.freeze(receipt)
	for _, callback in committedListeners do
		local ok, failure = pcall(callback, player, immutable)
		if not ok then
			warn("[CurrencySystem] Committed-operation observer failed: " .. tostring(failure))
		end
	end
end

local function finiteNonNegative(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= PlayerDataConfig.MaxBalance
		and math.abs(value) < math.huge
end

local function rejected(code: string): any
	return { ok = false, committed = false, code = code }
end

-- Trusted server-only calculation boundary for coherent multi-field profile
-- mutations. This validates wallet arithmetic without changing the profile;
-- the caller must commit the returned balance in the same non-yielding profile
-- mutation as its associated domain change.
function Currency:PrepareSpend(profileData: any, cost: number): any
	if not finiteNonNegative(cost) then
		return rejected("INVALID_COST")
	end
	if type(profileData) ~= "table" or type(profileData.Economy) ~= "table" then
		return rejected("INVALID_BALANCE")
	end
	local balance = profileData.Economy.Balance
	if not finiteNonNegative(balance) then
		return rejected("INVALID_BALANCE")
	end
	if balance < cost then
		return rejected("INSUFFICIENT_FUNDS")
	end
	local nextBalance = balance - cost
	if not finiteNonNegative(nextBalance) then
		return rejected("INVALID_BALANCE")
	end
	return {
		ok = true,
		committed = false,
		code = if cost == 0 then "Unchanged" else "Prepared",
		balanceBefore = balance,
		balance = nextBalance,
	}
end

function Currency:Init(owner: any): boolean
	if owner == nil then
		return false
	end
	profileOwner = owner
	return true
end

function Currency:OpenAccount(player: Player): boolean
	-- Compatibility boundary for existing callers. A currency account can no
	-- longer manufacture a writable zero-balance profile.
	return self:IsReady(player)
end

function Currency:IsReady(player: Player): boolean
	return profileOwner:IsWritable(player)
end

function Currency:GetBalance(player: Player): (number?, string?)
	local data, reason = profileOwner:GetReadableData(player)
	if not data then
		return nil, reason or "ACCOUNT_UNAVAILABLE"
	end
	local balance = data.Economy and data.Economy.Balance
	return if finiteNonNegative(balance) then balance else nil,
		if finiteNonNegative(balance) then nil else "INVALID_BALANCE"
end

function Currency:CanAfford(player: Player, cost: number): boolean
	if not finiteNonNegative(cost) or not profileOwner:IsWritable(player) then
		return false
	end
	local balance = self:GetBalance(player)
	return balance ~= nil and balance >= cost
end

function Currency:CanCredit(player: Player, amount: number): (boolean, string?)
	if not finiteNonNegative(amount) or amount <= 0 then
		return false, "INVALID_CREDIT"
	end
	local data, unavailableReason = profileOwner:GetWritableData(player)
	if not data then
		return false, unavailableReason or "ACCOUNT_UNAVAILABLE"
	end
	local balance = data.Economy and data.Economy.Balance
	if not finiteNonNegative(balance) then
		return false, "INVALID_BALANCE"
	end
	if balance > PlayerDataConfig.MaxBalance - amount then
		return false, "BALANCE_OVERFLOW"
	end
	return true, nil
end

function Currency:TryCredit(player: Player, amount: number, reason: string): any
	return self:TryCreditWithSource(player, amount, reason, nil)
end

-- Internal coherent-source variant used by platform collection and persistent
-- sales. The source callback validates and consumes profile-owned state in the
-- same non-yielding profile revision as the wallet credit.
function Currency:TryCreditWithSource(
	player: Player,
	amount: number,
	reason: string,
	consumeSource: ((any) -> (boolean, string?))?,
	settlementProof: any?
): any
	if not finiteNonNegative(amount) or amount <= 0 or type(reason) ~= "string" or reason == "" then
		return rejected("INVALID_CREDIT")
	end
	if consumeSource ~= nil and type(consumeSource) ~= "function" then
		return rejected("INVALID_SOURCE_MUTATION")
	end
	if profileOwner.CommitMutation then
		local balanceBefore: number? = nil
		local result = profileOwner:CommitMutation(player, function(data)
			local balance = data.Economy and data.Economy.Balance
			if not finiteNonNegative(balance) then
				return false, rejected("INVALID_BALANCE")
			end
			balanceBefore = balance
			if balance > PlayerDataConfig.MaxBalance - amount then
				return false, rejected("BALANCE_OVERFLOW")
			end
			if consumeSource then
				local consumed, sourceReason = consumeSource(data)
				if not consumed then
					return false, rejected(sourceReason or "SOURCE_CHANGED")
				end
			end
			local nextBalance = balance + amount
			data.Economy.Balance = nextBalance
			local retention
			-- Only the validated own-platform domain boundary supplies this proof.
			-- Ordinary credits (sales, refunds, Starter, admin and rewards) never qualify.
			if
				reason == "PlatformIncomeClaim"
				and consumeSource
				and type(settlementProof) == "table"
				and settlementProof.ownerUserId == player.UserId
				and settlementProof.earnings == amount
			then
				retention =
					require(game:GetService("ReplicatedStorage").Shared.Utility.RetentionRules).RecordPlatformSettlement(
						data,
						settlementProof
					)
			end
			return true,
				{
					ok = true,
					committed = true,
					code = "Applied",
					balance = data.Economy.Balance,
					retention = retention,
				}
		end)
		if type(result) == "table" and result.committed == true then
			notifyCommitted(player, {
				kind = "WalletCredit",
				eventId = tostring(result.revision or "none") .. ":credit:" .. reason,
				at = now(),
				amount = amount,
				source = reason,
				balanceBefore = balanceBefore,
				balanceAfter = result.balance,
				revision = result.revision,
				retention = result.retention,
			})
		end
		return result
	end
	local data, unavailableReason = profileOwner:GetWritableData(player)
	if not data then
		return rejected(unavailableReason or "ACCOUNT_UNAVAILABLE")
	end
	local balance = data.Economy and data.Economy.Balance
	if not finiteNonNegative(balance) then
		return rejected("INVALID_BALANCE")
	end
	if balance > PlayerDataConfig.MaxBalance - amount then
		return rejected("BALANCE_OVERFLOW")
	end
	local nextBalance = balance + amount
	if not finiteNonNegative(nextBalance) then
		return rejected("BALANCE_OVERFLOW")
	end
	if consumeSource then
		local consumed, sourceReason = consumeSource(data)
		if not consumed then
			return rejected(sourceReason or "SOURCE_CHANGED")
		end
	end
	data.Economy.Balance = nextBalance
	local revision, dirtyReason = profileOwner:MarkDirty(player)
	if not revision then
		data.Economy.Balance = balance
		return rejected(dirtyReason or "PROFILE_NOT_WRITABLE")
	end
	local result = {
		ok = true,
		committed = true,
		code = "Applied",
		balance = nextBalance,
		revision = revision,
	}
	notifyCommitted(player, {
		kind = "WalletCredit",
		eventId = tostring(revision) .. ":credit:" .. reason,
		at = now(),
		amount = amount,
		source = reason,
		balanceBefore = balance,
		balanceAfter = nextBalance,
		revision = revision,
	})
	return result
end

function Currency:TrySpend(player: Player, cost: number, reason: string): any
	if not finiteNonNegative(cost) or type(reason) ~= "string" or reason == "" then
		return rejected("INVALID_COST")
	end
	if not profileOwner.CommitMutation then
		return rejected("PROFILE_MUTATION_UNAVAILABLE")
	end
	local balanceBefore: number? = nil
	local result = profileOwner:CommitMutation(player, function(data)
		local prepared = self:PrepareSpend(data, cost)
		if prepared.ok ~= true then
			return false, prepared
		end
		balanceBefore = prepared.balanceBefore
		if cost == 0 then
			return false,
				{
					ok = true,
					committed = true,
					code = "Unchanged",
					balance = prepared.balance,
				}
		end
		data.Economy.Balance = prepared.balance
		return true, {
			ok = true,
			committed = true,
			code = "Applied",
			balance = prepared.balance,
		}
	end)
	if type(result) == "table" and result.committed == true and cost > 0 then
		notifyCommitted(player, {
			kind = "WalletDebit",
			eventId = tostring(result.revision or "none") .. ":debit:" .. reason,
			at = now(),
			amount = cost,
			source = reason,
			balanceBefore = balanceBefore,
			balanceAfter = result.balance,
			revision = result.revision,
		})
	end
	return result
end

-- Trusted server-only observation of an already-committed coherent domain spend.
-- The debit and entitlement must have been written by CommitMutation first.
function Currency:ObserveCommittedSpend(player: Player, result: any, reason: string)
	if type(result) ~= "table" or result.committed ~= true or result.ok ~= true then
		return
	end
	if
		not finiteNonNegative(result.price)
		or not finiteNonNegative(result.balanceBefore)
		or not finiteNonNegative(result.balance)
		or result.balanceBefore - result.balance ~= result.price
	then
		return
	end
	notifyCommitted(player, {
		kind = "WalletDebit",
		eventId = tostring(result.revision) .. ":debit:" .. reason,
		at = now(),
		amount = result.price,
		source = reason,
		balanceBefore = result.balanceBefore,
		balanceAfter = result.balance,
		revision = result.revision,
	})
end

function Currency:SubscribeCommitted(callback: (Player, any) -> ()): any
	local connection = {}
	committedListeners[connection] = callback
	function connection.Disconnect()
		committedListeners[connection] = nil
	end
	return connection
end

function Currency:AddCash(player: Player, amount: number, reason: string): any
	return self:TryCredit(player, amount, reason)
end

function Currency:SyncBalance(player: Player): (boolean, string?)
	local balance, reason = self:GetBalance(player)
	if balance == nil then
		return false, reason or "ACCOUNT_UNAVAILABLE"
	end
	local ok, failure = pcall(function()
		player:SetAttribute("Cash", balance)
		-- P15 mirrors: Gems balance and the income multiplier breakdown (presentation only).
		local data = profileOwner:GetReadableData(player)
		if data then
			local GemRules = require(game:GetService("ReplicatedStorage").Shared.Utility.GemRules)
			local income = GemRules.IncomeBreakdown(data, workspace:GetServerTimeNow())
			player:SetAttribute("Gems", GemRules.Balance(data))
			player:SetAttribute("IncomeMultiplier", income.total)
			player:SetAttribute("CashBoostUntil", if income.boostRemaining > 0 then workspace:GetServerTimeNow() + income.boostRemaining else 0)
		end
	end)
	return ok, if ok then nil else tostring(failure)
end

function Currency:BeginClosing(player: Player): boolean
	return profileOwner:BeginClosing(player)
end

function Currency:ReleaseAccount(_player: Player)
	-- PlayerDataService is the only release owner. Retained as a no-op so an old
	-- subsystem cannot unlock a profile before its final snapshot is persisted.
end

function Currency:_ResetForTests(owner: any?, options: any?)
	profileOwner = owner or PlayerDataService
	now = if options and options.Now
		then options.Now
		else function()
			return workspace:GetServerTimeNow()
		end
end

return Currency
