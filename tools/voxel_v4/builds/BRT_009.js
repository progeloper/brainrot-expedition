// BRT_009 Chimpanzini Bananini — Voxel V4 build (CP-B).
// Follows the accepted Studio sculpture (assets/BRT_009_Chimpanzini_Bananini_Studio/: revision 2,
// appearance correction 1, expression correction 1):
// - a full upright chimp with vivid leaf-green fur
// Revision 2 (owner): a bigger muzzle and grin, bigger ears; more contrast and not all green:
//   tangerine chest patch, purple shorts, cyan wristbands, brighter bananas.
// Revision 3 (owner): headband removed; a more ape-like body (hunched shoulders, broad forward
//   chest, head low and forward, long arms with the hanging hand reaching low).
// Revision 4 (owner): limbs fixed: arms and legs are connected tapered tubes along
//   shoulder-elbow-wrist and hip-knee-ankle paths with rounded joints, thick ape forearms, thumbs.
// - cream face, muzzle, ears, hands and feet
// - huge protruding eyes with raised asymmetric dark-green brows, a projecting green nose, and a
//   wide excited grin with a slim continuous ivory tooth row
// - long bent arms: one raised holding a peeled banana, the other hanging with a bunch of three
//   bright yellow bananas
// - bent legs on big cream feet
// V4 core rules: kit anime eyes (Violet; lash, catchlights, blush) on the protruding eye domes, a
// glowing Neon collar between head and body, light-up soles, studs on body panels only, dark joint
// collars. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const IVORY = '#FFF6DE';
const TIP = '#5A2E12';
const MOUTH = '#123018';

// --- ape-like torso: broad chest leaning forward over the belly (the Body), hunched shoulder
// hump, tangerine chest patch, purple shorts with a glowing waistline
S('Body');
B(-0.42, 0.46, 1.82, 2.75, -0.66, 0.66, 'upper', R);
S('Chest');
B(-0.3, 0.6, 2.4, 2.95, -0.72, 0.72, 'upper', R);               // chest pushed forward
B(-0.5, 0.52, 1.98, 2.6, -0.54, 0.54, 'upper', R);
S('ShoulderHump');
B(-0.46, 0.3, 2.85, 3.12, -0.84, 0.84, 'upper', R);             // hunched shoulders
B(-0.36, 0.2, 3.12, 3.24, -0.58, 0.58, 'upper', R);
S('ChestPatch');
B(0.6, 0.64, 2.44, 2.9, -0.36, 0.36, 'feather', R);
B(0.5, 0.54, 2.04, 2.44, -0.24, 0.24, 'feather', R);
S('Shorts');
B(-0.44, 0.48, 1.4, 1.84, -0.6, 0.6, 'skin2', R);
S('Waistline');
B(-0.47, 0.51, 1.84, 1.9, -0.63, 0.63, 'stripe', E);

// --- big round head (fur), cream muzzle, green nose, wide grin with a continuous tooth row
const HEAD_START = parts.length;
S('Head');
B(-0.55, 0.6, 3.0, 4.22, -0.66, 0.66, 'skin', R);
B(-0.45, 0.5, 4.22, 4.36, -0.5, 0.5, 'skin', R);
B(-0.66, 0.5, 3.12, 4.1, -0.52, 0.52, 'skin', R);
B(-0.42, 0.48, 4.36, 4.5, -0.46, 0.46, 'skin', R);             // crown above the eye domes
S('Muzzle');                                                    // big projecting chimp muzzle
B(0.55, 1.04, 2.88, 3.48, -0.58, 0.58, 'lower', R);
B(0.55, 0.96, 2.8, 2.88, -0.42, 0.42, 'lower');
S('Nose');
B(1.02, 1.16, 3.36, 3.54, -0.16, 0.16, 'trim', R);
S('Nostril');
MZ(1.16, 1.18, 3.4, 3.47, 0.03, 0.1, 'P', 0, DARK);
S('Mouth');                                                     // huge excited grin
B(1.04, 1.06, 2.94, 3.3, -0.48, 0.48, 'P', 0, MOUTH);
MZ(1.02, 1.06, 3.22, 3.42, 0.48, 0.56, 'P', 0, MOUTH);
S('Teeth');
B(1.05, 1.08, 3.21, 3.3, -0.46, 0.46, 'P', 0, IVORY);           // upper tooth row
B(1.05, 1.08, 2.94, 3.0, -0.36, 0.36, 'P', 0, IVORY);           // lower tooth row
S('Tongue');
B(1.05, 1.08, 3.0, 3.12, -0.2, 0.16, 'P', 0, '#FF4F7A');
// big round ears with pink inner ears
for (const s of [1, -1]) {
	S('Ear');
	B(-0.16, 0.14, 3.28, 4.12, 0.64 * s, 1.22 * s, 'skin', R);     // big round chimp ears
	B(-0.14, 0.12, 3.4, 4.0, 1.22 * s, 1.3 * s, 'skin', R);
	S('InnerEar');
	B(0.14, 0.18, 3.4, 4.0, 0.74 * s, 1.14 * s, 'feather2');
}
// huge protruding eye domes with big front anime eyes (Violet), raised asymmetric brows
const FX = 0.84;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.5, FX, 3.5, 4.36, (0.02 * out), (0.68 * out), 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.35 * out, top: 4.3, L: 1.1, H: 1.2, out, iris: 'Violet', lash: true, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	const lift = out > 0 ? 0.12 : 0;                           // one brow higher than the other
	S('Brow');
	B(0.6, FX + 0.08, eye.lashTop + 0.06 + lift, eye.lashTop + 0.18 + lift, z0 + 0.02, z1 - 0.02, 'trim', R);
}

// --- the head sits low and forward between the hunched shoulders, ape-style
for (const p of parts.slice(HEAD_START)) { p.min[0] += 0.18; p.max[0] += 0.18; p.min[1] -= 0.24; p.max[1] -= 0.24; }

// --- connected limb helpers: a tapered tube of overlapping steps along a path, and a rounded joint
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
function joint(c, r, role) {
	B(c[0] - 0.72 * r, c[0] + 0.72 * r, c[1] - r, c[1] + r, c[2] - 0.72 * r, c[2] + 0.72 * r, role, R);
	B(c[0] - r, c[0] + r, c[1] - 0.72 * r, c[1] + 0.72 * r, c[2] - r, c[2] + r, role, R);
}

// --- long ape arms: right arm (+z) raised with a peeled banana, left arm (-z) hanging low with a bunch
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.18, 0.18, 2.6, 3.0, 0.82 * s, 0.9 * s, 'P', 0, DARK);
}
S('Arm');                                                       // raised arm: shoulder → elbow → wrist
const RS = [0.0, 2.86, 0.86], RE = [0.02, 2.4, 1.42], RW = [0.03, 3.12, 1.56];
tube(RS, RE, 0.18, 0.16, 'upper');
joint(RE, 0.18, 'upper');
tube(RE, RW, 0.19, 0.15, 'upper');                              // thick ape forearm tapering to the wrist
S('Wristband');
B(-0.17, 0.21, 3.1, 3.24, 1.37, 1.73, 'stripe', R);
S('Hand');
B(-0.18, 0.24, 3.22, 3.58, 1.36, 1.76, 'lower', R);
B(0.2, 0.32, 3.3, 3.46, 1.4, 1.54, 'lower');                     // thumb
const BZ = 1.56;                                                 // banana axis
S('PeeledBanana');
B(-0.08, 0.1, 3.56, 4.2, BZ - 0.09, BZ + 0.09, 'lower', R);     // cream fruit standing up
B(-0.05, 0.07, 4.2, 4.32, BZ - 0.06, BZ + 0.06, 'lower');
B(-0.08, 0.1, 3.1, 3.22, BZ - 0.09, BZ + 0.09, 'prop');          // banana end below the fist
B(-0.03, 0.05, 3.02, 3.1, BZ - 0.04, BZ + 0.04, 'P', 0, TIP);
S('BananaPeel');                                                 // four peel flaps flopping down
B(0.1, 0.16, 3.2, 3.74, BZ - 0.09, BZ + 0.09, 'prop');
B(-0.14, -0.08, 3.2, 3.74, BZ - 0.09, BZ + 0.09, 'prop');
B(-0.08, 0.1, 3.2, 3.74, BZ + 0.09, BZ + 0.23, 'prop');
B(-0.08, 0.1, 3.24, 3.66, BZ - 0.23, BZ - 0.09, 'prop');
S('Arm');                                                       // hanging arm: shoulder → elbow → wrist
const LS = [0.0, 2.86, -0.86], LE = [0.08, 1.95, -1.18], LW = [0.12, 1.02, -1.22];
tube(LS, LE, 0.18, 0.16, 'upper');
joint(LE, 0.18, 'upper');
tube(LE, LW, 0.19, 0.15, 'upper');
S('Wristband');
B(-0.13, 0.27, 0.9, 1.04, -1.43, -1.01, 'stripe', R);
S('Hand');
B(-0.14, 0.3, 0.6, 0.94, -1.46, -0.98, 'lower', R);
B(0.28, 0.4, 0.68, 0.84, -1.12, -0.98, 'lower');                 // thumb
S('BananaBunch');                                               // three bananas curving out and down
for (const [x, dz] of [[-0.14, 0.04], [0.06, -0.06], [0.26, 0.02]]) {
	const z = -1.22 + dz;
	B(x - 0.08, x + 0.08, 0.36, 0.66, z - 0.09, z + 0.09, 'prop', R);
	B(x - 0.02, x + 0.16, 0.12, 0.4, z - 0.08, z + 0.08, 'prop', R);
	B(x + 0.04, x + 0.16, 0.05, 0.12, z - 0.05, z + 0.05, 'P', 0, TIP);
}

// --- bent legs as connected tubes (knees forward), big cream feet, light-up soles
for (const s of [1, -1]) {
	const zc = 0.32 * s;
	S('Leg');                                                    // hip → knee (forward) → ankle
	const H = [0.04, 1.56, zc], Kn = [0.2, 1.0, zc * 1.06], A = [0.0, 0.36, zc];
	tube(H, Kn, 0.22, 0.2, 'upper');
	joint(Kn, 0.21, 'upper');
	tube(Kn, A, 0.19, 0.15, 'upper');
	S('ShortsLeg');
	B(-0.17, 0.33, 1.3, 1.5, zc - 0.25, zc + 0.25, 'skin2', R);
	S('Foot');
	B(-0.28, 0.56, 0.06, 0.34, zc - 0.24, zc + 0.24, 'foot', R);
	for (const dz of [-0.14, 0, 0.14]) B(0.56, 0.64, 0.08, 0.22, zc + dz - 0.06, zc + dz + 0.06, 'foot');   // toes
	S('Sole');
	B(-0.28, 0.56, 0, 0.06, zc - 0.24, zc + 0.24, 'accent', E);
}

// --- mirror left/right so the raised peeled-banana arm is on the viewer-facing side, as in the
// sculpture's front three-quarter capture
for (const p of parts) { const z0 = p.min[2], z1 = p.max[2]; p.min[2] = -z1; p.max[2] = -z0; }

// Dopamine high-contrast palette (docs/creatures/V4/BRT_009_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#1FD65A', skin: '#1FD65A', feather: '#FF8A1A', feather2: '#FF2D95', skin2: '#7B2BFF', lower: '#FFF0C8', foot: '#FFF0C8', trim: '#0B6B2E', prop: '#FFF200', stripe: '#2EF2FF', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (owner, animation review): elbows and knees. The limbs are tubes along
// shoulder-elbow-wrist and hip-knee-ankle paths, so the lower half of each tube, with the hand,
// wristband, bananas, foot and sole, hangs off a joint at the elbow or knee. The rounded joint
// ball stays on the upper segment and hides the bend. Coordinates are after the mirror above:
// the hanging arm is the creature's Right (+z), the raised arm its Left (-z).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: {
		BananaBunch: 'RightForearm', PeeledBanana: 'LeftForearm', BananaPeel: 'LeftForearm',
		Wristband: '{side}Forearm', Hand: '{side}Forearm', Foot: '{side}LowerLeg', Sole: '{side}LowerLeg',
		ShoulderHump: 'Torso', Muzzle: 'Head',
	},
	extraBones: {
		RightForearm: { parent: 'RightArm', pivot: [0.08, 1.95, 1.18] },
		LeftForearm: { parent: 'LeftArm', pivot: [0.02, 2.4, -1.42] },
		RightLowerLeg: { parent: 'RightLeg', pivot: [0.2, 1.0, 0.339] },
		LeftLowerLeg: { parent: 'LeftLeg', pivot: [0.2, 1.0, -0.339] },
	},
	regions: [
		{ bone: 'RightForearm', region: [-1, 1, 0, 1.94, 0.9, 2], only: /^Arm$/ },      // hanging forearm: below the elbow
		{ bone: 'LeftForearm', region: [-1, 1, 2.2, 4, -2, -1.43], only: /^Arm$/ },     // raised forearm: outboard of the elbow
		{ bone: 'RightLowerLeg', region: [-1, 1, 0, 0.99, 0, 0.8], only: /^Leg$/ },
		{ bone: 'LeftLowerLeg', region: [-1, 1, 0, 0.99, -0.8, 0], only: /^Leg$/ },
	],
};
