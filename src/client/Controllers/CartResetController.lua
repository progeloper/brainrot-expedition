--!strict
-- Compatibility lifecycle entry point. Gameplay correction is server-owned;
-- no keyboard, controller, touch hold or legacy remote invocation remains.
local CartInputController = require(script.Parent.CartInputController)
local Controller = {}
function Controller.Start()
	CartInputController.SetResetEnabled(false)
	CartInputController.SetResetVisible(false)
end
function Controller.Stop()
	CartInputController.SetResetEnabled(false)
	CartInputController.SetResetVisible(false)
end
return Controller
