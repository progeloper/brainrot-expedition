--!strict
-- Stud Pop UI entry point for client controllers. View layer only: nothing here reads or writes game
-- state beyond what a controller hands it. Menus are Plate windows (src/shared/UI/Plate.lua); the skin
-- below only dresses the in-game HUD pieces their controllers still build (action buttons, status rows,
-- burst/shield, mounted fire).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIPortraits = require(ReplicatedStorage.Shared.Config.UIPortraits)

local StudPopUI = {}

StudPopUI.Theme = require(ReplicatedStorage.Shared.UI.Theme)
StudPopUI.Juice = require(ReplicatedStorage.Shared.UI.Juice)
StudPopUI.StudPop = require(ReplicatedStorage.Shared.UI.StudPop)
StudPopUI.Portraits = UIPortraits

function StudPopUI.portrait(speciesId: unknown, discovered: boolean?): string
	return UIPortraits.get(speciesId, discovered)
end

-- Lazily attaches the skin so controllers only pay for the module when the flag is on.
function StudPopUI.skin(gui: Instance, options: any?)
	return require(script.Parent.StudPopSkin).Attach(gui, options)
end

return StudPopUI
