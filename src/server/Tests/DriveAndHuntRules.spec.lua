--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.DriveAndHuntRules)
	local Config = require(RS.Shared.Config.DriveAndHunt)
	local Flags = require(RS.Shared.Config.DriveAndHuntFlags)
	local FeatureFlags = require(RS.Shared.Config.FeatureFlags)
	local Footprints = require(RS.Shared.Config.RegionFootprints)

	local bounds = Rules.BoundsOf(Footprints.Camp)
	local function input(overrides)
		local value = { edgeDistance = -5, seated = false, alive = true, canAct = true, busy = false, carrying = false }
		for key, item in overrides or {} do
			value[key] = item
		end
		return value
	end

	describe("flag", function()
		it("is a plain boolean (on since CP-D, 12 Nov 2026), and Studio preview is opt-in when off", function()
			expect(type(FeatureFlags.DriveAndHuntV1Enabled)).to.equal("boolean")
			expect(Flags.Resolve(false, false, true)).to.equal(false)
			expect(Flags.Resolve(false, true, nil)).to.equal(false)
			expect(Flags.Resolve(false, true, true)).to.equal(true)
			expect(Flags.Resolve(true, false, nil)).to.equal(true)
		end)
	end)

	describe("camp edge", function()
		it("is negative inside and positive outside the Camp footprint", function()
			expect(bounds.minX).to.equal(-267)
			expect(bounds.maxZ).to.equal(202)
			expect(Rules.EdgeDistance(bounds, 0, 0) < 0).to.equal(true)
			expect(Rules.EdgeDistance(bounds, 0, -304)).to.equal(10)
			expect(Rules.EdgeDistance(bounds, 232, 206)).to.equal(5)
		end)
	end)

	describe("gate trigger", function()
		it("launches on an on-foot walk out of camp", function()
			local state = Rules.NewGateState()
			expect(Rules.GateStep(state, input(), Config.Gate, 10)).to.equal(false)
			expect(Rules.GateStep(state, input({ edgeDistance = 2 }), Config.Gate, 10.1)).to.equal(true)
			-- Already outside: no second trigger.
			expect(Rules.GateStep(state, input({ edgeDistance = 4 }), Config.Gate, 10.2)).to.equal(false)
		end)
		it("never launches from the first sample or from outside to outside", function()
			local state = Rules.NewGateState()
			expect(Rules.GateStep(state, input({ edgeDistance = 3 }), Config.Gate, 1)).to.equal(false)
		end)
		it("refuses carrying, seated, dead, dazed, busy and teleported crossings", function()
			for key, case in {
				Carrying = { carrying = true },
				Seated = { seated = true },
				Dead = { alive = false },
				CannotAct = { canAct = false },
				Busy = { busy = true },
				Teleported = { edgeDistance = Config.Gate.MaxCrossingDistance + 1 },
			} do
				local state = Rules.NewGateState()
				Rules.GateStep(state, input(), Config.Gate, 10)
				case.edgeDistance = case.edgeDistance or 2
				local launch, reason = Rules.GateStep(state, input(case), Config.Gate, 10.1)
				expect(launch).to.equal(false)
				expect(reason).to.equal(key)
			end
		end)
		it("keeps a crossing made while a menu is open and launches when it closes", function()
			local state = Rules.NewGateState()
			Rules.GateStep(state, input(), Config.Gate, 10)
			local launch, reason = Rules.GateStep(state, input({ edgeDistance = 2, busy = true }), Config.Gate, 10.1)
			expect(launch).to.equal(false)
			expect(reason).to.equal("Busy")
			-- Still busy: still held.
			expect(Rules.GateStep(state, input({ edgeDistance = 6, busy = true }), Config.Gate, 10.2)).to.equal(false)
			-- Closed while still near the edge: launch.
			expect(Rules.GateStep(state, input({ edgeDistance = 8 }), Config.Gate, 10.3)).to.equal(true)
			-- Wandered too far before it closed: no launch.
			local far = Rules.NewGateState()
			Rules.GateStep(far, input(), Config.Gate, 10)
			Rules.GateStep(far, input({ edgeDistance = 2, busy = true }), Config.Gate, 10.1)
			local late, why = Rules.GateStep(far, input({ edgeDistance = Config.Gate.MaxCrossingDistance + 5 }), Config.Gate, 12)
			expect(late).to.equal(false)
			expect(why).to.equal("Teleported")
		end)
		it("does not relaunch within the seat-exit and repeat quiet windows", function()
			local state = Rules.NewGateState()
			Rules.GateStep(state, input({ seated = true }), Config.Gate, 0)
			Rules.GateStep(state, input(), Config.Gate, 1) -- left the seat at t=1, inside camp
			local launch, reason = Rules.GateStep(state, input({ edgeDistance = 2 }), Config.Gate, 2)
			expect(launch).to.equal(false)
			expect(reason).to.equal("JustLeftSeat")
			Rules.GateStep(state, input(), Config.Gate, 3)
			expect(Rules.GateStep(state, input({ edgeDistance = 2 }), Config.Gate, 1 + Config.Gate.SeatExitQuietSeconds + 0.1)).to.equal(true)

			local moved = Rules.NewGateState()
			Rules.GateStep(moved, input(), Config.Gate, 20)
			Rules.NoteMoved(moved, 20)
			local again, why = Rules.GateStep(moved, input({ edgeDistance = 2 }), Config.Gate, 21)
			expect(again).to.equal(false)
			expect(why).to.equal("JustMoved")
		end)
	end)

	describe("placement candidates", function()
		it("gives 8 bearings at each of the three distances, facing first, within the query budget", function()
			local candidates = Rules.CallCandidates(Vector3.new(0, 0, -1), Config.Call.Directions, Config.Call.Distances)
			expect(#candidates).to.equal(24)
			expect(#candidates + #Config.Lanes.Distances <= Config.Call.MaxBoundsQueries).to.equal(true)
			expect(candidates[1].offset:FuzzyEq(Vector3.new(0, 0, -7), 1e-3)).to.equal(true)
			expect(math.abs(candidates[9].offset.Magnitude - 10) < 1e-3).to.equal(true)
			local seen = {}
			for index = 1, 8 do
				local offset = candidates[index].offset
				seen[string.format("%d,%d", math.round(offset.X), math.round(offset.Z))] = true
				expect(math.abs(offset.Magnitude - 7) < 1e-3).to.equal(true)
			end
			local count = 0
			for _ in seen do
				count += 1
			end
			expect(count).to.equal(8)
		end)
		it("seeds lanes outside every camp edge, facing outward", function()
			local seeds = Rules.LaneSeeds(bounds, Config.Lanes.Spacing, Config.Lanes.EdgeInset, Config.Lanes.Distances)
			expect(#seeds > 0).to.equal(true)
			for _, seed in seeds do
				expect(#seed.points).to.equal(3)
				for index, point in seed.points do
					expect(math.abs(Rules.EdgeDistance(bounds, point.X, point.Z) - Config.Lanes.Distances[index]) < 1e-3).to.equal(true)
				end
			end
		end)
		it("orders lanes by distance from the crossing point", function()
			local lanes = {
				{ exit = "A", region = "R", normal = Vector3.zAxis, points = { Vector3.new(100, 0, 0) } },
				{ exit = "B", region = "R", normal = Vector3.zAxis, points = { Vector3.new(10, 0, 0) } },
				{ exit = "C", region = "R", normal = Vector3.zAxis, points = { Vector3.new(40, 0, 0) } },
			}
			local nearest = Rules.NearestLanes(lanes, Vector3.new(12, 0, 0), 2)
			expect(#nearest).to.equal(2)
			expect(nearest[1].exit).to.equal("B")
			expect(nearest[2].exit).to.equal("C")
		end)
		it("hops out on the target side, then the other side, then the back", function()
			expect(Rules.HopOutSides(nil)[1]).to.equal("Left")
			expect(Rules.HopOutSides(5)[1]).to.equal("Right")
			expect(Rules.HopOutSides(5)[2]).to.equal("Left")
			expect(Rules.HopOutSides(-5)[3]).to.equal("Back")
		end)
	end)

	describe("switch button", function()
		local function switch(overrides)
			local value = { driving = false, carrying = false, allowed = true, cooldownRemaining = 0, hasCart = true }
			for key, item in overrides or {} do
				value[key] = item
			end
			return Rules.SwitchState(value)
		end
		it("reads HOP OUT while driving", function()
			local state = switch({ driving = true, carrying = false })
			expect(state.state).to.equal("HopOut")
			expect(state.action).to.equal("HopOut")
			expect(state.enabled).to.equal(true)
		end)
		it("reads CART on foot and LOAD & GO (pulsing) while carrying", function()
			expect(switch().action).to.equal("CallCart")
			local carrying = switch({ carrying = true })
			expect(carrying.state).to.equal("LoadAndGo")
			expect(carrying.action).to.equal("LoadAndGo")
			expect(carrying.pulse).to.equal(true)
		end)
		it("greys out with a timer on cooldown and when not allowed", function()
			local cooling = switch({ cooldownRemaining = 3 })
			expect(cooling.enabled).to.equal(false)
			expect(cooling.action).to.equal(nil)
			expect(cooling.cooldown).to.equal(3)
			expect(switch({ allowed = false }).enabled).to.equal(false)
			expect(switch({ hasCart = false }).enabled).to.equal(false)
			-- HOP OUT is never blocked by the call cooldown.
			expect(switch({ driving = true, cooldownRemaining = 3 }).enabled).to.equal(true)
		end)
	end)

	describe("scoop reach (Part D)", function()
		local Profiles = require(RS.Shared.Config.CartGeometry)
		it("is cart half-width + ScoopReach (10) for every cart profile", function()
			local count = 0
			for _, profile in Profiles do
				local shape = Rules.ScoopShape(profile.BodySize, Config.Scoop.Reach)
				expect(math.abs(shape.Lateral - (profile.BodySize.X / 2 + 10)) < 1e-6).to.equal(true)
				-- never less than the old 13-stud pivot radius
				expect(shape.Lateral >= 13).to.equal(true)
				expect(shape.Reach).to.equal(10)
				count += 1
			end
			expect(count >= 9).to.equal(true)
		end)
		it("reaches 10 studs past the side, front and back edges, and no further", function()
			local shape = Rules.ScoopShape(Profiles.CRT_001.BodySize, Config.Scoop.Reach)
			local side, nose = shape.HalfWidth + 10, shape.HalfLength + 10
			expect(Rules.InScoopReach(shape, side - 0.01, 0)).to.equal(true)
			expect(Rules.InScoopReach(shape, -(side - 0.01), 0)).to.equal(true)
			expect(Rules.InScoopReach(shape, side + 0.01, 0)).to.equal(false)
			expect(Rules.InScoopReach(shape, 0, nose - 0.01)).to.equal(true)
			expect(Rules.InScoopReach(shape, 0, -(nose - 0.01))).to.equal(true)
			expect(Rules.InScoopReach(shape, 0, nose + 0.01)).to.equal(false)
			-- Corners are rounded: both offsets at their limits is outside.
			expect(Rules.InScoopReach(shape, side - 0.5, nose - 0.5)).to.equal(false)
		end)
		it("gives a wider cart a wider reach", function()
			local small = Rules.ScoopShape(Profiles.CRT_008.BodySize, Config.Scoop.Reach)
			local large = Rules.ScoopShape(Profiles.CRT_013.BodySize, Config.Scoop.Reach)
			expect(large.Lateral > small.Lateral).to.equal(true)
		end)
	end)

	describe("hints config (Part E)", function()
		it("has the five hints, 3 s each", function()
			local text = Config.HintToast.Text
			for _, key in { "Lock", "Sleep", "Scoop", "HopOut", "LoadAndGo" } do
				expect(type(text[key])).to.equal("string")
			end
			expect(Config.HintToast.Seconds).to.equal(3)
			expect(Config.Scoop.MaxRings * Config.Scoop.RingSegments <= 96).to.equal(true)
		end)
	end)
end
