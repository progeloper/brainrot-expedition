--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Config.Environment)

local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

local player = Players.LocalPlayer
local log = Logger.new("ClientBootstrap")

local function start()
	assert(player ~= nil, "LocalPlayer was unavailable")

	log:Info("Starting client for %s in %s", player.Name, Environment.Name)

	log:Info("Client bootstrap complete")
end

start()
