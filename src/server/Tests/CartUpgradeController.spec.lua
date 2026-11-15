--!nocheck

return function()
	local Controller = require(
		game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.CartUpgradeController
	)
	local Phase12 = require(game:GetService("ReplicatedStorage").Shared.Config.Phase12)

	local function signal()
		local listeners = {}
		local event = {}
		function event:Connect(callback)
			listeners[callback] = true
			return {
				Disconnect = function()
					listeners[callback] = nil
				end,
			}
		end
		function event:Fire(...)
			for callback in listeners do
				callback(...)
			end
		end
		function event:Count()
			local count = 0
			for _ in listeners do
				count += 1
			end
			return count
		end
		return event
	end

	local function card(id, available)
		return {
			offerId = id,
			title = "Cargo I",
			effectSummary = "+1 cargo slot",
			ownershipSummary = "Applies to all your carts",
			price = 500,
			priceText = "$500",
			currencyId = "Cash",
			requirementLines = { "No progression prerequisite" },
			state = if available then "Available" else "Unavailable",
			primaryExplanation = if available then nil else "The gameplay effect is not ready.",
			actionLabel = if available then "Buy" else "Unavailable",
			canActivate = available,
		}
	end

	local function payload(available)
		return {
			contextId = "context-ui",
			expiresAtServerTime = 220,
			balance = 1000.5,
			offers = { card("FIXTURE_A", available) },
		}
	end

	-- Records what the controller asks of its (optional) view. The real one is UI/Screens/CargoBayScreen.
	local function fakeView()
		local calls = { open = 0, update = 0, close = 0, notify = {} }
		local view = { Calls = calls, Context = nil }
		function view.open(viewContext)
			calls.open += 1
			view.Context = viewContext
		end
		function view.update()
			calls.update += 1
		end
		function view.notify(kind, text)
			table.insert(calls.notify, { Kind = kind, Text = text })
		end
		function view.close()
			calls.close += 1
		end
		return view
	end

	local function fixture(callback, options)
		Controller.Stop()
		local playerGui = Instance.new("Folder")
		playerGui.Name = "SPEC_CART_UPGRADE_GUI"
		playerGui.Parent = game:GetService("CoreGui")
		local openEvent, updateEvent, inputEvent = signal(), signal(), signal()
		local requests, closes, delays, spawned, warnings = {}, {}, {}, {}, {}
		local response = {
			ok = true,
			outcome = "Accepted",
			code = "PURCHASE_ACCEPTED",
			requestId = "request-1",
			offerId = "FIXTURE_A",
			chargedAmount = 500,
			balance = 500.5,
			commitRevision = 4,
			persistence = "Pending",
		}
		local immediate = true
		local requestRemote = {}
		function requestRemote:InvokeServer(request)
			table.insert(requests, request)
			return response
		end
		local closeRemote = {}
		function closeRemote:FireServer(contextId)
			table.insert(closes, contextId)
		end
		local requestSequence = 0
		Controller.Init({
			Player = {},
			PlayerGui = playerGui,
			OpenRemote = { OnClientEvent = openEvent },
			RequestRemote = requestRemote,
			CloseRemote = closeRemote,
			UpdateRemote = { OnClientEvent = updateEvent },
			InputBegan = inputEvent,
			Now = function()
				return 100
			end,
			GenerateRequestId = function()
				requestSequence += 1
				return "request-" .. requestSequence
			end,
			Spawn = function(run)
				if immediate then
					run()
				else
					table.insert(spawned, run)
				end
			end,
			Delay = function(seconds, run)
				table.insert(delays, { Seconds = seconds, Run = run })
			end,
			Warn = function(message)
				table.insert(warnings, message)
			end,
			-- nil = headless (no PlayerGui / Plate kit needed)
			View = options and options.View or nil,
			ProgressRemote = options and options.ProgressRemote or nil,
		})
		assert(Controller.Start())
		local ok, problem = xpcall(function()
			callback({
				Open = openEvent,
				Update = updateEvent,
				Input = inputEvent,
				Requests = requests,
				Closes = closes,
				Delays = delays,
				Spawned = spawned,
				Warnings = warnings,
				SetImmediate = function(value)
					immediate = value
				end,
				SetResponse = function(value)
					response = value
				end,
				RunSpawn = function()
					local run = table.remove(spawned, 1)
					assert(run, "expected queued request")
					run()
				end,
			})
		end, debug.traceback)
		Controller.Stop()
		playerGui:Destroy()
		assert(ok, problem)
	end

	describe("Phase 7B-2 cart upgrade controller", function()
		it("keeps server-owned offer data for the view and runs headless without one", function()
			fixture(function(context)
				context.Open:Fire(payload(false))
				local state = Controller._TestGetState()
				local cardRefs = state.Cards.FIXTURE_A
				expect(state.View).to.equal(nil)
				expect(state.State).to.equal("Open")
				expect(state.Context.contextId).to.equal("context-ui")
				expect(#state.Offers).to.equal(1)
				expect(state.Offers[1]).to.equal(cardRefs.Card)
				expect(cardRefs.Card.title).to.equal("Cargo I")
				expect(cardRefs.Card.effectSummary).to.equal("+1 cargo slot")
				expect(cardRefs.Card.ownershipSummary).to.equal("Applies to all your carts")
				expect(cardRefs.Card.priceText).to.equal("$500")
				expect(cardRefs.Card.requirementLines[1]).to.equal("No progression prerequisite")
				expect(cardRefs.Card.primaryExplanation).to.equal("The gameplay effect is not ready.")
				expect(cardRefs.Card.actionLabel).to.equal("Unavailable")
				expect(cardRefs.Card.canActivate).to.equal(false)
				expect(state.BalanceText).to.equal("Cash $1,000.5")
				expect(state.Status).to.equal("")
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(0)
				expect(#context.Warnings).to.equal(0)
			end)
		end)

		it("drives an attached view through its snapshot and callbacks", function()
			local view = fakeView()
			fixture(function(context)
				context.Open:Fire(payload(true))
				expect(view.Calls.open).to.equal(1)
				local snapshot = view.Context.snapshot()
				expect(snapshot.contextId).to.equal("context-ui")
				expect(snapshot.balanceText).to.equal("Cash $1,000.5")
				expect(#snapshot.offers).to.equal(1)
				expect(snapshot.offers[1].offerId).to.equal("FIXTURE_A")
				expect(snapshot.offers[1].canActivate).to.equal(true)
				expect(snapshot.busy).to.equal(false)
				view.Context.pressBegan()
				view.Context.pressMoved()
				view.Context.buy("FIXTURE_A")
				expect(#context.Requests).to.equal(0)
				view.Context.pressBegan()
				view.Context.buy("FIXTURE_A")
				expect(#context.Requests).to.equal(1)
				expect(context.Requests[1].operation).to.equal("Purchase")
				expect(view.Calls.update > 0).to.equal(true)
				local last = view.Calls.notify[#view.Calls.notify]
				expect(last.Kind).to.equal("accepted")
				expect(last.Text).to.equal("Owned • Saving…")
				snapshot = view.Context.snapshot()
				expect(snapshot.offers[1].state).to.equal("Owned")
				expect(snapshot.status).to.equal("Owned • Saving…")
				view.Context.close()
				expect(view.Calls.close).to.equal(1)
				expect(#context.Closes).to.equal(1)
				expect(context.Closes[1]).to.equal("context-ui")
				expect(view.Context.snapshot()).to.equal(nil)
				expect(Controller._TestGetState().State).to.equal("Closed")
			end, { View = view })
		end)

		it("uses one deliberate activation and reconciles the authoritative result", function()
			fixture(function(context)
				context.Open:Fire(payload(true))
				Controller._TestActivate("FIXTURE_A")
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(1)
				expect(context.Requests[1].operation).to.equal("Purchase")
				expect(context.Requests[1].contextId).to.equal("context-ui")
				expect(context.Requests[1].offerId).to.equal("FIXTURE_A")
				expect(context.Requests[1].price).to.equal(nil)
				local state = Controller._TestGetState()
				expect(state.State).to.equal("Open")
				expect(state.Pending).to.equal(nil)
				expect(state.Cards.FIXTURE_A.Card.state).to.equal("Owned")
				expect(state.Cards.FIXTURE_A.Card.canActivate).to.equal(false)
				expect(state.Cards.FIXTURE_A.Card.actionLabel).to.equal("Owned")
				expect(state.BalanceText).to.equal("Cash $500.5")
				expect(state.Status).to.equal("Owned • Saving…")
				context.Update:Fire({
					kind = "PurchasePersistence",
					requestId = "request-1",
					offerId = "FIXTURE_A",
					commitRevision = 4,
					persistence = "Confirmed",
				})
				expect(Controller._TestGetState().Status).to.equal("Owned")
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(1)
			end)
		end)

		it("sends the TrackUpgrade request for one offer and keeps the purchase status apart", function()
			local tracked = {}
			local progressRemote = {}
			function progressRemote:InvokeServer(request)
				table.insert(tracked, request)
				return { ok = true, progress = { trackedUpgrade = { offerId = request.offerId, shortfall = 1500 } } }
			end
			fixture(function(context)
				context.Open:Fire(payload(true))
				Controller._TestTrack("FIXTURE_A")
				Controller._TestTrack("UNKNOWN_OFFER")
				if not Phase12.Enabled then
					expect(#tracked).to.equal(0)
					return
				end
				expect(#tracked).to.equal(1)
				expect(tracked[1].action).to.equal("TrackUpgrade")
				expect(tracked[1].offerId).to.equal("FIXTURE_A")
				local state = Controller._TestGetState()
				expect(state.Tracks.FIXTURE_A.tracked).to.equal(true)
				expect(state.Tracks.FIXTURE_A.busy).to.equal(false)
				expect(string.find(state.StatusLine, "Tracking", 1, true)).to.equal(1)
				expect(state.Status).to.equal("")
				expect(#context.Requests).to.equal(0)
			end, { ProgressRemote = progressRemote })
		end)

		it("does not convert a scroll gesture into a purchase", function()
			fixture(function(context)
				context.Open:Fire(payload(true))
				Controller._TestSetScrollGestureMoved(true)
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(0)
				Controller._TestSetScrollGestureMoved(false)
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(1)
			end)
		end)

		it("closes without purchasing and keeps one listener across reopening", function()
			fixture(function(context)
				expect(context.Open:Count()).to.equal(1)
				context.Open:Fire(payload(true))
				Controller._TestClose()
				expect(#context.Requests).to.equal(0)
				expect(#context.Closes).to.equal(1)
				expect(Controller._TestGetState().State).to.equal("Closed")
				context.Open:Fire(payload(true))
				expect(context.Open:Count()).to.equal(1)
				expect(Controller._TestGetState().State).to.equal("Open")
			end)
		end)

		it("times out into one bounded status check without a new purchase ID", function()
			fixture(function(context)
				context.SetImmediate(false)
				context.Open:Fire(payload(true))
				Controller._TestActivate("FIXTURE_A")
				expect(#context.Requests).to.equal(0)
				expect(#context.Delays).to.equal(1)
				context.Delays[1].Run()
				expect(Controller._TestGetState().State).to.equal("Resolving")
				expect(#context.Spawned).to.equal(2)
				context.RunSpawn()
				expect(context.Requests[1].operation).to.equal("Purchase")
				expect(context.Requests[1].requestId).to.equal("request-1")
				context.RunSpawn()
				expect(context.Requests[2].operation).to.equal("Status")
				expect(context.Requests[2].requestId).to.equal("request-1")
			end)
		end)
	end)
end
