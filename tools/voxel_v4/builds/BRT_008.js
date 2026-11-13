// BRT_008 Lirili Larila — Voxel V4 build (CP-B, revision 2).
// Follows the accepted Studio sculpture (assets/BRT_008_Lirili_Larila_Studio/) for the head:
// - a big faceted grey elephant head with a brash cartoon scowl (angular lids, thick low brows)
// - large cupped ears with pink inner ears, an oversized hanging trunk curling up at the tip, and
//   two ivory tusks
// Revision 2 (owner): a more anthropomorphic, defined humanoid cactus body (broad chest and
// shoulders, narrow waist, hips, thighs, knees, shins); saguaro cactus arms bent up at the elbows;
// bigger sandals in new colours (electric purple, hot-pink straps); bolder greens; more colour
// accents (magenta cactus flowers).
// V4 core rules: kit anime eyes (Amber) under scowl lids, a glowing Neon collar between head and
// body, light-up sandal soles, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const IVORY = '#FFF6DE';
const BROW = '#22262E';

// --- glowing collar where the head sits on the cactus body
S('Collar');
B(-0.6, 0.6, 2.54, 2.64, -0.6, 0.6, 'stripe', E);

// --- big faceted grey elephant head with a smooth face plate
S('Head');
B(-0.6, 0.72, 2.62, 4.08, -0.72, 0.72, 'skin', R);
B(-0.72, 0.6, 2.76, 3.94, -0.6, 0.6, 'skin', R);
B(-0.5, 0.62, 4.08, 4.24, -0.56, 0.56, 'skin', R);              // dome
B(0.56, 0.86, 2.86, 3.96, -0.62, 0.62, 'skin', 0);              // face plate
// tough anime eyes (Amber) under angular scowl lids and thick low V brows
const FX = 0.86;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.32 * out, top: 3.8, L: 0.92, H: 1.02, out, iris: 'Amber', lash: false, blush: false });
	const zin = eye.inner, zout = eye.outer, zm = (zin + zout) / 2;
	const lo = Math.min, hi = Math.max;
	S('Lid');                                    // the lid drops lower toward the inner corner (scowl)
	B(FX, FX + 0.08, eye.whiteTop - 0.14, eye.whiteTop + 0.02, lo(zm, zout) - 0.03, hi(zm, zout) + 0.03, 'skin');
	B(FX, FX + 0.08, eye.whiteTop - 0.3, eye.whiteTop + 0.02, lo(zin, zm) - 0.03, hi(zin, zm) + 0.03, 'skin');
	B(FX, FX + 0.09, eye.whiteTop - 0.19, eye.whiteTop - 0.14, lo(zm, zout) - 0.02, hi(zm, zout) + 0.02, 'P', 0, '#000000');
	B(FX, FX + 0.09, eye.whiteTop - 0.35, eye.whiteTop - 0.3, lo(zin, zm) - 0.02, hi(zin, zm) + 0.02, 'P', 0, '#000000');
	S('Brow');                                   // thick V brows, low at the inner end
	B(FX, FX + 0.14, eye.whiteTop + 0.02, eye.whiteTop + 0.16, lo(zm, zout) - 0.05, hi(zm, zout) + 0.06, 'P', 0, BROW);
	B(FX, FX + 0.14, eye.whiteTop - 0.08, eye.whiteTop + 0.06, lo(zin, zm) + (out > 0 ? 0.06 : -0.02), hi(zin, zm) + (out > 0 ? 0.02 : -0.06), 'P', 0, BROW);   // gap between the brows
}

// --- big cupped ears flared to the sides, warm pink inner ears facing forward
for (const s of [1, -1]) {
	S('Ear');
	B(-0.2, 0.02, 3.72, 4.0, 0.7 * s, 1.36 * s, 'skin', R);
	B(-0.2, 0.02, 3.0, 3.72, 0.7 * s, 1.66 * s, 'skin', R);
	B(-0.2, 0.02, 2.72, 3.0, 0.78 * s, 1.42 * s, 'skin', R);
	S('InnerEar');
	B(0.02, 0.06, 3.06, 3.74, 0.88 * s, 1.5 * s, 'skin2');
}

// --- oversized hanging trunk curling forward and up at the tip, darker wrinkle rings, tusks
S('Trunk');
B(0.82, 1.12, 2.6, 3.14, -0.2, 0.2, 'skin', R);
B(0.86, 1.14, 1.9, 2.6, -0.17, 0.17, 'skin', R);
B(0.9, 1.16, 1.42, 1.9, -0.15, 0.15, 'skin', R);
B(1.12, 1.48, 1.42, 1.66, -0.14, 0.14, 'skin', R);              // curl forward
B(1.36, 1.56, 1.6, 1.96, -0.12, 0.12, 'skin', R);               // ...and up
S('TrunkWrinkle');
B(1.12, 1.15, 2.3, 2.36, -0.15, 0.15, 'P', 0, '#7E879C');
B(1.14, 1.17, 1.98, 2.04, -0.14, 0.14, 'P', 0, '#7E879C');
S('TrunkTip');
B(1.38, 1.54, 1.96, 2.0, -0.08, 0.08, 'P', 0, DARK);
S('Tusk');
MZ(0.86, 1.36, 2.66, 2.86, 0.22, 0.4, 'P', 0, IVORY);
MZ(1.22, 1.42, 2.84, 3.1, 0.24, 0.38, 'P', 0, IVORY);

// --- the head assembly above was modelled sitting on a 2.6 neck; raise it onto the taller body
for (const p of parts) { p.min[1] += 0.4; p.max[1] += 0.4; }

// --- anthropomorphic cactus body: broad chest and shoulders (the Body), narrow waist, hips
S('Body');
B(-0.55, 0.55, 2.15, 2.95, -0.68, 0.68, 'upper', R);
S('Shoulders');
B(-0.5, 0.5, 2.62, 3.0, -0.8, 0.8, 'upper', R);
B(-0.62, 0.62, 2.25, 2.85, -0.56, 0.56, 'upper', R);
S('Waist');
B(-0.42, 0.42, 1.88, 2.18, -0.46, 0.46, 'upper', R);
S('Hips');
B(-0.5, 0.5, 1.6, 1.9, -0.58, 0.58, 'upper', R);
S('CactusRib');                                  // bold lime ribs on chest, waist and back
for (const z of [-0.3, 0.3]) {
	B(0.6, 0.67, 2.2, 2.9, z - 0.06, z + 0.06, 'feather');
	B(-0.67, -0.6, 2.2, 2.9, z - 0.06, z + 0.06, 'feather');
}
B(0.42, 0.48, 1.62, 2.16, -0.06, 0.06, 'feather');
MZ(-0.06, 0.06, 2.2, 2.92, 0.68, 0.74, 'feather');
S('Spine');
for (const [y, z] of [[2.4, -0.3], [2.75, 0.3], [2.5, 0.3]]) B(0.67, 0.75, y, y + 0.05, z - 0.02, z + 0.02, 'P', 0, '#FFFFFF');

// --- saguaro cactus arms: out from the shoulders, bending up at the elbows, ribs and spines
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(0.06, 0.44, 2.5, 2.9, 0.78 * s, 0.86 * s, 'P', 0, DARK);
	S('CactusArm');
	B(0.1, 0.42, 2.52, 2.84, 0.84 * s, 1.36 * s, 'upper', R);       // upper arm out to the side
	B(0.1, 0.42, 2.52, 3.22, 1.18 * s, 1.5 * s, 'upper', R);         // forearm raised
	B(0.14, 0.38, 3.22, 3.32, 1.22 * s, 1.46 * s, 'upper', R);       // rounded top
	S('CactusRib');
	B(0.42, 0.46, 2.6, 3.2, 1.3 * s, 1.38 * s, 'feather');
	S('Spine');
	B(0.46, 0.52, 2.9, 2.94, 1.32 * s, 1.36 * s, 'P', 0, '#FFFFFF');
	B(0.24, 0.28, 2.68, 2.72, 1.5 * s, 1.56 * s, 'P', 0, '#FFFFFF');
}

// --- magenta cactus flowers on the head and the right arm, gold centres
function flower(x, y, z) {
	S('Flower');
	B(x - 0.3, x + 0.3, y, y + 0.14, z - 0.12, z + 0.12, 'feather2', R);
	B(x - 0.12, x + 0.12, y, y + 0.14, z - 0.3, z + 0.3, 'feather2', R);
	S('FlowerCentre');
	B(x - 0.09, x + 0.09, y + 0.14, y + 0.2, z - 0.09, z + 0.09, 'P', 0, '#FFD447');
}
flower(0.06, 4.64, 0.22);
flower(0.26, 3.32, 1.34);

// --- defined legs: thighs, knees, shins (dark collars at hips), green three-toed feet with cream
// nails, oversized purple sandals with hot-pink straps and light-up soles
for (const s of [1, -1]) {
	const zc = 0.32 * s;
	S('HipCollar');
	B(-0.26, 0.26, 1.52, 1.64, zc - 0.26, zc + 0.26, 'P', 0, DARK);
	S('Thigh');
	B(-0.22, 0.22, 1.1, 1.6, zc - 0.22, zc + 0.22, 'upper', R);
	S('Knee');
	B(-0.2, 0.26, 0.98, 1.16, zc - 0.21, zc + 0.21, 'upper', R);
	S('Shin');
	B(-0.18, 0.18, 0.5, 1.02, zc - 0.18, zc + 0.18, 'upper', R);
	S('CactusRib');
	B(0.18, 0.22, 0.56, 0.96, zc - 0.04, zc + 0.04, 'feather');
	B(0.22, 0.26, 1.16, 1.56, zc - 0.04, zc + 0.04, 'feather');
	const fz = 0.48 * s;
	S('Foot');
	B(-0.3, 0.52, 0.26, 0.54, fz - 0.24, fz + 0.24, 'foot', R);
	S('Toenail');
	for (const dz of [-0.15, 0, 0.15]) B(0.52, 0.6, 0.28, 0.4, fz + dz - 0.06, fz + dz + 0.06, 'P', 0, IVORY);
	S('SandalSole');
	B(-0.56, 0.8, 0.06, 0.26, fz - 0.3, fz + 0.3, 'trim', R);
	S('SandalStrap');
	B(-0.08, 0.08, 0.26, 0.6, fz - 0.28, fz + 0.28, 'prop');
	B(0.28, 0.4, 0.26, 0.5, fz - 0.27, fz + 0.27, 'prop');
	S('Buckle');
	B(-0.06, 0.06, 0.44, 0.54, fz + 0.28 * s, fz + 0.32 * s, 'P', 0, '#FFD447');
	S('Sole');
	B(-0.56, 0.8, 0, 0.06, fz - 0.3, fz + 0.3, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_008_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#0FA63A', feather: '#C6FF1A', feather2: '#FF4FD8', skin: '#A9B4CC', skin2: '#FF7FB0', trim: '#5B2BFF', prop: '#FF2D95', foot: '#0B8A30', stripe: '#FF3DD1', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Rig (animation brief v5, 13 Nov 2026): the trunk hangs from its own bone on the head (signature prop), so
// it can swing, lift and trumpet. Tusks, ears and flowers stay rigid with the head.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	extraBones: { Trunk: { parent: 'Head', pivot: [0.97, 3.4, 0] } },
	slots: { CactusRib: 'Torso', Spine: 'Torso', Flower: 'Head', FlowerCentre: 'Head', Trunk: 'Trunk', TrunkWrinkle: 'Trunk', TrunkTip: 'Trunk' },
};
