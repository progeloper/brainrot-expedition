--!nocheck
-- Pure coroutine tests of the actual production request flow. These do not
-- replace a connected client, native layout, RemoteFunction or backend test.
return function()
	local Shop = require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.Phase13ShopController)
	local function fixture()
		local flow = Shop.CreateOpenRequestFlow()
		local original = { label = "existing snapshot" }
		local state = {
			flow = flow, character = {}, started = true, alive = true,
			cinematic = false, visible = false, snapshot = original, commits = 0,
		}
		function state:Close()
			self.flow:Cancel()
			self.visible = false
		end
		function state:Begin(result)
			local thread = coroutine.create(function()
				return flow:Run(self.character, function()
					coroutine.yield("AwaitingSnapshot")
					return result
				end, function(character)
					return self.started and self.alive and not self.cinematic and self.character == character
				end, function(snapshot)
					self.snapshot, self.visible = snapshot, true
					self.commits += 1
					return true
				end)
			end)
			local ok, yielded = coroutine.resume(thread)
			assert(ok and yielded == "AwaitingSnapshot", tostring(yielded))
			return thread
		end
		return state, original
	end
	local function complete(thread)
		local ok, result = coroutine.resume(thread)
		assert(ok, tostring(result))
		expect(coroutine.status(thread)).to.equal("dead")
		return result
	end
	describe("Phase13 yielding shop request lifecycle", function()
		it("does not reopen or replace the snapshot after Close while Snapshot yields", function()
			local state, original = fixture()
			local request = state:Begin({ label = "stale response" })
			state:Close()
			expect(complete(request)).to.equal(false)
			expect(state.visible).to.equal(false)
			expect(state.snapshot).to.equal(original)
			expect(state.commits).to.equal(0)
		end)
		it("keeps a Stop then Start request authoritative over an old same-character request", function()
			local state = fixture()
			local old = state:Begin({ label = "before Stop" })
			state.started = false
			state:Close()
			state.started = true
			local latest = { label = "after Start" }
			local current = state:Begin(latest)
			expect(complete(current)).to.equal(true)
			expect(complete(old)).to.equal(false)
			expect(state.snapshot).to.equal(latest)
			expect(state.commits).to.equal(1)
		end)
		it("rejects death/respawn and character replacement while a request is suspended", function()
			local state, original = fixture()
			local request = state:Begin({ label = "old living character" })
			state.alive = false
			state:Close()
			state.character, state.alive = {}, true
			expect(complete(request)).to.equal(false)
			expect(state.snapshot).to.equal(original)
			local changed, preserved = fixture()
			local other = changed:Begin({ label = "old character without a close callback" })
			changed.character = {}
			expect(complete(other)).to.equal(false)
			expect(changed.snapshot).to.equal(preserved)
		end)
		it("allows only the newest overlapping open request to apply its computed snapshot", function()
			local state = fixture()
			local old = state:Begin({ label = "slow Base" })
			local latest = { label = "fast Cart" }
			local current = state:Begin(latest)
			expect(complete(current)).to.equal(true)
			expect(complete(old)).to.equal(false)
			expect(state.snapshot).to.equal(latest)
			expect(state.commits).to.equal(1)
		end)
		it("does not apply a snapshot when cinematic context changes before its close callback", function()
			local state, original = fixture()
			local request = state:Begin({ label = "pre-cinematic" })
			state.cinematic = true
			expect(complete(request)).to.equal(false)
			expect(state.snapshot).to.equal(original)
			expect(state.visible).to.equal(false)
		end)
		it("applies a current response exactly once without changing its snapshot identity", function()
			local state = fixture()
			local latest = { label = "current response" }
			local request = state:Begin(latest)
			expect(complete(request)).to.equal(true)
			expect(state.snapshot).to.equal(latest)
			expect(state.visible).to.equal(true)
			expect(state.commits).to.equal(1)
		end)
	end)

	-- Production focus ownership, with real native GUI ancestry and existing
	-- input/control handoff utilities. These are unit cases, not a connected pass.
	local roots = {}
	local function focusCase(name, callback)
		it(name, function()
			local ok, failure = xpcall(callback, debug.traceback)
			for _, root in roots do root:Destroy() end
			table.clear(roots)
			if not ok then error(failure, 0) end
		end)
	end
	local function focusFixture()
		local root = Instance.new("Folder")
		root.Name = "Phase13FocusUnitRoot"
		table.insert(roots, root)
		local shop = Instance.new("ScreenGui")
		shop.Name, shop.Parent = "Phase13Shop", root
		local panel = Instance.new("Frame")
		panel.Parent = shop
		local opener = Instance.new("TextButton")
		opener.Name, opener.Selectable, opener.Parent = "ShopOpener", true, shop
		local modal = Instance.new("Frame")
		modal.Parent = panel
		local confirm = Instance.new("TextButton")
		confirm.Selectable, confirm.Parent = true, modal
		local foreign = Instance.new("ScreenGui")
		foreign.Name, foreign.Parent = "OtherMenu", root
		local foreignPanel = Instance.new("Frame")
		foreignPanel.Parent = foreign
		local prior = Instance.new("TextButton")
		prior.Selectable, prior.Parent = true, foreignPanel
		local other = Instance.new("TextButton")
		other.Selectable, other.Parent = true, foreignPanel
		local f = { root = root, shop = shop, panel = panel, opener = opener, modal = modal, confirm = confirm, foreign = foreign, foreignPanel = foreignPanel, prior = prior, other = other, selected = nil, writes = 0 }
		f.flow = Shop.CreateSelectionOwnershipFlow(function() return f.selected end, function(value) f.selected, f.writes = value, f.writes + 1 end, function(value) return value:IsDescendantOf(shop) end, function(value) return Shop.IsRestorableSelection(value, root, shop) end)
		return f
	end
	describe("Phase13 shop focus ownership", function()
		focusCase("restores the prior outside focus after modal destruction selects the owned HUD opener", function()
			local f = focusFixture()
			f.selected = f.prior
			f.flow:Open()
			f.selected = f.confirm
			f.modal:Destroy()
			f.panel.Visible, f.selected = false, f.opener
			f.flow:Close()
			expect(f.selected).to.equal(f.prior)
			expect(f.writes).to.equal(1)
		end)
		focusCase("does not restore the persistent owned HUD opener captured by its own native click", function()
			local f = focusFixture()
			f.selected = f.opener
			f.flow:Open()
			f.selected = f.confirm
			f.flow:Close()
			expect(f.selected).to.equal(nil)
			expect(Shop.IsRestorableSelection(f.opener, f.root, f.shop)).to.equal(false)
		end)
		focusCase("keeps a different UI's newly acquired focus when the shop closes", function()
			local f = focusFixture()
			f.selected = f.prior
			f.flow:Open()
			f.selected = f.other
			expect(f.flow:Close()).to.equal(false)
			expect(f.selected).to.equal(f.other)
			expect(f.writes).to.equal(0)
		end)
		focusCase("never restores a destroyed prior control", function()
			local f = focusFixture()
			f.selected = f.prior
			f.flow:Open()
			f.prior:Destroy()
			f.selected = f.opener
			f.flow:Close()
			expect(f.selected).to.equal(nil)
		end)
		focusCase("rejects hidden, disabled and unselectable prior focus in its actual ancestry", function()
			for _, reason in { "HiddenAncestor", "DisabledGui", "Unselectable" } do
				local f = focusFixture()
				f.selected = f.prior
				f.flow:Open()
				if reason == "HiddenAncestor" then f.foreignPanel.Visible = false elseif reason == "DisabledGui" then f.foreign.Enabled = false else f.prior.Selectable = false end
				f.selected = f.opener
				f.flow:Close()
				expect(f.selected).to.equal(nil)
			end
		end)
		focusCase("does not overwrite its outside bookmark when switching tabs in an already open panel", function()
			local f = focusFixture()
			f.selected = f.prior
			f.flow:Open()
			f.selected = f.confirm
			expect(f.flow:Open()).to.equal(false)
			f.flow:Close()
			expect(f.selected).to.equal(f.prior)
		end)
		focusCase("does not recreate outside focus after the player cleared it following Close", function()
			local f = focusFixture()
			f.selected = f.prior
			f.flow:Open()
			f.selected = f.confirm
			f.flow:Close()
			expect(f.selected).to.equal(f.prior)
			f.selected = nil
			expect(f.flow:Close()).to.equal(false)
			expect(f.flow:RestoreClosed()).to.equal(false)
			expect(f.selected).to.equal(nil)
			expect(f.writes).to.equal(1)
		end)
		focusCase("releases a late owned fallback on cinematic completion without clearing foreign UI", function()
			local f = focusFixture()
			f.flow:Open()
			f.selected = f.confirm
			f.flow:Close()
			f.selected = f.opener -- native fallback while cinematic owns controls
			expect(f.flow:RestoreClosed()).to.equal(true)
			expect(f.selected).to.equal(nil)
			f.selected = f.other
			expect(f.flow:RestoreClosed()).to.equal(false)
			expect(f.selected).to.equal(f.other)
		end)
		focusCase("forgets a stopped lifetime and never clears focus belonging to a newly open panel", function()
			local f = focusFixture()
			f.flow:Open()
			f.flow:Close()
			f.flow:Forget()
			f.selected = f.opener
			expect(f.flow:RestoreClosed()).to.equal(false)
			expect(f.selected).to.equal(f.opener)
			f.flow:Open()
			f.selected = f.confirm
			expect(f.flow:RestoreClosed()).to.equal(false)
			expect(f.selected).to.equal(f.confirm)
		end)
		focusCase("releases existing default-control restoration only after a real daze deadline", function()
			local f = focusFixture()
			local utility = game.StarterPlayer.StarterPlayerScripts.Client.Utility
			local ControlRestore, Policy = require(utility.Phase10ControlRestore), require(utility.Phase10InputPolicy)
			local time, attrs = 100, { Phase10DazeEnd = 103 }
			local player = { GetAttribute = function(_, key) return attrs[key] end }
			local input = { GetFocusedTextBox = function() return nil end }
			local gui = { MenuIsOpen = false }
			local controls = { controlsEnabled = false, Enables = 0 }
			function controls:Enable() self.controlsEnabled = true; self.Enables += 1 end
			function controls:Disable() self.controlsEnabled = false end
			local restore = ControlRestore.new(function() gui.SelectedObject = f.selected; return Policy.IsDazed(player, time) or Policy.IsMenuOpen(player, gui, input) end)
			f.flow:Open()
			f.selected = f.confirm
			f.flow:Close()
			f.selected = f.opener
			restore:ResumeWhenAllowed(controls)
			f.flow:RestoreClosed()
			expect(restore:ReleaseWhenAllowed()).to.equal(false)
			expect(controls.controlsEnabled).to.equal(false)
			time = 103
			expect(restore:ReleaseWhenAllowed()).to.equal(true)
			expect(controls.controlsEnabled).to.equal(true)
			expect(controls.Enables).to.equal(1)
		end)
		focusCase("retains the existing control lock while another real menu owns selection", function()
			local f = focusFixture()
			local utility = game.StarterPlayer.StarterPlayerScripts.Client.Utility
			local ControlRestore, Policy = require(utility.Phase10ControlRestore), require(utility.Phase10InputPolicy)
			local player = { GetAttribute = function() return nil end }
			local input = { GetFocusedTextBox = function() return nil end }
			local gui = { MenuIsOpen = false }
			local controls = { controlsEnabled = false, Enables = 0 }
			function controls:Enable() self.controlsEnabled = true; self.Enables += 1 end
			function controls:Disable() self.controlsEnabled = false end
			local restore = ControlRestore.new(function() gui.SelectedObject = f.selected; return Policy.IsMenuOpen(player, gui, input) end)
			f.flow:Open()
			f.selected = f.other
			f.flow:Close()
			restore:ResumeWhenAllowed(controls)
			expect(controls.controlsEnabled).to.equal(false)
			f.flow:RestoreClosed()
			expect(f.selected).to.equal(f.other)
			f.selected = nil -- the other menu releases its own focus
			restore:ReleaseWhenAllowed()
			expect(controls.controlsEnabled).to.equal(true)
			expect(controls.Enables).to.equal(1)
		end)
	end)
end
