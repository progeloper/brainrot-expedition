--!nocheck
return function()
	local RS = game:GetService("ReplicatedStorage")
	local Selector = require(RS.Shared.Utility.HuntTargetSelector)
	local Config = require(RS.Shared.Config.DriveAndHunt).Lock

	local function candidate(id, overrides)
		local value = { id = id, distance = 40, facingAngle = 0, alreadyHit = false, rarityRank = 1, lineOfSight = true }
		for key, item in overrides or {} do
			value[key] = item
		end
		return value
	end
	local function context(overrides)
		local value = { range = 100, mounted = true, fireHeld = false, now = 100 }
		for key, item in overrides or {} do
			value[key] = item
		end
		return value
	end
	local function pick(list, state, ctx)
		local chosen = Selector.Select(list, state or Selector.NewState(), ctx or context(), Config)
		return chosen and chosen.id
	end

	describe("scripted scenes (L1)", function()
		it("ahead: prefers the brainrot in front over an equal one off to the side", function()
			expect(pick({ candidate("side", { facingAngle = math.rad(80) }), candidate("ahead") })).to.equal("ahead")
		end)
		it("beside: locks a lone brainrot 90 degrees to the side", function()
			expect(pick({ candidate("beside", { facingAngle = math.rad(90), distance = 25 }) })).to.equal("beside")
		end)
		it("behind: never locks past the mounted arc, but does on foot", function()
			local list = { candidate("behind", { facingAngle = math.rad(170) }) }
			expect(pick(list)).to.equal(nil)
			expect(pick(list, nil, context({ mounted = false }))).to.equal("behind")
		end)
		it("already-hit: finishes the one this player has hit before a slightly closer fresh one", function()
			expect(pick({ candidate("fresh", { distance = 35 }), candidate("hit", { distance = 45, alreadyHit = true }) })).to.equal("hit")
		end)
		it("rare vs common: rarity is only a small bonus between otherwise equal targets", function()
			expect(pick({ candidate("common"), candidate("rare", { rarityRank = 5 }) })).to.equal("rare")
			expect(pick({ candidate("common", { distance = 20 }), candidate("rare", { rarityRank = 5, distance = 60 }) })).to.equal("common")
		end)
		it("behind a wall: a candidate without line of sight is never chosen", function()
			expect(pick({ candidate("walled", { distance = 10, lineOfSight = false }), candidate("open", { distance = 70 }) })).to.equal("open")
			expect(pick({ candidate("walled", { lineOfSight = false }) })).to.equal(nil)
		end)
	end)

	describe("exclusions and limits", function()
		it("ignores candidates out of range", function()
			expect(pick({ candidate("far", { distance = 101 }) })).to.equal(nil)
		end)
		it("scores at most MaxCandidates, nearest first", function()
			local list = {}
			for index = 1, Config.MaxCandidates do
				table.insert(list, candidate(string.format("near%02d", index), { distance = 30 + index, facingAngle = math.rad(120) }))
			end
			table.insert(list, candidate("farButAhead", { distance = 90, alreadyHit = true, rarityRank = 8 }))
			local chosen = pick(list)
			expect(chosen ~= "farButAhead").to.equal(true)
		end)
		it("breaks exact ties by distance, then id", function()
			expect(pick({ candidate("b"), candidate("a") })).to.equal("a")
		end)
	end)

	describe("stickiness (L2)", function()
		it("keeps the lock while FIRE is held when a closer brainrot passes", function()
			local state = Selector.NewState()
			expect(pick({ candidate("first") }, state)).to.equal("first")
			local list = { candidate("first"), candidate("closer", { distance = 8 }) }
			expect(pick(list, state, context({ fireHeld = true }))).to.equal("first")
		end)
		it("keeps the lock for the hold window after a shot, then lets a much better target win", function()
			local state = Selector.NewState()
			pick({ candidate("first") }, state)
			Selector.NoteShot(state, 100)
			local list = { candidate("first", { facingAngle = math.rad(100) }), candidate("closer", { distance = 8 }) }
			expect(pick(list, state, context({ now = 100.5 }))).to.equal("first")
			expect(pick(list, state, context({ now = 100 + Config.HoldAfterShotSeconds + 0.1 }))).to.equal("closer")
		end)
		it("gives the current target a bonus against a marginally better one", function()
			local state = Selector.NewState()
			pick({ candidate("first", { distance = 40 }) }, state)
			expect(pick({ candidate("first", { distance = 40 }), candidate("other", { distance = 34 }) }, state)).to.equal("first")
		end)
		it("drops the lock when the target leaves the list (asleep, gone or out of range)", function()
			local state = Selector.NewState()
			pick({ candidate("first") }, state)
			expect(pick({ candidate("other", { distance = 70 }) }, state, context({ fireHeld = true }))).to.equal("other")
		end)
		it("holds through a brief loss of sight and drops after the grace", function()
			local state = Selector.NewState()
			pick({ candidate("first") }, state)
			local hidden = { candidate("first", { lineOfSight = false }) }
			expect(pick(hidden, state, context({ now = 100.2 }))).to.equal("first")
			expect(pick(hidden, state, context({ now = 100.4 }))).to.equal("first")
			expect(pick(hidden, state, context({ now = 100.2 + Config.LostSightGraceSeconds + 0.1 }))).to.equal(nil)
		end)
	end)

	describe("tap and pointer switching (L3)", function()
		it("a tap within the radius picks the nearest candidate on screen", function()
			local list = {
				candidate("a", { screen = Vector2.new(100, 100) }),
				candidate("b", { screen = Vector2.new(140, 100) }),
				candidate("c", { screen = Vector2.new(400, 300) }),
			}
			expect(Selector.PickByScreen(list, Vector2.new(132, 104), Config.TapRadiusPixels).id).to.equal("b")
			expect(Selector.PickByScreen(list, Vector2.new(250, 250), Config.TapRadiusPixels)).to.equal(nil)
		end)
		it("a manual choice overrides stickiness, even while FIRE is held", function()
			local state = Selector.NewState()
			local list = { candidate("first"), candidate("tapped", { distance = 80, facingAngle = math.rad(120) }) }
			pick(list, state)
			state.manualId = "tapped"
			expect(pick(list, state, context({ fireHeld = true }))).to.equal("tapped")
			expect(state.manualId).to.equal(nil)
			expect(pick(list, state, context({ fireHeld = true }))).to.equal("tapped")
		end)
		it("a manual choice outside reach or without sight is ignored", function()
			local state = Selector.NewState()
			local list = { candidate("first"), candidate("behind", { facingAngle = math.rad(175) }) }
			state.manualId = "behind"
			expect(pick(list, state)).to.equal("first")
		end)
		it("the pointer picks inside its cone and otherwise defers to the selector", function()
			local list = { candidate("a", { pointerAngle = math.rad(20) }), candidate("b", { pointerAngle = math.rad(6) }) }
			expect(Selector.PickByPointer(list, Config.PointerConeDegrees).id).to.equal("b")
			expect(Selector.PickByPointer({ candidate("a", { pointerAngle = math.rad(20) }) }, Config.PointerConeDegrees)).to.equal(nil)
		end)
	end)
end
