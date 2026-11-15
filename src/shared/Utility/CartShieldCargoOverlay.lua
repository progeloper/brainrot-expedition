--!strict

local Display = require(script.Parent.Parent.Config.BrainrotDisplayConfig)
local Presentation = require(script.Parent.CartShieldPresentation)
local Overlay = {}
Overlay.__index = Overlay

local function disconnect(list: { any })
	for _, connection in list do connection:Disconnect() end
	table.clear(list)
end

function Overlay.IsCargo(cart: Model, folder: Instance?, visual: Instance): boolean
	if not folder or folder.Name ~= "CargoVisuals" or folder.Parent ~= cart or not folder:IsA("Folder")
		or not visual:IsA("Model") or visual.Parent ~= folder then return false end
	local id = visual:GetAttribute("ItemId")
	local index = visual:GetAttribute("AttachmentIndex")
	if type(id) ~= "string" or id == "" or type(index) ~= "number" or index <= 0 or index % 1 ~= 0
		or visual:GetAttribute(Display.Attributes.DisplayState) ~= Display.States.Cart then return false end
	local slots = cart:FindFirstChild("CargoSlots")
	local slot = slots and slots:FindFirstChild("Slot" .. index)
	return slot ~= nil and slot:IsA("BasePart") and slot:GetAttribute("CargoItemId") == id
end

function Overlay.new(cart: Model, dependencies: any?): any
	local supplied = dependencies or {}
	local self = setmetatable({ Cart = cart, Snapshot = nil, Active = false, Destroyed = false,
		Clock = supplied.Clock or function() return workspace:GetServerTimeNow() end,
		Defer = supplied.Defer or task.defer, Generation = 0, Pending = false,
		Folder = nil, Connections = {}, FolderConnections = {}, Records = {},
		SlotsFolder = nil, SlotFolderConnections = {}, SlotRecords = {} }, Overlay)
	local function changed() self:QueueRefresh() end
	table.insert(self.Connections, cart.ChildAdded:Connect(changed))
	table.insert(self.Connections, cart.ChildRemoved:Connect(changed))
	self:Refresh()
	return self
end

function Overlay:QueueRefresh()
	if self.Destroyed or self.Pending then return end
	self.Pending = true
	local generation = self.Generation
	self.Defer(function()
		if self.Destroyed or self.Generation ~= generation then return end
		self.Pending = false
		self:Refresh()
	end)
end

function Overlay:Remove(visual: Model)
	local record = self.Records[visual]
	if not record then return end
	self.Records[visual] = nil
	disconnect(record.Connections)
	if record.Highlight then record.Highlight:Destroy() end
end

function Overlay:Update(visual: Model, record: any)
	local eligible = Overlay.IsCargo(self.Cart, self.Folder, visual)
	if not eligible then
		if record.Highlight then record.Highlight:Destroy() record.Highlight = nil end
		return
	end
	local active = self.Snapshot ~= nil and Presentation.View(self.Snapshot, self.Clock()).active
	if active and not record.Highlight then
		local highlight = Instance.new("Highlight")
		highlight.Name = "CartShieldCargoFilm"
		highlight.Adornee = visual
		highlight.FillColor = Color3.fromRGB(153, 221, 255)
		highlight.FillTransparency = 0.55
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = visual
		record.Highlight = highlight
	end
	if record.Highlight then record.Highlight.Enabled = active end
end

function Overlay:Refresh()
	if self.Destroyed then return end
	local slots = self.Cart:FindFirstChild("CargoSlots")
	if slots and not slots:IsA("Folder") then slots = nil end
	if slots ~= self.SlotsFolder then
		disconnect(self.SlotFolderConnections)
		self.SlotsFolder = slots
		if slots then
			table.insert(self.SlotFolderConnections, slots.ChildAdded:Connect(function() self:QueueRefresh() end))
			table.insert(self.SlotFolderConnections, slots.ChildRemoved:Connect(function() self:QueueRefresh() end))
		end
	end
	for slot, list in self.SlotRecords do if slot.Parent ~= slots then disconnect(list) self.SlotRecords[slot] = nil end end
	for _, slot in if slots then slots:GetChildren() else {} do
		if slot:IsA("BasePart") and not self.SlotRecords[slot] then
			self.SlotRecords[slot] = { slot:GetAttributeChangedSignal("CargoItemId"):Connect(function() self:QueueRefresh() end) }
		end
	end
	local folder = self.Cart:FindFirstChild("CargoVisuals")
	if folder and not folder:IsA("Folder") then folder = nil end
	if folder ~= self.Folder then
		disconnect(self.FolderConnections)
		self.Folder = folder
		if folder then
			table.insert(self.FolderConnections, folder.ChildAdded:Connect(function() self:QueueRefresh() end))
			table.insert(self.FolderConnections, folder.ChildRemoved:Connect(function() self:QueueRefresh() end))
		end
	end
	for visual in self.Records do
		if visual.Parent ~= folder then self:Remove(visual) end
	end
	for _, visual in if folder then folder:GetChildren() else {} do
		if not visual:IsA("Model") then continue end
		local record = self.Records[visual]
		if not record then
			record = { Connections = {}, Highlight = nil }
			self.Records[visual] = record
			for _, attribute in { "ItemId", "AttachmentIndex", Display.Attributes.DisplayState } do
				table.insert(record.Connections, visual:GetAttributeChangedSignal(attribute):Connect(function()
					if not self.Destroyed and self.Records[visual] == record then self:Update(visual, record) end
				end))
			end
			table.insert(record.Connections, visual.AncestryChanged:Connect(function()
				if not self.Destroyed and visual.Parent ~= self.Folder then self:Remove(visual) end
			end))
		end
		self:Update(visual, record)
	end
end

function Overlay:Sync(value: any, now: number): boolean
	if self.Destroyed or not Presentation.Accept(self.Snapshot, value, self.Cart:GetAttribute("CartGeneration")) then return false end
	self.Snapshot = value
	local active = Presentation.View(value, now).active
	if active ~= self.Active then
		self.Active = active
		for visual, record in self.Records do self:Update(visual, record) end
	end
	return true
end

function Overlay:Tick(now: number)
	if self.Destroyed or not self.Snapshot then return end
	local active = Presentation.View(self.Snapshot, now).active
	if active == self.Active then return end
	self.Active = active
	for visual, record in self.Records do self:Update(visual, record) end
end

function Overlay:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.Generation += 1
	disconnect(self.Connections)
	disconnect(self.FolderConnections)
	disconnect(self.SlotFolderConnections)
	for slot, list in self.SlotRecords do disconnect(list) self.SlotRecords[slot] = nil end
	for visual in self.Records do self:Remove(visual) end
	self.Folder, self.SlotsFolder = nil, nil
end

function Overlay:Diagnostics(): any
	local records, highlights, connections = 0, 0, #self.Connections + #self.FolderConnections + #self.SlotFolderConnections
	for _, list in self.SlotRecords do connections += #list end
	for _, record in self.Records do
		records += 1
		if record.Highlight then highlights += 1 end
		connections += #record.Connections
	end
	return { records = records, highlights = highlights, connections = connections }
end

return Overlay
