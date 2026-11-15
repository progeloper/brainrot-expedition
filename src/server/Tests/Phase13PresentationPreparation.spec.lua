--!nocheck
-- The production preparation fence with an explicit coroutine scheduler. These
-- cases do not claim native camera, template residency or rendered-pixel proof.
return function()
	local Rules = require(game.ReplicatedStorage.Shared.Utility.Phase13PresentationRules)
	local function fixture()
		local state =
			{ started = true, generation = 1, contextValid = true, uiCreated = 0, controlsDisabled = 0, superseded = 0 }
		state.fence = Rules.PreparationFence(function(expectedGeneration)
			return state.started and state.generation == expectedGeneration
		end)
		function state:Stop()
			self.fence:Cancel()
			self.started = false
			self.generation += 1
		end
		function state:Start()
			self.started = true
			self.generation += 1
		end
		function state:Prepare(operationId, duringCompletion)
			local ticket = self.fence:Begin(self.generation, function()
				return self.contextValid
			end)
			local thread = coroutine.create(function()
				coroutine.yield("AwaitingTemplateHeartbeat")
				if not self.fence:IsCurrent(ticket) then
					return false
				end
				self.superseded += 1
				if duringCompletion then
					duringCompletion()
				end
				if not self.fence:Commit(ticket) then
					return false
				end
				self.uiCreated += 1
				self.controlsDisabled += 1
				self.activeOperationId = operationId
				return true
			end)
			local ok, yielded = coroutine.resume(thread)
			assert(ok and yielded == "AwaitingTemplateHeartbeat", tostring(yielded))
			return thread, ticket
		end
		return state
	end
	local function resume(thread)
		local ok, result = coroutine.resume(thread)
		assert(ok, tostring(result))
		expect(coroutine.status(thread)).to.equal("dead")
		return result
	end
	describe("Phase13 asynchronous rebirth preparation lifetime", function()
		it("does not create UI or disable controls when Stop runs during template wait", function()
			local state = fixture()
			local pending = state:Prepare("saved-before-Stop")
			state:Stop()
			expect(resume(pending)).to.equal(false)
			expect(state.uiCreated).to.equal(0)
			expect(state.controlsDisabled).to.equal(0)
			expect(state.superseded).to.equal(0)
		end)
		it("keeps an old same-character preparation cancelled across Stop then Start", function()
			local state = fixture()
			local old = state:Prepare("old-confirmation")
			state:Stop()
			state:Start()
			local current = state:Prepare("new-confirmation")
			expect(resume(old)).to.equal(false)
			expect(resume(current)).to.equal(true)
			expect(state.activeOperationId).to.equal("new-confirmation")
			expect(state.uiCreated).to.equal(1)
			expect(state.controlsDisabled).to.equal(1)
		end)
		it("does not let an older distinct confirmation supersede a newer started presentation", function()
			local state = fixture()
			local old = state:Prepare("slow-confirmation")
			local current = state:Prepare("latest-confirmation")
			expect(resume(current)).to.equal(true)
			expect(resume(old)).to.equal(false)
			expect(state.activeOperationId).to.equal("latest-confirmation")
			expect(state.superseded).to.equal(1)
			expect(state.uiCreated).to.equal(1)
			expect(state.controlsDisabled).to.equal(1)
		end)
		it("rechecks cancellation after an existing completion callback stops the controller", function()
			local state = fixture()
			local pending = state:Prepare("interrupted-during-completion", function()
				state:Stop()
			end)
			expect(resume(pending)).to.equal(false)
			expect(state.superseded).to.equal(1)
			expect(state.uiCreated).to.equal(0)
			expect(state.controlsDisabled).to.equal(0)
		end)
		it("does not construct from stale character or plot context after a completion callback", function()
			local state = fixture()
			local pending = state:Prepare("stale-context", function()
				state.contextValid = false
			end)
			expect(resume(pending)).to.equal(false)
			expect(state.superseded).to.equal(1)
			expect(state.uiCreated).to.equal(0)
			expect(state.controlsDisabled).to.equal(0)
		end)
		it("commits a live preparation once without changing the existing timeline samples", function()
			local state = fixture()
			local pending, ticket = state:Prepare("current-confirmation")
			expect(resume(pending)).to.equal(true)
			expect(state.fence:Commit(ticket)).to.equal(false)
			expect(state.uiCreated).to.equal(1)
			expect(Rules.Rebirth(6.999).done).to.equal(false)
			expect(Rules.Rebirth(7).done).to.equal(true)
		end)
	end)
	local function cameraFixture(departing)
		local original = {}
		local oldHumanoid = { parent = original, live = true }
		local camera = {}
		local live = true
		local fence = Rules.CameraRestoreFence(function(expectedGeneration)
			return live and expectedGeneration == 1
		end, function(subject)
			return subject.live == true
		end, function(subject, character)
			return subject == character or subject.parent == character
		end)
		local state = {
			fence = fence,
			original = original,
			old = oldHumanoid,
			camera = camera,
			context = {
				now = 1,
				camera = camera,
				cameraType = "Custom",
				subject = oldHumanoid,
				character = original,
				humanoid = oldHumanoid,
			},
		}
		function state:Begin(subject)
			self.fence:Begin({
				generation = 1,
				camera = camera,
				cameraType = "Custom",
				subject = subject or oldHumanoid,
				character = original,
				departing = departing,
				deadline = 11,
			})
		end
		function state:Stop()
			live = false
		end
		function state:NewCharacter(withHumanoid)
			self.context.character = {}
			self.context.humanoid = if withHumanoid then { parent = self.context.character, live = true } else nil
		end
		state:Begin()
		return state
	end
	describe("Phase13 bounded camera subject restoration", function()
		it("restores the original live standard Humanoid after normal completion", function()
			local f = cameraFixture(false)
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(f.old)
			expect(status).to.equal("Ready")
			expect(f.fence:Pending()).to.equal(false)
		end)
		it("preserves a legitimate custom subject outside the departing character", function()
			local f = cameraFixture(true)
			local custom = { live = true }
			f:Begin(custom)
			f.context.subject = custom
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(custom)
			expect(status).to.equal("Ready")
		end)
		it("does not restore the departing Humanoid while CharacterRemoving still exposes it", function()
			local f = cameraFixture(true)
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Waiting")
			expect(f.fence:Pending()).to.equal(true)
		end)
		it("treats the departing character Model itself as a character subject", function()
			local f = cameraFixture(true)
			f.original.live = true
			f:Begin(f.original)
			f.context.subject = f.original
			local subject, waiting = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(waiting).to.equal("Waiting")
			f:NewCharacter(true)
			local current, ready = f.fence:Step(f.context)
			expect(current).to.equal(f.context.humanoid)
			expect(ready).to.equal("Ready")
		end)
		it("never restores an unparented old subject during the nil-character gap", function()
			local f = cameraFixture(true)
			f.old.live = false
			f.context.character, f.context.humanoid = nil, nil
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Waiting")
		end)
		it("waits for a delayed new Humanoid then repairs exactly once", function()
			local f = cameraFixture(true)
			f:NewCharacter(false)
			local _, waiting = f.fence:Step(f.context)
			expect(waiting).to.equal("Waiting")
			f.context.humanoid = { parent = f.context.character, live = true }
			local subject, ready = f.fence:Step(f.context)
			expect(subject).to.equal(f.context.humanoid)
			expect(ready).to.equal("Ready")
			local _, idle = f.fence:Step(f.context)
			expect(idle).to.equal("Idle")
		end)
		it("keeps an owned nil-subject respawn gap pending until the new Humanoid arrives", function()
			local f = cameraFixture(true)
			f.context.subject = nil
			local subject, waiting = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(waiting).to.equal("Waiting")
			f:NewCharacter(true)
			local current, ready = f.fence:Step(f.context)
			expect(current).to.equal(f.context.humanoid)
			expect(ready).to.equal("Ready")
		end)
		it("accepts a new live Humanoid already selected by the default camera", function()
			local f = cameraFixture(true)
			f:NewCharacter(true)
			f.context.subject = f.context.humanoid
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(f.context.humanoid)
			expect(status).to.equal("Ready")
		end)
		it("expires a missing-character repair at its deadline with no pending resource", function()
			local f = cameraFixture(true)
			f.context.now = 11
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Expired")
			expect(f.fence:Pending()).to.equal(false)
		end)
		it("yields to a replacement current Camera", function()
			local f = cameraFixture(true)
			f.context.camera = {}
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Cancelled")
			expect(f.fence:Pending()).to.equal(false)
		end)
		it("does not steal a subject selected by a different camera owner", function()
			local f = cameraFixture(true)
			f.context.subject = { live = true }
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Cancelled")
		end)
		it("does not restore a valid external custom subject explicitly cleared by another owner", function()
			local f = cameraFixture(true)
			local custom = { live = true }
			f:Begin(custom)
			f.context.subject = nil
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Cancelled")
			expect(f.fence:Pending()).to.equal(false)
		end)
		it("yields when another owner changes CameraType during a delayed restore", function()
			local f = cameraFixture(true)
			local _, waiting = f.fence:Step(f.context)
			expect(waiting).to.equal("Waiting")
			f.context.cameraType = "Scriptable"
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Cancelled")
		end)
		it("rejects an old generation after Stop and supports explicit new-presentation cancellation", function()
			local f = cameraFixture(true)
			f:Stop()
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(nil)
			expect(status).to.equal("Cancelled")
			local g = cameraFixture(true)
			g.fence:Cancel()
			expect(g.fence:Pending()).to.equal(false)
			local _, idle = g.fence:Step(g.context)
			expect(idle).to.equal("Idle")
		end)
		it("repairs an invalid prior subject from a live same-character Humanoid", function()
			local f = cameraFixture(false)
			f.old.live = false
			f.context.humanoid = { parent = f.original, live = true }
			local subject, status = f.fence:Step(f.context)
			expect(subject).to.equal(f.context.humanoid)
			expect(status).to.equal("Ready")
		end)
	end)
end
