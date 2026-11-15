--!strict
-- Read-only adornments for already-authorized labels. This module never reads
-- profile data or grants/equips a reward. Its caller supplies confirmed metadata.
local Expression = {}
local GOLD = Color3.fromRGB(246, 196, 72)

local function text(parent, name, size)
	local label = Instance.new("TextLabel")
	label.Name, label.BackgroundTransparency, label.Size = name, 1, UDim2.fromScale(1, 1)
	label.Font, label.TextSize, label.TextColor3 = Enum.Font.GothamBold, size, GOLD
	label.TextWrapped, label.RichText, label.Parent = true, false, parent
	return label
end

function Expression.Identity(head, values)
	local identity = head:FindFirstChild("Phase13VIPIdentity")
	local labels = {}
	if values.vip then
		table.insert(labels, "VIP")
	end
	for _, value in { values.title, values.nameplate } do
		if type(value) == "string" and value ~= "" then
			table.insert(labels, value)
		end
	end
	local badge = if type(values.badge) == "string" then values.badge else ""
	if #labels == 0 and badge == "" then
		if identity then
			identity:Destroy()
		end
		return nil
	end
	if not identity then
		identity = Instance.new("BillboardGui")
		identity.Name, identity.MaxDistance, identity.AlwaysOnTop = "Phase13VIPIdentity", 80, false
		identity.StudsOffset, identity.Adornee = Vector3.new(0, 2.2, 0), head
		text(identity, "Identity", 15).TextStrokeTransparency = 0.4
		local mark = text(identity, "CollectionBadge", 14)
		mark.TextColor3, mark.TextStrokeTransparency = Color3.fromRGB(220, 201, 255), 0.4
		identity.Parent = head
	end
	local hasBadge = badge ~= ""
	identity.Size = UDim2.fromOffset(280, if hasBadge then 76 else 52)
	local label = identity:FindFirstChild("Identity")
	label.Text, label.Size = table.concat(labels, " · "), UDim2.new(1, 0, 0, 52)
	local mark = identity:FindFirstChild("CollectionBadge")
	-- Tolerate an identity created by the earlier controller during source sync.
	if not mark then
		mark = text(identity, "CollectionBadge", 14)
	end
	mark.Text, mark.Visible = if hasBadge then "◆ " .. badge else "", hasBadge
	mark.Position, mark.Size = UDim2.fromOffset(0, 52), UDim2.new(1, 0, 0, 24)
	return identity
end

function Expression.Plaque(parent, label)
	local plaque = parent:FindFirstChild("CollectionMilestonePlaque")
	local visible = type(label) == "string" and label ~= ""
	if not visible then
		if plaque then
			plaque.Visible = false
		end
		return plaque
	end
	if not plaque then
		plaque = Instance.new("Frame")
		plaque.Name, plaque.BorderSizePixel = "CollectionMilestonePlaque", 0
		plaque.BackgroundColor3, plaque.Size = Color3.fromRGB(47, 35, 25), UDim2.new(1, -16, 0, 32)
		plaque.Position, plaque.Parent = UDim2.new(0, 8, 1, -40), parent
		local border = Instance.new("UIStroke")
		border.Color, border.Thickness, border.Parent = GOLD, 1, plaque
		text(plaque, "Reward", 14)
	end
	plaque.Reward.Text, plaque.Visible = label, true
	return plaque
end

return table.freeze(Expression)
