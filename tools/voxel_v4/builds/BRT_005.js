// BRT_005 Bombardiro Pigeon — Voxel V4 build (CP-B, revision 2: bomber-jet colouring).
// Follows the accepted Studio sculpture (assets/BRT_005_Bombardiro_Pigeon_Studio/) closely:
// - a plump upright city pigeon with a faceted round body
// - a head with oversized forward-facing eyes and a beak
// Revision 3 (owner): a rounder, plumper body. Revision 4 (owner): the neck band is back (as in
// revisions 1-2), with a bigger round head that is separate from the body and in gunmetal.
// - wings raised and spread to the sides, with two bars, a courier chevron and five flight-feather
//   fingers each
// - a three-feather tail, thin legs and big orange three-toed feet
// Revision 2 (owner): "bombard as in bomber jet colouring but still high contrast, high dopamine",
// with a bolder body and more colour contrast:
// - camouflage-style countershading: an army-green upper body over a light grey underside, split by
//   a glowing cyan line
// - gunmetal head and wings with yellow/black hazard-stripe wing bars and a hazard neck band
// - a red nose-cone beak and glowing orange afterburner tail tips
// - original pilot goggles pushed up on the head (no real insignia or logos)
// V4 core rules: kit anime eyes (Amber, lash, catchlights, blush), glowing lines, glowing chevrons,
// studs on body panels only, dark joint collars. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';

// --- round, plump stepped-sphere body with bomber countershading: army-green top, light grey
// underside, glowing cyan waterline.
// Each layer is an octagon of two boxes; r(y) follows a sphere of radius RAD about (cx, cy).
function layer(cx, y0, y1, r, role, rel = R, k = 0.7) {
	B(cx - r, cx + r, y0, y1, -k * r, k * r, role, rel);
	B(cx - k * r, cx + k * r, y0, y1, -r, r, role, rel);
}
const CY = 1.95, RAD = 1.18, WL = 1.75;
const rAt = (cy, R0, y0, y1) => Math.sqrt(Math.max(0.04, R0 * R0 - Math.pow((y0 + y1) / 2 - cy, 2)));
S('Underside');
for (const [y0, y1] of [[0.8, 1.05], [1.05, 1.35], [1.35, WL]]) layer(0, y0, y1, rAt(CY, RAD, y0, y1), 'lower');
S('Waterline');
layer(0, WL, WL + 0.1, rAt(CY, RAD, WL, WL + 0.1) + 0.03, 'stripe', 0);
// equator layer: the first box is the Body (largest upper box); its partner is a hair narrower
const rEq = rAt(CY, RAD, WL + 0.1, 2.35);
S('Body');
B(-rEq, rEq, WL + 0.1, 2.35, -0.7 * rEq, 0.7 * rEq, 'upper', R);
S('BodyRound');
B(-0.68 * rEq, 0.68 * rEq, WL + 0.1, 2.35, -rEq, rEq, 'upper', R);
for (const [y0, y1] of [[2.35, 2.75], [2.75, 3.0]]) layer(0, y0, y1, rAt(CY, RAD, y0, y1), 'upper');
S('Shoulders');
layer(0, 3.0, 3.1, rAt(CY, RAD, 3.0, 3.1), 'upper');

// --- neck (as in revisions 1-2): glowing line, yellow and black hazard bands
S('NeckGlow');
B(-0.66, 0.66, 3.06, 3.14, -0.66, 0.66, 'stripe', E);
S('NeckHazardYellow');
B(-0.6, 0.6, 3.14, 3.34, -0.6, 0.6, 'trim', R);
S('NeckHazardBlack');
B(-0.56, 0.56, 3.34, 3.56, -0.56, 0.56, 'feather2', R);

// --- bigger round gunmetal head, separate from the body on top of the neck; smooth face plate
const HX = 0.15, HY = 4.35, HR = 0.98;
const HEAD_START = parts.length;
S('Head');
for (const [y0, y1] of [[3.45, 3.75], [3.75, 4.1], [4.1, 4.6], [4.6, 4.95], [4.95, 5.2], [5.2, 5.32]]) layer(HX, y0, y1, rAt(HY, HR, y0, y1), 'skin');
const FX = HX + 0.98;
B(FX - 0.14, FX, 3.75, 4.95, -0.74, 0.74, 'skin', 0);       // face plate
// huge forward anime eyes (Amber), slim black brows
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.35 * out, top: 4.86, L: 1.18, H: 1.45, out, iris: 'Amber', lash: true, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Brow');
	B(FX, FX + 0.08, eye.lashTop + 0.03, eye.lashTop + 0.1, z0 + 0.08, z1 - 0.08, 'feather');
}
// red nose-cone beak with a golden lower mandible, pointed forward
S('Beak');
B(FX, FX + 0.34, 3.6, 3.84, -0.24, 0.24, 'prop', R);
B(FX + 0.34, FX + 0.5, 3.63, 3.8, -0.13, 0.13, 'prop');
S('Mandible');
B(FX, FX + 0.3, 3.52, 3.6, -0.18, 0.18, 'P', 0, '#FFC21A');
S('Nostril');
MZ(FX + 0.12, FX + 0.2, 3.84, 3.88, 0.06, 0.14, 'P', 0, DARK);
// original pilot goggles pushed up on the round crown: leather strap and two glowing lenses
S('GoggleStrap');
layer(HX, 5.02, 5.12, rAt(HY, HR, 5.02, 5.12) + 0.03, 'P', 0);
for (const p of parts.slice(-2)) p.col = '#8B5A2B';
for (const s of [1, -1]) {
	S('GoggleFrame');
	B(0.3, 0.8, 5.12, 5.4, 0.04 * s, 0.44 * s, 'P', 0, DARK);
	S('GoggleLens');
	B(0.8, 0.84, 5.16, 5.36, 0.08 * s, 0.4 * s, 'stripe', E);          // lens faces forward
}
// lift the whole head assembly so the hazard neck bands show below it
for (const p of parts.slice(HEAD_START)) { p.min[1] += 0.22; p.max[1] += 0.22; }

// --- wings raised and spread like real bird wings (thin plates in the y-z plane):
// an arched leading edge rises from the shoulder to the wrist; gunmetal coverts run along the top,
// then a bold yellow/black hazard band; gunmetal flight feathers hang below with black serrated
// tips; long black primary feathers fan outward from the wingtip. Glowing chevrons sit on the coverts.
const WCOL = [ // [z0, z1, trailing edge y, leading edge y]
	[0.95, 1.31, 1.95, 2.95], [1.31, 1.67, 2.15, 3.3], [1.67, 2.03, 2.35, 3.65], [2.03, 2.39, 2.6, 3.98], [2.39, 2.75, 2.95, 4.28],
];
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.34, -0.06, 2.28, 2.72, 1.0 * s, 1.1 * s, 'P', 0, DARK);
	WCOL.forEach(([z0, z1, yT, yL], k) => {
		S('WingCovert');
		B(-0.34, -0.1, yL - 0.45, yL, z0 * s, z1 * s, 'skin', R);
		S('WingBar');
		B(-0.32, -0.11, yL - 0.6, yL - 0.45, z0 * s, z1 * s, 'trim');
		B(-0.32, -0.11, yL - 0.75, yL - 0.6, z0 * s, z1 * s, 'feather');
		S('FlightFeather');
		B(-0.3, -0.14, yT, yL - 0.75, z0 * s, z1 * s, 'skin', R);
		if (k === 1 || k === 3) B(-0.3, -0.14, yT - 0.2, yT, (z0 + 0.06) * s, (z0 + 0.22) * s, 'feather');   // serrated tips
	});
	S('PrimaryFeather');
	for (const [y0, len] of [[4.12, 0.9], [3.9, 1.0], [3.68, 0.9], [3.46, 0.7]]) {
		B(-0.3, -0.14, y0, y0 + 0.16, 2.7 * s, (2.7 + len) * s, 'feather', R);
	}
	S('Chevron');
	B(-0.1, -0.06, 2.62, 2.74, 1.36 * s, 1.62 * s, 'accent', E);
	B(-0.1, -0.06, 2.96, 3.08, 1.72 * s, 1.98 * s, 'accent', E);
}

// --- three-feather tail fanned behind, angled down, with glowing afterburner tips
S('Tail');
for (const [z, dy] of [[-0.3, 0.06], [0, 0], [0.3, 0.06]]) {
	B(-1.75, -0.95, 1.38 + dy, 1.52 + dy, z - 0.13, z + 0.13, 'feather', R);
	S('Afterburner');
	B(-1.82, -1.75, 1.4 + dy, 1.5 + dy, z - 0.1, z + 0.1, 'accent', E);
	S('Tail');
}

// --- pigeon legs: grey feathered thighs, thicker coral-red legs with a backward ankle kink and a
// dark scale ring, big orange three-toed feet
for (const s of [1, -1]) {
	const zc = 0.42 * s;
	S('Thigh');
	B(-0.24, 0.18, 0.74, 1.0, zc - 0.21, zc + 0.21, 'lower', R);
	S('Leg');
	B(-0.18, 0.04, 0.5, 0.8, zc - 0.11, zc + 0.11, 'skin2', R);          // upper leg, set back
	B(-0.2, 0.06, 0.44, 0.58, zc - 0.13, zc + 0.13, 'skin2');             // ankle joint
	B(-0.08, 0.14, 0.14, 0.48, zc - 0.11, zc + 0.11, 'skin2', R);          // lower leg, kinked forward
	S('ScaleRing');
	B(-0.09, 0.15, 0.3, 0.36, zc - 0.12, zc + 0.12, 'P', 0, DARK);
	S('Foot');
	B(-0.16, 0.7, 0, 0.16, zc - 0.1, zc + 0.1, 'foot', R);               // middle toe
	B(-0.06, 0.56, 0, 0.14, zc + 0.12, zc + 0.3, 'foot');                 // side toes
	B(-0.06, 0.56, 0, 0.14, zc - 0.3, zc - 0.12, 'foot');
	B(-0.38, -0.08, 0, 0.12, zc - 0.07, zc + 0.07, 'foot');               // back toe
	B(-0.16, 0.16, 0, 0.18, zc - 0.16, zc + 0.16, 'foot', R);             // foot pad
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_005_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#4E9A2A', lower: '#C9D6E2', stripe: '#2EF2FF', trim: '#FFD60A', skin: '#46566E', skin2: '#E8473A', feather: '#15171C', feather2: '#15171C', foot: '#FF8A00', prop: '#FF2A2A', accent: '#FF5A1F', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = { slots: { ShoulderCollar: '{side}Wing' } };
