--!strict
-- AudioVariantService: assigns each player's audio A/B variant ("Trend" or "Current").
-- Presentation only. The client AudioController reads the "AudioVariant" player attribute.
-- The variant is stable per user (same answer every session), so a player never flips between
-- soundtracks, and analytics can compare the two groups.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Shared.Config.FeatureFlags)

local Service = {}

local function bucket(userId: number): number
	-- simple string hash of the UserId -> 0..999 (avoids UserId parity / range bias)
	local h = 7
	for i = 1, #tostring(userId) do
		h = (h * 31 + string.byte(tostring(userId), i)) % 1000003
	end
	return h % 1000
end

function Service.VariantFor(userId: number): string
	local flags = FeatureFlags :: any
	if not flags.GameAudioEnabled or not flags.TrendAudioTest then
		return "Current"
	end
	local share = if type(flags.TrendAudioShare) == "number" then flags.TrendAudioShare else 0.5
	return if bucket(userId) < share * 1000 then "Trend" else "Current"
end

function Service.Start()
	local function assign(player: Player)
		player:SetAttribute("AudioVariant", Service.VariantFor(player.UserId))
	end
	for _, player in Players:GetPlayers() do
		assign(player)
	end
	Players.PlayerAdded:Connect(assign)
end

return Service
