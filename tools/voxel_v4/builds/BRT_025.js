// BRT_025 Salamino Penguino — Voxel V4 build (CP-C, Rare, revision 4).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki) and the
// yumcut.com render ("a grumpy penguin-salami hybrid"):
// - a penguin whose head and back are salami, red and flecked with white fat
// - a white belly, black flippers, a black beak, a grumpy face, orange feet
// Revision 3 (owner): "go more dopamine, more v4". Rebuilt on the V4 hallmarks of the approved BRT_027
// reference (design_reference/voxel_v4):
// - chunky, simple panels; two-tone countershading (hot salami top, white belly wrapping round the
//   bottom) split by a glowing cyan waterline all the way round
// - big side anime eyes with the BRT_027 construction (white, three-band iris, pupil, three Neon
//   catchlights, lash bar, Neon blush), set grumpy-low with a slanted lash
// - a closed black beak with a gold tip (revision 4, owner: "the teeth throw me off": the toothy
//   grin, mouth and tongue are removed)
// - chunky hot-orange sneakers with white stripes and light-up cyan soles (the V4 sneakers)
// - the gag: the salami end tied with glowing gold twine and a dangling deli price tag; bright fat
//   flecks; icy snowflake sparkles (arctic region)
// Rig-ready (owner rule): flippers and legs are matching pairs with joint collars; sneakers point straight
// ahead on flat soles.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const GOLD = '#FFC21A';

// --- chunky countershaded body: hot salami top (the Body), white belly wrapping round the bottom
S('Body');
B(-0.86, 0.86, 1.46, 2.56, -0.78, 0.78, 'upper', R);
S('BellyBase');
B(-0.86, 0.86, 0.56, 1.46, -0.78, 0.78, 'lower', R);
B(-0.7, 0.7, 0.46, 0.56, -0.62, 0.62, 'lower', R);
S('BellyFront');                                                // the white front rises up the chest
B(0.86, 0.98, 0.6, 2.3, -0.48, 0.48, 'lower', R);
S('Waterline');                                                 // glowing cyan waterline all the way round
B(-0.89, 0.89, 1.43, 1.5, -0.81, 0.81, 'stripe', E);
B(0.98, 1.01, 0.6, 2.3, -0.5, -0.46, 'stripe', E);
B(0.98, 1.01, 0.6, 2.3, 0.46, 0.5, 'stripe', E);
B(0.98, 1.01, 2.26, 2.33, -0.5, 0.5, 'stripe', E);
// --- chunky salami head
S('Head');
B(-0.72, 0.84, 2.56, 3.62, -0.68, 0.68, 'upper', R);
B(-0.58, 0.7, 3.62, 3.76, -0.52, 0.52, 'upper', R);
// bright cream fat flecks on the head and back
S('FatFleck');
for (const s of [1, -1]) {
	const zf = (r) => (s > 0 ? [r - 0.02, r + 0.03] : [-r - 0.03, -r + 0.02]);
	for (const [x, y, r] of [[-0.45, 2.0, 0.78], [0.1, 1.75, 0.78], [-0.1, 2.3, 0.78], [0.55, 2.05, 0.78], [-0.5, 3.0, 0.68], [-0.35, 3.45, 0.68]]) {
		B(x - 0.09, x + 0.09, y - 0.09, y + 0.09, ...zf(r), 'skin2', 0);
	}
}
for (const [x, z] of [[-0.3, 0.3], [0.3, -0.25], [0.0, 0.0], [-0.4, -0.3]]) B(x - 0.09, x + 0.09, 3.76, 3.79, z - 0.09, z + 0.09, 'skin2', 0);
for (const [y, z] of [[1.75, 0.35], [2.2, -0.3], [2.9, 0.3], [3.3, -0.3], [1.95, -0.55]]) B(-0.89, -0.84, y - 0.09, y + 0.09, z - 0.09, z + 0.09, 'skin2', 0);

// --- the gag: salami end tied with glowing gold twine, deli price tag dangling at the back
S('SalamiTie');
B(-0.2, 0.2, 3.76, 3.9, -0.2, 0.2, 'upper', R);
S('Twine');
B(-0.24, 0.24, 3.8, 3.86, -0.24, 0.24, 'prop', E);
B(-0.04, 0.04, 3.86, 4.12, 0.12, 0.2, 'prop', E);
B(-0.04, 0.04, 3.86, 4.06, -0.2, -0.12, 'prop', E);
S('PriceTagString');
B(-0.74, -0.7, 3.2, 3.84, 0.22, 0.26, 'prop', E);
S('PriceTag');
B(-0.8, -0.74, 2.84, 3.22, 0.06, 0.42, 'P', 0, '#FFFFFF');
B(-0.81, -0.8, 2.94, 3.02, 0.12, 0.36, 'P', 0, '#FF2D55');
B(-0.81, -0.8, 3.06, 3.12, 0.12, 0.28, 'P', 0, '#FF2D55');

// --- big side anime eyes (BRT_027 construction, scaled), set grumpy with a slanted lash bar
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 0.68, k = 0.5, X = -0.05, Y = 2.86;                // eye rear x, white bottom y
	const y = (v) => Y + (v - 4.2) * k, x = (v) => X + v * k;
	const [w0, w1] = zz(zf, zf + 0.03), [i0, i1] = zz(zf + 0.03, zf + 0.05), [p0, p1] = zz(zf + 0.05, zf + 0.07), [c0, c1] = zz(zf + 0.07, zf + 0.09);
	S('EyeWhite');
	B(x(0.12), x(1.27), y(4.2), y(5.85), w0, w1, 'P', 0, '#FFFFFF');
	B(x(0), x(1.39), y(4.35), y(5.7), w0, w1, 'P', 0, '#FFFFFF');
	S('Iris');
	B(x(0.22), x(1.17), y(5.1), y(5.65), i0, i1, 'P', 0, '#7A2A10');
	B(x(0.22), x(1.17), y(4.65), y(5.1), i0, i1, 'P', 0, '#FF6A1A');
	B(x(0.22), x(1.17), y(4.27), y(4.65), i0, i1, 'P', 0, '#FFCF45');
	S('Pupil');
	B(x(0.47), x(0.94), y(4.7), y(5.35), p0, p1, 'P', 0, '#1A0B06');
	S('Catchlight');
	B(x(0.32), x(0.68), y(5.13), y(5.51), c0, c1, 'P', E, '#FFFFFF');
	B(x(0.88), x(1.06), y(4.45), y(4.63), c0, c1, 'P', E, '#FFFFFF');
	B(x(1.0), x(1.08), y(5.21), y(5.29), c0, c1, 'P', E, '#FFFFFF');
	S('Lash');                                                  // grumpy: the lash slants down toward the beak
	const [l0, l1] = zz(zf, zf + 0.1);
	B(x(-0.06), x(0.7), y(5.6), y(5.78), l0, l1, 'P', 0, '#000000');
	B(x(0.7), x(1.47), y(5.5), y(5.68), l0, l1, 'P', 0, '#000000');
	B(x(-0.28), x(0.02), y(5.72), y(5.96), l0, l1, 'P', 0, '#000000');
	S('Blush');
	B(x(0.05), x(0.75), y(3.8), y(4.05), w0, w1, 'P', E, '#FF6FA3');
}

// --- closed black beak with a gold tip (revision 4: the toothy grin is removed)
S('Beak');
B(0.84, 1.36, 2.88, 3.2, -0.26, 0.26, 'P', 0, '#141218');      // upper beak
B(1.36, 1.46, 2.94, 3.14, -0.14, 0.14, 'P', 0, GOLD);           // gold tip
B(0.84, 1.24, 2.68, 2.88, -0.22, 0.22, 'P', 0, '#2E2A36');      // lower beak

// --- glossy black flippers (matching pair) hanging at the sides, glowing cyan edges
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('ShoulderCollar');
	B(-0.2, 0.2, 2.3, 2.44, ...z(0.78, 0.86), 'P', 0, DARK);
	S('Flipper');
	B(-0.26, 0.26, 1.34, 2.4, ...z(0.86, 1.0), 'feather', R);
	B(-0.2, 0.2, 0.96, 1.34, ...z(0.86, 0.98), 'feather', R);
	S('FlipperEdge');
	B(0.26, 0.29, 1.04, 2.36, ...z(0.88, 0.98), 'accent', E);
}
S('Tail');
B(-1.04, -0.84, 0.56, 0.8, -0.22, 0.22, 'feather', R);

// --- arctic aura: glowing icy snowflake sparkles
S('Snowflake');
for (const [x, y, z] of [[0.2, 4.2, -0.9], [-0.3, 2.9, 1.3], [0.5, 3.9, 1.1], [-0.2, 1.4, -1.35]]) {
	B(x - 0.03, x + 0.03, y - 0.15, y + 0.15, z - 0.03, z + 0.03, 'accent', E);
	B(x - 0.03, x + 0.03, y - 0.03, y + 0.03, z - 0.15, z + 0.15, 'accent', E);
}

// --- short legs (matching pair) in chunky hot-orange V4 sneakers with white stripes and light-up soles
for (const s of [1, -1]) {
	const zc = 0.38 * s;
	S('HipCollar');
	B(-0.15, 0.15, 0.46, 0.52, zc - 0.15, zc + 0.15, 'P', 0, DARK);
	S('Leg');
	B(-0.12, 0.12, 0.34, 0.48, zc - 0.12, zc + 0.12, 'feather', R);
	S('Sneaker');                                               // chunky V4 sneaker
	B(-0.32, 0.54, 0.08, 0.44, zc - 0.27, zc + 0.27, 'foot', R);
	B(0.54, 0.8, 0.08, 0.32, zc - 0.24, zc + 0.24, 'foot', R);
	S('SneakerStripe');
	B(-0.16, 0.4, 0.18, 0.28, s > 0 ? zc + 0.27 : zc - 0.29, s > 0 ? zc + 0.29 : zc - 0.27, 'trim');
	S('SneakerToe');
	B(0.78, 0.82, 0.08, 0.22, zc - 0.22, zc + 0.22, 'trim');
	S('Laces');
	for (const x of [0.12, 0.3]) B(x, x + 0.08, 0.44, 0.47, zc - 0.16, zc + 0.16, 'trim');
	S('Midsole');
	B(-0.33, 0.82, 0.04, 0.1, zc - 0.28, zc + 0.28, 'trim');
	S('Sole');
	B(-0.33, 0.82, 0, 0.04, zc - 0.28, zc + 0.28, 'accent', E);
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_025_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF1E46', lower: '#F7F5FC', stripe: '#2EE9FF', skin2: '#FFE9DC', feather: '#121018', foot: '#FF6A0A', trim: '#FFFFFF', prop: '#FFD21A', accent: '#2EE9FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
