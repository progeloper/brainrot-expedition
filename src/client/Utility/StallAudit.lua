--!strict
-- Playtest Fixes 2 Part E3: the camp stall audit (DEV only: Studio, or ReplicatedStorage.StallAudit
-- = true on a live server). Read-only:
--   * every stall in CampLayout.ModelNames has exactly one enabled ProximityPrompt (NEWS: none);
--   * every window opened at a stall is that stall's own window (recorded by the shop/sale
--     controllers through StallAudit.Record);
--   * a red label floats over any stall that fails. The report prints to the output.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CampLayout = require(ReplicatedStorage.Shared.Config.CampLayout)

local StallAudit = {}

-- Stall key -> the window category it must open (nil = opens nothing).
StallAudit.Expected = table.freeze({
	Weapons = "Weapon",
	Carts = "Cart",
	Sell = "Sell",
	Training = "Training",
	Gems = "Passes",
	Announcements = false,
} :: { [string]: string | boolean })

local observed: { [string]: { [string]: number } } = {}

function StallAudit.On(): boolean
	return RunService:IsStudio() or ReplicatedStorage:GetAttribute("StallAudit") == true
end

local function services(): Instance?
	local map = Workspace:FindFirstChild("MapBlockout")
	local art = map and map:FindFirstChild("MapArt")
	return art and art:FindFirstChild("Services")
end

local function stallModel(key: string): Model?
	local folder = services()
	local name = (CampLayout.ModelNames :: any)[key]
	local found = folder and name and folder:FindFirstChild(name, true)
	return if found and found:IsA("Model") then found else nil
end

local function promptPosition(prompt: Instance): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

-- A prompt belongs to a stall when it sits inside the stall's bounding box (+2 studs): some stall
-- prompts live in MapBlockout.ServiceStallPatches, outside the art model (e.g. the Sell counter).
local function insideStall(model: Model, position: Vector3): boolean
	local frame, size = model:GetBoundingBox()
	local localPos = frame:PointToObjectSpace(position)
	local half = size / 2 + Vector3.new(2, 2, 2)
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- The stall key whose model contains `object` (by ancestry or position).
function StallAudit.StallOf(object: Instance?): string?
	if not object then
		return nil
	end
	local position = if object:IsA("ProximityPrompt") then promptPosition(object) else nil
	for key in StallAudit.Expected do
		local model = stallModel(key)
		if
			model and (object:IsDescendantOf(model) or (position and insideStall(model, position)))
		then
			return key
		end
	end
	return nil
end

-- Called when a window opens at a stall prompt.
function StallAudit.Record(category: string, prompt: Instance?)
	if not StallAudit.On() then
		return
	end
	local key = StallAudit.StallOf(prompt)
	if not key then
		return
	end
	local bucket = observed[key] or {}
	observed[key] = bucket
	bucket[category] = (bucket[category] or 0) + 1
end

local function enabledPrompts(model: Model): { ProximityPrompt }
	local out = {}
	local map = Workspace:FindFirstChild("MapBlockout") or Workspace
	for _, d in map:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Enabled then
			local position = promptPosition(d)
			if d:IsDescendantOf(model) or (position and insideStall(model, position)) then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- Pure: one stall's verdict. `expected` false = no prompt expected.
function StallAudit.Verdict(
	promptCount: number,
	expected: string | boolean,
	opened: { [string]: number }?
): (boolean, string)
	local wantPrompts = if expected == false then 0 else 1
	if promptCount ~= wantPrompts then
		return false, string.format("%d enabled prompts (want %d)", promptCount, wantPrompts)
	end
	for category in opened or {} do
		if category ~= expected then
			return false, "opened " .. category
		end
	end
	return true, "ok"
end

local labels: { [string]: BillboardGui } = {}
local function label(model: Model, key: string, text: string?)
	local existing = labels[key]
	if not text then
		if existing then
			existing:Destroy()
			labels[key] = nil
		end
		return
	end
	local bb = existing or Instance.new("BillboardGui")
	bb.Name = "StallAuditLabel"
	bb.Size = UDim2.fromOffset(260, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 18, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	local t = bb:FindFirstChild("Text") :: TextLabel? or Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(200, 20, 30)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Text = "STALL AUDIT: " .. key .. " — " .. text
	t.Parent = bb
	bb.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	bb.Parent = playerGui
	labels[key] = bb
end

function StallAudit.Run(): (boolean, string)
	local lines, allOk = {}, true
	for key, expected in StallAudit.Expected do
		local model = stallModel(key)
		if not model then
			-- Gems is flag-gated (moved out of the world when off); a missing stall is reported only.
			table.insert(lines, string.format("  %-13s missing", key))
		else
			local ok, why = StallAudit.Verdict(#enabledPrompts(model), expected, observed[key])
			allOk = allOk and ok
			table.insert(
				lines,
				string.format("  %-13s %s", key, if ok then "PASS" else "FAIL " .. why)
			)
			label(model, key, if ok then nil else why)
		end
	end
	table.sort(lines)
	local text = "[StallAudit] "
		.. (if allOk then "PASS" else "FAIL")
		.. "\n"
		.. table.concat(lines, "\n")
	return allOk, text
end

function StallAudit.Start()
	if not StallAudit.On() then
		return
	end
	task.delay(12, function()
		local _, text = StallAudit.Run()
		print(text)
	end)
end

return StallAudit
