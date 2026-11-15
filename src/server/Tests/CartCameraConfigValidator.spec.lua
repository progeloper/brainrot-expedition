--!strict

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local CartCamera = require(ReplicatedStorage.Shared.Config.CartCamera)
	local CartCameraConfigValidator =
		require(ReplicatedStorage.Shared.Validation.CartCameraConfigValidator)

	local function cloneConfig(): any
		local config = table.clone(CartCamera)

		config.Development = table.clone(CartCamera.Development)
		config.Obstruction = table.clone(CartCamera.Obstruction)

		return config
	end

	describe("CartCameraConfigValidator", function()
		it("preserves the five locked PC camera values", function()
			expect(CartCamera.Distance).to.equal(28)
			expect(CartCamera.HeightOffset).to.equal(9)
			expect(CartCamera.PCSensitivity).to.equal(0.8)
			expect(CartCamera.AutoRecenterDelay).to.equal(1.25)
			expect(CartCamera.AutoRecenterSpeed).to.equal(3.5)
		end)

		it("preserves the locked gamepad camera sensitivity", function()
			expect(CartCamera.GamepadSensitivity).to.equal(0.65)
		end)

		it("keeps non-locked tuning in a distinct Development section", function()
			expect(type(CartCamera.Development)).to.equal("table")
			expect(CartCamera.Development.DefaultPitch).to.equal(0)
			expect(CartCamera.Development.PositionResponsiveness).to.equal(10)
			expect(CartCamera.Development.RotationResponsiveness).to.equal(12)
			expect(CartCamera.Development.MouseRadiansPerPixel).to.equal(0.003)
			expect(CartCamera.Obstruction.QueryRadius).to.equal(0.5)
			expect(CartCamera.Obstruction.SurfaceBuffer).to.equal(0.25)
			expect(CartCamera.Obstruction.MinimumDistance).to.equal(6)
			expect(CartCamera.Obstruction.OutwardRecoverySpeed).to.equal(1 / 0.15)
			expect(CartCamera.Obstruction.DistanceTolerance).to.equal(0.05)
		end)

		it("accepts the configured PC camera profile", function()
			local result = CartCameraConfigValidator.Validate(CartCamera)

			expect(result.IsValid).to.equal(true)
			expect(#result.Errors).to.equal(0)
		end)

		it("rejects every missing required locked value", function()
			for _, field in
				{
					"Distance",
					"HeightOffset",
					"PCSensitivity",
					"GamepadSensitivity",
					"AutoRecenterDelay",
					"AutoRecenterSpeed",
				}
			do
				local config = cloneConfig()

				config[field] = nil

				local result = CartCameraConfigValidator.Validate(config)

				expect(result.IsValid).to.equal(false)
				expect(#result.Errors > 0).to.equal(true)
			end
		end)

		it("rejects every missing required Development value", function()
			for _, field in
				{
					"MinimumPitch",
					"MaximumPitch",
					"DefaultPitch",
					"PositionResponsiveness",
					"RotationResponsiveness",
					"MouseRadiansPerPixel",
					"ManualInputThreshold",
				}
			do
				local config = cloneConfig()

				config.Development[field] = nil

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("requires a Development tuning table", function()
			local missing = cloneConfig()

			missing.Development = nil
			expect(CartCameraConfigValidator.Validate(missing).IsValid).to.equal(false)

			local malformed = cloneConfig()

			malformed.Development = "tuning"
			expect(CartCameraConfigValidator.Validate(malformed).IsValid).to.equal(false)
		end)

		it("rejects non-numeric, NaN, and infinite values", function()
			for field, value in
				{
					Distance = "28",
					HeightOffset = true,
					PCSensitivity = 0 / 0,
					GamepadSensitivity = "0.65",
					AutoRecenterDelay = math.huge,
					AutoRecenterSpeed = -math.huge,
				}
			do
				local config = cloneConfig()

				config[field] = value

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("rejects unsafe locked-value ranges", function()
			for field, value in
				{
					Distance = 0,
					HeightOffset = 0,
					PCSensitivity = 0,
					GamepadSensitivity = 0,
					AutoRecenterDelay = -0.01,
					AutoRecenterSpeed = 0,
				}
			do
				local config = cloneConfig()

				config[field] = value

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("requires ordered pitch bounds with the default inside them", function()
			local reversed = cloneConfig()

			reversed.Development.MinimumPitch = math.rad(35)
			reversed.Development.MaximumPitch = math.rad(-20)
			expect(CartCameraConfigValidator.Validate(reversed).IsValid).to.equal(false)

			local outside = cloneConfig()

			outside.Development.DefaultPitch = math.rad(60)
			expect(CartCameraConfigValidator.Validate(outside).IsValid).to.equal(false)
		end)

		it("rejects invalid Development response and input values", function()
			for field, value in
				{
					MouseRadiansPerPixel = 0,
					ManualInputThreshold = -1,
					PositionResponsiveness = 0,
					RotationResponsiveness = -1,
				}
			do
				local config = cloneConfig()

				config.Development[field] = value

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("rejects every missing obstruction value", function()
			for _, field in
				{
					"Enabled",
					"QueryRadius",
					"SurfaceBuffer",
					"MinimumDistance",
					"OutwardRecoverySpeed",
					"DistanceTolerance",
				}
			do
				local config = cloneConfig()

				config.Obstruction[field] = nil

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("requires an obstruction configuration table", function()
			local missing = cloneConfig()

			missing.Obstruction = nil
			expect(CartCameraConfigValidator.Validate(missing).IsValid).to.equal(false)

			local malformed = cloneConfig()

			malformed.Obstruction = "enabled"
			expect(CartCameraConfigValidator.Validate(malformed).IsValid).to.equal(false)
		end)

		it("accepts an explicitly disabled but otherwise valid obstruction profile", function()
			local config = cloneConfig()

			config.Obstruction.Enabled = false
			expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(true)
		end)

		it("rejects malformed obstruction values", function()
			for field, value in
				{
					Enabled = "yes",
					QueryRadius = 0 / 0,
					SurfaceBuffer = -0.01,
					MinimumDistance = math.huge,
					OutwardRecoverySpeed = 0,
					DistanceTolerance = -0.01,
				}
			do
				local config = cloneConfig()

				config.Obstruction[field] = value

				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)

		it("validates obstruction distance relationships", function()
			local tooFar = cloneConfig()

			tooFar.Obstruction.MinimumDistance = CartCamera.Distance + 1
			expect(CartCameraConfigValidator.Validate(tooFar).IsValid).to.equal(false)

			local insideQueryVolume = cloneConfig()

			insideQueryVolume.Obstruction.MinimumDistance =
				insideQueryVolume.Obstruction.QueryRadius
			expect(CartCameraConfigValidator.Validate(insideQueryVolume).IsValid).to.equal(false)

			local excessiveTolerance = cloneConfig()

			excessiveTolerance.Obstruction.DistanceTolerance =
				excessiveTolerance.Obstruction.MinimumDistance
			expect(CartCameraConfigValidator.Validate(excessiveTolerance).IsValid).to.equal(false)
		end)

		it("rejects obstruction values above central physics-safety limits", function()
			for field, value in
				{
					QueryRadius = 9,
					SurfaceBuffer = 9,
					OutwardRecoverySpeed = 101,
					DistanceTolerance = 3,
				}
			do
				local config = cloneConfig()

				config.Obstruction[field] = value
				expect(CartCameraConfigValidator.Validate(config).IsValid).to.equal(false)
			end
		end)
	end)
end
