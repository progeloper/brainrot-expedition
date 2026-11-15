--!strict

return function()
	local Overlay = require(game:GetService("ReplicatedStorage").Shared.Utility.CartShieldCargoOverlay)
	local function fixture(callback)
		local stage = Instance.new("Folder")
		local cart = Instance.new("Model") cart:SetAttribute("CartGeneration", 7) cart.Parent = stage
		local folder = Instance.new("Folder") folder.Name = "CargoVisuals" folder.Parent = cart
		local slots = Instance.new("Folder") slots.Name = "CargoSlots" slots.Parent = cart
		local now = 10
		local function cargo(id: string, index: number): (Model, BasePart)
			local slot = Instance.new("Part") slot.Name = "Slot" .. index slot:SetAttribute("CargoItemId", id) slot.Parent = slots
			local model = Instance.new("Model") model.Name = "ArbitraryPresentationName"
			model:SetAttribute("ItemId", id) model:SetAttribute("AttachmentIndex", index) model:SetAttribute("BrainrotDisplayState", "Cart")
			local body = Instance.new("Part") body.Name = "Body" body.Color = Color3.fromRGB(50, 170, 70) body.Material = Enum.Material.Plastic body.Parent = model
			model.Parent = folder
			return model, slot
		end
		local visual, slot = cargo("fixture-cargo-1", 1)
		local overlay = Overlay.new(cart, { Clock = function() return now end, Defer = function(fn) fn() end })
		local function snapshot(expires: number, revision: number, capacity: number?): any
			return { capacity = capacity or 2, remaining = 0, protectedUntil = expires, revision = revision, lifecycleId = "fixture-life", cartGeneration = 7 }
		end
		local function at(value: number) now = value end
		local ok, result = xpcall(function() callback(cart, folder, visual, slot, overlay, cargo, snapshot, at, stage) end, debug.traceback)
		overlay:Destroy() folder:Destroy() stage:Destroy()
		assert(ok, result)
	end
	describe("Cargo-only reversible Shield film", function()
		it("spare charges alone add no film; active protection uses the approved occluded light blue overlay", function()
			fixture(function(_cart, _folder, visual, _slot, overlay, _cargo, snapshot)
				overlay:Sync(snapshot(0, 1), 10)
				expect(visual:FindFirstChildOfClass("Highlight")).to.equal(nil)
				overlay:Sync(snapshot(15, 2), 10)
				local film = visual:FindFirstChildOfClass("Highlight")
				assert(film, "Active cargo film missing")
				expect(film.FillColor).to.equal(Color3.fromRGB(153, 221, 255))
				expect(math.abs(film.FillTransparency - 0.55) < 1e-6).to.equal(true)
				expect(film.DepthMode).to.equal(Enum.HighlightDepthMode.Occluded)
				expect(film.Enabled).to.equal(true)
			end)
		end)
		it("rejects non-cargo and stale individual identities even inside the presentation folder", function()
			fixture(function(cart, folder, visual, slot, overlay, _cargo, snapshot)
				overlay:Sync(snapshot(15, 1), 10)
				slot:SetAttribute("CargoItemId", "replacement-individual") overlay:Refresh()
				expect(visual:FindFirstChildOfClass("Highlight")).to.equal(nil)
				expect(Overlay.IsCargo(cart, folder, visual)).to.equal(false)
				slot:SetAttribute("CargoItemId", "fixture-cargo-1") visual:SetAttribute("BrainrotDisplayState", "Carried") overlay:Refresh()
				expect(visual:FindFirstChildOfClass("Highlight")).to.equal(nil)
				visual.Parent = cart visual:SetAttribute("BrainrotDisplayState", "Cart") overlay:Refresh()
				expect(Overlay.IsCargo(cart, folder, visual)).to.equal(false)
			end)
		end)
		it("new cargo and streaming rebuilds receive only the original remaining window", function()
			fixture(function(cart, folder, _visual, _slot, overlay, cargo, snapshot, at)
				overlay:Sync(snapshot(15, 1), 10)
				at(14) local added = cargo("fixture-cargo-2", 2) overlay:Refresh()
				expect(added:FindFirstChildOfClass("Highlight").Enabled).to.equal(true)
				folder.Parent = nil overlay:Refresh()
				expect(overlay:Diagnostics().highlights).to.equal(0)
				folder.Parent = cart overlay:Refresh()
				expect(added:FindFirstChildOfClass("Highlight").Enabled).to.equal(true)
				at(15) overlay:Tick(15)
				expect(added:FindFirstChildOfClass("Highlight").Enabled).to.equal(false)
			end)
		end)
		it("cargo leaving the cart immediately loses its own overlay without recoloring current appearance", function()
			fixture(function(_cart, _folder, visual, _slot, overlay, _cargo, snapshot, _at, stage)
				local body = visual:FindFirstChild("Body")
				assert(body and body:IsA("BasePart"), "Fixture body missing")
				overlay:Sync(snapshot(15, 1), 10)
				local updatedColor = Color3.fromRGB(220, 50, 80) body.Color = updatedColor
				visual.Parent = stage overlay:Refresh()
				expect(visual:FindFirstChildOfClass("Highlight")).to.equal(nil)
				expect(body.Color).to.equal(updatedColor)
				expect(body.Material).to.equal(Enum.Material.Plastic)
			end)
		end)
		it("an old state cannot clear newer protection and capacity removal cannot truncate an earned window", function()
			fixture(function(_cart, _folder, visual, _slot, overlay, _cargo, snapshot, at)
				at(15)
				overlay:Sync(snapshot(20, 3, 0), 15)
				expect(overlay:Sync(snapshot(0, 2, 0), 15)).to.equal(false)
				at(19.999) overlay:Tick(19.999)
				expect(visual:FindFirstChildOfClass("Highlight").Enabled).to.equal(true)
				at(20) overlay:Tick(20)
				expect(visual:FindFirstChildOfClass("Highlight").Enabled).to.equal(false)
			end)
		end)
		it("late presentation refresh after expiry never creates active film", function()
			fixture(function(_cart, _folder, _visual, _slot, overlay, cargo, snapshot, at)
				overlay:Sync(snapshot(15, 1), 10)
				at(15) local added = cargo("fixture-cargo-2", 2) overlay:Refresh()
				expect(added:FindFirstChildOfClass("Highlight")).to.equal(nil)
			end)
		end)
		it("one hundred protection cycles reuse bounded overlays and release every connection on teardown", function()
			fixture(function(_cart, _folder, _visual, _slot, overlay, _cargo, snapshot, at)
				local connections = overlay:Diagnostics().connections
				for cycle = 1, 100 do
					local start = cycle * 10 at(start)
					overlay:Sync(snapshot(start + 5, cycle * 2), start)
					expect(overlay:Diagnostics().highlights).to.equal(1)
					at(start + 5) overlay:Tick(start + 5)
					expect(overlay:Diagnostics().connections).to.equal(connections)
				end
				overlay:Destroy()
				expect(overlay:Diagnostics().highlights).to.equal(0)
				expect(overlay:Diagnostics().connections).to.equal(0)
			end)
		end)
	end)
end
