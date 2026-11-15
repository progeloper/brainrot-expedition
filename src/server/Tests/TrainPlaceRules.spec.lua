--!nocheck
-- Playtest Fixes Part D: Train! validation, the shared bay and the bay pose (pure).

return function()
	local RS = game:GetService("ReplicatedStorage")
	local Rules = require(RS.Shared.Utility.TrainPlaceRules)
	local Config = require(RS.Shared.Config.PlaytestFixes).TrainPlace

	local function ok()
		return {
			trainingOn = true,
			alreadyTraining = false,
			alive = true,
			distance = 5,
			promptDistance = 12,
			canAct = true,
			busy = false,
			carrying = false,
			hasCart = true,
		}
	end

	describe("TrainPlace validation", function()
		it("accepts an eligible player", function()
			expect(Rules.Check(ok())).to.equal(nil)
		end)
		it("rejects each failure with its reason and a toast", function()
			local cases = {
				{ "trainingOn", false, "TrainingOff" },
				{ "alreadyTraining", true, "AlreadyTraining" },
				{ "alive", false, "NotLiving" },
				{ "distance", 12 + Config.ExtraActivationDistance + 0.5, "TooFar" },
				{ "canAct", false, "Dazed" },
				{ "busy", true, "Busy" },
				{ "carrying", true, "Carrying" },
				{ "hasCart", false, "NoCart" },
			}
			for _, case in cases do
				local input = ok()
				input[case[1]] = case[2]
				expect(Rules.Check(input)).to.equal(case[3])
				expect(type(Rules.Message(case[3]))).to.equal("string")
			end
			expect(Rules.Message("Carrying")).to.equal("Drop your brainrot first")
		end)
		it("allows the prompt distance plus the extra slack", function()
			local input = ok()
			input.distance = 12 + Config.ExtraActivationDistance
			expect(Rules.Check(input)).to.equal(nil)
		end)
	end)

	describe("shared bay", function()
		it("trains any number of players at once", function()
			local eligible = { "a", "b", "c", "d", "e", "f" }
			expect(#Rules.Occupants(true, eligible, "a")).to.equal(6)
		end)
		it("keeps the legacy single occupant when the bay is not shared", function()
			local eligible = { "a", "b", "c" }
			local one = Rules.Occupants(false, eligible, "b")
			expect(#one).to.equal(1)
			expect(one[1]).to.equal("b")
			expect(Rules.Occupants(false, eligible, nil)[1]).to.equal("a")
			expect(#Rules.Occupants(false, {}, nil)).to.equal(0)
		end)
	end)

	describe("bay pose", function()
		it("stands on the deck facing the way carts drive onto the rollers", function()
			local trigger = CFrame.new(-92, 3.4, -44.83) * CFrame.Angles(0, math.rad(180), 0)
			local frame = Rules.BayFrame(trigger, 1.09, CFrame.identity)
			expect(math.abs(frame.Position.Y - 1.09) < 1e-4).to.equal(true)
			expect(math.abs(frame.Position.X + 92) < 1e-4).to.equal(true)
			expect(frame.LookVector:Dot(trigger.LookVector) > 0.999).to.equal(true)
			expect(math.abs(frame.UpVector.Y - 1) < 1e-4).to.equal(true)
		end)
	end)
end
