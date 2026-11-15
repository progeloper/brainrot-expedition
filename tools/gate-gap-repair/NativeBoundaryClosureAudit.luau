-- Read-only native geometry QA. This module never creates, moves, deletes, tags,
-- starts services, changes profiles, or edits Source. Run in Edit or Server.
-- Usage: local qa = assert(loadstring(fileContents))(); return qa.Run({})
-- Optional: sections = {perimeter=true,corners=false,flanks=false,cart=false,closures=false}
-- Optional: heights = {...}; perimeterSpacing = 0.5; loadedCartSize = Vector3.new(...).
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local input = HttpService:JSONDecode([==[{"perimeters":[{"region":"Arctic","axis":"X","fixed":-654.0,"inward":1,"first":229.0,"last":709.0},{"region":"Arctic","axis":"X","fixed":-474.0,"inward":-1,"first":469.0,"last":709.0},{"region":"Arctic","axis":"X","fixed":-294.0,"inward":-1,"first":229.0,"last":469.0},{"region":"Arctic","axis":"Z","fixed":229.0,"inward":1,"first":-654.0,"last":-294.0},{"region":"Arctic","axis":"Z","fixed":469.0,"inward":-1,"first":-474.0,"last":-294.0},{"region":"Arctic","axis":"Z","fixed":709.0,"inward":-1,"first":-654.0,"last":-474.0},{"region":"Beach","axis":"X","fixed":-654.0,"inward":1,"first":-747.0,"last":-267.0},{"region":"Beach","axis":"X","fixed":-474.0,"inward":-1,"first":-507.0,"last":-267.0},{"region":"Beach","axis":"X","fixed":202.0,"inward":-1,"first":-747.0,"last":-507.0},{"region":"Beach","axis":"Z","fixed":-747.0,"inward":1,"first":-654.0,"last":202.0},{"region":"Beach","axis":"Z","fixed":-507.0,"inward":-1,"first":-474.0,"last":202.0},{"region":"Beach","axis":"Z","fixed":-267.0,"inward":-1,"first":-654.0,"last":-474.0},{"region":"Camp","axis":"X","fixed":-294.0,"inward":1,"first":-267.0,"last":229.0},{"region":"Camp","axis":"X","fixed":202.0,"inward":-1,"first":-267.0,"last":229.0},{"region":"Camp","axis":"Z","fixed":-267.0,"inward":1,"first":-294.0,"last":202.0},{"region":"Camp","axis":"Z","fixed":229.0,"inward":-1,"first":-294.0,"last":202.0},{"region":"Forest","axis":"X","fixed":-654.0,"inward":1,"first":-267.0,"last":229.0},{"region":"Forest","axis":"X","fixed":-474.0,"inward":1,"first":-507.0,"last":-267.0},{"region":"Forest","axis":"X","fixed":-294.0,"inward":-1,"first":-267.0,"last":229.0},{"region":"Forest","axis":"X","fixed":202.0,"inward":-1,"first":-507.0,"last":-267.0},{"region":"Forest","axis":"Z","fixed":-507.0,"inward":1,"first":-474.0,"last":202.0},{"region":"Forest","axis":"Z","fixed":-267.0,"inward":-1,"first":-294.0,"last":202.0},{"region":"Forest","axis":"Z","fixed":-267.0,"inward":1,"first":-654.0,"last":-474.0},{"region":"Forest","axis":"Z","fixed":229.0,"inward":-1,"first":-654.0,"last":-294.0},{"region":"Glitch Zone","axis":"X","fixed":202.0,"inward":1,"first":229.0,"last":709.0},{"region":"Glitch Zone","axis":"X","fixed":562.0,"inward":-1,"first":229.0,"last":709.0},{"region":"Glitch Zone","axis":"Z","fixed":229.0,"inward":1,"first":202.0,"last":562.0},{"region":"Glitch Zone","axis":"Z","fixed":709.0,"inward":-1,"first":202.0,"last":562.0},{"region":"Jungle","axis":"X","fixed":202.0,"inward":1,"first":-267.0,"last":229.0},{"region":"Jungle","axis":"X","fixed":382.0,"inward":1,"first":-507.0,"last":-267.0},{"region":"Jungle","axis":"X","fixed":562.0,"inward":-1,"first":-507.0,"last":229.0},{"region":"Jungle","axis":"Z","fixed":-507.0,"inward":1,"first":382.0,"last":562.0},{"region":"Jungle","axis":"Z","fixed":-267.0,"inward":1,"first":202.0,"last":382.0},{"region":"Jungle","axis":"Z","fixed":229.0,"inward":-1,"first":202.0,"last":562.0},{"region":"Swamp","axis":"X","fixed":202.0,"inward":1,"first":-747.0,"last":-267.0},{"region":"Swamp","axis":"X","fixed":382.0,"inward":-1,"first":-507.0,"last":-267.0},{"region":"Swamp","axis":"X","fixed":562.0,"inward":-1,"first":-747.0,"last":-507.0},{"region":"Swamp","axis":"Z","fixed":-747.0,"inward":1,"first":202.0,"last":562.0},{"region":"Swamp","axis":"Z","fixed":-507.0,"inward":-1,"first":382.0,"last":562.0},{"region":"Swamp","axis":"Z","fixed":-267.0,"inward":-1,"first":202.0,"last":382.0},{"region":"Volcano","axis":"X","fixed":-474.0,"inward":1,"first":469.0,"last":709.0},{"region":"Volcano","axis":"X","fixed":-294.0,"inward":1,"first":229.0,"last":469.0},{"region":"Volcano","axis":"X","fixed":202.0,"inward":-1,"first":229.0,"last":709.0},{"region":"Volcano","axis":"Z","fixed":229.0,"inward":1,"first":-294.0,"last":202.0},{"region":"Volcano","axis":"Z","fixed":469.0,"inward":1,"first":-474.0,"last":-294.0},{"region":"Volcano","axis":"Z","fixed":709.0,"inward":-1,"first":-474.0,"last":202.0}],"gates":[{"gate":"Volcano","axis":"Z","fixed":229,"center":-280.2055969238281,"actualStructuralOpening":[-298.2056198120117,-244.05887603759766],"nativeThresholdCF":[229,13.050000190734863,-280.2055969238281,0,0,-1,0,1,0,1,0,0],"closureTop":84.86666870117188},{"gate":"Jungle","axis":"X","fixed":202,"center":-244.233642578125,"actualStructuralOpening":[-262.2336437702179,-217.05887603759766],"nativeThresholdCF":[-244.233642578125,13.050000190734863,202,-1,0,0,0,1,0,0,0,-1],"closureTop":96.98333358764648},{"gate":"Beach","axis":"Z","fixed":-507,"center":-384,"actualStructuralOpening":[-402.0,-365.99999237060547],"nativeThresholdCF":[-507,13.050000190734863,-384,0,0,1,0,1,0,-1,0,0],"closureTop":84.86666870117188},{"gate":"Swamp","axis":"X","fixed":202,"center":-387,"actualStructuralOpening":[-405.0,-369.0],"nativeThresholdCF":[-387,13.050000190734863,202,-1,0,0,0,1,0,0,0,-1],"closureTop":84.86666870117188},{"gate":"GlitchZone","axis":"Z","fixed":229,"center":292,"actualStructuralOpening":[274.0,310.0],"nativeThresholdCF":[229,13.050000190734863,292,0,0,-1,0,1,0,1,0,0],"closureTop":96.98333358764648},{"gate":"Arctic","axis":"Z","fixed":229,"center":-564,"actualStructuralOpening":[-582.0,-546.0000076293945],"nativeThresholdCF":[229,13.050000190734863,-564,0,0,-1,0,1,0,1,0,0],"closureTop":84.86666870117188}],"free":[["Z",-267,-291.2336437702179,-251.233642578125],["X",-294,-251,-219]],"proposals":[{"id":"Volcano_Jamb_Negative","kind":"GateJamb","worldPosition":[229,41.93333435058594,-295.3306083679199],"worldSize":[4,85.86666870117188,6.250022888183594]},{"id":"Volcano_Jamb_Positive","kind":"GateJamb","worldPosition":[229,41.93333435058594,-256.0072364807129],"worldSize":[4,85.86666870117188,24.39672088623047]},{"id":"Jungle_Jamb_Negative","kind":"GateJamb","worldPosition":[-259.35864317417145,47.99166679382324,202],"worldSize":[6.2500011920928955,97.98333358764648,4]},{"id":"Jungle_Jamb_Positive","kind":"GateJamb","worldPosition":[-224.52125930786133,47.99166679382324,202],"worldSize":[15.424766540527344,97.98333358764648,4]},{"id":"Beach_Jamb_Negative","kind":"GateJamb","worldPosition":[-507,41.93333435058594,-399.125],"worldSize":[4,85.86666870117188,6.25]},{"id":"Beach_Jamb_Positive","kind":"GateJamb","worldPosition":[-507,41.93333435058594,-368.87499618530273],"worldSize":[4,85.86666870117188,6.250007629394531]},{"id":"Swamp_Jamb_Negative","kind":"GateJamb","worldPosition":[-402.125,41.93333435058594,202],"worldSize":[6.25,85.86666870117188,4]},{"id":"Swamp_Jamb_Positive","kind":"GateJamb","worldPosition":[-371.875,41.93333435058594,202],"worldSize":[6.25,85.86666870117188,4]},{"id":"GlitchZone_Jamb_Negative","kind":"GateJamb","worldPosition":[229,47.99166679382324,276.875],"worldSize":[4,97.98333358764648,6.25]},{"id":"GlitchZone_Jamb_Positive","kind":"GateJamb","worldPosition":[229,47.99166679382324,307.125],"worldSize":[4,97.98333358764648,6.25]},{"id":"Arctic_Jamb_Negative","kind":"GateJamb","worldPosition":[229,41.93333435058594,-579.125],"worldSize":[4,85.86666870117188,6.25]},{"id":"Arctic_Jamb_Positive","kind":"GateJamb","worldPosition":[229,41.93333435058594,-548.8750038146973],"worldSize":[4,85.86666870117188,6.249992370605469]},{"id":"VolcanoCornerReturn_CampForest","kind":"OrthogonalReturn","worldPosition":[204.0,41.93333435058594,-294.10279846191406],"worldSize":[46.5,85.86666870117188,3.794403076171875]},{"id":"VolcanoCornerReturn_ArcticVolcano","kind":"OrthogonalReturn","worldPosition":[254.0,41.93333435058594,-294.10279846191406],"worldSize":[46.5,85.86666870117188,3.794403076171875]},{"id":"JungleCornerReturn_CampForest","kind":"OrthogonalReturn","worldPosition":[-269.6168212890625,47.99166679382324,168.0],"worldSize":[26.766357421875,97.98333358764648,28.5]},{"id":"JungleCornerReturn_SwampJungle","kind":"OrthogonalReturn","worldPosition":[-269.6168212890625,47.99166679382324,242.47780060768127],"worldSize":[26.766357421875,97.98333358764648,15.544398784637451]},{"id":"Volcano_UpperBridge","kind":"UpperBridge","worldPosition":[229,51.458334350585936,-280.2055969238281],"worldSize":[4,66.81666870117188,24]},{"id":"Jungle_UpperBridge","kind":"UpperBridge","worldPosition":[-244.233642578125,57.51666679382324,202],"worldSize":[24,78.93333358764649,4]},{"id":"Beach_UpperBridge","kind":"UpperBridge","worldPosition":[-507,51.458334350585936,-384],"worldSize":[4,66.81666870117188,24]},{"id":"Swamp_UpperBridge","kind":"UpperBridge","worldPosition":[-387,51.458334350585936,202],"worldSize":[24,66.81666870117188,4]},{"id":"GlitchZone_UpperBridge","kind":"UpperBridge","worldPosition":[229,57.51666679382324,292],"worldSize":[4,78.93333358764649,24]},{"id":"Arctic_UpperBridge","kind":"UpperBridge","worldPosition":[229,51.458334350585936,-564],"worldSize":[4,66.81666870117188,24]}],"existingProxies":["Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_01.EV2_Run_02_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_11_Cliff_01.EV2_Run_11_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_09_Cliff_01.EV2_Run_09_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_04_Cliff_01.EV2_Run_04_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_01.EV2_Run_01_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_22_Cliff_03.EV2_Run_22_Cliff_03_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_16_Cliff_02.EV2_Run_16_Cliff_02_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_12_Cliff_02.EV2_Run_12_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_02.EV2_Run_02_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_03_Cliff_01.EV2_Run_03_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_13_Cliff_01.EV2_Run_13_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_21_Cliff_03.EV2_Run_21_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_12_Cliff_01.EV2_Run_12_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_Arctic_Header_01.Gate_Arctic_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_14_Cliff_03.EV2_Run_14_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_GlitchZone_Header_01.Gate_GlitchZone_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_06.EV2_Run_01_Cliff_06_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_03_Cliff_03.EV2_Run_03_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_18_Cliff_04.EV2_Run_18_Cliff_04_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_06_Cliff_01.EV2_Run_06_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.X_Camp_Exterior_WN_R10_0_Header_01.X_Camp_Exterior_WN_R10_0_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_04_Cliff_05.EV2_Run_04_Cliff_05_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_07_Cliff_02.EV2_Run_07_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_10_Cliff_02.EV2_Run_10_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_04_Cliff_02.EV2_Run_04_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_20_Cliff_01.EV2_Run_20_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_05.EV2_Run_02_Cliff_05_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_19_Cliff_01.EV2_Run_19_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_03_Cliff_04.EV2_Run_03_Cliff_04_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_14_Cliff_04.EV2_Run_14_Cliff_04_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_03.EV2_Run_02_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_20_Cliff_02.EV2_Run_20_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_04.EV2_Run_01_Cliff_04_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_Volcano_Header_01.Gate_Volcano_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_22_Cliff_01.EV2_Run_22_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_19_Cliff_02.EV2_Run_19_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_Swamp_Header_01.Gate_Swamp_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_04_Cliff_04.EV2_Run_04_Cliff_04_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_03_Cliff_05.EV2_Run_03_Cliff_05_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_17_Cliff_02.EV2_Run_17_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_02.EV2_Run_01_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_05.EV2_Run_01_Cliff_05_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_15_Cliff_01.EV2_Run_15_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_14_Cliff_05.EV2_Run_14_Cliff_05_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_06.EV2_Run_02_Cliff_06_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_10_Cliff_01.EV2_Run_10_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_05_Cliff_01.EV2_Run_05_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_21_Cliff_01.EV2_Run_21_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_20_Cliff_03.EV2_Run_20_Cliff_03_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_16_Cliff_01.EV2_Run_16_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_Beach_Header_01.Gate_Beach_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_11_Cliff_03.EV2_Run_11_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_04_Cliff_03.EV2_Run_04_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_07_Cliff_01.EV2_Run_07_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_18_Cliff_03.EV2_Run_18_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_17_Cliff_01.EV2_Run_17_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_15_Cliff_02.EV2_Run_15_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_08_Cliff_01.EV2_Run_08_Cliff_01_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_02_Cliff_04.EV2_Run_02_Cliff_04_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.Gate_Jungle_Header_01.Gate_Jungle_Header_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_21_Cliff_02.EV2_Run_21_Cliff_02_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_03_Cliff_02.EV2_Run_03_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_01_Cliff_03.EV2_Run_01_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_11_Cliff_02.EV2_Run_11_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_18_Cliff_02.EV2_Run_18_Cliff_02_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_17_Cliff_03.EV2_Run_17_Cliff_03_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_22_Cliff_02.EV2_Run_22_Cliff_02_CliffRun_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_18_Cliff_01.EV2_Run_18_Cliff_01_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_14_Cliff_02.EV2_Run_14_Cliff_02_GateLintel_Collider_1","Workspace.MapBlockout.EnvironmentArt_V2.EV2_Run_14_Cliff_01.EV2_Run_14_Cliff_01_GateLintel_Collider_1"],"floorRectangles":[{"region":"Jungle","x0":-507.0,"x1":-267.0,"z0":382.0,"z1":562.0},{"region":"Jungle","x0":-267.0,"x1":229.0,"z0":382.0,"z1":562.0},{"region":"Jungle","x0":-267.0,"x1":229.0,"z0":202.0,"z1":382.0},{"region":"Camp","x0":-267.0,"x1":229.0,"z0":-294.0,"z1":202.0},{"region":"Glitch Zone","x0":229.0,"x1":469.0,"z0":382.0,"z1":562.0},{"region":"Glitch Zone","x0":469.0,"x1":709.0,"z0":202.0,"z1":382.0},{"region":"Glitch Zone","x0":229.0,"x1":469.0,"z0":202.0,"z1":382.0},{"region":"Glitch Zone","x0":469.0,"x1":709.0,"z0":382.0,"z1":562.0},{"region":"Beach","x0":-747.0,"x1":-507.0,"z0":-294.0,"z1":202.0},{"region":"Beach","x0":-507.0,"x1":-267.0,"z0":-654.0,"z1":-474.0},{"region":"Beach","x0":-747.0,"x1":-507.0,"z0":-474.0,"z1":-294.0},{"region":"Beach","x0":-747.0,"x1":-507.0,"z0":-654.0,"z1":-474.0},{"region":"Arctic","x0":229.0,"x1":469.0,"z0":-654.0,"z1":-474.0},{"region":"Arctic","x0":469.0,"x1":709.0,"z0":-654.0,"z1":-474.0},{"region":"Arctic","x0":229.0,"x1":469.0,"z0":-474.0,"z1":-294.0},{"region":"Volcano","x0":469.0,"x1":709.0,"z0":-294.0,"z1":202.0},{"region":"Volcano","x0":229.0,"x1":469.0,"z0":-294.0,"z1":202.0},{"region":"Volcano","x0":469.0,"x1":709.0,"z0":-474.0,"z1":-294.0},{"region":"Swamp","x0":-747.0,"x1":-507.0,"z0":202.0,"z1":382.0},{"region":"Swamp","x0":-747.0,"x1":-507.0,"z0":382.0,"z1":562.0},{"region":"Swamp","x0":-507.0,"x1":-267.0,"z0":202.0,"z1":382.0},{"region":"Forest","x0":-267.0,"x1":229.0,"z0":-654.0,"z1":-474.0},{"region":"Forest","x0":-507.0,"x1":-267.0,"z0":-294.0,"z1":202.0},{"region":"Forest","x0":-267.0,"x1":229.0,"z0":-474.0,"z1":-294.0},{"region":"Forest","x0":-507.0,"x1":-267.0,"z0":-474.0,"z1":-294.0}]}]==])
local EPS = 0.001

local function resolve(path)
 local current = game
 for name in string.gmatch(path,"[^.]+") do
  current = current:FindFirstChild(name)
  if not current then return nil end
 end
 return current
end
local function point(axis,fixed,along,y)
 if axis=="X" then return Vector3.new(along,y,fixed) end
 return Vector3.new(fixed,y,along)
end
local function normal(axis)
 return axis=="X" and Vector3.new(0,0,1) or Vector3.new(1,0,0)
end
local function alongDirection(axis)
 return axis=="X" and Vector3.new(1,0,0) or Vector3.new(0,0,1)
end
local function asCF(row)
 return CFrame.new(table.unpack(row))
end
local function vec(row)
 return Vector3.new(row[1],row[2],row[3])
end
local function partBounds(part)
 local cf,s=part.CFrame,part.Size
 local r,u,b=cf.RightVector,cf.UpVector,-cf.LookVector
 local half=Vector3.new(math.abs(r.X)*s.X+math.abs(u.X)*s.Y+math.abs(b.X)*s.Z,
  math.abs(r.Y)*s.X+math.abs(u.Y)*s.Y+math.abs(b.Y)*s.Z,
  math.abs(r.Z)*s.X+math.abs(u.Z)*s.Y+math.abs(b.Z)*s.Z)/2
 return part.Position-half,part.Position+half
end
local function allowed(axis,fixed,along,y)
 for _,g in input.gates do
  if axis==g.axis and math.abs(fixed-g.fixed)<EPS and math.abs(along-g.center)<12+EPS and y<18.05-EPS then
   return "Paid:"..g.gate
  end
 end
 for _,f in input.free do
  if axis==f[1] and math.abs(fixed-f[2])<EPS and along>=f[3]-EPS and along<=f[4]+EPS then return "FreeForest" end
 end
 return nil
end
local function segmentUsesAllowed(a,b)
 -- Waive only a geometric intersection with one of the named portals.
 -- Every other corner diagonal is required to hit an actual collider.
 for _,g in input.gates do
  local da=g.axis=="X" and a.Z or a.X
  local db=g.axis=="X" and b.Z or b.X
  if math.abs(db-da)>EPS then
   local t=(g.fixed-da)/(db-da)
   if t>=0 and t<=1 then
    local hit=a+(b-a)*t
    local al=g.axis=="X" and hit.X or hit.Z
    if allowed(g.axis,g.fixed,al,hit.Y) then return true end
   end
  end
 end
 for _,f in input.free do
  local da=f[1]=="X" and a.Z or a.X
  local db=f[1]=="X" and b.Z or b.X
  if math.abs(db-da)>EPS then
   local t=(f[2]-da)/(db-da)
   if t>=0 and t<=1 then
    local hit=a+(b-a)*t
    local al=f[1]=="X" and hit.X or hit.Z
    if allowed(f[1],f[2],al,hit.Y)=="FreeForest" then return true end
   end
  end
 end
 return false
end
local function regionContains(region,p)
 for _,r in input.floorRectangles do
  if r.region==region and p.X>r.x0+EPS and p.X<r.x1-EPS and p.Z>r.z0+EPS and p.Z<r.z1-EPS then return true end
 end
 return false
end

local function Run(options)
 options=options or {}
 local sections=options.sections or {}
 local report={passed=true,method="Native Raycast/Blockcast against anchored colliding/queryable structural Parts, original gate parts, and GateApertureClosures; no MeshPart AABBs are asserted to be solid. Raycast origins initially within/contacting exact CFrame-local native block geometry count as solid; never meshes/unions/wedges. Loaded-cart empty broad-phase overlap plus native Blockcast certifies clearance.",
  mutations=0,checks=0,failures={},failureCount=0,sections={},perimeters={},gates={},proposalCores={},
  initialPointSolidEvidence={interior=0,boundaryContact=0,examples={}},
  allowedPortalPolicy={paidCount=6,paidWidth=24,paidHeight=18,freeForestFaces=input.free},
  sampleSpacing=options.perimeterSpacing or 0.5,heights=options.heights or {1,5,12,17.99,18.2,35,70}}
 local function fail(kind,detail)
  report.passed=false;report.failureCount+=1
  if #report.failures<100 then table.insert(report.failures,{kind=kind,detail=detail}) end
 end
 local function check(condition,kind,detail)
  report.checks+=1
  if not condition then fail(kind,detail) end
 end
 local function yieldIfNeeded()
  if report.checks%4096==0 then task.wait() end
 end
 local map=Workspace:FindFirstChild("MapBlockout")
 if not map then fail("MissingMapBlockout",{});return report end
 local gates=map:FindFirstChild("ProgressionGates")
 local closures=map:FindFirstChild("GateApertureClosures")
 if not gates or not closures then fail("MissingGateOrClosureFolder",{gates=gates~=nil,closures=closures~=nil});return report end
 local proxies={}
 for _,path in input.existingProxies do
  local p=resolve(path)
  check(p and p:IsA("BasePart") and p.Anchored and p.CanCollide and p.CanQuery,"OriginalCollisionProxyMissingOrDisabled",path)
  if p and p:IsA("BasePart") then table.insert(proxies,p) end
 end
 table.insert(proxies,gates);table.insert(proxies,closures)
 local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances=proxies;rp.RespectCanCollide=true;rp.CollisionGroup="Default"
 local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances=proxies;op.RespectCanCollide=true;op.CollisionGroup="Default";op.MaxParts=0
 local crp=RaycastParams.new();crp.FilterType=Enum.RaycastFilterType.Include;crp.FilterDescendantsInstances={closures};crp.RespectCanCollide=true;crp.CollisionGroup="Default"
 local cop=OverlapParams.new();cop.FilterType=Enum.RaycastFilterType.Include;cop.FilterDescendantsInstances={closures};cop.RespectCanCollide=true;cop.CollisionGroup="Default";cop.MaxParts=0
 local colliders={}
 for _,p in closures:GetDescendants() do
  if p:IsA("BasePart") and p.CanCollide then
   table.insert(colliders,p)
   check(p.Anchored and p.CanQuery and not p.CanTouch,"UnsafeClosureColliderFlags",p:GetFullName())
   check(p:IsA("Part") and p.Shape==Enum.PartType.Block,"ClosureColliderMustHaveExactBlockGeometry",p:GetFullName())
  end
 end
 -- Raycast intentionally omits hits when an origin starts in a collider.
 -- Resolve that case only against exact native block geometry, not bounds of
 -- meshes/unions/wedges. A 1e-5 contact tolerance covers float precision at a
 -- shared face; it is far smaller than any player/cart traversable gap.
 local exactBlocks={}
 local seenBlocks={}
 local function addExactBlock(p)
  if p:IsA("Part") and p.Shape==Enum.PartType.Block and p.Anchored and p.CanCollide and p.CanQuery and not seenBlocks[p] then
   seenBlocks[p]=true;table.insert(exactBlocks,p)
  end
 end
 for _,path in input.existingProxies do local p=resolve(path);if p then addExactBlock(p) end end
 for _,p in gates:GetDescendants() do addExactBlock(p) end
 for _,p in colliders do addExactBlock(p) end
 local function blockedPointRay(a,b,params,blocks,section)
  local hit=Workspace:Raycast(a,b-a,params)
  if hit then return hit.Instance,"Raycast" end
  for _,p in blocks do
   local q=p.CFrame:PointToObjectSpace(a)
   local h=p.Size/2
   local dx,dy,dz=math.abs(q.X)-h.X,math.abs(q.Y)-h.Y,math.abs(q.Z)-h.Z
   if dx<=1e-5 and dy<=1e-5 and dz<=1e-5 then
    local mode=dx<-1e-5 and dy<-1e-5 and dz<-1e-5 and "interior" or "boundaryContact"
    report.initialPointSolidEvidence[mode]+=1
    local examples=report.initialPointSolidEvidence.examples
    if #examples<24 then table.insert(examples,{section=section,kind=mode,part=p:GetFullName(),origin={a.X,a.Y,a.Z},localPoint={q.X,q.Y,q.Z},halfSize={h.X,h.Y,h.Z}}) end
    return p,"InitialExactBlock:"..mode
   end
  end
  return nil,"NoPhysicalBlock"
 end
 report.exactInitialBlockProxyCount=#exactBlocks
 report.initialPointSolidTolerance=1e-5
 report.closureCollisionPartCount=#colliders
 check(#colliders>=22,"TooFewClosureCores",#colliders)

 if sections.perimeter~=false then
  local startChecks=report.checks
  for _,e in input.perimeters do
   local row={region=e.region,axis=e.axis,fixed=e.fixed,first=e.first,last=e.last,samples=0,allowed=0,blocked=0,missing={}}
   local sampleSet={}
   local function add(al)
    if al>=e.first-EPS and al<=e.last+EPS then sampleSet[string.format("%.6f",math.clamp(al,e.first,e.last))]=math.clamp(al,e.first,e.last) end
   end
   for al=e.first,e.last,report.sampleSpacing do add(al) end
   add(e.last);add(e.first+0.005);add(e.last-0.005)
   -- Include both sides of every primitive endpoint; this catches narrow seams
   -- that lie between regular samples. The subsequent decision is native cast.
   local originalAndNew={}
   for _,path in input.existingProxies do local p=resolve(path);if p then table.insert(originalAndNew,p) end end
   for _,p in colliders do table.insert(originalAndNew,p) end
   for _,p in originalAndNew do
    local lo,hi=partBounds(p)
    local f0=e.axis=="X" and lo.Z or lo.X
    local f1=e.axis=="X" and hi.Z or hi.X
    if e.fixed>=f0-EPS and e.fixed<=f1+EPS then
     local a0=e.axis=="X" and lo.X or lo.Z
     local a1=e.axis=="X" and hi.X or hi.Z
     for _,v in {a0,a1} do add(v-0.005);add(v+0.005) end
    end
   end
   local sorted={};for _,al in sampleSet do table.insert(sorted,al) end;table.sort(sorted)
   local n=normal(e.axis)
   for _,height in report.heights do
    for _,al in sorted do
     row.samples+=1
     if allowed(e.axis,e.fixed,al,height) then row.allowed+=1 else
      local p=point(e.axis,e.fixed,al,height)
      local forward,forwardKind=blockedPointRay(p-n*80,p+n*80,rp,exactBlocks,"perimeter")
      local reverse,reverseKind=blockedPointRay(p+n*80,p-n*80,rp,exactBlocks,"perimeter")
      check(forward~=nil and reverse~=nil,"UnexpectedPerimeterOpening",{region=e.region,axis=e.axis,fixed=e.fixed,along=al,height=height,forward=forward and forward:GetFullName(),reverse=reverse and reverse:GetFullName(),forwardKind=forwardKind,reverseKind=reverseKind})
      if forward and reverse then row.blocked+=1 elseif #row.missing<24 then table.insert(row.missing,{along=al,height=height}) end
      yieldIfNeeded()
     end
    end
   end
   table.insert(report.perimeters,row)
  end
  report.sections.perimeterChecks=report.checks-startChecks
 end

 if sections.corners~=false then
  local startChecks=report.checks;local unique={};local cornerRows={}
  for _,e in input.perimeters do
   for _,al in {e.first,e.last} do
    local p=point(e.axis,e.fixed,al,0)
    local key=e.region..":"..string.format("%.5f:%.5f",p.X,p.Z)
    if not unique[key] then unique[key]={region=e.region,point=p} end
   end
  end
  for key,corner in unique do
   local r={key=key,casts=0,allowed=0,missing=0}
   for _,height in {1,5,12,17.99,35,70} do
    for _,theta in {15,30,45,60,75,105,120,135,150,165} do
     local d=Vector3.new(math.cos(math.rad(theta)),0,math.sin(math.rad(theta)))
     for _,offset in {-0.25,0,0.25} do
      local perpendicular=Vector3.new(-d.Z,0,d.X)
      local p=Vector3.new(corner.point.X,height,corner.point.Z)+perpendicular*offset
      local a,b=p-d*80,p+d*80
      -- Only a traverse from the region's inside to outside is a boundary crossing.
      if regionContains(corner.region,a)~=regionContains(corner.region,b) then
       if segmentUsesAllowed(a,b) then r.allowed+=1 else
        r.casts+=1
        local hit,hitKind=blockedPointRay(a,b,rp,exactBlocks,"corners")
        local reverse,reverseKind=blockedPointRay(b,a,rp,exactBlocks,"corners")
        check(hit~=nil and reverse~=nil,"CornerDiagonalOpening",{corner=key,height=height,theta=theta,offset=offset,forwardKind=hitKind,reverseKind=reverseKind})
        if not hit or not reverse then r.missing+=1 end
       end
      end
     end
    end
   end
   table.insert(cornerRows,r)
  end
  report.cornerRows=cornerRows;report.sections.cornerChecks=report.checks-startChecks
 end

 if sections.flanks~=false then
  local startChecks=report.checks
  for _,g in input.gates do
   local row={gate=g.gate,pointChecks=0,characterSweeps=0,startingOverlapBlocked=0}
   local lo,hi=g.actualStructuralOpening[1],g.actualStructuralOpening[2]
   local n,d=normal(g.axis),alongDirection(g.axis)
   for al=lo-0.25,hi+0.25,0.25 do
    if math.abs(al-g.center)>12+EPS then
     for _,height in {0.25,3,8,12,17.99,18.2,35,70} do
      local p=point(g.axis,g.fixed,al,height)
      for _,slope in {-40,-20,0,20,40} do
       local a,b=p-n*80-d*slope,p+n*80+d*slope
       local hit,hitKind=blockedPointRay(a,b,rp,exactBlocks,"flanks")
       local reverse,reverseKind=blockedPointRay(b,a,rp,exactBlocks,"flanks")
       row.pointChecks+=1
       check(hit~=nil and reverse~=nil,"GateSideDiagonalOpening",{gate=g.gate,along=al,height=height,alongDelta=slope*2,forwardKind=hitKind,reverseKind=reverseKind})
       yieldIfNeeded()
      end
     end
     -- Actual avatar-like box, walking and jumping. Initial overlap is tested
     -- explicitly because Blockcast intentionally does not report it.
     for _,bottom in {0.15,7.15,12.15} do
      for _,slope in {-20,0,20} do
       local p=point(g.axis,g.fixed,al,bottom+2.5)
       local a,b=p-n*64-d*slope,p+n*64+d*slope
       for _,reverse in {false,true} do
        local start,finish=reverse and b or a,reverse and a or b
        local cf=CFrame.lookAt(start,finish)
        local size=Vector3.new(2,5,2)
        local overlapping=Workspace:GetPartBoundsInBox(cf,size,op)
        local hit=Workspace:Blockcast(cf,size,finish-start,rp)
        row.characterSweeps+=1
        if #overlapping>0 then row.startingOverlapBlocked+=1 end
        check(#overlapping>0 or hit~=nil,"GateSideCharacterBypass",{gate=g.gate,along=al,bottom=bottom,alongDelta=slope*2,reverse=reverse})
       end
      end
     end
    end
   end
   table.insert(report.gates,row)
  end
  report.sections.flankChecks=report.checks-startChecks
 end

 if sections.closures~=false then
  local startChecks=report.checks
  for _,p in input.proposals do
   local pos,s=vec(p.worldPosition),vec(p.worldSize)
   local axis=s.X<s.Z and "Z" or "X"
   local n=normal(axis);local d=alongDirection(axis)
   local depth=axis=="Z" and s.X or s.Z
   local width=axis=="Z" and s.Z or s.X
   local row={id=p.id,kind=p.kind,rayChecks=0,exactCoreMatch=false}
   for _,native in colliders do
    if (native.Position-pos).Magnitude<0.002 and (native.Size-s).Magnitude<0.003 then row.exactCoreMatch=true end
   end
   check(row.exactCoreMatch,"MissingExpectedCollisionCore",{id=p.id,position=tostring(pos),size=tostring(s)})
   for _,fractionX in {0,0.25,0.5,0.75,1} do
    for _,fractionY in {0,0.25,0.5,0.75,1} do
     local al=(fractionX-0.5)*(width-0.02)
     local yy=(fractionY-0.5)*(s.Y-0.02)
     local center=pos+d*al+Vector3.new(0,yy,0)
     local a,b=center-n*(depth/2+0.5),center+n*(depth/2+0.5)
     local forward,forwardKind=blockedPointRay(a,b,crp,colliders,"closures")
     local reverse,reverseKind=blockedPointRay(b,a,crp,colliders,"closures")
     row.rayChecks+=1
     check(forward~=nil and reverse~=nil,"ClosureCoreNotSolidAtSample",{id=p.id,fractionAlong=fractionX,fractionHeight=fractionY,forwardKind=forwardKind,reverseKind=reverseKind})
     local occupants=Workspace:GetPartBoundsInBox(CFrame.new(center),Vector3.new(0.01,0.01,0.01),cop)
     check(#occupants>0,"ClosureCoreInitialOverlapMissing",{id=p.id,fractionAlong=fractionX,fractionHeight=fractionY})
    end
   end
   table.insert(report.proposalCores,row)
  end
  -- New solids must have no positive-volume intrusion into any named24x18 passage.
  for _,g in input.gates do
   local cf=asCF(g.nativeThresholdCF)
   local corridorCF=CFrame.new(cf.Position.X,9.05,cf.Position.Z)*(cf-cf.Position)
   local candidates=Workspace:GetPartBoundsInBox(corridorCF,Vector3.new(23.998,17.998,48),cop)
   check(#candidates==0,"NewClosureIntrudesPaidAperture",{gate=g.gate,parts=(function() local out={};for _,p in candidates do table.insert(out,p:GetFullName()) end;return out end)()})
  end
  report.sections.closureChecks=report.checks-startChecks
 end

 if sections.cart~=false then
  local startChecks=report.checks
  local size=options.loadedCartSize or Vector3.new(16,11.1385479,27.2479153)
  report.loadedCartSize={size.X,size.Y,size.Z}
  report.loadedCartEnvelopeSource=options.loadedCartEnvelopeSource or "Previously measured loaded native cart; pass current measured override if changed"
  local arp=RaycastParams.new();arp.FilterType=Enum.RaycastFilterType.Include;arp.FilterDescendantsInstances={map};arp.RespectCanCollide=true;arp.CollisionGroup="Default"
  local aop=OverlapParams.new();aop.FilterType=Enum.RaycastFilterType.Include;aop.FilterDescendantsInstances={map};aop.RespectCanCollide=true;aop.CollisionGroup="Default";aop.MaxParts=0
  local cartRows={}
  local function names(parts)
   local out={};for _,p in parts do if #out<20 then table.insert(out,p:GetFullName()) end end;return out
  end
  for _,g in input.gates do
   local threshold=gates:FindFirstChild(g.gate) and gates[g.gate]:FindFirstChild("Threshold")
   check(threshold and threshold:IsA("BasePart"),"GateThresholdUnavailable",g.gate)
   if threshold then
    local origin=CFrame.new(threshold.Position.X,0.05+0.10+size.Y/2,threshold.Position.Z)*(threshold.CFrame-threshold.Position)
    local row={gate=g.gate,overlapChecks=0,sweeps=0,centreSweepClear=true,manoeuvreClear=true}
    for _,offset in {-1.5,0,1.5} do
     for _,yaw in {-5,0,5} do
      for travel=-24,24,2 do
       local cf=origin*CFrame.new(offset,0,travel)*CFrame.Angles(0,math.rad(yaw),0)
       local parts=Workspace:GetPartBoundsInBox(cf,size,aop)
       row.overlapChecks+=1
       check(#parts==0,"LoadedCartRouteOverlap",{gate=g.gate,offset=offset,yaw=yaw,travel=travel,parts=names(parts)})
       if #parts>0 then row.manoeuvreClear=false end
      end
      for _,reverse in {false,true} do
       local sign=reverse and -1 or 1
       local cf=origin*CFrame.new(offset,0,sign*24)*CFrame.Angles(0,math.rad(yaw),0)
       local delta=origin:VectorToWorldSpace(Vector3.new(0,0,-sign*48))
       local startOverlap=Workspace:GetPartBoundsInBox(cf,size,aop)
       local hit=Workspace:Blockcast(cf,size,delta,arp)
       row.sweeps+=1
       check(#startOverlap==0 and hit==nil,"LoadedCartRouteSweepBlocked",{gate=g.gate,offset=offset,yaw=yaw,reverse=reverse,initial=names(startOverlap),hit=hit and hit.Instance:GetFullName()})
       if #startOverlap>0 or hit then row.manoeuvreClear=false;if offset==0 and yaw==0 then row.centreSweepClear=false end end
      end
     end
    end
    table.insert(cartRows,row)
   end
  end
  report.loadedCartRoutes=cartRows;report.sections.cartChecks=report.checks-startChecks
 end
 return report
end
return {Run=Run}
