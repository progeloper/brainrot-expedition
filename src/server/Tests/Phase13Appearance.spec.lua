--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Config = require(RS.Shared.Config.Phase13)
	local Weapons = require(RS.Shared.Config.Weapons)
	local Rules = require(RS.Shared.Utility.Phase13AppearanceRules)
	local Commerce = require(RS.Shared.Utility.Phase13CommerceRules)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Geometry = require(script.Parent.Parent.Utility.Phase13BaseGeometry)
	local function baseFixture()
		local base = Instance.new("Model")
		local foundation = Instance.new("Part")
		foundation.Name, foundation.Size, foundation.Anchored = "Foundation", Vector3.new(46.66, 1, 79.4625), true
		foundation.Color = Color3.fromRGB(113, 82, 59)
		foundation.Parent = base
		for i = 1, 12 do
			local slot = Instance.new("Part")
			slot.Name, slot.Size, slot.Anchored = string.format("Slot_%02d", i), Vector3.new(13.92, 1, 10.16), true
			slot.CFrame = CFrame.new(if i % 2 == 0 then 12.77 else -12.77, 1.5, -30 + math.floor((i - 1) / 2) * 12.18)
			slot.Parent = base
		end
		return base
	end
	describe("Required saved VIP and starter cosmetic contract", function()
		it(
			"permits explicit toggles only with the durable entitlement and never grants functional ownership",
			function()
				local data = Schema.CreateDefault()
				expect(Rules.CanSelect(data, "VIPBadge", "On")).to.equal(false)
				expect(Rules.CanSelect(data, "VIPBadge", "Off")).to.equal(true)
				expect(Rules.CanSelect(data, "CartFinish", "Trailblazer")).to.equal(false)
				Commerce.GrantPass(data, "VIP", 1000)
				Commerce.GrantPass(data, "STARTER_PACK", 1000)
				expect(Rules.CanSelect(data, "VIPChat", "On")).to.equal(true)
				expect(Rules.CanSelect(data, "VIPTitle", "On")).to.equal(true)
				expect(data.Phase13.OwnedCartIds.CRT_013).to.equal(nil)
				expect(data.Phase13.OwnedWeaponIds.WPN_G08).to.equal(nil)
				expect(data.Phase13.ExpansionLevel).to.equal(0)
			end
		)
		it(
			"resolves Riftgold for all nine owned carts and all24 owned weapons while unowned IDs stay Default",
			function()
				local data = Schema.CreateDefault()
				Commerce.GrantPass(data, "VIP", 1000)
				data.Commerce.Appearance.CartFinish, data.Commerce.Appearance.WeaponFinish = "Riftgold", "Riftgold"
				local carts, weapons = 0, 0
				for _, cart in Config.CartRows do
					if not cart.starter then
						expect(Rules.ResolveFinish(data, "Cart", cart.id)).to.equal("Default")
					end
					data.Phase13.OwnedCartIds[cart.id] = true
					expect(Rules.ResolveFinish(data, "Cart", cart.id)).to.equal("Riftgold")
					carts += 1
				end
				for _, weapon in Weapons.GetAll() do
					data.Phase13.OwnedWeaponIds[weapon.id] = true
					expect(Rules.ResolveFinish(data, "Weapon", weapon.id)).to.equal("Riftgold")
					weapons += 1
				end
				expect(carts).to.equal(9)
				expect(weapons).to.equal(24)
			end
		)
		it(
			"restricts permanent Trailblazer to the starter cart and weapon without replacing other owned kit",
			function()
				local data = Schema.CreateDefault()
				Commerce.GrantPass(data, "STARTER_PACK", 1000)
				data.Commerce.Appearance.CartFinish, data.Commerce.Appearance.WeaponFinish =
					"Trailblazer", "Trailblazer"
				data.Phase13.OwnedCartIds.CRT_013 = true
				data.Phase13.OwnedWeaponIds.WPN_G08 = true
				expect(Rules.ResolveFinish(data, "Cart", Config.InitialCartId)).to.equal("Trailblazer")
				expect(Rules.ResolveFinish(data, "Weapon", Config.InitialWeaponId)).to.equal("Trailblazer")
				expect(Rules.ResolveFinish(data, "Cart", "CRT_013")).to.equal("Default")
				expect(Rules.ResolveFinish(data, "Weapon", "WPN_G08")).to.equal("Default")
				expect(data.Phase13.SelectedCartId).to.equal(Config.InitialCartId)
			end
		)
		it("decorates only a selected VIP prefix while leaving filtered message text unchanged", function()
			local Identity =
				require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.Phase13AppearanceController)
			local values = { Entitlement_VIP = true, Appearance_VIPChat = "On" }
			local author = {
				GetAttribute = function(_, key)
					return values[key]
				end,
			}
			local message = { PrefixText = "[Role] Player:", Text = "platform-filtered text" }
			local properties = Identity.DecorateMessage(message, author)
			expect(properties.PrefixText:find("[Role] Player:", 1, true) ~= nil).to.equal(true)
			expect(message.Text).to.equal("platform-filtered text")
			expect(properties.Text).to.equal("")
			values.Appearance_VIPChat = "Off"
			expect(Identity.DecorateMessage(message, author)).to.equal(nil)
			values.Appearance_VIPChat, values.Entitlement_VIP = "On", false
			expect(Identity.DecorateMessage(message, author)).to.equal(nil)
			properties:Destroy()
		end)
		it(
			"uses identical preview/runtime tint independent of child order, without altering mechanical properties",
			function()
				local model = Instance.new("Model")
				local part = Instance.new("Part")
				part.Name, part.Color, part.Size = "Handle", Color3.fromRGB(30, 80, 120), Vector3.new(1, 2, 3)
				part.CFrame, part.CanCollide, part.Massless = CFrame.new(5, 8, 12), true, false
				part.Parent = model
				local attachment = Instance.new("Attachment")
				attachment.Name, attachment.CFrame, attachment.Parent = "Muzzle", CFrame.new(0, 0, -1.1), part
				local clone = model:Clone()
				local original = part.Color
				local ok, why = xpcall(function()
					Rules.Apply(model, "Trailblazer")
					Rules.Apply(clone, "Trailblazer")
					expect(part.Color).to.equal(clone.Handle.Color)
					expect(part.Size).to.equal(Vector3.new(1, 2, 3))
					expect(part.CFrame).to.equal(CFrame.new(5, 8, 12))
					expect(part.CanCollide).to.equal(true)
					expect(part.Massless).to.equal(false)
					expect(attachment.CFrame).to.equal(CFrame.new(0, 0, -1.1))
					Rules.Apply(model, "Riftgold")
					local gold = part.Color
					Rules.Apply(model, "Riftgold")
					expect(part.Color).to.equal(gold)
					Rules.Apply(model, "Default")
					expect(part.Color).to.equal(original)
				end, debug.traceback)
				model:Destroy()
				clone:Destroy()
				assert(ok, why)
			end
		)
		it(
			"gilds and restores all eight base designs at all seven capacities including starter with no collision/capacity change",
			function()
				local base = baseFixture()
				local cases = 0
				local ok, why = xpcall(function()
					Geometry.Build(base)
					for _, design in Config.DesignRows do
						for capacity = 12, 48, 6 do
							Geometry.Apply(base, capacity, design.id, false)
							local structural = base.Phase13Architecture:FindFirstChild("FloorLeft_1")
							local original, size, cf, collides =
								structural.Color, structural.Size, structural.CFrame, structural.CanCollide
							local groundColor = base.Foundation.Color
							Geometry.Apply(base, capacity, design.id, true)
							expect(base.Foundation.Transparency < 1).to.equal(true)
							expect(base.Foundation.Color ~= groundColor).to.equal(true)
							expect(structural.Color ~= original).to.equal(true)
							expect(structural.Size).to.equal(size)
							expect(structural.CFrame).to.equal(cf)
							expect(structural.CanCollide).to.equal(collides)
							expect(base:GetAttribute("Phase13Capacity")).to.equal(capacity)
							Geometry.Apply(base, capacity, design.id, false)
							expect(base.Foundation.Color).to.equal(groundColor)
							expect(structural.Color).to.equal(original)
							cases += 1
						end
					end
				end, debug.traceback)
				base:Destroy()
				assert(ok, why)
				expect(cases).to.equal(56)
			end
		)
	end)
end
