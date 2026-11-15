// BRT_001 Bingus Baguette — Voxel V4 build (CP-B, first species after CP-A approval).
// Identity: "Bingus", the pink hairless sphynx-cat meme, fused with a long golden
// baguette: the loaf is the cat's torso, the wrinkly pink sphynx head grows from its
// front end, with huge bat-like ears, four short pink legs and a thin hairless tail.
// Five diagonal cream scores run along the top crust. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';

// --- baguette torso: long stepped-octagon loaf with tapered, rounded ends
S('Body');
B(-3.0, 2.3, 1.0, 2.5, -0.66, 0.66, 'upper', R);          // loaf core
S('LoafRound');
B(-3.0, 2.3, 1.15, 2.35, -0.82, 0.82, 'upper', R);        // rounds the long edges
S('LoafEnd');
B(-3.45, -3.0, 1.18, 2.32, -0.56, 0.56, 'upper', R);      // rear taper
B(-3.8, -3.45, 1.42, 2.08, -0.34, 0.34, 'upper', R);      // pointed crust tip
S('CrustDome');
B(-2.75, 2.05, 2.5, 2.6, -0.62, 0.62, 'upper', R);         // puffed top crust under the scores
S('Belly');
B(-2.9, 2.2, 0.96, 1.12, -0.6, 0.6, 'lower', R);          // pale underside crust
S('CrustEdge');
for (const s of [1, -1]) B(-2.9, 2.2, 1.12, 1.2, 0.8 * s, 0.84 * s, 'trim');
// --- five diagonal scores across the top: dark baked rim, cream open crumb, warm glow centre
S('Score');
for (let i = 0; i < 5; i++) {
	const cx = -2.45 + i * 0.95;
	for (const [dz, dx] of [[-0.4, -0.2], [0, 0], [0.4, 0.2]]) {
		B(cx + dx - 0.26, cx + dx + 0.26, 2.6, 2.64, dz - 0.22, dz + 0.22, 'trim');
		B(cx + dx - 0.2, cx + dx + 0.2, 2.64, 2.74, dz - 0.18, dz + 0.18, 'stripe', R);
	}
	S('ScoreGlow');
	B(cx - 0.08, cx + 0.08, 2.74, 2.77, -0.1, 0.1, 'accent', E);
	S('Score');
}

// --- Bingus head: big pink hairless sphynx head growing from the loaf's front end
S('Head');
B(2.2, 3.7, 1.6, 3.55, -0.96, 0.96, 'skin', R);
B(2.3, 3.8, 1.75, 3.4, -1.06, 1.06, 'skin', R);           // cheeks (wide, rounded)
B(2.35, 3.6, 3.55, 3.72, -0.78, 0.78, 'skin', R);         // crown
// forehead wrinkles (sphynx folds)
S('Wrinkle');
for (const [y, w] of [[3.46, 0.42], [3.58, 0.3]]) B(3.8, 3.84, y, y + 0.05, -w, w, 'skin2');
for (const s of [1, -1]) B(2.6, 3.4, 2.0, 2.06, 1.06 * s, 1.1 * s, 'skin2');   // cheek fold
// huge broad bat-like ears, stepped outward to a point, with darker pink inner ear on the front
for (const s of [1, -1]) {
	S('Ear');
	for (const [y0, y1, z0, z1] of [[3.5, 3.85, 0.3, 1.12], [3.85, 4.2, 0.48, 1.16], [4.2, 4.5, 0.68, 1.18], [4.5, 4.72, 0.88, 1.18]]) {
		B(2.75, 3.15, y0, y1, z0 * s, z1 * s, 'skin', R);
	}
	S('InnerEar');
	B(3.15, 3.19, 3.62, 3.95, 0.5 * s, 1.0 * s, 'skin2');
	B(3.15, 3.19, 3.95, 4.38, 0.68 * s, 1.06 * s, 'skin2');
}
// face: big front anime eyes (Lime, the sphynx's pale green stare), muzzle, nose, smile, tongue
const FX = 3.8;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.46 * out, top: 3.3, L: 1.0, H: 1.34, out, iris: 'Lime', lash: false, blush: false });
	S('Lid');                                              // droopy, unimpressed upper lids
	B(FX, FX + 0.08, eye.whiteTop - 0.16, eye.whiteTop + 0.02, Math.min(eye.inner, eye.outer) - 0.03, Math.max(eye.inner, eye.outer) + 0.03, 'skin');
	B(FX, FX + 0.09, eye.whiteTop - 0.22, eye.whiteTop - 0.16, Math.min(eye.inner, eye.outer) - 0.02, Math.max(eye.inner, eye.outer) + 0.02, 'P', 0, '#000000');
}
S('Muzzle');
B(FX, FX + 0.3, 1.95, 2.45, -0.44, 0.44, 'skin', R);
B(FX, FX + 0.22, 1.85, 1.95, -0.3, 0.3, 'skin');          // chin
S('Nose');
B(FX + 0.3, FX + 0.36, 2.32, 2.48, -0.13, 0.13, 'P', 0, '#B5455C');
S('Mouth');
B(FX + 0.3, FX + 0.32, 2.06, 2.12, -0.3, 0.3, 'P', 0, '#6e0e2c');
MZ(FX + 0.3, FX + 0.32, 2.12, 2.2, 0.3, 0.36, 'P', 0, '#6e0e2c');                // smile corners
S('Tongue');
B(FX + 0.24, FX + 0.34, 1.86, 2.07, 0.02, 0.2, 'P', 0, '#FF7FA0');
S('Whisker');                                               // sparse sphynx whiskers
for (const s of [1, -1]) for (const y of [2.18, 2.32]) B(FX + 0.1, FX + 0.16, y, y + 0.04, 0.44 * s, 1.24 * s, 'P', 0, '#F6E9EA');

// --- four short pink legs on round paws, dark joint collars where they meet the loaf
for (const x of [1.55, -2.35]) for (const s of [1, -1]) {
	const zc = 0.5 * s;
	S('HipCollar');
	B(x - 0.27, x + 0.27, 0.9, 1.04, zc - 0.27, zc + 0.27, 'P', 0, DARK);
	S('Leg');
	B(x - 0.21, x + 0.21, 0.3, 0.96, zc - 0.21, zc + 0.21, 'skin', R);
	S('Paw');
	B(x - 0.3, x + 0.38, 0, 0.32, zc - 0.29, zc + 0.29, 'foot', R);
	for (const dz of [-0.17, 0, 0.17]) B(x + 0.38, x + 0.42, 0.04, 0.16, zc + dz - 0.06, zc + dz + 0.06, 'P', 0, '#262a3a');
}

// --- thin hairless tail rising from the rear crust tip in a hooked curl
S('Tail');
for (const [x0, x1, y0, y1] of [[-4.05, -3.7, 1.7, 1.95], [-4.25, -3.98, 1.9, 2.5], [-4.35, -4.1, 2.45, 3.1], [-4.3, -4.05, 3.05, 3.45], [-4.1, -3.85, 3.35, 3.55]]) {
	B(x0, x1, y0, y1, -0.12, 0.12, 'skin', R);
}

// Reference-derived default palette (docs/creatures/V4/BRT_001_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#D98A2B', lower: '#F2C46B', stripe: '#FFE7A8', trim: '#9A4E17', skin: '#EFA3AE', skin2: '#D97888', foot: '#F7BEC6', accent: '#FFC861', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
