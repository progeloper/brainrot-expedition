--!strict

-- The established controls were previously registered in individual adapters.
-- Keep their bindings here for conflict checks, including mounted aiming.
return table.freeze({
	Fire = table.freeze({ Keyboard = Enum.KeyCode.G, Gamepad = Enum.KeyCode.ButtonR2 }),
	-- Drive-and-Hunt only: a second fire key while driving (jump is blocked in the cart). With Playtest
	-- Fixes 2 JumpHopOut on, Space is Jump (= HOP OUT) in the cart and this binding is not used.
	FireWhileDriving = table.freeze({ Keyboard = Enum.KeyCode.Space }),
	-- Playtest Fixes 2 (InputUnstick): HUD buttons are not pad-selectable, so the two HUD windows
	-- get D-pad shortcuts (keyboard B / I already open them).
	HudBrainrots = table.freeze({ Keyboard = Enum.KeyCode.B, Gamepad = Enum.KeyCode.DPadLeft }),
	HudInventory = table.freeze({ Keyboard = Enum.KeyCode.I, Gamepad = Enum.KeyCode.DPadRight }),
	Brake = table.freeze({ Keyboard = Enum.KeyCode.S, Gamepad = Enum.KeyCode.ButtonL2 }),
	ManageTeam = table.freeze({ Keyboard = Enum.KeyCode.T, Gamepad = Enum.KeyCode.ButtonY }),
	Interact = table.freeze({ Keyboard = Enum.KeyCode.E, Gamepad = Enum.KeyCode.ButtonX }),
	Burst = table.freeze({
		Name = "Burst",
		Keyboard = Enum.KeyCode.F,
		Gamepad = Enum.KeyCode.ButtonL3,
	}),
	Aim = table.freeze({ Mouse = Enum.UserInputType.MouseButton2, Gamepad = Enum.KeyCode.ButtonL1 }),
	-- Drive-and-Hunt switch button (HOP OUT / CART / LOAD & GO). F and gamepad Y were already taken.
	Switch = table.freeze({
		Name = "DriveAndHuntSwitch",
		Keyboard = Enum.KeyCode.C,
		Gamepad = Enum.KeyCode.DPadUp,
	}),
})
