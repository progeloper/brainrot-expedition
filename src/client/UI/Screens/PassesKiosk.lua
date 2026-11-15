--!nocheck
-- MenusV2 entry point: a CLIENT-side ProximityPrompt on the Announcements kiosk that opens the
-- "Passes & Gems" window through the shop controller's existing open path (OpenFromHud("Passes") ->
-- open("Passes") -> Snapshot + OfferView -> PassesGemsScreen). Prompt/GemShop have no server location
-- gate (DATA_CONTRACT §1.8), so nothing server-side is needed. If the kiosk is missing it logs once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local Kiosk = {}

-- Playtest Fixes F2: with the Gems stall on, the prompt lives on its counter and the NEWS kiosk keeps
-- no prompt (it becomes a read-only board). Otherwise unchanged.
local PlaytestFlags = require(ReplicatedStorage.Shared.Config.PlaytestFixesFlags)
local GemsConfig = require(ReplicatedStorage.Shared.Config.PlaytestFixes).GemsStall
local GEMS = PlaytestFlags.Part("GemsStall")
local PATH = {
	"MapBlockout",
	"MapArt",
	"Services",
	if GEMS then GemsConfig.ModelName else "Kiosk_AnnouncementStall",
}
local WAIT_SECONDS = 30
local PROMPT_NAME = "PassesKioskPrompt"

local log = Logger.new("PassesKiosk")
local started = false
local warned = false
local attachToken = 0
local prompt: ProximityPrompt? = nil
local connections: { RBXScriptConnection } = {}

local function warnOnce(message: string)
	if not warned then
		warned = true
		log:Warn(message)
	end
end

local function findKiosk(deadline: number): Instance?
	local node: Instance? = workspace
	for _, name in PATH do
		local remaining = deadline - os.clock()
		if not node or remaining <= 0 then
			return nil
		end
		node = node:WaitForChild(name, remaining)
	end
	return node
end

-- PrimaryPart, else the largest BasePart (streamed parts may arrive a little after the model).
local function anchorPart(kiosk: Instance, deadline: number): BasePart?
	repeat
		if kiosk:IsA("BasePart") then
			return kiosk
		end
		if kiosk:IsA("Model") and kiosk.PrimaryPart then
			return kiosk.PrimaryPart
		end
		local best, bestVolume = nil, -1
		for _, d in kiosk:GetDescendants() do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bestVolume then
					best, bestVolume = d, v
				end
			end
		end
		if best then
			return best
		end
		task.wait(0.5)
	until os.clock() >= deadline or not kiosk.Parent
	return nil
end

local ANCHOR_NAME = "PassesKioskAnchor"
local PROMPT_HEIGHT = 3.5 -- studs above the kiosk floor

local function clear()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if prompt then
		local anchor = prompt.Parent
		prompt:Destroy()
		prompt = nil
		if anchor and anchor.Name == ANCHOR_NAME then
			anchor:Destroy()
		end
	end
end

-- Where a player can reach it: the middle of the kiosk's customer-facing front (its pivot's LookVector,
-- as in Config/CampLayout), at standing height. The building is 20 studs tall and 18 deep, so a prompt
-- on a part's centre sits out of reach.
local function frontPosition(kiosk: Model): Vector3
	local box, size = kiosk:GetBoundingBox()
	local look = kiosk:GetPivot().LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local inBox = box:VectorToObjectSpace(flat)
	local halfDepth = math.abs(inBox.X) * size.X / 2 + math.abs(inBox.Z) * size.Z / 2
	return Vector3.new(box.Position.X, box.Position.Y - size.Y / 2 + PROMPT_HEIGHT, box.Position.Z) + flat * halfDepth
end

local attach
-- `again`: the prompt existed before (kiosk streamed out); keep waiting instead of giving up.
attach = function(shop, again: boolean?)
	if not started then
		return
	end
	attachToken += 1
	local token = attachToken
	clear()
	local deadline = os.clock() + WAIT_SECONDS
	local kiosk = findKiosk(deadline)
	if token ~= attachToken then
		return
	end
	if not kiosk then
		if again and started then
			task.defer(attach, shop, true)
			return
		end
		warnOnce(PATH[#PATH] .. " not found; Passes & Gems kiosk prompt not created")
		return
	end
	local part = anchorPart(kiosk, deadline)
	if token ~= attachToken then
		return
	end
	if not part then
		if again and started then
			task.defer(attach, shop, true)
			return
		end
		warnOnce(PATH[#PATH] .. " has no BasePart; Passes & Gems kiosk prompt not created")
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = PROMPT_NAME
	p.ActionText = if GEMS then GemsConfig.PromptActionText else "Open"
	p.ObjectText = if GEMS then GemsConfig.PromptObjectText else "PASSES & GEMS"
	p.MaxActivationDistance = if GEMS then GemsConfig.PromptDistance else 12
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	local anchor = Instance.new("Attachment")
	anchor.Name = ANCHOR_NAME
	anchor.Parent = part
	if kiosk:IsA("Model") then
		anchor.WorldPosition = frontPosition(kiosk)
	end
	p.Parent = anchor
	prompt = p
	table.insert(
		connections,
		p.Triggered:Connect(function()
			shop.OpenFromHud("Passes")
		end)
	)
	-- streamed out / rebuilt: attach again to whatever kiosk part comes back
	table.insert(
		connections,
		p.AncestryChanged:Connect(function()
			if not p:IsDescendantOf(workspace) and prompt == p then
				task.defer(attach, shop, true)
			end
		end)
	)
end

-- shop = Phase13ShopController (needs OpenFromHud).
function Kiosk.Start(shop)
	if started or not shop then
		return false
	end
	started = true
	task.spawn(attach, shop)
	return true
end

function Kiosk.Stop()
	started = false
	attachToken += 1
	clear()
end

return Kiosk
