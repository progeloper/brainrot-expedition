--!nocheck
-- Focused supported-rule and native Instance fixtures. The separate fit probe
-- covers actual persisted art/templates; these do not certify moving-cart input.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local Cosmetics = require(RS.Shared.Utility.Phase14CosmeticRules)
	local Factory = require(RS.Shared.Utility.Phase14TrailFactory)
	local Geometry = require(RS.Shared.Utility.CartGeometry)
	local Config = require(RS.Shared.Config.Phase13)
	local Presenter = require(script.Parent.Parent.Utility.Phase14CosmeticPresenter)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Public = require(Client.Controllers.RetentionPublicDisplayController)
	local Input = require(Client.Utility.Phase10InputPolicy)
	local function near(a, b)
		expect(math.abs(a - b) < 0.00001).to.equal(true)
	end
	describe("Phase14 completed cosmetics transaction and mount invariants", function()
		it("debits exact fixed Cash once, preserves fractional balance and never auto-equips", function()
			for _, item in { { "P14_FLAG_FOREST", 500000000 }, { "P14_BASE_FOREST", 2500000000 } } do
				local data = Schema.CreateDefault()
				data.Economy.Balance = 3000000000.375
				local selected = Fixtures.Clone(data.Commerce.Appearance)
				local accepted, result = Cosmetics.ApplyPurchase(data, item[1])
				expect(accepted).to.equal(true)
				expect(result.priceCash).to.equal(item[2])
				expect(data.Economy.Balance).to.equal(3000000000.375 - item[2])
				expect(data.Commerce.Entitlements[item[1]]).to.equal(true)
				Fixtures.AssertDeepEqual(data.Commerce.Appearance, selected)
				local committed = Fixtures.Clone(data)
				local again, rejected = Cosmetics.ApplyPurchase(data, item[1])
				expect(again).to.equal(false)
				expect(rejected.code).to.equal("ALREADY_OWNED")
				Fixtures.AssertDeepEqual(data, committed)
			end
		end)
		it("rejects insufficient funds, earned rewards, disabled paid and included trails without mutation", function()
			local data = Schema.CreateDefault()
			data.Economy.Balance = 499999999.375
			local original = Fixtures.Clone(data)
			for _, id in
				{
					"P14_FLAG_FOREST",
					"P14_BASE_FOREST",
					"P14_FLAG_CAMP",
					"P14_BASE_EXPEDITION",
					"P14_FLAG_RIFT",
					"P14_BASE_RIFT",
					"P14_TRAIL_COMET",
					"Spoofed",
				}
			do
				expect(Cosmetics.ApplyPurchase(data, id)).to.equal(false)
				Fixtures.AssertDeepEqual(data, original)
			end
			for _, id in { "P14_FLAG_RIFT", "P14_BASE_RIFT" } do
				-- P15: Rift cosmetics are Gem-priced; there is no enabled Robux path.
				expect(Cosmetics.Get(id).paidEnabled ~= true).to.equal(true)
				expect(Cosmetics.Get(id).acquisition).to.equal("Gems")
				expect(Cosmetics.Get(id).platformId).to.equal(nil)
			end
		end)
		it("uses individually fitted chassis bounds for all nine mounts without touching fitted geometry", function()
			local seen, smallest, largest = {}, math.huge, -math.huge
			for _, row in Config.CartRows do
				local profile = assert(Geometry.GetById(row.id))
				local before = profile.CoreBodyBounds.Size
				local frame = Presenter.FlagFrame(profile)
				local body = profile.CoreBodyBounds
				expect(frame.Position.X > body.Frame.Position.X + body.Size.X / 2).to.equal(true)
				expect(frame.Position.Z > body.Frame.Position.Z).to.equal(true)
				expect(profile.CoreBodyBounds.Size).to.equal(before)
				seen[row.id] = true
				smallest, largest = math.min(smallest, frame.Position.X), math.max(largest, frame.Position.X)
			end
			local count = 0
			for _ in seen do
				count += 1
			end
			expect(count).to.equal(9)
			expect(largest > smallest).to.equal(true)
		end)
		it("mounts banners on a rotated ground exterior independently of upper-stage capacity", function()
			local base = Instance.new("Model")
			local foundation = Instance.new("Part")
			foundation.Name, foundation.Size = "Foundation", Vector3.new(46.66, 1, 79.4625)
			foundation.CFrame, foundation.Parent = CFrame.new(300, 6, -200) * CFrame.Angles(0, math.rad(70), 0), base
			local frame = assert(Presenter.BannerFrame(base))
			local localPoint = foundation.CFrame:PointToObjectSpace(frame.Position)
			expect(localPoint.X < -foundation.Size.X / 2).to.equal(true)
			near(localPoint.Y, foundation.Size.Y / 2)
			expect(localPoint.Z > -foundation.Size.Z / 2).to.equal(true)
			base:Destroy()
		end)
	end)
	describe("Phase14 bounded native trail recipe", function()
		it("clears actual ribbons when ordinary Auto resolves Low and keeps explicit preference precedence", function()
			local Adaptive = require(RS.Shared.Utility.AdaptiveVFXPolicy)
			local Quality = require(RS.Shared.Utility.ResolvedPresentationQuality)
			local TrailController = require(Client.Controllers.Phase14CosmeticController)
			-- This case belongs to the isolated fresh-source fixture runner; never
			-- replace an actual running client's quality publisher for a test.
			expect(TrailController.GetDiagnostics().started).to.equal(false)
			expect(Quality.GetDiagnostics("Auto").publisherActive).to.equal(false)
			local policy = Adaptive.new()
			local owner = Quality.Begin(policy.GetTier())
			local root = Instance.new("Part")
			local handle = assert(Factory.Create("P14_TRAIL_STARFORGE", root, CFrame.new(-2, 0, 4), CFrame.new(2, 0, 4)))
			local ok, failure = xpcall(function()
				-- Same publisher path as Phase12PresentationController.renderSample.
				policy.Step(0, { mode = "High", savedQuality = 1, ready = true, focused = nil })
				expect(Quality.Publish(owner, policy.GetTier())).to.equal(true)
				expect(TrailController.AllowsEffects("High", false)).to.equal(true)
				handle:Update(3, TrailController.AllowsEffects("High", false))
				for _, trail in handle.Trails do expect(trail.Enabled).to.equal(true) end
				policy.Step(1, { mode = "Auto", savedQuality = 1, ready = true, focused = nil })
				expect(policy.GetTier()).to.equal("Low")
				expect(Quality.Publish(owner, policy.GetTier())).to.equal(true)
				expect(TrailController.AllowsEffects("Auto", false)).to.equal(false)
				handle:Update(3, TrailController.AllowsEffects("Auto", false))
				expect(handle.Enabled).to.equal(false)
				for _, trail in handle.Trails do expect(trail.Enabled).to.equal(false) end
				policy.Step(2, { mode = "High", savedQuality = 1, ready = true, focused = nil })
				Quality.Publish(owner, policy.GetTier())
				expect(TrailController.AllowsEffects("High", false)).to.equal(true)
				expect(TrailController.AllowsEffects("Low", false)).to.equal(false)
				expect(TrailController.AllowsEffects("High", true)).to.equal(false)
				expect(TrailController.GetDiagnostics().connections).to.equal(0)
			end, debug.traceback)
			handle:Destroy()
			root:Destroy()
			Quality.Release(owner)
			expect(TrailController.AllowsEffects("Auto", false)).to.equal(false)
			assert(ok, failure)
		end)
		for _, id in { "P14_TRAIL_STARFORGE", "P14_TRAIL_COMET", "P14_TRAIL_OBSIDIAN" } do
			it(
				id .. " creates two inert ribbons with hysteresis and deterministic cleanup, including wheel-free hosts",
				function()
					local root = Instance.new("Part")
					local original = {
						Size = root.Size,
						Massless = root.Massless,
						CanCollide = root.CanCollide,
						Anchored = root.Anchored,
					}
					local handle = assert(Factory.Create(id, root, CFrame.new(-2, 0, 4), CFrame.new(2, 0, 4)))
					expect(#handle.Trails).to.equal(2)
					expect(#root:GetChildren()).to.equal(6)
					for _, trail in handle.Trails do
						expect(trail.Enabled).to.equal(false)
						near((trail.Attachment0.Position - trail.Attachment1.Position).Magnitude, 0.45)
						near(trail.Lifetime, 0.35)
						near(trail.MinLength, 0.08)
						expect(trail.MaxLength).to.equal(8)
						expect(trail.LightEmission).to.equal(0)
						expect(trail.LightInfluence).to.equal(1)
						expect(trail.FaceCamera).to.equal(true)
						near(trail.WidthScale.Keypoints[1].Value, 1)
						near(trail.WidthScale.Keypoints[2].Value, 0)
						near(trail.Transparency.Keypoints[1].Value, 0.12)
						near(trail.Transparency.Keypoints[2].Time, 0.7)
						near(trail.Transparency.Keypoints[3].Value, 1)
					end
					handle:Update(1.99, true)
					expect(handle.Enabled).to.equal(false)
					handle:Update(2, true)
					expect(handle.Enabled).to.equal(true)
					handle:Update(1, true)
					expect(handle.Enabled).to.equal(true)
					handle:Update(0.99, true)
					expect(handle.Enabled).to.equal(false)
					handle:Update(8, true)
					handle:Update(8, false)
					expect(handle.Enabled).to.equal(false)
					handle:Clear()
					handle:Destroy()
					handle:Destroy()
					expect(#root:GetChildren()).to.equal(0)
					for property, value in original do
						expect(root[property]).to.equal(value)
					end
					root:Destroy()
				end
			)
		end
	end)
	describe("Phase14 public base presentation ownership and input", function()
		it(
			"fails closed through owner/revision/readiness replication order and never grants visitor controls",
			function()
				local attrs = { RetentionPublicRevision = 10 }
				local owner = {
					UserId = 8101,
					Parent = Players,
					GetAttribute = function(_, key)
						return attrs[key]
					end,
				}
				local base = Instance.new("Model")
				base:SetAttribute("BasePresentationManaged", true)
				base:SetAttribute("BasePresentationReady", true)
				base:SetAttribute("OwnerUserId", 8101)
				base:SetAttribute("BaseOwnershipRevision", 2)
				base:SetAttribute("BasePresentationState", "1:8101:2:12")
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(true)
				base:SetAttribute("OwnerUserId", 8102)
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(false)
				base:SetAttribute("OwnerUserId", 8101)
				base:SetAttribute("BaseOwnershipRevision", 3)
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(false)
				base:SetAttribute("BasePresentationState", "0:8101:3:0")
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(false)
				base:SetAttribute("BasePresentationState", "1:8101:3:12")
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(true)
				attrs.RetentionPublicRevision = nil
				expect(Public._BaseReadyForTesting(base, owner)).to.equal(false)
				base:Destroy()
			end
		)
		it("keeps short/mobile inspectors inside the safe usable area with a scrollable body", function()
			for _, size in { { 390, 780 }, { 667, 300 }, { 1440, 900 } } do
				local layout = Public._InspectLayoutForTesting(size[1], size[2])
				expect(layout.usable).to.equal(true)
				expect(layout.left >= 12).to.equal(true)
				expect(layout.left + layout.width <= size[1] - 12).to.equal(true)
				expect(layout.top >= 12).to.equal(true)
				expect(layout.top + layout.height <= size[2] - (if size[1] < 900 or size[2] < 600 then 156 else 16)).to.equal(
					true
				)
			end
		end)
		it("suspends existing input only while public inspect owns the panel", function()
			local open = false
			local subject = {
				GetAttribute = function(_, key)
					return key == "RetentionPublicInspectOpen" and open
				end,
			}
			local core = { MenuIsOpen = false, SelectedObject = nil }
			local input = {
				GetFocusedTextBox = function()
					return nil
				end,
			}
			expect(Input.IsMenuOpen(subject, core, input)).to.equal(false)
			open = true
			expect(Input.IsMenuOpen(subject, core, input)).to.equal(true)
			open = false
			expect(Input.IsMenuOpen(subject, core, input)).to.equal(false)
		end)
	end)
end
