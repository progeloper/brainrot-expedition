--!strict

export type ActivationContext = {
	ControllerStarted: boolean,
	PlayerActive: boolean,
	AuthorizedDriver: boolean,
	CartAvailable: boolean,
	CartReady: boolean,
	TargetValid: boolean,
	CameraAvailable: boolean,
	CameraInputApplicable: boolean,
}

export type Snapshot = {
	Active: boolean,
	ContextRevision: number,
	ResetSuspended: boolean,
	ResyncRequired: boolean,
	ManualInputActive: boolean,
}

local CartCameraRuntimeState = {}

local function freezeSnapshot(
	active: boolean,
	contextRevision: number,
	resetSuspended: boolean,
	resyncRequired: boolean,
	manualInputActive: boolean
): Snapshot
	return table.freeze({
		Active = active,
		ContextRevision = contextRevision,
		ResetSuspended = resetSuspended,
		ResyncRequired = resyncRequired,
		ManualInputActive = manualInputActive,
	})
end

function CartCameraRuntimeState.Create(): Snapshot
	return freezeSnapshot(false, 0, false, false, false)
end

function CartCameraRuntimeState.CanActivate(context: ActivationContext): boolean
	return context.ControllerStarted
		and context.PlayerActive
		and context.AuthorizedDriver
		and context.CartAvailable
		and context.CartReady
		and context.TargetValid
		and context.CameraAvailable
		and context.CameraInputApplicable
end

function CartCameraRuntimeState.IsCartReady(
	assemblyState: unknown,
	cameraAlreadyActive: boolean,
	resetSuspended: boolean
): boolean
	return assemblyState == "Valid"
		or (assemblyState == "Preparing" and cameraAlreadyActive and resetSuspended)
end

function CartCameraRuntimeState.Activate(snapshot: Snapshot): Snapshot
	if snapshot.Active then
		return snapshot
	end

	return freezeSnapshot(true, snapshot.ContextRevision + 1, false, true, false)
end

function CartCameraRuntimeState.Deactivate(snapshot: Snapshot): Snapshot
	if
		not snapshot.Active
		and not snapshot.ResetSuspended
		and not snapshot.ResyncRequired
		and not snapshot.ManualInputActive
	then
		return snapshot
	end

	return freezeSnapshot(false, snapshot.ContextRevision + 1, false, false, false)
end

function CartCameraRuntimeState.IsCurrent(snapshot: Snapshot, expectedRevision: number): boolean
	return snapshot.ContextRevision == expectedRevision
end

function CartCameraRuntimeState.SetResetSuspended(
	snapshot: Snapshot,
	resetSuspended: boolean
): Snapshot
	if snapshot.ResetSuspended == resetSuspended then
		return snapshot
	end

	return freezeSnapshot(snapshot.Active, snapshot.ContextRevision, resetSuspended, true, false)
end

function CartCameraRuntimeState.ConsumeResync(snapshot: Snapshot): Snapshot
	if not snapshot.ResyncRequired then
		return snapshot
	end

	return freezeSnapshot(
		snapshot.Active,
		snapshot.ContextRevision,
		snapshot.ResetSuspended,
		false,
		snapshot.ManualInputActive
	)
end

function CartCameraRuntimeState.SetManualInputActive(
	snapshot: Snapshot,
	manualInputActive: boolean
): Snapshot
	local nextActive = manualInputActive and snapshot.Active and not snapshot.ResetSuspended

	if snapshot.ManualInputActive == nextActive then
		return snapshot
	end

	return freezeSnapshot(
		snapshot.Active,
		snapshot.ContextRevision,
		snapshot.ResetSuspended,
		snapshot.ResyncRequired,
		nextActive
	)
end

function CartCameraRuntimeState.ClearManualInput(snapshot: Snapshot): Snapshot
	return CartCameraRuntimeState.SetManualInputActive(snapshot, false)
end

return table.freeze(CartCameraRuntimeState)
