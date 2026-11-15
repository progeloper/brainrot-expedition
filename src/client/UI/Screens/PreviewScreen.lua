--!nocheck
-- Preview dialog (from the legacy shop's preview / riftTile / previewRift modals). Local only: no remotes.
-- A Plate "Dialog" window at zIndex 20, so it sits above the open window without closing it, holding
-- ONE ViewportFrame (weapon / cart / base design, optional finish) or the approved rift image.
-- Opened through Phase13ShopController's ctx:
--   ctx.preview(kind, id, finish)       -> Screen.open       kind: "Weapon" | "Cart" | "Base"
--   ctx.previewRift(finishId, vip)      -> Screen.openRift   (Phase12PresentationController.PrepareRiftPreview)
--   ctx.previewSet(items, index)        -> Screen.openSet    several previews behind tabs
-- It closes with its own ✕ / scrim, and whenever the window under it closes or changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.PlateCommon)
local MenusV2 = require(script.Parent.Parent.MenusV2)
local AppearanceRules = require(ReplicatedStorage.Shared.Utility.Phase13AppearanceRules)
local Strings = require(ReplicatedStorage.Shared.Config.Phase13Strings)

local Plate, Theme = Common.Plate, Common.Theme
local P = Theme.Plate
local px = Theme.px

local ERROR_RED = Color3.fromHex("#FF6B7A")

local player = Players.LocalPlayer

local Screen = {}

export type Item = {
	label: string?,
	kind: string?, -- "Weapon" | "Cart" | "Base"
	id: string?, -- weapon id / cart assetName / base design id
	finish: string?,
	rift: boolean?,
	finishId: string?, -- rift only
	vip: boolean?, -- rift only; nil = legacy rule (every rift but the Singularity DEV preview is VIP-tinted)
}

local window = nil
local items: { Item } = {}
local index = 1
local tabs = nil
local riftPreview = nil
local openBag = nil

local function releaseRiftPreview()
	if riftPreview then
		riftPreview.Destroy()
		riftPreview = nil
	end
end

-- The model the legacy preview cloned for this kind/id.
local function findSource(kind: string?, id: string?): Instance?
	if type(id) ~= "string" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("CodeAssets")
	if kind == "Weapon" then
		local f = assets and assets:FindFirstChild("Weapons")
		return f and f:FindFirstChild(id)
	elseif kind == "Cart" then
		local studio = ReplicatedStorage:FindFirstChild("StudioAssets")
		local f = studio and studio:FindFirstChild("Carts")
		return f and f:FindFirstChild(id)
	elseif kind == "Base" then
		local f = assets and assets:FindFirstChild("BaseDesigns")
		return f and f:FindFirstChild(id)
	end
	return nil
end

local function available(item: Item): boolean
	return item.rift == true or findSource(item.kind, item.id) ~= nil
end

local function unavailable(parent: Instance)
	Plate.Label(parent, Strings.PreviewUnavailable, { size = 20, min = 14, wrap = true, z = 6 })
end

local function showModel(area: Frame, item: Item)
	local source = findSource(item.kind, item.id)
	if not source then
		unavailable(area)
		return
	end
	local view = Instance.new("ViewportFrame")
	view.Name = "PreviewViewport"
	view.Size = UDim2.fromScale(1, 1)
	view.BorderSizePixel = 0
	view.BackgroundColor3 = Color3.fromRGB(38, 33, 55)
	view.Ambient = Color3.fromRGB(210, 210, 220)
	view.LightColor = Color3.new(1, 1, 1)
	view.ZIndex = 6
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px(P.Radius.Card))
	corner.Parent = view
	local stroke = Instance.new("UIStroke")
	stroke.Color = P.Color.Ink
	stroke.Thickness = px(P.Stroke.Outline)
	stroke.Parent = view
	view.Parent = area
	local world = Instance.new("WorldModel")
	world.Parent = view
	local clone = source:Clone()
	local model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		for _, child in clone:GetChildren() do
			child.Parent = model
		end
		clone:Destroy()
	end
	model.Parent = world
	AppearanceRules.Apply(model, item.finish or "Default", item.kind, item.id)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		elseif part:IsA("LuaSourceContainer") then
			part:Destroy()
		end
	end
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(radius * 0.95, radius * 0.65, -radius * 1.25), cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
end

local function showRift(area: Frame, item: Item)
	local finishId = item.finishId
	local vip = item.vip
	if vip == nil then
		vip = finishId ~= "FIN_SINGULARITY"
	end
	local ok, presentation = pcall(require, script.Parent.Parent.Parent.Controllers.Phase12PresentationController)
	if ok and type(presentation) == "table" and presentation.PrepareRiftPreview then
		local descriptor = nil
		if finishId == "FIN_SINGULARITY" then
			local definition = require(ReplicatedStorage.Shared.Config.Phase13OptionalFinishes).Finishes.FIN_SINGULARITY
			descriptor = { PrimaryImage = definition.TextureAssetId }
		end
		riftPreview = presentation.PrepareRiftPreview(area, {
			vip = vip == true,
			asset = descriptor,
			title = if descriptor then "Singularity DEV preview" else nil,
		})
	else
		Plate.Label(area, Strings.RiftLoading, { size = 18, min = 14, wrap = true, z = 6 })
	end
end

local function show()
	if not window then
		return
	end
	releaseRiftPreview()
	local old = window.Content:FindFirstChild("Area")
	if old then
		old:Destroy()
	end
	local top = if #items > 1 then px(44) else 0
	local area = Plate.frame(window.Content, "Area", {
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		ZIndex = 5,
	})
	local item = items[index]
	if not item then
		unavailable(area)
	elseif item.rift then
		showRift(area, item)
	else
		showModel(area, item)
	end
end

local function selectTab(id: string)
	local n = tonumber(id)
	if not n or n == index or not items[n] then
		return
	end
	index = n
	if tabs then
		tabs.setActive(id)
	end
	show()
end

function Screen.isOpen(): boolean
	return window ~= nil
end

function Screen.close(instant: boolean?)
	releaseRiftPreview()
	if openBag then
		openBag.clean()
		openBag = nil
	end
	tabs = nil
	local closing = window
	window = nil
	if closing then
		closing.close(instant) -- destroyOnClose: the dialog removes itself
	end
end

-- Opens the dialog on items[start]. Returns false (and tells the player) when nothing can be shown.
function Screen.openSet(list: { Item }, start: number?): boolean
	local usable = {}
	for _, item in list or {} do
		if type(item) == "table" and available(item) then
			table.insert(usable, item)
		end
	end
	if #usable == 0 then
		Plate.Toast(MenusV2.Gui(), Strings.PreviewUnavailable, { color = ERROR_RED })
		return false
	end
	Screen.close(true)
	items = usable
	index = math.clamp(start or 1, 1, #items)
	window = Plate.Window(MenusV2.Gui(), {
		key = "Dialog",
		title = "Preview",
		aspect = 1.5,
		widthScale = 0.62,
		heightScale = 0.86,
		maxSize = Vector2.new(470, 320),
		zIndex = 20,
		destroyOnClose = true,
		onClose = function()
			Screen.close(false)
		end,
	})
	window.open()
	if #items > 1 then
		local tabList = {}
		for i, item in items do
			table.insert(tabList, { id = tostring(i), text = item.label or tostring(i) })
		end
		tabs = Plate.Tabs(window.Content, {
			tabs = tabList,
			active = tostring(index),
			onSelect = selectTab,
			bag = window.bag,
			tabWidth = 88,
		})
	end
	-- the window under the dialog closed or changed (Back, walked away, died): close with it
	openBag = Plate.Bag()
	openBag.add(player:GetAttributeChangedSignal("MenusV2Open"):Connect(function()
		Screen.close(true)
	end))
	show()
	return true
end

function Screen.open(kind: string, id: string, finish: string?): boolean
	return Screen.openSet({ { kind = kind, id = id, finish = finish } }, 1)
end

function Screen.openRift(finishId: string?, vip: boolean?): boolean
	return Screen.openSet({ { rift = true, finishId = finishId, vip = vip } }, 1)
end

return Screen
