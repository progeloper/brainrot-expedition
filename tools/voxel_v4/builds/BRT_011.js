// BRT_011 Glorbo Fruttodrillo — Voxel V4 build (CP-B, Uncommon, revision 2).
// Base: the accepted Studio sculpture (assets/BRT_011_Glorbo_Fruttodrillo_Studio/):
// - a watermelon torso with stripes and a crocodile head with an open toothy grin
// - protruding eyes with brows, seeded watermelon-slice fins along the back
// - four splayed clawed crocodile legs and a tail
// Revision 2 (owner):
// - head: a bigger, longer snout, smaller eye domes, more teeth and a meaner look
// - body: longer (an oval melon), bolder zig-zag stripes and a darker rind
// Revision 3 (owner): an even longer body (1.85x oval, four stripes); fins taller to keep the
//   14-stud envelope
// - tail: longer, running along the ground
// V4 core rules: kit anime eyes (Amber; lash, catchlights) on the eye domes under mean V-brows, a
// glowing Neon seam where the head meets the melon, light-up soles, studs on body panels only, dark
// joint collars. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const IVORY = '#FFF6DE';
const SEED = '#1A1410';
const MOUTH = '#4A0E2A';

const rAt = (cy, R0, y0, y1) => Math.sqrt(Math.max(0.03, R0 * R0 - Math.pow((y0 + y1) / 2 - cy, 2)));
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

// --- long oval watermelon torso (stepped ellipsoid stretched 1.85x along x), dark rind
const CX = -0.95, CY = 1.25, RAD = 1.0, SX = 1.85;
function oval(y0, y1, r, role) {
	B(CX - SX * r, CX + SX * r, y0, y1, -0.7 * r, 0.7 * r, role, R);
	B(CX - SX * 0.7 * r, CX + SX * 0.7 * r, y0, y1, -r, r, role, R);
}
S('Body');
B(CX - SX * RAD, CX + SX * RAD, 0.95, 1.55, -0.7 * RAD, 0.7 * RAD, 'upper', R);
S('MelonRound');
B(CX - SX * 0.68 * RAD, CX + SX * 0.68 * RAD, 0.95, 1.55, -RAD, RAD, 'upper', R);
for (const [y0, y1] of [[0.35, 0.6], [0.6, 0.95], [1.55, 1.9], [1.9, 2.15]]) oval(y0, y1, rAt(CY, RAD, y0, y1), 'upper');
// four bold near-black zig-zag stripes wrapping over the melon
S('MelonStripe');
for (const sx of [-2.25, -1.4, -0.55, 0.3]) {
	[[0.6, 0.95, 0], [0.95, 1.55, 0.12], [1.55, 1.9, -0.1], [1.9, 2.15, 0.06]].forEach(([y0, y1, dx]) => {
		const r = rAt(CY, RAD, y0, y1), x = sx + dx;
		const w = r * Math.sqrt(Math.max(0.02, 1 - Math.pow((x - CX) / (SX * r), 2))) + 0.03;
		B(x - 0.11, x + 0.11, y0, y1 + (y1 === 2.15 ? 0.03 : 0), -w, w, 'trim', R);
	});
}

// --- glowing seam where the croc head meets the melon
S('Seam');
B(0.7, 0.77, 0.92, 1.9, -0.68, 0.68, 'stripe', E);

// --- crocodile head: skull, long chunky upper snout with nostril bumps, cream lower jaw,
// a big open mouth full of teeth
S('Head');
B(0.75, 1.4, 1.0, 1.86, -0.62, 0.62, 'skin', R);
S('Snout');
B(1.4, 2.9, 1.36, 1.8, -0.58, 0.58, 'skin', R);
B(1.4, 2.7, 1.8, 1.9, -0.44, 0.44, 'skin', R);
MZ(2.56, 2.82, 1.88, 1.98, 0.08, 0.28, 'skin');                  // nostril bumps
S('Nostril');
MZ(2.64, 2.76, 1.98, 2.0, 0.12, 0.24, 'P', 0, DARK);
S('LowerJaw');
B(0.9, 2.86, 0.82, 1.06, -0.54, 0.54, 'lower', R);
B(2.6, 2.92, 0.96, 1.12, -0.44, 0.44, 'lower');
S('Mouth');
B(1.05, 2.88, 1.04, 1.38, -0.48, 0.48, 'P', 0, MOUTH);
S('Tongue');
B(1.3, 2.3, 1.06, 1.13, -0.24, 0.24, 'P', 0, '#FF4F7A');
S('Tooth');
for (const x of [1.4, 1.7, 2.0, 2.3, 2.6]) MZ(x - 0.06, x + 0.06, 1.16, 1.38, 0.46, 0.56, 'P', 0, IVORY);   // upper row
for (const x of [1.55, 1.85, 2.15, 2.45]) MZ(x - 0.06, x + 0.06, 1.06, 1.26, 0.44, 0.54, 'P', 0, IVORY);   // lower row
MZ(2.84, 2.94, 1.16, 1.38, 0.2, 0.32, 'P', 0, IVORY);                                                     // front fangs

// --- smaller protruding eye domes with front anime eyes (Amber) under mean V-brows
const FX = 1.22;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.82, FX, 1.84, 2.46, 0.08 * out, 0.6 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.34 * out, top: 2.4, L: 0.86, H: 0.9, out, iris: 'Amber', lash: true, blush: false });
	const zin = eye.inner, zout = eye.outer, zm = (zin + zout) / 2;
	S('Brow');                                                // V-brows: low at the inner end, high outside
	B(0.82, FX + 0.1, eye.lashTop + 0.08, eye.lashTop + 0.2, Math.min(zm, zout) - 0.04, Math.max(zm, zout) + 0.04, 'trim', R);
	B(0.82, FX + 0.1, eye.lashTop - 0.04, eye.lashTop + 0.1, Math.min(zin, zm) - 0.04, Math.max(zin, zm) + 0.02, 'trim', R);
}

// --- seeded watermelon-slice fins standing along the back (rind, cream ring, pink flesh, seeds)
function fin(x, yc, r) {
	S('FinRind');
	B(x - 0.7 * r, x + 0.7 * r, yc - r, yc + r, -0.07, 0.07, 'trim', R);
	B(x - r, x + r, yc - 0.7 * r, yc + 0.9 * r, -0.07, 0.07, 'trim', R);
	S('FinCream');
	B(x - 0.62 * r, x + 0.62 * r, yc - 0.82 * r, yc + 0.84 * r, -0.09, 0.09, 'lower');
	S('FinFlesh');
	B(x - 0.5 * r, x + 0.5 * r, yc - 0.66 * r, yc + 0.7 * r, -0.11, 0.11, 'feather', R);
	S('Seed');
	MZ(x - 0.04, x + 0.04, yc - 0.1, yc + 0.02, 0.11, 0.13, 'P', 0, SEED);
}
fin(-0.25, 2.7, 0.48);
fin(-1.05, 2.86, 0.6);
fin(-1.9, 2.6, 0.46);

// --- four splayed clawed crocodile legs with dark collars, darker green feet, light-up soles
for (const x of [0.35, -1.95]) for (const s of [1, -1]) {
	S('LegCollar');
	B(x - 0.24, x + 0.24, 0.66, 0.84, 0.66 * s, 0.76 * s, 'P', 0, DARK);
	S('Leg');
	tube([x, 0.78, 0.72 * s], [x, 0.58, 1.12 * s], 0.21, 0.19, 'skin');
	tube([x, 0.58, 1.12 * s], [x + 0.08, 0.26, 1.2 * s], 0.19, 0.17, 'skin');
	S('Foot');
	B(x - 0.22, x + 0.46, 0.06, 0.3, (1.2 - 0.27) * s, (1.2 + 0.27) * s, 'foot', R);
	S('Claw');
	for (const dz of [-0.16, 0, 0.16]) B(x + 0.46, x + 0.62, 0.08, 0.2, (1.2 + dz - 0.05) * s, (1.2 + dz + 0.05) * s, 'P', 0, IVORY);
	S('Sole');
	B(x - 0.22, x + 0.46, 0, 0.06, (1.2 - 0.27) * s, (1.2 + 0.27) * s, 'accent', E);
}

// --- long crocodile tail running low along the ground, curling up at the tip, dark ridge spikes
S('Tail');
tube([-2.6, 0.95, 0], [-3.25, 0.62, 0], 0.32, 0.22, 'skin');
tube([-3.25, 0.62, 0], [-3.72, 0.5, 0], 0.22, 0.12, 'skin');
tube([-3.72, 0.5, 0], [-3.92, 0.74, 0], 0.12, 0.06, 'skin');
S('TailRidge');
for (const [x, y] of [[-2.9, 1.0], [-3.3, 0.86], [-3.62, 0.7]]) B(x - 0.1, x + 0.1, y, y + 0.14, -0.05, 0.05, 'trim');

// Dopamine high-contrast palette (docs/creatures/V4/BRT_011_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#1FA845', trim: '#0A4A1E', skin: '#6BFF3A', lower: '#FFF3C8', feather: '#FF3D7A', foot: '#2FBF4A', stripe: '#2EF2FF', accent: '#FFE14D', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { neckY: 0.82, slots: { MelonStripe: 'Torso' } };
