--!strict
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Expression =
	require(game:GetService("ReplicatedStorage").Shared.Utility.RetentionExpressionPresentation)
local Controller = {}
local connections = {}
local started = false
local perPlayer = {}
local chatPrefixReady = false
local function unbind(player)
	local binding = perPlayer[player]
	if not binding then
		return
	end
	perPlayer[player] = nil
	if binding.HeadConnection then
		binding.HeadConnection:Disconnect()
	end
	for _, connection in binding.Connections do
		connection:Disconnect()
	end
end
local function decorate(player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local entitled = player:GetAttribute("Entitlement_VIP") == true
	local selectedTitle = player:GetAttribute("RetentionTitleLabel")
	local title = if type(selectedTitle) == "string"
		then selectedTitle
		else (if entitled and player:GetAttribute("Appearance_VIPTitle") == "On"
			then "Rift Patron"
			else "")
	Expression.Identity(head, {
		vip = entitled and player:GetAttribute("Appearance_VIPBadge") == "On",
		title = title,
		nameplate = player:GetAttribute("RetentionNameplateLabel"),
		badge = player:GetAttribute("RetentionBadgeLabel"),
	})
end
local function bind(player)
	unbind(player)
	local binding = { Connections = {}, HeadConnection = nil }
	perPlayer[player] = binding
	local function current(character)
		return started and perPlayer[player] == binding and player.Character == character
	end
	local function characterAdded(character)
		if binding.HeadConnection then
			binding.HeadConnection:Disconnect()
		end
		binding.HeadConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "Head" and current(character) then
				decorate(player)
			end
		end)
		if character:FindFirstChild("Head") then
			if current(character) then
				decorate(player)
			end
		else
			task.spawn(function()
				character:WaitForChild("Head", 10)
				-- A late Head cannot resurrect a stopped controller or old character.
				if current(character) then
					decorate(player)
				end
			end)
		end
	end
	for _, key in
		{
			"Entitlement_VIP",
			"Appearance_VIPBadge",
			"Appearance_VIPTitle",
			"RetentionTitleLabel",
			"RetentionNameplateLabel",
			"RetentionBadgeLabel",
		}
	do
		table.insert(
			binding.Connections,
			player:GetAttributeChangedSignal(key):Connect(function()
				if perPlayer[player] == binding then
					decorate(player)
				end
			end)
		)
	end
	table.insert(binding.Connections, player.CharacterAdded:Connect(characterAdded))
	table.insert(
		binding.Connections,
		player.CharacterRemoving:Connect(function()
			if binding.HeadConnection then
				binding.HeadConnection:Disconnect()
				binding.HeadConnection = nil
			end
		end)
	)
	if player.Character then
		characterAdded(player.Character)
	end
end
-- Decoration only: filtered Text and channel delivery/moderation are never replaced.
function Controller.DecorateMessage(message, author)
	if
		author
		and author:GetAttribute("Entitlement_VIP") == true
		and author:GetAttribute("Appearance_VIPChat") == "On"
	then
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = "<font color='#F6C448'>[VIP]</font> " .. message.PrefixText
		return props
	end
	return nil
end
function Controller.GetDiagnostics()
	return {
		chatPrefixReady = chatPrefixReady,
		reason = if chatPrefixReady then "READY" else "PLATFORM_CHAT_DECORATION_UNAVAILABLE",
	}
end
function Controller.Start()
	if started then
		return false
	end
	started = true
	-- PrefixText retains the platform/role prefix. Filtered message text is never replaced.
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		-- One source owns this callback. Callback members are write-only; never read/chain them.
		chatPrefixReady = pcall(function()
			TextChatService.OnIncomingMessage = function(message)
				local source = message.TextSource
				local author = source and Players:GetPlayerByUserId(source.UserId)
				return Controller.DecorateMessage(message, author)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(bind))
	table.insert(connections, Players.PlayerRemoving:Connect(unbind))
	return true
end
function Controller.Stop()
	if not started then
		return
	end
	started = false
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		if chatPrefixReady then
			pcall(function()
				TextChatService.OnIncomingMessage = nil
			end)
		end
		chatPrefixReady = false
	end
	for player in perPlayer do
		unbind(player)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, player in Players:GetPlayers() do
		local head = player.Character and player.Character:FindFirstChild("Head")
		local badge = head and head:FindFirstChild("Phase13VIPIdentity")
		if badge then
			badge:Destroy()
		end
	end
end
return Controller
