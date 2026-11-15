--!nocheck
-- Regression contract for the removed automatic deposit scanner.
return function()
	local Return = require(script.Parent.Parent.Systems.BaseReturnSystem)
	local Storage = require(script.Parent.Parent.Systems.BaseStorageSystem)
	describe("Retired automatic cart return", function()
		it("cannot invoke deposit from repeated legacy startup, scans or unload calls", function()
			local original, calls = Storage.TryDepositItem, 0
			Storage.TryDepositItem = function()
				calls += 1
				error("Automatic deposit must never run")
			end
			local ok, failure = pcall(function()
				Return:Start()
				Return:Start()
				for _ = 1, 3 do
					Return:Step()
					local result = Return:TryUnloadCart(nil, nil, nil)
					expect(result.Success).to.equal(false)
					expect(result.Reason).to.equal("MANUAL_PLACEMENT_REQUIRED")
				end
				task.wait(0.5)
				Return:Destroy()
				expect(calls).to.equal(0)
			end)
			Storage.TryDepositItem = original
			assert(ok, failure)
		end)
	end)
end
