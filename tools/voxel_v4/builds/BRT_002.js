// BRT_002 Tralalero Toad — Voxel V4 build (CP-B).
// Identity (project original, accepted revision 4 in assets/BRT_002_Tralalero_Toad_Studio/):
// a squat, wide lime toad with two bulging eye domes on top, a huge croaking grin that
// wraps round the snout with a pink tongue, a golden-yellow belly and throat sac, violet
// hind thighs and big violet webbed feet. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const MOUTH = '#2A0F3A';

// --- squat wide torso with a low back hump; the belly almost touches the ground
S('Body');
B(-1.8, 1.4, 0.6, 2.0, -1.45, 1.45, 'upper', R);         // main mass (widest)
S('BodyCore');
B(-1.6, 1.2, 0.45, 2.15, -1.3, 1.3, 'upper', R);         // rounds the top and bottom edges
S('Hump');
B(-1.4, 0.9, 2.15, 2.37, -1.0, 1.0, 'upper', R);
// back warts (hot-pink poison-dart spots) with a few glowing cyan centres
S('Wart');
for (const [x, z] of [[-1.1, -0.55], [-0.5, 0.6], [0.2, -0.3], [-0.2, -0.95], [0.6, 0.75], [-1.3, 0.9]]) {
	B(x - 0.21, x + 0.21, 2.15, 2.47, z - 0.21, z + 0.21, 'stripe', R);
}
S('WartGlow');
for (const [x, z] of [[-1.1, -0.55], [-0.5, 0.6], [0.6, 0.75]]) B(x - 0.09, x + 0.09, 2.47, 2.51, z - 0.09, z + 0.09, 'accent', E);
// golden belly and throat sac (bulging forward under the chin)
S('Belly');
B(-1.3, 1.55, 0.25, 1.45, -1.15, 1.15, 'lower', R);
B(-1.0, 1.3, 0.12, 0.27, -0.85, 0.85, 'lower', R);
S('ThroatSac');
B(1.5, 2.45, 0.77, 1.35, -0.72, 0.72, 'lower', R);

// --- head: broad, flat-topped, with a rounded snout
S('Head');
B(0.9, 2.3, 1.15, 2.45, -1.25, 1.25, 'upper', R);
B(1.0, 2.1, 2.45, 2.57, -1.0, 1.0, 'upper', R);
S('Snout');
B(2.3, 2.65, 1.3, 2.17, -1.0, 1.0, 'upper', R);
// --- two big bulging eye domes on top, front-facing anime eyes, violet brows
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.2, 2.25, 2.3, 3.55, 0.2 * out, 1.32 * out, 'upper', R);
	B(1.32, 2.13, 3.55, 3.7, 0.32 * out, 1.2 * out, 'upper', R);
	const eye = frontEye({ faceX: 2.25, zc: 0.76 * out, top: 3.42, L: 1.1, H: 1.3, out, iris: 'Violet', lash: false, blush: false });
	S('Brow');
	B(2.23, 2.36, 3.46, 3.6, Math.min(eye.inner, eye.outer) - 0.04, Math.max(eye.inner, eye.outer) + 0.04, 'trim');
}
// --- huge croaking grin wrapping round the snout, violet lower lip, pink tongue
S('Mouth');
B(2.65, 2.69, 1.41, 1.65, -0.86, 0.86, 'P', 0, MOUTH);
MZ(2.65, 2.69, 1.65, 1.83, 0.82, 1.0, 'P', 0, MOUTH);                 // raised corners
MZ(2.3, 2.65, 1.67, 1.79, 1.0, 1.04, 'P', 0, MOUTH);                  // grin round the snout sides
MZ(1.6, 2.3, 1.75, 1.87, 1.25, 1.29, 'P', 0, MOUTH);                  // ...and back along the cheeks
S('Lip');
B(2.65, 2.73, 1.33, 1.42, -0.86, 0.86, 'trim');
S('Tongue');
B(2.62, 2.76, 1.15, 1.47, -0.28, 0.14, 'P', 0, '#FF3D6E');
S('Nostril');
MZ(2.65, 2.69, 1.99, 2.07, 0.18, 0.3, 'P', 0, MOUTH);

// --- front legs: short lime arms splayed outward onto violet webbed hands
for (const s of [1, -1]) {
	S('Arm');
	B(0.95, 1.3, 0.4, 1.0, 1.22 * s, 1.55 * s, 'skin', R);
	B(1.12, 1.46, 0.18, 0.62, 1.46 * s, 1.8 * s, 'skin', R);
	S('WristCollar');
	B(1.09, 1.49, 0.14, 0.22, 1.43 * s, 1.83 * s, 'P', 0, DARK);
	S('Hand');
	B(1.05, 1.9, 0, 0.16, 1.3 * s, 2.0 * s, 'foot', R);
	for (const dz of [-0.25, 0, 0.25]) B(1.9, 2.18, 0, 0.12, (1.65 + dz - 0.09) * s, (1.65 + dz + 0.09) * s, 'foot');
}
// --- hind legs: big rounded violet thighs folded at the sides, huge violet webbed feet
for (const s of [1, -1]) {
	S('Thigh');
	B(-2.0, -0.45, 0.3, 1.45, 1.15 * s, 1.8 * s, 'skin2', R);
	B(-1.85, -0.6, 0.2, 1.6, 1.25 * s, 1.7 * s, 'skin2', R);
	B(-1.75, -0.7, 0.42, 1.35, 1.8 * s, 1.88 * s, 'skin2', R);
	S('AnkleCollar');
	B(-1.3, -0.7, 0.14, 0.22, 1.28 * s, 1.72 * s, 'P', 0, DARK);
	S('Foot');
	B(-1.2, 0.1, 0, 0.16, 1.2 * s, 2.1 * s, 'foot', R);
	for (const dz of [-0.3, 0, 0.3]) B(0.1, 0.42, 0, 0.12, (1.65 + dz - 0.1) * s, (1.65 + dz + 0.1) * s, 'foot');
}

// Revision 2 (owner, 4 Nov): dopamine high-contrast palette. Project-derived default palette (docs/creatures/V4/BRT_002_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#2BEA3F', lower: '#FFE600', stripe: '#FF2D95', trim: '#2416C9', skin: '#3D86FF', skin2: '#2F6BFF', foot: '#FF7A00', accent: '#3DF5FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
