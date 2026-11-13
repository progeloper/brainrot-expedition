// BRT_004 Ballerina Banana — Voxel V4 build (CP-B, revision 4).
// Owner direction (revision 4): "too wide, should be more oblong and thin", and match the accepted
// Studio sculpture closely (assets/BRT_004_Ballerina_Banana_Studio/, revision 4):
// - a slim upright banana: yellow peel body, cream fruit top leaning slightly, brown tip
// - four peels folded down from the peel line, with brown tips
// - big eyes just under the peel line, brows, blush and an open smile
// - dark stick arms both raised and bent up
// - a pink tutu with a violet rim and a turquoise bow, two short pale legs planted in pink pointe
//   shoes with turquoise ribbon wraps
// V4 core rules: kit anime eyes (lash, catchlights, blush), glowing Neon peel line, glowing tutu hem,
// light-up soles, studs on body panels only, dark joint collars. Dopamine palette.
// Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const MOUTH = '#6E0E2C';
const TIP = '#5A2E12';

// --- slim banana torso (oblong stepped octagon); the Body is the largest upper box
const H = 0.45, C = 0.08;                              // half-width and chamfer
const Y0 = 1.95, PL = 4.4;                             // bottom (inside the tutu) and peel line
S('Body');
B(-H, H, Y0, PL, -H, H, 'upper', R);
S('BodyFace');                                         // smooth front plate carrying the face
B(-(H - C), H + C, Y0 + 0.1, PL, -(H - C), H - C, 'upper', 0);
S('BodyRound');
B(-(H + C), -(H - C), Y0 + 0.1, PL, -(H - C), H - C, 'upper', R);
B(-(H - C), H - C, Y0 + 0.1, PL, -(H + C), H + C, 'upper', R);
// glowing peel line
S('PeelLine');
B(-(H + C + 0.02), H + C + 0.02, PL, PL + 0.1, -(H - C), H - C, 'stripe', E);
B(-(H - C), H - C, PL, PL + 0.1, -(H + C + 0.02), H + C + 0.02, 'stripe', E);
// peeled cream fruit leaning slightly to one side, tapering to a brown tip
S('Fruit');
for (const [y0, y1, cz, h] of [[PL + 0.1, 4.95, 0.0, 0.42], [4.95, 5.35, 0.05, 0.35], [5.35, 5.7, 0.12, 0.26]]) {
	B(-h, h, y0, y1, cz - h + 0.07, cz + h - 0.07, 'lower', R);
	B(-h + 0.07, h - 0.07, y0, y1, cz - h, cz + h, 'lower', R);
}
S('Stem');
B(-0.11, 0.11, 5.7, 5.92, 0.08, 0.3, 'P', 0, TIP);

// --- four peels folded down from the peel line (front-side and back-side on each flank)
for (const s of [1, -1]) for (const [x0, x1] of [[0.02, 0.36], [-0.4, -0.06]]) {
	S('Peel');
	B(x0, x1, PL - 0.05, PL + 0.12, (H + C) * s, 0.72 * s, 'upper', R);       // folds out over the rim
	B(x0, x1, PL - 0.55, PL + 0.05, 0.62 * s, 0.76 * s, 'upper', R);          // hangs down
	B(x0 + 0.02, x1 - 0.02, PL - 0.8, PL - 0.5, 0.7 * s, 0.88 * s, 'upper');  // curls outward
	S('PeelTip');
	B(x0 + 0.04, x1 - 0.04, PL - 0.92, PL - 0.78, 0.76 * s, 0.92 * s, 'P', 0, TIP);
}

// --- face: big kit anime eyes (Violet), bold violet brows, blush, open smile with teeth and tongue
const FX = H + C;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.2 * out, top: 4.32, L: 0.7, H: 1.22, out, iris: 'Violet', lash: true, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Brow');
	B(FX, FX + 0.1, eye.lashTop + 0.02, eye.lashTop + 0.12, z0, z1, 'trim');
}
S('Mouth');
B(FX, FX + 0.03, 2.9, 3.18, -0.2, 0.2, 'P', 0, MOUTH);
MZ(FX, FX + 0.03, 3.1, 3.28, 0.2, 0.28, 'P', 0, MOUTH);          // upturned corners
S('Teeth');
B(FX + 0.01, FX + 0.04, 3.1, 3.18, -0.18, 0.18, 'P', 0, '#FFFFFF');
S('Tongue');
B(FX + 0.01, FX + 0.04, 2.9, 3.01, -0.12, 0.08, 'P', 0, '#FF4F7A');

// --- stick arms (deep plum), both raised and bent up, dark shoulder collars, cream gloves
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.13, 0.15, 2.94, 3.22, (H + C - 0.02) * s, (H + C + 0.08) * s, 'P', 0, DARK);
	S('Arm');
	B(-0.09, 0.11, 2.98, 3.18, (H + C + 0.06) * s, 0.95 * s, 'skin', R);      // upper arm out to the side
	B(-0.09, 0.11, 3.1, 3.42, 0.88 * s, 1.15 * s, 'skin', R);               // elbow lifting
	B(-0.09, 0.11, 3.36, 4.3, 1.04 * s, 1.24 * s, 'skin', R);               // forearm raised
	S('Glove');
	B(-0.13, 0.15, 4.26, 4.56, 0.98 * s, 1.3 * s, 'lower', R);
}

// --- tutu: two stepped pink tiers with a violet rim, glowing hem, waistband and turquoise bow
S('Tutu');
for (const [y0, y1, r, c] of [[1.78, 1.96, 1.1, 0.85], [1.96, 2.2, 0.82, 0.62]]) {
	const k = r + 0.17;
	B(-r, r, y0, y1, -r, r, 'skin2', R);
	B(-c, c, y0, y1, -k, k, 'skin2', R);
	B(-k, k, y0, y1, -c, c, 'skin2', R);
}
S('TutuRim');
B(-1.12, 1.12, 1.72, 1.78, -1.12, 1.12, 'trim');
B(-0.87, 0.87, 1.72, 1.78, -1.29, 1.29, 'trim');
B(-1.29, 1.29, 1.72, 1.78, -0.87, 0.87, 'trim');
S('TutuHem');
B(-1.0, 1.0, 1.68, 1.72, -1.0, 1.0, 'accent', E);
S('Waistband');
B(-(H + C + 0.04), H + C + 0.04, 2.2, 2.34, -(H + C + 0.04), H + C + 0.04, 'trim');
S('Bow');
MZ(H + C + 0.04, H + C + 0.16, 2.12, 2.48, 0.05, 0.32, 'prop', R);
B(H + C + 0.06, H + C + 0.2, 2.2, 2.38, -0.08, 0.08, 'lower');

// --- two short pale legs planted in pink pointe shoes with turquoise ribbon wraps
for (const s of [1, -1]) {
	const zc = 0.3 * s;
	S('HipCollar');
	B(-0.2, 0.2, 1.6, 1.72, zc - 0.2, zc + 0.2, 'P', 0, DARK);
	S('Leg');
	B(-0.14, 0.14, 0.5, 1.7, zc - 0.14, zc + 0.14, 'feather', R);
	S('Ribbon');
	B(-0.16, 0.16, 0.62, 0.72, zc - 0.16, zc + 0.16, 'prop');
	B(-0.16, 0.16, 0.86, 0.96, zc - 0.16, zc + 0.16, 'prop');
	S('PointeShoe');
	B(-0.2, 0.3, 0.1, 0.52, zc - 0.19, zc + 0.19, 'foot', R);
	B(0.3, 0.42, 0.1, 0.34, zc - 0.13, zc + 0.13, 'foot');
	S('Sole');
	B(-0.2, 0.42, 0, 0.1, zc - 0.17, zc + 0.17, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_004_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FFE014', lower: '#FFF6D2', stripe: '#2EF2FF', trim: '#7B1FD1', skin: '#2A1640', skin2: '#FF3FA8', feather: '#FFF0B0', foot: '#E0157F', prop: '#00E5D4', accent: '#B6FF2E', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig (animation brief v5, 13 Nov 2026): the tutu sits on its own bone (signature prop) so the skirt can lag
// and swish when she turns. Waistband and bow stay on the body.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	extraBones: { Tutu: { parent: 'Torso', pivot: [0, 2.0, 0] } },
	slots: { Tutu: 'Tutu', TutuRim: 'Tutu', TutuHem: 'Tutu' },
};
