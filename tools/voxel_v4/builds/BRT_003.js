// BRT_003 Cappuccino Capybara — Voxel V4 build (CP-B, revision 2).
// Identity: the chillest animal in the world on its tenth cappuccino. A stocky barrel
// capybara wearing an overflowing cappuccino cup on its head (the "capybara with a yuzu on
// its head" meme pose), huge sparkling anime eyes, a cream foam moustache and two big
// buck teeth in a wide caffeinated grin. Core V4 rules from the approved BRT_019/BRT_027
// builds: big side anime eyes (white, 3-band iris, pupil, three catchlights, lash with wing
// flick, blush), two-tone countershading with a glowing waterline, light-up soles, studs on
// the body panels, dark joint collars. Dopamine high-contrast palette. Design units, y up, nose = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const MOUTH = '#6E0E2C';
const COFFEE = '#4A2412';

// --- two-tone barrel body with a glowing waterline: [x0, x1, yBottom, yTop, halfWidth, slot]
const WL = 0.4;
for (const [x0, x1, yb, yt, hw, slot] of [
	[-2.75, -2.35, 1.3, 2.4, 0.7, 'Rump'],
	[-2.35, 1.3, 0.9, 2.95, 1.1, 'Body'],                    // one long barrel: the largest upper box is the Body
]) {
	const yw = yb + WL * (yt - yb);
	S(slot);
	B(x0, x1, yw + 0.14, yt, -hw, hw, 'upper', R);        // first box of 'Body' is the largest upper box
	S(slot + 'Belly');
	B(x0, x1, yb, yw, -hw, hw, 'lower', R);
	S('Waterline');
	B(x0, x1, yw, yw + 0.14, -hw - 0.02, hw + 0.02, 'stripe', E);
}

// --- big boxy capybara head + long blunt snout, same two-tone with the waterline at y 2.25
const HW = 1.85;
for (const [x0, x1, yb, yt, hw, slot] of [
	[1.2, 3.2, 1.2, 3.9, 1.1, 'Head'],
	[3.2, 4.1, 1.2, 3.45, 0.95, 'Snout'],
	[4.1, 4.45, 1.32, 3.15, 0.78, 'SnoutTip'],
]) {
	S(slot);
	B(x0, x1, HW + 0.14, yt, -hw, hw, 'upper', slot === 'Head' ? 0 : R);   // eye panel stays smooth
	S(slot + 'Jaw');
	B(x0, x1, yb, HW, -hw, hw, 'lower', R);
	S('Waterline');
	B(x0, x1, HW, HW + 0.14, -hw - 0.02, hw + 0.02, 'stripe', E);
}
S('BodyRound');
B(-2.1, 1.05, 2.95, 3.08, -0.86, 0.86, 'upper', R);    // rounds the barrel's back
S('Crown');
B(1.35, 3.05, 3.9, 4.0, -0.9, 0.9, 'upper', R);

// --- huge side anime eyes (approved BRT_027 proportions), bright blue irises, blush
const IRIS = ['#1446C8', '#2E9BFF', '#8FF0FF'];      // bright Ocean family, lifted for sparkle
function sideEye(X, yb, zf, s) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const w = zz(zf, zf + 0.04), ir = zz(zf + 0.04, zf + 0.07), p = zz(zf + 0.07, zf + 0.1), c = zz(zf + 0.1, zf + 0.12), l = zz(zf, zf + 0.14);
	S('EyeWhite');
	B(X + 0.12, X + 1.27, yb, yb + 1.65, ...w, 'P', 0, '#ffffff');
	B(X, X + 1.39, yb + 0.15, yb + 1.5, ...w, 'P', 0, '#ffffff');
	S('Iris');
	B(X + 0.22, X + 1.17, yb + 0.9, yb + 1.45, ...ir, 'P', 0, IRIS[0]);
	B(X + 0.22, X + 1.17, yb + 0.45, yb + 0.9, ...ir, 'P', 0, IRIS[1]);
	B(X + 0.22, X + 1.17, yb + 0.07, yb + 0.45, ...ir, 'P', 0, IRIS[2]);
	S('Pupil');
	B(X + 0.47, X + 0.94, yb + 0.5, yb + 1.15, ...p, 'P', 0, '#1a0b06');
	S('Catchlight');
	B(X + 0.32, X + 0.68, yb + 0.93, yb + 1.31, ...c, 'P', E, '#ffffff');
	B(X + 0.88, X + 1.06, yb + 0.25, yb + 0.43, ...c, 'P', E, '#ffffff');
	B(X + 1.0, X + 1.08, yb + 1.01, yb + 1.09, ...c, 'P', E, '#ffffff');
	S('Lash');
	B(X - 0.06, X + 1.47, yb + 1.57, yb + 1.81, ...l, 'P', 0, '#000000');
	B(X - 0.28, X + 0.02, yb + 1.7, yb + 2.0, ...l, 'P', 0, '#000000');      // wing flick
	B(X + 1.32, X + 1.52, yb + 1.45, yb + 1.63, ...l, 'P', 0, '#000000');
	S('Blush');
	B(X + 0.05, X + 0.75, yb - 0.4, yb - 0.15, ...w, 'P', E, '#ff6fa3');
}
for (const s of [1, -1]) sideEye(1.62, 2.02, 1.1, s);

// --- small round ears on the back of the head, hot-pink inner ear
for (const s of [1, -1]) {
	S('Ear');
	B(1.3, 1.72, 3.85, 4.33, 0.62 * s, 1.06 * s, 'upper', R);
	S('InnerEar');
	B(1.72, 1.76, 3.93, 4.25, 0.7 * s, 0.98 * s, 'skin2');
}

// --- face front: big flat nose, foam moustache, wide grin with two huge buck teeth and a tongue
S('Nostril');
MZ(4.45, 4.49, 2.43, 2.6, 0.1, 0.32, 'P', 0, DARK);
S('FoamMoustache');
B(4.45, 4.62, 1.9, 2.18, -0.66, 0.66, 'lower', R);
MZ(4.4, 4.6, 2.08, 2.4, 0.6, 0.86, 'lower');                          // curled-up ends
MZ(4.3, 4.55, 2.32, 2.5, 0.8, 0.98, 'lower');
S('CocoaDust');
for (const z of [-0.4, 0, 0.4]) B(4.62, 4.64, 2.06, 2.12, z - 0.06, z + 0.06, 'trim');
S('Mouth');
B(4.45, 4.48, 1.2, 1.7, -0.6, 0.6, 'P', 0, MOUTH);
for (const [x0, x1, hw] of [[3.3, 4.1, 0.95], [4.1, 4.45, 0.78]]) MZ(x0, x1, 1.36, 1.64, hw, hw + 0.03, 'P', 0, MOUTH);
MZ(3.05, 3.3, 1.53, 1.8, 1.1, 1.13, 'P', 0, MOUTH);                 // grin corners turn up toward the cheeks
S('Tongue');
B(4.43, 4.5, 1.2, 1.38, -0.4, 0.05, 'P', 0, '#FF4F7A');
S('BuckTooth');
B(4.47, 4.56, 1.1, 1.68, -0.24, -0.02, 'P', 0, '#FFFFFF');
B(4.47, 4.56, 1.1, 1.68, 0.02, 0.24, 'P', 0, '#FFFFFF');

// --- four short legs, dark hip collars, electric-blue feet on light-up soles, cream claws
for (const x of [1.05, -1.75]) for (const s of [1, -1]) {
	const zc = 0.66 * s;
	S('HipCollar');
	B(x - 0.34, x + 0.34, 0.9, 1.04, zc - 0.32, zc + 0.32, 'P', 0, DARK);
	S('Leg');
	B(x - 0.27, x + 0.27, 0.42, 0.95, zc - 0.26, zc + 0.26, 'upper', R);
	S('Foot');
	B(x - 0.38, x + 0.48, 0.12, 0.46, zc - 0.34, zc + 0.34, 'foot', R);
	S('Sole');
	B(x - 0.4, x + 0.5, 0, 0.12, zc - 0.36, zc + 0.36, 'accent', E);
	S('Claw');
	for (const dz of [-0.2, 0, 0.2]) B(x + 0.48, x + 0.56, 0.16, 0.3, zc + dz - 0.06, zc + dz + 0.06, 'lower');
}

// --- the cappuccino cup worn on the head, overflowing foam, glowing latte heart, open handle
S('Saucer');
B(1.45, 3.15, 4.0, 4.12, -0.92, 0.92, 'lower', R);
S('Cup');
B(1.8, 2.8, 4.12, 4.37, -0.46, 0.46, 'prop', R);
B(1.7, 2.9, 4.37, 4.73, -0.56, 0.56, 'prop', R);
B(1.6, 3.0, 4.73, 5.05, -0.66, 0.66, 'prop', R);
S('CupBand');
B(1.66, 2.94, 4.61, 4.73, -0.6, 0.6, 'skin2');
S('Rim');
B(1.55, 3.05, 5.05, 5.15, -0.7, 0.7, 'lower');
S('Coffee');
B(1.7, 2.9, 5.15, 5.18, -0.56, 0.56, 'P', 0, COFFEE);
S('Foam');                                                           // a foam dome spilling over the rim
B(1.72, 2.88, 5.15, 5.35, -0.54, 0.54, 'lower', R);
B(1.9, 2.7, 5.35, 5.47, -0.36, 0.36, 'lower', R);
S('FoamDrip');
for (const [x, s, y0] of [[1.95, -1, 4.57], [2.55, -1, 4.75], [2.3, 1, 4.63], [3.02, 0, 4.67]]) {
	if (s === 0) B(3.0, 3.06, y0, 5.15, -0.12, 0.12, 'lower');
	else B(x - 0.11, x + 0.11, y0, 5.15, 0.66 * s, 0.72 * s, 'lower');
}
S('LatteHeart');
MZ(2.45, 2.7, 5.47, 5.5, 0.03, 0.24, 'accent', E);
B(2.2, 2.55, 5.47, 5.5, -0.18, 0.18, 'accent', E);
B(2.06, 2.2, 5.47, 5.5, -0.07, 0.07, 'accent', E);
S('Handle');                                                         // on the camera (-z) side
B(2.1, 2.4, 4.83, 4.97, -1.06, -0.62, 'prop', R);
B(2.1, 2.4, 4.41, 4.55, -0.98, -0.52, 'prop', R);
B(2.1, 2.4, 4.41, 4.97, -1.18, -1.04, 'prop', R);
S('Steam');
for (const [x, z, h] of [[2.0, 0.22, 0], [2.6, -0.2, 0.14]]) {
	B(x - 0.07, x + 0.07, 5.57 + h, 5.83 + h, z - 0.07, z + 0.07, 'lower');
	B(x - 0.07, x + 0.07, 5.79 + h, 6.05 + h, z + 0.05, z + 0.19, 'lower');
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_003_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF7A1A', lower: '#FFF3D6', stripe: '#2EF2FF', trim: '#3A1A0E', skin2: '#FF2D95', foot: '#3A2BFF', prop: '#00D9C8', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Rig (animation brief v5, 13 Nov 2026): quadruped plus the signature prop. The cappuccino (saucer, cup, foam,
// handle and its steam) sits on its own Cup bone on the head, so it can wobble and be balanced.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	neckY: 1.2,
	extraBones: { Cup: { parent: 'Head', pivot: [2.3, 4.0, 0] } },
	slots: { Saucer: 'Cup', Cup: 'Cup', CupBand: 'Cup', Rim: 'Cup', Coffee: 'Cup', Foam: 'Cup', FoamDrip: 'Cup', LatteHeart: 'Cup', Handle: 'Cup', Steam: 'Cup' },
};
