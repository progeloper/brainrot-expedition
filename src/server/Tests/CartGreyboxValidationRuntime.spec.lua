--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartGreyboxScenarioIds)
	local CartGreyboxValidationResult =
		require(ReplicatedStorage.Shared.Utility.CartGreyboxValidationResult)
	local CartGreyboxValidationRuntime =
		require(script.Parent.Parent.Utility.CartGreyboxValidationRuntime)

	local function createActive(
		cart: Model,
		scenarioId: string
	): CartGreyboxValidationRuntime.ActiveScenario
		return {
			ScenarioId = scenarioId,
			SectionId = "GBOX_LIFECYCLE",
			SpawnId = "GBOX_SPAWN_GBOX_LIFECYCLE",
			StartedAt = 10,
			Cart = cart,
		}
	end

	describe("CartGreyboxValidationRuntime", function()
		it("selects the first unoccupied multiplayer lane deterministically", function()
			local spawnIds = {
				"GBOX_SPAWN_GBOX_MULTIPLAYER_LANE_1",
				"GBOX_SPAWN_GBOX_MULTIPLAYER_LANE_2",
				"GBOX_SPAWN_GBOX_MULTIPLAYER_LANE_3",
			}
			local occupied = {
				[spawnIds[1]] = true,
				[spawnIds[2]] = false,
				[spawnIds[3]] = false,
			}

			expect(
				CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(spawnIds, function(spawnId)
					return occupied[spawnId]
				end)
			).to.equal(spawnIds[2])

			occupied[spawnIds[2]] = true
			occupied[spawnIds[3]] = true

			expect(
				CartGreyboxValidationRuntime.SelectFirstAvailableSpawnId(spawnIds, function(spawnId)
					return occupied[spawnId]
				end)
			).to.equal(nil)
		end)

		it("replaces active scenario state without growing records", function()
			local runtime = CartGreyboxValidationRuntime.new()
			local firstCart = Instance.new("Model")
			local replacementCart = Instance.new("Model")

			runtime:SetActive(101, createActive(firstCart, ScenarioIds.SpawnReadiness))
			runtime:SetActive(101, createActive(replacementCart, ScenarioIds.CartReplacement))

			expect(runtime:GetActive(101).Cart).to.equal(replacementCart)
			expect(runtime:GetDiagnostics().ActiveScenarioCount).to.equal(1)

			firstCart:Destroy()
			replacementCart:Destroy()
		end)

		it("clears only the matching cart or player lifecycle", function()
			local runtime = CartGreyboxValidationRuntime.new()
			local firstCart = Instance.new("Model")
			local secondCart = Instance.new("Model")

			runtime:SetActive(101, createActive(firstCart, ScenarioIds.CartDestruction))
			runtime:SetActive(202, createActive(secondCart, ScenarioIds.MultiplayerIsolation))

			expect(runtime:ClearForCart(101, secondCart)).to.equal(false)
			expect(runtime:ClearForCart(101, firstCart)).to.equal(true)
			expect(runtime:GetActive(101)).to.equal(nil)
			expect(runtime:GetActive(202).Cart).to.equal(secondCart)

			runtime:RemovePlayer(202)
			expect(runtime:GetDiagnostics().ActiveScenarioCount).to.equal(0)

			firstCart:Destroy()
			secondCart:Destroy()
		end)

		it("captures immutable results and clears all state on reset", function()
			local runtime = CartGreyboxValidationRuntime.new()
			local cart = Instance.new("Model")
			local result = CartGreyboxValidationResult.Create({
				ScenarioId = ScenarioIds.LifecycleEndurance,
				Status = "Passed",
				RecordedAt = 20,
			})

			runtime:SetActive(101, createActive(cart, ScenarioIds.LifecycleEndurance))
			runtime:AddResult(result)

			local returned = runtime:GetResults()

			table.clear(returned)
			expect(runtime:GetDiagnostics().ResultCount).to.equal(1)

			runtime:Reset()
			expect(runtime:GetDiagnostics().ActiveScenarioCount).to.equal(0)
			expect(runtime:GetDiagnostics().ResultCount).to.equal(0)

			cart:Destroy()
		end)
	end)
end
