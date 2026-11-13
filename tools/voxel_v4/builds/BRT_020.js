// BRT_020 Bisonte Giuppitere — Voxel V4 build (CP-C, Rare, revision 5: giant, 1.5x height).
// Reference (revision 2): the meme picture (yumcut.com character image; brainrotcharacters.net and
// playbrainrot.org text):
// - the planet Jupiter as the body (cream / orange / rust bands)
// - a HUGE bison head mounted on its front, with a lighter shaggy mop and big curling horns
// - black-and-white high-top sneakers right under the ball, no legs
// Revision 3 (owner): "more tough, it's rare and needs to reflect that, needs aura"; less boxy, more
// sculpted, more bison-like; "more tuff aura". Changes:
// - sculpted, bison-like head: a wide forehead tapering to a broad, low, protruding snout; a massive
//   shaggy mane framing the face; a heavy forelock brow; a big chin beard
// - tough: narrowed, glowing red anime eyes with lids and thin angled brows, thick bone horns with
//   gold caps, a gold nose ring and a gold tooth in a smirk, and glowing breath snorting from the nose
// - aura: neon lightning crackling on both sides of the planet, and glowing violet seams on the band
//   edges as well as the gold equator
// - darker, richer, higher-contrast colours
// Revision 4 (owner): a bigger body and head (1.3x relative to the sneakers).
// The gag: the planet hovers a hair above its black-and-white high-tops on a glowing ring, with two
// little moons in orbit.
// Rig-ready (owner rule): the sneakers are a matching pair.
// V4 core rules: kit anime eyes (Ruby; thin lash line and lids, thin angled brows, catchlights) on
// white eye domes, glowing Neon lightning, seams, breath and ring, light-up soles, studs on body
// panels only. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const INK = '#141018';
const BONE = '#F2E2C0';
const GOLD = '#FFC21A';
const NOSE = '#3A2A30';

// three-box rounded layer (octagon with filled corners)
function layer(cx, y0, y1, r, role, rel = R) {
	B(cx - r, cx + r, y0, y1, -0.7 * r, 0.7 * r, role, rel);
	B(cx - 0.7 * r, cx + 0.7 * r, y0, y1, -r, r, role, rel);
	B(cx - 0.88 * r, cx + 0.88 * r, y0, y1, -0.88 * r, 0.88 * r, role, rel);
}
const PCY = 2.45, PR = 1.25;
const rP = (y) => Math.sqrt(Math.max(0.04, PR * PR - (y - PCY) * (y - PCY)));

// --- the planet Jupiter: banded sphere (the gold equator band's front box is the Body)
S('Body');
B(-PR, PR, 2.2, 2.7, -0.72 * PR, 0.72 * PR, 'upper', R);
S('Jupiter');
B(-0.68 * PR, 0.68 * PR, 2.2, 2.7, -PR, PR, 'upper', R);
B(-0.84 * PR, 0.84 * PR, 2.2, 2.7, -0.84 * PR, 0.84 * PR, 'upper', R);         // kept smaller than the Body
for (const [y0, y1, role] of [[1.2, 1.4, 'feather'], [1.4, 1.64, 'lower'], [1.64, 1.92, 'prop'], [1.92, 2.2, 'lower'],
	[2.7, 2.98, 'lower'], [2.98, 3.26, 'prop'], [3.26, 3.5, 'lower'], [3.5, 3.7, 'feather']]) {
	layer(0, y0, y1, rP((y0 + y1) / 2), role);
}
// aura seams: gold on the equator, violet on two band edges
S('AuraSeam');
B(-0.88 * PR - 0.02, 0.88 * PR + 0.02, 2.43, 2.47, -0.88 * PR - 0.02, 0.88 * PR + 0.02, 'stripe', E);
for (const y of [1.92, 2.98]) {
	const r = 0.88 * rP(y) + 0.03;
	B(-r, r, y - 0.02, y + 0.02, -r, r, 'accent', E);
}
S('Swirl');
for (const [y, a, role] of [[1.78, 2.4, 'lower'], [2.06, -2.3, 'prop'], [2.84, 2.6, 'prop'], [3.12, -2.6, 'lower']]) {
	const r = rP(y) * 0.92, cx = r * Math.cos(a), cz = r * Math.sin(a);
	B(cx - 0.18, cx + 0.18, y - 0.08, y + 0.08, cz - 0.18, cz + 0.18, role, 0);
}
S('GreatRedSpot');
B(-0.62, 0.02, 1.68, 2.08, -1.2, -1.08, 'P', 0, '#D81E1E');
B(-0.5, -0.1, 1.74, 2.02, -1.24, -1.18, 'P', 0, '#FF6A3A');

// --- sculpted bison head on the front of the planet: wide forehead, tapered low snout
S('Head');
B(0.55, 1.42, 1.95, 2.95, -0.62, 0.62, 'skin', R);              // face core
B(0.5, 1.36, 2.7, 3.12, -0.7, 0.7, 'skin', R);                  // wide forehead
S('Snout');                                                     // broad, low, protruding snout
B(1.3, 1.78, 1.72, 2.32, -0.46, 0.46, 'skin', R);
B(1.74, 1.86, 1.8, 2.24, -0.38, 0.38, 'skin', R);
S('NosePad');
B(1.84, 1.9, 2.0, 2.22, -0.24, 0.24, 'P', 0, NOSE);
S('Nostril');
MZ(1.9, 1.92, 2.04, 2.18, 0.1, 0.24, 'P', 0, INK);
S('NoseRing');
B(1.88, 1.95, 1.84, 2.0, -0.07, 0.07, 'P', 0, GOLD);
S('Mouth');                                                     // tough one-sided smirk with a gold tooth
B(1.86, 1.88, 1.76, 1.83, -0.34, 0.3, 'P', 0, INK);
B(1.84, 1.88, 1.82, 1.9, 0.24, 0.34, 'P', 0, INK);
S('GoldTooth');
B(1.87, 1.9, 1.77, 1.83, 0.04, 0.13, 'P', 0, GOLD);
// massive shaggy mane framing the face, heavy forelock brow, big chin beard
S('Mane');
B(0.38, 1.3, 3.06, 3.58, -0.84, 0.84, 'skin2', R);              // top mop
B(0.5, 1.12, 3.58, 3.8, -0.56, 0.56, 'skin2', R);               // crest
B(1.18, 1.52, 3.0, 3.2, -0.62, 0.62, 'skin2', R);               // heavy forelock brow
for (const s of [1, -1]) {
	B(0.4, 1.22, 1.86, 3.12, 0.6 * s, 1.0 * s, 'skin2', R);      // side mane
	B(1.0, 1.28, 2.1, 2.94, 0.92 * s, 1.04 * s, 'feather2', 0);  // highlight tufts
}
S('Beard');
B(0.9, 1.66, 1.3, 1.8, -0.44, 0.44, 'skin2', R);
B(1.0, 1.52, 1.04, 1.32, -0.28, 0.28, 'skin2', R);
B(1.08, 1.42, 0.9, 1.06, -0.14, 0.14, 'feather2', 0);
for (const s of [1, -1]) {
	S('Horn');                                                  // thick bone horn with a gold cap
	B(0.68, 1.1, 2.9, 3.24, 0.9 * s, 1.4 * s, 'P', 0, BONE);
	B(0.7, 1.08, 3.18, 3.7, 1.16 * s, 1.5 * s, 'P', 0, BONE);
	B(0.74, 1.04, 3.64, 3.96, 1.02 * s, 1.34 * s, 'P', 0, GOLD);
}
// narrowed, glowing red anime eyes: lid over the top of each eye, thin angled brows (inner end lower)
const FX = 1.5;
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.3, FX, 2.4, 2.98, 0.04 * out, 0.56 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.3 * out, top: 2.94, L: 0.98, H: 0.92, out, iris: 'Ruby', lash: false, blush: false });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	const zin = eye.inner, zout = eye.outer, zm = (zin + zout) / 2;
	S('Lid');
	B(FX, FX + 0.07, eye.whiteTop - 0.2, eye.whiteTop + 0.02, z0 - 0.03, z1 + 0.03, 'skin');
	B(FX, FX + 0.08, eye.whiteTop - 0.24, eye.whiteTop - 0.2, z0 - 0.02, z1 + 0.02, 'P', 0, INK);
	S('Brow');
	B(1.34, FX + 0.09, eye.whiteTop + 0.0, eye.whiteTop + 0.04, Math.min(zin, zm), Math.max(zin, zm), 'P', 0, INK);
	B(1.34, FX + 0.09, eye.whiteTop + 0.04, eye.whiteTop + 0.08, Math.min(zm, zout), Math.max(zm, zout), 'P', 0, INK);
}
// glowing breath snorting from both nostrils
S('Breath');
for (const s of [1, -1]) {
	B(1.86, 1.96, 2.06, 2.16, 0.4 * s, 0.5 * s, 'P', E, '#E8F6FF');     // small puffs off the sides
	B(1.9, 1.98, 2.14, 2.22, 0.54 * s, 0.62 * s, 'P', E, '#E8F6FF');
}

// --- aura: neon lightning crackling down both sides of the planet
S('Lightning');
for (const s of [1, -1]) {
	for (const [x0, y0, y1] of [[-0.1, 3.3, 3.75], [0.08, 2.9, 3.34], [-0.12, 2.5, 2.94], [0.06, 2.14, 2.54]]) {
		B(x0 - 0.05, x0 + 0.13, y0, y1, 1.56 * s - 0.04, 1.56 * s + 0.04, 'stripe', E);
	}
}

// --- two little moons in orbit
S('Moon');
B(-1.7, -1.44, 3.3, 3.56, 0.8, 1.06, 'P', 0, '#FFE14D');        // Io
B(-0.2, 0.02, 0.98, 1.2, -1.62, -1.4, 'P', 0, '#BFE6FF');      // Europa

// --- revision 4 (owner: "bigger body and head"): the planet, bison head, aura and moons are scaled up
// 1.3x about the bottom of the planet, so they tower over the sneakers
const BODY_SCALE = 1.3, BODY_PIVOT = [0, 1.2, 0];
for (const p of parts) for (const i of [0, 1, 2]) {
	p.min[i] = BODY_PIVOT[i] + (p.min[i] - BODY_PIVOT[i]) * BODY_SCALE;
	p.max[i] = BODY_PIVOT[i] + (p.max[i] - BODY_PIVOT[i]) * BODY_SCALE;
}
for (const p of parts) { p.min[1] += 0.2; p.max[1] += 0.2; }   // lifted so the hover gap and ring still read

// --- the gag: hovering a hair above detailed black-and-white high-tops on a glowing ring
S('AntiGravRing');
B(-0.66, 0.66, 1.18, 1.22, -0.46, 0.46, 'accent', E);
B(-0.46, 0.46, 1.18, 1.22, -0.66, 0.66, 'accent', E);
for (const s of [1, -1]) {
	const zc = 0.46 * s;
	S('Sneaker');
	B(-0.44, 0.48, 0.1, 0.62, zc - 0.3, zc + 0.3, 'foot', R);
	B(0.48, 0.78, 0.1, 0.42, zc - 0.27, zc + 0.27, 'foot');
	S('HighTop');
	B(-0.4, 0.22, 0.62, 1.02, zc - 0.28, zc + 0.28, 'foot', R);
	S('Collar');
	B(-0.41, 0.23, 0.96, 1.04, zc - 0.29, zc + 0.29, 'trim');
	S('Opening');
	B(-0.32, 0.14, 1.03, 1.05, zc - 0.2, zc + 0.2, 'P', 0, INK);
	S('ToeCap');
	B(0.6, 0.8, 0.1, 0.32, zc - 0.25, zc + 0.25, 'trim');
	S('Midsole');
	B(-0.46, 0.8, 0.04, 0.16, zc - 0.31, zc + 0.31, 'trim');
	S('Laces');
	for (const [y, dz] of [[0.48, 0.08], [0.64, -0.08], [0.8, 0.08]]) B(0.2, 0.27, y, y + 0.06, zc - 0.17 + dz, zc + 0.17 + dz, 'trim');
	S('Sole');
	B(-0.46, 0.8, 0, 0.04, zc - 0.31, zc + 0.31, 'accent', E);
}

// Darker, richer, high-contrast "tuff aura" palette (docs/creatures/V4/BRT_020_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF8A12', lower: '#FFE2A8', prop: '#D9420C', feather: '#6A1E08', skin: '#6E3618', skin2: '#8E4A1C', feather2: '#E0A050', foot: '#141018', trim: '#FFFFFF', stripe: '#FFD21A', accent: '#B44CFF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// Revision 5 (owner): "Much bigger, we need some giant brainrots too": a giant species, 1.5x the shared
// gameplay height (Builder.SizeMultiplier), with fit limits scaled by the same factor.
const sizeMultiplier = 1.5;
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, sizeMultiplier };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass): the whole face is one rigid group, so the mane, beard and mouth
// join the head (some sat on the planet and would have stayed behind when the head moved). Each
// moon gets its own bone at the planet's centre so it can orbit (signature prop): Io is the high
// one behind the right shoulder, Europa the low one on the left.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { NoseRing: 'Head', GoldTooth: 'Head', Mane: 'Head', Beard: 'Head', Mouth: 'Head' },
	extraBones: {
		MoonIo: { parent: 'Torso', pivot: [0, 3.025, 0] },
		MoonEuropa: { parent: 'Torso', pivot: [0, 3.025, 0] },
	},
	regions: [
		{ bone: 'MoonIo', region: [-3, -1.5, 3.5, 5, 0.5, 2], only: /^Moon$/ },
		{ bone: 'MoonEuropa', region: [-1, 1, 0.5, 2, -3, -1.5], only: /^Moon$/ },
	],
};
