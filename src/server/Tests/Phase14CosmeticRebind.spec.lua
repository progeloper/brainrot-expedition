--!nocheck
-- Isolated native templates + actual render adapter. Never grants a real player
-- ownership, edits an approved template, or writes a profile/backend.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Presenter = require(script.Parent.Parent.Utility.Phase14CosmeticPresenter)
	local Schema = require(script.Parent.Parent.Data.PlayerProfileSchema)
	local Fixtures = require(script.Parent.Support.PlayerProfileFixtures)
	local Trail = require(RS.Shared.Utility.Phase14TrailFactory)
	local Geometry = require(RS.Shared.Utility.CartGeometry)
	local function owned()
		local data = Schema.CreateDefault()
		data.Commerce.Entitlements.P14_FLAG_CAMP = true
		data.Commerce.Entitlements.P14_BASE_EXPEDITION = true
		data.Phase13.OwnedCartIds.CRT_007 = true
		data.Commerce.Appearance.Flag = "P14_FLAG_CAMP"
		data.Commerce.Appearance.BaseBanner = "P14_BASE_EXPEDITION"
		data.Commerce.Appearance.Trail = "P14_TRAIL_STARFORGE"
		return data
	end
	local function cartFixture()
		local cart, root = Instance.new("Model"), Instance.new("Part")
		root.Name, root.Parent, root.Anchored = "Root", cart, true
		cart.PrimaryPart = root
		local geometry = assert(Geometry.GetById("CRT_008"))
		cart:SetAttribute("CartGeometryId", geometry.Id)
		cart:SetAttribute("CartGeometryRevision", geometry.Revision)
		cart:SetAttribute("CartGeneration", 1)
		cart:SetAttribute("OwnerUserId", 8101)
		return cart, root
	end
	local function baseFixture()
		local base, foundation = Instance.new("Model"), Instance.new("Part")
		foundation.Name, foundation.Size, foundation.Anchored, foundation.Parent =
			"Foundation", Vector3.new(46.66, 1, 79.46), true, base
		base:SetAttribute("OwnerUserId", 8101)
		base:SetAttribute("BaseOwnershipRevision", 1)
		base:SetAttribute("SelectedBaseDesignId", "BASE_001")
		base:SetAttribute("BasePresentationManaged", true)
		base:SetAttribute("BasePresentationReady", true)
		return base
	end
	describe("Phase14 native presentation ownership and generation rebinding", function()
		it("reports only owned presenter bindings and releases the exact base handles", function()
			local before = Presenter.GetDiagnostics()
			local base, player, data = baseFixture(), { UserId = 8101 }, owned()
			local ok, reason = xpcall(function()
				Presenter.Reconcile(player, data, base, nil)
				local active = Presenter.GetDiagnostics()
				expect(active.baseBindingRecords).to.equal(before.baseBindingRecords + 1)
				expect(active.baseConnections).to.equal(before.baseConnections + 5)
				expect(active.cartBindingRecords).to.equal(before.cartBindingRecords)
				expect(active.retryEntries).to.equal(before.retryEntries)
				expect(active.ownedScheduledTasks).to.equal(0)
				Presenter.ReleaseBase(base)
				local after = Presenter.GetDiagnostics()
				expect(after.baseBindingRecords).to.equal(before.baseBindingRecords)
				expect(after.baseConnections).to.equal(before.baseConnections)
			end, debug.traceback)
			Presenter.ReleaseBase(base)
			base:Destroy()
			assert(ok, reason)
		end)

		it(
			"replaces an old generation and root weld, publishes only its matching trail binding, then clears None",
			function()
				local player, data = { UserId = 8101 }, owned()
				local before = Fixtures.Clone(data)
				local optional = Fixtures.Clone(assert(Geometry.GetById("CRT_008")))
				optional.HarpoonOrigin = nil
				expect(typeof(Presenter.FlagFrame(optional))).to.equal("CFrame")
				local cart = cartFixture()
				local ok, failure = xpcall(function()
					Presenter.Reconcile(player, data, nil, cart)
					local first = assert(cart:FindFirstChild("P14CartFlag"))
					expect(Trail.HasCurrentBinding(cart)).to.equal(true)
					cart:SetAttribute("CartGeneration", 2)
					Presenter.Reconcile(player, data, nil, cart)
					local second = assert(cart:FindFirstChild("P14CartFlag"))
					expect(first.Parent).to.equal(nil)
					expect(second:GetAttribute("P14CartGeneration")).to.equal(2)
					local replacement = Instance.new("Part")
					replacement.Name, replacement.Anchored, replacement.Parent =
						"ReplacementRoot", true, cart
					cart.PrimaryPart = replacement
					Presenter.Reconcile(player, data, nil, cart)
					local third = assert(cart:FindFirstChild("P14CartFlag"))
					expect(second.Parent).to.equal(nil)
					expect(third.PrimaryPart.P14CosmeticWeld.Part0).to.equal(replacement)
					expect(Trail.HasCurrentBinding(cart)).to.equal(true)
					Fixtures.AssertDeepEqual(data, before)
					data.Commerce.Appearance.Flag, data.Commerce.Appearance.Trail = "None", "None"
					Presenter.Reconcile(player, data, nil, cart)
					expect(cart:FindFirstChild("P14CartFlag")).to.equal(nil)
					expect(Trail.HasCurrentBinding(cart)).to.equal(false)
				end, debug.traceback)
				Presenter.ReleaseCart(cart)
				cart:Destroy()
				assert(ok, failure)
			end
		)
		it(
			"rebinds the banner assignment/design and removes the old presentation before owner replacement",
			function()
				local player, data, base = { UserId = 8101 }, owned(), baseFixture()
				local before = Fixtures.Clone(data)
				local ok, failure = xpcall(function()
					Presenter.Reconcile(player, data, base, nil)
					local first = assert(base:FindFirstChild("P14BaseBanner"))
					base:SetAttribute("BaseOwnershipRevision", 2)
					base:SetAttribute("SelectedBaseDesignId", "BASE_002")
					Presenter.Reconcile(player, data, base, nil)
					local second = assert(base:FindFirstChild("P14BaseBanner"))
					expect(first.Parent).to.equal(nil)
					expect(second:GetAttribute("P14AssignmentRevision")).to.equal(2)
					expect(second:GetAttribute("P14BaseDesignId")).to.equal("BASE_002")
					Presenter.ReleaseBase(base)
					expect(second.Parent).to.equal(nil)
					base:SetAttribute("OwnerUserId", 8102)
					local other = { UserId = 8102 }
					Presenter.Reconcile(other, data, base, nil)
					local current = assert(base:FindFirstChild("P14BaseBanner"))
					expect(current:GetAttribute("OwnerUserId")).to.equal(8102)
					-- A queued retry from the former owner must not destroy the new owner's art.
					Presenter.Reconcile(player, data, base, nil)
					expect(base:FindFirstChild("P14BaseBanner")).to.equal(current)
					Fixtures.AssertDeepEqual(data, before)
				end, debug.traceback)
				Presenter.ReleaseBase(base)
				base:Destroy()
				assert(ok, failure)
			end
		)
		it(
			"does not render managed unready bases or let a former cart owner remove another owner's presentation",
			function()
				local data, cart, base = owned(), cartFixture(), baseFixture()
				local current, former = { UserId = 8101 }, { UserId = 8102 }
				local ok, failure = xpcall(function()
					base:SetAttribute("BasePresentationReady", false)
					Presenter.Reconcile(current, data, base, cart)
					expect(base:FindFirstChild("P14BaseBanner")).to.equal(nil)
					local flag = assert(cart:FindFirstChild("P14CartFlag"))
					Presenter.Reconcile(former, data, nil, cart)
					expect(cart:FindFirstChild("P14CartFlag")).to.equal(flag)
					expect(cart:GetAttribute("P14TrailBinding")).to.equal(
						Trail.Binding(cart, "P14_TRAIL_STARFORGE")
					)
				end, debug.traceback)
				Presenter.ReleaseCart(cart)
				Presenter.ReleaseBase(base)
				cart:Destroy()
				base:Destroy()
				assert(ok, failure)
			end
		)
	end)
end
