--!nocheck
-- Real Instance signals; only the expensive physics validator is stubbed here.
-- CartAssemblyValidator.spec and the live cart checks cover actual physics validity.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Service = require(script.Parent.Parent.Services.CartAssemblyValidationService)
	local Validator = require(RS.Shared.Validation.CartAssemblyValidator)

	local function fixture(callback)
		local cart = Instance.new("Model")
		cart.Name, cart.Parent = "SPEC_OBSERVER_LIFETIME", workspace
		local root = Instance.new("Part")
		root.Name, root.Parent = "Root", cart
		local original = Validator.Validate
		local calls = 0
		local deliveryOrder = {}
		Validator.Validate = function(model, options)
			if model ~= cart then
				return original(model, options)
			end
			calls += 1
			table.insert(deliveryOrder, { Parent = root.Parent, Anchored = root.Anchored, Massless = root.Massless })
			return {
				IsValid = true,
				Warnings = {},
				FatalErrors = {},
				ModelName = cart.Name,
				CartId = "SPEC",
				Stage = options.Stage,
			}
		end
		local ok, failure = xpcall(function()
			assert(Service:RegisterCart(cart))
			callback(cart, root, function()
				return calls
			end, deliveryOrder)
		end, debug.traceback)
		Service:ForgetCart(cart, "test cleanup")
		Validator.Validate = original
		cart:Destroy()
		assert(ok, failure)
	end

	describe("Cart assembly observer ownership", function()
		it(
			"returns retained handles and descendants to baseline after 100 cargo-like mutations",
			function()
				fixture(function(cart, root, calls)
					local before = Service:GetDiagnostics()
					local beforeCalls = calls()
					for _ = 1, 100 do
						local accepted, revision = Service:BeginMutation(cart, "fixture mount")
						assert(accepted, "Fixture mount mutation rejected")
						local visual = Instance.new("Model")
						for index = 1, 20 do
							local part = Instance.new("Part")
							part.Name, part.Parent = "CargoPart" .. index, visual
							local weld = Instance.new("WeldConstraint")
							weld.Part0, weld.Part1, weld.Parent = root, part, part
						end
						visual.Parent = cart
						assert(Service:CompleteMutation(cart, revision, "Runtime", "fixture mount"))
						accepted, revision = Service:BeginMutation(cart, "fixture remove")
						assert(accepted, "Fixture removal mutation rejected")
						visual:Destroy()
						assert(
							Service:CompleteMutation(cart, revision, "Runtime", "fixture remove")
						)
					end
					local after = Service:GetDiagnostics()
					expect(calls() - beforeCalls).to.equal(200)
					expect(after.RetainedObservedInstanceCount).to.equal(
						before.RetainedObservedInstanceCount
					)
					expect(after.RetainedConnectionObjectCount).to.equal(
						before.RetainedConnectionObjectCount
					)
					expect(after.RecordConnectionCount).to.equal(before.RecordConnectionCount)
				end)
			end
		)

		it(
			"delivers unexpected physical edits in order, observes reinsertions and stops after Forget",
			function()
				fixture(function(cart, root, calls, deliveryOrder)
					local function awaitCondition(predicate, message)
						local deadline = os.clock() + 2
						while not predicate() and os.clock() < deadline do task.wait() end
						assert(predicate(), message)
					end
					local count = calls()
					root.Anchored = not root.Anchored
					awaitCondition(function() return calls() >= count + 1 end, "Anchored observer was not delivered within2s")
					expect(calls()).to.equal(count + 1)
					expect(deliveryOrder[count + 1].Anchored).to.equal(root.Anchored)
					root.Parent = nil
					awaitCondition(function() return calls() >= count + 2 end, "Removal observer was not delivered within2s")
					expect(calls()).to.equal(count + 2)
					expect(deliveryOrder[count + 2].Parent).to.equal(nil)
					root.Parent = cart
					awaitCondition(function() return calls() >= count + 3 end, "Reinsertion observer was not delivered within2s")
					expect(calls()).to.equal(count + 3)
					expect(deliveryOrder[count + 3].Parent).to.equal(cart)
					root.Massless = not root.Massless
					awaitCondition(function() return calls() >= count + 4 end, "Reinserted part observer was not delivered within2s")
					expect(calls()).to.equal(count + 4)
					expect(deliveryOrder[count + 4].Massless).to.equal(root.Massless)
					Service:ForgetCart(cart, "removed")
					-- Await the actual native property signal, so this assertion proves the
					-- removed service observer stays silent after deferred delivery too.
					local nativeDelivered = false
					local connection = root:GetPropertyChangedSignal("Anchored"):Connect(function() nativeDelivered = true end)
					root.Anchored = not root.Anchored
					awaitCondition(function() return nativeDelivered end, "Native post-Forget signal was not delivered within2s")
					connection:Disconnect()
					expect(calls()).to.equal(count + 4)
					expect(#deliveryOrder).to.equal(count + 4)
				end)
			end
		)
	end)
end
