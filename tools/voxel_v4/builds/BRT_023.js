// BRT_023 Giraffa Celeste — Voxel V4 build (CP-C, Rare, revision 2).
// References, which agree (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki,
// "Girafa Celestre") and the yumcut.com render ("a giraffe-watermelon hybrid with an astronaut
// helmet"):
// - a round half-watermelon body with its red cut face forward (seeds, white and green rind)
// - a giraffe head in a grey astronaut helmet on top; an orange spotted neck runs up the front of
//   the flesh
// - short legs in brown laced work boots
// Revision 2 (owner): "go off online resources especially referencing steal a brainrot and go even more
//   high dopamine v4 than the rest". Following the Steal a Brainrot model: a BIG boxy helmet covering the
//   giraffe's whole spotted face on top of the watermelon, no neck strip, tall brown boots. Pushed further:
//   electric green rind with lime stripes, hot pink-red flesh, a chrome helmet with a violet band, glowing
//   antenna and cyan visor rim, violet eyes, glowing laces and soles, five neon stars.
// The V4 take (revision 1, a Rare with a space aura):
// - a bright watermelon disc with a dark-striped green rind, white inner rind, red flesh and black
//   seeds
// - a spotted orange giraffe neck and face peeking out of a chunky silver astronaut helmet with a
//   glowing cyan visor rim, ossicones poking through the top and a side lamp; huge cyan anime eyes
// - the gag: a space giraffe wearing brown work boots, with glowing star sparkles around the helmet
// Rig-ready (owner rule): the legs are a matching pair with hip and knee collars and flat boots
// pointing straight ahead.
// V4 core rules: kit anime eyes (Ocean; thin lash, catchlights, blush) on white eye domes, glowing Neon
// visor rim, stars and soles, studs on body panels only. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const LACE = '#FFE2A8';

// disc helper: horizontal slabs of a circle (centre cy, radius r) in the y-z plane, from x0 to x1
const DCY = 1.95;
function disc(x0, x1, r, role, rel, bands) {
	for (const [b0, b1] of bands) {
		const y0 = DCY + (b0 - DCY) * r / 1.15, y1 = DCY + (b1 - DCY) * r / 1.15;   // bands scaled to this radius
		const ym = y0 < DCY && y1 > DCY ? 0 : Math.min(Math.abs(y0 - DCY), Math.abs(y1 - DCY));
		const hz = Math.sqrt(Math.max(0.02, r * r - ym * ym));
		B(x0, x1, y0, y1, -hz, hz, role, rel);
	}
}
const BANDS = [[0.8, 1.04], [1.04, 1.4], [1.4, 2.5], [2.5, 2.86], [2.86, 3.1]];

// --- round watermelon body: green rind (the middle band is the Body), white inner rind, red flesh
S('Body');
B(-0.5, 0.4, 1.4, 2.5, -1.15, 1.15, 'upper', R);
S('Watermelon');
disc(-0.5, 0.4, 1.15, 'upper', R, BANDS.filter((b) => b[0] !== 1.4));
S('InnerRind');
for (const [b0, b1] of BANDS) { const y0 = DCY + (b0 - DCY) * 1.04 / 1.15, y1 = DCY + (b1 - DCY) * 1.04 / 1.15; const ym = y0 < DCY && y1 > DCY ? 0 : Math.min(Math.abs(y0 - DCY), Math.abs(y1 - DCY)); const hz = Math.sqrt(Math.max(0.02, 1.04 * 1.04 - ym * ym)); B(0.4, 0.44, y0, y1, -hz, hz, 'P', 0, '#F6FFE8'); }
S('Flesh');
disc(0.44, 0.48, 0.92, 'lower', R, BANDS);
S('Seed');
for (const [y, z] of [[2.55, -0.45], [2.55, 0.45], [2.1, -0.72], [2.1, 0.72], [1.6, -0.6], [1.6, 0.6], [1.25, -0.3], [1.25, 0.3]]) {
	B(0.48, 0.5, y - 0.08, y + 0.08, z - 0.04, z + 0.04, 'P', 0, INK);
}
// dark rind stripes over the back and the rim
S('RindStripe');
for (const z of [-0.75, -0.25, 0.25, 0.75]) B(-0.53, -0.49, 1.0, 2.9, z - 0.08, z + 0.08, 'feather', 0);
for (const s of [1, -1]) {
	const z = s > 0 ? [1.14, 1.18] : [-1.18, -1.14];
	for (const x of [-0.25, 0.15]) B(x - 0.08, x + 0.08, 1.45, 2.45, ...z, 'feather', 0);
}

// --- revision 2 (owner: follow the Steal a Brainrot model, even more dopamine): a BIG boxy chrome
// astronaut helmet covering the giraffe's whole spotted face, sitting on top of the watermelon
S('Helmet');
B(-0.3, 0.92, 2.5, 3.96, -0.74, 0.74, 'prop', R);
B(-0.18, 0.8, 3.96, 4.1, -0.56, 0.56, 'prop', R);
B(-0.22, 0.84, 2.66, 3.8, -0.8, 0.8, 'prop', R);
S('HelmetBand');                                                // violet band around the helmet base
B(-0.32, 0.94, 2.5, 2.62, -0.76, 0.76, 'feather2', 0);
S('VisorRim');                                                  // glowing cyan rim around the face opening
B(0.92, 0.97, 2.62, 2.68, -0.62, 0.62, 'accent', E);
B(0.92, 0.97, 3.82, 3.88, -0.62, 0.62, 'accent', E);
MZ(0.92, 0.97, 2.62, 3.88, 0.58, 0.64, 'accent', E);
S('Antenna');                                                   // glowing antenna on the helmet
B(0.2, 0.28, 4.1, 4.5, 0.36, 0.44, 'prop', 0);
B(0.14, 0.34, 4.5, 4.7, 0.3, 0.5, 'P', E, '#FF3DD1');
S('HelmetLamp');
MZ(0.1, 0.46, 3.3, 3.54, 0.8, 0.86, 'stripe', E);
// big spotted giraffe face filling the visor
S('Face');
B(0.7, 0.94, 2.66, 3.84, -0.58, 0.58, 'skin', R);
S('FaceSpot');
for (const [y, z] of [[3.72, -0.42], [3.72, 0.42], [2.84, -0.48], [2.84, 0.48]]) B(0.94, 0.97, y - 0.08, y + 0.08, z - 0.08, z + 0.08, 'trim', 0);
S('Muzzle');
B(0.94, 1.24, 2.7, 3.06, -0.36, 0.36, 'skin2', R);
S('Nostril');
MZ(1.24, 1.26, 2.9, 3.0, 0.08, 0.18, 'P', 0, INK);
S('Mouth');                                                     // big happy grin
B(1.24, 1.26, 2.74, 2.8, -0.24, 0.24, 'P', 0, INK);
MZ(1.22, 1.26, 2.8, 2.88, 0.22, 0.3, 'P', 0, INK);
S('Ossicone');                                                  // horns poking through the helmet top
for (const s of [1, -1]) {
	B(0.24, 0.4, 4.08, 4.36, 0.16 * s - 0.08, 0.16 * s + 0.08, 'skin', R);
	B(0.22, 0.42, 4.36, 4.5, 0.16 * s - 0.1, 0.16 * s + 0.1, 'trim');
}
const FX = 0.98;
for (const out of [1, -1]) {
	S('EyeDome');
	B(0.78, FX, 3.08, 3.78, 0.03 * out, 0.54 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.28 * out, top: 3.74, L: 0.96, H: 0.92, out, iris: 'Violet', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
}

// --- space aura: five glowing star sparkles (gold, pink, cyan) around the helmet
S('Star');
for (const [x, y, z, col] of [[0.3, 4.62, -0.8, 'stripe'], [0.5, 3.4, 1.12, 'stripe'], [0.1, 4.3, 1.0, 'stripe'], [-0.4, 3.2, -1.22, 'stripe'], [0.6, 1.0, 1.25, 'stripe']]) {
	B(x - 0.04, x + 0.04, y - 0.15, y + 0.15, z - 0.04, z + 0.04, col, E);
	B(x - 0.04, x + 0.04, y - 0.04, y + 0.04, z - 0.15, z + 0.15, col, E);
}

// --- legs (matching pair) in tall caramel work boots with glowing cyan laces and soles
for (const s of [1, -1]) {
	const zc = 0.34 * s;
	S('HipCollar');
	B(-0.2, 0.2, 0.84, 0.92, zc - 0.2, zc + 0.2, 'P', 0, DARK);
	S('Leg');
	B(-0.16, 0.16, 0.74, 0.86, zc - 0.16, zc + 0.16, 'skin', R);
	S('KneeCollar');
	B(-0.18, 0.18, 0.68, 0.75, zc - 0.18, zc + 0.18, 'P', 0, DARK);
	S('Boot');
	B(-0.24, 0.24, 0.04, 0.7, zc - 0.22, zc + 0.22, 'foot', R);
	B(0.24, 0.52, 0.04, 0.3, zc - 0.2, zc + 0.2, 'foot', R);
	S('BootCuff');
	B(-0.25, 0.25, 0.6, 0.7, zc - 0.23, zc + 0.23, 'trim');
	S('Lace');
	for (const y of [0.22, 0.34, 0.46]) B(0.24, 0.27, y, y + 0.04, zc - 0.12, zc + 0.12, 'P', E, '#2EF2FF');
	S('Sole');
	B(-0.24, 0.52, 0, 0.04, zc - 0.22, zc + 0.22, 'P', E, '#FF3DD1');
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_023_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#0B8A33', feather: '#B8FF2E', feather2: '#9A4DFF', lower: '#FF1F5A', skin: '#FFB13B', skin2: '#FFE8C0', trim: '#A8480C', prop: '#E8ECFF', foot: '#C46A2A', stripe: '#FFE14D', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { kneeByHeight: true, slots: { InnerRind: 'Torso', Flesh: 'Torso' } };
