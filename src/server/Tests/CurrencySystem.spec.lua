--!nocheck
return function()
	local Currency = require(script.Parent.Parent.Systems.CurrencySystem)
	local counter = 1000

	local function fixture()
		counter += 1
		local player = {
			Name = "WalletFixture",
			UserId = counter,
			Cash = nil,
			FailMirror = false,
		}
		function player:SetAttribute(name, value)
			if self.FailMirror then
				error("injected mirror failure")
			end
			self[name] = value
		end
		local owner = {
			Ready = true,
			Closing = false,
			Revision = 0,
			Data = { Economy = { Balance = 0 } },
		}
		function owner:IsWritable(subject)
			return subject == player and self.Ready and not self.Closing
		end
		function owner:GetReadableData(subject)
			return if subject == player and self.Ready then self.Data else nil, "PROFILE_NOT_READY"
		end
		function owner:GetWritableData(subject)
			return if self:IsWritable(subject) then self.Data else nil, "PROFILE_NOT_READY"
		end
		function owner:MarkDirty(subject)
			if not self:IsWritable(subject) then
				return nil, "PROFILE_NOT_READY"
			end
			self.Revision += 1
			return self.Revision
		end
		function owner:CommitMutation(subject, mutate)
			if not self:IsWritable(subject) then
				return { ok = false, code = "PROFILE_NOT_READY" }
			end
			local committed, result = mutate(self.Data)
			if committed ~= true then
				return result
			end
			self.Revision += 1
			result.ok = true
			result.committed = true
			result.revision = self.Revision
			return result
		end
		function owner:GetDiagnostics()
			return { currentRevision = self.Revision }
		end
		function owner:BeginClosing(subject)
			if subject ~= player or not self.Ready then
				return false
			end
			self.Closing = true
			return true
		end
		Currency:_ResetForTests(owner)
		return player, owner
	end

	describe("Phase 7A-1 persistent wallet authority", function()
		it("distinguishes unavailable data from a loaded zero balance", function()
			local player, owner = fixture()
			expect(Currency:OpenAccount(player)).to.equal(true)
			expect(Currency:GetBalance(player)).to.equal(0)
			owner.Ready = false
			expect(Currency:IsReady(player)).to.equal(false)
			expect(Currency:GetBalance(player)).to.equal(nil)
			expect(Currency:OpenAccount(player)).to.equal(false)
		end)

		it("preserves fractional credits and spends", function()
			local player, owner = fixture()
			owner.Data.Economy.Balance = 10
			local credit = Currency:TryCredit(player, 1.8, "TestCredit")
			expect(credit.ok).to.equal(true)
			expect(math.abs(Currency:GetBalance(player) - 11.8) < 1e-9).to.equal(true)
			owner.Data.Economy.Balance = 100.5
			local spend = Currency:TrySpend(player, 40, "TestSpend")
			expect(spend.ok).to.equal(true)
			expect(math.abs(Currency:GetBalance(player) - 60.5) < 1e-9).to.equal(true)
			expect(owner.Revision).to.equal(2)
		end)

		it("rejects overspend, invalid amounts and overflow without mutation", function()
			local player, owner = fixture()
			owner.Data.Economy.Balance = 5
			expect(Currency:TrySpend(player, 6, "TooMuch").code).to.equal("INSUFFICIENT_FUNDS")
			for _, amount in { -1, 0, "2", math.huge, 0 / 0 } do
				expect(Currency:TryCredit(player, amount, "Invalid").ok).to.equal(false)
			end
			expect(Currency:GetBalance(player)).to.equal(5)
			owner.Data.Economy.Balance = 9007199254740991
			expect(Currency:TryCredit(player, 1, "Overflow").code).to.equal("BALANCE_OVERFLOW")
		end)

		it("ignores a client-edited mirror and keeps presentation failure secondary", function()
			local player = fixture()
			player.Cash = 99999
			expect(Currency:TryCredit(player, 2.5, "Income").committed).to.equal(true)
			expect(Currency:GetBalance(player)).to.equal(2.5)
			player.FailMirror = true
			expect(Currency:SyncBalance(player)).to.equal(false)
			expect(Currency:GetBalance(player)).to.equal(2.5)
			player.FailMirror = false
			expect(Currency:SyncBalance(player)).to.equal(true)
			expect(player.Cash).to.equal(2.5)
		end)

		it("stops mutations while closing", function()
			local player = fixture()
			expect(Currency:BeginClosing(player)).to.equal(true)
			expect(Currency:TryCredit(player, 4, "Late").ok).to.equal(false)
			expect(Currency:TrySpend(player, 0, "Late").ok).to.equal(false)
		end)

		it("rechecks affordability for every synchronous spend", function()
			local player, owner = fixture()
			owner.Data.Economy.Balance = 10
			local first = Currency:TrySpend(player, 7, "First")
			local second = Currency:TrySpend(player, 7, "Second")
			expect(first.ok).to.equal(true)
			expect(second.code).to.equal("INSUFFICIENT_FUNDS")
			expect(Currency:GetBalance(player)).to.equal(3)
			expect(owner.Revision).to.equal(1)
		end)

		it("prepares a debit without mutating the shared profile", function()
			local _, owner = fixture()
			owner.Data.Economy.Balance = 100.5
			local prepared = Currency:PrepareSpend(owner.Data, 40)
			expect(prepared.ok).to.equal(true)
			expect(prepared.balance).to.equal(60.5)
			expect(owner.Data.Economy.Balance).to.equal(100.5)
			expect(owner.Revision).to.equal(0)
		end)

		it("emits one immutable post-commit receipt without giving telemetry authority", function()
			local player, owner = fixture()
			owner.Data.Economy.Balance = 10
			local receipts = {}
			local healthy = Currency:SubscribeCommitted(function(subject, receipt)
				expect(subject).to.equal(player)
				table.insert(receipts, receipt)
			end)
			local throwing = Currency:SubscribeCommitted(function()
				error("injected telemetry failure")
			end)
			local result = Currency:TryCredit(player, 2.5, "ObservedCredit")
			expect(result.committed).to.equal(true)
			expect(owner.Data.Economy.Balance).to.equal(12.5)
			expect(owner.Revision).to.equal(1)
			expect(#receipts).to.equal(1)
			expect(receipts[1].kind).to.equal("WalletCredit")
			expect(receipts[1].amount).to.equal(2.5)
			expect(receipts[1].balanceAfter).to.equal(12.5)
			expect(table.isfrozen(receipts[1])).to.equal(true)
			healthy:Disconnect()
			throwing:Disconnect()
		end)
	end)
end
