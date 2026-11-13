// BRT_013 Cavallo Virtuoso — Voxel V4 build (CP-B, Uncommon, revision 2).
// Base: the accepted Studio sculpture (assets/remaining_roster/: recipes/BRT_013.json,
// previews/BRT_013_front.jpg and _rear.jpg):
// - a chestnut horse with an arched neck, pointed ears, a white blaze and a dark muzzle, emerging
//   from a crimson grand piano with a wine lid, ivory/black keys, gold pedals and rear strings
// - a black mane and tail, two giant black lace-up boots, big eyes with amber pupils
// Revision 3 (owner): a more "chad", handsome horse, keeping the anime eyes: thick neck, chiselled
//   face and cheekbones, square jaw and chin, confident smirk with a tooth sparkle, half-lidded
//   eyes, sharp brows, glossy swept-back pompadour mane.
// Revision 2 (owner):
// - head: a longer horse face, a bigger buck-toothed grin, a bigger mane with a forelock, smaller
//   brows
// - piano: thinner and sleeker
// - colours: a brighter horse, and more glow (neon gold strings and side trim)
// V4 core rules: kit anime eyes (Amber; lash, catchlights) on eye domes, a glowing Neon keyboard
// underglow, light-up soles, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x (the keyboard side).
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#131217';
const WOOD = '#5B2612';
const LACE = '#BFE6FF';

function tube(a, b, r0, r1, role) {
	const L = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
	const n = Math.max(1, Math.ceil(L / 0.24));
	for (let k = 0; k < n; k++) {
		const t0 = k / n, t1 = (k + 1) / n, r = r0 + (r1 - r0) * (t0 + t1) / 2;
		const c0 = a.map((v, i) => v + (b[i] - v) * t0), c1 = a.map((v, i) => v + (b[i] - v) * t1);
		B(Math.min(c0[0], c1[0]) - r, Math.max(c0[0], c1[0]) + r, Math.min(c0[1], c1[1]) - r, Math.max(c0[1], c1[1]) + r,
			Math.min(c0[2], c1[2]) - r, Math.max(c0[2], c1[2]) + r, role, R);
	}
}

// --- sleek crimson grand piano body (the Body), narrower curved back, wine lid, glowing gold trim
S('Body');
B(-0.78, 0.5, 1.45, 2.12, -0.9, 0.9, 'upper', R);
S('PianoBack');
B(-1.02, -0.78, 1.5, 2.08, -0.64, 0.64, 'upper', R);
B(-1.16, -1.02, 1.55, 2.02, -0.34, 0.34, 'upper', R);
S('Lid');
B(-0.8, 0.54, 2.12, 2.22, -0.93, 0.93, 'skin2', R);
B(-1.04, -0.8, 2.08, 2.18, -0.66, 0.66, 'skin2', R);
S('GoldTrim');
MZ(-0.78, 0.5, 1.98, 2.03, 0.9, 0.93, 'trim', E);
B(0.5, 0.54, 1.98, 2.03, -0.9, 0.9, 'trim', E);
// glowing gold strings over a wood soundboard at the rear of the lid
S('Soundboard');
B(-0.92, -0.3, 2.22, 2.25, -0.46, 0.46, 'P', 0, WOOD);
S('String');
for (const z of [-0.33, -0.165, 0, 0.165, 0.33]) B(-0.9, -0.33, 2.25, 2.28, z - 0.025, z + 0.025, 'trim', E);

// --- keyboard along the front: black key bed, ivory keys, black keys, glowing underglow
S('KeyBed');
B(0.5, 0.94, 1.52, 1.62, -0.88, 0.88, 'P', 0, INK);
S('WhiteKeys');
B(0.52, 0.92, 1.62, 1.7, -0.85, 0.85, 'lower', R);
S('BlackKeys');
for (const z of [-0.72, -0.6, -0.36, -0.24, -0.12, 0.11, 0.23, 0.46, 0.58, 0.7]) B(0.52, 0.74, 1.7, 1.77, z - 0.04, z + 0.04, 'P', 0, INK);
S('KeyGlow');
B(0.52, 0.96, 1.47, 1.52, -0.86, 0.86, 'stripe', E);
S('PedalLyre');
B(0.28, 0.4, 1.06, 1.46, -0.09, 0.09, 'P', 0, WOOD);
S('Pedal');
for (const z of [-0.15, 0, 0.15]) B(0.34, 0.6, 1.02, 1.08, z - 0.045, z + 0.045, 'trim');

// --- thick, strong chestnut neck rising from the piano top
S('Neck');
tube([0.0, 2.18, 0], [0.22, 3.1, 0], 0.44, 0.36, 'skin');

// --- handsome long horse head: skull, chiselled face with cheekbones, dark muzzle, strong square
// jaw and chin, confident smirk with a neat tooth line and a glinting sparkle, white blaze, ears
S('Head');
B(0.0, 0.72, 3.1, 4.02, -0.4, 0.4, 'skin', R);
B(0.1, 0.62, 4.02, 4.12, -0.3, 0.3, 'skin', R);
S('Face');
B(0.7, 1.36, 3.06, 3.66, -0.34, 0.34, 'skin', R);
S('Cheekbone');
MZ(0.6, 0.98, 3.28, 3.56, 0.38, 0.46, 'skin', R);
S('Muzzle');
B(1.34, 1.76, 2.96, 3.46, -0.33, 0.33, 'feather', R);
S('Jaw');                                                       // strong square jawline and chin
B(0.98, 1.68, 2.74, 2.98, -0.31, 0.31, 'skin', R);
B(1.48, 1.78, 2.7, 2.9, -0.23, 0.23, 'feather', R);
S('Nostril');
MZ(1.76, 1.78, 3.26, 3.36, 0.1, 0.22, 'P', 0, INK);
S('Mouth');                                                     // confident one-sided smirk
B(1.76, 1.78, 3.0, 3.06, -0.24, 0.2, 'P', 0, INK);
B(1.66, 1.78, 3.06, 3.16, 0.18, 0.28, 'P', 0, INK);
S('Teeth');
B(1.77, 1.8, 3.02, 3.06, -0.18, 0.16, 'lower');
S('ToothSparkle');
B(1.8, 1.82, 3.04, 3.16, 0.1, 0.14, 'P', E, '#FFFFFF');
B(1.8, 1.82, 3.08, 3.12, 0.06, 0.18, 'P', E, '#FFFFFF');
S('Blaze');
B(1.36, 1.4, 3.46, 3.66, -0.08, 0.08, 'lower');
B(0.88, 1.36, 3.66, 3.7, -0.08, 0.08, 'lower');
for (const s of [1, -1]) {
	S('Ear');
	B(0.08, 0.34, 4.02, 4.4, 0.16 * s, 0.4 * s, 'skin', R);
	B(0.14, 0.3, 4.4, 4.62, 0.22 * s, 0.36 * s, 'skin');
}
// confident half-lidded front anime eyes (Amber) under sharp brows angled up at the outer ends
const FX = 0.86;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.62, FX, 3.62, 4.2, 0.05 * out, 0.58 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.32 * out, top: 4.14, L: 0.9, H: 0.88, out, iris: 'Amber', lash: false, blush: false });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	const zin = eye.inner, zout = eye.outer, zm = (zin + zout) / 2;
	S('Lid');                                                   // level, relaxed upper lid
	B(FX, FX + 0.07, eye.whiteTop - 0.2, eye.whiteTop + 0.02, z0 - 0.03, z1 + 0.03, 'skin');
	B(FX, FX + 0.08, eye.whiteTop - 0.25, eye.whiteTop - 0.2, z0 - 0.02, z1 + 0.02, 'P', 0, INK);
	S('Brow');
	B(0.62, FX + 0.06, eye.whiteTop + 0.08, eye.whiteTop + 0.14, Math.min(zin, zm) - 0.02, Math.max(zin, zm), 'P', 0, INK);
	B(0.62, FX + 0.06, eye.whiteTop + 0.12, eye.whiteTop + 0.18, Math.min(zm, zout), Math.max(zm, zout) + 0.04, 'P', 0, INK);
}

// --- glossy swept-back pompadour mane flowing down the neck, with a sheen streak
S('Mane');
B(0.12, 0.74, 4.12, 4.5, -0.22, 0.22, 'foot', R);              // high pompadour
B(0.3, 0.84, 4.5, 4.68, -0.19, 0.19, 'foot', R);               // swept-up crown
B(0.66, 0.98, 4.36, 4.66, -0.17, 0.17, 'foot', R);             // swooping front curl
B(0.86, 1.02, 4.22, 4.42, -0.14, 0.14, 'foot');
B(-0.3, 0.2, 3.9, 4.36, -0.2, 0.2, 'foot', R);
B(-0.48, -0.14, 3.2, 4.0, -0.19, 0.19, 'foot', R);
B(-0.58, -0.28, 2.3, 3.3, -0.18, 0.18, 'foot', R);
MZ(-0.44, -0.18, 2.6, 3.6, 0.19, 0.27, 'foot');               // locks swept to the sides
S('ManeSheen');
B(0.36, 0.84, 4.68, 4.71, -0.06, 0.06, 'P', 0, '#4A4560');

// --- flowing black tail at the rear of the piano
S('Tail');
tube([-1.14, 1.8, 0], [-1.45, 1.2, 0.08], 0.15, 0.13, 'foot');
tube([-1.45, 1.2, 0.08], [-1.42, 0.6, 0.16], 0.13, 0.08, 'foot');

// --- two giant black lace-up boots under the piano, ice-blue laces, grey soles, light-up soles
for (const s of [1, -1]) {
	const zc = 0.44 * s;
	S('LegCollar');
	B(-0.28, 0.28, 1.36, 1.48, zc - 0.28, zc + 0.28, 'P', 0, DARK);
	S('BootShaft');
	tube([0.0, 1.4, zc], [0.02, 0.5, zc], 0.25, 0.27, 'foot');
	S('Boot');
	B(-0.36, 0.64, 0.12, 0.48, zc - 0.32, zc + 0.32, 'foot', R);
	B(0.64, 0.8, 0.12, 0.36, zc - 0.28, zc + 0.28, 'foot');
	S('Lace');
	for (const y of [0.62, 0.86, 1.1]) B(0.25, 0.3, y, y + 0.05, zc - 0.18, zc + 0.18, 'P', 0, LACE);
	S('BootSole');
	B(-0.38, 0.82, 0.04, 0.12, zc - 0.34, zc + 0.34, 'P', 0, '#49464F');
	S('Sole');
	B(-0.38, 0.82, 0, 0.04, zc - 0.34, zc + 0.34, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_013_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#E8231A', skin2: '#7A0C1A', trim: '#FFC21A', skin: '#FF8A1F', feather: '#5A2E1E', lower: '#FFF6D5', foot: '#1A1820', stripe: '#2EF2FF', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Rig (animation brief v5, 13 Nov 2026): biped. The arched neck (and the mane on it) swings from the top of
// the piano; the head nods on the neck. The piano lid stays rigid: the neck passes through it.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	neckY: 2.7,
	neck: { pivot: [0.03, 2.12, 0], slots: ['Neck'] },
	regions: [{ bone: 'Neck', region: [-0.7, -0.2, 2.2, 4.1, -0.3, 0.3], only: /^Mane$/ }],
};
