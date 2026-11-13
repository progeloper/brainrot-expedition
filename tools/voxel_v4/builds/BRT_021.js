// BRT_021 Cacto Hipopotamo — Voxel V4 build (CP-C, Rare, revision 4).
// Revision 3 (owner): "go off online references for a steal a brainrot and v4 it". This follows the
// Steal a Brainrot in-game model (stealabrainrot.noob.wiki picture; "a tall cactus ... it wears yellow
// slippers and sports a hippo's face"):
// - a slim, tall ribbed cactus column dotted with yellow spines
// - a blocky grey hippo face on the upper front: big muzzle, nostrils, two little buck teeth, small round
//   ears
// - no visible legs or arms: the column stands straight on two big yellow slippers that splay outward,
//   with green cactus toes showing
// The V4 take:
// - a crisp, ribbed bright-green column with dark grooves and a grid of glowing yellow spine dots
// - a chunky lavender-grey hippo face with a big pale muzzle, two buck teeth, pink ears and blush, and
//   slightly narrowed amber anime eyes (a cool Rare look)
// - the gag: giant splayed yellow slippers with orange trim, green cactus toes and glowing soles
// Revision 4 (owner): "make the slippers bottom flat to the ground and remember riggable feet": short
//   cactus legs with hip and ankle collars, slippers pointing straight ahead on one flat sole each.
// Rig-ready (owner rule): the legs and slippers are a matching pair in a neutral pose.
// V4 core rules: kit anime eyes (Amber; lids, catchlights, blush) on white eye domes, glowing Neon spine
// dots and soles, studs on body panels only. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const INK = '#141018';
const IVORY = '#FFF6DE';

function layer(cx, y0, y1, r, role, rel = R) {
	B(cx - r, cx + r, y0, y1, -0.7 * r, 0.7 * r, role, rel);
	B(cx - 0.66 * r, cx + 0.66 * r, y0, y1, -r, r, role, rel);
}

// --- slim, tall ribbed cactus column standing straight on the slippers (the Body)
const W = 0.62, Y0 = 0.66, Y1 = 4.3;                           // revision 4: raised onto short legs
S('Body');
B(-W, W, Y0, Y1, -0.72 * W, 0.72 * W, 'upper', R);
S('Cactus');
B(-0.7 * W, 0.7 * W, Y0, Y1, -W, W, 'upper', R);
layer(0, Y1, Y1 + 0.2, 0.5, 'upper');
layer(0, Y1 + 0.2, Y1 + 0.32, 0.3, 'upper');
// dark grooves between the ribs: two on each face (the front grooves stop under the face)
S('RibGroove');
for (const g of [-0.2, 0.2]) {
	B(-W - 0.03, -W + 0.01, Y0, Y1, g - 0.03, g + 0.03, 'feather', 0);                 // back
	B(W - 0.01, W + 0.03, Y0, 2.62, g - 0.03, g + 0.03, 'feather', 0);                 // front
	B(g - 0.03, g + 0.03, Y0, Y1, W - 0.01, W + 0.03, 'feather', 0);                   // right side
	B(g - 0.03, g + 0.03, Y0, Y1, -W - 0.03, -W + 0.01, 'feather', 0);                 // left side
}
// a grid of glowing yellow spine dots on the ribs (offset rows, like the game model's texture)
S('SpineDot');
const ROWS = [1.05, 1.5, 1.95, 2.4, 2.85, 3.3, 3.85];
ROWS.forEach((y, k) => {
	for (const c of k % 2 ? [0] : [-0.4, 0.4]) {
		B(c - 0.04, c + 0.04, y - 0.04, y + 0.04, W + 0.01, W + 0.06, 'stripe', E);           // right side
		B(c - 0.04, c + 0.04, y - 0.04, y + 0.04, -W - 0.06, -W - 0.01, 'stripe', E);         // left side
		B(-W - 0.06, -W - 0.01, y - 0.04, y + 0.04, c - 0.04, c + 0.04, 'stripe', E);         // back
		if (y < 2.6) B(W + 0.01, W + 0.06, y - 0.04, y + 0.04, c - 0.04, c + 0.04, 'stripe', E);   // front
	}
});

const FACE_START = parts.length;
// --- chunky hippo face on the upper front of the column
S('Head');
B(0.3, 1.0, 2.5, 3.66, -0.62, 0.62, 'skin', R);
S('Muzzle');                                                    // big pale hippo muzzle
B(0.96, 1.5, 2.36, 3.1, -0.66, 0.66, 'skin2', R);
B(1.5, 1.58, 2.46, 3.0, -0.54, 0.54, 'skin2');
S('Nostril');
MZ(1.58, 1.6, 2.86, 2.98, 0.16, 0.32, 'P', 0, INK);
S('Mouth');
B(1.58, 1.6, 2.5, 2.56, -0.4, 0.4, 'P', 0, INK);
S('BuckTooth');                                                 // two little buck teeth
MZ(1.52, 1.62, 2.32, 2.5, 0.04, 0.16, 'P', 0, IVORY);
S('Cheek');
MZ(1.2, 1.46, 2.5, 2.74, 0.66, 0.68, 'feather2');
for (const s of [1, -1]) {
	S('Ear');
	B(0.4, 0.62, 3.66, 3.9, 0.36 * s, 0.6 * s, 'skin', R);
	S('InnerEar');
	B(0.62, 0.64, 3.7, 3.86, 0.4 * s, 0.56 * s, 'feather2');
}
// slightly narrowed amber anime eyes on white domes (a cool Rare look), tiny brows with a gap
const FX = 1.1;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.86, FX, 3.06, 3.62, 0.04 * out, 0.54 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.29 * out, top: 3.58, L: 0.92, H: 0.84, out, iris: 'Amber', lash: false, blush: false });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer), zm = (z0 + z1) / 2;
	S('Lid');
	B(FX, FX + 0.07, eye.whiteTop - 0.14, eye.whiteTop + 0.02, z0 - 0.03, z1 + 0.03, 'skin');
	B(FX, FX + 0.08, eye.whiteTop - 0.18, eye.whiteTop - 0.14, z0 - 0.02, z1 + 0.02, 'P', 0, INK);
	S('Brow');
	B(0.88, FX + 0.06, eye.whiteTop + 0.04, eye.whiteTop + 0.08, zm - 0.1, zm + 0.1, 'P', 0, INK);
}

for (const p of parts.slice(FACE_START)) { p.min[1] += 0.26; p.max[1] += 0.26; }   // face rides up with the taller column

// --- revision 4 (owner): riggable feet, slipper bottoms flat on the ground. Short cactus legs (a
// matching pair) with dark hip and ankle collars carry giant yellow slippers that point straight ahead,
// each on one flat sole, with green cactus toes and glowing soles
const DARK = '#1D2133';
for (const s of [1, -1]) {
	const zc = 0.46 * s;
	S('HipCollar');
	B(-0.24, 0.24, 0.62, 0.7, zc - 0.24, zc + 0.24, 'P', 0, DARK);
	S('Leg');
	B(-0.22, 0.22, 0.36, 0.64, zc - 0.22, zc + 0.22, 'upper', R);
	S('AnkleCollar');
	B(-0.23, 0.23, 0.3, 0.37, zc - 0.23, zc + 0.23, 'P', 0, DARK);
	S('Foot');                                                  // green cactus foot inside the slipper
	B(-0.32, 0.86, 0.2, 0.36, zc - 0.28, zc + 0.28, 'upper', R);
	S('CactusToe');                                             // green toes poking out the front
	for (const dz of [-0.19, 0, 0.19]) B(0.86, 1.06, 0.2, 0.34, zc + dz - 0.08, zc + dz + 0.08, 'upper', R);
	S('SlipperSole');                                           // one flat sole on the ground
	B(-0.5, 1.16, 0.04, 0.2, zc - 0.36, zc + 0.36, 'prop', R);
	S('SlipperUpper');                                          // the strap band over the foot
	B(0.16, 0.8, 0.2, 0.46, zc - 0.36, zc + 0.36, 'prop', R);
	S('SlipperTrim');
	B(0.14, 0.82, 0.44, 0.5, zc - 0.37, zc + 0.37, 'trim');
	S('Sole');
	B(-0.5, 1.16, 0, 0.04, zc - 0.36, zc + 0.36, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_021_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#35D94F', feather: '#13782E', skin: '#A79BD0', skin2: '#D2C9F2', feather2: '#FF7FB8', prop: '#FFD21A', trim: '#FF8A1F', stripe: '#FFF04D', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass): six glowing spine dots beside the face had been swept onto the
// head bone with the face. They belong to the cactus column, so they stay on the Torso and the
// face moves as one rigid group without dragging dots across the ribs.
if (typeof module !== 'undefined') module.exports.rigOverrides = { slots: { BuckTooth: 'Head', SpineDot: 'Torso' } };
