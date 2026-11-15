--!nocheck
return function()
	local Policy = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Utility.Phase10InputPolicy)
	local function fixture(callback)
		local root = Instance.new("Folder")
		local hits = {}
		local gui = {}
		function gui:FindFirstChild(name)
			return root:FindFirstChild(name)
		end
		function gui:GetGuiObjectsAtPosition()
			return hits
		end
		local player = { Attributes = {} }
		function player:GetAttribute(key)
			return self.Attributes[key]
		end
		function player:FindFirstChildOfClass()
			return gui
		end
		local systemGui = { MenuIsOpen = false }
		local input = {}
		function input:GetFocusedTextBox()
			return self.Focus
		end
		local ok, err = xpcall(function()
			callback(player, systemGui, input, root, function(nextHits)
				hits = nextHits
			end)
		end, debug.traceback)
		root:Destroy()
		if not ok then
			error(err)
		end
	end
	describe("Phase10 native input exclusion", function()
		it("blocks the current Shop with no selected GUI object and restores on close", function()
			fixture(function(player, gui, input)
				expect(gui.SelectedObject).to.equal(nil)
				expect(Policy.IsBlocked(player, gui, input)).to.equal(false)
				player.Attributes.Phase13ShopOpen = true
				expect(Policy.IsMenuOpen(player, gui, input)).to.equal(true)
				expect(Policy.IsBlocked(player, gui, input)).to.equal(true)
				player.Attributes.Phase13ShopOpen = false
				expect(Policy.IsBlocked(player, gui, input)).to.equal(false)
				expect(gui.SelectedObject).to.equal(nil)
			end)
		end)
		it("marks current cargo unavailable for Shield charges or its live protection window", function()
			fixture(function(_, _, _, root)
				local cart = Instance.new("Model")
				cart:SetAttribute("RuntimeCart", true)
				cart.Parent = root
				local container = Instance.new("Folder")
				container.Name, container.Parent = "CargoVisuals", cart
				local visual = Instance.new("Model")
				visual.Parent = container
				cart:SetAttribute("ShieldRemaining", 1)
				cart:SetAttribute("ShieldProtectionExpiresAt", 0)
				expect(Policy.IsCargoShieldProtected(visual, 100)).to.equal(true)
				cart:SetAttribute("ShieldRemaining", 0)
				cart:SetAttribute("ShieldProtectionExpiresAt", 105)
				expect(Policy.IsCargoShieldProtected(visual, 104.999)).to.equal(true)
				expect(Policy.IsCargoShieldProtected(visual, 105)).to.equal(false)
				cart:SetAttribute("ShieldRemaining", 1)
				visual.Parent = root
				expect(Policy.IsCargoShieldProtected(visual, 100)).to.equal(false)
			end)
		end)
		it("passes GUI primary presses including nested labels and its own Fire to their native actions", function()
			fixture(function(player, _, _, root, setHits)
				local button = Instance.new("TextButton")
				button.Name, button.Parent = "Burst", root
				local child = Instance.new("TextLabel")
				child.Parent = button
				setHits({ child })
				expect(Policy.IsPointerInteraction(player, Vector2.new(100, 100))).to.equal(true)
				button.Name = "MountedFire"
				expect(Policy.IsPointerInteraction(player, Vector2.new(100, 100))).to.equal(true)
				local ordinary = Instance.new("TextLabel")
				ordinary.Parent = root
				setHits({ ordinary })
				expect(Policy.IsPointerInteraction(player, Vector2.new(100, 100))).to.equal(false)
				setHits({})
				expect(Policy.IsPointerInteraction(player, Vector2.new(100, 100))).to.equal(false)
			end)
		end)
		it("suspends all current native menus, chat and team management", function()
			fixture(function(player, gui, input, _root)
				-- every Plate window (sale, cargo bay, gate, stalls...) publishes its id through MenusV2
				for _, id in { "sale", "CargoBay", "Gate", "shop" } do
					player.Attributes.MenusV2Open = id
					expect(Policy.IsMenuOpen(player, gui, input)).to.equal(true)
					player.Attributes.MenusV2Open = nil
				end
				expect(Policy.IsMenuOpen(player, gui, input)).to.equal(false)
				input.Focus = {}
				expect(Policy.IsMenuOpen(player, gui, input)).to.equal(true)
				input.Focus = nil
				player.Attributes.ChariotTeamMenuOpen = true
				expect(Policy.IsMenuOpen(player, gui, input)).to.equal(true)
			end)
		end)
		it("uses authoritative deadlines without blocking normal protection-time controls", function()
			fixture(function(player)
				player.Attributes.Phase10DazeEnd = 103
				player.Attributes.Phase10ProtectionEnd = 108
				expect(Policy.IsDazed(player, 102.999)).to.equal(true)
				expect(Policy.IsDazed(player, 103)).to.equal(false)
				expect(Policy.IsDazed(player, 107)).to.equal(false)
			end)
		end)
	end)
end
