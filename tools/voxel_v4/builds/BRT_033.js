// BRT_033 Dragon Cannelloni — Voxel V4 build (CP-D, Legendary, teased; revision 5).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki: "a dragon made of pasta,
// it features hollow joints filled with red sauce, a cheesy orange hue on its wings, and a fiery aura streaming
// from its mouth and wings ... brown horns, claws, and expressive white eyes with black pupils") and the project
// recipe (golden cannelloni dragon, sauce-filled pasta-roll joints, ribbed wings, flame tips, toothed grin).
// Revision 5 (owner): "it's not fortnite coded enough" -> "make it more fortnite coded"; the owner chose heroic
// chunky proportions, clean bold shapes and legendary-skin flair. This takes the stylized hero-skin ART-STYLE
// archetype only: no Fortnite characters, skins, logos, meshes or assets are referenced or copied.
// - heroic chunky proportions: a big head, a wide V-shaped chest over a narrow waist, big fists and feet, short
//   thick legs, a short thick neck, chunky horns
// - clean bold shapes: fewer, bigger, chamfered blocks; three clean swept wing panels per side; bold colour blocking
// - legendary-skin flair: violet armour pauldrons with gold spikes, bracers, knee guards and an armoured belt, all
//   with glowing gold trims; the giant gold pasta fork worn as back bling; glowing gold horn bands and wing trims
// - kept: golden pasta body with glowing red sauce rings at every joint, ricotta belly plates, crimson wings,
//   violet horns, front fangs, glowing nostrils, green side eyes, forehead gem, flame tail spade, fire particles
// Rig-ready (owner rule): legs, arms and wings are matching mirrored pairs with sauce-ring collars; feet flat ahead.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const GOLD = '#FFC21A';
const MAW = '#6E0E2C';
const IVORY = '#FFF6DE';

// chamfered block: two overlapping boxes give clean bevelled edges
function cb(x0, x1, y0, y1, z0, z1, c, role, f = R) {
	B(x0, x1, y0 + c, y1 - c, z0, z1, role, f);
	B(x0 + c, x1 - c, y0, y1, z0 + c, z1 - c, role, f);
}

// --- wide V-shaped chest (the Body) over a narrow waist; bold ricotta plates framed in glowing gold trim
S('Body');
B(-0.6, 0.75, 2.6, 3.5, -0.95, 0.95, 'upper', R);
S('Chest');
B(-0.52, 0.67, 2.5, 3.6, -0.85, 0.85, 'upper', R);
S('SauceRing');
B(-0.5, 0.62, 2.46, 2.54, -0.7, 0.7, 'feather2', E);
S('Waist');
cb(-0.45, 0.55, 1.72, 2.5, -0.6, 0.6, 0.08, 'upper');
S('BellyPlate');
for (const y of [2.64, 2.94]) B(0.75, 0.82, y, y + 0.26, -0.42, 0.42, 'lower', R);
B(0.55, 0.62, 2.0, 2.42, -0.36, 0.36, 'lower', R);
S('GoldTrim');
MZ(0.75, 0.83, 2.6, 3.5, 0.42, 0.47, 'stripe', E);
S('ChestMedallion');
B(0.75, 0.84, 3.22, 3.48, -0.16, 0.16, 'P', 0, GOLD);
B(0.84, 0.87, 3.28, 3.42, -0.08, 0.08, 'P', E, '#FF2DD1');
S('ArmouredBelt');
B(-0.48, 0.58, 1.72, 1.9, -0.63, 0.63, 'prop', R);
B(-0.49, 0.59, 1.9, 1.94, -0.64, 0.64, 'stripe', E);
S('BeltBuckle');
B(0.58, 0.66, 1.7, 1.94, -0.16, 0.16, 'P', 0, GOLD);
B(0.66, 0.69, 1.76, 1.88, -0.07, 0.07, 'P', E, '#FF2DD1');

// --- short thick neck and a big, chunky dragon head
S('Neck');
cb(0.35, 0.95, 3.45, 4.02, -0.42, 0.42, 0.06, 'upper');
S('SauceRing');
B(0.4, 0.95, 3.96, 4.04, -0.45, 0.45, 'feather2', E);
S('Head');
cb(0.5, 1.65, 3.95, 4.95, -0.56, 0.56, 0.08, 'upper');
S('Snout');
cb(1.65, 2.35, 4.02, 4.6, -0.42, 0.42, 0.06, 'upper');
S('Jaw');
B(0.95, 2.28, 3.68, 3.9, -0.38, 0.38, 'lower', R);
S('Mouth');
B(1.1, 2.37, 3.9, 4.02, -0.37, 0.37, 'P', 0, MAW);
B(1.5, 2.2, 3.9, 3.94, -0.18, 0.18, 'P', 0, '#FF4F7A');
S('Fang');
MZ(2.2, 2.36, 3.74, 4.02, 0.18, 0.3, 'P', 0, IVORY);
MZ(2.23, 2.33, 3.6, 3.74, 0.2, 0.28, 'P', 0, IVORY);
S('Teeth');
for (const z of [-0.08, 0.08]) B(2.37, 2.42, 3.93, 4.02, z - 0.035, z + 0.035, 'P', 0, IVORY);
S('Nostril');                                                   // glowing orange nostrils (fire inside)
MZ(2.22, 2.34, 4.6, 4.63, 0.08, 0.2, 'P', E, '#FF7A1A');
S('DragonGem');
B(1.6, 1.7, 4.62, 4.86, -0.11, 0.11, 'P', 0, GOLD);
B(1.7, 1.73, 4.67, 4.81, -0.06, 0.06, 'P', E, '#FF2DD1');
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('BrowRidge');                                             // confident angled brow
	B(0.95, 1.25, 4.88, 4.96, ...z(0.52, 0.62), 'upper');
	B(0.65, 0.95, 4.93, 5.0, ...z(0.52, 0.62), 'upper');
	S('Horn');                                                  // chunky violet horns, glowing gold band, gold tip
	B(0.55, 0.85, 4.95, 5.25, ...z(0.22, 0.42), 'prop');
	B(0.35, 0.66, 5.2, 5.45, ...z(0.26, 0.45), 'prop');
	B(0.12, 0.42, 5.38, 5.58, ...z(0.3, 0.46), 'prop');
	B(-0.12, 0.16, 5.5, 5.66, ...z(0.33, 0.45), 'prop');
	B(-0.3, -0.08, 5.56, 5.7, ...z(0.35, 0.43), 'P', 0, GOLD);
	B(0.53, 0.87, 5.04, 5.1, ...z(0.21, 0.43), 'stripe', E);
	S('Frill');                                                 // bold violet frill fins
	B(0.5, 0.78, 4.4, 4.75, ...z(0.56, 0.74), 'prop');
	B(0.52, 0.8, 4.08, 4.4, ...z(0.56, 0.7), 'prop');
}
// big side anime eyes (BRT_027 construction, scaled), green iris, lash bar, blush
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 0.56, k = 0.42, X = 0.62, Y = 4.22;
	const y = (v) => Y + (v - 4.2) * k, x = (v) => X + v * k;
	const [w0, w1] = zz(zf, zf + 0.03), [i0, i1] = zz(zf + 0.03, zf + 0.05), [p0, p1] = zz(zf + 0.05, zf + 0.07), [c0, c1] = zz(zf + 0.07, zf + 0.09);
	S('EyeWhite');
	B(x(0.12), x(1.27), y(4.2), y(5.85), w0, w1, 'P', 0, '#FFFFFF');
	B(x(0), x(1.39), y(4.35), y(5.7), w0, w1, 'P', 0, '#FFFFFF');
	S('Iris');
	B(x(0.22), x(1.17), y(5.1), y(5.65), i0, i1, 'P', 0, '#1F4A0B');
	B(x(0.22), x(1.17), y(4.65), y(5.1), i0, i1, 'P', 0, '#45D11E');
	B(x(0.22), x(1.17), y(4.27), y(4.65), i0, i1, 'P', 0, '#C8FF6A');
	S('Pupil');
	B(x(0.47), x(0.94), y(4.7), y(5.35), p0, p1, 'P', 0, '#0A0B1A');
	S('Catchlight');
	B(x(0.32), x(0.68), y(5.13), y(5.51), c0, c1, 'P', E, '#FFFFFF');
	B(x(0.88), x(1.06), y(4.45), y(4.63), c0, c1, 'P', E, '#FFFFFF');
	B(x(1.0), x(1.08), y(5.21), y(5.29), c0, c1, 'P', E, '#FFFFFF');
	S('Lash');
	const [l0, l1] = zz(zf, zf + 0.1);
	B(x(-0.06), x(1.47), y(5.77), y(5.95), l0, l1, 'P', 0, '#000000');
	B(x(-0.28), x(0.02), y(5.9), y(6.14), l0, l1, 'P', 0, '#000000');
	S('Blush');
	B(x(0.05), x(0.75), y(3.8), y(4.05), w0, w1, 'P', E, '#FF6FA3');
}

// --- armour: violet pauldrons with glowing gold trim and gold spikes (mirrored pair)
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('Pauldron');
	B(-0.5, 0.55, 3.35, 3.75, ...z(0.8, 1.25), 'prop', R);
	B(-0.4, 0.45, 3.75, 3.85, ...z(0.85, 1.15), 'prop');
	S('PauldronTrim');
	B(-0.52, 0.57, 3.3, 3.36, ...z(0.78, 1.27), 'stripe', E);
	S('PauldronSpike');
	B(-0.1, 0.1, 3.85, 4.08, ...z(0.98, 1.1), 'P', 0, GOLD);
}

// --- big chunky arms (mirrored pair): sauce-ring elbows, violet bracers with gold trim, big fists, gold claws
for (const s of [1, -1]) {
	const zc = 1.12 * s;
	S('UpperArm');
	cb(-0.2, 0.24, 2.75, 3.36, zc - 0.2, zc + 0.2, 0.05, 'skin');
	S('SauceRing');
	B(-0.2, 0.24, 2.67, 2.75, zc - 0.21, zc + 0.21, 'feather2', E);
	S('Forearm');
	cb(-0.18, 0.5, 2.35, 2.67, zc - 0.2, zc + 0.2, 0.05, 'skin');
	S('Bracer');
	B(0.12, 0.42, 2.31, 2.71, zc - 0.23, zc + 0.23, 'prop', R);
	B(0.42, 0.46, 2.31, 2.71, zc - 0.23, zc + 0.23, 'stripe', E);
	S('Fist');
	cb(0.46, 0.8, 2.26, 2.72, zc - 0.22, zc + 0.22, 0.05, 'skin');
	S('Claw');
	for (const dz of [-0.13, 0, 0.13]) B(0.8, 0.92, 2.3, 2.4, zc + dz - 0.045, zc + dz + 0.045, 'P', 0, GOLD);
}

// --- clean swept wings (mirrored pair): three bold crimson panels, violet bones, glowing gold leading-edge trim
const wx = (zc) => -0.72 - 0.16 * (zc - 0.9);
const PANELS = [[0.9, 1.6, 2.6, 3.95], [1.6, 2.3, 2.8, 4.55], [2.3, 2.95, 3.2, 4.9]];
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('WingRoot');
	B(-0.8, -0.55, 3.0, 3.6, ...z(0.5, 0.95), 'prop', R);
	B(-0.82, -0.6, 3.1, 3.5, ...z(0.88, 0.96), 'feather2', E);
	for (const [z0, z1, y0, y1] of PANELS) {
		const x = wx((z0 + z1) / 2);
		S('WingPanel');
		B(x - 0.05, x + 0.05, y0, y1, ...z(z0, z1), 'skin2', R);
		S('WingBone');
		B(x - 0.08, x + 0.08, y1, y1 + 0.12, ...z(z0 - 0.03, z1 + 0.03), 'prop');
		S('WingTrim');
		B(x - 0.08, x + 0.08, y1 + 0.12, y1 + 0.16, ...z(z0 - 0.03, z1 + 0.03), 'stripe', E);
		S('FlameTip');
		B(x - 0.04, x + 0.04, y0 - 0.18, y0, ...z(z0 + 0.2, z1 - 0.2), 'accent', E);
	}
	S('FingerBone');
	B(wx(1.6) - 0.07, wx(1.6) + 0.07, 2.6, 4.55, ...z(1.56, 1.64), 'prop');
	B(wx(2.3) - 0.07, wx(2.3) + 0.07, 2.8, 4.9, ...z(2.26, 2.34), 'prop');
	S('WristClaw');
	B(wx(2.95) - 0.08, wx(2.95) + 0.08, 4.9, 5.2, ...z(2.84, 2.98), 'P', 0, GOLD);
}

// --- back bling: the giant gold pasta fork worn on the back, clipped to a violet plate
S('BackBlingClip');
B(-0.72, -0.6, 2.9, 3.1, -0.16, 0.16, 'prop');
S('GoldFork');
B(-0.82, -0.72, 1.9, 4.3, -0.05, 0.05, 'P', 0, GOLD);
B(-0.84, -0.7, 4.3, 4.4, -0.22, 0.22, 'P', 0, GOLD);
for (const z of [-0.19, -0.065, 0.065, 0.19]) B(-0.82, -0.72, 4.4, 4.86, z - 0.025, z + 0.025, 'P', 0, GOLD);
S('ForkGem');
B(-0.86, -0.82, 3.3, 3.5, -0.06, 0.06, 'P', E, '#FF2DD1');

// --- chunky tail with a sauce ring, glowing flame spines and a glowing flame spade
S('Tail');
cb(-1.4, -0.45, 1.8, 2.3, -0.32, 0.32, 0.06, 'upper');
S('SauceRing');
B(-1.48, -1.4, 1.78, 2.26, -0.3, 0.3, 'feather2', E);
S('Tail');
cb(-2.1, -1.48, 1.75, 2.1, -0.22, 0.22, 0.05, 'upper');
S('FlameSpine');
B(-1.2, -0.95, 2.3, 2.56, -0.06, 0.06, 'accent', E);
B(-1.9, -1.68, 2.1, 2.3, -0.05, 0.05, 'accent', E);
S('TailSpade');
B(-2.5, -2.1, 1.6, 2.2, -0.3, 0.3, 'accent', E);
B(-2.68, -2.48, 1.75, 2.05, -0.14, 0.14, 'accent', E);

// --- short thick legs (matching pair): sauce-ring collars, violet knee guards with gold trim, big flat feet
for (const s of [1, -1]) {
	const zc = 0.55 * s;
	S('SauceRing');
	B(-0.3, 0.34, 1.7, 1.78, zc - 0.33, zc + 0.33, 'feather2', E);
	S('Thigh');
	cb(-0.3, 0.34, 1.08, 1.72, zc - 0.32, zc + 0.32, 0.07, 'skin');
	S('SauceRing');
	B(-0.26, 0.28, 1.0, 1.08, zc - 0.28, zc + 0.28, 'feather2', E);
	S('Shin');
	cb(-0.24, 0.26, 0.44, 1.0, zc - 0.26, zc + 0.26, 0.06, 'skin');
	S('KneeGuard');
	B(0.26, 0.36, 0.62, 1.0, zc - 0.22, zc + 0.22, 'prop', R);
	B(0.26, 0.38, 1.0, 1.05, zc - 0.24, zc + 0.24, 'stripe', E);
	S('SauceRing');
	B(-0.2, 0.24, 0.36, 0.44, zc - 0.24, zc + 0.24, 'feather2', E);
	S('Foot');
	cb(-0.35, 0.75, 0, 0.36, zc - 0.34, zc + 0.34, 0.06, 'skin');
	S('Claw');
	for (const dz of [-0.22, 0, 0.22]) B(0.75, 0.9, 0, 0.14, zc + dz - 0.06, zc + dz + 0.06, 'P', 0, GOLD);
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_033_reference.md); fire, not blue. Mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FFC21A', feather: '#FFE48A', feather2: '#FF1F3D', lower: '#FFF3D0', stripe: '#FFD21A', skin: '#FFA51F', skin2: '#FF3B5C', prop: '#7A2BFF', trim: '#FFFFFF', accent: '#FF7A1A', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (Legendary flair): fire breath, wing embers, and a big fiery dragon aura rising around the body
const passiveFx = [
	{ name: 'FireBreath', texture: 'smoke', anchor: [2.42, 3.96, 0], rate: 8, lifetime: [0.5, 0.9], size: [0.25, 0.7], transparency: [0.1, 1], colors: ['#FFB21A', '#FF3D1F'], lightEmission: 1, speed: [1.0, 1.6], spread: 15, rise: 0.6 },
	{ name: 'WingEmbers', texture: 'sparkle', anchor: [-0.9, 3.8, 0], rate: 8, lifetime: [0.8, 1.4], size: [0.22, 0.05], transparency: [0, 1], colors: ['#FFD21A', '#FF3B5C'], lightEmission: 1, speed: [0.5, 1.0], spread: 180, rise: 0.4 },
	{ name: 'DragonAura', texture: 'smoke', anchor: [0, 2.6, 0], rate: 8, lifetime: [1.2, 1.8], size: [0.6, 1.4], transparency: [0.5, 1], colors: ['#FF7A1A', '#FF1F3D'], lightEmission: 1, speed: [0.3, 0.7], spread: 180, rise: 0.9 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { slots: { Jaw: 'Head', Fang: 'Head', Neck: 'Torso', GoldFork: 'Torso', ForkGem: 'Torso', BackBlingClip: 'Torso', Waist: 'Torso', BellyPlate: 'Torso' } };
