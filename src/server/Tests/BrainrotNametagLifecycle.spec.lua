--!strict

return function()
	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local Config = require(ReplicatedStorage.Shared.Config.BrainrotDisplayConfig)
	local Metadata = require(ReplicatedStorage.Shared.Utility.BrainrotDisplayMetadata)
	local View = require(ReplicatedStorage.Shared.UI.BrainrotNametagView)

	local function expectTweenCompleted(tween: Tween?)
		assert(tween ~= nil, "expected the production focus tween")
		local completedState: Enum.PlaybackState? = nil
		local connection = tween.Completed:Connect(function(state)
			completedState = state
		end)
		if
			tween.PlaybackState == Enum.PlaybackState.Completed
			or tween.PlaybackState == Enum.PlaybackState.Cancelled
		then
			completedState = tween.PlaybackState
		end
		-- A timeout bounds a broken tween; it is not timing padding for the assertion.
		local deadline = os.clock() + 2
		while completedState == nil and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end
		connection:Disconnect()
		expect(completedState).to.equal(Enum.PlaybackState.Completed)
	end

	describe("Brainrot lifecycle nametag presentation", function()
		it("uses the one tagged metadata contract for every authoritative display owner", function()
			local model = Instance.new("Model")
			local record = {
				ItemId = "individual-1",
				BrainrotId = "BRT_007",
				Metadata = { MutationId = "future-mutation" },
			}

			Metadata.Apply(model, record, Config.States.Sleeping, nil)
			expect(CollectionService:HasTag(model, Config.CollectionTag)).to.equal(true)
			expect(model:GetAttribute(Config.Attributes.BrainrotId)).to.equal("BRT_007")
			expect(model:GetAttribute(Config.Attributes.MutationId)).to.equal("future-mutation")
			expect(model:GetAttribute(Config.Attributes.DisplayState)).to.equal("Sleeping")

			Metadata.Apply(model, record, Config.States.Carried, 321)
			expect(model:GetAttribute(Config.Attributes.CarrierUserId)).to.equal(321)
			expect(model:GetAttribute(Config.Attributes.DisplayState)).to.equal("Carried")

			Metadata.Clear(model)
			expect(CollectionService:HasTag(model, Config.CollectionTag)).to.equal(false)
			expect(model:GetAttribute(Config.Attributes.DisplayState)).to.equal(nil)
			expect(model:GetAttribute(Config.Attributes.CarrierUserId)).to.equal(nil)
			model:Destroy()
		end)

		it("renders the exact awake, asleep, carried, cart and deposited variants", function()
			local playerGui = Instance.new("Folder") :: any
			local model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Name = "Body"
			part.Size = Vector3.new(2, 4, 2)
			part.Parent = model
			model.PrimaryPart = part

			local view = View.create(playerGui, model, part, {
				displayName = "Tung Tung Turnip",
				rarity = "Common",
				cashPerSecond = 2,
			}, Config.States.Awake)
			expect(view.Gui.Size).to.equal(UDim2.fromScale(4.2, 1.55))
			expect(view.Gui.MaxDistance).to.equal(55)
			expect(view.Gui.StudsOffsetWorldSpace.Y).to.equal(
				model:GetExtentsSize().Y / 2 + Config.Billboard.VerticalOffset
			)
			expect(Config.Billboard.VerticalOffset).to.equal(1.25)
			expect(view.IncomeLabel.Visible).to.equal(true)
			expect(view.BadgeRow.Visible).to.equal(false)

			View.updateState(view, Config.States.Sleeping, nil)
			expect(view.Gui.Size).to.equal(UDim2.fromScale(4.2, 1.82))
			expect(view.Gui.MaxDistance).to.equal(55)
			expect(view.StateLabel.Text).to.equal("ASLEEP")
			expect(view.StateLabel.Font).to.equal(Enum.Font.FredokaOne)
			expect(view.StateLabel.TextSize).to.equal(18)
			expect(view.StateBadge.BackgroundColor3).to.equal(Color3.fromRGB(54, 200, 255))
			expect(view.StateBadge.Size.Y.Offset).to.equal(28)
			expect(view.StateBadge.UIPadding.PaddingLeft.Offset).to.equal(8)
			expect(view.StateBadge.UIPadding.PaddingTop.Offset).to.equal(3)
			expect(view.StateBadge.UICorner.CornerRadius).to.equal(UDim.new(0, 6))
			expect(view.StateBadge.UIStroke.Color).to.equal(Color3.fromRGB(0, 0, 0))
			expect(view.StateBadge.UIStroke.Thickness).to.equal(2)
			expect(view.StateLabel.UIStroke.Color).to.equal(Color3.fromRGB(0, 0, 0))
			expect(view.StateLabel.UIStroke.Thickness).to.equal(2)
			expect(view.BadgeRow.Size).to.equal(UDim2.fromScale(1, Config.Layout.BadgeHeightScale))
			expect(view.BadgeRow.Visible).to.equal(true)
			task.wait(0.35)
			expect(view.Scale.Scale).to.equal(1)

			View.updateState(view, Config.States.Carried, 321)
			expect(view.Gui.Size).to.equal(UDim2.fromScale(3.6, 0.95))
			expect(view.Gui.MaxDistance).to.equal(20)
			expect(math.abs(view.NameLabel.Size.Y.Scale - 0.6) < 0.0001).to.equal(true)
			expect(math.abs(view.RankLabel.Size.Y.Scale - 0.4) < 0.0001).to.equal(true)
			expect(view.IncomeLabel.Visible).to.equal(false)
			expect(view.StateBadge.Visible).to.equal(false)

			View.updateState(view, Config.States.Cart, nil)
			expect(view.Gui.Size).to.equal(UDim2.fromScale(3.8, 1.35))
			expect(view.Gui.MaxDistance).to.equal(26)
			expect(view.IncomeLabel.Visible).to.equal(true)

			View.updateState(view, Config.States.Deposited, nil)
			expect(view.Gui.Size).to.equal(UDim2.fromScale(4.2 * 0.7, 1.55 * 0.7))
			expect(view.Gui.MaxDistance).to.equal(35)
			expect(view.StateBadge.Visible).to.equal(false)

			View.destroy(view)
			model:Destroy()
			playerGui:Destroy()
		end)

		it("clears wild sleep and HP presentation on every nonwild transition", function()
			local playerGui = Instance.new("Folder") :: any
			local model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Name = "Body"
			part.Parent = model
			model.PrimaryPart = part
			local view = View.create(playerGui, model, part, {
				displayName = "Tung Tung Tung Sahur",
				rarity = "Common",
				cashPerSecond = 2,
			}, Config.States.Awake)
			local ok, failure = xpcall(function()
				for _, state in { Config.States.Carried, Config.States.Cart, Config.States.Deposited } do
					View.updateState(view, Config.States.Sleeping, nil)
					View.updateCombat(view, { sleeping = true, countdown = "ASLEEP 8.9", waking = false }, true, true)
					expect(view.HealthArea.Visible).to.equal(true)
					expect(view.HealthLabel.Text).to.equal("ASLEEP 8.9")
					View.updateState(view, state, 321)
					expect(view.DisplayState).to.equal(state)
					expect(view.HealthArea.Visible).to.equal(false)
					expect(view.HealthTarget).to.equal(nil)
				end
				View.updateState(view, Config.States.Awake, nil)
				View.updateCombat(view, { sleeping = false, fraction = 0.75, text = "3 / 4", color = "Green" }, true, true)
				View.updateCombat(view, { sleeping = false, fraction = 0.25, text = "1 / 4", color = "Red" }, true, false)
				local oldTween = assert(view.HealthTween, "Expected an actual in-progress HP tween")
				View.updateState(view, Config.States.Cart, nil)
				expect(view.HealthArea.Visible).to.equal(false)
				expect(view.HealthTween).to.equal(nil)
				expect(view.HealthTarget).to.equal(nil)
				expect(oldTween.PlaybackState).to.equal(Enum.PlaybackState.Cancelled)
				View.updateState(view, Config.States.Awake, nil)
				View.updateCombat(view, { sleeping = false, fraction = 0.5, text = "2 / 4", color = "Amber" }, true, true)
				expect(view.HealthArea.Visible).to.equal(true)
				expect(view.HealthLabel.Text).to.equal("2 / 4")
			end, debug.traceback)
			View.destroy(view)
			model:Destroy()
			playerGui:Destroy()
			assert(ok, failure)
		end)

		it("orders mutation before asleep and collapses the badge row when empty", function()
			local playerGui = Instance.new("Folder") :: any
			local model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Parent = model
			model.PrimaryPart = part
			local view = View.create(playerGui, model, part, {
				displayName = "Tung Tung Turnip",
				rarity = "Common",
				cashPerSecond = 2,
			}, Config.States.Sleeping)

			View.setMutation(view, {
				displayName = "future",
				backgroundColor = Color3.fromRGB(180, 60, 255),
			})
			expect(view.MutationBadge.LayoutOrder).to.equal(1)
			expect(view.StateBadge.LayoutOrder).to.equal(2)
			expect(view.BadgeRow.UIListLayout.Padding.Offset).to.equal(6)
			expect(view.BadgeRow.Visible).to.equal(true)
			expect(view.MutationLabel.Text).to.equal("FUTURE")
			expect(view.MutationBadge.BackgroundColor3).to.equal(Color3.fromRGB(180, 60, 255))
			expect(view.MutationLabel.TextColor3).to.equal(Color3.fromRGB(255, 255, 255))
			View.updateState(view, Config.States.Awake, nil)
			View.setMutation(view, nil)
			expect(view.BadgeRow.Visible).to.equal(false)
			expect(view.BadgeRow.Size.Y.Scale).to.equal(0)

			View.destroy(view)
			model:Destroy()
			playerGui:Destroy()
		end)

		it("applies one restrained focus tween and restores exact permanent strokes", function()
			local playerGui = Instance.new("Folder") :: any
			local model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Parent = model
			model.PrimaryPart = part
			local view = View.create(playerGui, model, part, {
				displayName = "Tung Tung Turnip",
				rarity = "Common",
				cashPerSecond = 2,
			}, Config.States.Awake)

			local originalScale = view.Scale.Scale
			local originalNameStroke = view.NameLabel.UIStroke.Thickness
			local originalRankStroke = view.RankLabel.UIStroke.Thickness
			local originalIncomeStroke = view.IncomeLabel.UIStroke.Thickness
			local ok, failure = xpcall(function()
				View.setFocused(view, true)
				expect(view.NameLabel.UIStroke.Thickness).to.equal(3.5)
				expect(view.RankLabel.UIStroke.Thickness).to.equal(3)
				expect(view.IncomeLabel.UIStroke.Thickness).to.equal(3.5)
				expectTweenCompleted(view.FocusTween)
				expect(math.abs(view.Scale.Scale - 1.06) < 0.0001).to.equal(true)
				View.setFocused(view, false)
				expect(view.NameLabel.UIStroke.Thickness).to.equal(originalNameStroke)
				expect(view.RankLabel.UIStroke.Thickness).to.equal(originalRankStroke)
				expect(view.IncomeLabel.UIStroke.Thickness).to.equal(originalIncomeStroke)
				expectTweenCompleted(view.FocusTween)
				expect(view.Scale.Scale).to.equal(originalScale)
			end, debug.traceback)

			View.destroy(view)
			model:Destroy()
			playerGui:Destroy()
			assert(ok, failure)
		end)

		it("uses only a supplied authoritative effective rate and otherwise falls back", function()
			local playerGui = Instance.new("Folder") :: any
			local model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Parent = model
			model.PrimaryPart = part
			local view = View.create(playerGui, model, part, {
				displayName = "Tung Tung Turnip",
				rarity = "Common",
				cashPerSecond = 2,
			}, Config.States.Awake)
			expect(view.IncomeLabel.Text).to.equal("$2/s")
			View.updateData(view, {
				displayName = "Tung Tung Turnip",
				rarity = "Common",
				cashPerSecond = 2,
				effectiveCashPerSecond = 7,
			})
			expect(view.IncomeLabel.Text).to.equal("$7/s")

			View.destroy(view)
			model:Destroy()
			playerGui:Destroy()
		end)
	end)
end
