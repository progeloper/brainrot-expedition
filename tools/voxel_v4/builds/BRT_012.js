// BRT_012 Frigo Camelo — Voxel V4 build (CP-B, Uncommon).
// Follows the accepted Studio sculpture (assets/BRT_012_Frigo_Camelo_Studio/, revision 2:
// Frigo_Preview.jpg, Frigo_Profile.jpg, Frigo_Rear.jpg):
// - a four-legged camel whose torso is a long horizontal white fridge, two doors on each flank
//   with cyan seals and silver handles, dark-blue vents at the front, condenser coils at the rear
// - one icy freezer hump in the refrigerator theme: white dome, cyan vent panel, snowflake badge,
//   top handle and icicles
// - a bowed caramel neck with a cream front, a long camel muzzle with a drooping split cream lip,
//   small rounded ears, a chin tuft, big amber eyes with heavy brows
// - four knobbly legs in orange lace-up boots, and a tufted tail
// Revision 2 (owner, colours): a bold blue fridge with icy doors and hump, a brighter orange camel,
// hot-magenta boots with yellow toe caps (revision 3: electric purple boots, lime toe caps), and more glow (icicles, snowflake badge, hump vents).
// V4 core rules: kit anime eyes (Amber; lash, catchlights, blush) on eye domes, glowing Neon door
// seals, light-up soles, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const SILVER = '#C9D6E8';
const ICE = '#DFF8FF';

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

// --- long horizontal fridge torso (the Body), two doors per flank with glowing cyan seals
S('Body');
B(-1.6, 1.0, 1.55, 2.55, -0.6, 0.6, 'upper', R);
S('FridgeEdge');
B(-1.66, 1.06, 1.6, 2.5, -0.54, 0.54, 'upper', R);
for (const s of [1, -1]) for (const [x0, x1] of [[-1.5, -0.32], [-0.25, 0.92]]) {
	S('DoorSeal');
	B(x0, x1, 1.62, 2.48, 0.6 * s, 0.63 * s, 'stripe', E);
	S('Door');
	B(x0 + 0.05, x1 - 0.05, 1.67, 2.43, 0.62 * s, 0.66 * s, 'upper', R);
	S('Handle');
	B(x1 - 0.18, x1 - 0.12, 1.86, 2.24, 0.66 * s, 0.72 * s, 'P', 0, SILVER);
}
S('Vent');                                                       // dark-blue vents on the front
for (const y of [1.74, 1.86, 1.98]) B(1.06, 1.09, y, y + 0.05, -0.36, 0.36, 'trim');
S('Coil');                                                       // condenser coils at the rear
for (const y of [1.78, 1.98, 2.18]) B(-1.69, -1.66, y, y + 0.06, -0.4, 0.4, 'trim');

// --- icy freezer hump: stepped white dome, cyan vent panel, snowflake badge, handle, icicles
S('Hump');
B(-1.1, 0.5, 2.55, 2.86, -0.5, 0.5, 'feather2', R);
B(-0.95, 0.35, 2.86, 3.1, -0.4, 0.4, 'feather2', R);
B(-0.75, 0.15, 3.1, 3.24, -0.26, 0.26, 'feather2', R);
S('HumpPanel');
B(-0.22, 0.18, 2.6, 3.08, 0.4, 0.52, 'prop', R);
for (const y of [2.72, 2.84, 2.96]) B(-0.18, 0.14, y, y + 0.05, 0.52, 0.54, 'stripe', E);   // glowing vents
S('Snowflake');
B(-0.7, -0.4, 2.66, 2.96, -0.53, -0.5, 'trim');
B(-0.62, -0.48, 2.7, 2.92, -0.55, -0.53, 'stripe', E);          // glowing snowflake
B(-0.66, -0.44, 2.78, 2.84, -0.55, -0.53, 'stripe', E);
S('HumpHandle');
B(-0.32, -0.06, 3.24, 3.34, -0.04, 0.04, 'P', 0, SILVER);
S('Icicle');
for (const [x, len] of [[0.5, 0.26], [0.2, 0.18], [-1.1, 0.22]]) MZ(x - 0.05, x + 0.05, 2.55 - len, 2.55, 0.6, 0.66, 'stripe', E);   // glowing icicles

// --- bowed caramel neck rising from the front of the fridge, cream throat
S('Neck');
tube([0.75, 2.2, 0], [1.0, 2.9, 0], 0.3, 0.26, 'skin');
tube([1.0, 2.9, 0], [1.05, 3.5, 0], 0.26, 0.24, 'skin');
S('Throat');
B(1.22, 1.3, 2.3, 3.4, -0.18, 0.18, 'lower');

// --- camel head: long arched muzzle, drooping split cream lip, slit nostrils, chin tuft, small ears
S('Head');
B(0.8, 1.6, 3.45, 4.12, -0.42, 0.42, 'skin', R);
B(0.9, 1.5, 4.12, 4.24, -0.32, 0.32, 'skin', R);
S('Muzzle');
B(1.6, 2.32, 3.48, 3.92, -0.32, 0.32, 'skin', R);
B(1.6, 2.2, 3.92, 3.98, -0.24, 0.24, 'skin');                   // arched nose bridge
S('Lip');
B(1.6, 2.28, 3.3, 3.48, -0.3, 0.3, 'lower', R);
MZ(2.06, 2.3, 3.24, 3.36, 0.06, 0.28, 'lower');                 // drooping split upper lip
S('Mouth');
B(1.7, 2.3, 3.46, 3.5, -0.3, 0.3, 'P', 0, '#5A2410');
S('Tooth');
MZ(2.22, 2.3, 3.42, 3.48, 0.04, 0.16, 'P', 0, '#FFF6DE');
S('Nostril');
MZ(2.32, 2.34, 3.76, 3.82, 0.1, 0.24, 'P', 0, DARK);
S('ChinTuft');
B(1.6, 1.82, 3.12, 3.3, -0.1, 0.1, 'P', 0, '#5A2E12');
for (const s of [1, -1]) {
	S('Ear');
	B(0.84, 1.04, 4.06, 4.34, 0.32 * s, 0.56 * s, 'skin', R);
	S('InnerEar');
	B(1.04, 1.07, 4.12, 4.28, 0.36 * s, 0.52 * s, 'lower');
}
// big protruding eye domes with front anime eyes (Amber), heavy brows
const FX = 1.62;
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.24, FX, 3.86, 4.56, 0.04 * out, 0.62 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.33 * out, top: 4.5, L: 0.96, H: 1.0, out, iris: 'Amber', lash: true, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Brow');
	B(1.24, FX + 0.08, eye.lashTop + 0.04, eye.lashTop + 0.16, z0 + (out > 0 ? 0.08 : 0), z1 - (out > 0 ? 0 : 0.08), 'P', 0, '#4A2410');   // gap between brows
}

// --- four knobbly caramel legs with dark collars, orange lace-up boots, light-up soles
for (const x of [0.62, -1.22]) for (const s of [1, -1]) {
	const zc = 0.36 * s;
	S('LegCollar');
	B(x - 0.18, x + 0.18, 1.46, 1.58, zc - 0.18, zc + 0.18, 'P', 0, DARK);
	S('Leg');
	tube([x, 1.5, zc], [x + 0.04, 1.02, zc], 0.11, 0.1, 'skin');
	B(x - 0.1, x + 0.16, 0.95, 1.09, zc - 0.13, zc + 0.13, 'skin', R);     // knobbly knee
	tube([x + 0.04, 1.02, zc], [x, 0.56, zc], 0.1, 0.09, 'skin');
	S('Boot');
	B(x - 0.26, x + 0.3, 0.1, 0.6, zc - 0.22, zc + 0.22, 'foot', R);
	B(x + 0.3, x + 0.46, 0.1, 0.38, zc - 0.2, zc + 0.2, 'feather', R);   // yellow toe cap
	S('Lace');
	for (const y of [0.42, 0.52]) B(x + 0.2, x + 0.32, y, y + 0.04, zc - 0.16, zc + 0.16, 'P', 0, '#FFFFFF');
	S('BootSole');
	B(x - 0.28, x + 0.48, 0.04, 0.1, zc - 0.24, zc + 0.24, 'trim');
	S('Sole');
	B(x - 0.28, x + 0.48, 0, 0.04, zc - 0.24, zc + 0.24, 'accent', E);
}

// --- tufted tail at the rear
S('Tail');
tube([-1.66, 2.3, 0], [-1.8, 1.8, 0], 0.07, 0.06, 'skin');
S('TailTuft');
B(-1.88, -1.72, 1.56, 1.82, -0.09, 0.09, 'P', 0, '#5A2E12');

// Dopamine high-contrast palette (docs/creatures/V4/BRT_012_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#2E9BFF', feather2: '#C8F4FF', stripe: '#2EF2FF', trim: '#13226B', skin: '#FF9F1A', lower: '#FFE6B0', foot: '#7B2BFF', feather: '#B6FF2E', prop: '#2E9BFF', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass):
// - Neck: the bowed neck and throat get their own bone at the base of the neck, and the head
//   pivots at the top of the neck.
// - Knees: each leg is hip-knee-ankle tubes with a knobbly knee, so the lower tube and the boot
//   hang off a joint at the knee. The knee box stays on the thigh and hides the bend.
// - FridgeDoor (signature prop): the front door on the right flank, with its handle, hinges on
//   its rear edge so it can swing open. Its glowing seal stays on the fridge and shows as the
//   light inside.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { Lip: 'Head', ChinTuft: 'Head' },
	neck: { pivot: [0.75, 2.2, 0], slots: ['Neck', 'Throat'] },
	headPivot: [1.05, 3.5, 0],
	extraBones: {
		FrontRightLowerLeg: { parent: 'FrontRightLeg', pivot: [0.66, 1.02, 0.36] },
		FrontLeftLowerLeg: { parent: 'FrontLeftLeg', pivot: [0.66, 1.02, -0.36] },
		BackRightLowerLeg: { parent: 'BackRightLeg', pivot: [-1.18, 1.02, 0.36] },
		BackLeftLowerLeg: { parent: 'BackLeftLeg', pivot: [-1.18, 1.02, -0.36] },
		FridgeDoor: { parent: 'Torso', pivot: [-0.25, 2.05, 0.62] },
	},
	regions: [
		{ bone: 'FrontRightLowerLeg', region: [0, 2, 0, 0.99, 0, 1], only: /^(Leg|Boot|Lace|BootSole|Sole)$/ },
		{ bone: 'FrontLeftLowerLeg', region: [0, 2, 0, 0.99, -1, 0], only: /^(Leg|Boot|Lace|BootSole|Sole)$/ },
		{ bone: 'BackRightLowerLeg', region: [-2, -0.5, 0, 0.99, 0, 1], only: /^(Leg|Boot|Lace|BootSole|Sole)$/ },
		{ bone: 'BackLeftLowerLeg', region: [-2, -0.5, 0, 0.99, -1, 0], only: /^(Leg|Boot|Lace|BootSole|Sole)$/ },
		{ bone: 'FridgeDoor', region: [-0.25, 0.95, 1.6, 2.5, 0.6, 0.8], only: /^(Door|Handle)$/ },
	],
};
