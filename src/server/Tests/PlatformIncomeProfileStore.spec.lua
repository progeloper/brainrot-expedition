--!nocheck

return function()
	local Players = game:GetService("Players")
	local Store = require(script.Parent.Parent.Systems.PlatformIncomeProfileStore)

	describe("Phase 5D platform-income profile persistence", function()
		it(
			"migrates, saves exact stable-slot balances and reloads without offline accrual",
			function()
				Store:Stop()
				local values = {
					player_9200 = { Version = 0 },
				}
				local writes = 0
				local adapter = {}
				function adapter:GetAsync(key)
					return values[key]
				end
				function adapter:UpdateAsync(key, transform)
					writes += 1
					values[key] = transform(values[key])
					return values[key]
				end
				assert(Store:Start({ DataStore = adapter, Now = 0 }))

				local first = { UserId = 9200, Parent = Players }
				expect(Store:Load(first)).to.equal(true)
				expect(Store:Get(first).PlatformIncome["1"].UnclaimedCashExact).to.equal(0)
				local profile = Store:Get(first)
				profile.PlatformIncome["1"].UnclaimedCashExact = 5.25
				profile.PlatformIncome["9"].UnclaimedCashExact = 1.75
				expect(Store:MarkDirty(first, profile)).to.equal(true)
				expect(Store:Autosave(59)).to.equal(false)
				expect(writes).to.equal(0)
				expect(Store:Autosave(60)).to.equal(true)
				expect(writes).to.equal(1)
				expect(Store:Release(first)).to.equal(true)

				local rejoined = { UserId = 9200, Parent = Players }
				expect(Store:Load(rejoined)).to.equal(true)
				local restored = Store:Get(rejoined)
				expect(restored.PlatformIncome["1"].UnclaimedCashExact).to.equal(5.25)
				expect(restored.PlatformIncome["9"].UnclaimedCashExact).to.equal(1.75)
				expect(restored.PlatformIncome["2"].UnclaimedCashExact).to.equal(0)
				Store:Release(rejoined)
				Store:Stop()
			end
		)

		it("rejects malformed persisted balances without creating a replacement save", function()
			Store:Stop()
			local adapter = {}
			function adapter:GetAsync()
				return {
					PlatformIncome = {
						["1"] = { UnclaimedCashExact = 0 / 0 },
						["2"] = { UnclaimedCashExact = -4 },
						["3"] = { UnclaimedCashExact = math.huge },
					},
				}
			end
			function adapter:UpdateAsync(_, transform)
				return transform(nil)
			end
			assert(Store:Start({ DataStore = adapter }))
			local player = { UserId = 9201, Parent = Players }
			local loaded, reason = Store:Load(player)
			expect(loaded).to.equal(false)
			expect(reason).to.equal("INVALID_PLATFORM_CASH")
			expect(Store:Get(player)).to.equal(nil)
			expect(Store:Save(player)).to.equal(false)
			Store:Stop()
		end)
	end)
end
