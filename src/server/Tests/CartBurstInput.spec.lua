--!strict

return function()
	local Shared = game:GetService("ReplicatedStorage").Shared
	local Registry = require(Shared.Config.CartInputRegistry)
	local Policy = require(Shared.Utility.CartBurstInputPolicy)
	local Layout = require(Shared.Utility.CartBurstHudLayout)
	local function context(): any
		return { FeatureEnabled = true, AuthorizedDriver = true, CartAlive = true,
			WindowFocused = true, TextFocused = false, SystemMenuOpen = false,
			TeamMenuOpen = false, ResetActive = false }
	end
	describe("Burst input and reachable HUD", function()
		it("registers one named action distinct from Fire Brake Reset Team and Interaction", function()
			expect(Registry.Burst.Name).to.equal("Burst")
			for _, action in { Registry.Fire, Registry.Brake, Registry.Reset, Registry.ManageTeam, Registry.Interact } do
				expect(action.Keyboard == Registry.Burst.Keyboard).to.equal(false)
				expect(action.Gamepad == Registry.Burst.Gamepad).to.equal(false)
			end
			expect(Registry.Burst.Gamepad == Enum.KeyCode.Thumbstick2).to.equal(false)
		end)
		it("allows the registered action only for active driving context", function()
			expect(Policy.CanActivate(context())).to.equal(true)
			for _, key in { "FeatureEnabled", "AuthorizedDriver", "CartAlive", "WindowFocused" } do
				local blocked = context() blocked[key] = false
				expect(Policy.CanActivate(blocked)).to.equal(false)
			end
			for _, key in { "TextFocused", "SystemMenuOpen", "TeamMenuOpen", "ResetActive" } do
				local blocked = context() blocked[key] = true
				expect(Policy.CanActivate(blocked)).to.equal(false)
			end
		end)
		it("places its bar and 49-pixel action wholly inside common phone safe areas", function()
			for _, size in { Vector2.new(320, 568), Vector2.new(390, 760), Vector2.new(568, 250), Vector2.new(844, 310), Vector2.new(1024, 700) } do
				local layout = Layout.Resolve(size)
				local width, height = layout.Size.X.Offset, layout.Size.Y.Offset
				local right = size.X + layout.Position.X.Offset
				local top = layout.Position.Y.Offset
				expect(right - width >= 0).to.equal(true)
				expect(right <= size.X).to.equal(true)
				expect(top >= 0 and top + height <= size.Y).to.equal(true)
				expect(width - 16 >= 48).to.equal(true)
				-- Reset uses right24, width92, height56, bottom150.
				local resetLeft, resetTop = size.X - 116, size.Y - 206
				local overlaps = right > resetLeft and right - width < size.X - 24
					and top + height > resetTop and top < size.Y - 150
				expect(overlaps).to.equal(false)
			end
		end)
	end)
end
