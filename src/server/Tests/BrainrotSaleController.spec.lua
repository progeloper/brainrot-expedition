--!nocheck

return function()
	local Controller = require(
		game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.BrainrotSaleController
	)

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

	-- Stands in for the Plate window: records what the controller tells its view.
	local function recordingView()
		local view = { Opens = {}, Closes = {}, Submit = {}, Errors = {}, Actions = nil }
		function view.Open(shown, actions)
			table.insert(view.Opens, shown)
			view.Actions = actions
		end
		function view.Close(reason)
			table.insert(view.Closes, reason)
		end
		function view.SetSubmitEnabled(enabled)
			table.insert(view.Submit, enabled)
		end
		function view.ShowError(message)
			table.insert(view.Errors, message)
		end
		return view
	end

	-- headless = true injects no view at all: the sale session must still run.
	local function fixture(callback, headless)
		Controller.Stop()
		local openEvent = signal()
		local inputEvent = signal()
		local characterAdded = signal()
		local invocations, cancellations, delays, spawned, warnings = {}, {}, {}, {}, {}
		local response = { ok = true, code = "Sold", DisplayName = "Server Name", Paid = 999 }
		local deferSpawn = false
		local now = 100
		local view = if headless then nil else recordingView()
		local player = { CharacterAdded = characterAdded }
		local confirmRemote = {}
		function confirmRemote:InvokeServer(...)
			table.insert(invocations, table.pack(...))
			return response
		end
		local cancelRemote = {}
		function cancelRemote:FireServer(...)
			table.insert(cancellations, table.pack(...))
		end
		Controller.Init({
			Player = player,
			OpenRemote = { OnClientEvent = openEvent },
			ConfirmRemote = confirmRemote,
			CancelRemote = cancelRemote,
			InputBegan = inputEvent,
			View = view,
			Clock = function()
				return now
			end,
			Spawn = function(run)
				if deferSpawn then
					table.insert(spawned, run)
				else
					run()
				end
			end,
			Delay = function(seconds, run)
				table.insert(delays, { Seconds = seconds, Run = run })
			end,
			Warn = function(message)
				table.insert(warnings, message)
			end,
		})
		assert(Controller.Start())
		local context = {
			View = view,
			OpenEvent = openEvent,
			InputEvent = inputEvent,
			CharacterAdded = characterAdded,
			Invocations = invocations,
			Cancellations = cancellations,
			Delays = delays,
			Warnings = warnings,
			SetNow = function(value)
				now = value
			end,
			SetResponse = function(value)
				response = value
			end,
			DeferSpawn = function()
				deferSpawn = true
			end,
			RunSpawn = function()
				local run = table.remove(spawned, 1)
				assert(run, "Expected a queued spawned callback")
				run()
			end,
			SpawnCount = function()
				return #spawned
			end,
		}
		local ok, problem = xpcall(function()
			callback(context)
		end, debug.traceback)
		Controller.Stop()
		assert(ok, problem)
	end

	local function preview(sessionId, speciesId, displayName, rarity, sellValue, expiresAt)
		return {
			SaleSessionId = sessionId or "sale-session",
			RuntimeBrainrotId = "runtime-" .. (sessionId or "sale-session"),
			SpeciesId = speciesId or "BRT_019",
			DisplayName = displayName or "Trenostruzzo Turbo 3000",
			Rarity = rarity or "Rare",
			Rank = rarity or "Rare",
			SellValue = sellValue or 648,
			ExpiresAtServerTime = expiresAt or 120,
			TrainAvailable = false,
			MutationAvailable = false,
		}
	end

	describe("Brainrot sale controller", function()
		it("shows one sale view from the server quote and replaces it on a newer quote", function()
			fixture(function(context)
				local view = context.View
				expect(Controller.Start()).to.equal(false)
				expect(context.OpenEvent:Count()).to.equal(1)
				expect(context.CharacterAdded:Count()).to.equal(1)
				context.OpenEvent:Fire(preview())
				local state = Controller._TestGetState()
				expect(state.Open).to.equal(true)
				expect(state.State).to.equal("Open")
				expect(state.SessionId).to.equal("sale-session")
				expect(state.DisplayName).to.equal("Trenostruzzo Turbo 3000")
				expect(state.Rarity).to.equal("Rare")
				expect(state.SellValue).to.equal(648)
				expect(state.SubmitEnabled).to.equal(true)
				expect(state.Error).to.equal(nil)
				expect(#view.Opens).to.equal(1)
				expect(view.Opens[1].SaleSessionId).to.equal("sale-session")
				expect(view.Opens[1].SpeciesId).to.equal("BRT_019")
				expect(view.Opens[1].DisplayName).to.equal("Trenostruzzo Turbo 3000")
				expect(view.Opens[1].Rarity).to.equal("Rare")
				expect(view.Opens[1].SellValue).to.equal(648)
				expect(view.Opens[1].ExpiresAtServerTime).to.equal(120)
				expect(view.Actions.IsBusy()).to.equal(false)
				expect(view.Actions.Clock()).to.equal(100)

				context.OpenEvent:Fire(
					preview("replacement", "BRT_026", "Rhino Toasterino", "Epic", 2160, 125)
				)
				expect(Controller._TestGetState().SessionId).to.equal("replacement")
				expect(Controller._TestGetState().RuntimeBrainrotId).to.equal("runtime-replacement")
				expect(Controller._TestGetState().SpeciesId).to.equal("BRT_026")
				expect(Controller._TestGetState().DisplayName).to.equal("Rhino Toasterino")
				expect(Controller._TestGetState().Rarity).to.equal("Epic")
				expect(Controller._TestGetState().SellValue).to.equal(2160)
				expect(#view.Opens).to.equal(2)
				expect(view.Opens[2].SaleSessionId).to.equal("replacement")
				expect(view.Closes[#view.Closes]).to.equal("Replaced")
				expect(#context.Cancellations).to.equal(1)
				expect(context.Cancellations[1][1]).to.equal("sale-session")

				-- the view's Cancel (window X / Cancel button / MenusV2 back) cancels the quote on screen
				view.Actions.Cancel()
				expect(Controller._TestGetState().Open).to.equal(false)
				expect(view.Closes[#view.Closes]).to.equal("CloseButton")
				expect(#context.Cancellations).to.equal(2)
				expect(context.Cancellations[2][1]).to.equal("replacement")

				-- the view's Confirm is the same path as _TestConfirm
				context.OpenEvent:Fire(preview("from-view"))
				view.Actions.Confirm()
				expect(#context.Invocations).to.equal(1)
				expect(context.Invocations[1][1]).to.equal("from-view")
				expect(view.Closes[#view.Closes]).to.equal("Sold")
				expect(#context.Cancellations).to.equal(2)
			end)
		end)

		it("runs the whole sale session headless when no view is injected", function()
			fixture(function(context)
				expect(context.View).to.equal(nil)
				context.OpenEvent:Fire(preview("headless"))
				expect(Controller._TestGetState().Open).to.equal(true)
				Controller._TestConfirm()
				expect(#context.Invocations).to.equal(1)
				expect(context.Invocations[1][1]).to.equal("headless")
				expect(Controller._TestGetState().Open).to.equal(false)
				context.OpenEvent:Fire(preview("headless-cancel"))
				Controller._TestCancel()
				expect(Controller._TestGetState().Open).to.equal(false)
				expect(#context.Cancellations).to.equal(1)
				expect(context.Cancellations[1][1]).to.equal("headless-cancel")
			end, true)
		end)

		it("rejects malformed or expired quotes and warns only once", function()
			fixture(function(context)
				context.OpenEvent:Fire({ SaleSessionId = "bad" })
				context.OpenEvent:Fire(preview("expired", nil, nil, nil, nil, 100))
				expect(Controller._TestGetState().Open).to.equal(false)
				expect(#context.Warnings).to.equal(1)
			end)
		end)

		it("X, Escape, gamepad back, respawn and expiry cancel the exact quote", function()
			fixture(function(context)
				for index, action in { "button", "escape", "back", "respawn", "expiry" } do
					local id = action .. index
					context.OpenEvent:Fire(
						preview(id, nil, nil, nil, nil, if action == "expiry" then 105 else nil)
					)
					if action == "button" then
						Controller._TestCancel()
					elseif action == "escape" then
						context.InputEvent:Fire({ KeyCode = Enum.KeyCode.Escape })
					elseif action == "back" then
						context.InputEvent:Fire({ KeyCode = Enum.KeyCode.ButtonB })
					elseif action == "respawn" then
						context.CharacterAdded:Fire()
					else
						context.SetNow(105)
						context.Delays[#context.Delays].Run()
					end
					expect(Controller._TestGetState().Open).to.equal(false)
				end
				expect(#context.Invocations).to.equal(0)
				expect(#context.Cancellations).to.equal(5)
			end)
		end)

		it("submits only the transaction ID once and closes on authoritative success", function()
			fixture(function(context)
				context.DeferSpawn()
				context.OpenEvent:Fire(preview("only-this-id"))
				Controller._TestConfirm()
				Controller._TestConfirm()
				expect(context.SpawnCount()).to.equal(1)
				expect(Controller._TestGetState().State).to.equal("SubmittingSell")
				expect(Controller._TestGetState().RequestInFlight).to.equal(true)
				expect(Controller._TestGetState().SubmitEnabled).to.equal(false)
				expect(context.View.Submit[#context.View.Submit]).to.equal(false)
				expect(context.View.Actions.IsBusy()).to.equal(true)
				context.RunSpawn()
				expect(#context.Invocations).to.equal(1)
				expect(context.Invocations[1].n).to.equal(1)
				expect(context.Invocations[1][1]).to.equal("only-this-id")
				expect(#context.Cancellations).to.equal(0)
				expect(Controller._TestGetState().Open).to.equal(false)
			end)
		end)

		it("invalidates stale quotes and keeps transient failures retryable", function()
			fixture(function(context)
				context.SetResponse({ ok = false, code = "PreviewChanged" })
				context.OpenEvent:Fire(preview("stale"))
				Controller._TestConfirm()
				expect(Controller._TestGetState().Open).to.equal(false)
				expect(#context.Cancellations).to.equal(1)

				context.SetResponse({ ok = false, code = "AwardFailed" })
				context.OpenEvent:Fire(preview("retry"))
				Controller._TestConfirm()
				expect(Controller._TestGetState().Open).to.equal(true)
				expect(Controller._TestGetState().State).to.equal("Open")
				expect(Controller._TestGetState().RequestInFlight).to.equal(false)
				expect(Controller._TestGetState().SubmitEnabled).to.equal(true)
				expect(Controller._TestGetState().Error).to.equal("Unable to award currency. Try again.")
				expect(context.View.Submit[#context.View.Submit]).to.equal(true)
				expect(context.View.Errors[#context.View.Errors]).to.equal("Unable to award currency. Try again.")
			end)
		end)

		it("recovers from an invalid transport result without automatic retry", function()
			fixture(function(context)
				context.SetResponse("invalid transport response")
				context.OpenEvent:Fire(preview("retry-manually"))
				Controller._TestConfirm()
				expect(#context.Invocations).to.equal(1)
				expect(Controller._TestGetState().Open).to.equal(true)
				expect(Controller._TestGetState().RequestInFlight).to.equal(false)
				expect(Controller._TestGetState().SubmitEnabled).to.equal(true)
				expect(Controller._TestGetState().Error).to.equal("Unable to complete sale.")
				expect(context.View.Errors[#context.View.Errors]).to.equal("Unable to complete sale.")
				expect(#context.Warnings).to.equal(1)
			end)
		end)
	end)
end
