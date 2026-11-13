// BRT_028 Tartaragno — Voxel V4 build (CP-C, Epic, revision 5).
// References (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki) and the yumcut.com
// render ("a turtle-spider hybrid from Steal a Brainrot's October 11, 2025 Witch Fuse event ... with a shell,
// six spider-like legs, and fangs"):
// - a BIG, tall domed turtle shell sitting low, with a sturdy turtle head and big fangs in front
// - six thin spider legs arching up from under the shell rim and spreading wide down to the ground
// Revision 2 (owner): "as before, use online references and super dopamine v4" (all areas). Revision 1's
// small shell on tall vertical stick legs is replaced by the references' proportions:
// - a big emerald dome with bold lime scutes and dark grooves, a glowing gold rim and the cyan V4 waterline
//   over a cream plastron
// - a bigger, rounder mint turtle head jutting forward, big BRT_027-construction side anime eyes, four
//   glowing spider eyes, a closed smirk and two big curved ivory fangs
// - six thin arched electric-purple spider legs with glowing violet knee joints, each ending in a tiny
//   neon-orange V4 sneaker with a light-up sole (the gag)
// - witchy aura (Witch Fuse event): glowing violet and lime sparkles
// Revision 5 (owner): "go back to online sources and use our distinct style as before to make it more dopamine
//   and more desirable to catch". Back to the reference-faithful revision 2 design (the villain and
//   mad-scientist revisions 3 and 4 are dropped), pushed further: a vivid green shell with candy scutes in
//   lime and hot pink, a glowing magenta crystal gem crowning the shell in a gold mount, brighter purple legs,
//   and the witchy sparkles turned into passive particle FX (lime and violet glitter, gem twinkle).
// Rig-ready (owner rule): the six legs are three matching pairs with hip and knee collars; sneakers point
// straight ahead on flat soles.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const IVORY = '#FFF6DE';

function layer(y0, y1, rx, rz, role, rel = R) {
	B(-rx, rx, y0, y1, -0.7 * rz, 0.7 * rz, role, rel);
	B(-0.66 * rx, 0.66 * rx, y0, y1, -rz, rz, role, rel);
}

// --- big, tall emerald dome shell sitting low (the rim's long box is the Body)
S('Body');
B(-1.2, 1.2, 0.86, 1.22, -0.73, 0.73, 'upper', R);
S('Shell');
B(-0.79, 0.79, 0.86, 1.22, -1.04, 1.04, 'upper', R);
layer(1.22, 1.58, 1.1, 0.95, 'upper');
layer(1.58, 1.9, 0.92, 0.8, 'upper');
layer(1.9, 2.14, 0.68, 0.58, 'upper');
layer(2.14, 2.3, 0.38, 0.32, 'upper');
S('Plastron');
layer(0.56, 0.84, 0.98, 0.84, 'lower');
S('Waterline');
layer(0.82, 0.88, 1.24, 1.08, 'stripe', E);
S('GoldRim');                                                   // glowing gold shell rim
B(-1.24, 1.24, 1.2, 1.26, -0.756, 0.756, 'P', E, '#FFC21A');
B(-0.82, 0.82, 1.2, 1.26, -1.08, 1.08, 'P', E, '#FFC21A');
// bold lime scutes with dark grooves all over the dome
S('Scute');
B(-0.26, 0.26, 2.3, 2.35, -0.22, 0.22, 'feather', 0);
[[0.9, 0], [-0.9, 0], [0.66, 0.5], [0.66, -0.5], [-0.66, 0.5], [-0.66, -0.5]].forEach(([x, z], i) => {
	const nx = Math.abs(x) > 0.8, sx = Math.sign(x), role = i % 2 ? 'feather2' : 'feather';
	if (nx) B(sx > 0 ? 1.1 : -1.15, sx > 0 ? 1.15 : -1.1, 1.3, 1.52, z - 0.26, z + 0.26, role, 0);
	else B(x - 0.22, x + 0.22, 1.3, 1.52, z > 0 ? 0.95 : -1.0, z > 0 ? 1.0 : -0.95, role, 0);
});
for (const s of [1, -1]) {
	const z = s > 0 ? [0.8, 0.85] : [-0.85, -0.8];
	B(-0.62, -0.22, 1.64, 1.84, ...z, 'feather2', 0);
	B(0.22, 0.62, 1.64, 1.84, ...z, 'feather', 0);
	const z2 = s > 0 ? [0.58, 0.63] : [-0.63, -0.58];
	B(-0.24, 0.24, 1.94, 2.1, ...z2, 'feather', 0);
}
for (const z of [-0.3, 0.3]) {
	B(0.92, 0.97, 1.64, 1.84, z - 0.18, z + 0.18, 'feather', 0);
	B(-0.97, -0.92, 1.64, 1.84, z - 0.18, z + 0.18, 'feather', 0);
}

// --- collectible bling: a glowing magenta crystal gem crowning the shell, set in a gold mount
S('GemMount');
B(-0.22, 0.22, 2.35, 2.43, -0.22, 0.22, 'P', 0, '#FFC21A');
S('CrystalGem');
B(-0.16, 0.16, 2.43, 2.75, -0.16, 0.16, 'P', E, '#FF2DD1');
B(-0.1, 0.1, 2.75, 2.9, -0.1, 0.1, 'P', E, '#FF8AE6');
B(-0.05, 0.05, 2.9, 2.98, -0.05, 0.05, 'P', E, '#FFFFFF');

// --- bigger, rounder mint turtle head jutting forward: closed smirk, big curved fangs, spider eyes
S('Head');
B(1.0, 1.86, 0.62, 1.42, -0.5, 0.5, 'skin', R);
B(1.08, 1.78, 1.42, 1.54, -0.38, 0.38, 'skin', R);
S('Muzzle');
B(1.84, 2.1, 0.66, 1.12, -0.4, 0.4, 'skin2', R);
S('Mouth');
B(2.1, 2.12, 0.84, 0.9, -0.3, 0.3, 'P', 0, INK);
MZ(2.08, 2.12, 0.9, 0.98, 0.28, 0.36, 'P', 0, INK);
S('Fang');                                                      // two big curved ivory fangs
MZ(2.0, 2.14, 0.46, 0.86, 0.12, 0.24, 'P', 0, IVORY);
MZ(1.96, 2.08, 0.34, 0.48, 0.13, 0.21, 'P', 0, IVORY);
S('SpiderEye');                                                 // four small glowing secondary eyes
for (const [x, z] of [[1.36, -0.14], [1.36, 0.14], [1.62, -0.22], [1.62, 0.22]]) B(x - 0.06, x + 0.06, 1.54, 1.6, z - 0.06, z + 0.06, 'P', E, '#FF2D55');
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 0.5, k = 0.42, X = 1.08, Y = 0.78;
	const y = (v) => Y + (v - 4.2) * k, x = (v) => X + v * k;
	const [w0, w1] = zz(zf, zf + 0.03), [i0, i1] = zz(zf + 0.03, zf + 0.05), [p0, p1] = zz(zf + 0.05, zf + 0.07), [c0, c1] = zz(zf + 0.07, zf + 0.09);
	S('EyeWhite');
	B(x(0.12), x(1.27), y(4.2), y(5.85), w0, w1, 'P', 0, '#FFFFFF');
	B(x(0), x(1.39), y(4.35), y(5.7), w0, w1, 'P', 0, '#FFFFFF');
	S('Iris');
	B(x(0.22), x(1.17), y(5.1), y(5.65), i0, i1, 'P', 0, '#7A0A4A');
	B(x(0.22), x(1.17), y(4.65), y(5.1), i0, i1, 'P', 0, '#FF2D95');
	B(x(0.22), x(1.17), y(4.27), y(4.65), i0, i1, 'P', 0, '#FFB0D8');
	S('Pupil');
	B(x(0.47), x(0.94), y(4.7), y(5.35), p0, p1, 'P', 0, '#1A0B10');
	S('Catchlight');
	B(x(0.32), x(0.68), y(5.13), y(5.51), c0, c1, 'P', E, '#FFFFFF');
	B(x(0.88), x(1.06), y(4.45), y(4.63), c0, c1, 'P', E, '#FFFFFF');
	S('Lash');
	const [l0, l1] = zz(zf, zf + 0.08);
	B(x(-0.06), x(1.47), y(5.77), y(5.93), l0, l1, 'P', 0, '#000000');
	B(x(-0.28), x(0.02), y(5.9), y(6.1), l0, l1, 'P', 0, '#000000');
	S('Blush');
	B(x(0.05), x(0.75), y(3.8), y(4.05), w0, w1, 'P', E, '#FF6FA3');
}
S('Tail');
B(-1.5, -1.12, 0.66, 0.88, -0.12, 0.12, 'skin', R);
B(-1.68, -1.46, 0.7, 0.82, -0.06, 0.06, 'skin');

// --- six thin arched electric-purple spider legs (three matching pairs): up and out from under the rim
// to a glowing violet knee, then spreading wide down to a tiny neon-orange light-up sneaker
for (const lx of [0.66, 0, -0.66]) {
	for (const s of [1, -1]) {
		const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
		S('HipCollar');
		B(lx - 0.09, lx + 0.09, 0.8, 0.96, ...z(0.98, 1.06), 'P', 0, DARK);
		S('UpperLeg');
		B(lx - 0.07, lx + 0.07, 0.86, 1.12, ...z(1.04, 1.24), 'prop', R);
		B(lx - 0.07, lx + 0.07, 1.04, 1.32, ...z(1.18, 1.38), 'prop', R);
		S('KneeJoint');                                         // glowing violet knee
		B(lx - 0.09, lx + 0.09, 1.26, 1.4, ...z(1.32, 1.46), 'accent', E);
		S('LowerLeg');                                          // spreading wide and down to the ground
		B(lx - 0.06, lx + 0.06, 0.8, 1.32, ...z(1.42, 1.58), 'prop', R);
		B(lx - 0.06, lx + 0.06, 0.3, 0.86, ...z(1.54, 1.7), 'prop', R);
		S('Sneaker');
		B(lx - 0.13, lx + 0.27, 0.06, 0.32, ...z(1.48, 1.78), 'foot', R);
		S('SneakerStripe');
		B(lx - 0.05, lx + 0.18, 0.13, 0.2, ...z(1.78, 1.8), 'trim');
		S('Sole');
		B(lx - 0.13, lx + 0.27, 0, 0.06, ...z(1.48, 1.78), 'stripe', E);
	}
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_028_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#14DA62', feather: '#C6FF3A', feather2: '#FF3DB4', lower: '#FFF0A8', stripe: '#2EE9FF', prop: '#7A3BFF', skin: '#5BF08E', skin2: '#D4FFBE', foot: '#FF7A0A', trim: '#FFFFFF', accent: '#D04DFF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// --- passive FX (collectible flair): witchy lime and violet glitter drifting up around the shell, and a
// soft sparkle twinkling off the crystal gem; small, cheap, engine-bundled sprites
const passiveFx = [
	{ name: 'WitchGlitter', texture: 'sparkle', anchor: [0, 1.4, 0], rate: 6, lifetime: [1.2, 2.0], size: [0.16, 0.04], transparency: [0, 1], colors: ['#C6FF3A', '#D04DFF'], lightEmission: 1, speed: [0.3, 0.7], spread: 70, rise: 0.3 },
	{ name: 'GemTwinkle', texture: 'sparkle', anchor: [0, 2.9, 0], rate: 3, lifetime: [0.6, 1.0], size: [0.22, 0.06], transparency: [0, 1], colors: ['#FFFFFF', '#FF2DD1'], lightEmission: 1, speed: [0.1, 0.3], spread: 180, rise: 0 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { Scute: 'Torso', Fang: 'Head' },
	// animation pass (13 Nov 2026): the head turns (and pulls back) from inside the front of the shell
	headPivot: [1.1, 1.0, 0],
};
