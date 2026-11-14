// BRT_029 Cocofanto Elefanto — Voxel V4 build (CP-C, Epic, revision 2).
// References, which agree (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki; "an
// elephant body with coconut characteristics, including a light grey skin and an aura of coconut water")
// and the yumcut.com render ("a baby-elephant-and-coconut hybrid"):
// - a grey baby elephant face peeking out of a halved coconut, framed by a white coconut-meat ring
// - a brown, hairy coconut-shell body; big flared ears; a trunk curling up; little tusks; four stout legs
// The V4 take (super dopamine + hallmarks + collectible flair from the first revision):
// - a round chocolate coconut husk with tan fibre stripes; the cut front shows a thick white coconut-meat
//   ring with a glowing cyan coconut-water rim (the V4 waterline and the game's coconut-water aura)
// - a lavender-grey elephant face with big aqua anime eyes, blush, a little smile, a trunk curling up and
//   two ivory tusks; big flared ears lined in pink
// - the gag: a tropical-drink coconut, with a yellow cocktail umbrella and a pink bendy straw stuck in the top
// - four stout legs in chunky hot-pink V4 sneakers with light-up soles
// - passive FX: glowing coconut-water droplets sparkling off the rim, and a drifting mist from the straw
// Revision 2 (owner): "make it even more dopamine inducing ... it needs to look worth the catch and feel
//   rewarding". Same reference silhouette, pushed to jackpot: a vivid lilac elephant, a richer caramel coconut
//   with bright fibres, a gold band and a jeweled gold crown with glowing gems ("king coconut"), neon-pink glowing
//   ear edges, a hibiscus behind one ear, bigger sparkly eyes, a rainbow-striped umbrella, glowing sneaker laces,
//   and a third passive FX layer of gold glitter.
// Rig-ready (owner rule): legs are two matching pairs with hip collars; sneakers point straight ahead.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const IVORY = '#FFF6DE';

function layer(y0, y1, r, role, rel = R) {
	B(-r, r, y0, y1, -0.7 * r, 0.7 * r, role, rel);
	B(-0.66 * r, 0.66 * r, y0, y1, -r, r, role, rel);
}
const CCY = 1.8, CR = 1.0;
const rC = (y) => Math.sqrt(Math.max(0.04, CR * CR - (y - CCY) * (y - CCY)));

// --- round chocolate coconut husk (the equator band is the Body) with tan fibre stripes
S('Body');
B(-CR, CR, 1.5, 2.1, -0.7 * CR, 0.7 * CR, 'upper', R);
S('Coconut');
B(-0.66 * CR, 0.66 * CR, 1.5, 2.1, -CR, CR, 'upper', R);
for (const [y0, y1] of [[0.84, 1.06], [1.06, 1.28], [1.28, 1.5], [2.1, 2.32], [2.32, 2.54], [2.54, 2.76]]) layer(y0, y1, rC((y0 + y1) / 2), 'upper');
S('HuskFibre');
for (const s of [1, -1]) {
	const zf = s > 0 ? [CR - 0.02, CR + 0.03] : [-CR - 0.03, -CR + 0.02];
	for (const x of [-0.45, 0.0, 0.42]) B(x - 0.05, x + 0.05, 1.2, 2.4, ...zf, 'feather', 0);
}
for (const z of [-0.4, 0, 0.4]) B(-CR - 0.03, -CR + 0.02, 1.2, 2.4, z - 0.05, z + 0.05, 'feather', 0);

// --- jackpot bling: a gold band around the coconut and a jeweled gold crown on top ("king coconut")
S('GoldBand');
B(-0.98, 0.7, 1.74, 1.86, -0.72, 0.72, 'P', 0, '#FFC21A');
B(-0.68, 0.7, 1.74, 1.86, -1.02, 1.02, 'P', 0, '#FFC21A');
S('Crown');
B(0.04, 0.6, 2.76, 2.88, -0.28, 0.28, 'P', 0, '#FFC21A');
for (const [x, z] of [[0.08, -0.24], [0.08, 0.24], [0.56, -0.24], [0.56, 0.24]]) B(x - 0.05, x + 0.05, 2.88, 3.06, z - 0.05, z + 0.05, 'P', 0, '#FFC21A');
S('CrownGem');
B(0.56, 0.62, 2.78, 2.92, -0.07, 0.07, 'P', E, '#FF2DD1');
B(0.28, 0.38, 2.88, 3.12, -0.05, 0.05, 'P', E, '#2EF2FF');
B(0.22, 0.44, 2.86, 2.94, -0.11, 0.11, 'P', E, '#7DFF2E');

// --- the cut front: thick white coconut-meat ring with a glowing cyan coconut-water rim
S('CoconutMeat');
B(0.84, 0.98, 1.06, 2.54, -0.6, 0.6, 'lower', R);
B(0.84, 0.98, 1.2, 2.4, -0.74, 0.74, 'lower', R);
B(0.84, 0.98, 1.36, 2.24, -0.82, 0.82, 'lower', R);
S('CoconutWaterRim');                                           // the V4 waterline
B(0.86, 1.0, 2.54, 2.6, -0.6, 0.6, 'stripe', E);
B(0.86, 1.0, 1.0, 1.06, -0.6, 0.6, 'stripe', E);
MZ(0.86, 1.0, 1.36, 2.24, 0.82, 0.88, 'stripe', E);
MZ(0.86, 1.0, 1.2, 2.4, 0.74, 0.78, 'stripe', E);

// --- lavender-grey baby elephant face peeking out of the coconut
S('Head');
B(0.96, 1.2, 1.3, 2.32, -0.5, 0.5, 'skin', R);
B(0.96, 1.18, 1.42, 2.2, -0.6, 0.6, 'skin', R);
const FX = 1.22;
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.0, FX, 1.72, 2.3, 0.03 * out, 0.5 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.26 * out, top: 2.26, L: 0.9, H: 0.9, out, iris: 'Ocean', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
}
S('Trunk');                                                     // trunk dropping, then curling up
B(1.18, 1.44, 1.42, 1.76, -0.15, 0.15, 'skin', R);
B(1.38, 1.6, 1.24, 1.52, -0.13, 0.13, 'skin', R);
B(1.56, 1.76, 1.3, 1.66, -0.12, 0.12, 'skin', R);
B(1.6, 1.78, 1.62, 1.98, -0.11, 0.11, 'skin', R);
B(1.48, 1.7, 1.94, 2.08, -0.1, 0.1, 'skin');
S('TrunkTip');
B(1.44, 1.52, 1.9, 2.06, -0.08, 0.08, 'skin2');
S('Tusk');
MZ(1.18, 1.44, 1.36, 1.48, 0.2, 0.3, 'P', 0, IVORY);
MZ(1.38, 1.5, 1.46, 1.6, 0.21, 0.29, 'P', 0, IVORY);
S('Mouth');                                                     // little smile under the trunk
B(1.2, 1.22, 1.32, 1.38, -0.12, 0.12, 'P', 0, INK);
for (const s of [1, -1]) {
	S('Ear');                                                   // big flared ears lined in pink
	B(0.2, 0.74, 1.36, 2.46, 0.9 * s, 1.44 * s, 'skin', R);
	B(0.28, 0.66, 1.24, 2.56, 1.0 * s, 1.36 * s, 'skin', R);
	S('InnerEar');
	B(0.74, 0.77, 1.46, 2.36, 1.0 * s, 1.36 * s, 'skin2');
	S('EarGlow');                                               // glowing neon-pink ear edge
	B(0.2, 0.76, 2.46, 2.52, 0.9 * s, 1.44 * s, 'P', E, '#FF2DD1');
	B(0.2, 0.76, 1.36, 2.46, s > 0 ? 1.44 : -1.48, s > 0 ? 1.48 : -1.44, 'P', E, '#FF2DD1');
}
S('Hibiscus');                                                  // tropical flower tucked behind the +z ear
for (const [dy, dz] of [[0.14, 0], [-0.14, 0], [0, 0.14], [0, -0.14]]) B(0.66, 0.78, 2.3 + dy - 0.1, 2.3 + dy + 0.1, 0.86 + dz - 0.1, 0.86 + dz + 0.1, 'skin2', 0);
B(0.76, 0.82, 2.24, 2.36, 0.8, 0.92, 'P', E, '#FFE14D');

// --- the gag: a tropical-drink coconut: yellow cocktail umbrella and a pink bendy straw
S('UmbrellaPole');
B(-0.16, -0.12, 2.76, 3.46, -0.36, -0.32, 'P', 0, '#FFFFFF');
S('Umbrella');
B(-0.62, 0.34, 3.4, 3.5, -0.82, 0.14, 'prop', R);
B(-0.42, 0.14, 3.5, 3.6, -0.62, -0.06, 'prop', R);
B(-0.24, -0.04, 3.6, 3.66, -0.44, -0.24, 'prop');
S('UmbrellaStripe');
B(-0.63, 0.35, 3.44, 3.46, -0.38, -0.3, 'skin2');
B(-0.18, -0.1, 3.44, 3.46, -0.83, 0.15, 'skin2');
B(-0.63, 0.35, 3.44, 3.46, -0.62, -0.56, 'P', 0, '#2EF2FF');
B(0.14, 0.22, 3.44, 3.46, -0.83, 0.15, 'P', 0, '#7DFF2E');
S('Straw');
B(0.22, 0.3, 2.7, 3.36, 0.3, 0.38, 'P', 0, '#FF4FA8');
B(0.22, 0.52, 3.3, 3.38, 0.3, 0.38, 'P', 0, '#FF4FA8');
B(0.46, 0.54, 3.18, 3.36, 0.3, 0.38, 'P', 0, '#FFFFFF');

// --- tail tuft at the back
S('Tail');
B(-1.12, -0.96, 1.3, 1.5, -0.05, 0.05, 'skin');
B(-1.2, -1.06, 1.1, 1.32, -0.08, 0.08, 'feather');

// --- four stout elephant legs (two matching pairs) in chunky hot-pink V4 sneakers with light-up soles
for (const lx of [0.46, -0.5]) {
	for (const s of [1, -1]) {
		const zc = 0.46 * s;
		S('HipCollar');
		B(lx - 0.24, lx + 0.24, 0.86, 0.94, zc - 0.24, zc + 0.24, 'P', 0, DARK);
		S('Leg');
		B(lx - 0.22, lx + 0.22, 0.4, 0.9, zc - 0.22, zc + 0.22, 'skin', R);
		S('Sneaker');
		B(lx - 0.28, lx + 0.4, 0.08, 0.44, zc - 0.26, zc + 0.26, 'foot', R);
		S('SneakerStripe');
		B(lx - 0.14, lx + 0.26, 0.18, 0.28, s > 0 ? zc + 0.26 : zc - 0.28, s > 0 ? zc + 0.28 : zc - 0.26, 'trim');
		S('Laces');
		B(lx + 0.06, lx + 0.3, 0.44, 0.47, zc - 0.14, zc + 0.14, 'P', E, '#FFE14D');
		S('Midsole');
		B(lx - 0.29, lx + 0.41, 0.04, 0.1, zc - 0.27, zc + 0.27, 'trim');
		S('Sole');
		B(lx - 0.29, lx + 0.41, 0, 0.04, zc - 0.27, zc + 0.27, 'accent', E);
	}
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_029_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#B85E1E', feather: '#FFB86B', lower: '#FFF8EC', stripe: '#2EF2FF', skin: '#B9A2FF', skin2: '#FF5FB8', prop: '#FFD21A', foot: '#FF2D95', trim: '#FFFFFF', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (collectible flair): glowing coconut-water droplets sparkling off the rim, a drifting mist at the straw
const passiveFx = [
	{ name: 'CoconutWater', texture: 'sparkle', anchor: [1.0, 1.8, 0], rate: 5, lifetime: [0.8, 1.4], size: [0.16, 0.04], transparency: [0, 1], colors: ['#2EF2FF', '#FFFFFF'], lightEmission: 1, speed: [0.4, 0.9], spread: 80, rise: -0.6 },
	{ name: 'GoldGlitter', texture: 'sparkle', anchor: [0, 2.0, 0], rate: 6, lifetime: [1.0, 1.8], size: [0.2, 0.05], transparency: [0, 1], colors: ['#FFE14D', '#FF2DD1'], lightEmission: 1, speed: [0.3, 0.8], spread: 180, rise: 0.25 },
	{ name: 'StrawMist', texture: 'smoke', anchor: [0.5, 3.4, 0.34], rate: 2, lifetime: [1.2, 1.8], size: [0.12, 0.4], transparency: [0.5, 1], colors: ['#BFF6FF', '#FFFFFF'], lightEmission: 0.3, speed: [0.2, 0.4], spread: 20, rise: 0.2 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { slots: { CoconutMeat: 'Torso', CoconutWaterRim: 'Torso', Hibiscus: 'Head' } };
