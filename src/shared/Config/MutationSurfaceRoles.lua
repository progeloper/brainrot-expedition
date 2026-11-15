--!strict

-- Authored from the selected Development source audit on 14 October 2026.
-- All 35 stable species / 890 source BaseParts are mapped by exact relative path.
-- A path includes same-name sibling occurrence, matching AuditSources.luau.
-- Neutral mixed unions stay intact; their non-face pieces also retain source appearance.
-- Palette roles are development art assignments, not gameplay or economy data.

local AuthoredRoles: { [string]: { [string]: { string } } } = {
	BRT_001 = {
		Primary = {
			"Loaf#1/Body#1",
			"Paws#1/PawAndHock_1#1",
			"Paws#1/PawAndHock_2#1",
			"Paws#1/PawAndHock_3#1",
			"Paws#1/PawAndHock_4#1",
			"Tail#1/HookedWildcatTail#1",
		},
		Secondary = {
			"Ears#1/LynxEar_-1#1",
			"Ears#1/LynxEar_1#1",
			"Scoring#1/BakedCutRim_1#1",
			"Scoring#1/BakedCutRim_2#1",
			"Scoring#1/BakedCutRim_3#1",
			"Scoring#1/BakedCutRim_4#1",
			"Scoring#1/BakedCutRim_5#1",
			"WildcatMarkings#1/ToastedWildcatMarkings#1",
		},
		Accent = {
			"Face#1/Cheek_L#1",
			"Face#1/Cheek_R#1",
			"Scoring#1/OpenCreamScore_1#1",
			"Scoring#1/OpenCreamScore_2#1",
			"Scoring#1/OpenCreamScore_3#1",
			"Scoring#1/OpenCreamScore_4#1",
			"Scoring#1/OpenCreamScore_5#1",
		},
		Neutral = {
			"Face#1/Brow_R#1",
			"Face#1/Bucktooth#1",
			"Face#1/EyeGlint_L#1",
			"Face#1/EyeGlint_R#1",
			"Face#1/EyeWhite_L#1",
			"Face#1/EyeWhite_R#1",
			"Face#1/Mouth#1",
			"Face#1/Nose#1",
			"Face#1/Pupil_L#1",
			"Face#1/Pupil_R#1",
			"Face#1/RaisedBrow_L#1",
			"Face#1/Tongue#1",
			"Face#1/Whisker_-1_0#1",
			"Face#1/Whisker_-1_1#1",
			"Face#1/Whisker_1_0#1",
			"Face#1/Whisker_1_1#1",
		},
		Ignore = {
			"Loaf#1/HiddenRoot#1",
		},
	},
	BRT_002 = {
		Primary = {
			"BodyArt#1/Body#1",
			"BodyArt#1/WideMuzzle#1",
			"Forelimbs#1/Forearm_L#1",
			"Forelimbs#1/Forearm_R#1",
		},
		Secondary = {
			"Forelimbs#1/Elbow_L#1",
			"Forelimbs#1/Elbow_R#1",
			"HindLegs#1/BentAnkle_L#1",
			"HindLegs#1/BentAnkle_R#1",
			"HindLegs#1/FoldedHaunch_L#1",
			"HindLegs#1/FoldedHaunch_R#1",
		},
		Accent = {
			"Feet#1/FrontPaddle_L#1",
			"Feet#1/FrontPaddle_R#1",
			"Feet#1/HindPaddle_L#1",
			"Feet#1/HindPaddle_R#1",
			"RhythmCrest#1/RhythmBar_1#1",
			"RhythmCrest#1/RhythmBar_2#1",
			"RhythmCrest#1/RhythmBar_3#1",
			"Throat#1/InflatedSingingThroat#1",
		},
		Neutral = {
			"Eyes#1/Brow_L#1",
			"Eyes#1/Brow_R#1",
			"Eyes#1/EyeGlint_L#1",
			"Eyes#1/EyeGlint_R#1",
			"Eyes#1/EyeMount_L#1",
			"Eyes#1/EyeMount_R#1",
			"Eyes#1/EyeWhite_L#1",
			"Eyes#1/EyeWhite_R#1",
			"Eyes#1/Iris_L#1",
			"Eyes#1/Iris_R#1",
			"Eyes#1/Pupil_L#1",
			"Eyes#1/Pupil_R#1",
			"Face#1/CurvedCroakingMouth#1",
			"Face#1/CurvedLowerLip#1",
			"Face#1/Nostril_L#1",
			"Face#1/Nostril_R#1",
			"Face#1/Tongue#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_003 = {
		Primary = {
			"BodyArt#1/Body#1",
			"Feet#1/Foot_1#1",
			"Feet#1/Foot_2#1",
			"Feet#1/Foot_3#1",
			"Feet#1/Foot_4#1",
			"Feet#1/Toe_1_-1#1",
			"Feet#1/Toe_1_0#1",
			"Feet#1/Toe_1_1#1",
			"Feet#1/Toe_2_-1#1",
			"Feet#1/Toe_2_0#1",
			"Feet#1/Toe_2_1#1",
			"Feet#1/Toe_3_-1#1",
			"Feet#1/Toe_3_0#1",
			"Feet#1/Toe_3_1#1",
			"Feet#1/Toe_4_-1#1",
			"Feet#1/Toe_4_0#1",
			"Feet#1/Toe_4_1#1",
			"Head#1/BluntCapybaraHead#1",
			"Legs#1/Ankle_1#1",
			"Legs#1/Ankle_2#1",
			"Legs#1/Ankle_3#1",
			"Legs#1/Ankle_4#1",
			"Legs#1/Leg_1#1",
			"Legs#1/Leg_2#1",
			"Legs#1/Leg_3#1",
			"Legs#1/Leg_4#1",
		},
		Secondary = {
			"CoffeeAndFoam#1/CoffeeSurface#1",
			"Cup#1/CeramicCup#1",
			"Ears#1/EarOuter_L#1",
			"Ears#1/EarOuter_R#1",
		},
		Accent = {
			"CoffeeAndFoam#1/CappuccinoFoam#1",
			"CoffeeAndFoam#1/FoamHeart#1",
			"Cup#1/CreamRim#1",
			"Ears#1/EarInner_L#1",
			"Ears#1/EarInner_R#1",
		},
		SpecialSilver = {
			"Cup#1/CupHandle#1",
		},
		Neutral = {
			"Face#1/CapybaraGrin#1",
			"Face#1/EyeWhite_L#1",
			"Face#1/EyeWhite_R#1",
			"Face#1/Incisor_L#1",
			"Face#1/Incisor_R#1",
			"Face#1/Nostril_L#1",
			"Face#1/Nostril_R#1",
			"Face#1/Pupil_L#1",
			"Face#1/Pupil_R#1",
			"Face#1/SleepyLid_L#1",
			"Face#1/SleepyLid_R#1",
			"Head#1/EyeHood_L#1",
			"Head#1/EyeHood_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_004 = {
		Primary = {
			"Arms#1/BalletArm_L#1",
			"Arms#1/BalletArm_R#1",
			"Arms#1/Hand_L#1",
			"Arms#1/Hand_R#1",
			"Banana#1/Body#1",
			"Legs#1/Leg_L#1",
			"Legs#1/Leg_R#1",
			"Peel#1/GoldenPeelBody#1",
			"Peel#1/Peel_BackLeft#1/Outer#1",
			"Peel#1/Peel_BackRight#1/Outer#1",
			"Peel#1/Peel_FrontLeft#1/Outer#1",
			"Peel#1/Peel_FrontRight#1/Outer#1",
			"Slippers#1/Slipper_L#1",
			"Slippers#1/Slipper_R#1",
			"Tutu#1/PleatedTutu#1",
		},
		Secondary = {
			"Banana#1/BananaTip#1",
			"Peel#1/Peel_BackLeft#1/BrownTip#1",
			"Peel#1/Peel_BackRight#1/BrownTip#1",
			"Peel#1/Peel_FrontLeft#1/BrownTip#1",
			"Peel#1/Peel_FrontRight#1/BrownTip#1",
			"Tutu#1/TutuUnderside#1",
		},
		Accent = {
			"Accessories#1/BowKnot#1",
			"Accessories#1/BowLoop#1",
			"Face#1/Cheek_L#1",
			"Face#1/Cheek_R#1",
			"Legs#1/Ribbon_L_1#1",
			"Legs#1/Ribbon_L_2#1",
			"Legs#1/Ribbon_R_1#1",
			"Legs#1/Ribbon_R_2#1",
			"Peel#1/Peel_BackLeft#1/Inner#1",
			"Peel#1/Peel_BackRight#1/Inner#1",
			"Peel#1/Peel_FrontLeft#1/Inner#1",
			"Peel#1/Peel_FrontRight#1/Inner#1",
			"Slippers#1/Sole_L#1",
			"Slippers#1/Sole_R#1",
			"Tutu#1/TutuHem#1",
		},
		SpecialBronze = {
			"Tutu#1/Waistband#1",
		},
		Neutral = {
			"Face#1/BananaGrin#1",
			"Face#1/EyeGlint_L#1",
			"Face#1/EyeGlint_R#1",
			"Face#1/EyeWhite_L#1",
			"Face#1/EyeWhite_R#1",
			"Face#1/GrinTeeth#1",
			"Face#1/Lash_L_1#1",
			"Face#1/Lash_L_2#1",
			"Face#1/Lash_R_1#1",
			"Face#1/Lash_R_2#1",
			"Face#1/Pupil_L#1",
			"Face#1/Pupil_R#1",
			"Face#1/Tongue#1",
			"Face#1/UpperLid_L#1",
			"Face#1/UpperLid_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_005 = {
		Primary = {
			"BodyArt#1/Body#1",
			"Head#1/PigeonHead#1",
			"Neck#1/IridescentNeck#1",
			"Tail#1/TailFeather_1#1",
			"Tail#1/TailFeather_2#1",
			"Tail#1/TailFeather_3#1",
			"Wings#1/Wing_L#1/FlightFeather_1#1",
			"Wings#1/Wing_L#1/FlightFeather_2#1",
			"Wings#1/Wing_L#1/FlightFeather_3#1",
			"Wings#1/Wing_L#1/FlightFeather_4#1",
			"Wings#1/Wing_L#1/FlightFeather_5#1",
			"Wings#1/Wing_L#1/WingCoverts#1",
			"Wings#1/Wing_R#1/FlightFeather_1#1",
			"Wings#1/Wing_R#1/FlightFeather_2#1",
			"Wings#1/Wing_R#1/FlightFeather_3#1",
			"Wings#1/Wing_R#1/FlightFeather_4#1",
			"Wings#1/Wing_R#1/FlightFeather_5#1",
			"Wings#1/Wing_R#1/WingCoverts#1",
		},
		Secondary = {
			"Neck#1/VioletNeckBase#1",
			"Tail#1/TailBand_1#1",
			"Tail#1/TailBand_2#1",
			"Tail#1/TailBand_3#1",
			"Wings#1/Wing_L#1/PigeonWingBar_1#1",
			"Wings#1/Wing_L#1/PigeonWingBar_2#1",
			"Wings#1/Wing_R#1/PigeonWingBar_1#1",
			"Wings#1/Wing_R#1/PigeonWingBar_2#1",
		},
		Accent = {
			"Face#1/PaleCere#1",
			"Wings#1/Wing_L#1/CourierChevron#1",
			"Wings#1/Wing_R#1/CourierChevron#1",
		},
		SpecialBronze = {
			"Face#1/LowerBeak#1",
			"Face#1/UpperBeak#1",
			"Feet#1/Foot_L#1",
			"Feet#1/Foot_R#1",
			"Legs#1/PigeonLeg_L#1",
			"Legs#1/PigeonLeg_R#1",
		},
		Neutral = {
			"Face#1/BeakGap#1",
			"Face#1/EyeGlint_L#1",
			"Face#1/EyeGlint_R#1",
			"Face#1/EyeWhite_L#1",
			"Face#1/EyeWhite_R#1",
			"Face#1/Pupil_L#1",
			"Face#1/Pupil_R#1",
			"Face#1/UpperLid_L#1",
			"Face#1/UpperLid_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_006 = {
		Primary = {
			"BodyArt#1/Body#1",
			"Feet#1/Foot_LB#1",
			"Feet#1/Foot_LF#1",
			"Feet#1/Foot_RB#1",
			"Feet#1/Foot_RF#1",
			"Head#1/LongUpperSnout#1",
			"Head#1/LowerJaw#1",
			"Head#1/WideHead#1",
			"Legs#1/Haunch_LB#1",
			"Legs#1/Haunch_LF#1",
			"Legs#1/Haunch_RB#1",
			"Legs#1/Haunch_RF#1",
			"Tail#1/SweptTail#1",
		},
		Secondary = {
			"Armour#1/DorsalArmour_1#1",
			"Armour#1/DorsalArmour_2#1",
			"Armour#1/DorsalArmour_3#1",
			"Tail#1/TailScute_1#1",
			"Tail#1/TailScute_2#1",
			"Tail#1/TailScute_3#1",
		},
		Accent = {
			"BodyArt#1/GoldenBelly#1",
			"Pasta#1/Spaghetti_BackCoil#1",
			"Pasta#1/Spaghetti_Centre#1",
			"Pasta#1/Spaghetti_Left#1",
			"Pasta#1/Spaghetti_Right#1",
			"Pasta#1/Spaghetti_ShoulderFold#1",
		},
		SpecialSilver = {
			"Feet#1/Claws_LB#1",
			"Feet#1/Claws_LF#1",
			"Feet#1/Claws_RB#1",
			"Feet#1/Claws_RF#1",
		},
		Neutral = {
			"Face#1/EyeGlint_L#1",
			"Face#1/EyeGlint_R#1",
			"Face#1/EyeWhite_L#1",
			"Face#1/EyeWhite_R#1",
			"Face#1/FrontTooth_L#1",
			"Face#1/FrontTooth_R#1",
			"Face#1/MouthInterior#1",
			"Face#1/Nostril_L#1",
			"Face#1/Nostril_R#1",
			"Face#1/Pupil_L#1",
			"Face#1/Pupil_R#1",
			"Face#1/SideTooth_L1#1",
			"Face#1/SideTooth_L2#1",
			"Face#1/SideTooth_L3#1",
			"Face#1/SideTooth_R1#1",
			"Face#1/SideTooth_R2#1",
			"Face#1/SideTooth_R3#1",
			"Face#1/UpperLid_L#1",
			"Face#1/UpperLid_R#1",
			"Head#1/EyeHousing_L#1",
			"Head#1/EyeHousing_R#1",
			"Pasta#1/Spaghetti_MouthStrand#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_007 = {
		Primary = {
			"Arm_L#1",
			"Arm_R#1",
			"Body#1",
			"LegAndFoot_L#1",
			"LegAndFoot_R#1",
		},
		Secondary = {
			"WoodGrain#1",
			"WornWood#1",
		},
		Accent = {
			"Hand_L#1",
			"Hand_R#1",
		},
		SpecialBronze = {
			"HeldPrimitiveBat#1",
		},
		Neutral = {
			"BigTeeth#1",
			"CrookedGrin#1",
			"EyeHighlights#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Eyebrows#1",
			"Nose#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_008 = {
		Primary = {
			"Body#1",
			"CactusLegsAndToes#1",
			"DroopingFoldedEars#1",
			"HeavyElephantHead#1",
			"HeavySwingingTrunk#1",
		},
		Secondary = {
			"GiantSandalSoles#1",
			"RoundedCactusRibs#1",
		},
		Accent = {
			"CreamCactusSpines#1",
			"IvoryTusksAndToenails#1",
			"RecessedWarmEars#1",
		},
		SpecialSilver = {
			"GoldenSandalBuckles#1",
		},
		SpecialBronze = {
			"BroadLeatherStraps#1",
		},
		Neutral = {
			"DroopyHeavyLids#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"FaceAndTrunkCreases#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"UnevenExpressiveBrows#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_009 = {
		Primary = {
			"Body#1",
			"ChimpHeadAndEars#1",
			"LongArmsAndBentLegs#1",
			"YellowBananasAndThinPeels#1",
		},
		Secondary = {
			"GoldenBananaRidges#1",
		},
		Accent = {
			"ChestPatch#1",
			"ChimpFeetAndToes#1",
			"GrippingChimpHands#1",
			"PaleFruitAndPeelLinings#1",
			"TanFaceAndEarInsets#1",
		},
		SpecialBronze = {
			"BrownBananaTipsAndStems#1",
		},
		Neutral = {
			"CheekyMouth#1",
			"ExpressiveBrows#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"FlatChimpNose#1",
			"GrinTeeth#1",
			"Nostrils#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_010 = {
		Primary = {
			"Body#1",
			"BroadDiggingPawsAndFeet#1",
			"CurledMoleTail#1",
			"MoleHeadAndEars#1",
			"ShortArmsAndLegs#1",
		},
		Secondary = {
			"FacetedBackArmor#1",
			"GoggleStrapsAndDrillCollar#1",
		},
		Accent = {
			"IvoryDiggingClaws#1",
		},
		SpecialSilver = {
			"DrillCore#1",
			"RaisedSpiralDrill#1",
			"SilverArmorBorders#1",
			"SilverArmorSpikes#1",
		},
		SpecialBronze = {
			"BrassGogglesBandsAndBolts#1",
			"CopperMuzzleAndEarInsets#1",
		},
		Neutral = {
			"BrightEyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"RaisedBrowsAndWhiskers#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_011 = {
		Primary = {
			"Body#1",
			"CrocHeadAndUpperJaw#1",
			"CurledMelonStem#1",
			"FourCrocodileLegsAndFeet#1",
			"LowerJaw#1",
			"SweepingCrocodileTail#1",
		},
		Secondary = {
			"DarkWatermelonStripes#1",
			"FoldedMelonLeaves#1",
		},
		Accent = {
			"FiveWatermelonRindFins#1",
			"PaleFinPith#1",
		},
		Neutral = {
			"CoralOrangeIrises#1",
			"ExpressiveBrowsAndTailScutes#1",
			"EyeSparkles#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"IvoryTeethAndClaws#1",
			"OpenMouthInterior#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WatermelonFleshAndTongue#1",
			"WatermelonSeedsAndNostrils#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_012 = {
		Primary = {
			"Body#1",
			"CamelNeckHeadEarsAndLegs#1",
		},
		Secondary = {
			"DarkBootSolesAndTreads#1",
			"DarkSealsVentsAndCoolingCoils#1",
			"OversizedLeatherBoots#1",
		},
		Accent = {
			"CreamThroatAndLowerMuzzle#1",
			"CyanTrimAndFrost#1",
			"FourFridgeDoors#1",
			"IvoryLacesAndSnowflake#1",
			"WarmCamelEarInsets#1",
		},
		SpecialSilver = {
			"ChromeHandlesAndHinges#1",
		},
		SpecialBronze = {
			"GoldenCuffsAndToeCaps#1",
		},
		Neutral = {
			"AmberCamelIrises#1",
			"BlueSnowflakeBadge#1",
			"BrightEyeGlints#1",
			"BrowsNostrilsAndSmile#1",
			"CleanGrinTeeth#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_013 = {
		Primary = {
			"Body#1",
			"HorseNeckHeadAndEars#1",
		},
		Secondary = {
			"KeyboardBed#1",
			"ManeAndSweepingTail#1",
			"PianoTop#1",
			"TwoChunkyBootSoles#1",
			"TwoTallBlackBoots#1",
		},
		Accent = {
			"BootLaces#1",
			"HorseMuzzleAndInnerEars#1",
			"HorseWhiteBlaze#1",
			"RearSoundboard#1",
		},
		SpecialBronze = {
			"BrassRimStringsAndPedals#1",
		},
		Neutral = {
			"AlignedEyeGlints#1",
			"LargeHorseEyeWhites#1",
			"PianoBlackKeysAndFaceDetails#1",
			"PianoWhiteKeysAndToothRow#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WarmAmberIrises#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_014 = {
		Primary = {
			"Body#1",
			"FurHeadEarsAndPaws#1",
		},
		Secondary = {
			"BeaverPaddleTail#1",
			"DrumGunMetal#1",
			"TailCrosshatchAndToeLines#1",
			"TiltedFedora#1",
		},
		Accent = {
			"CreamMuzzleAndInnerEars#1",
			"IvoryPinstripesAndCollar#1",
			"ScarletTieAndPocketSquare#1",
		},
		SpecialSilver = {
			"DrumGunChromeTrim#1",
		},
		SpecialBronze = {
			"DrumGunWood#1",
			"GoldBandFramesAndDetails#1",
		},
		Neutral = {
			"BrightEyeAndLensGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"GreenBeaverIrises#1",
			"LoweredBlueSunglasses#1",
			"NoseBrowsAndSmile#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"TwoBuckTeeth#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_015 = {
		Primary = {
			"Body#1",
			"FlamingoHead#1",
			"FlamingoSNeck#1",
			"TwoKnobblyJoints#1",
			"TwoSlenderFlamingoLegs#1",
			"TwoWebbedFeet#1",
		},
		Secondary = {
			"LayeredBerryWings#1",
			"SevenFoldedCalyxLeaves#1",
			"WebbedToeCreases#1",
		},
		Accent = {
			"BrightFeatherEdges#1",
			"IvoryFlamingoBeak#1",
			"LimeLeafFacets#1",
		},
		SpecialBronze = {
			"GoldenSeedsAroundBerry#1",
		},
		Neutral = {
			"AmberIrises#1",
			"BlackHookedBeakTip#1",
			"BrowsNostrilsAndBeakSeam#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_016 = {
		Primary = {
			"Body#1",
			"GorillaMuzzleMaskAndEars#1",
			"LongKnuckleWalkingArms#1",
			"ShortBentHindLegs#1",
		},
		Secondary = {
			"DarkHandsAndOpposableFeet#1",
			"FiveRecessedSpeakerCones#1",
			"FlushSpeakerHousingsAndCaps#1",
		},
		Accent = {
			"CyanShoulderRimsAndCores#1",
			"SlopingSilverbackFur#1",
		},
		SpecialSilver = {
			"SilverSpeakerBolts#1",
		},
		SpecialBronze = {
			"AmberWooferRims#1",
		},
		Neutral = {
			"AmberGorillaIrises#1",
			"BroadFlatGorillaNose#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"GorillaCraniumCheeksAndBrow#1",
			"IvoryGorillaTeeth#1",
			"NostrilsMouthAndHandCreases#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"TinyEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_017 = {
		Primary = {
			"Body#1",
			"GingerHeadFlangesArmsAndLegs#1",
			"PineappleDiamondScalesAllSides#1",
		},
		Secondary = {
			"CurledFingersAndToes#1",
			"NinePineappleCrownLeaves#1",
		},
		Accent = {
			"BrightLeafFoldFacets#1",
			"FaceHandsAndFeet#1",
			"PineappleScaleGoldenEyes#1",
		},
		Neutral = {
			"AmberIrises#1",
			"BrowsNostrilsAndMouth#1",
			"EyeGlints#1",
			"HugeInquisitiveEyeWhites#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"SingleCleanToothRow#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_018 = {
		Primary = {
			"Body#1",
			"FourZebraLegsNeckSkullAndEars#1",
		},
		Secondary = {
			"DarkZebraMuzzle#1",
			"FourZebraHooves#1",
			"MelonRindStripes#1",
			"SixteenMelonSeeds#1",
			"StandingManeAndTail#1",
			"TailTuft#1",
		},
		Accent = {
			"BrightRedMelonFlesh#1",
			"PaleRindAtCutSurfaces#1",
		},
		Neutral = {
			"BlackZebraStripesAndExpression#1",
			"GoldenZebraIrises#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"StartledZebraEyeWhites#1",
			"WhiteEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_019 = {
		Primary = {
			"Body#1",
			"LayeredWingsAndTailFeathers#1",
			"OstrichNeckAndHead#1",
			"TwoLongLegsAndBareFeet#1",
		},
		Secondary = {
			"DarkWheelsBeakAndEngineDetails#1",
			"HeadMountedSmokestack#1",
			"LocomotiveChassis#1",
		},
		Accent = {
			"LowerOstrichBeak#1",
			"PorcelainToiletBowlCisternAndSeat#1",
			"RedDrivingWheelHubs#1",
		},
		SpecialSilver = {
			"SilverRodsRivetsAndFlushLever#1",
		},
		SpecialBronze = {
			"BrassRailsAndHeadlamp#1",
		},
		Neutral = {
			"Pupil_L#1",
			"Pupil_R#1",
			"StartledOstrichEyeWhites#1",
			"TinyEyeGlints#1",
			"YellowOstrichIrises#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_020 = {
		Primary = {
			"Body#1",
			"TwoOversizedCanvasSneakers#1",
		},
		Secondary = {
			"DarkJupiterPolarBand#1",
			"RustJupiterBandsAllAround#1",
			"ShaggyBisonSkullCheeksEarsAndBeard#1",
		},
		Accent = {
			"BisonMuzzleAndEarInteriors#1",
			"CreamJupiterBandsAllAround#1",
			"TwoHookedIvoryHorns#1",
			"WhiteSneakerSolesAndToeCaps#1",
		},
		SpecialBronze = {
			"GreatRedSpot#1",
			"GreatRedSpotInnerVortex#1",
			"GreatRedSpotOuterCloud#1",
		},
		Neutral = {
			"AmberBisonIrises#1",
			"BisonEyeWhites#1",
			"DarkBrowsNostrilsAndMouth#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WhiteCrossedLacesAndEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_021 = {
		Primary = {
			"Body#1",
			"BroadHippoHeadMuzzleAndEars#1",
			"TwoBentSaguaroBranches#1",
			"TwoShortConnectedCactusLegs#1",
		},
		Secondary = {
			"TwoOversizedDarkSandalSoles#1",
		},
		Accent = {
			"ContinuousBrightCactusRidges#1",
			"PinkEarInsertsAndCactusFlower#1",
			"SixHippoToes#1",
			"SixteenSolidCactusThorns#1",
		},
		SpecialBronze = {
			"GoldenSandalStraps#1",
		},
		Neutral = {
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"GoldHippoIrises#1",
			"HippoBrowsNostrilsAndMouth#1",
			"HippoIncisorsAndGlints#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_022 = {
		Primary = {
			"Body#1",
			"FourBareFeetAndToes#1",
			"FourHumanLikeWalkingLegs#1",
			"GingerCatHeadAndPointedEars#1",
		},
		Secondary = {
			"FishGillCovers#1",
		},
		Accent = {
			"CreamCatMuzzleAndChin#1",
			"DorsalSideFinsAndForkedFishTail#1",
			"TwentyFourRaisedDiamondScales#1",
		},
		Neutral = {
			"EmeraldCatIrises#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"PinkEarsAndCatNose#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WhiskersTabbyStripesGillSlitsAndFinRays#1",
			"WhiteEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_023 = {
		Primary = {
			"Body#1",
			"CurvingGiraffeTail#1",
			"FourLongGiraffeLegs#1",
			"LongNeckHeadEarsAndOssicones#1",
		},
		Secondary = {
			"EightWrappingWatermelonStripes#1",
			"FourDarkBootSoles#1",
			"GiraffeSpotsHornTipsAndTailTuft#1",
		},
		Accent = {
			"CyanOxygenHoseAndHelmetLights#1",
			"TwinRearOxygenBottles#1",
		},
		SpecialSilver = {
			"OpenAstronautHelmetFrameDomeAndCollar#1",
		},
		SpecialBronze = {
			"FourBrownAstronautBoots#1",
			"GoldHelmetHinges#1",
		},
		Neutral = {
			"BootLacesAndEyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"GiraffeAmberIrises#1",
			"GiraffeBrowsNostrilsSmile#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_024 = {
		Primary = {
			"Body#1",
			"ConnectedKneelingLegsAndPleadingArms#1",
			"OverlappingTortillaWrapFolds#1",
		},
		Secondary = {
			"DarkBeanFilling#1",
			"EightToastedWrapMarks#1",
		},
		Accent = {
			"CreamRiceGrains#1",
			"FoldedGreenLettuceFilling#1",
			"RedTomatoChunks#1",
			"TwoWhiteKneelingSneakers#1",
			"WhitePhoneCase#1",
		},
		Neutral = {
			"BlueWetIrises#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"LongBlueTearsAndDroplets#1",
			"PhoneScreenCameraAndWrappedGrip#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"RedLostHotspotSymbolAndPhoneCross#1",
			"WailingMouthAndDesperateBrows#1",
			"WetEyeGlintsAndToothBand#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_025 = {
		Primary = {
			"Body#1",
			"SalamiHeadAndCuredCrown#1",
		},
		Secondary = {
			"BlackPointedBeakAndToeCreases#1",
			"DeepRedSalamiCasingSeams#1",
			"LongBlackFlippersAndPenguinTail#1",
		},
		Accent = {
			"CreamPenguinBellyAndChin#1",
			"SalamiCasingTwineTie#1",
			"TwentyFiveCreamSalamiFatFlecks#1",
		},
		SpecialBronze = {
			"TwoShortOrangePenguinLegs#1",
			"TwoSplayedWebbedFeet#1",
		},
		Neutral = {
			"CuredRedHeavyBrows#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"OrangePenguinIrises#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WhitePenguinEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_026 = {
		Primary = {
			"Body#1",
			"PowerfulRhinoArmsLegsHandsAndFeet#1",
			"RhinoHeadLongMuzzleAndEars#1",
		},
		Secondary = {
			"DarkCuppedRhinoEarInserts#1",
			"TwentyToastBrownFlecks#1",
		},
		Accent = {
			"FourToastCrumbFaces#1",
			"OrangeHeatAndControls#1",
			"SixBroadRhinoToenails#1",
			"TwoCurvedIvoryRhinoHorns#1",
		},
		SpecialSilver = {
			"ChromeRimsPanelLeverTrayAndPlugProngs#1",
		},
		SpecialBronze = {
			"TwoThickGoldenToastSlices#1",
		},
		Neutral = {
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"RhinoAmberIrises#1",
			"RhinoBrows#1",
			"RhinoGlintsAndCleanToothRow#1",
			"ToasterSlotsVentsCordAndRhinoFacialCreases#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_027 = {
		Primary = {
			"Body#1",
			"DorsalPectoralAndForkedTailFins#1",
			"IntegratedSharkEyeSocketsAndMuzzle#1",
			"ThreeCobaltTrainers#1",
			"ThreeConnectedFinLegs#1",
		},
		Secondary = {
			"HeelCollars#1",
		},
		Accent = {
			"IvoryBellyPlanes#1",
			"IvoryLowerSharkJaw#1",
			"TrainerLacesAndSideStripes#1",
			"TrainerSoles#1",
		},
		Neutral = {
			"AlternatingSharkTeeth#1",
			"BrowsGillsAndNostrils#1",
			"CyanSharkIrises#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WideSharkGrin#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_028 = {
		Primary = {
			"Body#1",
			"TurtleHeadNeckJawAndTail#1",
		},
		Secondary = {
			"SixConnectedBentSpiderLegs#1",
		},
		Accent = {
			"RaisedLeafGreenShellScutes#1",
			"SixAngularLegJoints#1",
		},
		SpecialBronze = {
			-- This lip is the shell rim, verified in BRT_028.geometry.luau.
			"GoldenShellScutesAndLip#1",
			"SixGoldenFootTips#1",
		},
		Neutral = {
			"AmberIrisesAndFourSmallSpiderEyes#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"MischievousFangedMouth#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"SmallPupilsAndTurtleNostrils#1",
			"TurtleBrows#1",
			"TwoCurvedIvoryFangs#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_029 = {
		Primary = {
			"Body#1",
			"ElephantHeadAndFlaredEars#1",
			"ElephantTail#1",
			"FourBroadFeet#1",
			"FourPillarLegs#1",
			"LongCurledElephantTrunk#1",
		},
		Secondary = {
			"DarkHuskGrooves#1",
			"TailHuskTuft#1",
		},
		Accent = {
			"EarInnerFoldPlanes#1",
			"ExposedCoconutCreamRim#1",
			"TwelveToenails#1",
			"TwoUpturnedTusks#1",
		},
		SpecialBronze = {
			"LongGoldenCoconutFibres#1",
		},
		Neutral = {
			"BrightTropicalIrises#1",
			"CoconutWaterAtOpening#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"TrunkCreasesAndBrows#1",
			"WhiteEyeGlints#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_030 = {
		Primary = {
			"Body#1",
			"DinosaurHeadJawArmsAndTail#1",
		},
		Secondary = {
			"FortyEightTyreTreads#1",
			"FourRuggedTyres#1",
		},
		Accent = {
			"LimeThroatAndDorsalPlates#1",
		},
		SpecialSilver = {
			"TractorSteelHardware#1",
		},
		SpecialBronze = {
			"OrangeTractorChassisAndMudguards#1",
			"OrangeWheelHubs#1",
		},
		Neutral = {
			"AmberDinosaurIrises#1",
			"BrowsNostrilsGrilleAndExhaust#1",
			"EyeHighlights#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"IvoryTeethAndTinyClaws#1",
			"OpenTyrannosaurMouth#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_031 = {
		Primary = {
			"Body#1",
			"ClenchedFistsAndIndividualKnuckles#1",
			"TwoHugeFlexedBicepsAndForearms#1",
			"TwoPowerfulOrangeLegs#1",
		},
		Secondary = {
			"HighTopAnkleCollars#1",
			"NavyAthleticShoes#1",
			"RearOrangeSegmentSeams#1",
			"TwoFoldedOrangeLeaves#1",
			"WoodyOrangeStem#1",
		},
		Accent = {
			"FacetedCitrusPecsAndAbs#1",
			"LeafMidribs#1",
			"OrangeTrainerPanels#1",
			"ThickIvorySoles#1",
			"TrainerLacesAndHeelTabs#1",
		},
		Neutral = {
			"BluntOrangeNose#1",
			"BrightEyeGlints#1",
			"CleanIvoryToothRow#1",
			"DeterminedBrows#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"FistKneeAndSmileCreases#1",
			"HazelIrises#1",
			"LopsidedCompetitiveGrin#1",
			"Pupil_L#1",
			"Pupil_R#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_032 = {
		Primary = {
			"Body#1",
			"CowNeckHeadAndEars#1",
			"SwishingCowTail#1",
			"TenSculptedHumanToes#1",
			"TwoGiantHumanFeet#1",
			"TwoHumanCalves#1",
		},
		Secondary = {
			"AmberSaturnCloudBands#1",
			"DarkCowTailTuft#1",
			"DistinctiveDairyCowPatches#1",
		},
		Accent = {
			"CreamSaturnCloudBands#1",
			"FiveOrbitalStarInlays#1",
			"OuterIvorySaturnRing#1",
			"PinkMuzzleAndEarFolds#1",
			"TenToenails#1",
			"TwoIvoryCowHorns#1",
		},
		SpecialSilver = {
			"BroadPaleGoldSaturnRing#1",
			"SmallOrbitingMoon#1",
		},
		SpecialBronze = {
			"InnerBronzeSaturnRing#1",
		},
		Neutral = {
			"CowBrowsNostrilsAndSmile#1",
			"EyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"WarmAmberCowIrises#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_033 = {
		Primary = {
			"Body#1",
			"DragonHeadAndJaw#1",
			"FourBentDragonLegs#1",
			"FourDragonFeet#1",
			"LongCurledDragonTail#1",
			"RibbedPastaWingSkeleton#1",
			"SweepingDragonNeck#1",
		},
		Secondary = {
			"OrangeFoldedWingMembranes#1",
			"SixSauceFilledJoints#1",
			"SweptBrownHorns#1",
			"TwelveCurvedClaws#1",
		},
		Accent = {
			"CheekAndBackSpines#1",
			"LayeredPastaBelly#1",
			"SixCannelloniRollRims#1",
		},
		SpecialBronze = {
			"SculptedGoldenWingFlames#1",
		},
		Neutral = {
			"CyanDragonIrises#1",
			"DragonEyeGlints#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"NostrilsAndRoaringMouth#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"RuggedDragonBrows#1",
			"SauceTongue#1",
			"SharpDragonTeeth#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_034 = {
		Primary = {
			"Body#1",
			"FourWhaleLegs#1",
			"OrcaHeadAndSnout#1",
			"RaisedWhaleTailStock#1",
			"TallSweptDorsalFin#1",
			"TwoFlaredPectoralFins#1",
			"TwoHorizontalTailFlukes#1",
		},
		Secondary = {
			"FourDetailedTrainerUppers#1",
			"SoleTreads#1",
		},
		Accent = {
			"CyanTrainerTrim#1",
			"GreySaddlePatch#1",
			"NaturalWhiteWhaleMarkings#1",
			"SixteenTrainerLaces#1",
			"TrainerSolesCapsAndSeams#1",
		},
		Neutral = {
			"AmberOrcaIrises#1",
			"Blowhole#1",
			"CleanSmallOrcaTeeth#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"OrcaEyeGlints#1",
			"PinkMouthInterior#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"RaisedOrcaBrows#1",
			"WideOrcaGrin#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
	BRT_035 = {
		Primary = {
			"Body#1",
			"PorcelainCistern#1",
			"RosyCheeks#1",
			"TwoPorcelainArms#1",
		},
		Secondary = {
			"DragonFruitBackSeeds#1",
			"DragonFruitBackShell#1",
			"PhoneCase#1",
			"WoodGrainAccents#1",
		},
		Accent = {
			"DetailedWhiteGloveHands#1",
			"FacetedToiletSeatRim#1",
			"GreenBellRoof#1",
			"TwentyFourDragonFruitSpikes#1",
		},
		SpecialBronze = {
			"GoldBellClapperAndFlush#1",
			"PlantedWoodenFeetAndToes#1",
			"TwoWoodenLegs#1",
			"UpperHeadPhoneArmAndGrip#1",
			"UpperWoodenHead#1",
			"UpperWoodenJaw#1",
		},
		Neutral = {
			"ContinuousIvoryToothRow#1",
			"CyanPhoneScreen#1",
			"DelightedBrows#1",
			"EyeWhite_L#1",
			"EyeWhite_R#1",
			"GrippedNinePlacard#1",
			"LongFoldedPinkTongue#1",
			"PhoneDisplayDetails#1",
			"PrimaryEyeGlints#1",
			"PrimaryGoldenIrises#1",
			"Pupil_L#1",
			"Pupil_R#1",
			"SculptedNumberNines#1",
			"UpperAmberEyes#1",
			"UpperFaceWhiteEyes#1",
			"UpperHeadSocketsPupilsAndMouth#1",
			"WideDelightedMouth#1",
		},
		Ignore = {
			"HiddenRoot#1",
		},
	},
}

local SourceParts: { [string]: { [string]: string } } = {}
for speciesId, groups in AuthoredRoles do
	local paths: { [string]: string } = {}
	for role, entries in groups do
		for _, path in entries do
			assert(paths[path] == nil, "Duplicate mutation role path: " .. speciesId .. "/" .. path)
			paths[path] = role
		end
	end
	SourceParts[speciesId] = table.freeze(paths)
end
table.freeze(SourceParts)

local SurfaceRoles = {}
SurfaceRoles.SourceParts = SourceParts
SurfaceRoles.SourceAudit = "assets/phase12-mutations/reference/Source_Baseline.json"
SurfaceRoles.SourceSpeciesCount = 35
SurfaceRoles.SourcePartCount = 890

function SurfaceRoles.GetSpeciesId(model: Model): string?
	local id = model:GetAttribute("BrainrotId")
		or (
			if model:GetAttribute("PresentationRole") == "FrontTeam"
				then model:GetAttribute("CosmeticSpeciesId")
				else nil
		)
	if type(id) == "string" and SourceParts[id] then
		return id
	end
	if SourceParts[model.Name] then
		return model.Name
	end
	return nil
end

-- GetChildren ordering is stable in a native clone. Duplicate paths are indexed
-- exactly like the source audit; no runtime color or mutation inference is used.
function SurfaceRoles.GetPath(model: Model, part: Instance): string?
	local segments: { string } = {}
	local cursor: Instance? = part
	while cursor and cursor ~= model do
		local parent = cursor.Parent
		if parent == nil then
			return nil
		end
		local occurrence = 0
		for _, sibling in parent:GetChildren() do
			if sibling.Name == cursor.Name then
				occurrence += 1
			end
			if sibling == cursor then
				break
			end
		end
		table.insert(segments, 1, cursor.Name .. "#" .. tostring(occurrence))
		cursor = parent
	end
	if cursor ~= model then
		return nil
	end
	return table.concat(segments, "/")
end

function SurfaceRoles.GetRole(speciesId: string, path: string): string
	local paths = SourceParts[speciesId]
	return if paths then (paths[path] or "Preserve") else "Preserve"
end

function SurfaceRoles.Resolve(model: Model)
	local speciesId = SurfaceRoles.GetSpeciesId(model)
	local parts = {}
	local unknown: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local path = SurfaceRoles.GetPath(model, descendant) or descendant.Name
			local role = if speciesId then SurfaceRoles.GetRole(speciesId, path) else "Preserve"
			parts[descendant] = { path = path, role = role }
			seen[path] = true
			if role == "Preserve" then
				table.insert(unknown, path)
			end
		end
	end
	local missing: { string } = {}
	if speciesId then
		for path in SourceParts[speciesId] do
			if not seen[path] then
				table.insert(missing, path)
			end
		end
	end
	table.sort(unknown)
	table.sort(missing)
	return { speciesId = speciesId, parts = parts, unknown = unknown, missing = missing }
end

return table.freeze(SurfaceRoles)
