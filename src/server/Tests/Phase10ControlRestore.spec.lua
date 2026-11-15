--!nocheck
-- Default-control ownership is exercised with the actual shared input policy,
-- controlled server time and a fake PlayerModule control endpoint. No client
-- singleton, frame wait, real player control or live UI is needed.
return function()
	local utility = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Utility
	local ControlRestore = require(utility.Phase10ControlRestore)
	local Policy = require(utility.Phase10InputPolicy)
	-- Legacy contract: any controller selection blocks (unstick = false). The Playtest Fixes 2
	-- InputUnstick rule (a HUD selection never blocks) is covered by PlaytestFixes2.spec.
	local function fixture()
		local time = 100
		local enabled = true
		local attributes = {}
		local player = {}
		function player:GetAttribute(key)
			return attributes[key]
		end
		local gui = { MenuIsOpen = false }
		local input = {}
		function input:GetFocusedTextBox()
			return self.Focus
		end
		local controls = { controlsEnabled = true, Enables = 0, Disables = 0 }
		function controls:Enable()
			self.controlsEnabled = true
			self.Enables += 1
		end
		function controls:Disable()
			self.controlsEnabled = false
			self.Disables += 1
		end
		local restore = ControlRestore.new(function()
			return enabled and (Policy.IsDazed(player, time) or Policy.IsMenuOpen(player, gui, input, false))
		end)
		return {
			Controls = controls,
			Restore = restore,
			Attributes = attributes,
			Gui = gui,
			Input = input,
			At = function(nextTime)
				time = nextTime
				return restore:ReleaseWhenAllowed()
			end,
			DisableFeature = function()
				enabled = false
				return restore:ReleaseWhenAllowed()
			end,
		}
	end

	describe("Phase10 default control restoration handoff", function()
		it("keeps touch controls disabled when daze starts inside Team and the menu closes", function()
			local f = fixture()
			f.Attributes.ChariotTeamMenuOpen = true
			f.Controls:Disable() -- Team saved an enabled pre-menu state.
			f.Attributes.Phase10DazeEnd = 103
			expect(f.Restore:Hold(f.Controls)).to.equal(false) -- Daze did not take Team's lock.
			f.Attributes.ChariotTeamMenuOpen = nil
			f.Restore:ResumeWhenAllowed(f.Controls) -- Team transfers only its own restoration.
			expect(f.Controls.controlsEnabled).to.equal(false)
			expect(f.Controls.Enables).to.equal(0)
			expect(f.At(102.999)).to.equal(false)
			expect(f.Controls.Enables).to.equal(0)
			expect(f.At(103)).to.equal(true)
			expect(f.Controls.controlsEnabled).to.equal(true)
			expect(f.Controls.Enables).to.equal(1)
			f.At(104)
			expect(f.Controls.Enables).to.equal(1)
		end)

		it("retains a pre-menu daze lock until the still-open menu releases it", function()
			local f = fixture()
			f.Attributes.Phase10DazeEnd = 103
			expect(f.Restore:Hold(f.Controls)).to.equal(true)
			f.Attributes.ChariotTeamMenuOpen = true -- Team observes controls already disabled.
			expect(f.At(103)).to.equal(false)
			expect(f.Controls.Enables).to.equal(0)
			f.Attributes.ChariotTeamMenuOpen = nil -- Team has no pre-menu restoration permission.
			expect(f.At(103)).to.equal(true)
			expect(f.Controls.Enables).to.equal(1)
		end)

		it("never claims or enables controls that were already disabled by another owner", function()
			local f = fixture()
			f.Controls.controlsEnabled = false
			f.Attributes.Phase10DazeEnd = 103
			expect(f.Restore:Hold(f.Controls)).to.equal(false)
			f.At(103)
			expect(f.Controls.controlsEnabled).to.equal(false)
			expect(f.Controls.Enables).to.equal(0)
		end)

		it("waits for other menus, chat and controller focus after the deadline", function()
			local f = fixture()
			f.Controls:Disable()
			f.Attributes.Phase10DazeEnd = 103
			f.Restore:ResumeWhenAllowed(f.Controls)
			f.Gui.MenuIsOpen = true
			f.At(103)
			f.Gui.MenuIsOpen = false
			f.Input.Focus = {}
			f.At(103)
			f.Input.Focus = nil
			f.Gui.SelectedObject = {}
			f.At(103)
			expect(f.Controls.Enables).to.equal(0)
			f.Gui.SelectedObject = nil
			f.At(103)
			expect(f.Controls.Enables).to.equal(1)
		end)

		it("repeated transfers stay bounded and honor a changed authoritative deadline", function()
			local f = fixture()
			f.Controls:Disable()
			f.Attributes.Phase10DazeEnd = 103
			for _ = 1, 100 do
				f.Restore:ResumeWhenAllowed(f.Controls)
			end
			f.Attributes.Phase10DazeEnd = 104
			f.At(103)
			expect(f.Controls.Enables).to.equal(0)
			f.At(104)
			expect(f.Controls.Enables).to.equal(1)
			expect(f.Controls.Disables).to.equal(1)
		end)

		it("restores normally without a restriction and releases owned controls when the feature stops", function()
			local f = fixture()
			f.Controls:Disable()
			f.Restore:ResumeWhenAllowed(f.Controls)
			expect(f.Controls.Enables).to.equal(1)
			f.Attributes.Phase10DazeEnd = 103
			f.Restore:Hold(f.Controls)
			f.DisableFeature()
			expect(f.Controls.Enables).to.equal(2)
			f.DisableFeature()
			expect(f.Controls.Enables).to.equal(2)
		end)
	end)
end
