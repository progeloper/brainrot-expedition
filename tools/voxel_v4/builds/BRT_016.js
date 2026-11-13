// BRT_016 Gorillo Subwoofero — Voxel V4 build (CP-B, Uncommon, revision 4).
// Concept: a gorilla fused with a subwoofer, the "bass drop" gorilla. Online sources confirm only
// that core idea.
// Revision 3 (owner chose "speakers built into muscles" and "black fur, neon speakers"):
// - an upright bodybuilder gorilla: broad chest, big deltoids, a narrow waist with a six-pack,
//   short thick legs
// - glowing cyan woofers set into the pecs and glowing magenta woofers set into both biceps
// - near-black fur, a grey face with a crest, a heavy brow, a flat nose and a confident toothy grin
// Revision 4 (owner): "arms don't look riggable": the raised double-biceps flex is replaced by arms
//   hanging in a neutral A-pose, with shoulder, elbow and wrist collars and fists at the hips.
// Limbs are symmetric pairs (rig-ready).
// V4 core rules: kit anime eyes (Ocean; lash, catchlights) under the brow, glowing Neon speaker
// rings, light-up soles, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#0C0C14';
const CONE = '#06060C';
const IVORY = '#FFF6DE';

function tube(a, b, r0, r1, role) {
	const L = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
	const n = Math.max(1, Math.ceil(L / 0.26));
	for (let k = 0; k < n; k++) {
		const t0 = k / n, t1 = (k + 1) / n, r = r0 + (r1 - r0) * (t0 + t1) / 2;
		const c0 = a.map((v, i) => v + (b[i] - v) * t0), c1 = a.map((v, i) => v + (b[i] - v) * t1);
		B(Math.min(c0[0], c1[0]) - r, Math.max(c0[0], c1[0]) + r, Math.min(c0[1], c1[1]) - r, Math.max(c0[1], c1[1]) + r,
			Math.min(c0[2], c1[2]) - r, Math.max(c0[2], c1[2]) + r, role, R);
	}
}
// recessed woofer facing +x: glowing ring, dark cone, chrome dust cap (octagonal)
function woofer(x, y, z, r, ringRole) {
	S('SpeakerRing');
	B(x, x + 0.04, y - r, y + r, z - 0.42 * r, z + 0.42 * r, ringRole, E);
	B(x, x + 0.04, y - 0.42 * r, y + 0.42 * r, z - r, z + r, ringRole, E);
	B(x, x + 0.04, y - 0.74 * r, y + 0.74 * r, z - 0.74 * r, z + 0.74 * r, ringRole, E);
	S('SpeakerCone');
	B(x + 0.03, x + 0.08, y - 0.6 * r, y + 0.6 * r, z - 0.6 * r, z + 0.6 * r, 'P', 0, CONE);
	S('SpeakerCap');
	B(x + 0.07, x + 0.12, y - 0.22 * r, y + 0.22 * r, z - 0.22 * r, z + 0.22 * r, 'lower', R);
}

// --- V-shaped bodybuilder torso: broad chest (the Body), narrow waist with a six-pack
S('Body');
B(-0.5, 0.55, 1.6, 2.55, -0.85, 0.85, 'upper', R);
S('ChestRound');
B(-0.42, 0.62, 1.7, 2.45, -0.7, 0.7, 'upper', R);
S('Waist');
B(-0.42, 0.46, 1.04, 1.62, -0.55, 0.55, 'upper', R);
S('SixPack');
for (const y of [1.14, 1.3, 1.46]) for (const z of [-0.14, 0.14]) B(0.46, 0.52, y, y + 0.13, z - 0.12, z + 0.12, 'feather', R);
// glowing cyan woofers set into the pecs
for (const z of [-0.36, 0.36]) woofer(0.62, 2.12, z, 0.3, 'stripe');

// --- big deltoids and arms in a neutral, riggable A-pose (symmetric): shoulder -> elbow -> wrist with
// clear joint collars, magenta woofers set into the biceps on the front of each upper arm
for (const s of [1, -1]) {
	S('Deltoid');
	B(-0.36, 0.4, 2.2, 2.8, 0.78 * s, 1.2 * s, 'upper', R);
	S('UpperArm');
	tube([0.0, 2.42, 1.04 * s], [0.06, 1.7, 1.22 * s], 0.28, 0.26, 'upper');
	S('Biceps');
	B(0.08, 0.34, 1.86, 2.3, 0.98 * s, 1.32 * s, 'upper', R);      // biceps bulge on the front of the arm
	woofer(0.34, 2.08, 1.15 * s, 0.15, 'accent');
	S('ElbowCollar');
	B(-0.2, 0.3, 1.6, 1.72, (1.22 - 0.25) * s, (1.22 + 0.25) * s, 'P', 0, DARK);
	S('Forearm');
	tube([0.06, 1.66, 1.22 * s], [0.12, 0.98, 1.28 * s], 0.26, 0.22, 'upper');
	S('WristCollar');
	B(-0.12, 0.34, 0.9, 1.0, (1.28 - 0.22) * s, (1.28 + 0.22) * s, 'P', 0, DARK);
	S('Fist');
	B(-0.14, 0.4, 0.52, 0.92, (1.28 - 0.24) * s, (1.28 + 0.24) * s, 'foot', R);
	for (const dy of [-0.12, 0.0, 0.12]) B(0.4, 0.48, 0.66 + dy, 0.74 + dy, (1.28 - 0.18) * s, (1.28 + 0.18) * s, 'foot');   // knuckles
}

// --- gorilla head sitting low between the shoulders: crest, grey face, brow, muzzle, grin
S('Head');
B(-0.06, 0.74, 2.5, 3.28, -0.5, 0.5, 'upper', R);
S('Crest');
B(0.08, 0.56, 3.28, 3.42, -0.13, 0.13, 'upper', R);
S('Face');
B(0.66, 0.84, 2.56, 3.06, -0.42, 0.42, 'skin2', 0);
S('Muzzle');
B(0.8, 1.08, 2.36, 2.62, -0.34, 0.34, 'skin2', R);
S('Nose');
B(1.0, 1.12, 2.52, 2.64, -0.18, 0.18, 'P', 0, '#2A2A3A');
S('Nostril');
MZ(1.12, 1.14, 2.55, 2.61, 0.04, 0.13, 'P', 0, CONE);
S('Mouth');
B(1.08, 1.1, 2.38, 2.5, -0.26, 0.26, 'P', 0, CONE);
MZ(1.0, 1.1, 2.46, 2.56, 0.24, 0.32, 'P', 0, CONE);
S('Teeth');
B(1.09, 1.12, 2.42, 2.5, -0.23, 0.23, 'P', 0, IVORY);
const FX = 0.84;
for (const out of [1, -1]) frontEye({ faceX: FX, zc: 0.2 * out, top: 3.04, L: 0.7, H: 0.64, out, iris: 'Ocean', lash: true, blush: false });
S('BrowRidge');
B(0.68, 0.94, 3.06, 3.18, -0.46, 0.46, 'upper', R);
S('NeckCollar');
B(-0.3, 0.4, 2.5, 2.58, -0.46, 0.46, 'P', 0, DARK);

// --- short thick legs (symmetric pair), dark hip collars, big feet, light-up soles
for (const s of [1, -1]) {
	const zc = 0.38 * s;
	S('HipCollar');
	B(-0.3, 0.3, 0.98, 1.1, zc - 0.3, zc + 0.3, 'P', 0, DARK);
	S('Leg');
	tube([0.0, 1.04, zc], [0.05, 0.34, zc], 0.3, 0.26, 'upper');
	S('Foot');
	B(-0.32, 0.58, 0.04, 0.32, zc - 0.3, zc + 0.3, 'foot', R);
	S('Sole');
	B(-0.32, 0.58, 0, 0.04, zc - 0.3, zc + 0.3, 'accent', E);
}

// Black fur, neon speakers (owner) with dopamine neon accents; mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#1C1C2A', skin2: '#6E6E8A', feather: '#34344C', foot: '#3A3A52', stripe: '#2EF2FF', accent: '#FF2DD1', lower: '#DDE6F2', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js. Animation pass (13 Nov 2026): the mouth and teeth go on the head
// (they were left on the torso), the head turns from its neck, each leg gets a knee, and the cone and dust cap of
// each chest woofer get a joint so the speakers can pump. The deltoids stay on the chest as shoulder caps (on the arm
// they swung into the chest and head), and every piece of each biceps speaker goes on its arm (one ring piece per
// arm was left on the torso).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { Mouth: 'Head', Teeth: 'Head', Deltoid: 'Torso' },
	headPivot: [0.3, 2.55, 0],
	extraBones: {
		RightLowerLeg: { parent: 'RightLeg', pivot: [0.03, 0.8, 0.38] },
		LeftLowerLeg: { parent: 'LeftLeg', pivot: [0.03, 0.8, -0.38] },
		RightWoofer: { parent: 'Torso', pivot: [0.62, 2.12, 0.36] },
		LeftWoofer: { parent: 'Torso', pivot: [0.62, 2.12, -0.36] },
	},
	regions: [
		{ bone: 'RightLowerLeg', region: [-1, 1, 0, 0.8, 0, 1], only: /^(Leg|Foot|Sole)$/ },
		{ bone: 'LeftLowerLeg', region: [-1, 1, 0, 0.8, -1, 0], only: /^(Leg|Foot|Sole)$/ },
		{ bone: 'RightWoofer', region: [0.6, 0.8, 1.7, 2.5, 0, 0.8], only: /^(SpeakerCone|SpeakerCap)$/ },
		{ bone: 'LeftWoofer', region: [0.6, 0.8, 1.7, 2.5, -0.8, 0], only: /^(SpeakerCone|SpeakerCap)$/ },
		{ bone: 'RightArm', region: [0.2, 0.6, 1.7, 2.5, 0.8, 1.6], only: /^(SpeakerRing|SpeakerCone|SpeakerCap)$/ },
		{ bone: 'LeftArm', region: [0.2, 0.6, 1.7, 2.5, -1.6, -0.8], only: /^(SpeakerRing|SpeakerCone|SpeakerCap)$/ },
	],
};
