--!nocheck
-- Exercise the actual shared deadline/eligibility service with real character
-- Humanoids; fake player sessions and a clock isolate persistence/map access.
return function()
	local Combat = require(script.Parent.Parent.Services.PlayerCombatService)
	local Profile = require(script.Parent.Parent.Services.PlayerDataService)
	local function fixture(callback)
		local instances, players = {}, {}
		local clock = 100
		local function character(generation)
			local model = Instance.new("Model")
			model.Name, model.Parent = "SPEC_COMBAT_CHARACTER", workspace
			model:SetAttribute("Phase10CharacterGeneration", generation)
			table.insert(instances, model)
			local root = Instance.new("Part")
			root.Name, root.Anchored, root.Position, root.Parent =
				"HumanoidRootPart", true, Vector3.new(9000, 100, 9000), model
			local head = Instance.new("Part")
			head.Name, head.Anchored, head.Parent = "Head", true, model
			local humanoid = Instance.new("Humanoid")
			humanoid.RequiresNeck, humanoid.Parent = false, model
			return model, humanoid, root
		end
		local function player(id)
			local model, humanoid, root = character(id)
			local value = {
				UserId = id,
				Character = model,
				Ready = true,
				Playtime = 900,
				Attributes = {},
				Humanoid = humanoid,
				Root = root,
			}
			function value:GetAttribute(key)
				return self.Attributes[key]
			end
			function value:SetAttribute(key, data)
				self.Attributes[key] = data
			end
			table.insert(players, value)
			return value
		end
		local a, b, c = player(-701), player(-702), player(-703)
		Combat:_ConfigureForTests({
			Now = function()
				return clock
			end,
			Ready = function(p)
				return p.Ready
			end,
			Camp = function(position)
				return position.X == 0
			end,
			Playtime = function(p)
				return p.Playtime
			end,
			Players = function()
				return players
			end,
			PlayerFromCharacter = function(model)
				for _, p in players do
					if p.Character == model then
						return p
					end
				end
				return nil
			end,
			PlayerByUserId = function(id)
				for _, p in players do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
		})
		local f = { A = a, B = b, C = c, Players = players, Character = character }
		function f.Now()
			return clock
		end
		function f.At(time, step)
			clock = time
			if step then
				Combat:Step()
			end
		end
		local ok, err = xpcall(function()
			callback(f)
		end, debug.traceback)
		Combat:_ConfigureForTests(nil)
		Combat:ConfigureTransactions(nil)
		for _, instance in instances do
			instance:Destroy()
		end
		if not ok then
			error(err)
		end
	end

	describe("Phase10 actual player combat deadlines and restrictions", function()
		it(
			"counts world-ready elapsed time between samples and preserves acknowledged playtime on readiness loss",
			function()
				fixture(function(f)
					local saved = { WorldReadyPlaytimeSeconds = 899.5 }
					local previous = Profile.GetReadableData
					Profile.GetReadableData = function()
						return saved
					end
					local ok, failure = xpcall(function()
						Combat:_ConfigureForTests({
							Now = f.Now,
							Ready = function(p)
								return p.Ready
							end,
							Camp = function()
								return false
							end,
							Players = function()
								return f.Players
							end,
						})
						f.At(100, true)
						f.At(100.499)
						expect(Combat:GetPlaytime(f.A) < 900).to.equal(true)
						f.At(100.5)
						expect(Combat:GetPlaytime(f.A)).to.equal(900)
						expect(Combat:CanAttack(f.A, f.B)).to.equal(true)
						f.A.Ready = false
						f.At(100.6, true)
						expect(Combat:GetPlaytime(f.A) >= 900).to.equal(true)
					end, debug.traceback)
					Profile.GetReadableData = previous
					if not ok then
						error(failure)
					end
				end)
			end
		)
		it("rejects replay-untrackable request IDs before a real player impact mutation", function()
			fixture(function(f)
				Combat:ConfigureTransactions({
					Cargo = {
						ResolveHit = function()
							return nil
						end,
					},
					Carry = {
						GetCarriedRecord = function()
							return nil
						end,
					},
				})
				local hit = { Instance = f.B.Root, Position = f.B.Root.Position }
				for _, id in { 0, -1, 1.5, 0 / 0, math.huge, 9007199254740992 } do
					local handled, reason = Combat:ResolveImpact(
						f.A,
						{ Character = f.A.Character },
						hit,
						hit,
						{ RequestId = id }
					)
					expect(handled).to.equal(true)
					expect(reason).to.equal("StaleTarget")
					expect(f.B:GetAttribute("Phase10DazeEnd")).to.equal(nil)
				end
				local handled, reason = Combat:ResolveImpact(
					f.A,
					{ Character = f.A.Character },
					hit,
					hit,
					{ RequestId = 1 }
				)
				expect(handled).to.equal(true)
				expect(reason).to.equal("PlayerDazed")
				expect(f.B:GetAttribute("Phase10DazeEnd")).to.equal(103)
			end)
		end)
		it("dazes for three and gives exactly five natural recovery seconds", function()
			fixture(function(f)
				local speed, jump = f.B.Humanoid.WalkSpeed, f.B.Humanoid.JumpPower
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(true)
				expect(f.B:GetAttribute("Phase10DazeEnd")).to.equal(103)
				expect(f.B.Humanoid.WalkSpeed).to.equal(0)
				expect(f.B.Humanoid.JumpPower).to.equal(0)
				f.At(102.999, true)
				expect(Combat:IsDazed(f.B)).to.equal(true)
				expect(Combat:CanAct(f.B)).to.equal(false)
				f.At(103, true)
				expect(Combat:IsDazed(f.B)).to.equal(false)
				expect(Combat:CanAct(f.B)).to.equal(true)
				expect(f.B.Humanoid.WalkSpeed).to.equal(speed)
				expect(f.B.Humanoid.JumpPower).to.equal(jump)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(108)
				f.At(107.999)
				expect(Combat:CanAttack(f.C, f.B)).to.equal(false)
				f.At(108)
				expect(Combat:CanAttack(f.C, f.B)).to.equal(true)
			end)
		end)
		it("has no accepted-hit gap at the natural deadline before the next sampling tick", function()
			fixture(function(f)
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(true)
				f.At(103) -- No Step yet: eligibility must settle the same deadline.
				expect(Combat:CanAttack(f.C, f.B)).to.equal(false)
				expect(Combat:CommitDaze(f.C, f.B, f.B.Character)).to.equal(false)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(108)
			end)
		end)
		it("does not refresh daze/protection or accept two same-time outcomes", function()
			fixture(function(f)
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(true)
				expect(Combat:CommitCargoProtection(f.C, f.B)).to.equal(false)
				f.At(101)
				expect(Combat:CommitDaze(f.C, f.B, f.B.Character)).to.equal(false)
				expect(f.B:GetAttribute("Phase10DazeEnd")).to.equal(103)
				expect(f.B:GetAttribute("Phase10DazeRevision")).to.equal(1)
				f.At(103, true)
				f.At(106)
				expect(Combat:CommitCargoProtection(f.C, f.B)).to.equal(false)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(108)
			end)
		end)
		it("ends daze on Camp entry once and caps protection at the original timeline", function()
			fixture(function(f)
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(true)
				f.B.Root.Position = Vector3.new(0, 100, 9000)
				f.At(101, true)
				expect(Combat:IsDazed(f.B)).to.equal(false)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(106)
				expect(f.B.Humanoid.WalkSpeed > 0).to.equal(true)
				f.B.Root.Position = Vector3.new(9000, 100, 9000)
				f.At(102, true)
				f.B.Root.Position = Vector3.new(0, 100, 9000)
				f.At(104, true)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(106)
				expect(Combat:FinishDaze(f.B, 105)).to.equal(false)
			end)
		end)
		it("rejects either participant in Camp and cargo Camp positions without side effects", function()
			fixture(function(f)
				f.A.Root.Position = Vector3.new(0, 100, 9000)
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(false)
				expect(f.B:GetAttribute("Phase10DazeEnd")).to.equal(nil)
				f.A.Root.Position = Vector3.new(9000, 100, 9000)
				f.B.Root.Position = Vector3.new(0, 100, 9000)
				expect(Combat:CanAttack(f.A, f.B)).to.equal(false)
				f.B.Root.Position = Vector3.new(9000, 100, 9000)
				expect(Combat:CanAttack(f.A, f.B, Vector3.new(0, 100, 9000))).to.equal(false)
				expect(Combat:CanAttack(f.A, f.B)).to.equal(true)
			end)
		end)
		it("expires beginner protection at exactly 900 while preserving ordinary actions", function()
			fixture(function(f)
				f.A.Playtime = 899.999
				expect(Combat:CanAttack(f.A, f.B)).to.equal(false)
				expect(Combat:CanAct(f.A)).to.equal(true)
				f.A.Playtime = 900
				expect(Combat:CanAttack(f.A, f.B)).to.equal(true)
				f.B.Playtime = 899.999
				expect(Combat:CanAttack(f.A, f.B)).to.equal(false)
			end)
		end)
		it("grants cargo protection immediately for five and blocks protected PvP initiation", function()
			fixture(function(f)
				expect(Combat:CommitCargoProtection(f.A, f.B)).to.equal(true)
				expect(Combat:IsDazed(f.B)).to.equal(false)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(105)
				expect(f.B.Humanoid.WalkSpeed > 0).to.equal(true)
				expect(Combat:CanAttack(f.B, f.C)).to.equal(false)
				expect(Combat:CanAct(f.B)).to.equal(true)
				f.At(104.999)
				expect(Combat:CommitCargoProtection(f.C, f.B)).to.equal(false)
				expect(f.B:GetAttribute("Phase10ProtectionEnd")).to.equal(105)
				f.At(105)
				expect(Combat:CanAttack(f.C, f.B)).to.equal(true)
			end)
		end)
		it("keeps the sixty-second restriction directional and independent of cart/session object swaps", function()
			fixture(function(f)
				expect(Combat:CommitCargoProtection(f.A, f.B)).to.equal(true)
				f.At(105)
				expect(Combat:CanAttack(f.B, f.A)).to.equal(true)
				expect(Combat:CanAttack(f.A, f.B)).to.equal(false)
				expect(Combat:CanAttack(f.A, f.C)).to.equal(true)
				expect(Combat:CanAttack(f.C, f.B)).to.equal(true)
				local reconnect = { UserId = f.A.UserId, Character = f.A.Character, Ready = true, Playtime = 900 }
				expect(Combat:CanAttack(reconnect, f.B)).to.equal(false)
				f.At(159.999)
				expect(Combat:CanAttack(f.A, f.B)).to.equal(false)
				f.At(160)
				expect(Combat:CanAttack(f.A, f.B)).to.equal(true)
			end)
		end)
		it("cannot restore stale physical properties onto a replacement character", function()
			fixture(function(f)
				expect(Combat:CommitDaze(f.A, f.B, f.B.Character)).to.equal(true)
				local model, humanoid = f.Character(999)
				humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate = 23, 64, true
				f.B.Character = model
				f.At(103)
				expect(Combat:FinishDaze(f.B, 103)).to.equal(true)
				expect(humanoid.WalkSpeed).to.equal(23)
				expect(humanoid.JumpPower).to.equal(64)
				expect(humanoid.AutoRotate).to.equal(true)
				expect(Combat:CommitDaze(f.C, f.B, f.A.Character)).to.equal(false)
			end)
		end)
	end)
end
