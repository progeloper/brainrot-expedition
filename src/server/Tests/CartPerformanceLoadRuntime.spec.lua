--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local LoadCounts = require(ReplicatedStorage.Shared.Constants.CartPerformanceLoadCounts)
	local ScenarioIds = require(ReplicatedStorage.Shared.Constants.CartPerformanceScenarioIds)
	local CartPerformanceLoadRuntime =
		require(script.Parent.Parent.Utility.CartPerformanceLoadRuntime)

	type Handle = {
		OwnerUserId: number,
		LoadIndex: number,
		ScenarioId: string,
	}

	local function createAdapter()
		local liveByOwnerUserId: { [number]: Handle } = {}
		local spawnOrder: { number } = {}
		local cleanupOrder: { number } = {}

		local adapter = {
			Spawn = function(ownerUserId: number, loadIndex: number, scenarioId: string): Handle
				local handle = {
					OwnerUserId = ownerUserId,
					LoadIndex = loadIndex,
					ScenarioId = scenarioId,
				}

				liveByOwnerUserId[ownerUserId] = handle
				table.insert(spawnOrder, ownerUserId)

				return handle
			end,
			Cleanup = function(handle: Handle, ownerUserId: number, loadIndex: number)
				expect(handle.OwnerUserId).to.equal(ownerUserId)
				expect(handle.LoadIndex).to.equal(loadIndex)
				liveByOwnerUserId[ownerUserId] = nil
				table.insert(cleanupOrder, ownerUserId)
			end,
		}

		return adapter, liveByOwnerUserId, spawnOrder, cleanupOrder
	end

	local function keyCount(values: { [any]: any }): number
		local count = 0

		for _ in values do
			count += 1
		end

		return count
	end

	describe("CartPerformanceLoadRuntime", function()
		it("is available only behind every Development, debug, Studio, and config gate", function()
			expect(CartPerformanceLoadRuntime.IsAvailable("Development", true, true, true)).to.equal(
				true
			)
			expect(CartPerformanceLoadRuntime.IsAvailable("Production", true, true, true)).to.equal(
				false
			)
			expect(CartPerformanceLoadRuntime.IsAvailable("Development", false, true, true)).to.equal(
				false
			)
			expect(CartPerformanceLoadRuntime.IsAvailable("Development", true, false, true)).to.equal(
				false
			)
			expect(CartPerformanceLoadRuntime.IsAvailable("Development", true, true, false)).to.equal(
				false
			)
		end)

		it("uses twelve fixed unique finite negative synthetic owner IDs", function()
			local ownerUserIds = CartPerformanceLoadRuntime.SyntheticOwnerUserIds
			local seen: { [number]: boolean } = {}

			expect(#ownerUserIds).to.equal(LoadCounts.Target)

			for _, ownerUserId in ownerUserIds do
				expect(ownerUserId == ownerUserId).to.equal(true)
				expect(math.abs(ownerUserId) < math.huge).to.equal(true)
				expect(ownerUserId < 0).to.equal(true)
				expect(ownerUserId % 1).to.equal(0)
				expect(seen[ownerUserId]).to.equal(nil)
				seen[ownerUserId] = true
			end

			expect(table.isfrozen(ownerUserIds)).to.equal(true)
		end)

		it("supports exactly the central 1, 4, 8, and 12 cart loads", function()
			for _, loadCount in LoadCounts.Ordered do
				local adapter, liveByOwnerUserId = createAdapter()
				local runtime = CartPerformanceLoadRuntime.new(adapter)
				local snapshot = runtime:Start(ScenarioIds.StationaryLoad, loadCount)

				expect(snapshot.State).to.equal("Running")
				expect(snapshot.ScenarioId).to.equal(ScenarioIds.StationaryLoad)
				expect(snapshot.LoadCount).to.equal(loadCount)
				expect(snapshot.ActiveCount).to.equal(loadCount)
				expect(#snapshot.OwnerUserIds).to.equal(loadCount)
				expect(keyCount(liveByOwnerUserId)).to.equal(loadCount)
				expect(table.isfrozen(snapshot)).to.equal(true)
				expect(table.isfrozen(snapshot.OwnerUserIds)).to.equal(true)
				expect((snapshot :: any).Handles).to.equal(nil)

				runtime:Stop()
				expect(keyCount(liveByOwnerUserId)).to.equal(0)
			end
		end)

		it("rejects noncentral load counts and scenario IDs before spawning", function()
			local adapter, liveByOwnerUserId = createAdapter()
			local runtime = CartPerformanceLoadRuntime.new(adapter)

			for _, invalidCount in { 0, 2, 3, 6, 13, math.huge, 0 / 0 } do
				local succeeded = pcall(function()
					runtime:Start(ScenarioIds.MovingLoad, invalidCount)
				end)

				expect(succeeded).to.equal(false)
				expect(runtime:GetState()).to.equal("Idle")
			end

			local scenarioSucceeded = pcall(function()
				runtime:Start("PERF_SCENARIO_NOT_REGISTERED", LoadCounts.Baseline)
			end)

			expect(scenarioSucceeded).to.equal(false)
			expect(keyCount(liveByOwnerUserId)).to.equal(0)
		end)

		it("spawns sequentially and cleans partial setup in reverse on failure", function()
			local adapter, liveByOwnerUserId, spawnOrder, cleanupOrder = createAdapter()
			local originalSpawn = adapter.Spawn

			adapter.Spawn = function(
				ownerUserId: number,
				loadIndex: number,
				scenarioId: string
			): Handle
				if loadIndex == 3 then
					error("controlled setup failure")
				end

				return originalSpawn(ownerUserId, loadIndex, scenarioId)
			end

			local runtime = CartPerformanceLoadRuntime.new(adapter)
			local succeeded = pcall(function()
				runtime:Start(ScenarioIds.MixedLifecycle, LoadCounts.IntermediateFour)
			end)

			expect(succeeded).to.equal(false)
			expect(#spawnOrder).to.equal(2)
			expect(#cleanupOrder).to.equal(2)
			expect(cleanupOrder[1]).to.equal(spawnOrder[2])
			expect(cleanupOrder[2]).to.equal(spawnOrder[1])
			expect(keyCount(liveByOwnerUserId)).to.equal(0)
			expect(runtime:GetState()).to.equal("Idle")
			expect(runtime:GetActiveCount()).to.equal(0)
			expect(#runtime:GetOwnerUserIds()).to.equal(0)
		end)

		it("rejects duplicate starts and stops running loads idempotently", function()
			local adapter, liveByOwnerUserId = createAdapter()
			local runtime = CartPerformanceLoadRuntime.new(adapter)

			runtime:Start(ScenarioIds.RepeatedReset, LoadCounts.IntermediateFour)

			local duplicateSucceeded = pcall(function()
				runtime:Start(ScenarioIds.StationaryLoad, LoadCounts.Baseline)
			end)

			expect(duplicateSucceeded).to.equal(false)
			expect(runtime:GetActiveCount()).to.equal(LoadCounts.IntermediateFour)
			expect(runtime:Stop()).to.equal(true)
			expect(runtime:Stop()).to.equal(false)
			expect(keyCount(liveByOwnerUserId)).to.equal(0)
			expect(runtime:GetSnapshot().State).to.equal("Idle")
		end)

		it("honours a stop requested during setup and cleans the returned handle", function()
			local cleanupOrder: { number } = {}
			local runtime: CartPerformanceLoadRuntime.Runtime
			local adapter = {
				Spawn = function(ownerUserId: number, loadIndex: number, scenarioId: string)
					expect(runtime:GetSnapshot().State).to.equal("Setup")
					expect(runtime:Stop()).to.equal(true)

					return {
						OwnerUserId = ownerUserId,
						LoadIndex = loadIndex,
						ScenarioId = scenarioId,
					}
				end,
				Cleanup = function(_handle: any, ownerUserId: number, _loadIndex: number)
					table.insert(cleanupOrder, ownerUserId)
				end,
			}

			runtime = CartPerformanceLoadRuntime.new(adapter)

			local succeeded = pcall(function()
				runtime:Start(ScenarioIds.LifecycleEndurance, LoadCounts.Target)
			end)

			expect(succeeded).to.equal(false)
			expect(#cleanupOrder).to.equal(1)
			expect(runtime:GetState()).to.equal("Idle")
			expect(runtime:GetActiveCount()).to.equal(0)
		end)

		it("does not retain state across ten complete target-load cycles", function()
			local adapter, liveByOwnerUserId, spawnOrder, cleanupOrder = createAdapter()
			local runtime = CartPerformanceLoadRuntime.new(adapter)

			for _cycle = 1, 10 do
				runtime:Start(ScenarioIds.LifecycleEndurance, LoadCounts.Target)
				expect(runtime:GetActiveCount()).to.equal(LoadCounts.Target)
				runtime:Stop()

				local snapshot = runtime:GetSnapshot()

				expect(snapshot.State).to.equal("Idle")
				expect(snapshot.ScenarioId).to.equal(nil)
				expect(snapshot.LoadCount).to.equal(0)
				expect(snapshot.ActiveCount).to.equal(0)
				expect(#snapshot.OwnerUserIds).to.equal(0)
				expect(keyCount(liveByOwnerUserId)).to.equal(0)
			end

			expect(#spawnOrder).to.equal(10 * LoadCounts.Target)
			expect(#cleanupOrder).to.equal(10 * LoadCounts.Target)
		end)
	end)
end
