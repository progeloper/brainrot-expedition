--!strict
return function()
	local View = require(game.ReplicatedStorage.Shared.Utility.RetentionPresentation)
	describe("Phase14 confirmed Expedition presentation", function()
		it("invalidates an existing warning when either visibility or text clears after a menu closes", function()
			local Controller = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.RetentionController)
			local playerGui = Instance.new("Folder")
			local warnings = Instance.new("ScreenGui")
			warnings.Name, warnings.Parent = "Phase12CriticalWarnings", playerGui
			local critical, escape = Instance.new("TextLabel"), Instance.new("TextLabel")
			critical.Name, critical.Text, critical.Visible, critical.Parent = "CriticalReturn", "RETURN", true, warnings
			escape.Name, escape.Text, escape.Visible, escape.Parent = "FocusedEscapeWarning", "ESCAPE", true, warnings
			local changes = 0
			local observer = Controller.CreateCriticalWarningObserver(playerGui, function()
				changes += 1
			end)
			local ok, failure = xpcall(function()
				expect(observer.GetConnectionCount()).to.equal(8)
				expect(changes).to.equal(1)
				-- Menu closure already ran layout with the warning active. No new
				-- snapshot, viewport or menu event follows either clearance below.
				local before = changes
				critical.Visible = false
				task.wait()
				expect(changes > before).to.equal(true)
				before = changes
				escape.Text = ""
				task.wait()
				expect(changes > before).to.equal(true)
				before = changes
				escape.Text, critical.Visible = "ESCAPE", true
				task.wait()
				expect(changes > before).to.equal(true)
			end, debug.traceback)
			observer.Disconnect()
			playerGui:Destroy()
			assert(ok, failure)
		end)
		it("rebinds late warning labels and replacement roots without keeping removed handles", function()
			local Controller = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.RetentionController)
			local playerGui = Instance.new("Folder")
			local changes = 0
			local observer = Controller.CreateCriticalWarningObserver(playerGui, function()
				changes += 1
			end)
			local detached = {}
			local ok, failure = xpcall(function()
				expect(observer.GetConnectionCount()).to.equal(2)
				local warnings = Instance.new("ScreenGui")
				warnings.Name, warnings.Parent = "Phase12CriticalWarnings", playerGui
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(4)
				local critical = Instance.new("TextLabel")
				critical.Name, critical.Text, critical.Parent = "CriticalReturn", "RETURN", warnings
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(6)
				critical.Parent = nil
				table.insert(detached, critical)
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(4)
				local replacementCritical = Instance.new("TextLabel")
				replacementCritical.Name, replacementCritical.Text, replacementCritical.Parent = "CriticalReturn", "RETURN AGAIN", warnings
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(6)
				local before = changes
				critical.Text = "detached"
				task.wait()
				expect(changes).to.equal(before)
				warnings.Parent = nil
				table.insert(detached, warnings)
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(2)
				local replacement = Instance.new("ScreenGui")
				replacement.Name = "Phase12CriticalWarnings"
				local escape = Instance.new("TextLabel")
				escape.Name, escape.Text, escape.Parent = "FocusedEscapeWarning", "ESCAPE", replacement
				replacement.Parent = playerGui
				task.wait()
				expect(observer.GetConnectionCount()).to.equal(6)
				before = changes
				escape.Visible = false
				task.wait()
				expect(changes > before).to.equal(true)
				observer.Disconnect()
				expect(observer.GetConnectionCount()).to.equal(0)
				before = changes
				escape.Text, escape.Visible = "after Stop", true
				replacement.Parent = nil
				table.insert(detached, replacement)
				task.wait()
				expect(changes).to.equal(before)
			end, debug.traceback)
			observer.Disconnect()
			playerGui:Destroy()
			for _, object in detached do
				object:Destroy()
			end
			assert(ok, failure)
		end)
		it("opens claimable supplies in two interactions without auto-opening or a quest claim", function()
			local ready = { available = true, status = "Ready", supplies = { claimable = true, rewardCash = 25000000 } }
			expect(View.OpenTab(ready, "Collection")).to.equal("Supplies")
			expect(View.Supply(ready, false).enabled).to.equal(true)
			expect(View.Supply(ready, true).state).to.equal("Saving")
			expect(View.Supply(ready, true).enabled).to.equal(false)
			ready.supplies.claimable = false
			ready.supplies.claimedToday = true
			expect(View.Supply(ready, false).text).to.equal("Claimed today")
			expect(View.OpenTab(ready, "Collection")).to.equal("Collection")
			ready.available = false
			expect(View.Supply(ready, false).state).to.equal("Unavailable")
			expect(View.Supply(ready, false).enabled).to.equal(false)
		end)
		it("paginates32 live species through twelve retained cards and clamps stale page selections", function()
			local collection: any = { entries = {} }
			for index = 1, 32 do
				table.insert(collection.entries, { id = tostring(index) })
			end
			local first, page, pages = View.CollectionPage(collection, 1)
			expect(#first).to.equal(12)
			expect(page).to.equal(1)
			expect(pages).to.equal(3)
			expect(first[1].id).to.equal("1")
			expect(first[12].id).to.equal("12")
			local last, clamped = View.CollectionPage(collection, 100)
			expect(#last).to.equal(8)
			expect(clamped).to.equal(3)
			expect(last[1].id).to.equal("25")
			expect(last[8].id).to.equal("32")
			local empty, emptyPage, emptyPages = View.CollectionPage(nil, -1)
			expect(#empty).to.equal(0)
			expect(emptyPage).to.equal(1)
			expect(emptyPages).to.equal(1)
		end)
		it("never exposes a hidden Secret thumbnail and accepts only actual approved image references", function()
			local catalog = { BRT_001 = "rbxassetid://123", BRT_032 = "rbxassetid://456" }
			expect(View.Thumbnail({ id = "BRT_001" }, catalog)).to.equal("rbxassetid://123")
			expect(View.Thumbnail({ id = "BRT_032", hidden = true, thumbnail = "rbxassetid://999" }, catalog)).to.equal(
				nil
			)
			expect(View.Thumbnail({ id = "BRT_001", thumbnail = "https://unapproved.example/image.png" }, catalog)).to.equal(
				nil
			)
			expect(View.Thumbnail({ id = "BRT_001", thumbnail = "rbxassetid://789" }, catalog)).to.equal(
				"rbxassetid://789"
			)
		end)
		it("shows real wallet shortfall and preserves both accepted sacrifice warnings", function()
			local text = View.GoalText({
				name = "Cargo1",
				currency = "Cash",
				price = 500000000,
				balance = 125000000,
				shortfall = 375000000,
				prerequisites = { satisfied = false, previousLevel = 1 },
			})
			expect(text:find("Wallet", 1, true) ~= nil).to.equal(true)
			expect(text:find("Previous level 1 required", 1, true) ~= nil).to.equal(true)
			local cash = View.GoalText({
				currency = "Cash",
				price = 10000000000,
				balance = 3000000000,
				shortfall = 7000000000,
				cashSacrificeAll = true,
				warning = "Sacrifices ALL CASH: wallet and settled platform earnings.",
			})
			expect(cash:find("Cash threshold", 1, true) ~= nil).to.equal(true)
			expect(cash:find("ALL CASH: wallet and settled platform earnings.", 1, true) ~= nil).to.equal(true)
			local collection = View.GoalText({
				currency = "Owned qualifying brainrots",
				price = 4,
				balance = 2,
				shortfall = 2,
				prerequisites = {
					ownedCount = 12,
					qualifyingIndividuals = 2,
					requiredIndividuals = 4,
					minimumRarity = "Rare",
					full = true,
				},
				warning = "Sacrifices ALL owned brainrots. Cash is preserved.",
			})
			expect(collection:find("Rare individuals 2/4", 1, true) ~= nil).to.equal(true)
			expect(collection:find("Owned 12", 1, true) ~= nil).to.equal(true)
			expect(collection:find("ALL owned brainrots", 1, true) ~= nil).to.equal(true)
		end)
		it("coalesces duplicate progress and keeps at most three queued notices", function()
			local queue = {}
			for index = 1, 5 do
				View.PushNotice(queue, { key = tostring(index), text = tostring(index), duration = 1.5, expires = 12 })
			end
			expect(#queue).to.equal(3)
			expect(queue[1].key).to.equal("3")
			View.PushNotice(queue, { key = "4", text = "newest confirmed progress", duration = 3, expires = 15 })
			expect(#queue).to.equal(3)
			expect(queue[2].text).to.equal("newest confirmed progress")
		end)
		it("uses at most three server return rows including an absence refresher without inventing rewards", function()
			local rows = View.ReturnLines({
				returnRows = {
					{ kind = "Goal", goal = { name = "Beach", currency = "Cash", shortfall = 250000000 } },
					{ kind = "Supply", supplies = { nextLifetimeClaim = 8, claimedToday = false } },
					{ kind = "Refresher", text = "Hunt → bank → collect platform earnings." },
					{ kind = "Milestone", milestone = { label = "Collector", required = 5 }, count = 3 },
				},
			})
			expect(#rows).to.equal(3)
			expect(rows[1]:find("Remaining", 1, true) ~= nil).to.equal(true)
			expect(rows[2]:find("Supply claim 8", 1, true) ~= nil).to.equal(true)
			expect(rows[3]).to.equal("Hunt → bank → collect platform earnings.")
		end)
	end)
end
