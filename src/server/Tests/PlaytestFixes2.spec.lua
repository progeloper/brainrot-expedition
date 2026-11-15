--!nocheck
-- Playtest Fixes 2: Parts A (menu-open predicate + watchdog decisions), B (Jump -> HOP OUT debounce)
-- and E (opt-in previews, switch table, stall audit verdict).
return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local Policy = require(Client.Utility.Phase10InputPolicy)
	local InputUnstick = require(Client.Utility.InputUnstick)
	local StallAudit = require(Client.Utility.StallAudit)
	local Rules = require(ReplicatedStorage.Shared.Utility.DriveAndHuntRules)
	local SwitchTable = require(ReplicatedStorage.Shared.Utility.SwitchTable)
	local Fixes2Flags = require(ReplicatedStorage.Shared.Config.PlaytestFixes2Flags)
	local CampFlags = require(ReplicatedStorage.Shared.Config.CampReworkFlags)
	local CashPadRules = require(ReplicatedStorage.Shared.Utility.CashPadRules)
	local BarGuard = require(ReplicatedStorage.Shared.UI.BarGuard)
	local Legs = require(ReplicatedStorage.Shared.Config.LegsTraining)
	local Phase13Rules = require(ReplicatedStorage.Shared.Utility.Phase13Rules)
	local GemRules = require(ReplicatedStorage.Shared.Utility.GemRules)
	local LegsFlags = require(ReplicatedStorage.Shared.Config.LegsTrainingFlags)
	local LegsService =
		require(game:GetService("ServerScriptService").Server.Services.LegsTrainingService)

	-- A PlayerGui stand-in with a HUD gui and the MenusV2 gui.
	local function fixture(callback)
		local root = Instance.new("Folder")
		root.Name = "PlayerGui"
		local function screen(name)
			local g = Instance.new("ScreenGui")
			g.Name = name
			g.Parent = root
			local b = Instance.new("TextButton")
			b.Parent = g
			return g, b
		end
		local _, hudButton = screen("StudPopHud")
		local menus, menuButton = screen("MenusV2")
		local attributes = {}
		local player = {}
		function player:GetAttribute(name)
			return attributes[name]
		end
		function player:FindFirstChildOfClass()
			return root
		end
		local gui = { MenuIsOpen = false, SelectedObject = nil }
		local input = {}
		function input:GetFocusedTextBox()
			return nil
		end
		local ok, err = xpcall(function()
			callback({
				player = player,
				attributes = attributes,
				gui = gui,
				input = input,
				root = root,
				menus = menus,
				hudButton = hudButton,
				menuButton = menuButton,
			})
		end, debug.traceback)
		root:Destroy()
		if not ok then
			error(err)
		end
	end

	describe("A: menu-open predicate", function()
		it("a stray HUD selection blocks only with InputUnstick off", function()
			fixture(function(f)
				f.gui.SelectedObject = f.hudButton
				expect(Policy.IsMenuOpen(f.player, f.gui, f.input, false)).to.equal(true)
				expect(Policy.IsMenuOpen(f.player, f.gui, f.input, true)).to.equal(false)
			end)
		end)
		it("a selection inside an open menu window still blocks", function()
			fixture(function(f)
				f.gui.SelectedObject = f.menuButton
				expect(Policy.IsMenuOpen(f.player, f.gui, f.input, true)).to.equal(false)
				f.attributes.MenusV2Open = "shop"
				expect(Policy.IsMenuOpen(f.player, f.gui, f.input, true)).to.equal(true)
			end)
		end)
		it("a hidden or orphaned selection never blocks", function()
			fixture(function(f)
				f.attributes.Phase13ConsentDialogOpen = true
				f.menuButton.Visible = false
				expect(InputUnstick.SelectionBlocks(f.menuButton, f.root, function(n)
					return f.attributes[n]
				end)).to.equal(false)
				f.menuButton.Visible = true
				expect(InputUnstick.SelectionBlocks(f.menuButton, f.root, function(n)
					return f.attributes[n]
				end)).to.equal(true)
				f.menuButton.Parent = nil
				expect(InputUnstick.SelectionBlocks(f.menuButton, f.root, function(n)
					return f.attributes[n]
				end)).to.equal(false)
			end)
		end)
		it("attribute rules: names, empty strings and false are 'not open'", function()
			expect(InputUnstick.AttributeSet("DailyGift")).to.equal(true)
			expect(InputUnstick.AttributeSet(true)).to.equal(true)
			expect(InputUnstick.AttributeSet("")).to.equal(false)
			expect(InputUnstick.AttributeSet(false)).to.equal(false)
			expect(InputUnstick.AttributeSet(nil)).to.equal(false)
		end)
		it("the open attributes still block exactly as before", function()
			fixture(function(f)
				expect(Policy.IsMenuOpen(f.player, f.gui, f.input, true)).to.equal(false)
				for _, name in
					{ "Phase13ShopOpen", "ChariotTeamMenuOpen", "RetentionPublicInspectOpen" }
				do
					f.attributes[name] = true
					expect(Policy.IsMenuOpen(f.player, f.gui, f.input, true)).to.equal(true)
					f.attributes[name] = nil
				end
			end)
		end)
	end)

	describe("B: Jump -> HOP OUT debounce", function()
		it("ignores Jump during the seated grace and repeats inside the interval", function()
			expect(Rules.JumpHopAllowed(10.1, 10, -math.huge, 0.3, 0.3)).to.equal(false)
			expect(Rules.JumpHopAllowed(10.35, 10, -math.huge, 0.3, 0.3)).to.equal(true)
			expect(Rules.JumpHopAllowed(11.0, 10, 10.8, 0.3, 0.3)).to.equal(false)
			expect(Rules.JumpHopAllowed(11.15, 10, 10.8, 0.3, 0.3)).to.equal(true)
		end)
	end)

	describe("C: cash-pad poll decision", function()
		it("claims on entry, then every RepeatSeconds while the pad holds >= MinClaim", function()
			expect(CashPadRules.ShouldClaim(false, false, 10, -math.huge, 50, 1, 1)).to.equal(false)
			expect(CashPadRules.ShouldClaim(true, false, 10, 9.9, 0, 1, 1)).to.equal(true) -- entry
			expect(CashPadRules.ShouldClaim(true, true, 10.5, 10, 50, 1, 1)).to.equal(false) -- too soon
			expect(CashPadRules.ShouldClaim(true, true, 11, 10, 50, 1, 1)).to.equal(true)
			expect(CashPadRules.ShouldClaim(true, true, 11, 10, 0.5, 1, 1)).to.equal(false) -- < MinClaim
		end)
		it("extrapolates unclaimed cash from the replicated snapshot", function()
			expect(CashPadRules.Unclaimed(10, 2, 100, 105)).to.equal(20)
			expect(CashPadRules.Unclaimed(nil, nil, nil, 105)).to.equal(0)
			expect(CashPadRules.Unclaimed(5, 2, 110, 105)).to.equal(5) -- never negative time
		end)
		it("grows the stack in three steps and hides at 0", function()
			local steps = { 10, 60 }
			expect(CashPadRules.StackStep(0, 2, steps)).to.equal(0)
			expect(CashPadRules.StackStep(10, 2, steps)).to.equal(1) -- 5 s
			expect(CashPadRules.StackStep(40, 2, steps)).to.equal(2) -- 20 s
			expect(CashPadRules.StackStep(200, 2, steps)).to.equal(3) -- 100 s
		end)
		it("starts off-screen coins on the nearest screen edge", function()
			local vp = Vector2.new(800, 400)
			local o = CashPadRules.CoinOrigin(Vector2.new(2000, 200), false, vp, 20)
			expect(math.abs(o.X - 780) < 0.01).to.equal(true)
			expect(math.abs(o.Y - 200) < 0.01).to.equal(true)
			expect(CashPadRules.CoinOrigin(Vector2.new(10, 10), true, vp, 20)).to.equal(
				Vector2.new(10, 10)
			)
			expect(CashPadRules.CoinCount(true, 8, 4)).to.equal(4)
			expect(CashPadRules.CoinCount(false, 8, 4)).to.equal(8)
		end)
	end)

	describe("F: progress bar guard", function()
		it("ignores sub-threshold moves with the same label", function()
			expect(BarGuard.ShouldUpdate(0.5, 0.501, "50%", "50%", 0.002)).to.equal(false)
			expect(BarGuard.ShouldUpdate(0.5, 0.503, "50%", nil, 0.002)).to.equal(true)
			expect(BarGuard.ShouldUpdate(0.5, 0.5, "50%", "51%", 0.002)).to.equal(true)
			expect(BarGuard.ShouldUpdate(nil, 0.5, nil, nil, 0.002)).to.equal(true)
		end)
		it("pops only when crossing to full and hides tiny fills", function()
			expect(BarGuard.CrossedFull(0.9, 1)).to.equal(true)
			expect(BarGuard.CrossedFull(1, 1)).to.equal(false)
			expect(BarGuard.CrossedFull(0.5, 0.9)).to.equal(false)
			expect(BarGuard.FillVisible(0.03, 0.04)).to.equal(false)
			expect(BarGuard.FillVisible(0.04, 0.04)).to.equal(true)
		end)
		it("phase-locks the stripe scroll to the clock", function()
			expect(BarGuard.Phase(0.45, 0.9)).to.equal(0.5)
			expect(math.abs(BarGuard.Phase(1.35, 0.9) - 0.5) < 1e-9).to.equal(true)
		end)
	end)

	describe("G: Legs training", function()
		local function profile(level, xp)
			return {
				Phase13 = { LegsLevel = level, LegsXP = xp, OwnedTrails = {}, EquippedTrail = "" },
				Economy = { Gems = 1000 },
			}
		end
		it("maps Legs level to WalkSpeed 16 -> 26 with no cap", function()
			expect(Legs.WalkSpeed(0)).to.equal(16)
			expect(Legs.WalkSpeed(15)).to.equal(26)
			expect(Legs.WalkSpeed(99)).to.equal(26)
			expect(math.abs(Legs.WalkSpeed(3) - 18) < 1e-9).to.equal(true)
			expect(Legs.XpToNext(0)).to.equal(60)
			expect(Legs.XpToNext(15)).to.equal(math.huge)
		end)
		it("levels up through ticks and grants the free trails at 5 / 10 / 15", function()
			local data = profile(4, Legs.XpToNext(4) - 1)
			local ok, out = Phase13Rules.ApplyLegsTick(data, 1)
			expect(ok).to.equal(true)
			expect(out.levels).to.equal(1)
			expect(data.Phase13.LegsLevel).to.equal(5)
			expect(data.Phase13.OwnedTrails.TRAIL_GREEN).to.equal(true)
			expect(out.unlocked[1]).to.equal("TRAIL_GREEN")
			local maxed = profile(15, 0)
			local _, m = Phase13Rules.ApplyLegsTick(maxed, 1)
			expect(m.levels).to.equal(0)
			expect(maxed.Phase13.LegsXP).to.equal(0)
			expect((Phase13Rules.ApplyLegsTick(profile(0, 0), -1))).to.equal(false)
		end)
		it("equips owned trails only, one at a time", function()
			local data = profile(5, 0)
			expect((Phase13Rules.ApplyTrailEquip(data, "TRAIL_GREEN"))).to.equal(false) -- not owned yet
			data.Phase13.OwnedTrails.TRAIL_GREEN = true
			expect((Phase13Rules.ApplyTrailEquip(data, "TRAIL_GREEN"))).to.equal(true)
			expect(data.Phase13.EquippedTrail).to.equal("TRAIL_GREEN")
			expect((Phase13Rules.ApplyTrailEquip(data, "TRAIL_NOPE"))).to.equal(false)
			expect((Phase13Rules.ApplyTrailEquip(data, ""))).to.equal(true)
			expect(data.Phase13.EquippedTrail).to.equal("")
		end)
		it("migrates an old profile to zero / empty and validates the fields", function()
			local data = { Phase13 = {} }
			expect(Phase13Rules.MigrateLegs(data, true)).to.equal(true)
			expect(data.Phase13.LegsLevel).to.equal(0)
			expect(data.Phase13.LegsXP).to.equal(0)
			expect(next(data.Phase13.OwnedTrails)).to.equal(nil)
			expect(data.Phase13.EquippedTrail).to.equal("")
			expect(Phase13Rules.MigrateLegs(data, true)).to.equal(false) -- idempotent
			local saved = {
				Phase13 = {
					LegsLevel = 11,
					LegsXP = 5,
					OwnedTrails = {},
					EquippedTrail = "TRAIL_FIRE",
				},
			}
			Phase13Rules.MigrateLegs(saved, true)
			expect(saved.Phase13.OwnedTrails.TRAIL_GREEN).to.equal(true)
			expect(saved.Phase13.OwnedTrails.TRAIL_PURPLE).to.equal(true)
			expect(saved.Phase13.OwnedTrails.TRAIL_GOLD).to.equal(nil)
			expect(saved.Phase13.EquippedTrail).to.equal("") -- unowned equip is dropped
		end)
		it("sells gem trails once, only with the flag on", function()
			local previous = LegsFlags._SetForTests(true)
			local data = profile(0, 0)
			local ok, out = GemRules.ApplyShopItem(data, "TRAIL_RAINBOW", 0)
			expect(ok).to.equal(true)
			expect(out.trailId).to.equal("TRAIL_RAINBOW")
			expect(data.Economy.Gems).to.equal(850)
			expect(data.Phase13.OwnedTrails.TRAIL_RAINBOW).to.equal(true)
			local again, code = GemRules.ApplyShopItem(data, "TRAIL_RAINBOW", 0)
			expect(again).to.equal(false)
			expect(code.code).to.equal("ALREADY_OWNED")
			LegsFlags._SetForTests(false)
			expect((GemRules.ApplyShopItem(profile(0, 0), "TRAIL_FIRE", 0))).to.equal(false)
			LegsFlags._SetForTests(previous)
		end)
		it("finds a player standing on the belt", function()
			local frame, size = CFrame.new(0, 1, 0), Vector3.new(4, 0.25, 9)
			expect(LegsService.OnBelt(frame, size, Vector3.new(0, 4, 3), 6)).to.equal(true)
			expect(LegsService.OnBelt(frame, size, Vector3.new(3, 4, 0), 6)).to.equal(false)
			expect(LegsService.OnBelt(frame, size, Vector3.new(0, 9, 0), 6)).to.equal(false)
		end)
	end)

	describe("E: Studio parity", function()
		it("Studio previews are opt-in for every gate family", function()
			expect(CampFlags.Resolve(false, true, nil)).to.equal(false)
			expect(CampFlags.Resolve(false, true, false)).to.equal(false)
			expect(CampFlags.Resolve(false, true, true)).to.equal(true)
			expect(CampFlags.Resolve(false, false, true)).to.equal(false)
			expect(CampFlags.Resolve(true, false, nil)).to.equal(true)
			expect(Fixes2Flags.Resolve(false, true, nil)).to.equal(false)
			expect(Fixes2Flags.Resolve(false, false, true)).to.equal(false)
			expect(SwitchTable.Resolve(false, true, nil)).to.equal(false)
			expect(SwitchTable.Resolve(false, false, true)).to.equal(false)
		end)
		it("the switch hash changes when any switch changes", function()
			local a = { { name = "A", flag = false, preview = false, resolved = false } }
			local b = { { name = "A", flag = false, preview = false, resolved = true } }
			expect(SwitchTable.HashRows(a)).never.to.equal(SwitchTable.HashRows(b))
			expect(#SwitchTable.HashRows(a)).to.equal(6)
		end)
		it("stall audit verdicts", function()
			expect((StallAudit.Verdict(1, "Weapon", { Weapon = 2 }))).to.equal(true)
			expect((StallAudit.Verdict(2, "Cart", nil))).to.equal(false)
			expect((StallAudit.Verdict(0, false, nil))).to.equal(true)
			expect((StallAudit.Verdict(1, false, nil))).to.equal(false)
			expect((StallAudit.Verdict(1, "Sell", { Passes = 1 }))).to.equal(false)
		end)
	end)
end
