--!nocheck
-- Local prompt/request-state fixtures, not native UI/control playtests.
return function()
	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local State = require(Client.Utility.BrainrotInteractionState)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config.BrainrotInteraction)

	describe("Current primary interaction versus authored Shop prompts", function()
		local function fixture(callback)
			local root = Instance.new("Folder")
			local function prompt(name, enabled, key)
				local value = Instance.new("ProximityPrompt")
				value.Name, value.Enabled, value.KeyboardKeyCode = name, enabled, key or Enum.KeyCode.E
				value.GamepadKeyCode = Enum.KeyCode.ButtonX
				require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation).Capture(value)
				value.Parent = root
				return value
			end
			local ok, failure = xpcall(function() callback(prompt) end, debug.traceback)
			root:Destroy()
			if not ok then error(failure) end
		end
		it("mutes only current authored shared-key prompts and restores only its enabled ownership", function()
			fixture(function(prompt)
				local shop = prompt("Phase13ShopPrompt", true)
				local base = prompt("Phase13BaseUpgradePrompt", true)
				base:SetAttribute("BaseContent_Enabled", true)
				local disabled = prompt("Phase13ShopPrompt", false)
				local unrelated = prompt("OtherPrompt", true)
				local registry = { [shop] = true, [base] = true, [disabled] = true, [unrelated] = true }
				local muted = {}
				-- A selected but hidden/dwelling primary supplies false; Shop remains available.
				local idle = State.new("shop-dwell")
				idle:TrackShopPriorityKey(Enum.KeyCode.E, true, false)
				expect(idle:HasShopPriority(false)).to.equal(false)
				State.UpdateShopPromptPriority(registry, muted, idle:HasShopPriority(false), function() return true end)
				expect(shop.Enabled).to.equal(true) expect(base.Enabled).to.equal(true)
				idle:ClearShopPriorityKeys()
				State.UpdateShopPromptPriority(registry, muted, true, function() return true end)
				expect(shop.Enabled).to.equal(false) expect(base.Enabled).to.equal(false)
				expect(disabled.Enabled).to.equal(false) expect(unrelated.Enabled).to.equal(true)
				expect(shop:GetAttribute("BaseContent_Enabled")).to.equal(false)
				expect(disabled:GetAttribute("BaseContent_Enabled")).to.equal(nil)
				State.UpdateShopPromptPriority(registry, muted, false, function() return true end)
				expect(shop.Enabled).to.equal(true) expect(base.Enabled).to.equal(true)
				expect(disabled.Enabled).to.equal(false) expect(unrelated.Enabled).to.equal(true)
				expect(next(muted)).to.equal(nil)
				expect(shop:GetAttribute("BaseContent_Enabled")).to.equal(nil)
				expect(base:GetAttribute("BaseContent_Enabled")).to.equal(true)
				expect(shop:GetAttribute("BaseAuthored_Enabled")).to.equal(true)
			end)
		end)
		it("keeps one consumed E or ButtonX press muted after selection and request finish", function()
			local state = State.new("shop-priority")
			expect(state:TrackShopPriorityKey(Enum.KeyCode.W, true, true)).to.equal(false)
			state:TrackShopPriorityKey(Enum.KeyCode.E, true, true)
			state:TrackShopPriorityKey(Enum.KeyCode.ButtonX, true, false)
			local request = state:Begin("Cargo", "owned", nil, nil, "owned", 0)
			state:Finish(request.Token)
			expect(state:HasShopPriority(false)).to.equal(true)
			state:TrackShopPriorityKey(Enum.KeyCode.E, false, false)
			expect(state:HasShopPriority(false)).to.equal(true)
			state:TrackShopPriorityKey(Enum.KeyCode.ButtonX, false, false)
			expect(state:HasShopPriority(false)).to.equal(false)
			-- A native prompt can start the request after the key was first observed.
			state:TrackShopPriorityKey(Enum.KeyCode.E, true, false)
			request = state:Begin("Base", "owned", nil, nil, "owned", 1)
			state:Finish(request.Token)
			expect(state:HasShopPriority(false)).to.equal(true)
			state:ClearShopPriorityKeys()
			expect(state:HasShopPriority(false)).to.equal(false)
		end)
		it("handles late add and removal and never enables a hidden semantic prompt on cleanup", function()
			fixture(function(prompt)
				local registry, muted = {}, {}
				local late = prompt("Phase13ShopPrompt", true)
				local hidden = prompt("Phase13BaseUpgradePrompt", true)
				registry[late], registry[hidden] = true, true
				State.UpdateShopPromptPriority(registry, muted, true, function() return true end)
				expect(late.Enabled).to.equal(false) expect(hidden.Enabled).to.equal(false)
				local parent = late.Parent
				late.Parent, registry[late] = nil, nil
				State.UpdateShopPromptPriority(registry, muted, true, function(value) return value ~= hidden end)
				expect(late.Enabled).to.equal(false) expect(hidden.Enabled).to.equal(false)
				expect(late:GetAttribute("BaseContent_Enabled")).to.equal(nil)
				late.Parent = parent
				-- The existing authored presenter can restore this exact reused instance.
				require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation).ApplyGroup(late, true)
				expect(late.Enabled).to.equal(true)
				State.UpdateShopPromptPriority(registry, muted, false, function(value) return value ~= hidden end)
				expect(hidden.Enabled).to.equal(false) expect(next(muted)).to.equal(nil)
				-- Hidden release clears only our content overlay. RVC still has true
				-- authored content to restore on the next legitimate visible entry.
				expect(hidden:GetAttribute("BaseContent_Enabled")).to.equal(nil)
				expect(require(game:GetService("ReplicatedStorage").Shared.Utility.BaseSlotPresentation).GetAuthoredProperty(hidden, "Enabled")).to.equal(true)
				-- No retained helper signal/task can later rewrite an unrelated value.
				late.Enabled = false
				State.UpdateShopPromptPriority({}, muted, false, function() return true end)
				expect(late.Enabled).to.equal(false)
				local destroyed = prompt("Phase13ShopPrompt", true)
				registry = { [destroyed] = true }
				State.UpdateShopPromptPriority(registry, muted, true, function() return true end)
				destroyed:Destroy()
				registry[destroyed] = nil
				State.UpdateShopPromptPriority(registry, muted, false, function() return true end)
				expect(next(muted)).to.equal(nil)
			end)
		end)
	end)

	describe("Platform-only local prompt dwell", function()
		it("stays hidden at 1.99 seconds and becomes visible at 2.00", function()
			local state = State.new("dwell")
			expect(state:PlatformPromptReady("A", "character", true, 0)).to.equal(false)
			expect(state:PlatformPromptReady("A", "character", true, 1.99)).to.equal(false)
			expect(state:PlatformPromptReady("A", "character", true, 2)).to.equal(true)
		end)
		it("resets on ineligibility, switching platforms and character replacement", function()
			local state = State.new("dwell")
			state:PlatformPromptReady("A", "character", true, 0)
			expect(state:PlatformPromptReady("A", "character", false, 1)).to.equal(false)
			expect(state:PlatformPromptReady("A", "character", true, 2)).to.equal(false)
			expect(state:PlatformPromptReady("A", "character", true, 4)).to.equal(true)
			expect(state:PlatformPromptReady("B", "character", true, 4)).to.equal(false)
			expect(state:PlatformPromptReady("B", "character", true, 6)).to.equal(true)
			expect(state:PlatformPromptReady("B", "respawn", true, 6)).to.equal(false)
		end)
		it(
			"never shares dwell with another player and uses the platform front half-space",
			function()
				local a, b = State.new("A"), State.new("B")
				a:PlatformPromptReady("platform", "char", true, 0)
				expect(a:PlatformPromptReady("platform", "char", true, 2)).to.equal(true)
				expect(b:PlatformPromptReady("platform", "char", true, 2)).to.equal(false)
				local cf = CFrame.Angles(0, math.rad(90), 0)
				expect(State.IsPlatformFront(cf, cf.LookVector * 5)).to.equal(true)
				expect(State.IsPlatformFront(cf, -cf.LookVector * 5)).to.equal(false)
			end
		)
	end)

	describe("Task C request finalization", function()
		it(
			"serializes intents and never lets an old reply/timeout clear a new same-item action",
			function()
				local state = State.new("session")
				local old = state:Begin("Cargo", "same-id", nil, nil, "same-id", 0)
				expect(state:Begin("Cargo", "same-id", nil, nil, "same-id", 1)).to.equal(nil)
				expect(state:Expire(1.99)).to.equal(false)
				expect(state:Expire(2)).to.equal(true)
				local current = state:Begin("Cargo", "same-id", nil, nil, "same-id", 2.1)
				expect(current.Token == old.Token).to.equal(false)
				expect(state:Finish(old.Token)).to.equal(false)
				expect(state.Pending).to.equal(current)
				expect(state:Finish(current.Token)).to.equal(true)
				expect(state.Pending).to.equal(nil)
			end
		)
		it(
			"uses the same terminal path for rejection/cancellation and keeps player sessions independent",
			function()
				local first, second = State.new("first"), State.new("second")
				for _, kind in { "Cargo", "Pickup", "Replace", "Base", "Drop" } do
					local a = first:Begin(kind, "id", nil, nil, nil, 0)
					local b = second:Begin(kind, "id", nil, nil, nil, 0)
					expect(second:Finish(a.Token)).to.equal(false)
					expect(first:Finish(a.Token)).to.equal(true)
					expect(second.Pending).to.equal(b)
					expect(second:Finish(b.Token)).to.equal(true)
				end
			end
		)
	end)

	describe("Task C stable selection", function()
		it("sends the carried ID for replacement, never the occupied slot ID", function()
			local context = { Action = "Replace", CarryId = "incoming", Occupant = "outgoing" }
			expect(State.RequestItemId(context)).to.equal("incoming")
			expect(State.IsPickup(context)).to.equal(false)
			local state = State.new("replacement")
			local request =
				state:Begin("Replace", State.RequestItemId(context), nil, nil, "incoming", 0)
			expect(request.ItemId).to.equal("incoming") -- Server echoes the incoming ID.
		end)
		it("preserves cargo and base placement/pickup request identities", function()
			for _, context in
				{
					{ Action = "Cargo", CarryId = "incoming", Expected = "incoming" },
					{ Action = "Pickup", Occupant = "outgoing", Expected = "outgoing" },
					{ Action = "Base", CarryId = "incoming", Expected = "incoming" },
					{ Action = "Base", Occupant = "outgoing", Expected = "outgoing" },
				}
			do
				expect(State.RequestItemId(context)).to.equal(context.Expected)
			end
			expect(State.RequestItemId({ Action = "Replace", Occupant = "outgoing" })).to.equal(nil)
		end)
		it("refreshes physics-only range changes without pointer or property events", function()
			local heartbeat = Instance.new("BindableEvent")
			local distance, selected, count = 20, nil, 0
			local connection = State.WatchSpatialContext(heartbeat.Event, function()
				count += 1
				selected = State.Choose(
					if distance <= 14
						then {
							{ Target = "slot", Distance = distance, Key = "slot" },
						}
						else {},
					selected,
					nil,
					false
				)
			end)
			local function step(dt)
				heartbeat:Fire(dt)
				task.wait()
			end
			step(0.05)
			expect(count).to.equal(0)
			distance = 8.3 -- Humanoid motion does not emit CFrame change events.
			step(0.05)
			expect(selected.Target).to.equal("slot")
			distance = 20 -- Leaving also releases competing pickup/seat prompts.
			step(0.1)
			expect(selected).to.equal(nil)
			distance = 8
			step(5) -- No catch-up refresh loop after a stall.
			expect(count).to.equal(3)
			expect(selected.Target).to.equal("slot")
			connection:Disconnect()
			step(0.1)
			expect(count).to.equal(3)
			heartbeat:Destroy()
		end)
		it("only offers replacement when the complete permitted cart is full", function()
			expect(State.CargoAction(true, true, false)).to.equal(nil)
			expect(State.CargoAction(true, false, false)).to.equal("Cargo")
			expect(State.CargoAction(true, true, true)).to.equal("Replace")
			expect(State.CargoAction(false, true, false)).to.equal("Pickup")
			expect(State.CargoAction(false, false, false)).to.equal(nil)
		end)
		it("breaks numeric slot ties in numeric rather than lexical order", function()
			local a =
				{ Target = "Slot2", SlotIndex = 2, Cart = "cart", Distance = 10, Key = "Slot2" }
			local b =
				{ Target = "Slot10", SlotIndex = 10, Cart = "cart", Distance = 10, Key = "Slot10" }
			expect(State.Choose({ b, a }, nil, nil, false)).to.equal(a)
		end)
		local function candidate(id, distance)
			return { Target = id, Distance = distance, Key = id }
		end
		it(
			"selects without an exact pointer hit and breaks equal-distance ties deterministically",
			function()
				local a, b = candidate("Slot1", 10), candidate("Slot2", 10)
				expect(State.Choose({ b, a }, nil, nil, false)).to.equal(a)
			end
		)
		it(
			"retains a valid slot across small motion but switches for a clearly nearer one",
			function()
				local a, b = candidate("Slot1", 10), candidate("Slot2", 11)
				expect(State.Choose({ a, b }, b, nil, false)).to.equal(b)
				b.Distance = 12.01
				expect(State.Choose({ a, b }, b, nil, false)).to.equal(a)
			end
		)
		it(
			"honours optional deliberate selection and locks a valid hold to its selected slot",
			function()
				local a, b = candidate("Slot1", 5), candidate("Slot2", 12)
				expect(State.Choose({ a, b }, a, "Slot2", false)).to.equal(b)
				expect(State.Choose({ a, b }, b, "Slot1", true)).to.equal(b)
				expect(State.Choose({ a }, b, nil, true)).to.equal(a)
				expect(State.Choose({}, a, nil, false)).to.equal(nil)
			end
		)
	end)

	describe("Task C persistent local prompts", function()
		local function fixture(test)
			local part = Instance.new("Part")
			local marker = Instance.new("Attachment")
			marker.Name, marker.Parent = "CargoAttachment", part
			local entry = { Target = part, Marker = marker, Kind = "Cargo" }
			local ok, failure = xpcall(function()
				test(entry, part)
			end, debug.traceback)
			State.RemovePrompt(entry)
			part:Destroy()
			assert(ok, failure)
		end
		local function noop() end
		it("uses compact platform-only views with immediate activation and cleans them", function()
			fixture(function(entry, part)
				local parent = Instance.new("Folder")
				parent.Parent = part
				entry.Kind = "Base"
				local prompt = State.EnsurePrompt(entry, noop, noop, noop)
				expect(prompt.Style).to.equal(Enum.ProximityPromptStyle.Custom)
				expect(prompt.HoldDuration).to.equal(0)
				prompt.Enabled, entry.Shown = true, true
				State.UpdatePlatformView(entry, parent, false, false)
				local view = entry.PlatformView
				expect(view.Size).to.equal(UDim2.fromOffset(150, 48))
				expect(view.Enabled).to.equal(true)
				State.UpdatePlatformView(entry, parent, true, false)
				expect(view.Size).to.equal(UDim2.fromOffset(180, 56))
				prompt.Enabled = false
				State.UpdatePlatformView(entry, parent, true, false)
				expect(view.Enabled).to.equal(false)
				State.RemovePrompt(entry)
				expect(view.Parent).to.equal(nil)
				entry.Kind = "Cargo"
				local cargo = State.EnsurePrompt(entry, noop, noop, noop)
				expect(cargo.Style).to.equal(Enum.ProximityPromptStyle.Default)
				State.UpdatePlatformView(entry, parent, true, false)
				expect(entry.PlatformView).to.equal(nil)
			end)
		end)
		it("refreshes platform text and input modes immediately while retaining one owned view", function()
			fixture(function(entry, part)
				local parent = Instance.new("Folder")
				parent.Parent = part
				entry.Kind = "Base"
				local prompt = State.EnsurePrompt(entry, noop, noop, noop)
				prompt.Enabled, entry.Shown = true, true
				State.UpdatePlatformView(entry, parent, false, false)
				local view, listeners = entry.PlatformView, entry.PlatformViewConnections
				local descendantCount = #view:GetDescendants()
				for _ = 1, 20 do State.UpdatePlatformView(entry, parent, false, false) end
				expect(entry.PlatformView).to.equal(view)
				expect(entry.PlatformViewConnections).to.equal(listeners)
				expect(#view:GetDescendants()).to.equal(descendantCount)
				expect(#listeners).to.equal(2)
				prompt.ActionText, prompt.ObjectText = "Pick up", "Slot12"
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Action.ActionText.Text).to.equal("Pick up")
				expect(view.Action.ObjectText.Text).to.equal("Slot12")
				State.UpdatePlatformView(entry, parent, false, true)
				expect(view.Action.Key.Text).to.equal("X")
				State.UpdatePlatformView(entry, parent, true, true)
				expect(view.Action.Key.Text).to.equal("•")
				expect(view.Size).to.equal(UDim2.fromOffset(180, 56))
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Action.Key.Text).to.equal("E")
				expect(view.Size).to.equal(UDim2.fromOffset(150, 48))
				entry.Shown = false
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Enabled).to.equal(false)
				entry.Shown = true
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Enabled).to.equal(true)
				view.Enabled = false -- An immediate owned hide must not poison a matching snapshot.
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Enabled).to.equal(true)
				prompt.Enabled = false
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Enabled).to.equal(false)
				prompt.Enabled = true
				State.UpdatePlatformView(entry, parent, false, false)
				expect(view.Enabled).to.equal(true)
				for _, connection in listeners do expect(connection.Connected).to.equal(true) end
				State.RemovePrompt(entry)
				for _, connection in listeners do expect(connection.Connected).to.equal(false) end
			end)
		end)
		it("rebuilds destroyed or reparented platform views without retaining old listeners", function()
			fixture(function(entry, part)
				local parent, replacement = Instance.new("Folder"), Instance.new("Folder")
				parent.Parent, replacement.Parent = part, part
				entry.Kind = "Base"
				local prompt = State.EnsurePrompt(entry, noop, noop, noop)
				prompt.Enabled, entry.Shown = true, true
				for i = 1, 3 do
					State.UpdatePlatformView(entry, parent, false, false)
					local view, listeners = entry.PlatformView, entry.PlatformViewConnections
					expect(view.ResetOnSpawn).to.equal(false)
					expect(#listeners).to.equal(2)
					if i == 1 then view:Destroy() elseif i == 2 then view.Action:Destroy() else view.Parent = replacement end
					State.UpdatePlatformView(entry, parent, false, true)
					expect(entry.PlatformView ~= view).to.equal(true)
					expect(entry.PlatformView.Action.Key.Text).to.equal("X")
					expect(entry.PlatformView.Enabled).to.equal(true)
					for _, connection in listeners do expect(connection.Connected).to.equal(false) end
					expect(#entry.PlatformViewConnections).to.equal(2)
				end
				local connections = entry.PlatformViewConnections
				State.RemovePrompt(entry)
				for _, connection in connections do expect(connection.Connected).to.equal(false) end
				expect(entry.PlatformViewConnections).to.equal(nil)
			end)
		end)
		it(
			"retains one prompt and listener set through five exits/reentries and visual rebuilds",
			function()
				fixture(function(entry, part)
					local prompt = State.EnsurePrompt(entry, noop, noop, noop)
					local listeners = entry.PromptConnections
					for _ = 1, 5 do
						prompt.Enabled = false
						local visual = Instance.new("Model")
						visual.Name, visual.Parent = "DisposableCargoVisual", part
						visual:Destroy()
						expect(State.EnsurePrompt(entry, noop, noop, noop)).to.equal(prompt)
						expect(entry.PromptConnections).to.equal(listeners)
						prompt.Enabled = true
					end
					expect(#entry.Marker:GetChildren()).to.equal(1)
					expect(#listeners).to.equal(5) -- One Triggered plus four presentation/hold listeners.
					expect(prompt.Parent).to.equal(entry.Marker)
				end)
			end
		)
		it("uses one 14-stud non-native-LOS placement prompt for cargo and bases", function()
			fixture(function(entry)
				local cargo = State.EnsurePrompt(entry, noop, noop, noop)
				expect(cargo.MaxActivationDistance).to.equal(14)
				expect(cargo.RequiresLineOfSight).to.equal(false)
				expect(Config.PLACEMENT_INTERACT_RADIUS + Config.PLACEMENT_SERVER_TOLERANCE).to.equal(
					16
				)
				State.RemovePrompt(entry)
				entry.Kind = "Base"
				local base = State.EnsurePrompt(entry, noop, noop, noop)
				expect(base.MaxActivationDistance).to.equal(14)
				expect(base.RequiresLineOfSight).to.equal(false)
			end)
		end)
		it(
			"cleans only its prompt/listeners and rebinds once when the actual anchor changes",
			function()
				fixture(function(entry, part)
					local old = State.EnsurePrompt(entry, noop, noop, noop)
					local listeners = entry.PromptConnections
					local marker = Instance.new("Attachment")
					marker.Parent = part
					entry.Marker = marker
					local new = State.EnsurePrompt(entry, noop, noop, noop)
					expect(old.Parent).to.equal(nil)
					expect(new.Parent).to.equal(marker)
					for _, connection in listeners do
						expect(connection.Connected).to.equal(false)
					end
					State.RemovePrompt(entry)
					expect(#marker:GetChildren()).to.equal(0)
					expect(marker.Parent).to.equal(part)
				end)
			end
		)
	end)
end
