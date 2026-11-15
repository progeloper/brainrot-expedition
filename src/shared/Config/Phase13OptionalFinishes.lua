--!strict
-- Asset data only. Does not grant ownership, activate sales or modify any model.
-- Merge through the current appearance system after explicit role mapping.
-- A Roblox platform ID is deliberately absent until verified.
return table.freeze({
    SchemaVersion = 1,
    Version = "P13_ASSET_CLOSEOUT_V1",
    Finishes = table.freeze({
        FIN_PRISM = table.freeze({
            Name = "Prism weapon finish",
            Category = "Weapon",
            TargetRobux = 79,
            PaidEnabled = false,
            DefaultSelected = false,
            MaterialPolicy = "PreserveExistingMatteMaterialsAndSurfaceDetail",
            Palette = table.freeze({
                Primary = Color3.fromRGB(48, 39, 84),
                Secondary = Color3.fromRGB(55, 202, 218),
                EdgeBand = Color3.fromRGB(166, 160, 229),
                Accent1 = Color3.fromRGB(219, 80, 199),
                Accent2 = Color3.fromRGB(193, 232, 86),
                Hardware = Color3.fromRGB(32, 42, 58),
            }),
        }),
        FIN_GLACIER = table.freeze({
            Name = "Glacier cart finish",
            Category = "Cart",
            TargetRobux = 149,
            PaidEnabled = false,
            DefaultSelected = false,
            MaterialPolicy = "PreserveExistingMatteMaterialsAndSurfaceDetail",
            Palette = table.freeze({
                Primary = Color3.fromRGB(169, 214, 232),
                Secondary = Color3.fromRGB(82, 139, 177),
                EdgeBand = Color3.fromRGB(232, 245, 250),
                Accent1 = Color3.fromRGB(104, 197, 215),
                Accent2 = Color3.fromRGB(104, 125, 188),
                Hardware = Color3.fromRGB(41, 68, 89),
            }),
        }),
        FIN_AURORA = table.freeze({
            Name = "Aurora base finish",
            Category = "Base",
            TargetRobux = 199,
            PaidEnabled = false,
            DefaultSelected = false,
            MaterialPolicy = "PreserveExistingMatteMaterialsAndSurfaceDetail",
            Palette = table.freeze({
                Primary = Color3.fromRGB(32, 48, 71),
                Secondary = Color3.fromRGB(39, 140, 145),
                EdgeBand = Color3.fromRGB(133, 212, 196),
                Accent1 = Color3.fromRGB(137, 114, 198),
                Accent2 = Color3.fromRGB(204, 114, 170),
                Hardware = Color3.fromRGB(23, 39, 55),
            }),
        }),
        FIN_SINGULARITY = table.freeze({
            Name = "Singularity rift finish",
            Category = "Rift",
            TargetRobux = 199,
            PaidEnabled = false,
            DefaultSelected = false,
            MaterialPolicy = "PreserveExistingMatteMaterialsAndSurfaceDetail",
            Palette = table.freeze({
                Void = Color3.fromRGB(11, 7, 26),
                Rim = Color3.fromRGB(129, 69, 235),
                Highlight = Color3.fromRGB(236, 227, 255),
            }),
            TextureSource = "optional_finishes/textures/Singularity_Rift_RGBA.png",
            UploadedDecalAssetId = 120748659537301,
            TextureAssetId = "rbxassetid://85100458814418",
            -- Upload succeeded; native loaded dimensions and rendered acceptance are still pending.
            ImportedDimensionsVerified = true,
            TextureWidth = 1024,
            TextureHeight = 1024,
            ReadyForRuntime = false, -- actual rendered acceptance remains open; DEV preview is separate
        }),
    }),
})
