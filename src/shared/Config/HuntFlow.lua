--!strict
-- Drive-by hunting loop (owner decision, 10 Nov 2026). Server-decided throughout:
-- shoot to sleep, drive over to load, drive home to bank. Weapon, price,
-- ownership and receipt rules are untouched.
return table.freeze({
	-- Scoop: a sleeping brainrot this close to the owner's driven cart is loaded.
	ScoopEnabled = true,
	ScoopRadius = 13,
	ScoopHz = 10,
	-- Bank: cargo moves onto free platforms while the driven cart is at its base.
	AutoBankEnabled = true,
	BankMargin = 10, -- studs around the base footprint that count as "home"
	BankInterval = 0.3, -- seconds between banked individuals
	FeedbackCooldown = 4,

	-- Spawning for the player: new wild brainrots appear ahead of whichever
	-- hunter has the fewest nearby, instead of only at a burrow mouth.
	PlayerSpawnEnabled = true,
	NearbyRadius = 150,
	NearbyTarget = 6,
	AheadMin = 60,
	AheadMax = 120,
	AheadSpreadDegrees = 55,
	AheadAttempts = 8,
	MovingSpeed = 8,

	-- Fair despawn. A brainrot never leaves next to a player or just after a hit,
	-- and stranded ones (nobody near for a while) are recycled toward hunters.
	DepartBlockRadius = 90,
	DepartBlockAfterHitSeconds = 8,
	StrandedRadius = 230,
	StrandedSeconds = 15,
	StrandedSweepSeconds = 2,
	StrandedPerSweep = 3,
	StarvedBelow = 3,

	-- The 5-minute cycle no longer wipes the world. It starts a rare wave.
	ResetWipesWorld = false,
	RareWaveSeconds = 45,
	RareWaveDraws = 4, -- best tier of this many normal draws
	RareWaveRecycle = 8, -- far Commons recycled at wave start so the wave is visible
})
