// BRT_030 Tractoro Dinosauro — Voxel V4 build (CP-C, Epic, revision 2).
// References, which agree (viewed only): the Steal a Brainrot in-game model (stealabrainrot.noob.wiki; "a
// distinctive combination of dinosaur and tractor elements") and the yumcut.com render ("a T-Rex-like reptile fused
// with an orange farm tractor. Fan lore casts him as a prehistoric farmer"):
// - a big, bulky green T-rex lying on top of the tractor, wider than the hood, its big long-jawed toothy head
//   raised at the front, tiny forearms held forward, a tail sweeping back
// - an orange tractor front block with a grille and headlights; four big dark tyres, the rear pair larger
// Revision 2 (owner): "as before, use online references and super dopamine v4" + "more dopamine".
// - closer to the in-game proportions: a much bulkier, wider T-rex dominating the tractor; a bigger head
// - louder: glowing lime dorsal plates and spots, a glowing cyan racing stripe, glowing yellow lightning bolts on
//   the hood, a gold grille and gold exhaust, gold hubcaps with glowing cyan gems, bigger side eyes, a jeweled hat
//   buckle; the steering wheel is dropped (clutter in front of the face)
// Kept from revision 1: cream belly with the glowing cyan waterline, amber BRT_027 side eyes, a toothy grin with a
// tongue, the straw farmer hat and wheat stalk (the "prehistoric farmer" gag), magenta hub rings, passive FX.
// Rig-ready (owner rule): the arms and the wheels are matching symmetric pairs with collars / axles.
// Studs on body panels only. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const STEEL = '#DDE8F0';
const GOLD = '#FFC21A';
const MAW = '#6E0E2C';

// --- the bulky T-rex torso lying on the tractor: green top (the Body) over a cream belly, cyan waterline between
S('Body');
B(-1.15, 0.8, 1.95, 2.8, -0.8, 0.8, 'upper', R);
S('Belly');
B(-1.1, 0.78, 1.4, 1.89, -0.74, 0.74, 'lower', R);
S('Waterline');
B(-1.17, 0.82, 1.89, 1.95, -0.82, 0.82, 'stripe', E);
S('Chest');                                                     // chest / neck rising forward to the head
B(0.4, 1.08, 2.1, 3.1, -0.56, 0.56, 'upper', R);
S('ChestBelly');
B(1.08, 1.13, 1.95, 2.95, -0.4, 0.4, 'lower', R);
B(0.8, 0.85, 1.4, 1.95, -0.5, 0.5, 'lower', R);
S('Spots');                                                     // glowing lime spots on the flanks
for (const [x, y] of [[-0.75, 2.35], [-0.25, 2.5], [0.25, 2.28]]) MZ(x - 0.13, x + 0.13, y - 0.1, y + 0.1, 0.8, 0.83, 'feather', E);

// --- big T-rex head: skull, long snout, cream lower jaw, wide toothy grin with a tongue
S('Head');
B(0.55, 1.62, 2.95, 3.82, -0.58, 0.58, 'upper', R);
B(0.55, 1.08, 2.58, 2.95, -0.58, 0.58, 'upper', R);           // jaw hinge / cheeks
S('Snout');
B(1.62, 2.26, 2.95, 3.48, -0.48, 0.48, 'upper', R);
S('Jaw');
B(1.04, 2.2, 2.56, 2.78, -0.46, 0.46, 'lower', R);
S('Mouth');
B(1.08, 2.22, 2.78, 2.95, -0.43, 0.43, 'P', 0, MAW);
S('Tongue');
B(1.5, 2.17, 2.78, 2.85, -0.23, 0.23, 'P', 0, '#FF4F7A');
S('Teeth');                                                     // a toothy grin (T-rex: teeth are in character)
for (const z of [-0.32, -0.16, 0, 0.16, 0.32]) B(2.17, 2.24, 2.85, 2.95, z - 0.05, z + 0.05, 'P', 0, '#FFFFFF');
MZ(1.82, 1.92, 2.85, 2.95, 0.38, 0.44, 'P', 0, '#FFFFFF');
MZ(1.5, 1.6, 2.85, 2.95, 0.38, 0.44, 'P', 0, '#FFFFFF');
S('Nostril');
MZ(2.08, 2.18, 3.48, 3.5, 0.13, 0.26, 'P', 0, INK);
S('Wheat');                                                     // the farmer's wheat stalk in the grin
B(1.9, 2.62, 2.86, 2.92, -0.41, -0.35, 'P', 0, '#FFE08A');
B(2.54, 2.76, 2.84, 2.96, -0.43, -0.33, 'P', 0, GOLD);

// big side anime eyes (BRT_027 construction, scaled), amber iris, lash bar, blush
for (const s of [1, -1]) {
	const zz = (a, b) => (s > 0 ? [a, b] : [-b, -a]);
	const zf = 0.58, k = 0.5, X = 0.66, Y = 2.98;
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

// --- the farmer's straw hat with a red band and a jeweled gold buckle (gag + bling)
S('HatCrown');
B(0.62, 1.38, 3.82, 4.22, -0.44, 0.44, 'skin2', R);
S('HatBrim');
B(0.3, 1.7, 3.88, 3.96, -0.82, 0.82, 'skin2', R);
S('HatBand');
B(0.61, 1.39, 3.94, 4.05, -0.45, 0.45, 'P', 0, '#FF2D55');
S('HatBuckle');
B(1.39, 1.42, 3.92, 4.07, -0.12, 0.12, 'P', 0, GOLD);
B(1.42, 1.45, 3.95, 4.04, -0.05, 0.05, 'P', E, '#2EF2FF');

// --- glowing lime dorsal plates down the back and tail
S('DorsalPlate');
for (const x of [-0.85, -0.4, 0.05]) {
	B(x - 0.17, x + 0.17, 2.8, 2.98, -0.07, 0.07, 'feather', E);
	B(x - 0.08, x + 0.08, 2.98, 3.12, -0.06, 0.06, 'feather', E);
}
B(-1.58, -1.32, 2.62, 2.78, -0.06, 0.06, 'feather', E);
B(-2.1, -1.9, 2.48, 2.6, -0.05, 0.05, 'feather', E);

// --- long tail sweeping back
S('Tail');
B(-1.75, -1.1, 1.98, 2.62, -0.46, 0.46, 'upper', R);
B(-2.3, -1.7, 2.08, 2.48, -0.31, 0.31, 'upper', R);
B(-2.7, -2.25, 2.18, 2.38, -0.18, 0.18, 'upper');
S('TailBelly');
B(-1.75, -1.15, 1.93, 1.98, -0.42, 0.42, 'lower');

// --- tiny T-rex arms (matching pair) held forward
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('ShoulderCollar');
	B(1.08, 1.14, 2.16, 2.38, ...z(0.22, 0.42), 'P', 0, DARK);
	S('UpperArm');
	B(1.12, 1.34, 2.14, 2.36, ...z(0.23, 0.41), 'upper', R);
	S('Forearm');
	B(1.32, 1.5, 2.06, 2.22, ...z(0.24, 0.4), 'upper');
	S('Claw');
	B(1.48, 1.57, 2.02, 2.14, ...z(0.25, 0.39), 'P', 0, '#FFFFFF');
}

// --- candy-orange tractor: hood with a glowing racing stripe and lightning bolts, gold grille, glowing headlights
S('Hood');
B(0.3, 1.66, 0.62, 1.4, -0.58, 0.58, 'skin', R);
S('Chassis');
B(-1.4, 0.3, 0.7, 1.45, -0.7, 0.7, 'skin', R);
S('HoodStripe');
B(0.3, 1.67, 1.4, 1.43, -0.13, 0.13, 'stripe', E);
S('LightningBolt');                                             // glowing glitch-zone bolts on the hood sides
MZ(0.38, 0.78, 1.12, 1.24, 0.58, 0.61, 'P', E, '#FFE14D');
MZ(0.66, 1.16, 0.94, 1.06, 0.58, 0.61, 'P', E, '#FFE14D');
MZ(1.04, 1.5, 0.76, 0.88, 0.58, 0.61, 'P', E, '#FFE14D');
S('Grille');
B(1.66, 1.7, 0.7, 1.32, -0.44, 0.44, 'P', 0, GOLD);
for (const z of [-0.26, 0, 0.26]) B(1.7, 1.73, 0.74, 1.0, z - 0.05, z + 0.05, 'P', 0, DARK);
S('Headlight');
MZ(1.66, 1.78, 1.04, 1.3, 0.2, 0.48, 'P', E, '#FFF6A0');
S('Bumper');
B(1.66, 1.86, 0.5, 0.68, -0.64, 0.64, 'P', 0, STEEL);
S('Towbar');
B(-1.7, -1.4, 0.66, 0.76, -0.08, 0.08, 'P', 0, STEEL);
B(-1.78, -1.66, 0.6, 0.82, -0.12, 0.12, 'P', 0, STEEL);
S('ExhaustStack');                                              // gold stack beside the tail, glowing tip
B(-0.24, -0.08, 1.45, 3.0, -0.98, -0.82, 'P', 0, GOLD);
B(-0.27, -0.05, 3.0, 3.1, -1.01, -0.79, 'P', E, '#FF2DD1');

// --- rear mudguards (matching pair) over the big wheels, with a glowing cyan edge
for (const s of [1, -1]) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('Mudguard');
	B(-1.92, 0.02, 1.76, 1.9, ...z(0.84, 1.42), 'skin', R);
	B(-0.08, 0.02, 1.2, 1.76, ...z(0.84, 1.42), 'skin', R);
	S('MudguardGlow');
	B(-1.92, 0.02, 1.9, 1.94, ...z(1.36, 1.42), 'stripe', E);
}

// --- four chunky tyres (two matching pairs): tread lugs, glowing magenta hub ring, gold hubcap, glowing cyan gem
function wheel(cx, cy, r, zIn, zOut, s) {
	const z = (a, b) => [Math.min(a * s, b * s), Math.max(a * s, b * s)];
	S('Tyre');
	B(cx - r, cx + r, cy - 0.7 * r, cy + 0.7 * r, ...z(zIn, zOut), 'prop', R);
	B(cx - 0.7 * r, cx + 0.7 * r, cy - r, cy + r, ...z(zIn, zOut), 'prop', R);
	S('TreadLug');
	for (const dx of [-0.35, 0.2]) B(cx + dx * r - 0.08, cx + dx * r + 0.08, cy + r, cy + r + 0.06, ...z(zIn + 0.03, zOut - 0.03), 'prop');
	for (const sx of [1, -1]) {
		const x0 = sx > 0 ? cx + r : cx - r - 0.06;
		B(x0, x0 + 0.06, cy - 0.08, cy + 0.08, ...z(zIn + 0.03, zOut - 0.03), 'prop');
	}
	S('HubRing');
	B(cx - 0.58 * r, cx + 0.58 * r, cy - 0.58 * r, cy + 0.58 * r, ...z(zOut, zOut + 0.03), 'accent', E);
	S('Hubcap');
	B(cx - 0.44 * r, cx + 0.44 * r, cy - 0.44 * r, cy + 0.44 * r, ...z(zOut + 0.03, zOut + 0.07), 'foot', R);
	S('HubGem');
	B(cx - 0.14 * r, cx + 0.14 * r, cy - 0.14 * r, cy + 0.14 * r, ...z(zOut + 0.07, zOut + 0.11), 'P', E, '#2EF2FF');
}
for (const s of [1, -1]) {
	S('Axle');
	B(-1.07, -0.83, 0.73, 0.97, ...[Math.min(0.7 * s, 0.84 * s), Math.max(0.7 * s, 0.84 * s)], 'P', 0, DARK);
	wheel(-0.95, 0.85, 0.85, 0.84, 1.38, s);                    // big rear wheels
	wheel(1.0, 0.62, 0.62, 0.62, 1.06, s);                      // smaller front wheels
}

// Super-dopamine V4 palette (docs/creatures/V4/BRT_030_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#1EF04E', lower: '#FFF4D6', stripe: '#2EF2FF', feather: '#D4FF2A', skin: '#FF6A00', skin2: '#FFD54A', prop: '#2E2650', foot: '#FFC21A', trim: '#FFFFFF', accent: '#FF2DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
// passive FX (collectible flair): candy exhaust puffs, glitch sparkles (REGION_GLITCH), gold glints off the hubs
const passiveFx = [
	{ name: 'ExhaustPuff', texture: 'smoke', anchor: [-0.16, 3.15, -0.9], rate: 4, lifetime: [1.0, 1.6], size: [0.15, 0.55], transparency: [0.35, 1], colors: ['#FF6FE0', '#B9A2FF'], lightEmission: 0.4, speed: [0.5, 0.9], spread: 15, rise: 0.4 },
	{ name: 'GlitchSparkle', texture: 'sparkle', anchor: [0, 2.3, 0], rate: 7, lifetime: [0.9, 1.6], size: [0.22, 0.05], transparency: [0, 1], colors: ['#2EF2FF', '#FF2DD1'], lightEmission: 1, speed: [0.3, 0.8], spread: 180, rise: 0.25 },
	{ name: 'GoldGlint', texture: 'sparkle', anchor: [-0.95, 0.85, 0], rate: 4, lifetime: [0.6, 1.0], size: [0.18, 0.04], transparency: [0, 1], colors: ['#FFE14D', '#FFFFFF'], lightEmission: 1, speed: [0.2, 0.5], spread: 180, rise: 0.1 },
];
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin, passiveFx };
// Rig plan overrides for tools/voxel_v4/rig.js. Animation pass (13 Nov 2026): the tractor is the root joint
// (Torso, pivoting on its rear axle) and the dinosaur rides on it as its own joint, with the head, jaw, arms
// and tail on the dinosaur; the four wheel hubs and the exhaust stack get joints on the tractor.
if (typeof module !== 'undefined') {
	const HEAD = ['Head', 'Snout', 'Mouth', 'Teeth', 'Nostril', 'Wheat', 'EyeWhite', 'Iris', 'Pupil', 'Catchlight', 'Lash', 'Blush', 'HatCrown', 'HatBrim', 'HatBand', 'HatBuckle'];
	const slots = { Jaw: 'Jaw', Tongue: 'Jaw', Tail: 'Tail', TailBelly: 'Tail', ExhaustStack: 'Exhaust' };
	for (const s of HEAD) slots[s] = 'Head';
	for (const s of ['Body', 'Belly', 'Waterline', 'Chest', 'ChestBelly', 'Spots', 'DorsalPlate']) slots[s] = 'Dino';
	for (const s of ['ShoulderCollar', 'UpperArm', 'Forearm', 'Claw']) slots[s] = '{side}Arm';
	// only the hubs turn: the tyres are blocky crosses, so a turning tyre would dip its corners under the floor
	const WHEEL = /^(HubRing|Hubcap|HubGem)$/;
	module.exports.rigOverrides = {
		noHead: true, noArms: true, noTail: true,
		torsoPivot: [-0.95, 0.85, 0],
		slots,
		extraBones: {
			Dino: { parent: 'Torso', pivot: [-0.175, 1.9, 0] },
			Head: { parent: 'Dino', pivot: [0.8, 3.0, 0] },
			Jaw: { parent: 'Head', pivot: [1.04, 2.78, 0] },
			RightArm: { parent: 'Dino', pivot: [1.11, 2.27, 0.32] },
			LeftArm: { parent: 'Dino', pivot: [1.11, 2.27, -0.32] },
			Tail: { parent: 'Dino', pivot: [-1.1, 2.3, 0] },
			RearRightWheel: { parent: 'Torso', pivot: [-0.95, 0.85, 1.11] },
			RearLeftWheel: { parent: 'Torso', pivot: [-0.95, 0.85, -1.11] },
			FrontRightWheel: { parent: 'Torso', pivot: [1.0, 0.62, 0.84] },
			FrontLeftWheel: { parent: 'Torso', pivot: [1.0, 0.62, -0.84] },
			Exhaust: { parent: 'Torso', pivot: [-0.16, 1.45, -0.9] },
		},
		regions: [
			{ bone: 'Tail', region: [-2.2, -1.25, 2.4, 2.9, -0.2, 0.2], only: /^DorsalPlate$/ },
			{ bone: 'RearRightWheel', region: [-2, 0, 0, 1.8, 0.8, 1.6], only: WHEEL },
			{ bone: 'RearLeftWheel', region: [-2, 0, 0, 1.8, -1.6, -0.8], only: WHEEL },
			{ bone: 'FrontRightWheel', region: [0.3, 1.7, 0, 1.3, 0.6, 1.3], only: WHEEL },
			{ bone: 'FrontLeftWheel', region: [0.3, 1.7, 0, 1.3, -1.3, -0.6], only: WHEEL },
		],
	};
}
