--!nocheck
-- MenusV2 "Passes & Gems" window (Announcements kiosk / HUD Shop & Gems openers). Phase13ShopController
-- routes the categories Passes, Cash and Cosmetics here and keeps every remote call:
--   Robux  -> ctx.prompt(offerId)  = {action="Prompt", offerId}            (legacy :1192)
--   Gems   -> ctx.gemShop(itemId)  = {action="GemShop", itemId, operationId} (legacy :1120)
--   Preview -> ctx.previewSet(items) (local dialog): VIP (Riftgold base / cart / weapon + the VIP rift),
--              Starter Pack (Trailblazer cart + weapon), and the DEV-only finish preview.
--   OfferView and the open cue are sent by the controller when it opens Passes/Cash.
-- Every number (prices, amounts, bonus %, BEST VALUE, gem costs, crate Cash) comes from the server
-- snapshot or MarketplaceService (ctx.regionalPrice). Rows that are not on sale say so; no fake prices.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local Config = require(ReplicatedStorage.Shared.Config.Phase13)
local Finishes = require(ReplicatedStorage.Shared.Config.Phase13OptionalFinishes).Finishes

local Plate, Theme, Shots = Common.Plate, Common.Theme, Common.Shots
local P = Theme.Plate
local px = Theme.px

local Screen = {}

local ROBUX = utf8.char(0xE002)
local NOT_ON_SALE = "Not on sale yet"

local ctx = nil
local window = nil
local tab = "Passes"
local tabs = nil
local renderBag = nil
-- Finish previews are DEV-only: the exact DEV Studio target, never a grant (legacy guard). Opt-in
-- (ReplicatedStorage.FinishPreview = true) so a normal Studio Play shows the store a device shows
-- (Playtest Fixes 2, Part E1).
local DEV_PREVIEW = RunService:IsStudio()
	and game.PlaceId == 91958083796436
	and game.GameId == 10548905405
	and game:GetService("ReplicatedStorage"):GetAttribute("FinishPreview") == true

local TABS = {
	{ id = "Passes", text = "Passes", variant = "robux" },
	{ id = "Gems", text = "Gems", variant = "gem" },
	{ id = "GemShop", text = "Gem Shop", variant = "gem" },
}
-- controller category -> opening tab
local TAB_FOR = { Passes = "Passes", Cash = "Gems", Cosmetics = "GemShop" }

-- card art: a display shot when one exists, otherwise the matching currency/meaning icon
local PASS_ICONS = {
	STARTER_PACK = Theme.Icons.Gift,
	INCOME_2X = Theme.Icons.Cash,
	VIP = Theme.Icons.Rebirth,
	AUTO_COLLECT = Theme.Icons.Cash,
	TRAINING_2X = Theme.Icons.Bolt,
}
local ITEM_ICONS = {
	CashBoost = Theme.Icons.Bolt,
	CashCrate = Theme.Icons.Cash,
	MutationStorm = Theme.Icons.Rebirth,
}

local function snapshot()
	return ctx and ctx.snapshot()
end

local function gemsOf(s): number
	return s and s.economy and s.economy.gems or 0
end

-- first `n` words of the server description (rows are short today; never rewritten)
local function shortText(text: string?, n: number): string
	if type(text) ~= "string" then
		return ""
	end
	local words = {}
	for w in text:gmatch("%S+") do
		table.insert(words, w)
	end
	if #words <= n then
		return text
	end
	return table.concat(words, " ", 1, n) .. "…"
end

local function imageFor(id: string?, fallback: string): string
	if id and Shots.has(id) then
		return Shots.get(id)
	end
	return fallback
end

local function minutes(seconds: number?): string?
	if type(seconds) ~= "number" or seconds <= 0 then
		return nil
	end
	if seconds >= 3600 and seconds % 3600 == 0 then
		return (seconds // 3600) .. " h"
	end
	return math.floor(seconds / 60 + 0.5) .. " min"
end

-- wrapped description inside a card footer (>= 14 px)
local function footerText(card, text: string, order: number, color: Color3?, height: number?)
	if text == "" then
		return
	end
	Plate.Label(card.Footer, text, {
		size = 15,
		min = 14,
		wrap = true,
		color = color,
		frameSize = UDim2.new(0.94, 0, 0, px(height or 40)),
		order = order,
		z = 9,
	})
end

-- Robux purchase action: price shown before any prompt; locked when the row is not on sale.
-- Mirrors the legacy guard `busy or pending or not available or row.owned` (busy/pending in ctx.prompt).
local function robuxAction(card, row)
	if row.owned then
		Common.Action(card, { kind = "well", text = "Owned", bag = renderBag })
		return
	end
	local price = if row.enabled == true then ctx.regionalPrice(row) else nil
	if row.enabled == true and price ~= nil then
		Common.Action(card, {
			kind = "robux",
			text = ROBUX .. " " .. tostring(price),
			bag = renderBag,
			onClick = function()
				local result = ctx.prompt(row.id)
				if result and not result.ok then
					Screen.notify(result, ctx.message(result))
				end
			end,
		})
		return
	end
	-- not on sale, or the localized price is still loading (the controller re-renders when it arrives)
	Common.Action(card, { kind = "locked", text = NOT_ON_SALE, bag = renderBag })
end

-- assetName of the cart the player drives (previews look carts up by asset name)
local function selectedCartAsset(s): string?
	for _, cart in Config.CartRows do
		if cart.id == s.selectedCart then
			return cart.assetName
		end
	end
	return nil
end

-- The legacy Passes tab's preview buttons for this row, with the same arguments, read from the
-- snapshot at tap time. Empty for rows that never had one.
local function previewItems(row): { any }
	local s = snapshot()
	if not s then
		return {}
	end
	local items = {}
	if row.id == "VIP" then
		table.insert(items, { label = "Base", kind = "Base", id = s.selectedDesign, finish = "Riftgold" })
		local cart = selectedCartAsset(s)
		if cart then
			table.insert(items, { label = "Cart", kind = "Cart", id = cart, finish = "Riftgold" })
		end
		table.insert(items, { label = "Weapon", kind = "Weapon", id = s.selectedWeapon, finish = "Riftgold" })
		table.insert(items, { label = "Rift", rift = true }) -- the VIP rift
	elseif row.id == "STARTER_PACK" then
		table.insert(items, { label = "Cart", kind = "Cart", id = "ScrapChariot", finish = "Trailblazer" })
		table.insert(items, { label = "Weapon", kind = "Weapon", id = "HRP_001", finish = "Trailblazer" })
	end
	local finish = Finishes[row.id]
	if finish and DEV_PREVIEW then
		if finish.Category == "Weapon" then
			table.insert(items, { label = "Weapon", kind = "Weapon", id = s.selectedWeapon, finish = row.id })
		elseif finish.Category == "Base" then
			table.insert(items, { label = "Base", kind = "Base", id = s.selectedDesign, finish = row.id })
		elseif finish.Category == "Cart" then
			local cart = selectedCartAsset(s)
			if cart then
				table.insert(items, { label = "Cart", kind = "Cart", id = cart, finish = row.id })
			end
		else
			table.insert(items, { label = "Rift", rift = true, finishId = row.id })
		end
	end
	return items
end

local function hasPreview(row): boolean
	return row.id == "VIP" or row.id == "STARTER_PACK" or (DEV_PREVIEW and Finishes[row.id] ~= nil)
end

-- Small info "Preview" button in the card footer (above the purchase action).
local function previewButton(card, row)
	Plate.Button(card.Footer, {
		variant = "info",
		text = if Finishes[row.id] then "DEV Preview" else "Preview",
		size = UDim2.new(0.9, 0, 0, px(30)),
		order = 3,
		textSize = 16,
		bag = renderBag,
		name = "Preview",
		onClick = function()
			ctx.previewSet(previewItems(row))
		end,
	})
end

local function statText(s): string
	return tostring(gemsOf(s)) .. " Gems"
end

local function hintText(s): string
	if tab == "Passes" then
		local anyOnSale = false
		for _, row in (s and s.commerce and s.commerce.Passes) or {} do
			if row.enabled == true then
				anyOnSale = true
			end
		end
		return if anyOnSale
			then "Robux prices shown before every prompt"
			else "Robux sales aren't open yet"
	elseif tab == "Gems" then
		return ctx.strings and ctx.strings.GemPacksDetail or ""
	end
	return "You have " .. tostring(gemsOf(s)) .. " Gems"
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
	for _, name in { "Cards", "Footnote" } do
		local old = window.Content:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	window.setStat(statText(s))
	if tabs then
		tabs.setHint(hintText(s))
	end
	if not s then
		Plate.Label(
			window.Content,
			"Loading…",
			{
				size = 20,
				frameSize = UDim2.new(1, 0, 0, px(40)),
				position = UDim2.fromOffset(0, px(60)),
				name = "Cards",
			}
		)
		return
	end
	local commerce = s.commerce or {}
	local footnote = nil
	if tab == "Gems" then
		local parts = {}
		for _, t in { commerce.disclosure, commerce.stormDisclosure } do
			if type(t) == "string" and t ~= "" then
				table.insert(parts, t)
			end
		end
		if #parts > 0 then
			footnote = table.concat(parts, "  ")
		end
	end
	local footH = if footnote then px(36) else 0
	local row = Common.CardRow(window.Content, {
		position = UDim2.fromOffset(0, px(44)),
		size = UDim2.new(1, 0, 1, -px(44) - footH),
	})
	row.Name = "Cards"
	if footnote then
		Plate.Label(window.Content, footnote, {
			size = 14,
			min = 14,
			wrap = true,
			color = P.Color.Hint,
			frameSize = UDim2.new(1, 0, 0, footH),
			position = UDim2.new(0, 0, 1, -footH),
			z = 6,
			name = "Footnote",
		})
	end
	local cardH = window.contentSize().Y - px(44) - footH - px(14)
	local cardSize = UDim2.fromOffset(px(158), math.max(px(170), cardH))
	local count = 0

	if tab == "Passes" then
		for i, r in commerce.Passes or {} do
			count += 1
			local preview = hasPreview(r)
			local card = Plate.ItemCard(row, {
				name = r.name or r.id,
				image = imageFor(r.id, PASS_ICONS[r.id] or Theme.Icons.Robux),
				background = P.Tier.Robux,
				rays = true,
				size = cardSize,
				imageHeight = if preview then 0.2 else 0.3, -- room for the Preview button
				index = i,
				bag = renderBag,
				pop = pop,
			})
			footerText(card, shortText(r.description, 8), 1, nil, if preview then 30 else nil)
			if preview then
				previewButton(card, r)
			end
			robuxAction(card, r)
		end
		if count == 0 then
			Plate.Label(
				row,
				"No passes yet",
				{ size = 18, frameSize = UDim2.fromOffset(px(300), px(40)) }
			)
		end
	elseif tab == "Gems" then
		local packs, storms = {}, {}
		for _, r in commerce.Cash or {} do
			if r.currency == "Gems" then
				table.insert(packs, r)
			elseif r.currency == "MutationStorm" then
				table.insert(storms, r)
			end
		end
		local i = 0
		for _, r in packs do
			i += 1
			local card = Plate.ItemCard(row, {
				name = r.name or r.id,
				sub = if type(r.amount) == "number"
					then tostring(r.amount) .. " Gems"
					else r.description,
				image = Theme.Icons.Gem,
				background = P.Tier.Robux,
				rays = r.bestValue == true,
				size = cardSize,
				index = i,
				bag = renderBag,
				pop = pop,
			})
			if type(r.bonusPercent) == "number" and r.bonusPercent > 0 then
				Plate.Label(card.Footer, "+" .. tostring(r.bonusPercent) .. "% bonus", {
					size = 16,
					min = 14,
					color = Theme.Color.GemHi,
					frameSize = UDim2.new(0.9, 0, 0, px(20)),
					order = 1,
					z = 9,
				})
			end
			if r.bestValue == true then
				-- BEST VALUE only where the server row says so
				Plate.Starburst(card.Root, "BEST\nVALUE", renderBag, {
					size = 58,
					position = UDim2.new(1, -px(22), 0, px(22)),
				})
			end
			robuxAction(card, r)
		end
		for _, r in storms do
			i += 1
			local card = Plate.ItemCard(row, {
				name = r.name or r.id,
				image = ITEM_ICONS.MutationStorm,
				background = P.Tier.Robux,
				rays = true,
				size = cardSize,
				imageHeight = 0.3,
				index = i,
				bag = renderBag,
				pop = pop,
			})
			footerText(card, shortText(r.description, 8), 1)
			robuxAction(card, r)
		end
		if i == 0 then
			Plate.Label(
				row,
				"No gem packs yet",
				{ size = 18, frameSize = UDim2.fromOffset(px(300), px(40)) }
			)
		end
	else -- GemShop
		local eco = s.economy or {}
		local gems = eco.gems or 0
		local items = table.clone(eco.shop or {})
		table.sort(items, function(a, b)
			return (a.order or 0) < (b.order or 0)
		end)
		-- the ONE breathing primary: the cheapest affordable, unowned gem item
		local primaryId, cheapest = nil, math.huge
		for _, item in items do
			if
				item.affordable == true
				and not item.owned
				and (item.priceGems or math.huge) < cheapest
			then
				primaryId, cheapest = item.id, item.priceGems
			end
		end
		local i = 0
		for _, item in items do
			i += 1
			local sub = if type(item.cash) == "number"
				then "Fixed " .. ctx.cash(item.cash)
				else minutes(item.seconds)
			local card = Plate.ItemCard(row, {
				name = item.name or item.id,
				sub = sub,
				image = imageFor(item.weaponId, ITEM_ICONS[item.kind] or Theme.Icons.Gem),
				background = P.Tier.Gem,
				rays = item.id == primaryId,
				size = cardSize,
				imageHeight = 0.3,
				index = i,
				bag = renderBag,
				pop = pop,
				onClick = if item.weaponId
					then function()
						ctx.preview("Weapon", item.weaponId)
					end
					else nil,
			})
			footerText(card, item.description or "", 1)
			local cost = item.priceGems or 0
			if item.owned then
				Common.Action(card, { kind = "well", text = "Owned", bag = renderBag })
			elseif item.affordable == true and gems >= cost then
				Common.Action(card, {
					kind = "gem",
					text = tostring(cost),
					icon = Theme.Icons.Gem,
					primary = item.id == primaryId,
					bag = renderBag,
					onClick = function()
						-- legacy guard: busy/pending (in ctx.gemShop) or not enough Gems on the fresh snapshot
						local fresh = snapshot()
						if gemsOf(fresh) < cost then
							return
						end
						ctx.gemShop(item.id)
					end,
				})
			else
				Common.Action(
					card,
					{ kind = "locked", text = "Need " .. tostring(cost) .. " Gems", bag = renderBag }
				)
			end
		end
		-- Gem-priced finishes: listed by the server but with no buy path today (enabled = false)
		for _, r in commerce.Cosmetics or {} do
			i += 1
			local card = Plate.ItemCard(row, {
				name = r.name or r.id,
				image = imageFor(r.id, Theme.Icons.Gem),
				background = P.Tier.Dark,
				size = cardSize,
				imageHeight = if hasPreview(r) then 0.2 else 0.3, -- room for the DEV Preview button
				index = i,
				bag = renderBag,
				pop = pop,
			})
			footerText(card, "Finish", 1, P.Color.Hint, 20)
			if hasPreview(r) then
				previewButton(card, r)
			end
			Common.Action(card, { kind = "locked", text = NOT_ON_SALE, bag = renderBag })
		end
		if i == 0 then
			Plate.Label(
				row,
				"Nothing to spend Gems on yet",
				{ size = 18, frameSize = UDim2.fromOffset(px(320), px(40)) }
			)
		end
	end
end

local function selectTab(id: string)
	if id == tab then
		return
	end
	tab = id
	if tabs then
		tabs.setActive(id)
	end
	render(true)
end

local function buildTabs()
	local list = {}
	for _, t in TABS do
		table.insert(list, { id = t.id, text = t.text, variant = t.variant })
	end
	tabs = Plate.Tabs(
		window.Content,
		{ tabs = list, active = tab, onSelect = selectTab, bag = window.bag, tabWidth = 104 }
	)
end

function Screen.open(context, category: string?)
	ctx = context
	local gui = MenusV2.Gui()
	if not window then
		window = Plate.Window(gui, {
			key = "PassesGems",
			title = "Passes & Gems",
			icon = Theme.Icons.Gem,
			onClose = function()
				ctx.close()
			end,
		})
	end
	tab = TAB_FOR[category or "Passes"] or "Passes"
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
