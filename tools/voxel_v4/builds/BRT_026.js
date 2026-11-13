// BRT_026 Rhino Toasterino — Voxel V4 build (CP-C, Epic, revision 3).
// References, which agree (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki,
// "standing upright, it has the body of a toaster with two slices of toasted bread popping out") and the
// yumcut.com render ("a smiling rhino fused with a toaster"):
// - an upright chrome toaster body with dials and a lever
// - a grey rhino head on the front with a big curved ivory horn, a smile and blue eyes
// - little rhino arms, short legs, two slices of toast popping out of the top
// The V4 take (super dopamine, BRT_027 hallmarks):
// - a chrome toaster with a dark base split by a glowing cyan waterline, candy-coloured knobs, a red lever
//   knob and slots glowing hot orange inside; two golden toast slices popping up, one with a butter pat,
//   with glowing steam puffs
// - a lavender-grey rhino head with a big curved ivory horn, a small second horn, cupped pink-lined ears,
//   big BRT_027-construction side anime eyes (blue iris) with blush and a closed smile
// - the gag: a curling black power-cord tail with a plug and gold prongs, and hot-pink light-up sneakers
// Revision 2 (owner): "as before, use online references and super dopamine v4": an electric-turquoise retro
//   candy toaster with chrome trim bands and a hot-pink glowing waterline, a periwinkle-violet rhino, a bigger
//   glossy horn with a gold tip, glowing candy dials, taller golden toast, and the gag of one slice popping
//   clean out mid-air with a glowing crumb burst.
// Revision 3 (owner): "more dopamine, more v4": the BRT_027 hallmarks: a turquoise top over a white belly
//   wrapping round the toaster, split by the glowing cyan V4 waterline (the fussy chrome bands are gone, a
//   chrome rim stays); a chunkier, more saturated violet rhino head with bigger side eyes; a wide open V4
//   grin with a pink tongue and no teeth.
// Rig-ready (owner rule): arms and legs are matching pairs with joint collars; sneakers point straight ahead.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const BONE = '#F4E8CC';
const GOLD = '#FFC21A';
const HEAT = '#FF7A1A';
const CHROME = '#EEF3FA';

// --- revision 3: V4 countershaded toaster: turquoise top (the Body) over a white belly wrapping round the
// bottom, split by the glowing cyan V4 waterline; a dark base; a chrome rim around the top
S('Body');
B(-0.76, 0.76, 2.06, 2.96, -0.96, 0.96, 'upper', R);
S('Toaster');
B(-0.68, 0.68, 2.06, 3.02, -0.88, 0.88, 'upper', R);
S('ToasterBelly');
B(-0.76, 0.76, 1.26, 2.06, -0.96, 0.96, 'lower', R);
S('Waterline');
B(-0.79, 0.79, 2.02, 2.1, -0.99, 0.99, 'stripe', E);
S('ChromeRim');
B(-0.78, 0.78, 2.9, 2.98, -0.98, 0.98, 'P', 0, CHROME);
S('ToasterBase');
B(-0.8, 0.8, 0.98, 1.26, -1.0, 1.0, 'feather', R);
// two slots on top glowing hot orange inside, two golden toast slices popping up, butter and steam
for (const [zs, lift] of [[-0.42, 0], [0.42, 0.95]]) {
	S('Slot');
	B(-0.54, 0.54, 2.96, 3.04, zs - 0.18, zs + 0.18, 'P', 0, INK);
	B(-0.5, 0.5, 2.98, 3.05, zs - 0.14, zs + 0.14, 'P', E, HEAT);
	S('Toast');                                                 // the +z slice has popped clean out mid-air
	B(-0.46, 0.46, 3.0 + lift, 3.82 + lift, zs - 0.1, zs + 0.1, 'prop', R);
	B(-0.38, 0.38, 3.82 + lift, 3.92 + lift, zs - 0.1, zs + 0.1, 'prop', R);
	S('Crust');                                                 // crust rim around the golden face
	B(-0.48, 0.48, 3.78 + lift, 3.94 + lift, zs - 0.11, zs + 0.11, 'trim', 0);
	B(-0.48, -0.4, 3.0 + lift, 3.84 + lift, zs - 0.11, zs + 0.11, 'trim', 0);
	B(0.4, 0.48, 3.0 + lift, 3.84 + lift, zs - 0.11, zs + 0.11, 'trim', 0);
}
S('Butter');
B(-0.16, 0.16, 3.92, 4.0, -0.54, -0.3, 'P', 0, '#FFE88A');
S('CrumbBurst');                                                // glowing crumbs where the toast shot out
for (const [x, y, z] of [[0.3, 3.3, 0.42], [-0.3, 3.45, 0.55], [0.0, 3.6, 0.3], [0.45, 3.7, 0.6]]) B(x - 0.05, x + 0.05, y - 0.05, y + 0.05, z - 0.05, z + 0.05, 'P', E, '#FFD27A');
S('Steam');
B(-0.1, 0.06, 4.08, 4.22, -0.48, -0.36, 'P', E, '#FFFFFF');
B(0.02, 0.14, 4.28, 4.38, -0.4, -0.3, 'P', E, '#FFFFFF');
// candy-coloured dials on the lower front, lever on the side
S('Dial');
for (const [z, col] of [[-0.5, '#FF2D95'], [0, '#2EF2FF'], [0.5, '#7DFF2E']]) {
	B(0.76, 0.84, 1.42, 1.62, z - 0.1, z + 0.1, 'P', E, col);
	B(0.84, 0.88, 1.5, 1.54, z - 0.03, z + 0.03, 'P', 0, INK);
}
S('Lever');
B(-0.3, 0.3, 1.5, 2.7, 0.96, 0.99, 'P', 0, INK);
B(-0.12, 0.12, 2.3, 2.46, 0.99, 1.14, 'P', 0, '#FF2D2D');
// side heating vents glowing hot orange
S('Vent');
for (const y of [1.6, 1.85, 2.1]) B(-0.5, -0.1, y - 0.04, y + 0.04, -0.99, -0.96, 'P', E, HEAT);

// --- lavender-grey rhino head on the front: big curved ivory horn, second horn, cupped ears, smile
S('Head');
B(0.5, 1.56, 2.14, 3.3, -0.64, 0.64, 'skin', R);
S('Snout');
B(1.56, 2.06, 2.14, 2.8, -0.52, 0.52, 'skin', R);
S('Horn');                                                      // big curved horn sweeping up and back
B(1.76, 2.18, 2.8, 3.2, -0.17, 0.17, 'P', 0, BONE);
B(1.84, 2.14, 3.2, 3.62, -0.14, 0.14, 'P', 0, BONE);
B(1.74, 2.04, 3.62, 3.98, -0.11, 0.11, 'P', 0, BONE);
B(1.6, 1.88, 3.98, 4.22, -0.08, 0.08, 'P', 0, GOLD);               // gold tip
B(1.36, 1.6, 3.3, 3.52, -0.08, 0.08, 'P', 0, BONE);           // small second horn
S('Nostril');
MZ(2.06, 2.08, 2.58, 2.68, 0.14, 0.28, 'P', 0, INK);
S('Mouth');                                                     // wide open V4 grin with a tongue (no teeth)
B(2.06, 2.08, 2.24, 2.42, -0.38, 0.38, 'P', 0, '#6E0E2C');
MZ(2.04, 2.08, 2.42, 2.52, 0.36, 0.44, 'P', 0, '#6E0E2C');
B(2.06, 2.09, 2.24, 2.31, -0.2, 0.2, 'P', 0, '#FF4F7A');
for (const s of [1, -1]) {
	S('Ear');
	B(0.62, 0.9, 3.28, 3.6, 0.36 * s, 0.62 * s, 'skin', R);
	S('InnerEar');
	B(0.9, 0.92, 3.32, 3.54, 0.4 * s, 0.58 * s, 'skin2');
}
// big side anime eyes (BRT_027 construction, scaled), blue iris, lash bar, blush
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 0.64, k = 0.5, X = 0.66, Y = 2.44;
	const y = (v) => Y + (v - 4.2) * k, x = (v) => X + v * k;
	const [w0, w1] = zz(zf, zf + 0.03), [i0, i1] = zz(zf + 0.03, zf + 0.05), [p0, p1] = zz(zf + 0.05, zf + 0.07), [c0, c1] = zz(zf + 0.07, zf + 0.09);
	S('EyeWhite');
	B(x(0.12), x(1.27), y(4.2), y(5.85), w0, w1, 'P', 0, '#FFFFFF');
	B(x(0), x(1.39), y(4.35), y(5.7), w0, w1, 'P', 0, '#FFFFFF');
	S('Iris');
	B(x(0.22), x(1.17), y(5.1), y(5.65), i0, i1, 'P', 0, '#0A3A7A');
	B(x(0.22), x(1.17), y(4.65), y(5.1), i0, i1, 'P', 0, '#2E8BFF');
	B(x(0.22), x(1.17), y(4.27), y(4.65), i0, i1, 'P', 0, '#9FE0FF');
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

// --- little rhino arms (matching pair) hanging at the toaster sides
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('ShoulderCollar');
	B(-0.16, 0.16, 2.24, 2.4, ...z(0.96, 1.02), 'P', 0, DARK);
	S('UpperArm');
	B(-0.15, 0.15, 1.82, 2.36, ...z(1.0, 1.26), 'skin', R);
	S('ElbowCollar');
	B(-0.16, 0.16, 1.76, 1.84, ...z(0.99, 1.27), 'P', 0, DARK);
	S('Forearm');
	B(-0.14, 0.14, 1.42, 1.78, ...z(1.0, 1.24), 'skin', R);
	S('Hand');
	B(-0.17, 0.19, 1.2, 1.44, ...z(0.98, 1.26), 'skin', R);
}

// --- the gag: a curling power-cord tail with a plug and gold prongs
S('PowerCord');
B(-1.12, -0.76, 1.5, 1.6, -0.05, 0.05, 'feather', 0);
B(-1.22, -1.1, 1.0, 1.6, -0.05, 0.05, 'feather', 0);
B(-1.22, -0.98, 0.96, 1.06, -0.05, 0.05, 'feather', 0);
S('Plug');
B(-1.0, -0.76, 0.86, 1.14, -0.13, 0.13, 'P', 0, '#2A2A33');
B(-0.76, -0.64, 0.92, 0.96, -0.08, -0.04, 'P', 0, GOLD);
B(-0.76, -0.64, 1.04, 1.08, 0.04, 0.08, 'P', 0, GOLD);

// --- short rhino legs (matching pair) in chunky hot-pink V4 sneakers with light-up soles
for (const s of [1, -1]) {
	const zc = 0.46 * s;
	S('HipCollar');
	B(-0.22, 0.22, 0.92, 0.99, zc - 0.22, zc + 0.22, 'P', 0, DARK);
	S('Thigh');
	B(-0.2, 0.2, 0.62, 0.94, zc - 0.2, zc + 0.2, 'skin', R);
	S('KneeCollar');
	B(-0.19, 0.19, 0.56, 0.63, zc - 0.19, zc + 0.19, 'P', 0, DARK);
	S('Sneaker');
	B(-0.3, 0.5, 0.08, 0.58, zc - 0.26, zc + 0.26, 'foot', R);
	B(0.5, 0.76, 0.08, 0.34, zc - 0.23, zc + 0.23, 'foot', R);
	S('SneakerStripe');
	B(-0.14, 0.36, 0.2, 0.3, s > 0 ? zc + 0.26 : zc - 0.28, s > 0 ? zc + 0.28 : zc - 0.26, 'lower');
	S('SneakerToe');
	B(0.74, 0.78, 0.08, 0.24, zc - 0.21, zc + 0.21, 'lower');
	S('Midsole');
	B(-0.31, 0.78, 0.04, 0.1, zc - 0.27, zc + 0.27, 'lower');
	S('Sole');
	B(-0.31, 0.78, 0, 0.04, zc - 0.27, zc + 0.27, 'accent', E);
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_026_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#14D8C8', feather: '#2A2440', stripe: '#2EE9FF', skin: '#8A5CFF', lower: '#F7F5FC', skin2: '#FF7FB8', prop: '#FFC24A', trim: '#B8561A', foot: '#FF2D95', accent: '#2EE9FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	// animation pass (13 Nov 2026): each toast slice, the lever knob and the power-cord tail get a joint;
	// the butter and steam ride on the slice in the slot; the head turns where it meets the toaster
	slots: {
		Toast: '{side}Toast', Crust: '{side}Toast', Butter: 'LeftToast', Steam: 'LeftToast',
		CrumbBurst: 'Torso', PowerCord: 'Tail', Plug: 'Tail',
	},
	headPivot: [0.76, 2.72, 0],
	extraBones: {
		LeftToast: { parent: 'Torso', pivot: [0, 3.0, -0.42] },
		RightToast: { parent: 'Torso', pivot: [0, 4.41, 0.42] },
		LeverKnob: { parent: 'Torso', pivot: [0, 2.38, 1.065] },
		Tail: { parent: 'Torso', pivot: [-0.76, 1.55, 0] },
	},
	regions: [{ bone: 'LeverKnob', region: [-0.2, 0.2, 2.25, 2.5, 1.0, 1.2], only: /^Lever$/ }],
};
