// BRT_024 Nooo My Hotspot — Voxel V4 build (CP-C, Rare, revision 2).
// Reference: the Steal a Brainrot in-game model (stealabrainrot.noob.wiki picture; "a sad burrito with
// black limbs, holding a white phone with a Wi-Fi signal in front of it, representing a struggling
// connection"; called "Hotspotini Burrito" in Plants & Brainrots):
// - a tan tortilla burrito with lettuce and tomato spilling from the top
// - a sad face, thin black limbs, a white phone held in front, black Wi-Fi arcs floating nearby
// Revision 2 (owner): "check online references and add a higher dopamine leaning v4 style". The original
//   meme (brainrotcharacters.net) is a pale flour tortilla with char spots and a big overflowing topping
//   mound, huge googly eyes, worried black brows and black Wi-Fi arcs glowing red; the yumcut render gives
//   it teal limbs with black hands and shoes. So: char-spotted cream tortilla, overflowing cheese shreds,
//   peppers, tomato and beef, bolder worried brows, black-and-neon-red Wi-Fi arcs, electric teal limbs
//   with black gloves and shoes.
// The V4 take (revision 1; the game model slumps; it stands here in a neutral, riggable pose):
// - a golden tortilla burrito with toasted spots and wrap seams, and a riot of filling spilling from the
//   top: lime lettuce, red tomato, white rice, yellow cheese and beans
// - crying anime eyes (Ocean) with sad raised inner brows, glowing cyan tear streams and a wailing mouth
// - the gag: both black arms clutch a white phone held out to show its screen, a red no-signal X, while
//   glowing red Wi-Fi arcs flicker above his head
// Rig-ready (owner rule): black arms and legs are matching pairs with joint collars; flat white sneakers
// point straight ahead.
// V4 core rules: kit anime eyes (Ocean; thin lash line, catchlights, blush) on white eye domes, glowing Neon
// tears, Wi-Fi arcs and soles, studs on body panels only. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#3A3446';
const INK = '#141018';
const CHEESE = '#FFE14D';
const BEAN = '#6A2A10';

function layer(cx, y0, y1, r, role, rel = R) {
	B(cx - r, cx + r, y0, y1, -0.7 * r, 0.7 * r, role, rel);
	B(cx - 0.66 * r, cx + 0.66 * r, y0, y1, -r, r, role, rel);
}

// --- upright golden tortilla burrito (the Body), rounded bottom
S('Body');
B(-0.72, 0.72, 1.2, 3.2, -0.5, 0.5, 'upper', R);
S('Tortilla');
B(-0.48, 0.48, 1.2, 3.2, -0.72, 0.72, 'upper', R);
layer(0, 0.98, 1.2, 0.56, 'upper');
S('WrapSeam');                                                  // folded wrap seams
for (const y of [1.55, 2.95]) layer(0, y - 0.03, y + 0.03, 0.74, 'skin2', 0);
B(0.72, 0.76, 1.2, 3.2, -0.62, -0.54, 'skin2', 0);
S('ToastSpot');
for (const [y, z] of [[1.4, 0.4], [2.6, -0.42], [3.05, 0.3]]) B(0.72, 0.75, y - 0.07, y + 0.07, z - 0.09, z + 0.09, 'feather', 0);
for (const s of [1, -1]) for (const [x, y] of [[0.2, 1.8], [-0.3, 2.5]]) {
	const z = s > 0 ? [0.72, 0.75] : [-0.75, -0.72];
	B(x - 0.09, x + 0.09, y - 0.07, y + 0.07, ...z, 'feather', 0);
}
for (const [y, z] of [[1.6, 0.2], [2.4, -0.2], [2.9, 0.25]]) B(-0.75, -0.72, y - 0.07, y + 0.07, z - 0.09, z + 0.09, 'feather', 0);

// --- revision 2: a big overflowing topping mound (original meme): lettuce, peppers, tomato, beef, cheese
S('Lettuce');
layer(0, 3.2, 3.34, 0.66, 'feather2');
S('ToppingMound');
B(-0.42, 0.58, 3.34, 3.5, -0.35, 0.35, 'P', 0, BEAN);
B(-0.25, 0.41, 3.34, 3.5, -0.5, 0.5, 'P', 0, BEAN);
S('Tomato');
for (const [x, z] of [[0.2, 0.22], [-0.28, -0.12], [0.48, -0.32], [-0.1, 0.46]]) B(x - 0.13, x + 0.13, 3.44, 3.66, z - 0.13, z + 0.13, 'prop', R);
S('Pepper');
for (const [x, z] of [[0.55, 0.3], [-0.45, -0.45], [0.05, -0.5]]) B(x - 0.12, x + 0.12, 3.4, 3.62, z - 0.1, z + 0.1, 'feather2', 0);
S('Cheese');                                                    // yellow cheese shreds sticking out
for (const [x, z, h] of [[0.3, -0.05, 0.3], [-0.2, 0.2, 0.26], [0.6, 0.0, 0.2], [0.0, -0.3, 0.24], [-0.45, 0.3, 0.2]]) B(x - 0.035, x + 0.035, 3.46, 3.46 + h, z - 0.12, z + 0.12, 'P', 0, CHEESE);
S('Beef');
for (const [x, z] of [[-0.1, 0.0], [0.32, 0.44], [-0.4, -0.2]]) B(x - 0.08, x + 0.08, 3.5, 3.6, z - 0.08, z + 0.08, 'P', 0, BEAN);

// --- crying face: big anime eyes, sad raised inner brows, glowing tear streams, wailing mouth
const FX = 0.74;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.56, FX, 2.4, 3.0, 0.04 * out, 0.5 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.27 * out, top: 2.96, L: 0.88, H: 0.84, out, iris: 'Ocean', lash: false, blush: true });
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, Math.min(eye.inner, eye.outer) - 0.01, Math.max(eye.inner, eye.outer) + 0.01, 'P', 0, '#000000');
	const zin = eye.inner, zout = eye.outer, zm = (zin + zout) / 2;
	S('Brow');                                                  // sad: the inner end is raised
	B(0.56, FX + 0.06, eye.whiteTop + 0.12, eye.whiteTop + 0.18, Math.min(zin, zm), Math.max(zin, zm), 'P', 0, INK);
	B(0.56, FX + 0.06, eye.whiteTop + 0.06, eye.whiteTop + 0.12, Math.min(zm, zout), Math.max(zm, zout), 'P', 0, INK);
	S('Tear');                                                  // glowing tear streams down the cheeks
	const zt = 0.27 * out + 0.2 * out;
	B(FX + 0.01, FX + 0.05, 1.86, 2.42, zt - 0.05, zt + 0.05, 'accent', E);
	B(FX, FX + 0.08, 1.76, 1.88, zt - 0.08, zt + 0.08, 'accent', E);
}
S('Mouth');                                                     // wailing open mouth
B(0.74, 0.77, 1.96, 2.28, -0.24, 0.24, 'P', 0, INK);
B(0.74, 0.78, 2.0, 2.1, -0.16, 0.16, 'P', 0, '#FF4F7A');

// --- the gag: black arms (matching pair) clutching a white phone held out, red no-signal X on screen
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.12, 0.12, 2.42, 2.62, 0.7 * s, 0.76 * s, 'P', 0, DARK);
	S('UpperArm');
	B(-0.1, 0.1, 1.96, 2.56, 0.76 * s, 0.96 * s, 'trim', R);
	S('ElbowCollar');
	B(-0.11, 0.11, 1.9, 1.98, 0.75 * s, 0.97 * s, 'P', 0, DARK);
	S('Forearm');                                               // reaching forward, then angling in to the phone
	B(-0.1, 0.62, 1.74, 1.94, 0.76 * s, 0.96 * s, 'trim', R);
	B(0.52, 1.0, 1.74, 1.94, Math.min(0.42 * s, 0.84 * s), Math.max(0.42 * s, 0.84 * s), 'trim', R);
	S('Hand');                                                  // small white glove gripping the phone edge
	B(0.96, 1.2, 1.7, 1.98, Math.min(0.26 * s, 0.44 * s), Math.max(0.26 * s, 0.44 * s), 'foot', R);
}
S('Phone');
B(1.08, 1.18, 1.6, 2.46, -0.3, 0.3, 'P', 0, '#F4F4FF');
S('PhoneScreen');
B(1.18, 1.2, 1.68, 2.38, -0.24, 0.24, 'P', 0, '#141826');
S('NoSignalX');                                                 // red X on the screen (stepped diagonals)
for (const [y, z] of [[2.03, 0], [2.17, 0.12], [2.17, -0.12], [1.89, 0.12], [1.89, -0.12], [2.29, 0.2], [2.29, -0.2], [1.77, 0.2], [1.77, -0.2]]) {
	B(1.2, 1.22, y - 0.05, y + 0.05, z - 0.05, z + 0.05, 'stripe', E);
}

// --- glowing red Wi-Fi arcs flickering above the head (facing front)
S('WifiDot');
B(0.2, 0.3, 3.8, 3.94, -0.07, 0.07, 'P', 0, INK);
B(0.3, 0.33, 3.83, 3.91, -0.04, 0.04, 'stripe', E);
S('WifiArc');                                                   // black arcs with a glowing red core
function arcBox(y0, y1, z0, z1) {
	B(0.18, 0.3, y0 - 0.02, y1 + 0.02, Math.min(z0, z1) - 0.02, Math.max(z0, z1) + 0.02, 'P', 0, INK);
	B(0.3, 0.33, y0, y1, Math.min(z0, z1), Math.max(z0, z1), 'stripe', E);
}
for (const r of [0.28, 0.5, 0.72]) {
	const y0 = 3.88;
	arcBox(y0 + r, y0 + r + 0.08, -0.42 * r, 0.42 * r);
	for (const s of [1, -1]) {
		arcBox(y0 + 0.72 * r, y0 + 0.72 * r + 0.08, 0.42 * r * s, 0.82 * r * s);
		arcBox(y0 + 0.3 * r, y0 + 0.72 * r, 0.78 * r * s, 0.92 * r * s);
	}
}

// --- black legs (matching pair) with hip and knee collars, flat white sneakers, glowing soles
for (const s of [1, -1]) {
	const zc = 0.3 * s;
	S('HipCollar');
	B(-0.16, 0.16, 0.96, 1.04, zc - 0.16, zc + 0.16, 'P', 0, DARK);
	S('Thigh');
	B(-0.11, 0.11, 0.58, 1.0, zc - 0.11, zc + 0.11, 'trim', R);
	S('KneeCollar');
	B(-0.13, 0.13, 0.52, 0.6, zc - 0.13, zc + 0.13, 'P', 0, DARK);
	S('Shin');
	B(-0.1, 0.1, 0.24, 0.54, zc - 0.1, zc + 0.1, 'trim', R);
	S('Sneaker');
	B(-0.2, 0.4, 0.04, 0.26, zc - 0.17, zc + 0.17, 'foot', R);
	S('Sole');
	B(-0.2, 0.4, 0, 0.04, zc - 0.17, zc + 0.17, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_024_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FFD27A', feather: '#9A4A14', skin2: '#FFF0C4', feather2: '#3EE84A', prop: '#FF2D2D', trim: '#14C8CF', foot: '#17141E', stripe: '#FF2D55', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Animation rig (14 Nov 2026): the phone (with its screen and no-signal X) rides on the right
// forearm, so it moves with the hands that hold it; both arms lift it together.
if (typeof module !== 'undefined') module.exports.rigOverrides = { slots: { Phone: 'RightForearm', PhoneScreen: 'RightForearm', NoSignalX: 'RightForearm' } };
