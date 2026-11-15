--!strict

-- Retired automatic-arrival entrypoints. Keep this small inert compatibility
-- surface so a stale caller cannot re-enable a scanner or bank cargo.
-- Deliberate placement is owned by BrainrotInteractionSystem.TryPlaceOnPlatform.
local BaseReturnSystem = {}

function BaseReturnSystem:Start() end
function BaseReturnSystem:Step() end
function BaseReturnSystem:Destroy() end

function BaseReturnSystem:TryUnloadCart(_player: Player, _cart: Model, _storage: any): any
	return { Success = false, Reason = "MANUAL_PLACEMENT_REQUIRED", Moved = 0 }
end

return BaseReturnSystem
