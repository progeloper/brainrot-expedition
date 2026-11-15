--!strict
-- Stud Pop v2 (LOUD) design tokens for Brainrot Expedition.
-- Source of truth: the "Stud Pop" design system (tokens.json). Change values there first, then here.
-- Place at ReplicatedStorage/Shared/UI/Theme (or wherever your Rojo tree keeps client UI modules).

local Theme = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

export type Ramp = { base: Color3, hi: Color3, lo: Color3 }
export type Variant = "go" | "stop" | "info" | "robux" | "gem" | "alert" | "locked" | "burst" | "tab"

Theme.Color = {
	Ink = hex("#1D2133"), -- JointDark: every outline, text stroke, lip
	Ink2 = hex("#2A2F45"), -- empty slots, tracks
	Panel = hex("#32246B"), -- window body (deep violet)
	PanelHi = hex("#4A36A0"),
	Scrim = hex("#0B0D18"), -- use with Theme.ScrimTransparency
	Text = hex("#F7F5FC"),
	TextMuted = hex("#C9C3EA"),
	Cash = hex("#52FF6A"), -- Cash ($): everyday currency, +$X/s, matches creature name tags
	CashLo = hex("#16A83A"),
	Gem = hex("#A64DFF"), -- GEMS: rare currency (jagged rock)
	GemHi = hex("#E3B8FF"),
	GemGlint = hex("#6DF6FF"), -- cyan sparkle on gems only
	Burst = hex("#FFE14A"), -- starbursts, title gradient top
	BurstLo = hex("#FF8A2A"), -- title gradient bottom
	Notify = hex("#FF2D55"), -- red count dot only
	White = Color3.new(1, 1, 1),
}
Theme.ScrimTransparency = 0.45

-- One colour = one meaning. Never pick a variant for looks.
Theme.Variant = {
	go = { base = hex("#3BD16F"), hi = hex("#8DFF3A"), lo = hex("#1E8F45") }, -- BUY / CLAIM / EQUIP / YES
	stop = { base = hex("#F0283C"), hi = hex("#FF6B7A"), lo = hex("#A8122A") }, -- CLOSE / SELL / CANCEL
	info = { base = hex("#46A7FF"), hi = hex("#9AD2FF"), lo = hex("#1E6BFF") }, -- navigate / look
	robux = { base = hex("#FF3D9E"), hi = hex("#FF87C8"), lo = hex("#B0186A") }, -- costs Robux
	gem = { base = hex("#A64DFF"), hi = hex("#E3B8FF"), lo = hex("#5A1FC2") }, -- costs Gems
	alert = { base = hex("#FF8A2A"), hi = hex("#FFD447"), lo = hex("#C2560A") }, -- NEW / limited / boost
	locked = { base = hex("#8A8FA8"), hi = hex("#B9BDD0"), lo = hex("#5D6788") }, -- can't yet (+ reason)
	burst = { base = hex("#FFE14A"), hi = hex("#FFF6B0"), lo = hex("#FF8A2A") }, -- BEST VALUE / x2 starbursts
	tab = { base = hex("#2A2F45"), hi = hex("#3A3F5C"), lo = hex("#1D2133") }, -- inactive tab
	-- Logo plate only (creature palette teal; Trenostruzzo livery). Never a button colour.
	brand = { base = hex("#14C79F"), hi = hex("#7DF7DA"), lo = hex("#0A8C70") },
} :: { [string]: Ramp }
Theme.BrandStripe = hex("#FF3D9E") -- hot-pink stripe across the logo plate

-- Workbook tier palette (keep the key `Celestial`).
Theme.Rarity = {
	Common = hex("#E3EAF3"),
	Uncommon = hex("#72E65B"),
	Rare = hex("#46A7FF"),
	Epic = hex("#B86CFF"),
	Legendary = hex("#FFAE3D"),
	Mythic = hex("#FF4B67"),
	Celestial = hex("#6DEBFF"),
	Secret = hex("#DBD6E7"),
} :: { [string]: Color3 }

-- How loud the reveal / card effects get per tier (RewardReveal + ItemCard).
Theme.RarityIntensity = {
	Common = 1, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 4, Celestial = 5, Secret = 5,
} :: { [string]: number }

-- Mutation tag-label colours (creature standard 6.1).
Theme.Mutation = {
	Shiny = hex("#FF87B7"),
	Golden = hex("#FFD447"),
	Glitched = hex("#FF49E1"),
	Radioactive = hex("#DCFF2B"),
	Astral = hex("#B9A6FF"),
} :: { [string]: Color3 }

-- Core Loop V2 meaning colours (prompt L1; mockups "Core Loop V2 — HUD & FX mockups"). One colour = one
-- meaning: never reuse these for anything else.
Theme.CoreLoop = {
	Lucky = hex("#3BD16F"), -- Lucky Meter fill
	LuckyFull = hex("#FFD447"), -- Lucky Meter full
	RushA = hex("#FF3D9E"), -- RUSH gradient (left)
	RushB = hex("#FF8A2A"), -- RUSH gradient (right)
	MegaA = hex("#FFD447"), -- MEGA RUSH gradient (left)
	MegaB = hex("#A64DFF"), -- MEGA RUSH gradient (right)
	Jackpot = hex("#FFD447"),
	JackpotRays = hex("#FFF6B0"),
	Shimmer = hex("#FFFFFF"),
	ShimmerB = hex("#CFF7FF"),
	Guarded = hex("#FF8A2A"),
	Saved = hex("#46A7FF"),
	Leaving = hex("#FF8A2A"),
	NotYours = hex("#8A8FA8"),
	RainCloud = hex("#2A2F45"), -- L3.12 Mutation Rain cloud (CL_Dust tint)
	Alert = hex("#F0283C"), -- "!" brainrot spotted you
	Suspicious = hex("#FFE14A"), -- villager "?"
	-- Beam cores per tier (rarity ladder glow column).
	Glow = {
		Common = hex("#FFFFFF"),
		Uncommon = hex("#D1FFB4"),
		Rare = hex("#9AD2FF"),
		Epic = hex("#E3B8FF"),
		Legendary = hex("#FFE14A"),
		Mythic = hex("#FF9AAE"),
		Celestial = hex("#DFFBFF"),
		Secret = hex("#DBD6E7"),
	} :: { [string]: Color3 },
}

Theme.Font = {
	Display = Font.fromEnum(Enum.Font.LuckiestGuy), -- titles, ribbons, buttons, amounts, shouts
	Body = Font.fromEnum(Enum.Font.FredokaOne), -- names, descriptions, small labels (readable at 14 px)
}

-- Pixel sizes at the 844x390 phone baseline (visual audit viewport). Use Theme.px() to scale.
Theme.Size = {
	MinText = 14, -- audit rule A5: nothing smaller ships
	Stroke = 4, -- UIStroke on surfaces (v2: louder)
	TextStroke = 3, -- UIStroke on text
	Lip = 7, -- 3D lip depth
	Rim = 2, -- white inner rim
	TouchMin = 48,
}

Theme.Radius = {
	Sm = UDim.new(0, 8),
	Md = UDim.new(0, 14),
	Lg = UDim.new(0, 22),
	Pill = UDim.new(0.5, 0),
}

-- Reuse the creature stud texture (creature standard: never upload a new stud image).
-- Leave "" to skip studs on UI.
Theme.StudTexture = "rbxassetid://126387978066468" -- creature stud ColorMap (Bingus_Saved_Studs_13719188279), VoxelCreaturePalette
Theme.StudTilePx = 12
Theme.StudTransparency = 0.82

-- Icon asset ids: upload IconPack/*.png (512², glow baked in) and paste the ids:
-- cash.png -> Cash, gem.png -> Gem, robux.png -> Robux, bag.png -> Shop, book.png -> Index, gift.png -> Gift,
-- star.png -> Rebirth, gear.png -> Settings, lock.png -> Lock, plus.png -> Plus, x.png -> Close, check.png -> Check,
-- bolt.png -> Bolt, cart.png -> Cart. For Robux PRICES in text, prefer Roblox's own Robux glyph so players trust it.
Theme.Icons = {
	-- Uploaded 10 Nov 2026 from design_reference/stud_pop/IconPack (Studio MCP upload_image).
	Cash = "rbxassetid://94414421522040",
	Gem = "rbxassetid://116596597296975",
	Robux = "rbxassetid://128854171889035",
	Shop = "rbxassetid://121967289429940",
	Index = "rbxassetid://131845096092841",
	Gift = "rbxassetid://129108485557720",
	Rebirth = "rbxassetid://83196540152233",
	Settings = "rbxassetid://88727437250436",
	Lock = "rbxassetid://70711614023180",
	Plus = "rbxassetid://105558447660425",
	Close = "rbxassetid://80542701567036",
	Check = "rbxassetid://110716604709658",
	Bolt = "rbxassetid://71207611603816",
	Cart = "rbxassetid://124056941444832",
	-- Favourite lock (12 Nov 2026): assets/ui/icons/star_on.png, star_off.png (sources in docs/menus_v2/mockups).
	Star = "rbxassetid://111130986823181",
	StarOff = "rbxassetid://117290454515652",
} :: { [string]: string }

-- Optional images (white on transparent). Effects that need one are skipped while it is "".
Theme.Images = {
	Rays = "rbxassetid://102197915183943", -- sunburst behind titles and reveals
	Sparkle = "rbxassetid://77872093169360", -- 4-point star; falls back to a rotated neon square
	Glow = "rbxassetid://89468577258603", -- soft radial glow behind primary button / gem offers
} :: { [string]: string }

-- Gem ladder (Robux -> Gems). Bonus is the real extra vs the smallest pack.
Theme.GemPacks = {
	{ robux = 49, gems = 40, bonus = 0 },
	{ robux = 149, gems = 130, bonus = 7 },
	{ robux = 399, gems = 385, bonus = 18, tag = "POPULAR" },
	{ robux = 799, gems = 830, bonus = 27 },
	{ robux = 1699, gems = 1970, bonus = 42, tag = "BEST VALUE" },
} :: { { robux: number, gems: number, bonus: number, tag: string? } }

Theme.Sounds = {
	Click = "", -- short pop; played with pitch 0.95–1.05
	Purchase = "", -- cha-ching
	RewardSmall = "",
	RewardBig = "", -- Legendary+ fanfare
	Error = "", -- locked button bonk
	GemTing = "", -- crystal ting, one per gem rock landing
} :: { [string]: string }

-- Motion vocabulary (tuned Nov 2026 for an 8-year-old audience): instant tap response (<100 ms),
-- squash on press then an overshoot-and-settle on release, icons that bounce/twirl when tapped,
-- windows that pop in with a small overshoot (~0.28 s) and leave faster (~0.16 s, accelerating).
-- Everything degrades to fades when the player's ReducedMotion attribute is on.
Theme.Motion = {
	PressDown = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	PressScale = 0.9, -- squash target on press
	Release = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- overshoots, settles
	Hover = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	HoverScale = 1.05,
	IconPop = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	IconSettle = TweenInfo.new(0.38, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	IconTwirl = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	WindowIn = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	WindowOut = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	ScrimIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	StaggerStep = 0.035, -- delay between buttons popping in after their window
	StaggerMax = 10,
	Breathe = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), -- primary button only
	PopOut = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	PopBack = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fill = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CountUpSeconds = 0.6,
	ShineEvery = 2.6,
	FloatPeriod = 1.6,
}

local BASE_HEIGHT = 390

-- Scale a baseline pixel value (stroke, lip, text floor) to the current viewport.
-- Growth stops at MaxScale so tablet/desktop chrome stays compact (2.5x made the HUD overlap the
-- world UI at 1080p). An unsized viewport (client start) uses the baseline instead of shrinking.
Theme.MaxScale = 1.35
function Theme.px(n: number): number
	local cam = workspace.CurrentCamera
	local h = if cam then cam.ViewportSize.Y else BASE_HEIGHT
	if h < 200 then
		h = BASE_HEIGHT
	end
	return math.max(1, math.floor(n * math.clamp(h / BASE_HEIGHT, 1, Theme.MaxScale) + 0.5))
end

-- 12431902 -> "12.4M". Numbers on screen are always short.
function Theme.abbreviate(n: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local i = 1
	local v = math.abs(n)
	while v >= 1000 and i < #suffixes do
		v /= 1000
		i += 1
	end
	local sign = if n < 0 then "-" else ""
	if i == 1 then
		return sign .. tostring(math.floor(v))
	end
	local s = if v < 10 then string.format("%.2f", v) elseif v < 100 then string.format("%.1f", v) else string.format("%d", math.floor(v))
	if s:find("%.") then
		s = (s:gsub("0+$", ""))
		s = (s:gsub("%.$", ""))
	end
	return sign .. s .. suffixes[i]
end

function Theme.ramp(variant: string): Ramp
	return Theme.Variant[variant] or Theme.Variant.info
end

------------------------------------------------------------------ Stud Pop Plate (owner-approved 12 Nov 2026)
-- Menu look for MenusV2 (stall shops, HUD Brainrots/Inventory windows, dialogs). Values come from
-- design_reference/menus_v2/Menu_Concepts/tokens_plate.json at the 844x390 baseline (mockup px / 1.5).
-- Plate builders live in Plate.lua; v2 rounded-gloss builders in StudPop.lua stay for older screens.
local function grad(...): { Color3 }
	local out = {}
	for _, h in { ... } do
		table.insert(out, hex(h))
	end
	return out
end

Theme.Plate = {
	Radius = { Window = 5, Button = 4, Card = 4, Tab = 4, Pill = 3 },
	Stroke = { Outline = 3, TitleText = 5, LabelText = 2.5 },
	FrameLayers = 3, -- ink 3 -> grey 3 -> ink 3
	BottomLip = 8,
	ButtonLip = 3,
	Color = {
		Ink = hex("#1D2133"),
		WindowBody = hex("#2B2D38"),
		FrameGrey = hex("#565868"),
		Well = hex("#2A2F45"),
		WellRim = hex("#8DFF3A"),
		Cash = hex("#52FF6A"),
		RollerLine = hex("#FF6B7A"),
		Hint = hex("#C9C3EA"),
		White = Color3.new(1, 1, 1),
	},
	StatPill = grad("#FFE14A", "#FFB02A"),
	LevelGradient = grad("#9FFBFF", "#3FD2FF", "#3BD16F"),
	Header = {
		Weapons = grad("#9B2CF0", "#C04DFF", "#D98BFF"),
		Carts = grad("#FF6A00", "#FF9A1F", "#FFC94A"),
		Sell = grad("#3CCF1A", "#7DFF3A", "#B4FF6A"),
		Training = grad("#14A8E0", "#3FD2FF", "#9AF2FF"),
		Brainrots = grad("#FF3D9E", "#FF7AD0", "#FFB0E4"),
		Inventory = grad("#2F7BFF", "#46A7FF", "#9AD2FF"),
		PassesGems = grad("#A64DFF", "#C98BFF", "#E3B8FF"),
		Rebirth = grad("#FFB000", "#FFD447", "#FFF0A0"),
		Dialog = grad("#3FD2FF", "#9AF2FF"),
	},
	-- one colour, one meaning (top -> middle -> bottom)
	Button = {
		go = grad("#8DFF3A", "#4CD820", "#2FA514"),
		gem = grad("#D49BFF", "#A64DFF", "#7A2FD6"),
		robux = grad("#FF7AD0", "#E632C8", "#B0189A"),
		stop = grad("#FF4A4A", "#E01E1E", "#A80F0F"),
		info = grad("#7CC8FF", "#3A9DFF", "#1E6BFF"),
		alert = grad("#FFD447", "#FF9A1F", "#E06A0A"),
		locked = grad("#6A6D7C", "#4A4C5A", "#383A46"),
		tabOff = grad("#5D606F", "#3F414E", "#2F313C"),
	},
	Glow = { go = hex("#8DFF3A"), stop = hex("#FF4A4A"), gem = hex("#A64DFF"), robux = hex("#FF7AD0") },
	-- item card backgrounds; carts T0/T1/T2/T3 reuse T1/T2/T4/T8
	Tier = {
		T1 = grad("#F2F5FA", "#AEB9CB"),
		T2 = grad("#A6F58F", "#3FAE37"),
		T3 = grad("#8FD0FF", "#1E6BFF"),
		T4 = grad("#D6A6FF", "#7A2FD6"),
		T5 = grad("#FF8193", "#B3122E"),
		T6 = grad("#D4FBFF", "#3FBCD8"),
		T7 = grad("#DBD6E7", "#6B5F87", "#1A1428"), -- radial in the mockup
		T8 = grad("#FF4B67", "#FFAE3D", "#DCFF2B", "#3BD16F", "#46A7FF", "#A64DFF", "#FF49E1"),
		Robux = grad("#FF7AD0", "#B0189A"),
		Gem = grad("#D49BFF", "#7A2FD6"),
		WonBronze = grad("#F2B27A", "#9A5A24"),
		WonSilver = grad("#EEF3FA", "#8A96AB"),
		WonGold = grad("#FFF0A0", "#D89A12"),
		Cargo = grad("#E8B27A", "#B37A42"),
		Dark = grad("#3A3D4C", "#2B2D38"),
	},
	CardFrame = hex("#565868"),
	Font = {
		Title = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy),
		Label = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
		Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	},
	-- Tiles are NOT the creature stud texture: square raised studs for window bodies, soft L-bevel for
	-- coloured surfaces. Ids from assets/ui/stall_menus (see assets/ui/UPLOADED_ASSETS.md).
	Tiles = {
		Body = "rbxassetid://71265897917776", -- stud_tile_body.png, tiled at 19 px
		Surface = "rbxassetid://71570062644940", -- stud_tile_surface.png, tiled at 15 px
		BodyTile = 19,
		SurfaceTile = 15,
		Stripes = "rbxassetid://107337993689601", -- diagonal white stripes (XP bars)
	},
	-- Window / card / badge motion (tokens_plate.json "motion")
	Motion = {
		WindowOpen = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		WindowClose = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		TitleDrop = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.12),
		TitleDropPx = 36 / 1.5,
		TitleIdle = 2.2,
		HeaderIconHop = 1.6,
		HeaderShine = 3.4,
		StatPillShine = 2.8,
		BodySunburst = 70,
		BodySweep = 4.6,
		BodyParticles = 12,
		CardStagger = 0.07,
		CardPop = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		CardRisePx = 18 / 1.5,
		CardGlint = 3.8,
		ItemBob = 2.6,
		ItemBobPx = 7 / 1.5,
		Rays = 14,
		ButtonShine = 3,
		PrimaryBreathe = 1.4,
		InUsePulse = 1.3,
		Sticker = 1.8,
	},
}

return Theme
