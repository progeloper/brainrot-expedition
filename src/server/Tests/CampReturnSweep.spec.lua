--!nocheck
return function()
	local Roaming = require(script.Parent.Parent.Systems.DevelopmentBrainrotRoaming)
	describe("Camp return grounded sweep", function()
		it("keeps Camp arrival owned by recovery on a coincident sensing frame", function()
			local returning = {
				ReturningToRegion = true,
				RecoveringTerritory = true,
				TerritoryRecoveryGoal = Vector3.new(40, 0, 0),
				NextTerritoryRecoveryAt = 12,
			}
			-- The production sensing path must not clear the flag before the same
			-- updateAll invocation dispatches the existing completion owner.
			Roaming._TestReconcileTerritoryPresence(nil, returning, true, 15)
			expect(returning.RecoveringTerritory).to.equal(true)
			expect(returning.ReturningToRegion).to.equal(true)
			expect(returning.TerritoryRecoveryGoal).to.equal(Vector3.new(40, 0, 0))
			local natural = table.clone(returning)
			natural.ReturningToRegion = false
			Roaming._TestReconcileTerritoryPresence(nil, natural, true, 15)
			expect(natural.RecoveringTerritory).to.equal(false)
			expect(natural.TerritoryRecoveryGoal).to.equal(nil)
			expect(natural.NextTerritoryRecoveryAt).to.equal(0)
		end)

		it(
			"uses actual CSG torso extents instead of the offset authoring origin at floor seams",
			function()
				-- Synthetic property fixture reproduces the measured BRT_011 UnionOperation
				-- contract. Its geometric centre differs from CFrame by 0.923337 studs.
				-- Live engine A/B casts reproduced the false Jungle floor-seam hit.
				local origin = Vector3.new(21000, 0, 21000)
				local body = {
					CFrame = CFrame.new(origin + Vector3.new(-5, 0.5620622, 0)),
					Size = Vector3.new(1.9536338, 2.0298982, 2.0910048),
					ExtentsCFrame = CFrame.new(origin + Vector3.new(-5, 1.4853995, 0)),
					ExtentsSize = Vector3.new(1.9536338, 2.0298982, 2.0910048),
					IsA = function(_, className)
						return className == "BasePart"
					end,
				}
				local brainrot = {
					FindFirstChild = function(_, name)
						return if name == "Body" then body else nil
					end,
				}
				local frame, size = Roaming._TestMovementEnvelope(brainrot)
				expect(frame).to.equal(body.ExtentsCFrame)
				expect(size).to.equal(body.ExtentsSize)
				local floors = Instance.new("Folder")
				floors.Name, floors.Parent = "SPEC_CSG_TORSO_SEAM", workspace
				for index, x in { -10, 10 } do
					local floor = Instance.new("Part")
					floor.Name, floor.Anchored = "Floor_" .. index, true
					floor.Size = Vector3.new(20, 2, 30)
					floor.Position = origin + Vector3.new(x, -0.95, 0)
					floor.Parent = floors
				end
				local ok, failure = xpcall(function()
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Include
					params.FilterDescendantsInstances = { floors }
					local step = Vector3.new(10, 0, 0)
					local oldHit = workspace:Blockcast(body.CFrame, body.Size, step, params)
					expect(oldHit and oldHit.Instance).to.equal(floors.Floor_2)
					expect(workspace:Blockcast(frame, size, step, params)).to.equal(nil)
				end, debug.traceback)
				floors:Destroy()
				if not ok then
					error(failure, 0)
				end
			end
		)

		it("covers low protection between safe endpoints and the next facing rotation", function()
			local model = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name, root.Size, root.CFrame, root.Parent =
				"Root", Vector3.one, CFrame.identity, model
			model.PrimaryPart = root
			local body = Instance.new("Part")
			body.Name, body.Size, body.CFrame, body.Parent =
				"Body", Vector3.new(2, 2, 4), CFrame.new(0, 4, 0), model
			local from, to = Vector3.zero, Vector3.new(18, 0, 0)
			local frame, size = Roaming._TestCampReturnRouteEnvelope(model, from, to, 0)
			assert(frame and size, "Expected grounded sweep")
			local rampPoint = frame:PointToObjectSpace(Vector3.new(9, 0.5, 0))
			expect(math.abs(rampPoint.X) < size.X / 2).to.equal(true)
			expect(math.abs(rampPoint.Y) < size.Y / 2).to.equal(true)
			expect(math.abs(rampPoint.Z) < size.Z / 2).to.equal(true)
			expect(math.abs(size.X - math.sqrt(20)) < 1e-5).to.equal(true)
			expect(math.abs(size.Z - (18 + math.sqrt(20))) < 1e-5).to.equal(true)
			expect(size.Y).to.equal(5)
			expect(model:GetPivot()).to.equal(CFrame.identity)
			model:Destroy()
		end)

		it(
			"keeps an offset Body sweep invariant when movement changes facing after validation",
			function()
				local model = Instance.new("Model")
				local root = Instance.new("Part")
				root.Name, root.Size, root.CFrame, root.Parent =
					"Root", Vector3.one, CFrame.identity, model
				model.PrimaryPart = root
				local body = Instance.new("Part")
				body.Name, body.Size, body.CFrame, body.Parent =
					"Body",
					Vector3.new(1.9536338, 2.0298982, 2.0910048),
					CFrame.new(0, 0.41206235, 0.28997803),
					model
				local from = Vector3.new(21.5287857, 0.15, 256.34021)
				local to = from + Vector3.new(18, 0, 0)
				local expectedCentre = (from + to) * 0.5
				local expectedWidth = math.sqrt(body.Size.X ^ 2 + body.Size.Z ^ 2) + 2 * 0.28997803
				local ok, failure = xpcall(function()
					for _, yaw in { 0, 90, 180, 270 } do
						model:PivotTo(CFrame.Angles(0, math.rad(yaw), 0))
						local frame, size =
							Roaming._TestCampReturnRouteEnvelope(model, from, to, 0.15)
						assert(frame and size, "Expected offset Body sweep")
						-- The old torso-centred envelope shifts by 0.289978 studs on
						-- rotation, admitting a position the next movement step rejects.
						expect(math.abs(frame.X - expectedCentre.X) < 1e-4).to.equal(true)
						expect(math.abs(frame.Z - expectedCentre.Z) < 1e-4).to.equal(true)
						expect(math.abs(size.X - expectedWidth) < 1e-4).to.equal(true)
						expect(math.abs(size.Z - (18 + expectedWidth)) < 1e-4).to.equal(true)
					end
				end, debug.traceback)
				model:Destroy()
				if not ok then
					error(failure, 0)
				end
			end
		)
	end)
end
