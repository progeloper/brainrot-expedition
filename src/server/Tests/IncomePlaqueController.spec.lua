--!nocheck

return function()
	local Controller = require(
		game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.IncomePlaqueController
	)

	local function signal()
		local listeners = {}
		local event = {}
		function event:Connect(callback)
			listeners[callback] = true
			return {
				Disconnect = function()
					listeners[callback] = nil
				end,
			}
		end
		function event:Fire(...)
			for callback in listeners do
				callback(...)
			end
		end
		function event:Count()
			local count = 0
			for _ in listeners do
				count += 1
			end
			return count
		end
		return event
	end

	local function fakeCollection(initial)
		local tagged = table.clone(initial or {})
		local added = signal()
		local removed = signal()
		local collection = {}
		function collection:GetTagged()
			return table.clone(tagged)
		end
		function collection:GetInstanceAddedSignal()
			return added
		end
		function collection:GetInstanceRemovedSignal()
			return removed
		end
		function collection:Add(instance)
			table.insert(tagged, instance)
			added:Fire(instance)
		end
		function collection:Remove(instance)
			local index = table.find(tagged, instance)
			if index then
				table.remove(tagged, index)
				removed:Fire(instance)
			end
		end
		collection.Added = added
		collection.Removed = removed
		return collection
	end

	local function makePlaque(name, position, snapshot, rate, occupied, revision, serverTime)
		local plaque = Instance.new("Part")
		plaque.Name = name
		plaque.Anchored = true
		plaque.Position = position
		plaque:SetAttribute("UnclaimedCashSnapshot", snapshot)
		plaque:SetAttribute("IncomeRatePerSecond", rate)
		plaque:SetAttribute("IncomeSnapshotServerTime", serverTime or 0)
		plaque:SetAttribute("IncomeOccupied", occupied)
		plaque:SetAttribute("IncomeRevision", revision or 1)
		plaque:SetAttribute("IncomeSnapshotReady", true)
		plaque:SetAttribute("ClaimRevision", 0)
		local surface = Instance.new("SurfaceGui")
		surface.Name = "AmountSurfaceGui"
		surface.Enabled = false
		surface.Parent = plaque
		local label = Instance.new("TextLabel")
		label.Name = "AmountLabel"
		label.Text = "SERVER"
		label.Parent = surface
		plaque.Parent = workspace
		return plaque, label, surface
	end

	local function setSnapshot(plaque, now, snapshot, rate, occupied, revision)
		plaque:SetAttribute("UnclaimedCashSnapshot", snapshot)
		plaque:SetAttribute("IncomeRatePerSecond", rate)
		plaque:SetAttribute("IncomeSnapshotServerTime", now)
		plaque:SetAttribute("IncomeOccupied", occupied)
		plaque:SetAttribute("IncomeRevision", revision)
	end

	local function fixture(plaqueList, callback)
		Controller.Stop()
		local collection = fakeCollection(plaqueList)
		local now = 0
		local viewerPosition = Vector3.zero
		assert(Controller.Init({
			CollectionService = collection,
			Clock = function()
				return now
			end,
			GetViewerPosition = function()
				return viewerPosition
			end,
			DisableLoop = true,
		}))
		assert(Controller.Start())
		local context = {
			Collection = collection,
			SetNow = function(value)
				now = value
			end,
			SetViewerPosition = function(value)
				viewerPosition = value
			end,
		}
		local ok, err = xpcall(function()
			callback(context)
		end, debug.traceback)
		Controller.Stop()
		for _, plaque in plaqueList do
			if plaque.Parent then
				plaque:Destroy()
			end
		end
		if not ok then
			error(err)
		end
	end

	describe("IncomePlaqueController", function()
		it("renders only replicated authoritative balances", function()
			local first, firstLabel, firstSurface =
				makePlaque("SPEC_INCOME_A", Vector3.new(10, 0, 0), 10, 2, true, 1, 0)
			local second, secondLabel, secondSurface =
				makePlaque("SPEC_INCOME_B", Vector3.new(20, 0, 0), 20, 5, true, 1, 0)
			local empty, emptyLabel, emptySurface =
				makePlaque("SPEC_INCOME_EMPTY", Vector3.new(30, 0, 0), 37, 100, false, 1, 0)
			fixture({ first, second, empty }, function(context)
				context.SetNow(3)
				Controller._TestStep(3, true)
				expect(firstLabel.Text).to.equal("$10")
				expect(secondLabel.Text).to.equal("$20")
				expect(emptyLabel.Text).to.equal("")
				expect(firstSurface.Enabled).to.equal(true)
				expect(secondSurface.Enabled).to.equal(true)
				expect(emptySurface.Enabled).to.equal(false)

				context.SetNow(4)
				setSnapshot(first, 4, 0, 2, true, 2)
				expect(firstLabel.Text).to.equal("$0")
				expect(secondLabel.Text).to.equal("$20")
				expect(emptyLabel.Text).to.equal("")
				expect(Controller._TestRegistrySize()).to.equal(3)

				context.SetNow(4.6)
				Controller._TestStep(4.6, false)
				expect(firstLabel.Text).to.equal("$0")

				context.SetNow(5)
				setSnapshot(second, 5, 2, 8, true, 2)
				expect(secondLabel.Text).to.equal("$2")
				expect(Controller._TestRegistrySize()).to.equal(3)

				context.SetNow(6)
				setSnapshot(second, 6, 7, 0, false, 3)
				Controller._TestStep(20, false)
				expect(secondLabel.Text).to.equal("")
				expect(secondSurface.Enabled).to.equal(false)

				setSnapshot(second, 7, 0, 0, false, 4)
				expect(secondLabel.Text).to.equal("")
				expect(secondSurface.Enabled).to.equal(false)

				setSnapshot(second, 8, 0, 20, true, 5)
				expect(secondLabel.Text).to.equal("$0")
				expect(secondSurface.Enabled).to.equal(true)

				second:SetAttribute("IncomeSnapshotReady", false)
				second:SetAttribute("IncomeRevision", 6)
				expect(secondLabel.Text).to.equal("")
				expect(secondSurface.Enabled).to.equal(false)
			end)
		end)

		it("does not speculate while a distant plaque becomes active", function()
			local plaque, label =
				makePlaque("SPEC_INCOME_RANGE", Vector3.new(200, 0, 0), 0, 3, true, 1, 0)
			fixture({ plaque }, function(context)
				expect(Controller._TestIsActive(plaque)).to.equal(false)
				context.SetNow(10)
				Controller._TestStep(10, false)
				expect(label.Text).to.equal("$0")
				context.SetViewerPosition(Vector3.new(200, 0, 0))
				Controller._TestStep(10, true)
				expect(Controller._TestIsActive(plaque)).to.equal(true)
				expect(label.Text).to.equal("$0")
			end)
		end)

		it("keeps one subscription set and replaces destroyed plaque registries", function()
			local oldPlaques = {}
			for index = 1, 12 do
				oldPlaques[index] = makePlaque(
					"SPEC_INCOME_OLD_" .. index,
					Vector3.new(index, 0, 0),
					0,
					0,
					false,
					1,
					0
				)
			end
			fixture(oldPlaques, function(context)
				expect(Controller._TestRegistrySize()).to.equal(12)
				expect(Controller.Start()).to.equal(false)
				expect(context.Collection.Added:Count()).to.equal(1)
				expect(context.Collection.Removed:Count()).to.equal(1)

				for _, plaque in oldPlaques do
					context.Collection:Remove(plaque)
					plaque:Destroy()
				end
				expect(Controller._TestRegistrySize()).to.equal(0)

				for index = 1, 12 do
					local plaque = makePlaque(
						"SPEC_INCOME_NEW_" .. index,
						Vector3.new(index, 0, 0),
						0,
						0,
						false,
						1,
						0
					)
					table.insert(oldPlaques, plaque)
					context.Collection:Add(plaque)
				end
				expect(Controller._TestRegistrySize()).to.equal(12)
				for _, plaque in oldPlaques do
					for _, descendant in plaque:GetDescendants() do
						expect(descendant:IsA("LocalScript")).to.equal(false)
					end
				end
			end)
		end)
	end)
end
