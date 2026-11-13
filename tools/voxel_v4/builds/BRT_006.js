// BRT_006 Spaghetti Crocodilo — Voxel V4 build (CP-B, revision 3).
// Base: the accepted Studio sculpture (assets/BRT_006_Spaghetti_Crocodilo_Studio/, revision 3):
// - a low green crocodile with a long flat leaf-green snout, a long closed grin with ivory teeth,
//   and matching raised eye housings
// - forest-green dorsal ridges and legs, leaf-green feet with ivory claws, a buff belly and a
//   tapered tail
// - golden and pale-wheat spaghetti on the back, draped down the flanks and hanging from the mouth
// Revision 3 (owner): the body is back to green (revision 2's spaghetti-wrapped body is undone), the
// spaghetti hair is removed. Revision 4: the loops are removed; the pile is a solid stepped heap with
// wavy noodle strands across it and a big meatball on top (sauce, basil), which gives the height the
// 14-stud envelope needs. No fork.
// V4 core rules: kit anime eyes (Candy; lash, catchlights), two-tone with a glowing Neon waterline
// along the flanks, light-up soles, studs on body panels only, dark joint collars.
// Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const MOUTH = '#123018';
const IVORY = '#FFF6DE';
const SAUCE = '#FF3B24';

// --- low body: deeper green above a glowing waterline, buff belly below (the Body is the top box)
const WL = 0.86;
S('Body');
B(-1.5, 0.95, WL + 0.1, 1.45, -0.95, 0.95, 'upper', R);
S('BodyRound');
B(-1.35, 0.8, WL + 0.1, 1.55, -0.75, 0.75, 'upper', R);
B(-1.65, 1.1, WL + 0.1, 1.32, -0.78, 0.78, 'upper', R);
S('Belly');
B(-1.5, 0.95, 0.42, WL, -0.95, 0.95, 'lower', R);
B(-1.3, 0.8, 0.34, 0.42, -0.72, 0.72, 'lower', R);
S('Waterline');
B(-1.52, 0.97, WL, WL + 0.1, -0.97, 0.97, 'stripe', E);
// dorsal ridges along the back
S('Ridge');
for (const x of [-1.25, -0.85, 0.55]) MZ(x - 0.12, x + 0.12, 1.55, 1.72, 0.22, 0.42, 'skin2', R);

// --- head block behind the snout, raised eye housings on top facing forward
S('Head');
B(0.9, 1.6, 0.44, 1.38, -0.86, 0.86, 'skin', R);
for (const s of [1, -1]) {
	S('EyeHousing');
	B(1.0, 1.6, 1.3, 2.12, 0.14 * s, 0.88 * s, 'skin', 0);
}
// big forward anime eyes (Candy) on the housings, dark-green brows
const FX = 1.6;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.5 * out, top: 2.04, L: 0.98, H: 1.08, out, iris: 'Candy', lash: true, blush: false });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Brow');
	B(1.0, FX + 0.1, eye.lashTop + 0.02, eye.lashTop + 0.12, z0 - 0.02, z1 + 0.02, 'trim');
}

// --- long flat snout: leaf-green upper and lower jaws, dark grin line rising at the back,
// ivory teeth along the sides and front, nostrils on top
S('Snout');
B(1.6, 3.2, 0.8, 1.16, -0.64, 0.64, 'skin', R);               // upper jaw
B(1.6, 3.12, 0.42, 0.72, -0.6, 0.6, 'skin', R);                // lower jaw
S('Mouth');
B(1.6, 3.21, 0.72, 0.8, -0.62, 0.62, 'P', 0, MOUTH);
MZ(1.3, 1.62, 0.78, 0.96, 0.86, 0.88, 'P', 0, MOUTH);           // grin corners curl up on the head
S('Tooth');
for (const x of [1.85, 2.25, 2.65, 3.0]) MZ(x - 0.09, x + 0.09, 0.54, 0.8, 0.6, 0.67, 'P', 0, IVORY);
MZ(3.19, 3.28, 0.54, 0.8, 0.18, 0.36, 'P', 0, IVORY);
S('Nostril');
MZ(2.95, 3.09, 1.16, 1.2, 0.14, 0.28, 'P', 0, DARK);

// --- tapered tail curling up at the tip, with ridges
S('Tail');
B(-2.0, -1.5, 0.6, 1.3, -0.62, 0.62, 'upper', R);
B(-2.4, -2.0, 0.66, 1.16, -0.44, 0.44, 'upper', R);
B(-2.65, -2.4, 0.74, 1.12, -0.3, 0.3, 'upper', R);
B(-2.8, -2.55, 1.08, 1.56, -0.2, 0.2, 'upper', R);
S('Ridge');
MZ(-2.25, -2.05, 1.16, 1.3, 0.1, 0.26, 'skin2');

// --- four planted forest-green legs with dark collars, leaf-green feet, ivory claws, light-up soles
for (const x of [0.55, -1.15]) for (const s of [1, -1]) {
	S('LegCollar');
	B(x - 0.32, x + 0.32, 0.86, 1.0, 0.86 * s, 1.0 * s, 'P', 0, DARK);
	S('Leg');
	B(x - 0.28, x + 0.28, 0.3, 1.02, 0.95 * s, 1.36 * s, 'skin2', R);
	S('Foot');
	B(x - 0.3, x + 0.46, 0.06, 0.32, 0.92 * s, 1.46 * s, 'skin', R);
	S('Claw');
	for (const dz of [-0.17, 0, 0.17]) B(x + 0.46, x + 0.56, 0.08, 0.2, (1.19 + dz - 0.05) * s, (1.19 + dz + 0.05) * s, 'P', 0, IVORY);
	S('Sole');
	B(x - 0.3, x + 0.46, 0, 0.06, 0.94 * s, 1.44 * s, 'accent', E);
}

// --- spaghetti draped down both flanks and one strand hanging from the mouth
S('SpaghettiStrand');
for (const s of [1, -1]) for (const x of [-0.95, 0.15]) {
	B(x - 0.06, x + 0.06, 0.7, 1.62, 0.96 * s, 1.02 * s, 'feather2');
	B(x - 0.06, x + 0.2, 0.62, 0.72, 0.96 * s, 1.02 * s, 'feather2');      // little curl at the end
}
B(2.6, 2.68, 0.05, 0.74, 0.3, 0.38, 'feather2');
B(2.46, 2.68, 0.05, 0.13, 0.3, 0.38, 'feather2');
B(2.4, 2.48, 0.05, 0.3, 0.3, 0.38, 'feather2');

// --- solid stepped heap of spaghetti on the back (no loops), wavy noodle strands lying across its
// surface, a big round meatball on top with tomato sauce and a basil leaf
const PX = -0.35;
S('SpaghettiHeap');
for (const [y0, y1, r, role] of [[1.5, 1.76, 0.8, 'feather'], [1.76, 2.0, 0.64, 'feather2'], [2.0, 2.2, 0.48, 'feather']]) {
	B(PX - r, PX + r, y0, y1, -0.74 * r, 0.74 * r, role, R);
	B(PX - 0.74 * r, PX + 0.74 * r, y0, y1, -r, r, role, R);
}
S('NoodleStrand');                                 // wavy strands lying over the heap
for (const [x0, x1, y, z, role] of [
	[PX - 0.78, PX - 0.2, 1.7, 0.62, 'feather2'], [PX - 0.22, PX + 0.5, 1.64, 0.6, 'feather2'],
	[PX - 0.7, PX - 0.1, 1.68, -0.62, 'feather2'], [PX - 0.12, PX + 0.55, 1.62, -0.6, 'feather2'],
	[PX - 0.6, PX + 0.1, 1.94, 0.5, 'feather'], [PX - 0.1, PX + 0.5, 1.9, -0.48, 'feather'],
]) B(x0, x1, y, y + 0.1, z - 0.06, z + 0.06, role);
const MX = PX - 0.05;
S('Meatball');
B(MX - 0.42, MX + 0.42, 2.14, 2.76, -0.3, 0.3, 'prop', R);
B(MX - 0.3, MX + 0.3, 2.14, 2.76, -0.42, 0.42, 'prop', R);
B(MX - 0.3, MX + 0.3, 2.06, 2.86, -0.3, 0.3, 'prop', R);
S('Sauce');
B(MX - 0.24, MX + 0.24, 2.86, 2.9, -0.2, 0.2, 'P', 0, SAUCE);
B(MX + 0.3, MX + 0.34, 2.24, 2.76, -0.08, 0.06, 'P', 0, SAUCE);
B(MX - 0.08, MX + 0.06, 2.3, 2.76, 0.42, 0.46, 'P', 0, SAUCE);
B(PX + 0.18, PX + 0.5, 2.2, 2.24, -0.3, 0.06, 'P', 0, SAUCE);          // sauce pooled on the heap
B(PX + 0.4, PX + 0.46, 1.92, 2.2, -0.2, -0.08, 'P', 0, SAUCE);
S('Basil');
B(MX - 0.12, MX + 0.14, 2.9, 2.95, -0.04, 0.16, 'skin');

// Dopamine high-contrast palette (docs/creatures/V4/BRT_006_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#1FBF4A', lower: '#FFE6A8', stripe: '#2EF2FF', trim: '#0B4A22', skin: '#7CFF3A', skin2: '#0E7A3A', feather: '#FFC21A', feather2: '#FFEFA8', prop: '#8B3A1E', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig (animation brief v5, 13 Nov 2026): the meatball (with the sauce and basil on it) sits on its own bone
// on top of the spaghetti heap (signature prop), so it can bounce, wobble and be launched.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	extraBones: { Meatball: { parent: 'Torso', pivot: [-0.4, 2.2, 0] } },
	regions: [{ bone: 'Meatball', region: [-0.85, 0.05, 2.25, 3.0, -0.5, 0.5], only: /^(Meatball|Sauce|Basil)$/ }],
};
