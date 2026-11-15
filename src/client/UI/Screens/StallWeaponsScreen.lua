--!nocheck
-- MenusV2 Weapons stall (from "Trail Shop"). Opened only by the Weapons stall prompt (server
-- Phase13Update {kind="Open", category="Weapon"}); Phase13ShopController keeps every remote call:
--   Equip  -> ctx.select("Weapon", id)   = mutate("Select", "Weapon", id)
--   Buy    -> ctx.buy("Weapon", id)      = mutate(Strings.Purchase, "Weapon", id)
--   Gems   -> ctx.gemShop(itemId)        = {action="GemShop", itemId, operationId}
--   Robux  -> ctx.prompt(passId)         = {action="Prompt", offerId}
-- Every number comes from Config/Weapons or the server snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Tiers = require(ReplicatedStorage.Shared.Config.WeaponTiersV2)

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local Screen = {}

local ctx = nil
local window = nil
local tab = "Bow"
local tabs = nil
local renderBag = nil
local seenSpecials = false -- NEW! sticker: session-only (see docs/menus_v2/REPORT.md "NEW! store")

local TABS = {
	{ id = "Bow", text = "Bows" },
	{ id = "Crossbow", text = "Crossbows" },
	{ id = "Gun", text = "Blasters" },
	{ id = "Specials", text = "Specials", variant = "alert" },
}

local function snapshot()
	return ctx and ctx.snapshot()
end

-- power tier of a special weapon (WeaponTiersV2.Specials[id].powerTier)
local function specialPower(id: string): number
	local row = Tiers.Specials and Tiers.Specials[id]
	return row and row.powerTier or 1
end

local function familyRows(family: string)
	local rows = {}
	for _, row in Weapons.GetAll() do
		if row.family == family then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		return (Tiers.TierFromWeaponId(a.id) or 0) < (Tiers.TierFromWeaponId(b.id) or 0)
	end)
	return rows
end

local function equippedName(s): string
	local def = s and Weapons.Get(s.selectedWeapon)
	return def and def.displayName or "—"
end

local function statText(s): string?
	if tab == "Specials" then
		local n = if s and type(s.specials) == "table" then #s.specials else 0
		return n .. " Specials"
	end
	local rows = familyRows(tab)
	local owned = 0
	for _, r in rows do
		if s and s.ownedWeapons[r.id] then
			owned += 1
		end
	end
	return "Owned " .. owned .. "/" .. #rows
end

local function render(pop: boolean)
	if not window then
		return
	end
	local s = snapshot()
	if renderBag then
		renderBag.clean()
	end
	renderBag = Plate.Bag()
	local area = window.Content:FindFirstChild("Cards")
	if area then
		area:Destroy()
	end
	window.setStat(statText(s))
	if tabs then
		tabs.setHint(if tab == "Specials" then "Specials can't be sold" else "Equipped: " .. equippedName(s))
	end
	if not s then
		Plate.Label(window.Content, "Loading…", { size = 20, frameSize = UDim2.new(1, 0, 0, px(40)), position = UDim2.fromOffset(0, px(60)) })
		return
	end
	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(44)),
		size = UDim2.new(1, 0, 1, -px(44)),
	})
	row.Name = "Cards"
	local cardH = window.contentSize().Y - px(44) - px(14)
	local cardSize = UDim2.fromOffset(px(158), math.max(px(170), cardH))
	local equippedSlot = nil
	local balance = s.balance or 0

	if tab ~= "Specials" then
		local rows = familyRows(tab)
		-- the ONE breathing primary: the cheapest affordable unowned weapon in this tab
		local primaryId, cheapest = nil, math.huge
		for _, r in rows do
			if not s.ownedWeapons[r.id] and r.price > 0 and r.price <= balance and r.price < cheapest then
				primaryId, cheapest = r.id, r.price
			end
		end
		for i, r in rows do
			local tier = Tiers.TierFromWeaponId(r.id) or 1
			local style = Common.tierStyle(tier)
			local card = Plate.ItemCard(row, {
				name = r.displayName,
				sub = "T" .. tier .. " · " .. (if tab == "Gun" then "Blaster" else tab),
				image = Shots.get(r.id),
				background = style.background,
				rainbow = style.rainbow,
				radial = style.radial,
				rays = style.rays,
				size = cardSize,
				index = i,
				bag = renderBag,
				pop = pop,
				onClick = function()
					ctx.preview("Weapon", r.id)
				end,
			})
			Plate.Pips(card.Footer, "Power", tier, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
			local owned = s.ownedWeapons[r.id] == true
			local selected = s.selectedWeapon == r.id
			if selected then
				equippedSlot = card.Root
				Common.Action(card, { kind = "well", text = "Equipped", bag = renderBag })
			elseif owned then
				Common.Action(card, { kind = "info", text = "Equip", bag = renderBag, onClick = function()
					ctx.select("Weapon", r.id)
				end })
			elseif r.price <= balance then
				Common.Action(card, {
					kind = "go",
					text = Common.money(r.price),
					icon = Theme.Icons.Cash,
					primary = r.id == primaryId,
					bag = renderBag,
					onClick = function()
						ctx.buy("Weapon", r.id)
					end,
				})
			else
				Common.Action(card, { kind = "locked", text = "Need " .. Common.money(r.price), bag = renderBag })
			end
		end
	else
		local specials = if type(s.specials) == "table" then s.specials else {}
		local gems = s.economy and s.economy.gems or 0
		local passes = s.commerce and s.commerce.Passes or {}
		for i, sp in specials do
			local unlock = sp.unlock or {}
			local power = specialPower(sp.id)
			local bg = if unlock.kind == "Pass" then P.Tier.Robux
				elseif unlock.kind == "Gems" then P.Tier.Gem
				elseif unlock.medal == "Gold" then P.Tier.WonGold
				elseif unlock.medal == "Silver" then P.Tier.WonSilver
				else P.Tier.WonBronze
			local def = Weapons.Get(sp.id)
			local card = Plate.ItemCard(row, {
				name = sp.name,
				sub = (sp.source or "") .. " · " .. (if def and def.family == "Gun" then "Blaster" else (def and def.family or "")),
				image = Shots.get(sp.id),
				background = bg,
				rays = true,
				size = cardSize,
				index = i,
				bag = renderBag,
				pop = pop,
				onClick = function()
					ctx.preview("Weapon", sp.id)
				end,
			})
			if sp.owned then
				Plate.Pips(card.Footer, "Power", power, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
				if s.selectedWeapon == sp.id then
					equippedSlot = card.Root
					Common.Action(card, { kind = "well", text = "Equipped", bag = renderBag })
				else
					Common.Action(card, { kind = "info", text = "Equip", bag = renderBag, onClick = function()
						ctx.select("Weapon", sp.id)
					end })
				end
			elseif unlock.kind == "Milestone" then
				local label = if unlock.milestone == "SpeciesDiscovered" then "Species"
					elseif unlock.milestone == "CleanEscapes" then "Escapes"
					else "Secret"
				local target = math.max(1, sp.target or unlock.target or 1)
				local progress = sp.progress or 0
				Plate.StripedProgress(card.Footer, {
					frac = progress / target,
					text = string.format("%d/%d %s", progress, target, label),
					size = UDim2.new(0.9, 0, 0, px(24)),
					order = 1,
					bag = renderBag,
				})
				Common.Action(card, { kind = "locked", text = "Win it", bag = renderBag })
			elseif unlock.kind == "Gems" then
				Plate.Pips(card.Footer, "Power", power, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
				local cost = unlock.gems or 0
				if gems >= cost then
					Common.Action(card, { kind = "gem", text = tostring(cost), icon = Theme.Icons.Gem, bag = renderBag, onClick = function()
						ctx.gemShop(unlock.itemId)
					end })
				else
					Common.Action(card, { kind = "locked", text = "Need " .. cost .. " Gems", bag = renderBag })
				end
			elseif unlock.kind == "Pass" then
				Plate.Pips(card.Footer, "Power", power, 8, { size = UDim2.new(0.9, 0, 0, px(22)), order = 1 })
				local passRow = nil
				for _, p in passes do
					if p.id == (unlock.passId or sp.id) then
						passRow = p
					end
				end
				local price = passRow and ctx.regionalPrice(passRow)
				if passRow and passRow.enabled and price then
					Common.Action(card, { kind = "robux", text = utf8.char(0xE002) .. " " .. tostring(price), bag = renderBag, onClick = function()
						local result = ctx.prompt(passRow.id)
						if result and not result.ok then
							Screen.notify(result, ctx.message(result))
						end
					end })
				else
					-- honest: Robux sales are not open (no platform id / delivery disabled)
					Common.Action(card, { kind = "locked", text = "Robux soon", bag = renderBag })
				end
			end
		end
		if #specials == 0 then
			Plate.Label(row, "No specials yet", { size = 18, frameSize = UDim2.fromOffset(px(300), px(40)) })
		end
	end
	Common.scrollTo(row, equippedSlot)
end

local function selectTab(id: string)
	if id == tab then
		return
	end
	tab = id
	if id == "Specials" then
		seenSpecials = true
		local tabButton = window and window.Content:FindFirstChild("Tab_Specials", true)
		local sticker = tabButton and tabButton:FindFirstChild("NewSticker")
		if sticker then
			sticker:Destroy()
		end
	end
	if tabs then
		tabs.setActive(id)
	end
	render(true)
end

local function buildTabs()
	local list = {}
	for _, t in TABS do
		table.insert(list, { id = t.id, text = t.text, variant = t.variant, new = t.id == "Specials" and not seenSpecials })
	end
	tabs = Plate.Tabs(window.Content, { tabs = list, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 104 })
end

function Screen.open(context, _category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "Weapons",
			title = "Weapons",
			icon = Shots.get("HRP_001"),
			onClose = function()
				ctx.close()
			end,
		})
	end
	-- open on the family of the equipped weapon
	local s = snapshot()
	local def = s and Weapons.Get(s.selectedWeapon)
	tab = if def and Weapons.IsSpecial(def.id) then "Specials" elseif def then def.family else "Bow"
	window.open()
	window.clearContent()
	buildTabs()
	task.defer(render, true)
end

function Screen.update()
	render(false)
end

function Screen.notify(result, text)
	Common.notify(MenusV2.Gui(), result, text)
end

function Screen.close(instant: boolean?)
	if renderBag then
		renderBag.clean()
		renderBag = nil
	end
	tabs = nil
	if window then
		window.close(instant)
	end
end

return Screen
