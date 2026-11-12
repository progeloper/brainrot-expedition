--!strict
local Strings = {
	CashCard = "Give up all your cash to unlock this upgrade. Keep your brainrots.",
	CollectionCard = "Give up all your owned brainrots to unlock this upgrade. Keep your cash.",
	CashBoundary = "All cash you have when you confirm will be used.",
	PaidWarning = "This includes cash bought with Robux.",
	Preserve = "Keep your regions, cosmetics and permanent upgrades.",
	Saving = "Saving your upgrade…",
	Pending = "Your upgrade is still saving. Please wait.",
	Stale = "Something changed. Check the updated details.",
	Locked = "Expand your base to use this slot.",
	Unavailable = "This offer is unavailable right now.",
	ShopRequired = "Visit the appropriate shop or your base to continue.",
}

Strings.Cancel = "Cancel"
Strings.ConfirmSacrifice = "Confirm sacrifice"
Strings.ConfirmRebirth = "Confirm rebirth"
Strings.ClosePreview = "Close preview"
Strings.Saved = "Saved."
Strings.NeedCash = "You need more Cash."
Strings.PreviewUnavailable = "Preview unavailable."
Strings.Preview = "Preview"
Strings.Equipped = "Equipped"
Strings.EquipWeapon = "Equip weapon"
Strings.BuyWeapon = "Buy weapon"
Strings.InUse = "In use"
Strings.UseDock = "Use at my dock"
Strings.BuyCart = "Buy cart"
Strings.PreviewCart = "Preview cart"
Strings.UpgradesTitle = "Permanent cart upgrades"
Strings.CashRebirth = "Cash rebirth"
Strings.CollectionRebirth = "Brainrot rebirth"
Strings.UseDesign = "Use design"
Strings.OwnedCapacity = "Owned · works at every capacity"
Strings.AppearanceTitle = "Appearance and accessibility"
Strings.AppearanceDetail =
	"Optional finishes apply to items you already own. Changes do not alter their stats. Visit your base to save a selection."
Strings.PurchasedCash = "Purchased cash"
Strings.PreviewStarterCart = "Preview Trailblazer cart"
Strings.PreviewStarterWeapon = "Preview Trailblazer weapon"
Strings.PaidTemporarilyUnavailable = "Purchases are temporarily unavailable while saved-data delivery is recovering."
Strings.PreviewVIPBase = "Preview Riftgold base style"
Strings.PreviewVIPCart = "Preview Riftgold on my cart"
Strings.PreviewVIPWeapon = "Preview Riftgold on my weapon"
Strings.PreviewVIPRift = "Preview the VIP rift"
Strings.VIPIdentityPreview =
	"Optional chat prefix: [VIP] · Overhead VIP badge · Rift Patron title. Toggle each in Settings."
Strings.RiftPreview = "Rebirth rift preview"
Strings.RiftPreviewDetail =
	"The same approved rift appears during the seven-second rebirth. Loading does not change your saved reward."
Strings.RiftLoading = "Loading approved rift preview…"
Strings.PriceUnavailable = "Price unavailable"
Strings.Owned = "Owned"
Strings.Purchase = "Purchase"
Strings.SetupRequired = "Setup required"
Strings.PromptInstruction = "Complete or cancel the Roblox purchase prompt."
Strings.Shop = "Shop"
Strings.Close = "Close"
Strings.NeedCashAmount = "Need %s more Cash."
Strings.FillSlots = "Fill all %s base slots."
Strings.NeedQuality = "Need %s more %s or better brainrots."
Strings.SlotReward = "%s base slots"
Strings.DesignReward = "this base design"
Strings.CashConfirmation = "You will lose an estimated %s Cash and unlock %s."
Strings.CollectionConfirmation =
	"You will lose %s owned brainrots. Your cash, weapons, carts and upgrades stay.\nBase income: %s/s → 0/s."
Strings.StatusLine = "Cash: %s · Gems: %s · %s base slots · %s rebirths"
-- P15 economy copy (short, calm labels; Stud Pop rules: ≤ 8 words of description).
Strings.GemBalance = "%s Gems"
Strings.IncomeLine = "Income ×%s  (rebirths +%s%%%s%s%s)"
Strings.IncomeVip = " · VIP +15%"
Strings.IncomePass = " · 2× pass"
Strings.IncomeBoost = " · 2× boost %s"
Strings.GemShopTitle = "Spend Gems"
Strings.GemPacksTitle = "Get Gems"
Strings.GemPacksDetail = "Gems also come free from discoveries, quests and daily gifts."
Strings.GemPrice = "%s Gems"
Strings.NeedGems = "Need %s more Gems"
Strings.CrateValue = "Gives about %s Cash right now."
Strings.StormActive = "Mutation Storm active: %s left"
Strings.BoostFull = "Boost is already at the 6 hour limit."
Strings.StormFull = "This server's storm is already at 1 hour."
Strings.NotEnoughGems = "You need more Gems."
Strings.RebirthRewards = "You also get +%s Gems and income +%s%% (now +%s%%)."
Strings.PrestigeTitle = "Prestige %s"
Strings.PrestigeDetail = "%s Cash · keeps brainrots and slots · +10%% income forever"
Strings.WeaponStats = "%s · %s damage · %s studs · %s s per shot\n%s"
Strings.CashPrice = "%s Cash"
Strings.CartStats = "%s · speed ×%s · acceleration ×%s · brake ×%s\n%s"
Strings.OwnedDock = "Owned; change at your dock"
Strings.UpgradeStats =
	"Speed level %s / 5 · Cargo %s / 6. Use Upgrade Cart at CARTS. Equipped brainrots are managed with your cart's team prompt."
Strings.ExpansionDetail =
	"%s Cash threshold, or fill all current slots including 4 %s or better individuals. Duplicates count."
Strings.DesignDetail = "%s Cash threshold, or a full base including 4 %s or better individuals. Duplicates count."
Strings.SettingsLabels = {
	RiftVariant = "Rift style",
	VIPBadge = "VIP badge",
	VIPTitle = "VIP title",
	VIPChat = "VIP chat prefix",
	BaseFinish = "Base finish",
	CartFinish = "Cart finish",
	WeaponFinish = "Weapon finish",
	ReducedMotion = "Reduced motion",
}
Strings.Tabs = {
	Passes = "Passes",
	Cash = "Gems",
	Cosmetics = "Cosmetics",
	Weapon = "Weapons",
	Cart = "Carts",
	Base = "Base",
	Settings = "Settings",
}
-- Rebirth UI v2 (RebirthUiV2Enabled): one name everywhere — "Rebirth" (it IS the base-upgrade system).
Strings.YouLoseCash = "YOU LOSE: %s (all your Cash)"
Strings.YouLoseCollection = "YOU LOSE: All %s brainrots + cart team"
Strings.YouGet = "YOU GET: %s · +10%% income forever · +%s Gems"
Strings.PaybackCash = "You'll earn it back in ~%s"
Strings.PaybackCollection = "You give up %s brainrots; your Cash stays."
Strings.RebirthReady = "Rebirth — Ready!"
if require(script.Parent.CampReworkFlags).RebirthUi() then
	Strings.CashCard = "Rebirth with all your Cash to unlock this. Keep your brainrots."
	Strings.CollectionCard = "Rebirth with all your brainrots to unlock this. Keep your Cash."
	Strings.Saving = "Saving your rebirth…"
	Strings.Pending = "Your rebirth is still saving. Please wait."
	Strings.Locked = "Rebirth to unlock this slot."
	Strings.ShopRequired = "Visit the stall or your base entrance to continue."
	Strings.ConfirmSacrifice = "Rebirth"
	Strings.ConfirmRebirth = "Rebirth?"
	Strings.Tabs.Base = "Rebirth"
end
function Strings.Format(key, ...)
	return string.format(Strings[key], ...)
end
return table.freeze(Strings)
