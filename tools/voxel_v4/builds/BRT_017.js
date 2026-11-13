// BRT_017 Orangutini Ananassini — Voxel V4 build (CP-B, Uncommon, revision 5).
// Revision 4 (owner): "looks sloppy, stop relying on the og models, search references online and go
// crazy with V4". The accepted Studio sculpture is no longer the reference. Online guides describe an
// orangutan-pineapple fusion: a rounded pineapple torso with segmented squares, orangutan arms and
// legs, and a leafy crown on the head (gameboost.com, rblxguide.com, u4gm.com).
// The V4 take, built from fewer, cleaner, bolder shapes:
// - a golden pineapple barrel with a diamond lattice (revision 4 had a brick grid of grooves; the
//   owner asked for diamonds in revision 5)
// - a real orangutan head: ginger fur, a dark plum face with huge flat cheek flanges, a pale muzzle,
//   a big goofy grin, and huge anime eyes
// - a giant spiky pineapple crown sprouting from the head
// - the gag: a tiki party orangutan, wearing a green-and-lime grass skirt with a glowing waistband and
//   a glowing neon flower lei
// - long, straight orangutan arms hanging to the ground with big dark hands; short legs, dark feet
// Revision 5 (owner): a diamond lattice instead of the brick grid (gold stepped diamonds on a dark-amber
//   barrel), and a bigger tiki gag: a fuller, longer grass skirt and a lei of eight bigger flowers.
// Rig-ready (owner rule): arms and legs are straight matching pairs in a neutral pose, with dark
// collars at the shoulder, elbow, wrist, hip and knee.
// V4 core rules: kit anime eyes (Amber; thin lash line, small brows with a gap, catchlights, blush)
// on white eye domes, glowing Neon lei and waistband, light-up soles, studs on body panels only.
// Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const IVORY = '#FFF6DE';

// octagon layer centred at x = cx (two crossed boxes)
function layer(cx, y0, y1, r, role, rel = R) {
	B(cx - r, cx + r, y0, y1, -0.7 * r, 0.7 * r, role, rel);
	B(cx - 0.66 * r, cx + 0.66 * r, y0, y1, -r, r, role, rel);
}
// radius of an ellipsoid (centre cy, horizontal radius R0, vertical radius Ry) at height y
const rAt = (cy, R0, Ry, y) => R0 * Math.sqrt(Math.max(0.05, 1 - Math.pow((y - cy) / Ry, 2)));

// --- golden pineapple barrel (revision 5): a dark-amber core (the Body) covered in gold stepped
// diamonds packed in offset rows, so the dark gaps between them form a criss-cross diamond lattice;
// gold rounded top and bottom
const TR = 1.0;
S('Body');
B(-TR, TR, 1.35, 2.55, -0.7 * TR, 0.7 * TR, 'upper', R);
S('PineappleRound');
B(-0.66 * TR, 0.66 * TR, 1.35, 2.55, -TR, TR, 'upper', R);
S('PineappleCap');
for (const [y0, y1, r] of [[0.9, 1.1, 0.55], [1.1, 1.35, 0.85], [2.55, 2.8, 0.85], [2.8, 3.0, 0.55]]) layer(0, y0, y1, r, 'lower');
// one gold stepped diamond (or a two-box cross) on the front (+x) or back (-x) face, clipped to the face
function diamond(y, z, dir, steps = 3) {
	const a = dir > 0 ? TR : -TR - 0.05, b = dir > 0 ? TR + 0.05 : -TR;
	const clip = (z0, z1) => [Math.max(z0, -0.7 * TR), Math.min(z1, 0.7 * TR)];
	S('PineappleDiamond');
	const bars = steps === 3 ? [[0.07, 0.22], [0.15, 0.15], [0.22, 0.07]] : [[0.08, 0.21], [0.21, 0.08]];
	for (const [hy, hz] of bars) B(a, b, y - hy, y + hy, ...clip(z - hz, z + hz), 'lower', R);
}
for (const [y, zs] of [[2.3, [-0.3, 0.3]], [2.0, [-0.6, 0, 0.6]], [1.7, [-0.3, 0.3]]]) for (const z of zs) diamond(y, z, 1);
for (const [y, zs] of [[2.3, [-0.3, 0.3]], [2.0, [0]], [1.7, [-0.3, 0.3]]]) for (const z of zs) diamond(y, z, -1, 2);

// --- the gag: a full tiki grass skirt (ten long alternating green / lime slats) with a glowing waistband
S('GrassSkirt');
for (let i = 0; i < 10; i++) {
	const a = (i * Math.PI) / 5, cx = 0.94 * Math.cos(a), cz = 0.94 * Math.sin(a);
	const hx = 0.08 + 0.2 * Math.abs(Math.sin(a)), hz = 0.08 + 0.2 * Math.abs(Math.cos(a));
	B(cx - hx, cx + hx, 0.56, 1.5, cz - hz, cz + hz, i % 2 ? 'feather' : 'feather2', 0);
}
S('Waistband');
layer(0, 1.46, 1.58, 1.1, 'stripe', E);

// --- round ginger orangutan head: dark plum face, huge flat cheek flanges, pale muzzle, goofy grin
const HX = 0.05, HCY = 3.5, HR = 0.68, HRY = 0.62;
S('Head');
for (const [y0, y1] of [[2.88, 3.1], [3.1, 3.9], [3.9, 4.12]]) layer(HX, y0, y1, rAt(HCY, HR, HRY, (y0 + y1) / 2), 'skin');
S('Face');
B(0.5, 0.7, 3.0, 3.96, -0.5, 0.5, 'skin2', 0);
for (const s of [1, -1]) {
	S('CheekFlange');                                           // huge flat dark disc framing the face
	B(0.44, 0.64, 3.06, 3.86, 0.46 * s, 1.16 * s, 'skin2', R);
	B(0.44, 0.64, 2.96, 3.96, 0.46 * s, 1.02 * s, 'skin2', R);
}
S('Muzzle');                                                    // pale orangutan muzzle
B(0.66, 1.0, 2.9, 3.4, -0.4, 0.4, 'trim', R);
S('Nose');
B(0.68, 0.76, 3.4, 3.5, -0.12, 0.12, 'P', 0, INK);
S('Mouth');                                                     // big goofy grin with a tooth row and tongue
B(1.0, 1.02, 2.96, 3.26, -0.32, 0.32, 'P', 0, INK);
S('Teeth');
B(1.01, 1.04, 3.15, 3.26, -0.28, 0.28, 'P', 0, IVORY);
S('Tongue');
B(1.01, 1.035, 2.96, 3.08, -0.18, 0.12, 'P', 0, '#FF4F7A');
// huge white eye domes with front anime eyes (Amber), thin lash line, small ginger brows with a gap
const FX = 0.8;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.56, FX, 3.38, 4.12, 0.02 * out, 0.54 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.28 * out, top: 4.08, L: 0.98, H: 1.0, out, iris: 'Amber', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer), zm = (z0 + z1) / 2;
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
	S('Brow');
	B(0.56, FX + 0.04, eye.whiteTop + 0.05, eye.whiteTop + 0.09, zm - 0.12, zm + 0.12, 'skin');
}

// --- big neon flower lei around the neck (eight flowers, alternating hot pink and cyan)
S('Lei');
for (let i = 0; i < 8; i++) {
	const ang = (i * Math.PI) / 4, cx = 0.8 * Math.cos(ang), cz = 0.8 * Math.sin(ang);
	B(cx - 0.16, cx + 0.16, 2.58, 2.9, cz - 0.16, cz + 0.16, i % 2 ? 'accent' : 'stripe', E);
}

// --- giant spiky pineapple crown sprouting from the head
const CY = 4.08;
S('LeafCrown');
B(HX - 0.07, HX + 0.07, CY, 4.8, -0.07, 0.07, 'feather', R);    // tall centre spike
B(HX - 0.035, HX + 0.035, 4.8, 5.3, -0.035, 0.035, 'feather2');
const LEAVES = [[1, 0], [-1, 0], [0, 1], [0, -1], [0.71, 0.71], [0.71, -0.71], [-0.71, 0.71], [-0.71, -0.71]];
LEAVES.forEach(([dx, dz], i) => {
	const tall = i < 4 ? 0 : -0.16;                             // diagonal leaves a little shorter
	// a dark lower blade reaching out, then a tall lime spike at its end
	for (const [r0, r1, w, y0, y1, role] of [[0.06, 0.66, 0.04, CY, 4.3 + tall, 'feather'], [0.6, 0.74, 0.0, 4.2 + tall, 5.1 + tall, 'feather2']]) {
		const xa = HX + dx * r0, xb = HX + dx * r1, za = dz * r0, zb = dz * r1;
		const wx = Math.abs(dz) * w + 0.035, wz = Math.abs(dx) * w + 0.035;
		B(Math.min(xa, xb) - wx, Math.max(xa, xb) + wx, y0, y1, Math.min(za, zb) - wz, Math.max(za, zb) + wz, role, 0);
	}
});

// --- long, straight orangutan arms hanging to the ground (matching pair): round shoulder, upper arm,
// elbow collar, thick forearm, wrist collar, big dark hand with three fingers and a thumb
for (const s of [1, -1]) {
	const z = (a, b) => [a * s, b * s];
	S('Shoulder');
	B(-0.26, 0.26, 2.42, 2.86, ...z(0.94, 1.42), 'skin', R);
	S('UpperArm');
	B(-0.19, 0.19, 1.72, 2.5, ...z(1.0, 1.36), 'skin', R);
	S('ElbowCollar');
	B(-0.2, 0.2, 1.62, 1.72, ...z(0.98, 1.38), 'P', 0, DARK);
	S('Forearm');
	B(-0.21, 0.21, 0.8, 1.62, ...z(0.98, 1.38), 'skin', R);
	S('WristCollar');
	B(-0.17, 0.17, 0.72, 0.8, ...z(1.02, 1.34), 'P', 0, DARK);
	S('Hand');
	B(-0.2, 0.28, 0.4, 0.72, ...z(1.0, 1.36), 'foot', R);
	S('Finger');
	for (const x of [-0.13, 0.03, 0.19]) B(x - 0.065, x + 0.065, 0.04, 0.4, ...z(1.04, 1.32), 'foot');
	S('Thumb');
	B(0.28, 0.38, 0.44, 0.64, ...z(1.08, 1.28), 'foot');
}

// --- short straight legs (matching pair) under the skirt: hip collar, thigh, knee collar, shin,
// big dark feet with two toes, light-up soles
for (const s of [1, -1]) {
	const zc = 0.38 * s;
	S('HipCollar');
	B(-0.22, 0.22, 0.98, 1.06, zc - 0.22, zc + 0.22, 'P', 0, DARK);
	S('Thigh');
	B(-0.2, 0.2, 0.64, 1.0, zc - 0.2, zc + 0.2, 'skin', R);
	S('KneeCollar');
	B(-0.21, 0.21, 0.58, 0.64, zc - 0.21, zc + 0.21, 'P', 0, DARK);
	S('Shin');
	B(-0.17, 0.17, 0.3, 0.58, zc - 0.17, zc + 0.17, 'skin', R);
	S('Foot');
	B(-0.26, 0.54, 0.04, 0.3, zc - 0.24, zc + 0.24, 'foot', R);
	S('Toe');
	for (const dz of [-0.12, 0.12]) B(0.54, 0.68, 0.04, 0.2, zc + dz - 0.09, zc + dz + 0.09, 'foot');
	S('Sole');
	B(-0.26, 0.68, 0, 0.04, zc - 0.24, zc + 0.24, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_017_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#9C7A0C', lower: '#FFCC1A', skin: '#FF5A14', skin2: '#3B2340', trim: '#FFC79A', feather: '#0E8A3A', feather2: '#7DFF2E', foot: '#4A2C52', stripe: '#FF2DD1', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Animation pass (13 Nov 2026): the shoulders pivot at the top of the upper arm (they were at its middle), the
// head turns from its neck, and the grass skirt with its glowing waistband gets a joint at the waist so it can sway.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { CheekFlange: 'Head', GrassSkirt: 'Skirt', Waistband: 'Skirt' },
	shoulderY: 2.45,
	headPivot: [0.05, 2.95, 0],
	extraBones: { Skirt: { parent: 'Torso', pivot: [0, 1.52, 0] } },
};
