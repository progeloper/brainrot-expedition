// BRT_015 Strawberelli Flamingelli — Voxel V4 build (CP-B, Uncommon).
// Follows the accepted Studio sculpture (assets/BRT_015_Strawberelli_Flamingelli_Studio/, revision 4:
// Strawberelli_Preview.jpg, Strawberelli_Rear.jpg):
// - a sharp-edged, straight-paneled vivid scarlet strawberry torso (angular shoulder, straight middle,
//   pointed taper) with golden seeds
// - folded deep-green and lime calyx leaves on top
// - a long pale-pink S-shaped flamingo neck to a small head with huge amber-irised eyes (aligned
//   pupils), raised brows and a large ivory/black hooked beak
// - fanned wine-red wings and tail plumes
// - two slender hot-pink legs on oversized webbed feet (revision 3: a matching standing pair)
// Revision 2 (owner): less prominent brows (thin lash line, small brows), a thinner neck, longer legs.
// Revision 3 (owner): both legs match (a symmetric standing pair) so every model can be rigged later.
// V4 core rules: kit anime eyes (Amber; thin lash line, catchlights, blush) on eye domes, glowing Neon seeds,
// a light-up sole, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';

// angular octagon section (sharp panels) of half-size h
function sect(y0, y1, h, role, rel = R) {
	B(-h, h, y0, y1, -0.62 * h, 0.62 * h, role, rel);
	B(-0.62 * h, 0.62 * h, y0, y1, -h, h, role, rel);
}
function tube(a, b, r0, r1, role) {
	const L = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
	const n = Math.max(1, Math.ceil(L / 0.2));
	for (let k = 0; k < n; k++) {
		const t0 = k / n, t1 = (k + 1) / n, r = r0 + (r1 - r0) * (t0 + t1) / 2;
		const c0 = a.map((v, i) => v + (b[i] - v) * t0), c1 = a.map((v, i) => v + (b[i] - v) * t1);
		B(Math.min(c0[0], c1[0]) - r, Math.max(c0[0], c1[0]) + r, Math.min(c0[1], c1[1]) - r, Math.max(c0[1], c1[1]) + r,
			Math.min(c0[2], c1[2]) - r, Math.max(c0[2], c1[2]) + r, role, R);
	}
}

// --- sharp-edged strawberry torso: straight middle (the Body), angular shoulder, pointed taper
S('Body');
B(-0.74, 0.74, 1.45, 2.05, -0.74, 0.74, 'upper', R);
S('BerryPanels');
B(-0.88, 0.88, 1.5, 2.0, -0.5, 0.5, 'upper', R);
B(-0.5, 0.5, 1.5, 2.0, -0.88, 0.88, 'upper', R);
sect(2.05, 2.3, 0.66, 'upper');                                // angular shoulder
sect(1.1, 1.45, 0.56, 'upper');                                // taper
sect(0.82, 1.1, 0.32, 'upper');                                // pointed tip
// glowing golden seeds on the front and side panels
S('Seed');
for (const [y, z] of [[1.86, -0.3], [1.86, 0.3], [1.62, 0], [1.62, -0.56], [1.62, 0.56], [1.3, -0.24], [1.3, 0.24]]) {
	B(0.88, 0.92, y - 0.06, y + 0.06, z - 0.04, z + 0.04, 'stripe', E);
}
for (const s of [1, -1]) for (const [x, y] of [[-0.3, 1.8], [0.24, 1.6], [-0.2, 1.3]]) {
	B(x - 0.04, x + 0.04, y - 0.06, y + 0.06, 0.88 * s, 0.92 * s, 'stripe', E);
}

// --- folded deep-green and lime calyx leaves radiating from the top
S('Calyx');
B(-0.3, 0.3, 2.3, 2.42, -0.3, 0.3, 'feather', R);
for (const [dx, dz, role] of [[1, 0, 'feather2'], [-1, 0, 'feather'], [0, 1, 'feather2'], [0, -1, 'feather'], [0.71, 0.71, 'feather'], [-0.71, 0.71, 'feather2'], [-0.71, -0.71, 'feather2']]) {
	// long pointed leaf: wide base, narrower mid, tip, rising slightly outward
	for (const [r0, r1, w, y0] of [[0.3, 0.75, 0.2, 2.3], [0.75, 1.05, 0.12, 2.34], [1.05, 1.25, 0.06, 2.38]]) {
		const xa = dx * r0, xb = dx * r1, za = dz * r0, zb = dz * r1;
		const wx = Math.abs(dz) * w + 0.04, wz = Math.abs(dx) * w + 0.04;
		B(Math.min(xa, xb) - wx, Math.max(xa, xb) + wx, y0, y0 + 0.1, Math.min(za, zb) - wz, Math.max(za, zb) + wz, role, r0 < 0.5 ? R : 0);
	}
}

// --- long pale-pink S-shaped flamingo neck to a small head
S('Neck');
tube([0.0, 2.36, 0], [0.55, 2.8, 0], 0.11, 0.1, 'skin');
tube([0.55, 2.8, 0], [0.02, 3.3, 0], 0.1, 0.1, 'skin');
tube([0.02, 3.3, 0], [0.42, 3.74, 0], 0.1, 0.11, 'skin');
S('Head');
B(0.22, 0.76, 3.66, 4.18, -0.32, 0.32, 'skin', R);
// huge eye domes with front anime eyes (Amber), raised black brows
const FX = 0.84;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.46, FX, 3.84, 4.66, 0.02 * out, 0.52 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.27 * out, top: 4.6, L: 0.86, H: 1.06, out, iris: 'Amber', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer), zm = (z0 + z1) / 2;
	S('Lash');                                                  // thin lash line
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
	const lift = out > 0 ? 0.05 : 0;                          // small, thin, slightly asymmetric brows
	S('Brow');
	B(0.5, FX + 0.04, eye.whiteTop + 0.08 + lift, eye.whiteTop + 0.12 + lift, zm - 0.12, zm + 0.12, 'P', 0, INK);
}
// large ivory/black hooked beak pointing forward and down
S('Beak');
B(0.76, 1.1, 3.6, 3.92, -0.17, 0.17, 'lower', R);
S('BeakTip');
B(1.02, 1.3, 3.38, 3.72, -0.15, 0.15, 'P', 0, INK);
B(1.12, 1.28, 3.26, 3.4, -0.09, 0.09, 'P', 0, INK);

// --- fanned wine-red wings on the flanks and spiky tail plumes at the back
for (const s of [1, -1]) {
	S('Wing');
	B(-0.62, 0.36, 1.56, 2.02, 0.88 * s, 0.96 * s, 'skin2', R);
	B(-0.78, 0.1, 1.68, 2.12, 0.94 * s, 1.0 * s, 'skin2');
}
S('TailPlume');
for (const [y, len] of [[1.66, 0.62], [1.86, 0.74], [2.06, 0.58]]) {
	B(-0.88 - len, -0.84, y, y + 0.12, -0.14, 0.14, 'skin2', R);
	B(-0.88 - len - 0.16, -0.88 - len, y + 0.02, y + 0.1, -0.06, 0.06, 'skin2');
}

// --- lift everything above so the flamingo stands on longer legs
const LIFT = 0.6;
for (const p of parts) { p.min[1] += LIFT; p.max[1] += LIFT; }

// --- matching pair of long slender hot-pink legs (symmetric, rig-ready), knee joints, webbed feet
S('HipCollar');
B(-0.16, 0.16, 1.36, 1.48, -0.34, 0.34, 'P', 0, DARK);
for (const s of [1, -1]) {
	const zc = 0.2 * s;
	S('Leg');
	tube([0.0, 1.44, zc], [0.06, 0.78, zc], 0.07, 0.06, 'prop');
	B(0.0, 0.14, 0.72, 0.84, zc - 0.07, zc + 0.07, 'P', 0, DARK);     // knee joint
	tube([0.07, 0.78, zc], [0.08, 0.12, zc], 0.06, 0.06, 'prop');
	S('Foot');                                                    // oversized webbed foot
	B(-0.12, 0.5, 0.04, 0.12, zc - 0.2, zc + 0.2, 'foot', R);
	S('Web');
	for (const dz of [-0.11, 0, 0.11]) B(0.1, 0.5, 0.12, 0.14, zc + dz - 0.015, zc + dz + 0.015, 'P', 0, '#E06AA6');
	S('Sole');
	B(-0.12, 0.5, 0, 0.04, zc - 0.2, zc + 0.2, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_015_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF1F3D', stripe: '#FFE14D', feather: '#0E8A3A', feather2: '#9BFF2E', skin: '#FF8FC8', skin2: '#8A0C2E', lower: '#FFF6D5', prop: '#FF2D95', foot: '#FFB3D9', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass):
// - Neck: the S-shaped neck gets two joints. NeckBase sits where the neck leaves the body and
//   carries the first two bends; Neck sits at the top bend and carries the last stretch. The
//   head pivots at the top of the neck.
// - Knees: the lower tube of each leg, with the webbed foot, hangs off a joint at the dark knee
//   box, which stays on the upper leg.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { HipCollar: 'Torso', BeakTip: 'Head', Foot: '{side}LowerLeg', Web: '{side}LowerLeg', Sole: '{side}LowerLeg' },
	neck: { pivot: [0.02, 3.9, 0], slots: ['Neck'], base: { pivot: [0, 2.96, 0] } },
	headPivot: [0.42, 4.34, 0],
	extraBones: {
		RightLowerLeg: { parent: 'RightLeg', pivot: [0.07, 0.78, 0.2] },
		LeftLowerLeg: { parent: 'LeftLeg', pivot: [0.07, 0.78, -0.2] },
	},
	regions: [
		{ bone: 'NeckBase', region: [-1, 1, 2.5, 3.9, -0.3, 0.3], only: /^Neck$/ },
		{ bone: 'RightLowerLeg', region: [-1, 1, 0, 0.72, 0, 1], only: /^Leg$/ },
		{ bone: 'LeftLowerLeg', region: [-1, 1, 0, 0.72, -1, 0], only: /^Leg$/ },
	],
};
