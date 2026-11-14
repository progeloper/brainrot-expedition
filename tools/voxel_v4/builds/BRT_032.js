// BRT_032 La Vaca Saturno Saturnita — Voxel V4 build (CP-C, Legendary, revision 2).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki, "La Vacca Saturno
// Saturnita": "a large cow fused with the planet Saturn, complete with human-like feet with five toes on each") and
// the project recipe / AGENTS.md (two human-like legs, two oversized bare feet, ten toes, cow muzzle, horns, ears):
// - a round, banded Saturn planet as the body, with one wide flat ring around the equator
// - a little white cow head with dark patches and horns peeking out of the planet's top-front
// - two short human legs ending in two huge bare feet with five toes each
// The V4 take (super dopamine + hallmarks + Legendary jackpot flair from the first revision):
// - a candy-banded planet (amber gold, sky cyan, hot pink) over a cream lower half; the ring is a wide glowing cyan
//   band (the V4 waterline) with a gold outer rim, a little glowing moon and a glowing star riding on it
// - a bigger white cow head with big front anime eyes (amber), lash, Neon blush, a dark cow patch around one eye, a pink muzzle with a
//   wide grin and a tongue, ivory horns with gold tips, pink-lined ears, dark-violet patches
// - the gag: two huge bare feet with ten toes and glowing hot-pink pedicured toenails; a gold cowbell with a
//   glowing gem (bling)
// - passive FX: cosmic stardust around the ring, gold glints off the cowbell, and a soft moon glow
// Revision 2 (owner): "more dopamine", "not all brainrots need to be blue", "closer to SAB model". The cyan is gone:
//   warm candy bands closer to the in-game cream / tan planet (tangerine caramel, butter yellow, pink over cream)
//   with a glowing gold band; a glowing hot-pink ring with glowing gold segments and a gold rim (a jackpot ring);
//   more glowing stars; a glowing pearl moon; a jeweled gold nose ring; pink cowbell gem; gold and pink stardust.
// Rig-ready (owner rule): the legs are a matching pair with hip / ankle collars; the feet are flat and point ahead.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const GOLD = '#FFC21A';
const IVORY = '#FFF6DE';
const MAW = '#6E0E2C';

// --- the banded Saturn planet: candy bands on top (the equator band is the Body), cream lower half
const CCY = 2.3, PR = 1.35;
const rP = (y) => Math.sqrt(Math.max(0.03, PR * PR - (y - CCY) ** 2));
function layer(y0, y1, r, role, flags = R) {
	B(-r, r, y0, y1, -0.7 * r, 0.7 * r, role, flags);
	B(-0.66 * r, 0.66 * r, y0, y1, -r, r, role, flags);
}
S('Body');
B(-PR, PR, 2.3, 2.75, -0.7 * PR, 0.7 * PR, 'upper', R);
S('Planet');
B(-0.66 * PR, 0.66 * PR, 2.3, 2.75, -PR, PR, 'upper', R);
S('PlanetBand');
for (const [y0, y1, role] of [[2.75, 2.95, 'feather'], [2.95, 3.15, 'upper'], [3.15, 3.32, 'feather2'], [3.32, 3.47, 'upper'], [3.47, 3.58, 'feather'], [3.58, 3.65, 'feather2']]) layer(y0, y1, rP((y0 + y1) / 2), role);
S('GoldBand');                                                  // glowing gold band on the planet
{
	const r = rP(2.965) + 0.02;
	B(-r, r, 2.94, 2.99, -0.7 * r, 0.7 * r, 'P', E, '#FFD21A');
	B(-0.66 * r, 0.66 * r, 2.94, 2.99, -r, r, 'P', E, '#FFD21A');
}
S('PlanetBelly');
for (const [y0, y1] of [[1.95, 2.3], [1.6, 1.95], [1.3, 1.6], [1.08, 1.3], [0.95, 1.08]]) layer(y0, y1, rP((y0 + y1) / 2), 'lower');

// --- the wide glowing ring around the equator (the V4 waterline), with a gold outer rim
const RI = 1.52, RO = 2.2, RA = 0.91;
S('Ring');
MZ(-RA, RA, 2.24, 2.32, RI, RO, 'stripe', E);
B(RI, RO, 2.24, 2.32, -RA, RA, 'stripe', E);
B(-RO, -RI, 2.24, 2.32, -RA, RA, 'stripe', E);
for (const [sx, sz] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
	const xs = sx > 0 ? [1.05, 1.6] : [-1.6, -1.05], zs = sz > 0 ? [1.05, 1.6] : [-1.6, -1.05];
	B(...xs, 2.24, 2.32, ...zs, 'P', E, '#FFD21A');
}
S('RingRim');
B(RO, RO + 0.1, 2.25, 2.31, -RA, RA, 'P', 0, GOLD);
B(-RO - 0.1, -RO, 2.25, 2.31, -RA, RA, 'P', 0, GOLD);
MZ(-RA, RA, 2.25, 2.31, RO, RO + 0.1, 'P', 0, GOLD);
S('Moon');                                                      // a little glowing moon and a star on the ring
B(-1.62, -1.26, 2.32, 2.68, -1.62, -1.26, 'P', E, '#FFF2B8');
S('Star');
B(1.3, 1.46, 2.32, 2.48, 1.3, 1.46, 'P', E, '#FFE14D');
B(1.86, 1.98, 2.32, 2.44, -0.5, -0.38, 'P', E, '#FF6FD8');
B(-0.5, -0.38, 2.32, 2.44, 1.86, 1.98, 'P', E, '#FFE14D');

// --- the white cow head peeking out of the planet's top-front
S('Head');
B(0.5, 1.35, 3, 4.05, -0.5, 0.5, 'skin', R);
S('Patch');                                                     // dark-violet cow patches
B(0.57, 1.01, 4.05, 4.08, -0.36, 0.08, 'prop');
B(0.5, 0.9, 3.5, 4.05, 0.5, 0.53, 'prop');
S('Muzzle');
B(1.35, 1.65, 3, 3.4, -0.44, 0.44, 'skin2', R);
S('Nostril');
MZ(1.65, 1.67, 3.26, 3.34, 0.14, 0.28, 'P', 0, MAW);
S('NoseRing');                                                  // jeweled gold nose ring (bling gag)
B(1.65, 1.71, 3.06, 3.12, -0.14, 0.14, 'P', 0, '#FFC21A');
MZ(1.65, 1.71, 2.94, 3.12, 0.12, 0.18, 'P', 0, '#FFC21A');
B(1.71, 1.75, 2.9, 2.98, -0.05, 0.05, 'P', E, '#FF2DD1');
S('Mouth');                                                     // wide V4 grin with a tongue
B(1.65, 1.67, 3.06, 3.18, -0.3, 0.3, 'P', 0, MAW);
MZ(1.65, 1.67, 3.18, 3.23, 0.28, 0.36, 'P', 0, MAW);
B(1.65, 1.68, 3.06, 3.11, -0.16, 0.16, 'P', 0, '#FF4F7A');
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('Horn');                                                  // ivory horns with gold tips
	B(0.75, 0.93, 4.05, 4.25, ...z(0.28, 0.44), 'P', 0, IVORY);
	B(0.75, 0.93, 4.25, 4.41, ...z(0.36, 0.5), 'P', 0, IVORY);
	B(0.77, 0.91, 4.41, 4.53, ...z(0.4, 0.5), 'P', 0, GOLD);
	S('Ear');
	B(0.65, 0.93, 3.6, 3.76, ...z(0.5, 0.84), 'skin', R);
	S('InnerEar');
	B(0.93, 0.95, 3.63, 3.73, ...z(0.54, 0.8), 'skin2');
}
// big front anime eyes (amber) above the muzzle, a dark cow patch around the left eye
S('EyePatch');
B(1.35, 1.37, 3.46, 4.05, -0.5, -0.04, 'prop');
const FX = 1.37;
for (const out of [1, -1]) frontEye({ faceX: FX, zc: 0.25 * out, top: 3.98, L: 0.62, H: 0.66, out, iris: 'Amber', lash: true, blush: true });
S('CowbellStrap');                                              // the gold cowbell with a glowing gem (bling)
B(1.2, 1.5, 2.92, 3.0, -0.3, 0.3, 'P', 0, '#FF2D55');
S('Cowbell');
B(1.36, 1.64, 2.6, 2.92, -0.16, 0.16, 'P', 0, GOLD);
B(1.4, 1.6, 2.54, 2.6, -0.2, 0.2, 'P', 0, GOLD);
S('CowbellGem');
B(1.64, 1.68, 2.68, 2.82, -0.07, 0.07, 'P', E, '#FF2DD1');

// --- tufted cow tail at the back
S('Tail');
B(-1.66, -1.28, 1.75, 1.83, -0.04, 0.04, 'skin');
B(-1.82, -1.64, 1.57, 1.85, -0.09, 0.09, 'prop');

// --- two short human legs (matching pair) ending in huge bare feet with ten toes and glowing pedicured nails
for (const s of [1, -1]) {
	const zc = 0.45 * s;
	S('HipCollar');
	B(-0.2, 0.2, 0.96, 1.04, zc - 0.2, zc + 0.2, 'P', 0, DARK);
	S('Leg');
	B(-0.18, 0.18, 0.48, 0.98, zc - 0.18, zc + 0.18, 'foot', R);
	S('AnkleCollar');
	B(-0.19, 0.19, 0.42, 0.5, zc - 0.19, zc + 0.19, 'P', 0, DARK);
	S('Foot');
	B(-0.42, 0.9, 0, 0.44, zc - 0.36, zc + 0.36, 'foot', R);
	// toes: big toe on the inner side (toward the centre), then smaller toes outward
	const inner = zc - 0.36 * s;
	const toes = [[0, 0.18, 0.26, 0.3], [0.21, 0.33, 0.21, 0.23], [0.36, 0.47, 0.18, 0.21], [0.5, 0.6, 0.15, 0.19], [0.63, 0.72, 0.12, 0.16]];
	for (const [a, b, len, h] of toes) {
		const za = inner + a * s, zb = inner + b * s;
		const z0 = Math.min(za, zb), z1 = Math.max(za, zb);
		S('Toe');
		B(0.9, 0.9 + len, 0, h, z0, z1, 'foot');
		S('ToeNail');
		B(0.9 + len - 0.09, 0.9 + len + 0.01, h, h + 0.03, z0 + 0.015, z1 - 0.015, 'accent', E);
	}
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_032_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF8A1F', feather: '#FFD23F', feather2: '#FF4FA3', lower: '#FFF1D6', stripe: '#FF3DCB', skin: '#FFFFFF', skin2: '#FF9EC4', prop: '#3A2D5C', foot: '#FFB48A', trim: '#FFFFFF', accent: '#FF2DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (Legendary flair): cosmic stardust around the ring, gold glints off the cowbell, a soft moon glow
const passiveFx = [
	{ name: 'Stardust', texture: 'sparkle', anchor: [0, 2.3, 0], rate: 8, lifetime: [1.0, 1.8], size: [0.24, 0.05], transparency: [0, 1], colors: ['#FFE14D', '#FF3DCB'], lightEmission: 1, speed: [0.4, 0.9], spread: 180, rise: 0.15 },
	{ name: 'CowbellGlint', texture: 'sparkle', anchor: [1.66, 2.75, 0], rate: 3, lifetime: [0.5, 0.9], size: [0.18, 0.04], transparency: [0, 1], colors: ['#FFFFFF', '#FFE14D'], lightEmission: 1, speed: [0.1, 0.3], spread: 120, rise: 0 },
	{ name: 'MoonGlow', texture: 'smoke', anchor: [-1.44, 2.5, -1.44], rate: 2, lifetime: [1.2, 2.0], size: [0.2, 0.6], transparency: [0.5, 1], colors: ['#FFF2B8', '#FFD6F0'], lightEmission: 0.6, speed: [0.05, 0.15], spread: 180, rise: 0.05 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
