--!nocheck
-- Native Edit dependency/lifecycle boundaries. This does not claim connected input or rewards.
return function()
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local Systems = script.Parent.Parent.Systems
	local Sleep = require(Systems.BrainrotSleepSystem)
	local function isolated()
		local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
		local boot = server and server:FindFirstChild("Bootstrap")
		return not RunService:IsRunning()
			or (
				game:GetAttribute("BrainrotTestDiagnosticsDisabled") == true
				and boot ~= nil
				and boot:IsA("Script")
				and boot.Disabled == true
			)
	end
	describe("Owner-retired capture boundary with current shooting to sleep", function()
		it("loads current sleep without the deleted legacy module, meter, or committed-capture APIs", function()
			expect(Systems:FindFirstChild("BrainrotCaptureSystem")).to.equal(nil)
			expect(RS.Shared.Config:FindFirstChild("BrainrotCapture")).to.equal(nil)
			expect(RS.Shared.Utility:FindFirstChild("CaptureProgress")).to.equal(nil)
			expect(type(Sleep.HandleFireRequest)).to.equal("function")
			expect(Sleep.SubscribeCommitted).to.equal(nil)
			expect(Sleep.ObservePickupOutcome).to.equal(nil)
		end)
		it("owns two current listeners and removes them once without creating a retired endpoint", function()
			assert(isolated(), "Isolated Edit or explicitly disabled-bootstrap UNIT fixture only")
			assert(not Sleep.GetDiagnostics().Started, "Do not interrupt a current live service")
			local ok, reason = xpcall(function()
				expect(Sleep:Start()).to.equal(true)
				expect(Sleep:Start()).to.equal(false)
				expect(Sleep.GetDiagnostics().ConnectionCount).to.equal(2)
				expect(RS.Remotes.SleepRequest:IsA("RemoteEvent")).to.equal(true)
				expect(RS.Remotes:FindFirstChild("CaptureRequest")).to.equal(nil)
				expect(Sleep:Stop()).to.equal(true)
				expect(Sleep:Stop()).to.equal(false)
				expect(Sleep.GetDiagnostics().ConnectionCount).to.equal(0)
				expect(Sleep.GetDiagnostics().Started).to.equal(false)
			end, debug.traceback)
			Sleep:Stop()
			assert(ok, reason)
		end)
		it("rejects malformed sleep input before touching current world identity or making an endpoint", function()
			assert(isolated(), "Isolated Edit or explicitly disabled-bootstrap UNIT fixture only")
			local player = {
				UserId = -21901,
				GetAttribute = function()
					return nil
				end,
			}
			for _, intent in
				{
					false,
					{},
					{ CameraOrigin = Vector3.new(0 / 0, 0, 0) },
					{ CameraOrigin = Vector3.zero, CameraDirection = Vector3.zero },
				}
			do
				local shot = Sleep.HandleFireRequest(player, intent)
				expect(shot).to.equal(nil)
			end
			expect(Sleep.GetDiagnostics().ConnectionCount).to.equal(0)
		end)
	end)
end
