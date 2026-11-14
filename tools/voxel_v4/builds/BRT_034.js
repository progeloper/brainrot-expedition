// BRT_034 Orcalero Orcala — Voxel V4 build (CP-D, Mythic, teased; revision 7).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki and the Steal a Brainrot
// fandom wiki infobox): a horizontal black-and-white orca with a big blunt head, white lower jaw and chin, a white eye
// patch behind the eye, a big hooked dorsal fin, a white underside and flank swirl, horizontal flukes, and four short
// legs in big chunky black-and-white sneakers.
// Revision 7 (owner): "go back to the drawing board, get references from steal a brainrot and convert to the
// established high dopamine v4 style that's fortnite coded and lay off the neon pink, use other colours"; more
// dopamine, smoother, Mythic wow factor.
// Orcalero Orcala is the orca counterpart of the approved BRT_027 Tralalero Tralala (a shark in sneakers), so this
// build reuses BRT_027's approved V4 construction exactly, converted to the Steal a Brainrot orca:
// - a big chunky tapering torpedo of sections, white lower third, a thick glowing waterline between (BRT_027)
// - BRT_027's huge side anime eyes (amber), lash with flick and blush; BRT_027's wrap-around grin with spaced side
//   teeth, front teeth and tongue; nostrils become a blowhole
// - orca changes: a blunt rounded head, a tall hooked dorsal fin, the white orca eye patch behind each eye (in place
//   of gills), a lavender-grey saddle, a white flank swirl, horizontal flukes, two flipper-legs in front (BRT_027's
//   fin-legs) and two legs at the back (Steal a Brainrot has four)
// - BRT_027's chunky light-up sneakers (no logos), in tangerine with white midsoles and glowing lime soles
// - colours: royal indigo over white with a glowing gold waterline, gold fin tip and fluke edges; no pink, no blue
// - Fortnite-coded (art-style archetype only): big chunky clean shapes and a big head, as in BRT_027
// - Mythic aura: gold-and-tangerine aura, blowhole spray, and lime-and-gold star sparkles
// Rig-ready (owner rule): four legs as two matching pairs with ankle collars; sneakers flat, pointing ahead.
// Design units, y up, nose = +x (BRT_027 scale).
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const GOLD = '#FFD21A';
const MAW = '#6E0E2C';

// --- chunky torpedo body: [x0, x1, yBottom, yTop, halfWidth, relief]; a blunt, rounded orca head at the front
const secs = [
	[-5.0, -3.9, 3.55, 4.55, 0.5, 1],
	[-3.9, -2.7, 3.15, 4.95, 0.85, 1],
	[-2.7, -1.2, 2.85, 5.3, 1.15, 1],
	[-1.2, 0.5, 2.65, 5.55, 1.32, 1],
	[0.5, 3.0, 2.6, 6.3, 1.38, 0],    // head (no studs: eye panel)
	[3.0, 3.9, 2.75, 5.95, 1.25, 0],
	[3.9, 4.6, 2.95, 5.45, 1.0, 0],
	[4.6, 5.05, 3.25, 4.85, 0.66, 0],
];
for (const [x0, x1, yb, yt, hw, rel] of secs) {
	const yw = yb + 0.42 * (yt - yb);                         // countershading waterline
	S('BodySection');
	B(x0, x1, yb, yw, -hw, hw, 'lower', rel ? R : 0);
	S('Waterline');
	B(x0, x1, yw, yw + 0.16, -hw - 0.02, hw + 0.02, 'stripe', E);
	S('BodySection');
	B(x0, x1, yw + 0.16, yt, -hw, hw, 'upper', rel ? R : 0);
}
S('HeadDome');                                                  // rounds off the top of the head
B(0.7, 2.8, 6.3, 6.45, -1.15, 1.15, 'upper');
B(3.0, 3.75, 5.95, 6.1, -1.0, 1.0, 'upper');

// --- orca markings: lavender-grey saddle behind the fin, white flank swirl rising toward the tail
S('Saddle');
B(-2.6, -1.3, 5.3, 5.34, -0.9, 0.9, 'feather');
MZ(-2.6, -1.4, 4.85, 5.3, 1.15, 1.18, 'feather');
S('FlankSwirl');
MZ(-2.6, -1.4, 4.04, 4.62, 1.15, 1.18, 'lower');
MZ(-3.8, -2.7, 4.04, 4.75, 0.85, 0.88, 'lower');

// --- tall hooked orca dorsal fin with a glowing gold tip
S('DorsalFin');
B(-1.5, 0.5, 5.55, 6.3, -0.3, 0.3, 'upper', R);
B(-1.45, 0.2, 6.3, 7.1, -0.26, 0.26, 'upper', R);
B(-1.4, -0.2, 7.1, 7.9, -0.22, 0.22, 'upper', R);
B(-1.5, -0.55, 7.9, 8.5, -0.18, 0.18, 'upper', R);
B(-1.8, -0.9, 8.5, 8.85, -0.14, 0.14, 'upper');
S('FinGlow');
B(-1.95, -1.65, 8.7, 8.95, -0.1, 0.1, 'P', E, GOLD);

// --- horizontal orca flukes, slightly lifted, with glowing gold trailing edges
S('Fluke');
B(-5.6, -4.9, 3.75, 4.3, -0.4, 0.4, 'upper', R);
B(-6.3, -5.4, 3.95, 4.2, -1.1, 1.1, 'upper', R);
MZ(-6.7, -6.0, 3.95, 4.2, 0.8, 1.6, 'upper');
S('FlukeGlow');
B(-6.36, -6.3, 3.95, 4.2, -0.8, 0.8, 'P', E, GOLD);
MZ(-6.78, -6.7, 3.95, 4.2, 0.8, 1.6, 'P', E, GOLD);

// --- sneaker builder (BRT_027's chunky light-up kicks; no logos)
function shoe(x, z, len) { // x = heel, toe at +x
	S('Sneaker');
	B(x, x + len, 0, 0.22, z - 0.42, z + 0.42, 'accent', E);                 // light-up sole
	B(x, x + len, 0.22, 0.46, z - 0.42, z + 0.42, 'trim');                   // white midsole
	B(x + 0.05, x + len - 0.3, 0.46, 1.05, z - 0.38, z + 0.38, 'foot', R);   // upper
	B(x + len - 0.32, x + len, 0.46, 0.85, z - 0.36, z + 0.36, 'foot');      // toe cap
	B(x + len - 0.3, x + len + 0.02, 0.46, 0.6, z - 0.37, z + 0.37, 'trim'); // toe bumper
	for (const lx of [x + 0.5, x + 0.85, x + 1.2]) B(lx, lx + 0.22, 1.05, 1.14, z - 0.24, z + 0.24, 'trim'); // laces
	B(x + 0.05, x + len - 0.35, 0.62, 0.78, z + 0.38, z + 0.41, 'trim');      // side flash
	B(x + 0.05, x + len - 0.35, 0.62, 0.78, z - 0.41, z - 0.38, 'trim');
	B(x - 0.06, x + 0.22, 0.5, 1.15, z - 0.2, z + 0.2, 'accent', E);         // glowing heel tab
	B(x + 0.05, x + 0.75, 1.05, 1.25, z - 0.36, z + 0.36, 'P', 0, DARK);      // ankle collar
}
// --- front flipper-legs (BRT_027's pectoral fin-legs)
for (const s of [1, -1]) {
	const z = 1.05 * s;
	S('FinLeg');
	B(0.3, 1.9, 2.25, 2.75, z - 0.35, z + 0.35, 'upper', R);    // flipper root
	B(0.2, 1.6, 2.6, 2.85, z + 0.25 * s, z + 0.85 * s, 'upper', R); B(0.0, 1.0, 2.45, 2.65, z + 0.7 * s, z + 1.05 * s, 'upper', R); // flared flipper
	B(0.55, 1.45, 1.25, 2.3, z - 0.3, z + 0.3, 'upper', R);     // thigh
	B(0.7, 1.3, 1.2, 1.3, z - 0.28, z + 0.28, 'upper');
	shoe(0.2, z, 1.75);
}
// --- rear legs (matching pair; Steal a Brainrot's orca has four legs)
for (const s of [1, -1]) {
	const z = 0.62 * s;
	S('RearLeg');
	B(-3.5, -2.7, 2.6, 3.3, z - 0.3, z + 0.3, 'upper', R);
	B(-3.45, -2.75, 1.25, 2.6, z - 0.28, z + 0.28, 'upper', R);
	B(-3.35, -2.85, 1.2, 1.3, z - 0.26, z + 0.26, 'upper');
	shoe(-3.85, z, 1.75);
}

// --- face: BRT_027 anime eyes, the white orca eye patch behind each eye, BRT_027 grin, blowhole
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 1.38;
	const [w0, w1] = zz(zf, zf + 0.04), [i0, i1] = zz(zf + 0.04, zf + 0.07), [p0, p1] = zz(zf + 0.07, zf + 0.1), [c0, c1] = zz(zf + 0.1, zf + 0.12);
	const X = 1.45; // eye rear x
	S('EyePatch');                                              // the white orca eye patch, behind and above the eye
	B(0.55, 1.42, 4.7, 5.85, ...zz(1.38, 1.405), 'lower');
	B(0.2, 0.5, 4.95, 5.6, ...zz(1.32, 1.345), 'lower');
	S('EyeWhite');
	B(X + 0.12, X + 1.27, 4.2, 5.85, w0, w1, 'P', 0, '#ffffff'); B(X, X + 1.39, 4.35, 5.7, w0, w1, 'P', 0, '#ffffff');
	S('Iris');
	B(X + 0.22, X + 1.17, 5.1, 5.65, i0, i1, 'P', 0, '#7a2a10');
	B(X + 0.22, X + 1.17, 4.65, 5.1, i0, i1, 'P', 0, '#ff6a1a');
	B(X + 0.22, X + 1.17, 4.27, 4.65, i0, i1, 'P', 0, '#ffcf45');
	S('Pupil');
	B(X + 0.47, X + 0.94, 4.7, 5.35, p0, p1, 'P', 0, '#1a0b06');
	S('Catchlight');
	B(X + 0.32, X + 0.68, 5.13, 5.51, c0, c1, 'P', E, '#ffffff');
	B(X + 0.88, X + 1.06, 4.45, 4.63, c0, c1, 'P', E, '#ffffff');
	B(X + 1.0, X + 1.08, 5.21, 5.29, c0, c1, 'P', E, '#ffffff');
	const [l0, l1] = zz(zf, zf + 0.14);
	S('Lash');
	B(X - 0.06, X + 1.47, 5.77, 6.01, l0, l1, 'P', 0, '#000000');
	B(X - 0.28, X + 0.02, 5.9, 6.2, l0, l1, 'P', 0, '#000000');
	B(X + 1.32, X + 1.52, 5.65, 5.83, l0, l1, 'P', 0, '#000000');
	S('Blush');
	B(X + 0.05, X + 0.75, 3.8, 4.05, w0, w1, 'P', E, '#ff8a5c');
}
// grin: dark mouth band wrapping snout front + both sides, spaced teeth, tongue, upturned corners (BRT_027)
S('Mouth');
B(2.3, 4.95, 3.25, 3.62, -1.0, 1.0, 'P', 0, MAW);
B(4.95, 5.07, 3.4, 3.62, -0.5, 0.5, 'P', 0, MAW);
for (const [x0, x1, hw] of [[2.25, 3.0, 1.38], [3.0, 3.9, 1.25], [3.9, 4.6, 1.0], [4.6, 5.05, 0.66]]) {
	S('Mouth');
	MZ(x0, x1, 3.25, 3.62, hw, hw + 0.03, 'P', 0, MAW);
	S('Teeth');
	for (let tx = x0 + 0.06; tx + 0.2 <= x1; tx += 0.34) MZ(tx, tx + 0.2, 3.47, 3.62, hw + 0.03, hw + 0.05, 'P', 0, '#ffffff');
}
S('Mouth');
MZ(2.0, 2.3, 3.4, 3.85, 1.38, 1.41, 'P', 0, MAW);
MZ(1.85, 2.1, 3.75, 4.0, 1.38, 1.41, 'P', 0, MAW);
S('Teeth');
B(4.97, 5.08, 3.62, 3.68, -0.5, 0.5, 'P', 0, '#ffffff');
S('Tongue');
B(2.8, 4.7, 3.25, 3.36, -0.7, 0.7, 'P', 0, '#ff4f7a');
MZ(3.0, 3.8, 3.25, 3.34, 1.26, 1.27, 'P', 0, '#ff4f7a');
S('Blowhole');
B(1.2, 1.6, 6.45, 6.48, -0.18, 0.18, 'P', 0, DARK);

// High-dopamine V4 palette (docs/creatures/V4/BRT_034_reference.md); no pink, no blue. Mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#2B2F7A', lower: '#FFFFFF', stripe: '#FFB21A', feather: '#B9C0E8', trim: '#FFFFFF', foot: '#FF7A1A', accent: '#7DFF2E', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (Mythic flair): a gold-and-tangerine aura, blowhole spray, lime-and-gold star sparkles
const passiveFx = [
	{ name: 'MythicAura', texture: 'smoke', anchor: [0, 4.3, 0], rate: 7, lifetime: [1.2, 1.8], size: [0.5, 1.3], transparency: [0.55, 1], colors: ['#FFB21A', '#FF7A1A'], lightEmission: 1, speed: [0.3, 0.6], spread: 180, rise: 0.8 },
	{ name: 'BlowholeSpray', texture: 'sparkle', anchor: [1.4, 6.55, 0], rate: 7, lifetime: [0.6, 1.1], size: [0.2, 0.05], transparency: [0, 1], colors: ['#FFFFFF', '#FFE9A8'], lightEmission: 1, speed: [1.0, 1.6], spread: 20, rise: -0.8 },
	{ name: 'StarSparkle', texture: 'sparkle', anchor: [0, 4.8, 0], rate: 6, lifetime: [0.8, 1.4], size: [0.24, 0.05], transparency: [0, 1], colors: ['#7DFF2E', '#FFD21A'], lightEmission: 1, speed: [0.4, 0.9], spread: 180, rise: 0.2 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Animation rig (14 Nov 2026): BRT_027's head joint behind the eyes and a knee above every
// sneaker, so the orca can take Tralalero Tralala's approved set.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	noHead: true,
	extraBones: {
		Head: { parent: 'Torso', pivot: [0.5, 4.3, 0] },
		FrontRightLowerLeg: { parent: 'FrontRightLeg', pivot: [1.0, 1.25, 1.05] },
		FrontLeftLowerLeg: { parent: 'FrontLeftLeg', pivot: [1.0, 1.25, -1.05] },
		BackRightLowerLeg: { parent: 'BackRightLeg', pivot: [-3.1, 1.25, 0.62] },
		BackLeftLowerLeg: { parent: 'BackLeftLeg', pivot: [-3.1, 1.25, -0.62] },
	},
	regions: [
		{ bone: 'Head', region: [0.5, 6, 0, 9, -3, 3], only: /^(BodySection|Waterline|HeadDome|Mouth|Teeth|Tongue|EyePatch|EyeWhite|Iris|Pupil|Catchlight|Lash|Blush|Blowhole)$/ },
		{ bone: 'Head', region: [0.1, 0.6, 4.9, 5.7, -2, 2], only: /^EyePatch$/ },
		{ bone: 'Torso', region: [-1, 3, 2.3, 3, -3, 3], only: /^FinLeg$/ },
		{ bone: 'FrontRightLowerLeg', region: [-1, 3, 0, 1.3, 0, 3], only: /^Sneaker$/ },
		{ bone: 'FrontLeftLowerLeg', region: [-1, 3, 0, 1.3, -3, 0], only: /^Sneaker$/ },
		{ bone: 'BackRightLowerLeg', region: [-5, -1.5, 0, 1.3, 0, 3], only: /^Sneaker$/ },
		{ bone: 'BackLeftLowerLeg', region: [-5, -1.5, 0, 1.3, -3, 0], only: /^Sneaker$/ },
	],
};
