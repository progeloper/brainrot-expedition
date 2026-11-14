// BRT_031 Odin Din Din Dun — Voxel V4 build (CP-C, Legendary, revision 3).
// References (viewed only):
// - the Steal a Brainrot in-game model (stealabrainrot.noob.wiki: "muscular orange limbs and bodybuilding pose ...
//   a pair of stylish white-red-black" high-top sneakers): a blocky orange with a face on the front, a curved
//   green stem, huge arms in a double-biceps flex, thin legs in high-tops
// - the original meme image (brainrotcharacters.net): a round orange with a stern, determined face and blue eyes,
//   one big green leaf on the stem, massive bulging bodybuilder arms and legs, and small posing trunks
// - the project recipe (faceted citrus torso, clenched knuckles, rear segment seams, heel tabs)
// Revision 2 (owner): "as before, use online references and super dopamine v4".
// - closer to the references: a rounder, taller orange; one big leaf; much bigger, layered bodybuilder arms
//   (deltoid, bicep peak, flaring forearm) with lighter muscle highlights; thicker legs with calves; a determined
//   gritted-teeth flex grin; hot-pink posing trunks (the original's trunks)
// - louder: a more vivid orange, glowing gold wristbands and soles (Legendary gold), a bigger gold belt plate with
//   three glowing gems, a glowing leaf vein, red high-tops with glowing laces
// Revision 3 (owner): "more dopamine spiking, needs to feel worth the hunt". Jackpot bling on the revision 2
//   design: a jeweled gold champion's crown around the stem, gold bicep armbands with glowing gems, and glowing gold
//   lightning veins down the forearms.
// Rig-ready (owner rule): legs are a matching pair with hip / knee / ankle collars and flat soles pointing ahead;
// the flex arms are a mirrored pair with shoulder / elbow collars (the double-biceps pose is the meme's identity).
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#3A1A08';
const GOLD = '#FFC21A';
const MAW = '#6E0E2C';

// --- the round orange: orange peel top (the equator band is the Body), cream pith belly, cyan waterline
const CCY = 2.75, CR = 1.12, RY = 1.08;
const rC = (y) => CR * Math.sqrt(Math.max(0.03, 1 - ((y - CCY) / RY) ** 2));
function layer(y0, y1, r, role, rel = R, flags = 0) {
	B(-r, r, y0, y1, -0.7 * r, 0.7 * r, role, rel | flags);
	B(-0.66 * r, 0.66 * r, y0, y1, -r, r, role, rel | flags);
}
S('Body');
B(-CR, CR, 2.5, 3.0, -0.7 * CR, 0.7 * CR, 'upper', R);
S('Fruit');
B(-0.66 * CR, 0.66 * CR, 2.5, 3.0, -CR, CR, 'upper', R);
for (const [y0, y1] of [[2.42, 2.5], [3.0, 3.2], [3.2, 3.4], [3.4, 3.58], [3.58, 3.72], [3.72, 3.83]]) layer(y0, y1, rC((y0 + y1) / 2), 'upper');
S('Pith');
for (const [y0, y1] of [[1.67, 1.82], [1.82, 2.0], [2.0, 2.2], [2.2, 2.36]]) layer(y0, y1, rC((y0 + y1) / 2), 'lower');
S('Waterline');
layer(2.36, 2.42, rC(2.39) + 0.03, 'stripe', 0, E);
S('SegmentSeam');                                               // citrus segment seams on the back
for (const z of [-0.42, 0, 0.42]) B(-CR - 0.03, -CR + 0.02, 2.45, 3.4, z - 0.05, z + 0.05, 'feather');

// --- the face panel: determined blue anime eyes under low lids, thin angled brows, gritted-teeth flex grin
S('Face');
B(0.8, 1.14, 2.3, 3.45, -0.62, 0.62, 'upper', R);
const FX = 1.14;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.3 * out, top: 3.3, L: 0.9, H: 0.9, out, iris: 'Ocean', lash: false, blush: true });
	const zi = eye.inner, zo = eye.outer;
	const zr = (a, b) => [Math.min(a, b), Math.max(a, b)];
	const mid = (zi + zo) / 2;
	S('Lid');                                                   // low, determined lid: lower on the inner half
	B(FX, FX + 0.13, 3.13, 3.35, ...zr(zi - 0.03 * out, zo + 0.03 * out), 'upper');
	B(FX, FX + 0.13, 3.07, 3.13, ...zr(zi - 0.03 * out, mid), 'upper');
	S('LashLine');
	B(FX, FX + 0.14, 3.1, 3.13, ...zr(mid, zo + 0.05 * out), 'P', 0, '#000000');
	B(FX, FX + 0.14, 3.04, 3.07, ...zr(zi - 0.03 * out, mid), 'P', 0, '#000000');
	S('Brow');                                                  // thin angled brows with a gap between them
	B(FX, FX + 0.06, 3.42, 3.47, ...zr(mid, zo + 0.02 * out), 'P', 0, INK);
	B(FX, FX + 0.06, 3.37, 3.42, ...zr(0.1 * out, mid), 'P', 0, INK);
}
S('Nose');
B(FX, FX + 0.12, 2.62, 2.78, -0.08, 0.08, 'upper');
S('Mouth');                                                     // gritted-teeth flex grin
B(FX, FX + 0.02, 2.34, 2.52, -0.28, 0.28, 'P', 0, MAW);
MZ(FX, FX + 0.02, 2.52, 2.58, 0.22, 0.3, 'P', 0, MAW);
S('Teeth');
B(FX, FX + 0.03, 2.45, 2.52, -0.25, 0.25, 'P', 0, '#FFFFFF');
B(FX, FX + 0.03, 2.35, 2.42, -0.21, 0.21, 'P', 0, '#FFFFFF');

// --- jackpot bling: a jeweled gold champion's crown around the stem
S('Crown');
B(-0.58, 0.58, 3.8, 3.98, -0.58, 0.58, 'P', 0, GOLD);
for (const [x, z] of [[0.48, 0.48], [0.48, -0.48], [-0.48, 0.48], [-0.48, -0.48]]) B(x - 0.1, x + 0.1, 3.98, 4.26, z - 0.1, z + 0.1, 'P', 0, GOLD);
S('CrownGem');
B(0.58, 0.63, 3.82, 3.96, -0.11, 0.11, 'P', E, '#FF2DD1');
MZ(-0.11, 0.11, 3.82, 3.96, 0.58, 0.63, 'P', E, '#2EF2FF');

// --- curved green stem and one big leaf with a glowing vein (as in the original meme)
S('Stem');
B(-0.07, 0.07, 3.8, 4.12, -0.07, 0.07, 'skin2');
B(-0.07, 0.26, 4.06, 4.16, -0.07, 0.07, 'skin2');
S('Leaf');
B(-0.22, 0.22, 3.94, 4.04, 0.06, 0.4, 'skin2', R);
B(-0.3, 0.3, 4.02, 4.12, 0.3, 0.86, 'skin2', R);
B(-0.18, 0.18, 4.1, 4.18, 0.78, 1.06, 'skin2');
S('LeafVein');
B(-0.03, 0.03, 4.12, 4.14, 0.1, 0.96, 'P', E, '#C6FF3A');

// --- hot-pink posing trunks (the original's trunks) and the purple champion's belt with a gold plate
S('PosingTrunks');
B(-0.42, 0.42, 1.58, 1.8, -0.64, 0.64, 'feather2', R);
B(0.42, 0.46, 1.6, 1.74, -0.22, 0.22, 'feather2');
S('ChampionBelt');
layer(1.88, 2.06, rC(1.97) + 0.03, 'prop', 0);
S('BeltPlate');
B(0.66, 0.92, 1.76, 2.18, -0.42, 0.42, 'P', 0, GOLD);
MZ(0.56, 0.76, 1.84, 2.1, 0.46, 0.62, 'P', 0, GOLD);
S('BeltGem');
B(0.92, 0.97, 1.88, 2.06, -0.11, 0.11, 'P', E, '#2EF2FF');
MZ(0.92, 0.95, 1.92, 2.02, 0.22, 0.32, 'P', E, '#FF2DD1');

// --- massive tangerine bodybuilder arms in a mirrored double-biceps flex
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('ShoulderCollar');
	B(-0.3, 0.3, 2.84, 3.4, ...z(0.98, 1.06), 'P', 0, DARK);
	S('Deltoid');
	B(-0.36, 0.36, 2.86, 3.46, ...z(1.04, 1.32), 'skin', R);
	S('UpperArm');
	B(-0.32, 0.32, 2.8, 3.32, ...z(1.26, 1.92), 'skin', R);
	S('Bicep');                                                 // the big bicep peak
	B(-0.34, 0.34, 3.32, 3.78, ...z(1.3, 1.82), 'skin', R);
	B(-0.22, 0.22, 3.78, 3.88, ...z(1.42, 1.7), 'skin');
	S('MuscleHighlight');
	B(0.34, 0.36, 3.38, 3.72, ...z(1.4, 1.72), 'feather');
	B(0.36, 0.38, 2.92, 3.36, ...z(1.08, 1.28), 'feather');
	S('Armband');                                               // gold armband with a glowing gem
	B(-0.35, 0.35, 2.78, 3.6, ...z(1.24, 1.32), 'P', 0, GOLD);
	B(0.35, 0.39, 3.0, 3.2, ...z(1.25, 1.31), 'P', E, '#FF2DD1');
	S('ElbowCollar');
	B(-0.3, 0.3, 2.78, 2.98, ...z(1.92, 2.4), 'P', 0, DARK);
	S('Forearm');                                               // thick, flaring forearm
	B(-0.28, 0.28, 2.94, 3.5, ...z(1.96, 2.38), 'skin', R);
	B(-0.32, 0.32, 3.5, 4.0, ...z(1.92, 2.44), 'skin', R);
	S('PowerVein');                                             // glowing gold lightning vein down the forearm
	B(0.28, 0.3, 3.0, 3.5, ...z(2.12, 2.18), 'P', E, '#FFE14D');
	B(0.32, 0.34, 3.48, 3.96, ...z(2.04, 2.12), 'P', E, '#FFE14D');
	S('Wristband');
	B(-0.34, 0.34, 4.0, 4.12, ...z(1.9, 2.46), 'accent', E);
	S('Fist');
	B(-0.3, 0.34, 4.12, 4.5, ...z(1.92, 2.44), 'skin', R);
	S('Knuckle');                                               // individual clenched knuckles
	for (const k of [0, 1, 2, 3]) B(0.34, 0.4, 4.15 + k * 0.085, 4.22 + k * 0.085, ...z(1.98, 2.38), 'skin');
	S('Thumb');
	B(0.1, 0.38, 4.12, 4.24, ...z(1.84, 1.94), 'skin');
}

// --- strong legs (matching pair) with calves, in chunky red high-tops with glowing gold soles
for (const s of [1, -1]) {
	const zc = 0.42 * s;
	S('HipCollar');
	B(-0.22, 0.22, 1.62, 1.74, zc - 0.22, zc + 0.22, 'P', 0, DARK);
	S('Thigh');
	B(-0.2, 0.2, 1.12, 1.66, zc - 0.2, zc + 0.2, 'skin', R);
	S('KneeCollar');
	B(-0.21, 0.21, 1.06, 1.14, zc - 0.21, zc + 0.21, 'P', 0, DARK);
	S('Calf');
	B(-0.2, 0.2, 0.66, 1.08, zc - 0.2, zc + 0.2, 'skin', R);
	B(-0.26, -0.2, 0.74, 1.0, zc - 0.15, zc + 0.15, 'skin');
	S('HighTopCollar');
	B(-0.26, 0.26, 0.58, 0.7, zc - 0.25, zc + 0.25, 'P', 0, DARK);
	S('Sneaker');
	B(-0.28, 0.28, 0.1, 0.6, zc - 0.25, zc + 0.25, 'foot', R);
	S('ToeCap');
	B(0.28, 0.56, 0.1, 0.36, zc - 0.23, zc + 0.23, 'trim', R);
	S('SneakerStripe');
	B(-0.14, 0.32, 0.26, 0.34, s > 0 ? zc + 0.25 : zc - 0.27, s > 0 ? zc + 0.27 : zc - 0.25, 'trim');
	S('HeelTab');
	B(-0.32, -0.28, 0.3, 0.74, zc - 0.08, zc + 0.08, 'P', 0, DARK);
	S('Laces');
	B(0.28, 0.5, 0.36, 0.39, zc - 0.12, zc + 0.12, 'P', E, '#2EF2FF');
	S('Midsole');
	B(-0.29, 0.57, 0.04, 0.1, zc - 0.26, zc + 0.26, 'trim');
	S('Sole');
	B(-0.29, 0.57, 0, 0.04, zc - 0.26, zc + 0.26, 'accent', E);
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_031_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF7A00', lower: '#FFF3D6', stripe: '#2EF2FF', feather: '#FFC04D', feather2: '#FF2D95', skin: '#FF5418', skin2: '#2EE05A', prop: '#7A2BFF', foot: '#FF2D55', trim: '#FFFFFF', accent: '#FFD21A', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (Legendary flair): a gold flex aura, a citrus spritz from the leaf, and a gold shine off the belt
const passiveFx = [
	{ name: 'FlexAura', texture: 'sparkle', anchor: [0, 2.8, 0], rate: 8, lifetime: [1.0, 1.8], size: [0.26, 0.05], transparency: [0, 1], colors: ['#FFE14D', '#FF7A00'], lightEmission: 1, speed: [0.4, 0.9], spread: 180, rise: 0.3 },
	{ name: 'CitrusSpritz', texture: 'sparkle', anchor: [0, 4.2, 0.6], rate: 4, lifetime: [0.7, 1.2], size: [0.16, 0.04], transparency: [0, 1], colors: ['#C6FF3A', '#FFB020'], lightEmission: 1, speed: [0.5, 1.0], spread: 50, rise: -0.4 },
	{ name: 'BeltShine', texture: 'sparkle', anchor: [0.95, 1.97, 0], rate: 3, lifetime: [0.5, 0.9], size: [0.18, 0.04], transparency: [0, 1], colors: ['#FFFFFF', '#FFE14D'], lightEmission: 1, speed: [0.1, 0.3], spread: 120, rise: 0 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { noHead: true };
