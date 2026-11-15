--!strict

-- Restore only controls this owner disabled or explicitly received from a
-- closing menu. A menu/daze boundary can transfer that permission without
-- briefly enabling touch movement or taking somebody else's disabled state.
local ControlRestore = {}

function ControlRestore.new(isBlocked: () -> boolean): any
	local owned: { [any]: boolean } = {}
	local restore = {}

	function restore:Hold(controls: any): boolean
		if not controls or controls.controlsEnabled == false then
			return false
		end
		controls:Disable()
		owned[controls] = true
		return true
	end

	function restore:ReleaseWhenAllowed(): boolean
		if isBlocked() then
			return false
		end
		for controls in owned do
			owned[controls] = nil
			controls:Enable()
		end
		return true
	end

	function restore:ResumeWhenAllowed(controls: any)
		if not controls then
			return
		end
		-- The caller already owns restoration (its pre-menu state was enabled).
		owned[controls] = true
		if isBlocked() then
			if controls.controlsEnabled ~= false then
				controls:Disable()
			end
		else
			self:ReleaseWhenAllowed()
		end
	end

	return restore
end

return table.freeze(ControlRestore)
