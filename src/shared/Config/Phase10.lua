--!strict
-- Approved Main rollout plus the existing Development path; no economy/catalog changes.
local Environment = require(script.Parent.Environment)
return table.freeze({
 Enabled = Environment.MainGameplayEnabled or Environment.Name == "Development",
 DazeSeconds = 3,
 ProtectionSeconds = 5,
 CargoProtectionSeconds = 5,
 BeginnerSeconds = 900,
 SameVictimSeconds = 60,
 FreshCatchGraceSeconds = 0,
 LooseReactionSeconds = 0,
 LooseExpirySeconds = 0, -- No deletion expiry.
 OrdinaryLimit = 42,
 StuckSeconds = 5,
 ProgressStuds = 1,
 SampleSeconds = 0.1,
 RetrySeconds = 1,
 SafetySkin = 0.15,
 DropCandidates = 8,
 DropRadius = 8,
 CountdownScale = 1.1,
 CountdownRed = Color3.fromRGB(255,64,64),
 CountdownBlue = Color3.fromRGB(64,160,255),
 CountdownGreen = Color3.fromRGB(80,255,100),
 FilmColor = Color3.fromRGB(150,220,255),
 FilmTransparency = 0.72,
 ZeroHoldSeconds = 0.25,
 ZeroFadeSeconds = 0.15,
})
