--!strict
-- AudioController: every Brainrot Expedition sound (see the audio list doc + soundboard).
-- Client-only presentation. It listens to the same events the visual controllers use, so no
-- gameplay script depends on it, and it changes no gameplay state.
--
-- Buses (SoundGroups): Music 0.3, Ambience 0.18, SFX 0.6, UI 0.45, Rewards 0.95.
-- Music: one 128 BPM theme. Hub (M1) in camp; exploration (M2) + region layer in regions;
-- tension layer (M3) while a villager is suspicious of you; chase layer (M4) during a chase.
-- Every jingle ducks the music by half and releases over 1.5 s.
--
-- Trend test layer (v3): players whose "AudioVariant" attribute is "Trend" (set by the server,
-- see AudioVariantService) get a phonk join intro, the phonk chase layer, a 0.5 s freeze + BOOM
-- before Legendary+ reveals, and brainrots that chant their own names. "Current" players hear v2.
-- Everyone gets a bigger first catch of the session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Config.AudioCatalog)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local player = Players.LocalPlayer
local Controller = {}

local started = false
local groups: { [string]: SoundGroup } = {}
local oneShotFolder: Folder
local loops: { [string]: Sound } = {}
local loopTarget: { [string]: number } = {}
local loopRate: { [string]: number } = {}
local active: { [string]: number } = {}
local lastPlayed: { [string]: number } = {}

local duckLevel = 1
local duckHoldUntil = 0
local duckDepth = 1
local silenceUntil = 0

local state = {
	region = nil :: string?,
	inCamp = true,
	chase = false,
	tension = false,
	chaseCenter = nil :: Vector3?,
	chaseRadius = 0,
	ringNearPlayed = false,
	hitCombo = 0,
	lastHitAt = 0,
	lastHitItem = nil :: string?,
	bankStreak = 0,
	lastBankAt = 0,
	entryCounts = {} :: { [string]: number },
	toyIndex = 0,
	toyLastAt = 0,
	toyRun = {} :: { number },
	firstCatchDone = false,
	introPlayed = false,
	introUntil = 0,
}

local speciesNearAt: { [string]: number } = {}
local lastNearAt = 0

local function trend(): boolean
	return player:GetAttribute("AudioVariant") == "Trend"
end

local function chaseKey(): string
	return if trend() and (Catalog.Loops :: any).M4_PHONK ~= "" then "M4_PHONK" else "M4"
end

-- ---------------------------------------------------------------- helpers

local function now(): number
	return os.clock()
end

local function rank(tier: any): number
	return (Rarities.GetDisplayRank and Rarities.GetDisplayRank(tier)) or 0
end

local function atLeast(tier: any, floor: string): boolean
	return rank(tier) >= (rank(floor) or math.huge)
end

local function regionKey(regionId: any): string?
	if type(regionId) ~= "string" then
		return nil
	end
	return (Catalog.RegionKeys :: any)[regionId]
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setting(name: string): number
	local v = player:GetAttribute(name)
	if type(v) == "number" then
		return math.clamp(v, 0, 1)
	end
	return 1
end

local function makeGroup(name: string, volume: number): SoundGroup
	local existing = SoundService:FindFirstChild("BE_" .. name)
	local g = if existing and existing:IsA("SoundGroup") then existing else Instance.new("SoundGroup")
	g.Name = "BE_" .. name
	g.Volume = volume
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function duck(seconds: number, depth: number?)
	duckHoldUntil = math.max(duckHoldUntil, now() + seconds)
	duckDepth = math.min(duckDepth, depth or 0.5)
end

-- ---------------------------------------------------------------- one-shots

export type PlayOptions = {
	bus: string?,
	volume: number?,
	pitch: number?,
	position: Vector3?,
	parent: Instance?,
	range: number?,
	cap: string?,
	capCount: number?,
	cooldown: number?,
	duck: boolean?,
}

function Controller.Play(id: string, options: PlayOptions?): Sound?
	if not started then
		return nil
	end
	local o: PlayOptions = options or {}
	local entry = (Catalog.Entries :: any)[id]
	if not entry then
		return nil
	end
	local asset = (Catalog.Packs :: any)[entry.pack]
	if type(asset) ~= "string" or asset == "" then
		return nil
	end
	local t = now()
	if o.cooldown and lastPlayed[id] and t - lastPlayed[id] < o.cooldown then
		return nil
	end
	local cap = o.cap
	if cap and (active[cap] or 0) >= (o.capCount or 3) then
		return nil
	end
	lastPlayed[id] = t
	local pitch = o.pitch or 1
	local s = Instance.new("Sound")
	s.Name = id
	s.SoundId = asset
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(entry.start, entry.start + entry.length)
	s.Volume = o.volume or 1
	s.PlaybackSpeed = pitch
	s.SoundGroup = groups[o.bus or "SFX"]
	local holder: Instance? = nil
	if o.position then
		local a = Instance.new("Attachment")
		a.Name = "BE_Audio"
		-- RegionVisibilityController mutes workspace Sounds it places in another region, and a holder
		-- under Terrain resolves to the map origin. Mark it global; distance roll-off does the rest.
		a:SetAttribute("GlobalNavigationFacade", true)
		a.WorldPosition = o.position
		a.Parent = Workspace.Terrain
		holder = a
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 12
		s.RollOffMaxDistance = o.range or 140
		s.Parent = a
	elseif o.parent then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = o.range or 120
		s.Parent = o.parent
	else
		s.Parent = oneShotFolder
	end
	local life = entry.length / pitch + 0.5
	if cap then
		active[cap] = (active[cap] or 0) + 1
		task.delay(entry.length / pitch, function()
			active[cap] = math.max(0, (active[cap] or 1) - 1)
		end)
	end
	if o.duck or (o.bus == "Rewards") then
		duck(entry.length * 0.8 / pitch)
	end
	s:Play()
	Debris:AddItem(holder or s, life)
	return s
end

local function pick(prefix: string, count: number): string
	return prefix .. tostring(math.random(1, count))
end

-- ---------------------------------------------------------------- loops (music / ambience / engine)

local function loop(key: string, bus: string, parent: Instance?): Sound?
	if loops[key] then
		return loops[key]
	end
	local asset = (Catalog.Loops :: any)[key]
	if type(asset) ~= "string" or asset == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "BE_" .. key
	s.SoundId = asset
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = groups[bus]
	s.Parent = parent or oneShotFolder
	loops[key] = s
	loopTarget[key] = 0
	loopRate[key] = 1
	return s
end

-- target volume (0-1.2) and fade time in seconds to get there
local function fadeTo(key: string, target: number, seconds: number)
	loopTarget[key] = target
	loopRate[key] = 1 / math.max(seconds, 0.05)
end

local MUSIC_LAYERS = { "M2", "M3", "M4", "M4_PHONK", "R1_music", "R2_music", "R3_music", "R4_music", "R5_music", "R6_music", "R7_music" }

local function startMusic()
	loop("M1", "Music")
	for _, key in MUSIC_LAYERS do
		loop(key, "Music")
	end
	-- M2 (exploration) always runs and is the beat clock. The other layers only play while audible
	-- and are started at M2's position (see stepLoops), which keeps the sound count low on phones.
	if loops.M2 then
		loops.M2:Play()
	end
	if loops.M1 then
		loops.M1:Play()
	end
	for i = 1, 7 do
		loop("A" .. i, "Ambience")
	end
end

local function applyMusicState()
	local key = state.region
	if state.inCamp or not key then
		fadeTo("M1", if now() < state.introUntil then 0 else 1, if now() < state.introUntil then 0.1 else 2)
		fadeTo("M2", 0, 2)
		for i = 1, 7 do
			fadeTo("R" .. i .. "_music", 0, 2)
			fadeTo("A" .. i, 0, 3)
		end
		fadeTo("M3", 0, 1)
		fadeTo("M4", 0, if state.chase then 0.3 else 2.5)
		fadeTo("M4_PHONK", 0, if state.chase then 0.3 else 2.5)
		return
	end
	fadeTo("M1", 0, 2)
	fadeTo("M2", 1, 2)
	for i = 1, 7 do
		local k = "R" .. i
		fadeTo(k .. "_music", if k == key then 0.75 else 0, 3)
		fadeTo("A" .. i, if k == key then (if state.chase then 0.5 else 1) else 0, 3)
	end
	if state.chase then
		local ck = chaseKey()
		fadeTo(ck, 1.15, 0.3)
		fadeTo(if ck == "M4" then "M4_PHONK" else "M4", 0, 0.3)
		fadeTo("M3", 0, 0.3)
	else
		fadeTo("M4", 0, 2.5)
		fadeTo("M4_PHONK", 0, 2.5)
		fadeTo("M3", if state.tension then 0.65 else 0, 1)
	end
end

local function stepLoops(dt: number)
	-- ducking envelope: hold, then release over 1.5 s
	local t = now()
	local target = if t < duckHoldUntil then duckDepth else 1
	if t >= duckHoldUntil then
		duckDepth = 1
	end
	if t < silenceUntil then
		target = 0
	end
	if target < duckLevel then
		duckLevel = math.max(target, duckLevel - dt / 0.12)
	else
		duckLevel = math.min(target, duckLevel + dt / 1.5)
	end
	local buses = Catalog.Buses :: any
	groups.Music.Volume = buses.Music * setting("MusicVolume") * duckLevel
	groups.Ambience.Volume = buses.Ambience * setting("MusicVolume")
	groups.SFX.Volume = buses.SFX * setting("SfxVolume")
	groups.UI.Volume = buses.UI * setting("SfxVolume")
	groups.Rewards.Volume = buses.Rewards * setting("SfxVolume")
	for key, s in loops do
		local goal = loopTarget[key] or 0
		local v = s.Volume
		if v ~= goal then
			local step = (loopRate[key] or 1) * dt * math.max(goal, 1)
			v = if v < goal then math.min(goal, v + step) else math.max(goal, v - step)
			s.Volume = v
		end
		-- ambience only plays while audible (saves memory on low-end phones)
		if key:sub(1, 1) == "A" then
			if v > 0.001 and not s.IsPlaying then
				s:Play()
			elseif v <= 0.001 and s.IsPlaying then
				s:Stop()
			end
		elseif key == "M1" then
			-- hub track: pause while silent so it picks up where it left off
			if goal > 0 and not s.IsPlaying then
				s:Resume()
			elseif goal <= 0 and v <= 0.001 and s.IsPlaying then
				s:Pause()
			end
		elseif key ~= "M2" then
			-- tension / chase / region layers: start on M2's beat, stop once faded out
			if goal > 0 and not s.IsPlaying then
				local clock = loops.M2
				local length = s.TimeLength
				if clock and length > 0 then
					s.TimePosition = clock.TimePosition % length
				end
				s:Play()
			elseif goal <= 0 and v <= 0.001 and s.IsPlaying then
				s:Stop()
			end
		end
	end
end

-- ---------------------------------------------------------------- regions

local function onRegionChanged()
	local regionId = player:GetAttribute("Phase13RegionId")
	local inCamp = player:GetAttribute("Phase10InCamp") == true or regionId == "REGION_CAMP"
	local key = regionKey(regionId)
	local previous = state.region
	state.inCamp = inCamp
	state.region = key
	if key and key ~= previous and not inCamp then
		local count = (state.entryCounts[key] or 0) + 1
		state.entryCounts[key] = count
		-- full fanfare for the first three entries a session, then a quieter version
		Controller.Play(key .. "_entry", { bus = "Rewards", volume = if count <= 3 then 1 else 0.45 })
	end
	applyMusicState()
end

-- ---------------------------------------------------------------- catching

local SIZES = { "s", "m", "l" }
local HIT_KINDS = { BrainrotDamageHit = true, BrainrotHit = true, DecoyHit = true }

local function onSleepResult(_origin: any, _endpoint: any, result: any)
	if type(result) ~= "table" or result.PlayerId ~= player.UserId then
		return
	end
	if not HIT_KINDS[result.ImpactKind] and result.Slept ~= true then
		return
	end
	local t = now()
	local item = if type(result.ItemId) == "string" then result.ItemId else nil
	if item and item == state.lastHitItem and t - state.lastHitAt < 3 then
		state.hitCombo = math.min(state.hitCombo + 1, 8)
	else
		state.hitCombo = 1
	end
	state.lastHitItem = item
	state.lastHitAt = t
	-- each hit in a row steps up the scale, so a combo builds toward the catch
	Controller.Play("S1_" .. state.hitCombo, { volume = 0.9 })
	if trend() and item then
		local species = Controller.SpeciesOf(item)
		if species then
			Controller.Play("V_" .. species .. "_hit", { volume = 0.8, cooldown = 0.12 })
		end
	end
	if result.ImpactKind ~= "DecoyHit" then
		Controller.Play("S2_" .. SIZES[math.random(1, 3)], { volume = 0.55, cap = "squeak", capCount = 2 })
	end
	if result.Slept == true then
		state.hitCombo = 0
		Controller.Play(pick("S3_", 2), { volume = 0.8 })
	end
end

-- Called by CatchRevealController when the reveal card shows (tier + mutation known there).
function Controller.CatchReveal(tier: string?, mutationId: string?, speciesId: string?)
	if not started then
		return
	end
	local level = if atLeast(tier, "Celestial") then 4 elseif atLeast(tier, "Legendary") then 3 elseif atLeast(tier, "Rare") then 2 else 1
	-- first catch of the session plays one tier bigger (everyone, both variants)
	if not state.firstCatchDone then
		state.firstCatchDone = true
		if level < 3 then
			level += 1
		end
	end
	local jingle = ({ "J1", "J2", "J3", "J4" })[level]
	local delay = 0
	if trend() and level >= 3 then
		-- half-second freeze + BOOM before the reveal (vine-boom moment players clip)
		local celestial = atLeast(tier, "Celestial")
		silenceUntil = now() + (if celestial then 1.1 else 0.6)
		Controller.Play(if celestial then "BOOM_X" else "BOOM_L", { bus = "Rewards" })
		delay = if celestial then 1.1 else 0.6
	elseif level == 4 then
		silenceUntil = now() + 0.3
	end
	task.delay(delay, function()
		Controller.Play(jingle, { bus = "Rewards" })
		if state.region and not state.inCamp then
			Controller.Play(state.region .. "_catch", { bus = "Rewards", volume = 0.7 })
		end
	end)
	if trend() and type(speciesId) == "string" then
		task.delay(delay + 1.1, function()
			Controller.Play("V_" .. speciesId .. "_catch", { bus = "Rewards", volume = 0.9 })
		end)
	end
	local m = if type(mutationId) == "string" then mutationId else "None"
	local layer = ({ Shiny = "J5a", Golden = "J5b", Glitched = "J5c", Radioactive = "J5d", Astral = "J5e" } :: any)[m]
	if layer then
		task.delay(delay + (if jingle == "J4" then 0.5 else 0.15), function()
			Controller.Play(layer, { bus = "Rewards", volume = 0.75 })
		end)
	end
end

-- Species lookup for hit yelps. CatchRevealController exposes SpeciesOf(itemId) (see the prompt).
function Controller.SpeciesOf(itemId: string): string?
	local ok, Reveal = pcall(require, script.Parent:FindFirstChild("CatchRevealController") :: any)
	if ok and type(Reveal) == "table" and Reveal.SpeciesOf then
		local okS, species = pcall(Reveal.SpeciesOf, itemId)
		if okS and type(species) == "string" then
			return species
		end
	end
	return nil
end

-- Called by the creature presentation when a wild brainrot is within ~30 studs of the player.
-- Rate limited: one chant per species per 20 s, one chant overall per 6 s, nothing while chasing.
function Controller.NearBrainrot(speciesId: string, position: Vector3)
	if not started or not trend() or state.chase then
		return
	end
	local t = now()
	if t - lastNearAt < 6 or (speciesNearAt[speciesId] and t - speciesNearAt[speciesId] < 20) then
		return
	end
	lastNearAt = t
	speciesNearAt[speciesId] = t
	Controller.Play("V_" .. speciesId .. "_near", { position = position, range = 70, volume = 0.75, cap = "voice", capCount = 3 })
end

-- Called by CatchRevealController for a first discovery ("NEW!").
function Controller.NewSpecies()
	Controller.Play("J6", { bus = "Rewards" })
end

-- ---------------------------------------------------------------- Phase12 events (load, bank, escape, theft)

local function onPhase12(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local mine = payload.userId == player.UserId
	if kind == "Load" and mine then
		Controller.Play(pick("S6_", 2), { volume = 0.9 })
	elseif kind == "Escape" and mine then
		Controller.Play("S4", { volume = 0.8 })
	elseif kind == "Bank" and mine and payload.batchReady == true then
		local records = if type(payload.records) == "table" then payload.records else { payload }
		local best, bestMutation = nil, nil
		for _, r in records do
			if type(r) == "table" then
				if best == nil or rank(r.rarity) > rank(best) then
					best = r.rarity
				end
				if r.mutationId and r.mutationId ~= "None" then
					bestMutation = r.mutationId
				end
			end
		end
		local t = now()
		if t - state.lastBankAt > 20 then
			state.bankStreak = 0
		end
		state.lastBankAt = t
		state.bankStreak += #records
		Controller.Play("S16", { volume = 0.9 })
		task.delay(0.3, function()
			local big = atLeast(best, "Legendary") or bestMutation ~= nil
			Controller.Play(if big then "J13" else "J12", { bus = "Rewards" })
			local layer = ({ Shiny = "J5a", Golden = "J5b", Glitched = "J5c", Radioactive = "J5d", Astral = "J5e" } :: any)[bestMutation or ""]
			if layer then
				Controller.Play(layer, { bus = "Rewards", volume = 0.7 })
			end
		end)
		if type(payload.cashPerSecond) == "number" and payload.cashPerSecond > 0 then
			task.delay(1.4, function()
				Controller.Play("J14", { bus = "Rewards", volume = 0.8 })
			end)
		end
		if state.bankStreak >= 2 then
			task.delay(2.6, function()
				Controller.Play("J15", { bus = "Rewards", volume = 0.85 })
			end)
		end
	elseif type(kind) == "string" and (kind:find("Theft") or kind:find("Steal")) then
		if payload.victimUserId == player.UserId or payload.ownerUserId == player.UserId then
			Controller.Play("S17", { volume = 0.8, cooldown = 2 })
		elseif mine then
			Controller.Play("S18", { volume = 0.9 })
		end
	end
end

-- ---------------------------------------------------------------- villagers + chase

local villagerConnections: { [Instance]: RBXScriptConnection } = {}

local function villagerRegionKey(root: Instance): string
	return regionKey(root:GetAttribute("RegionId")) or "R1"
end

local function villagerPosition(root: Instance): Vector3?
	if root:IsA("Model") then
		return root:GetPivot().Position
	elseif root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function refreshTension()
	local folder = Workspace:FindFirstChild("Villagers")
	local any = false
	if folder then
		for _, v in folder:GetChildren() do
			if v:GetAttribute("State") == "Suspicious" and v:GetAttribute("TargetUserId") == player.UserId then
				any = true
				break
			end
		end
	end
	if any ~= state.tension then
		state.tension = any
		applyMusicState()
	end
end

local function onVillagerState(root: Instance)
	local s = root:GetAttribute("State")
	local target = root:GetAttribute("TargetUserId")
	local pos = villagerPosition(root)
	local key = villagerRegionKey(root)
	local me = target == player.UserId
	if s == "Suspicious" and me then
		Controller.Play("J7", { bus = "Rewards", volume = 0.8, cooldown = 1.5 })
		if pos then
			Controller.Play(key .. "_voice_ask", { position = pos, range = 120, cap = "voice", capCount = 3 })
		end
	elseif s == "WindUp" and me and pos then
		Controller.Play(key .. "_voice_shout", { position = pos, range = 150, cap = "voice", capCount = 3 })
	elseif s == "GiveUp" and pos then
		local root_ = rootPart()
		if root_ and (root_.Position - pos).Magnitude < 90 then
			Controller.Play(key .. "_voice_grumble", { position = pos, range = 110, cap = "voice", capCount = 3 })
			Controller.Play(pick("S13_", 2), { position = pos, range = 90, volume = 0.6, cap = "tantrum", capCount = 2 })
		end
	end
	refreshTension()
end

local function watchVillager(root: Instance)
	if villagerConnections[root] or root:GetAttribute("VillagerId") == nil then
		return
	end
	villagerConnections[root] = root:GetAttributeChangedSignal("State"):Connect(function()
		onVillagerState(root)
	end)
end

local function onGuardEvent(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind == "ChaseStarted" or kind == "ChaseRecentred" then
		if kind == "ChaseStarted" then
			Controller.Play("J8", { bus = "Rewards" })
			task.delay(0.3, function()
				Controller.Play("S14", { volume = 0.8 })
			end)
			state.ringNearPlayed = false
		end
		state.chase = true
		state.chaseCenter = if typeof(payload.center) == "Vector3" then payload.center else nil
		state.chaseRadius = if type(payload.radius) == "number" then payload.radius else 0
		applyMusicState()
	elseif kind == "ChaseTag" then
		Controller.Play(pick("S12_", 2), { volume = 0.9 })
	elseif kind == "ChaseEnded" then
		state.chase = false
		state.chaseCenter = nil
		applyMusicState()
		Controller.Play("J9", { bus = "Rewards" })
		if payload.clean then
			task.delay(0.9, function()
				Controller.Play("J10", { bus = "Rewards", volume = 0.85 })
			end)
		end
	elseif kind == "Sneaky" then
		Controller.Play("J11", { bus = "Rewards", volume = 0.85 })
	end
end

local function landmarkPosition(key: string): Vector3?
	local world = Workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild((Catalog.RegionFolders :: any)[key] or "")
	if not folder then
		return nil
	end
	for _, d in folder:GetChildren() do
		if d.Name:find("^Landmark_") and d:IsA("Model") then
			return d:GetPivot().Position
		end
	end
	return nil
end

local function playLandmark(key: string, volume: number?)
	local pos = landmarkPosition(key)
	if pos then
		Controller.Play(key .. "_landmark", { position = pos, range = 1400, volume = volume or 1, cooldown = 8 })
	end
end

local function onAudioCue(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "BigChase" then
		local key = regionKey(payload.regionId)
		if key and key == state.region and (key == "R1" or key == "R4") then
			playLandmark(key)
		end
	end
end

local function onAnnouncement(message: any)
	if type(message) == "table" and message.kind == "MutationStorm" then
		Controller.Play("J21", { bus = "Rewards" })
	end
end

-- ---------------------------------------------------------------- world progression, storm, upgrades

local function onProgression(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "Open" then
		Controller.Play("U2", { bus = "UI" })
	elseif message.kind == "Result" and type(message.result) == "table" then
		local code = message.result.code
		if code == "Success" then
			Controller.Play("J16", { bus = "Rewards" })
			Controller.Play("ST3", { volume = 0.8 })
		elseif type(code) == "string" and (code:find("Insufficient") or code:find("NotEnough") or code:find("Afford")) then
			Controller.Play("U6", { bus = "UI" })
		end
	end
end

local function onStormPush(_message: any)
	Controller.Play("ST2", { volume = 0.9, cooldown = 0.5 })
end

local upgradeSeen: { [string]: boolean } = {}
local function onUpgradeUpdate(value: any)
	if type(value) == "table" and value.kind == "PurchasePersistence" and type(value.offerId) == "string" then
		if not upgradeSeen[value.offerId] then
			upgradeSeen[value.offerId] = true
			Controller.Play("U5", { bus = "UI" })
			Controller.Play("J17", { bus = "Rewards" })
		end
	end
end

-- ---------------------------------------------------------------- player attributes (gems, boosts, rebirth)

local lastGems: number? = nil
local lastRebirth: number? = nil
local lastBoost: number = 0
local boostWarned = false

local function watchPlayerAttributes()
	lastGems = player:GetAttribute("Gems") :: any
	lastRebirth = player:GetAttribute("RebirthCount") :: any
	lastBoost = (player:GetAttribute("CashBoostUntil") :: any) or 0
	player:GetAttributeChangedSignal("Gems"):Connect(function()
		local g = player:GetAttribute("Gems")
		if type(g) == "number" and type(lastGems) == "number" and g > lastGems then
			Controller.Play(pick("E2_", 2), { bus = "UI", volume = 1 })
		end
		lastGems = g :: any
	end)
	player:GetAttributeChangedSignal("RebirthCount"):Connect(function()
		local r = player:GetAttribute("RebirthCount")
		if type(r) == "number" and type(lastRebirth) == "number" and r > lastRebirth then
			Controller.Play("J20", { bus = "Rewards" })
		end
		lastRebirth = r :: any
	end)
	player:GetAttributeChangedSignal("CashBoostUntil"):Connect(function()
		local b = player:GetAttribute("CashBoostUntil")
		if type(b) == "number" and b > lastBoost and b > Workspace:GetServerTimeNow() then
			Controller.Play("E3", { bus = "UI" })
			boostWarned = false
		end
		lastBoost = if type(b) == "number" then b else 0
	end)
	-- on-foot pickup: the server mirrors the carried item onto the player
	local lastCarried = player:GetAttribute("CarriedItemId")
	player:GetAttributeChangedSignal("CarriedItemId"):Connect(function()
		local carried = player:GetAttribute("CarriedItemId")
		if carried ~= nil and carried ~= lastCarried then
			Controller.Play(pick("S5_", 2), { volume = 0.9 })
		end
		lastCarried = carried
	end)
	player:GetAttributeChangedSignal("Phase13RegionId"):Connect(onRegionChanged)
	player:GetAttributeChangedSignal("Phase10InCamp"):Connect(onRegionChanged)
end

-- ---------------------------------------------------------------- UI taps

local buttonConnections = setmetatable({} :: { [Instance]: boolean }, { __mode = "k" })
local function hookButton(b: Instance)
	if buttonConnections[b] or not b:IsA("GuiButton") then
		return
	end
	buttonConnections[b] = true
	(b :: GuiButton).Activated:Connect(function()
		-- close / cancel buttons get the menu-close pops instead of the tap
		local name = string.lower(b.Name)
		local text = if b:IsA("TextButton") then string.lower(b.Text) else ""
		local closes = text == "x"
			or text == "✕"
			or text == "×"
			or string.find(name, "close", 1, true) ~= nil
			or string.find(name, "cancel", 1, true) ~= nil
			or string.sub(text, 1, 5) == "close"
		if closes then
			Controller.Play("U3", { bus = "UI", cooldown = 0.1 })
		else
			Controller.Play(pick("U1_", 3), { bus = "UI", cooldown = 0.04 })
		end
	end)
end

local function watchGui()
	local gui = player:WaitForChild("PlayerGui")
	for _, d in gui:GetDescendants() do
		hookButton(d)
	end
	gui.DescendantAdded:Connect(hookButton)
end

-- ---------------------------------------------------------------- toys, traversal, footsteps

local toyParts: { BasePart } = {}
local toyInfo: { [BasePart]: { set: string, note: number, kind: string, group: Instance } } = {}
local partLastHit: { [BasePart]: number } = {}
-- Toy props are decoration (CanQuery = false), so spatial queries never see them. Parts are bucketed
-- into an XZ grid instead and tested by distance to their box.
local TOY_RADIUS = 4.5
local TOY_CELL = 16
local toyGrid: { [number]: { BasePart } } = {}
local toysInside: { [Instance]: boolean } = {}

local function toyCell(cx: number, cz: number): number
	return cx * 65537 + cz
end

local function addToyToGrid(part: BasePart)
	local cf, half = part.CFrame, part.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z + TOY_RADIUS
	local ez = math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z + TOY_RADIUS
	local p = cf.Position
	for cx = math.floor((p.X - ex) / TOY_CELL), math.floor((p.X + ex) / TOY_CELL) do
		for cz = math.floor((p.Z - ez) / TOY_CELL), math.floor((p.Z + ez) / TOY_CELL) do
			local key = toyCell(cx, cz)
			local bucket = toyGrid[key]
			if not bucket then
				bucket = {}
				toyGrid[key] = bucket
			end
			table.insert(bucket, part)
		end
	end
end

local function toyDistance(part: BasePart, position: Vector3): number
	local half = part.Size / 2
	local p = part.CFrame:PointToObjectSpace(position)
	local d = Vector3.new(
		math.max(math.abs(p.X) - half.X, 0),
		math.max(math.abs(p.Y) - half.Y, 0),
		math.max(math.abs(p.Z) - half.Z, 0)
	)
	return d.Magnitude
end

local function noteFor(part: BasePart, count: number): number
	local p = part.Position
	local h = math.floor(math.abs(p.X * 7.13 + p.Z * 3.71 + p.Y * 1.3)) % count
	return h + 1
end

local function indexToys()
	table.clear(toyParts)
	table.clear(toyInfo)
	table.clear(toyGrid)
	local world = Workspace:FindFirstChild("World")
	if not world then
		return
	end
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			local kind: string? = nil
			local set = ""
			local group: Instance = d
			local a: Instance? = d.Parent
			while a and a ~= world do
				local name = a.Name
				if name:find("^Toy_") then
					kind = if name:find("Slide") then "slide" elseif name:find("Bounce") then "bounce" else nil
					local regionFolder = a.Parent
					set = if regionFolder and regionFolder.Name == "Arctic" then "R5" else ""
					break
				end
				for _, t in Catalog.Toys :: any do
					if name:find(t.pattern) then
						kind = "toy"
						set = t.set
						break
					end
				end
				if kind then
					break
				end
				a = a.Parent
			end
			if kind then
				group = a or d
				table.insert(toyParts, d)
				local count = (Catalog.ToyNotes :: any)[set] or 1
				toyInfo[d] = { set = set, note = noteFor(d, count), kind = kind, group = group }
				addToyToGrid(d)
			end
		end
	end
end

local function playToy(part: BasePart, info: { set: string, note: number, kind: string, group: Instance })
	local t = now()
	if partLastHit[part] and t - partLastHit[part] < 0.6 then
		return
	end
	partLastHit[part] = t
	if info.kind == "bounce" then
		Controller.Play("T1", { cooldown = 0.8, volume = 0.9 })
		return
	elseif info.kind == "slide" then
		Controller.Play("T2", { cooldown = 1.5, volume = 0.9 })
		if info.set == "R5" then
			Controller.Play("R5_toy_slide", { cooldown = 3 })
		end
		return
	end
	if t - state.toyLastAt < 0.15 then
		return
	end
	local set = info.set
	local id
	if set == "R1" then
		-- mushrooms climb the scale with each bounce in a row
		state.toyIndex = if t - state.toyLastAt < 3 then (state.toyIndex % 8) + 1 else 1
		id = "R1_toy_" .. state.toyIndex
	elseif set == "R6plop" then
		id = "R6_toy_plop"
	elseif set == "R7" then
		id = if info.note == 8 and math.random() < 0.35 then "R7_toy_silly_" .. math.random(1, 3) else "R7_toy_" .. info.note
	else
		id = set .. "_toy_" .. info.note
	end
	state.toyLastAt = t
	Controller.Play(id, { position = part.Position, range = 90, cap = "toy", capCount = 6 })
	if set == "R5" then
		-- hidden reward: five rising icicle notes in a row make them sparkle
		table.insert(state.toyRun, info.note)
		if #state.toyRun > 5 then
			table.remove(state.toyRun, 1)
		end
		local rising = #state.toyRun == 5
		for i = 2, #state.toyRun do
			if state.toyRun[i] <= state.toyRun[i - 1] then
				rising = false
			end
		end
		if rising then
			table.clear(state.toyRun)
			task.delay(0.3, function()
				Controller.Play("R5_toy_secret", { position = part.Position, range = 120 })
			end)
		end
	end
end

local stepAccumulator = 0
local function stepFootsteps(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if not humanoid or not root or humanoid.Sit or humanoid.FloorMaterial == Enum.Material.Air then
		stepAccumulator = 0
		return
	end
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	if speed < 3 then
		stepAccumulator = 0
		return
	end
	-- mute Roblox's default running sound once; region steps replace it
	local running = root:FindFirstChild("Running")
	if running and running:IsA("Sound") and running.Volume > 0 then
		running.Volume = 0
	end
	stepAccumulator += dt * speed / 16
	if stepAccumulator >= 0.32 then
		stepAccumulator = 0
		local key = state.region or "R1"
		Controller.Play(key .. "_step_" .. math.random(1, 3), { volume = 0.35, pitch = 0.95 + math.random() * 0.1 })
	end
end

-- ---------------------------------------------------------------- per-frame

local toyClock = 0
local engineSound: Sound? = nil
local LocalCartState: any = nil
local landmarkNext: { [string]: number } = {}

local burstWasActive = false
local villagerStepClock = 0

-- quiet patter under villagers that are chasing near you (nearest first, three at most)
local function stepVillagerFootsteps(dt: number)
	villagerStepClock += dt
	if villagerStepClock < 0.26 then
		return
	end
	villagerStepClock = 0
	local folder = Workspace:FindFirstChild("Villagers")
	local root = rootPart()
	if not folder or not root then
		return
	end
	for _, v in folder:GetChildren() do
		if v:GetAttribute("State") == "Chase" then
			local pos = villagerPosition(v)
			if pos and (pos - root.Position).Magnitude < 70 then
				Controller.Play("S11", {
					position = pos,
					range = 70,
					volume = 0.5,
					pitch = 0.9 + math.random() * 0.2,
					cap = "vstep",
					capCount = 3,
				})
			end
		end
	end
end

local function stepEngine()
	local cart = LocalCartState and LocalCartState.GetCart and LocalCartState.GetCart()
	local driving = cart and LocalCartState.IsAuthorizedDriver and LocalCartState.IsAuthorizedDriver()
	-- cart burst (boost) starting
	local burst = driving and cart and cart:GetAttribute("BurstActive") == true
	if burst and not burstWasActive then
		Controller.Play(pick("S8_", 2), { volume = 0.9 })
	end
	burstWasActive = burst == true
	if driving and cart then
		local primary = cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart")
		if not primary then
			return
		end
		if not engineSound or engineSound.Parent ~= primary then
			if engineSound then
				engineSound:Destroy()
			end
			local asset = (Catalog.Loops :: any).S7
			if asset == "" then
				return
			end
			local s = Instance.new("Sound")
			s.Name = "BE_Engine"
			s.SoundId = asset
			s.Looped = true
			s.Volume = 0
			s.SoundGroup = groups.SFX
			s.RollOffMinDistance = 15
			s.RollOffMaxDistance = 120
			s.Parent = primary
			s:Play()
			engineSound = s
		end
		local speed = primary.AssemblyLinearVelocity.Magnitude
		local x = math.clamp(speed / 60, 0, 1)
		local s = engineSound :: Sound
		s.PlaybackSpeed = 0.7 + x * 0.75
		s.Volume = 0.25 + x * 0.35
	elseif engineSound then
		engineSound:Destroy()
		engineSound = nil
	end
end

local function stepRing()
	if not state.chase or not state.chaseCenter or state.ringNearPlayed or state.chaseRadius <= 0 then
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	local flat = Vector3.new(root.Position.X - state.chaseCenter.X, 0, root.Position.Z - state.chaseCenter.Z).Magnitude
	if flat >= state.chaseRadius * 0.85 then
		state.ringNearPlayed = true
		Controller.Play("S15", { volume = 0.75 })
	end
end

local function stepLandmarks()
	local key = state.region
	if not key or state.inCamp then
		return
	end
	local spec = (Catalog.Landmarks :: any)[key]
	if not spec then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local slot = math.floor((serverNow - spec.offset) / spec.period)
	if landmarkNext[key] == nil then
		landmarkNext[key] = slot
	elseif slot > landmarkNext[key] then
		landmarkNext[key] = slot
		playLandmark(key)
	end
end

local function onHeartbeat(dt: number)
	stepLoops(dt)
	stepEngine()
	stepVillagerFootsteps(dt)
	stepRing()
	stepFootsteps(dt)
	toyClock += dt
	if toyClock >= 0.12 then
		toyClock = 0
		stepLandmarks()
		local root = rootPart()
		if root and #toyParts > 0 then
			-- Sound toys give one note per arrival (walk up, hop on, land) and re-arm once you move
			-- away. Slide/bounce toys keep retriggering on their own cooldowns while you are on them.
			local position = root.Position
			local bucket = toyGrid[toyCell(math.floor(position.X / TOY_CELL), math.floor(position.Z / TOY_CELL))]
			local inside: { [Instance]: boolean } = {}
			if bucket then
				for _, part in bucket do
					local info = toyInfo[part]
					if info and not inside[info.group] and part.Parent and toyDistance(part, position) <= TOY_RADIUS then
						inside[info.group] = true
						if info.kind ~= "toy" or not toysInside[info.group] then
							playToy(part, info)
						end
					end
				end
			end
			toysInside = inside
		end
	end
end

-- ---------------------------------------------------------------- start

local function bindRemote(name: string, handler: (...any) -> ())
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 120)
		if not remotes then
			return
		end
		local bound = false
		local function try(remote: Instance?)
			if not bound and remote and remote.Name == name and remote:IsA("RemoteEvent") then
				bound = true
				remote.OnClientEvent:Connect(handler)
			end
		end
		-- some remotes (AudioCue) are created later by the server; bind whenever they appear
		try(remotes:FindFirstChild(name))
		if not bound then
			remotes.ChildAdded:Connect(try)
		end
	end)
end

function Controller.Start()
	if started then
		return
	end
	started = true
	makeGroup("Music", 0.3)
	makeGroup("Ambience", 0.18)
	makeGroup("SFX", 0.6)
	makeGroup("UI", 0.45)
	makeGroup("Rewards", 0.95)
	local folder = Instance.new("Folder")
	folder.Name = "BE_Audio"
	folder.Parent = SoundService
	oneShotFolder = folder

	local okState, cartState = pcall(function()
		return require(script.Parent.Parent.State.LocalCartState)
	end)
	LocalCartState = if okState then cartState else nil

	-- trend test: keep the hub theme silent until we know whether the join intro will play
	if player:GetAttribute("AudioVariant") ~= "Current" and (Catalog.Packs :: any).Trend ~= "" then
		state.introUntil = now() + 11
	end
	startMusic()
	onRegionChanged()
	watchPlayerAttributes()

	-- trend test: phonk join intro, once per session, then the hub theme takes over
	task.spawn(function()
		local waited = 0
		while player:GetAttribute("AudioVariant") == nil and waited < 10 do
			task.wait(0.25)
			waited += 0.25
		end
		if trend() and not state.introPlayed and (Catalog.Packs :: any).Trend ~= "" then
			if not player.Character then
				player.CharacterAdded:Wait()
			end
			task.wait(0.4)
			state.introPlayed = true
			state.introUntil = now() + 5.6
			applyMusicState()
			Controller.Play("JOIN_INTRO", { bus = "Rewards" })
			task.delay(5.7, applyMusicState)
		else
			state.introUntil = 0
		end
		applyMusicState()
	end)
	player:GetAttributeChangedSignal("AudioVariant"):Connect(applyMusicState)

	-- preload the packs so the first catch is instant
	task.spawn(function()
		local list = {}
		for _, s in loops do
			table.insert(list, s)
		end
		for _, asset in Catalog.Packs :: any do
			if asset ~= "" then
				local probe = Instance.new("Sound")
				probe.SoundId = asset
				table.insert(list, probe)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)

	bindRemote("SleepRequest", onSleepResult)
	bindRemote("Phase12Event", onPhase12)
	bindRemote("VillagerGuardEvent", onGuardEvent)
	bindRemote("WorldAnnouncement", onAnnouncement)
	bindRemote("WorldProgressionUpdate", onProgression)
	bindRemote("StormPush", onStormPush)
	bindRemote("CartUpgradeShopUpdate", onUpgradeUpdate)
	bindRemote("OpenCartUpgradeShop", function()
		Controller.Play("U2", { bus = "UI" })
	end)
	bindRemote("AudioCue", onAudioCue)

	task.spawn(function()
		local villagers = Workspace:WaitForChild("Villagers", 120)
		if villagers then
			for _, v in villagers:GetChildren() do
				watchVillager(v)
			end
			villagers.ChildAdded:Connect(function(v)
				task.wait(0.5)
				watchVillager(v)
			end)
			villagers.ChildRemoved:Connect(function(v)
				local c = villagerConnections[v]
				if c then
					c:Disconnect()
					villagerConnections[v] = nil
				end
			end)
		end
	end)

	task.spawn(watchGui)
	task.spawn(function()
		Workspace:WaitForChild("World", 120)
		indexToys()
		-- streamed world parts arrive over time; refresh the toy index now and then
		while started do
			task.wait(20)
			indexToys()
		end
	end)

	task.spawn(function()
		while started do
			task.wait(1)
			local b = player:GetAttribute("CashBoostUntil")
			if type(b) == "number" then
				local left = b - Workspace:GetServerTimeNow()
				if left > 0 and left <= 30 and not boostWarned then
					boostWarned = true
					Controller.Play("E4", { bus = "UI" })
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return Controller
