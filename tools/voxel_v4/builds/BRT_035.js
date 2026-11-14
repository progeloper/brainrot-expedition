// BRT_035 La Secret Combinasion — Voxel V4 build (CP-D, Secret, teased; revision 1).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki and the Steal a Brainrot
// fandom wiki infobox: "a fusion of multiple Brainrots"): Spaghetti Tualetti's white porcelain toilet body and white
// glove hands; Esok Sekolah's rosy cheeks, long tongue, the "9" on its head, the "9" sign held in one hand and the
// little bell on top; Torrtuginni Dragonfrutini's dragon-fruit shell on its back; Pot Hotspot's wooden upper body with
// a phone for a head rising out of the top, and its wooden legs at the bottom.
// V4 conversion, started from the approved BRT_027 construction (owner rule: "established V4 style"):
// - porcelain-white tank over a white bowl split by a thick glowing waterline, here a prismatic Secret rim
//   (gold front, through tangerine and lime to mint and violet at the back); no neon-pink glow, no blue
// - BRT_027-construction huge anime eyes (violet), Esok Sekolah's big rosy cheeks, a wide open grin with spaced cone
//   teeth, and the long scarlet tongue hanging over the bowl carrying a spaghetti-and-meatball gag
// - signature: a gold-framed phone head with a worried wooden face on a glowing mint screen, the glowing gold "9"
//   on the forehead, and the orange "9" sign with a glowing gold border held up in a white glove
// - dragon-fruit shell on the back: magenta with seeds and green scales tipped in glowing lime
// - BRT_027's chunky light-up sneakers (no logos), in violet with gold light-up soles, on wooden legs
// - Secret flair: a gold flush lever and lid, a gold bell, prismatic aura particles and phone-signal sparkles
// Rig-ready (owner rule): legs and arms are matching mirrored pairs with collars; sneakers flat, pointing ahead.
// Design units, y up, front = +x, z = left/right.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const GOLD = '#FFD21A';
const MAW = '#5A0A1E';
const TONGUE = '#FF3B3B';
const INK = '#1A1410';

// chamfered block: two overlapping boxes give clean bevelled edges (BRT_033)
function cb(x0, x1, y0, y1, z0, z1, c, role, f = R, col = null) {
	B(x0, x1, y0 + c, y1 - c, z0, z1, role, f, col);
	B(x0 + c, x1 - c, y0, y1, z0 + c, z1 - c, role, f, col);
}
// pixel "9" (3 x 5 cells) on a +x-facing plane at x..x+d; viewed from the front, -z is the viewer's right
function nine(x, d, yb, zc, cw, ch, col, flags) {
	const z = (a, b) => [zc + 1.5 * cw - b * cw, zc + 1.5 * cw - a * cw];
	const y = (r) => [yb + (4 - r) * ch, yb + (5 - r) * ch];
	B(x, x + d, ...y(0), ...z(0, 3), 'P', flags, col);
	B(x, x + d, ...y(1), ...z(0, 1), 'P', flags, col);
	B(x, x + d, ...y(1), ...z(2, 3), 'P', flags, col);
	B(x, x + d, ...y(2), ...z(0, 3), 'P', flags, col);
	B(x, x + d, ...y(3), ...z(2, 3), 'P', flags, col);
	B(x, x + d, ...y(4), ...z(0, 3), 'P', flags, col);
}

// --- porcelain tank: the Body (single largest upper box), with a chamfered gold lid
S('Body');
B(-0.85, 1.0, 3.68, 6.45, -1.3, 1.3, 'upper', R);
S('TankEdge');
B(-0.8, 0.95, 3.68, 6.5, -1.34, 1.34, 'upper');
S('Lid');
cb(-0.95, 1.12, 6.45, 6.68, -1.42, 1.42, 0.05, 'stripe', 0);
S('FlushLever');
B(1.0, 1.1, 6.05, 6.17, 0.85, 1.22, 'P', E, GOLD);
B(1.0, 1.14, 5.98, 6.2, 0.78, 0.88, 'P', 0, GOLD);
S('ForeheadNine');
nine(1.0, 0.04, 5.94, 0, 0.1, 0.095, GOLD, E);

// --- bowl projecting in front of the tank (the toilet read), with a pedestal (white belly)
S('Bowl');
cb(-0.9, 1.5, 2.3, 3.5, -1.15, 1.15, 0.1, 'lower');
cb(1.4, 1.95, 2.4, 3.5, -0.85, 0.85, 0.08, 'lower');
S('Pedestal');
cb(-0.5, 1.1, 1.85, 2.35, -0.8, 0.8, 0.06, 'lower');

// --- prismatic Secret seat / waterline: gold front -> tangerine -> lime -> mint -> violet back
S('Waterline');
B(-0.95, 1.5, 3.5, 3.68, -1.2, 1.2, 'stripe', E);
B(1.5, 2.0, 3.5, 3.68, -0.9, 0.9, 'stripe', E);
const RIM = [[-0.95, -0.25, '#9B5BFF'], [-0.25, 0.45, '#2EFFB0'], [0.45, 1.15, '#7DFF2E'], [1.15, 1.5, '#FF8A1A']];
for (const [x0, x1, c] of RIM) MZ(x0, x1, 3.5, 3.68, 1.2, 1.23, 'P', E, c);
MZ(1.5, 2.0, 3.5, 3.68, 0.9, 0.93, 'P', E, '#FF8A1A');
MZ(1.5, 1.53, 3.5, 3.68, 0.93, 1.2, 'P', E, '#FF8A1A');
B(2.0, 2.03, 3.5, 3.68, -0.9, 0.9, 'P', E, GOLD);
B(-0.98, -0.95, 3.5, 3.68, -1.23, 1.23, 'P', E, '#9B5BFF');
S('BowlOpening');
B(1.05, 1.8, 3.68, 3.7, -0.62, 0.62, 'P', 0, '#2A1A3A');

// --- face: BRT_027-construction anime eyes (violet), rosy cheeks, open grin with spaced cone teeth
for (const s of [1, -1]) frontEye({ faceX: 1.0, zc: 0.62 * s, top: 5.75, L: 1.42, H: 1.4, out: s, iris: 'Violet', blush: false });
S('Cheek');
MZ(1.0, 1.05, 4.3, 4.8, 0.92, 1.28, 'P', E, '#FF5A4D');
S('Mouth');
B(1.0, 1.04, 3.82, 4.75, -0.86, 0.86, 'P', 0, MAW);
B(1.0, 1.04, 3.95, 4.62, -0.98, 0.98, 'P', 0, MAW);
S('Teeth');
for (const zc of [-0.62, -0.21, 0.21, 0.62]) {   // spaced upper cone teeth
	B(1.04, 1.08, 4.55, 4.75, zc - 0.1, zc + 0.1, 'P', 0, '#FFFFFF');
	B(1.04, 1.08, 4.43, 4.55, zc - 0.05, zc + 0.05, 'P', 0, '#FFFFFF');
}
for (const zc of [-0.42, 0.42]) {                  // two lower cone teeth
	B(1.04, 1.08, 3.82, 3.97, zc - 0.08, zc + 0.08, 'P', 0, '#FFFFFF');
	B(1.04, 1.08, 3.97, 4.06, zc - 0.04, zc + 0.04, 'P', 0, '#FFFFFF');
}
// --- the long tongue lolling out over the seat and down the bowl front, with the spaghetti-and-meatball gag
S('Tongue');
B(1.0, 2.0, 3.7, 3.86, -0.5, 0.5, 'P', 0, TONGUE);
cb(1.96, 2.16, 2.75, 3.86, -0.52, 0.52, 0.04, 'P', 0, TONGUE);
B(1.96, 2.14, 2.5, 2.75, -0.38, 0.38, 'P', 0, TONGUE);
B(1.96, 2.12, 2.38, 2.5, -0.2, 0.2, 'P', 0, TONGUE);
B(1.1, 1.96, 3.86, 3.88, -0.03, 0.03, 'P', 0, '#B81E2A');
B(2.16, 2.18, 2.6, 3.8, -0.03, 0.03, 'P', 0, '#B81E2A');
S('Spaghetti');                                  // a messy heap of noodles on the tongue
for (const [x0, x1, y, z0, z1] of [[1.2, 1.9, 3.86, -0.36, -0.24], [1.3, 1.95, 3.86, 0.14, 0.26], [1.15, 1.75, 3.9, -0.1, 0.02], [1.4, 1.5, 3.86, -0.42, 0.4], [1.62, 1.72, 3.9, -0.3, 0.34], [1.25, 1.85, 3.94, 0.3, 0.4]])
	B(x0, x1, y, y + 0.08, z0, z1, 'P', 0, '#FFE066');
S('Meatball');
cb(1.42, 1.8, 3.92, 4.28, -0.2, 0.18, 0.05, 'P', 0, '#8A3A1A');
B(1.5, 1.72, 4.28, 4.34, -0.12, 0.1, 'P', 0, '#E0201E');
B(1.48, 1.74, 3.88, 3.94, -0.24, 0.22, 'P', 0, '#E0201E');

// --- dragon-fruit shell on the back: magenta, black seeds, green scales tipped in glowing lime
S('Shell');
cb(-1.45, -0.85, 2.55, 6.15, -1.15, 1.15, 0.12, 'feather', R);
S('Seeds');
for (const [y, z] of [[5.6, -0.6], [5.3, 0.3], [4.8, -0.2], [4.6, 0.7], [4.2, -0.75], [3.9, 0.15], [3.4, -0.4], [3.2, 0.6], [2.9, -0.05]])
	B(-1.47, -1.45, y, y + 0.1, z - 0.05, z + 0.05, 'P', 0, INK);
S('ShellScale');
for (const [y, z] of [[5.15, 0], [3.65, 0]]) {
	B(-1.75, -1.45, y, y + 0.42, z - 0.32, z + 0.32, 'feather2');
	B(-1.92, -1.75, y + 0.1, y + 0.32, z - 0.14, z + 0.14, 'accent', E);
}
for (const y of [5.5, 4.4, 3.2]) {
	MZ(-1.35, -0.95, y, y + 0.38, 1.15, 1.42, 'feather2');
	MZ(-1.25, -1.05, y + 0.1, y + 0.28, 1.42, 1.56, 'accent', E);
}

// --- gold bell on a little green roof (Esok Sekolah)
S('Bell');
B(0.38, 0.88, 6.68, 6.78, 0.48, 0.98, 'feather2');
cb(0.5, 0.76, 6.78, 7.08, 0.6, 0.86, 0.04, 'P', E, GOLD);
B(0.6, 0.66, 7.08, 7.18, 0.7, 0.76, 'P', 0, GOLD);

// --- Pot Hotspot: chunky wooden upper body rising from the lid, with a gold-framed phone for a head
S('PhoneTorso');
cb(-0.6, 0.15, 6.68, 7.5, -0.5, 0.5, 0.07, 'skin', R);
B(-0.55, 0.1, 6.68, 6.8, -0.52, 0.52, 'P', 0, DARK);              // collar where it rises from the lid
S('PhoneNeck');
B(-0.38, -0.06, 7.5, 7.66, -0.2, 0.2, 'skin2');
S('PhoneBezel');
cb(-0.44, -0.04, 7.62, 10.05, -0.95, 0.95, 0.08, 'stripe', 0);
S('PhoneScreen');
B(-0.04, -0.01, 7.78, 9.88, -0.8, 0.8, 'P', E, '#2EFFB0');
S('PhoneFace');
B(-0.01, 0.02, 7.98, 9.58, -0.56, 0.56, 'skin');
for (const s of [1, -1]) frontEye({ faceX: 0.02, zc: 0.27 * s, top: 9.3, L: 0.82, H: 0.82, out: s, iris: 'Lime', blush: false });
S('PhoneBrow');                                                 // worried brows, raised at the inner ends
MZ(0.02, 0.06, 9.4, 9.48, 0.1, 0.32, 'P', 0, '#3A1A0A');
MZ(0.02, 0.06, 9.34, 9.42, 0.32, 0.5, 'P', 0, '#3A1A0A');
S('PhoneMouth');
B(0.02, 0.05, 8.2, 8.62, -0.15, 0.15, 'P', 0, MAW);
B(0.02, 0.05, 8.26, 8.56, -0.21, 0.21, 'P', 0, MAW);
S('PhoneCamera');
B(-0.04, 0.0, 9.92, 9.98, -0.08, 0.08, 'P', 0, DARK);
B(-0.5, -0.44, 9.3, 9.85, 0.3, 0.8, 'P', 0, DARK);           // rear camera module
B(-0.53, -0.5, 9.6, 9.78, 0.38, 0.56, 'P', E, '#2EFFB0');
B(-0.53, -0.5, 9.38, 9.5, 0.6, 0.72, 'P', E, '#FFFFFF');
for (const s of [1, -1]) {   // little wooden arms, matching pair hanging in a neutral pose
	const z = 0.62 * s;
	S('PhoneArm');
	B(-0.4, -0.05, 7.2, 7.45, z - 0.14, z + 0.14, 'skin2');
	B(-0.36, -0.09, 6.82, 7.2, z - 0.12, z + 0.12, 'skin');
}

// --- arms and white gloves (Spaghetti Tualetti), matching mirrored pair; one fist grips the "9" sign
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	S('Arm');
	B(-0.18, 0.22, 4.18, 4.55, ...zz(1.3, 1.92), 'stripe', R);
	S('GloveCuff');
	B(-0.24, 0.28, 4.08, 4.65, ...zz(1.86, 1.98), 'P', E, GOLD);
	S('Glove');
	cb(-0.22, 0.32, 3.98, 4.72, ...zz(1.98, 2.36), 0.05, 'trim', 0);
	if (s > 0) {               // open waving hand: three fingers and a thumb
		for (const fz of [2.02, 2.15, 2.28]) B(-0.05, 0.15, 4.72, 5.08, ...zz(fz, fz + 0.1), 'trim');
		B(0.2, 0.42, 4.4, 4.58, ...zz(2.04, 2.2), 'trim');
	} else {                   // fist with knuckles wrapped round the sign stick
		B(0.28, 0.4, 4.1, 4.62, ...zz(2.0, 2.34), 'trim');
	}
}
S('SignStick');
B(0.0, 0.12, 3.5, 5.6, -2.22, -2.1, 'skin2');
S('Sign');
cb(-0.04, 0.16, 5.5, 6.75, -2.7, -1.62, 0.05, 'prop', 0);
S('SignBorder');
B(0.16, 0.19, 5.5, 5.58, -2.66, -1.66, 'P', E, GOLD);
B(0.16, 0.19, 6.67, 6.75, -2.66, -1.66, 'P', E, GOLD);
B(0.16, 0.19, 5.58, 6.67, -2.7, -2.62, 'P', E, GOLD);
B(0.16, 0.19, 5.58, 6.67, -1.7, -1.62, 'P', E, GOLD);
S('SignNine');
nine(0.16, 0.04, 5.72, -2.16, 0.17, 0.16, INK, 0);

// --- wooden legs (Pot Hotspot) into BRT_027's chunky light-up sneakers (no logos)
function shoe(x, z, len) { // x = heel, toe at +x
	S('Sneaker');
	B(x, x + len, 0, 0.22, z - 0.42, z + 0.42, 'accent', E);                 // light-up sole
	B(x, x + len, 0.22, 0.46, z - 0.42, z + 0.42, 'trim');                   // white midsole
	B(x + 0.05, x + len - 0.3, 0.46, 1.05, z - 0.38, z + 0.38, 'foot', R);   // upper
	B(x + len - 0.32, x + len, 0.46, 0.85, z - 0.36, z + 0.36, 'foot');      // toe cap
	B(x + len - 0.3, x + len + 0.02, 0.46, 0.6, z - 0.37, z + 0.37, 'trim'); // toe bumper
	for (const lx of [x + 0.45, x + 0.75, x + 1.05]) B(lx, lx + 0.2, 1.05, 1.14, z - 0.24, z + 0.24, 'trim'); // laces
	B(x + 0.05, x + len - 0.35, 0.62, 0.78, z + 0.38, z + 0.41, 'trim');      // side flash
	B(x + 0.05, x + len - 0.35, 0.62, 0.78, z - 0.41, z - 0.38, 'trim');
	B(x - 0.06, x + 0.22, 0.5, 1.15, z - 0.2, z + 0.2, 'accent', E);         // glowing heel tab
	B(x + 0.05, x + 0.7, 1.05, 1.25, z - 0.36, z + 0.36, 'P', 0, DARK);       // ankle collar
}
for (const s of [1, -1]) {
	const z = 0.52 * s;
	S('Leg');
	B(0.02, 0.56, 1.2, 1.9, z - 0.24, z + 0.24, 'skin', R);
	B(-0.02, 0.6, 1.78, 1.9, z - 0.27, z + 0.27, 'skin2');               // hip collar under the pedestal
	shoe(-0.3, z, 1.55);
}

// High-dopamine V4 palette (docs/creatures/V4/BRT_035_reference.md); no neon-pink glow, no blue.
const PALETTES = Object.assign(
	{
		normal: {
			upper: '#FFFFFF', lower: '#F3F1FF', stripe: '#FFC21A', trim: '#FFFFFF', skin: '#D98A45', skin2: '#7A4320',
			feather: '#E8307A', feather2: '#2FBF4A', foot: '#7A3CFF', prop: '#FF8A1A', accent: '#C8FF2E', mode: 0,
		},
	},
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (Secret flair): a gold-and-violet aura, prismatic sparkles, phone-signal sparkles above the phone
const passiveFx = [
	{ name: 'SecretAura', texture: 'smoke', anchor: [0, 4.4, 0], rate: 7, lifetime: [1.2, 1.8], size: [0.5, 1.3], transparency: [0.55, 1], colors: ['#FFC21A', '#9B5BFF'], lightEmission: 1, speed: [0.3, 0.6], spread: 180, rise: 0.8 },
	{ name: 'PrismSparkle', texture: 'sparkle', anchor: [0, 4.6, 0], rate: 7, lifetime: [0.8, 1.4], size: [0.24, 0.05], transparency: [0, 1], colors: ['#C8FF2E', '#FF8A1A'], lightEmission: 1, speed: [0.4, 0.9], spread: 180, rise: 0.2 },
	{ name: 'PhoneSignal', texture: 'sparkle', anchor: [-0.24, 10.15, 0], rate: 5, lifetime: [0.6, 1.1], size: [0.2, 0.05], transparency: [0, 1], colors: ['#2EFFB0', '#FFFFFF'], lightEmission: 1, speed: [0.6, 1.0], spread: 25, rise: 0.6 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: {
		SignStick: 'LeftArm', Sign: 'LeftArm', SignBorder: 'LeftArm', SignNine: 'LeftArm',
		PhoneTorso: 'PhoneBody', PhoneArm: 'PhoneBody',
		PhoneNeck: 'PhoneHead', PhoneBezel: 'PhoneHead', PhoneScreen: 'PhoneHead', PhoneFace: 'PhoneHead', PhoneBrow: 'PhoneHead', PhoneMouth: 'PhoneHead', PhoneCamera: 'PhoneHead',
	},
	extraBones: { PhoneBody: { parent: 'Torso', pivot: [-0.22, 6.68, 0] }, PhoneHead: { parent: 'PhoneBody', pivot: [-0.22, 7.62, 0] } },
	regions: [{ bone: 'PhoneHead', region: [-0.6, 0.3, 7.7, 10.2, -1.0, 1.0] }],
};
