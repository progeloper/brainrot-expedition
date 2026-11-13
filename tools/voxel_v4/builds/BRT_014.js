// BRT_014 Bandito Bobritto — Voxel V4 build (CP-B, Uncommon, revision 2).
// Base: the accepted Studio sculpture (assets/BRT_014_Bandito_Bobritto_Studio/, revision 3 = the
// restored original):
// - an upright amber beaver bandit with cream cheeks, a black nose and two buck teeth
// - green eyes peering over lowered shades, a fedora with a band, a pinstripe suit, a tie, a gold
//   watch chain, both paws around a drum-gun prop, and a broad crosshatched paddle tail
// Revision 2 (owner): "too blocky", "tail isn't in the right spot"; "more high dopamine mafia
// style but keep the anime eyes". Changes:
// - rounded stepped torso and head, tube limbs
// - the tail grows from the lower back and curves down to a rounded paddle on the ground
// - dopamine mafia look: electric-violet suit with glowing gold pinstripes, black shirt, hot-pink tie
//   and shades, gold bling (medallion chain, watch chain, pinky rings), a white fedora with a glowing
//   pink band, and black-and-white spat shoes
// V4 core rules: kit anime eyes (Lime; lash, catchlights) on eye domes, glowing Neon pinstripes and
// hat band, light-up soles, studs on body panels only, dark joint collars.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const IVORY = '#FFF6DE';

const rAt = (cy, R0, y0, y1) => Math.sqrt(Math.max(0.03, R0 * R0 - Math.pow((y0 + y1) / 2 - cy, 2)));
// rounded layer: x half-size rx, z half-size rz (octagon of two boxes)
function layer(cx, y0, y1, rx, rz, role, rel = R) {
	B(cx - rx, cx + rx, y0, y1, -0.7 * rz, 0.7 * rz, role, rel);
	B(cx - 0.66 * rx, cx + 0.66 * rx, y0, y1, -rz, rz, role, rel);
}
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

// --- rounded pear-shaped torso in an electric-violet suit (the equator box is the Body)
S('Body');
B(-0.56, 0.56, 1.3, 1.9, -0.49, 0.49, 'upper', R);
S('SuitRound');
B(-0.37, 0.37, 1.3, 1.9, -0.7, 0.7, 'upper', R);
for (const [y0, y1, r] of [[0.86, 1.06, 0.5], [1.06, 1.3, 0.64], [1.9, 2.1, 0.62], [2.1, 2.26, 0.48]]) layer(0, y0, y1, 0.8 * r, r, 'upper');
S('Shirt');                                                     // black shirt V
B(0.52, 0.56, 1.6, 2.14, -0.24, 0.24, 'prop', R);
B(0.52, 0.56, 1.4, 1.6, -0.12, 0.12, 'prop');
S('Tie');
B(0.56, 0.6, 1.3, 2.08, -0.07, 0.07, 'feather');
B(0.56, 0.61, 2.02, 2.14, -0.1, 0.1, 'feather');
S('Medallion');                                                 // gold bling chain and medallion
B(0.5, 0.54, 2.06, 2.12, -0.32, 0.32, 'trim');
B(0.54, 0.6, 1.88, 2.06, -0.08, 0.08, 'trim', R);
S('WatchChain');
B(0.55, 0.58, 1.22, 1.26, 0.12, 0.42, 'trim');
B(0.55, 0.58, 1.08, 1.22, 0.36, 0.42, 'trim');
S('Pinstripe');                                                 // glowing gold pinstripes
for (const z of [-0.4, 0.4]) B(0.55, 0.57, 1.3, 1.9, z - 0.02, z + 0.02, 'stripe', E);
for (const x of [-0.22, 0.22]) MZ(x - 0.02, x + 0.02, 1.3, 1.9, 0.7, 0.72, 'stripe', E);
for (const z of [-0.26, 0.26]) B(-0.57, -0.55, 1.3, 1.9, z - 0.02, z + 0.02, 'stripe', E);

// --- big round amber beaver head (stepped sphere), cream muzzle and puffy cheeks, nose, buck teeth
const HCY = 2.82, HR = 0.8;
S('Head');
for (const [y0, y1] of [[2.08, 2.32], [2.32, 3.28], [3.28, 3.48], [3.48, 3.56]]) {
	const r = rAt(HCY, HR, y0, y1);
	layer(0.05, y0, y1, 0.92 * r, r, 'skin');
}
S('Muzzle');
B(0.66, 1.0, 2.34, 2.8, -0.42, 0.42, 'lower', R);
MZ(0.58, 0.86, 2.38, 2.74, 0.42, 0.64, 'lower', R);              // puffy cheeks
S('Nose');
B(1.0, 1.12, 2.66, 2.84, -0.14, 0.14, 'P', 0, '#140E12');
S('Mouth');
B(1.0, 1.02, 2.36, 2.42, -0.26, 0.26, 'P', 0, DARK);
S('BuckTooth');
MZ(0.96, 1.06, 2.06, 2.38, 0.02, 0.16, 'P', 0, IVORY);
for (const s of [1, -1]) {
	S('Ear');
	B(-0.12, 0.22, 3.28, 3.6, 0.6 * s, 0.88 * s, 'skin', R);
	S('InnerEar');
	B(0.22, 0.25, 3.34, 3.54, 0.66 * s, 0.82 * s, 'lower');
}
// eye domes with front anime eyes (Lime) peering over lowered gold-rimmed hot-pink shades
const FX = 0.86;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.6, FX, 2.88, 3.48, 0.04 * out, 0.62 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.33 * out, top: 3.44, L: 1.0, H: 0.98, out, iris: 'Lime', lash: false, blush: false });
	S('Lash');                                                  // thin lash line (owner: less prominent brows)
	B(FX, FX + 0.06, eye.whiteTop - 0.01, eye.whiteTop + 0.04, Math.min(eye.inner, eye.outer) - 0.02, Math.max(eye.inner, eye.outer) + 0.02, 'P', 0, '#000000');
	S('ShadeFrame');
	B(0.88, 0.92, 2.74, 3.02, (0.33 - 0.26) * out, (0.33 + 0.26) * out, 'trim');
	S('ShadeLens');
	B(0.92, 0.95, 2.78, 2.98, (0.33 - 0.22) * out, (0.33 + 0.22) * out, 'feather');
	S('ShadeArm');
	B(0.3, 0.9, 2.94, 2.98, 0.6 * out, 0.64 * out, 'trim');
}
S('ShadeBridge');
B(0.88, 0.94, 2.92, 2.98, -0.08, 0.08, 'trim');

// --- white fedora with a glowing hot-pink band
S('HatBrim');
layer(0.05, 3.5, 3.58, 0.92, 0.98, 'skin2');
S('HatCrown');
layer(0.05, 3.58, 3.96, 0.6, 0.62, 'skin2');
layer(0.05, 3.96, 4.06, 0.46, 0.46, 'skin2');
S('HatBand');
layer(0.05, 3.58, 3.68, 0.62, 0.64, 'accent', E);

// --- violet suit arms (tubes) reaching forward, amber paws with gold pinky rings, drum-gun prop
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.16, 0.16, 1.86, 2.16, 0.64 * s, 0.74 * s, 'P', 0, DARK);
	S('Arm');
	tube([0.0, 2.0, 0.72 * s], [0.62, 1.52, 0.58 * s], 0.18, 0.15, 'upper');
	S('Paw');
	B(0.72, 1.06, 1.3, 1.66, (0.58 - 0.17) * s, (0.58 + 0.17) * s, 'skin', R);
	S('Ring');
	B(1.06, 1.1, 1.34, 1.42, (0.58 - 0.12) * s, (0.58 - 0.04) * s, 'trim');
}
S('Gun');
B(0.8, 1.0, 1.4, 1.56, -0.62, 0.62, 'P', 0, '#1A2550');
B(0.8, 0.98, 1.34, 1.58, 0.62, 1.08, 'P', 0, '#8A3A1E');
B(0.85, 0.95, 1.44, 1.52, -1.12, -0.62, 'P', 0, '#2A3A6E');
B(0.84, 0.96, 1.42, 1.54, -1.18, -1.1, 'P', 0, '#9FC8E8');
B(0.8, 1.04, 1.06, 1.4, -0.16, 0.16, 'P', 0, '#9FC8E8');
B(0.86, 0.94, 1.2, 1.4, -0.46, -0.36, 'P', 0, '#8A3A1E');

// --- violet trouser legs (tubes), black-and-white spat shoes, light-up soles
for (const s of [1, -1]) {
	const zc = 0.3 * s;
	S('Leg');
	tube([0.0, 1.0, zc], [0.02, 0.4, zc], 0.21, 0.2, 'upper');
	S('Shoe');
	B(-0.26, 0.5, 0.06, 0.32, zc - 0.22, zc + 0.22, 'foot', R);
	B(0.5, 0.62, 0.08, 0.28, zc - 0.17, zc + 0.17, 'foot');
	S('Spat');
	B(-0.24, 0.3, 0.28, 0.44, zc - 0.23, zc + 0.23, 'P', 0, '#F4F4FF');
	S('Sole');
	B(-0.26, 0.62, 0, 0.06, zc - 0.22, zc + 0.22, 'accent', E);
}

// --- beaver tail growing from the lower back, curving down to a rounded crosshatched paddle
S('TailBase');
tube([-0.44, 1.0, 0], [-0.82, 0.32, 0], 0.18, 0.14, 'feather2');
S('Tail');
B(-1.62, -0.76, 0.04, 0.2, -0.3, 0.3, 'feather2', R);
B(-1.52, -0.86, 0.04, 0.2, -0.42, 0.42, 'feather2', R);
S('TailHatch');
for (const x of [-1.42, -1.19, -0.96]) B(x - 0.02, x + 0.02, 0.2, 0.22, -0.36, 0.36, 'P', 0, '#5A2410');
for (const z of [-0.2, 0, 0.2]) B(-1.52, -0.86, 0.2, 0.22, z - 0.02, z + 0.02, 'P', 0, '#5A2410');

// Dopamine mafia palette (docs/creatures/V4/BRT_014_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#6A2BFF', skin: '#FF9A1F', lower: '#FFF0C8', feather: '#FF2D95', trim: '#FFC21A', prop: '#14101C', skin2: '#F6F2FF', feather2: '#C2581F', foot: '#14101C', stripe: '#FFE14D', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass):
// - Gun (signature prop): the drum-gun gets its own bone on the line through both shoulders, so
//   when both arms and the gun are given the same swing the paws stay on it.
// - Knees: the lower step of each trouser tube, with the shoe, spat and sole, hangs off a joint
//   at the knee. No elbows: both paws hold the gun, so each arm stays one piece.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: {
		Paw: '{side}Arm', Ring: '{side}Arm', SuitRound: 'Torso', Medallion: 'Torso', Gun: 'Gun',
		Shoe: '{side}LowerLeg', Spat: '{side}LowerLeg', Sole: '{side}LowerLeg',
	},
	extraBones: {
		Gun: { parent: 'Torso', pivot: [0, 2.01, 0] },
		RightLowerLeg: { parent: 'RightLeg', pivot: [0.013, 0.6, 0.3] },
		LeftLowerLeg: { parent: 'LeftLeg', pivot: [0.013, 0.6, -0.3] },
	},
	regions: [
		{ bone: 'RightLowerLeg', region: [-1, 1, 0, 0.65, 0, 1], only: /^Leg$/ },
		{ bone: 'LeftLowerLeg', region: [-1, 1, 0, 0.65, -1, 0], only: /^Leg$/ },
	],
};
