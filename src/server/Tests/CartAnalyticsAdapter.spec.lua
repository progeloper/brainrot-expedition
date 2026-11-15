--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local AnalyticsEvents = require(ReplicatedStorage.Shared.Constants.AnalyticsEvents)
	local CartAnalyticsAdapter = require(script.Parent.Parent.Utility.CartAnalyticsAdapter)

	type Payload = CartAnalyticsAdapter.Payload
	type Provider = CartAnalyticsAdapter.Provider

	local function validSpawnPayload(): Payload
		return {
			EventVersion = 1,
			BuildId = "test-build",
			Environment = "Development",
			ServerTimestamp = 100,
			PlayerUserId = 42,
			RuntimeCartId = "runtime-cart-1",
			CartId = "CRT_001",
			SpawnId = "CSP_001",
		}
	end

	describe("CartAnalyticsAdapter", function()
		it("delivers one validated event to an injected provider", function()
			local emissions: { { Name: string, Payload: Payload } } = {}
			local payload = validSpawnPayload()
			local provider: Provider = {
				Emit = function(_self, eventName, eventPayload)
					table.insert(emissions, {
						Name = eventName,
						Payload = eventPayload,
					})
				end,
			}
			local adapter = CartAnalyticsAdapter.new({
				Provider = provider,
				Warn = function(_message) end,
			})

			local emitted, emitError = adapter:Emit(AnalyticsEvents.CartSpawned, payload)

			expect(emitted).to.equal(true)
			expect(emitError).to.equal(nil)
			expect(#emissions).to.equal(1)
			expect(emissions[1].Name).to.equal(AnalyticsEvents.CartSpawned)
			expect(emissions[1].Payload).to.equal(payload)
		end)

		it("uses an enabled no-op provider by default", function()
			local adapter = CartAnalyticsAdapter.new()
			local emitted, emitError =
				adapter:Emit(AnalyticsEvents.CartSpawned, validSpawnPayload())

			expect(adapter:IsEnabled()).to.equal(true)
			expect(emitted).to.equal(true)
			expect(emitError).to.equal(nil)
			expect(table.isfrozen(CartAnalyticsAdapter.CreateNoopProvider())).to.equal(true)
		end)

		it("gates dispatch before validation when disabled", function()
			local providerCalls = 0
			local warnings = 0
			local provider: Provider = {
				Emit = function(_self, _eventName, _payload)
					providerCalls += 1
				end,
			}
			local adapter = CartAnalyticsAdapter.new({
				Enabled = false,
				Provider = provider,
				Warn = function(_message)
					warnings += 1
				end,
			})

			local emitted, emitError = adapter:Emit("not-an-event", nil)

			expect(adapter:IsEnabled()).to.equal(false)
			expect(emitted).to.equal(false)
			expect(emitError).to.equal("Disabled")
			expect(providerCalls).to.equal(0)
			expect(warnings).to.equal(0)
		end)

		it("drops invalid events and reports the validation failure", function()
			local providerCalls = 0
			local warnings: { string } = {}
			local provider: Provider = {
				Emit = function(_self, _eventName, _payload)
					providerCalls += 1
				end,
			}
			local adapter = CartAnalyticsAdapter.new({
				Provider = provider,
				Warn = function(message)
					table.insert(warnings, message)
				end,
			})

			local emitted, emitError = adapter:Emit(AnalyticsEvents.CartSpawned, {
				EventVersion = 1,
			})

			expect(emitted).to.equal(false)
			expect(emitError).to.equal("InvalidPayload")
			expect(providerCalls).to.equal(0)
			expect(#warnings).to.equal(1)
			expect(string.find(warnings[1], AnalyticsEvents.CartSpawned, 1, true) ~= nil).to.equal(
				true
			)
		end)

		it("contains a provider exception without retrying", function()
			local providerCalls = 0
			local warnings: { string } = {}
			local provider: Provider = {
				Emit = function(_self, _eventName, _payload)
					providerCalls += 1
					error("test provider unavailable")
				end,
			}
			local adapter = CartAnalyticsAdapter.new({
				Provider = provider,
				Warn = function(message)
					table.insert(warnings, message)
				end,
			})

			local emitted, emitError =
				adapter:Emit(AnalyticsEvents.CartSpawned, validSpawnPayload())

			expect(emitted).to.equal(false)
			expect(emitError).to.equal("ProviderFailure")
			expect(providerCalls).to.equal(1)
			expect(#warnings).to.equal(1)
			expect(string.find(warnings[1], "test provider unavailable", 1, true) ~= nil).to.equal(
				true
			)
		end)

		it("rejects malformed provider configuration eagerly", function()
			expect(function()
				CartAnalyticsAdapter.new({
					Provider = {} :: any,
				})
			end).to.throw()
		end)
	end)
end
