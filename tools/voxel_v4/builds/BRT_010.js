// BRT_010 Talpa Di Fero — Voxel V4 build (CP-B, revision 2: "iron mole, more metal").
// Base: the accepted Studio sculpture (assets/BRT_010_Talpa_Di_Fero_Studio/):
// - a squat upright mole with huge round brass goggles over startled eyes
// - a spiral drill snout with whiskers, forward-reaching arms with big digging claws, short legs,
//   a curled tail, and spiked back armour with bands
// Revision 2 (owner): lean into "di Fero" (of iron), make it less boxy, and fix the muddy colours.
// - round stepped-sphere body and head in cobalt-painted steel, a riveted light-steel belly plate
// - a hot-orange riveted armour shell with brass bands, a glowing rim and chrome spikes
// - a bigger chrome drill with an orange spiral, and a miner's headlamp
// - gunmetal paws and feet with chrome claws
// Revision 3 (owner flagged body/limbs, no preference given): huge shovel-shaped digging hands with
//   bigger claws, chunkier arms, longer visible legs (body lifted 0.3), a slightly plumper body.
// V4 core rules: kit anime eyes (Candy; lash, catchlights) inside the goggle lenses, glowing Neon
// armour rim and headlamp, light-up soles, studs on body panels only, dark joint collars.
// Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const CHROME = '#F2F6FF';
const CLAW = '#DDE6F2';

// stepped octagon layer of radius r about (cx, cz)
function layer(cx, cz, y0, y1, r, role, rel = R) {
	B(cx - r, cx + r, y0, y1, cz - 0.7 * r, cz + 0.7 * r, role, rel);
	B(cx - 0.7 * r, cx + 0.7 * r, y0, y1, cz - r, cz + r, role, rel);
}
const rAt = (cy, R0, y0, y1) => Math.sqrt(Math.max(0.03, R0 * R0 - Math.pow((y0 + y1) / 2 - cy, 2)));
function tube(a, b, r0, r1, role) {
	const L = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
	const n = Math.max(1, Math.ceil(L / 0.2));
	for (let k = 0; k < n; k++) {
		const t0 = k / n, t1 = (k + 1) / n, r = r0 + (r1 - r0) * (t0 + t1) / 2;
		const c0 = a.map((v, i) => v + (b[i] - v) * t0), c1 = a.map((v, i) => v + (b[i] - v) * t1);
		B(Math.min(c0[0], c1[0]) - r, Math.max(c0[0], c1[0]) + r, Math.min(c0[1], c1[1]) - r, Math.max(c0[1], c1[1]) + r,
			Math.min(c0[2], c1[2]) - r, Math.max(c0[2], c1[2]) + r, role, R);
	}
}

// --- round cobalt-steel body (stepped sphere); the equator box is the Body
const BCY = 1.32, BR = 0.92;
S('Body');
B(-BR, BR, 1.0, 1.66, -0.7 * BR, 0.7 * BR, 'upper', R);
S('BodyRound');
B(-0.68 * BR, 0.68 * BR, 1.0, 1.66, -BR, BR, 'upper', R);
for (const [y0, y1] of [[0.48, 0.7], [0.7, 1.0], [1.66, 1.94], [1.94, 2.14]]) layer(0, 0, y0, y1, rAt(BCY, BR, y0, y1), 'upper');
// riveted light-steel belly plate with a dark seam
S('BellyPlate');
B(0.8, 0.86, 0.78, 1.86, -0.4, 0.4, 'lower', R);
S('Seam');
B(0.86, 0.88, 1.3, 1.34, -0.4, 0.4, 'P', 0, DARK);
S('Rivet');
for (const [y, z] of [[1.78, -0.32], [1.78, 0.32], [0.86, -0.32], [0.86, 0.32]]) {
	B(0.86, 0.9, y - 0.04, y + 0.04, z - 0.04, z + 0.04, 'P', 0, CHROME);
}

// --- round cobalt-steel head (stepped sphere)
const HCX = 0.12, HCY = 2.58, HR = 0.64;
S('Head');
for (const [y0, y1] of [[2.0, 2.2], [2.2, 2.96], [2.96, 3.12], [3.12, 3.22]]) layer(HCX, 0, y0, y1, rAt(HCY, HR, y0, y1), 'skin');

// --- big round brass goggles with pink anime eyes, navy strap and brows
const FXG = HCX + HR + 0.02, GY = 2.62, GZ = 0.4, GO = 0.4, GI = 0.29;
for (const out of [1, -1]) {
	const zc = GZ * out, C = 0.21;
	S('GoggleRing');
	B(FXG - 0.1, FXG + 0.1, GY + GI, GY + GO, zc - C, zc + C, 'trim', R);
	B(FXG - 0.1, FXG + 0.1, GY - GO, GY - GI, zc - C, zc + C, 'trim', R);
	B(FXG - 0.1, FXG + 0.1, GY - C, GY + C, zc - GO, zc - GI, 'trim', R);
	B(FXG - 0.1, FXG + 0.1, GY - C, GY + C, zc + GI, zc + GO, 'trim', R);
	for (const [sy, sz] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) B(FXG - 0.1, FXG + 0.1, GY + sy * 0.2, GY + sy * 0.34, zc + sz * 0.2, zc + sz * 0.34, 'trim', R);
	S('Lens');
	B(FXG - 0.08, FXG - 0.04, GY - GI, GY + GI, zc - C, zc + C, 'P', 0, '#F4FBFF');
	B(FXG - 0.08, FXG - 0.04, GY - C, GY + C, zc - GI, zc + GI, 'P', 0, '#F4FBFF');
	frontEye({ faceX: FXG - 0.04, zc, top: GY + GI - 0.02, L: 1.0, H: 0.88, out, iris: 'Candy', lash: true, blush: false });
	S('Brow');
	B(FXG - 0.2, FXG + 0.06, GY + GO + 0.06, GY + GO + 0.17, zc - 0.26, zc + 0.26, 'skin2', R);
}
S('GoggleStrap');
layer(HCX, 0, GY - 0.07, GY + 0.07, HR + 0.03, 'skin2', 0);
// miner's headlamp on the forehead above the goggles
S('Headlamp');
B(HCX + 0.24, HCX + 0.56, 3.06, 3.3, -0.16, 0.16, 'P', 0, DARK);
S('HeadlampLens');
B(HCX + 0.56, HCX + 0.6, 3.1, 3.26, -0.12, 0.12, 'stripe', E);

// --- big chrome drill snout: navy collar, stepped cone, orange spiral bands, chrome whiskers
const DX = HCX + HR - 0.04, DY = 2.08;
S('DrillCollar');
B(DX, DX + 0.12, DY - 0.32, DY + 0.32, -0.32, 0.32, 'skin2', R);
S('Drill');
[[0.12, 0.38, 0.3], [0.38, 0.62, 0.24], [0.62, 0.84, 0.18], [0.84, 1.02, 0.12], [1.02, 1.16, 0.06]].forEach(([a, b, r]) => {
	B(DX + a, DX + b, DY - r, DY + r, -r, r, 'prop', R);
});
S('DrillSpiral');
for (const [a, r] of [[0.34, 0.28], [0.58, 0.22], [0.8, 0.16]]) B(DX + a, DX + a + 0.07, DY - r, DY + r, -r, r, 'feather');
S('Whisker');
for (const y of [2.0, 2.18]) MZ(DX + 0.1, DX + 0.14, y, y + 0.03, 0.34, 0.92, 'P', 0, CHROME);

// --- chunky arms reaching forward to huge shovel-shaped mole hands with big chrome claws
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.2, 0.22, 1.48, 1.9, 0.8 * s, 0.9 * s, 'P', 0, DARK);
	S('Arm');
	tube([0.0, 1.7, 0.86 * s], [0.5, 1.16, 1.16 * s], 0.24, 0.2, 'upper');
	S('Paw');                                                    // broad flat digging hand
	B(0.36, 1.0, 0.8, 1.26, (1.16 - 0.34) * s, (1.16 + 0.34) * s, 'foot', R);
	B(0.46, 0.92, 0.72, 0.8, (1.16 - 0.28) * s, (1.16 + 0.28) * s, 'foot');
	S('Claw');
	for (const dz of [-0.22, 0, 0.22]) {
		const z = (1.16 + dz) * s;
		B(1.0, 1.34, 0.8, 1.04, z - 0.085, z + 0.085, 'P', 0, CLAW);
		B(1.34, 1.56, 0.76, 0.96, z - 0.05, z + 0.05, 'P', 0, CLAW);
	}
}

// --- hot-orange riveted armour shell on the back: rounded dome, brass bands, glowing rim, chrome spikes
S('Armour');
B(-1.0, -0.2, 0.86, 2.12, -0.64, 0.64, 'feather', R);
B(-0.92, -0.12, 0.98, 2.0, -0.8, 0.8, 'feather', R);
B(-0.84, -0.3, 2.12, 2.36, -0.48, 0.48, 'feather', R);
S('ArmourBand');
for (const z of [-0.3, 0.3]) B(-1.03, -1.0, 0.86, 2.12, z - 0.05, z + 0.05, 'trim');
B(-1.03, -1.0, 1.46, 1.56, -0.64, 0.64, 'trim');
S('Rivet');
for (const z of [-0.5, 0.5]) B(-1.06, -1.03, 1.9, 1.98, z - 0.04, z + 0.04, 'P', 0, CHROME);
S('ArmourRim');
B(-1.04, -0.1, 0.8, 0.88, -0.84, 0.84, 'stripe', E);
S('Spike');
for (const [y, z] of [[1.82, 0.32], [1.82, -0.32], [1.22, 0.4], [1.22, -0.4]]) {
	B(-1.16, -1.0, y - 0.09, y + 0.09, z - 0.09, z + 0.09, 'P', 0, CLAW);
	B(-1.3, -1.16, y - 0.04, y + 0.04, z - 0.04, z + 0.04, 'P', 0, CLAW);
}
for (const z of [-0.26, 0.26]) {
	B(-0.66, -0.5, 2.36, 2.54, z - 0.08, z + 0.08, 'P', 0, CLAW);
	B(-0.61, -0.55, 2.54, 2.68, z - 0.035, z + 0.035, 'P', 0, CLAW);
}

// --- curled gunmetal tail
S('Tail');
B(-1.12, -0.82, 0.34, 0.58, -0.1, 0.1, 'foot', R);
B(-1.26, -1.04, 0.14, 0.44, -0.09, 0.09, 'foot', R);
B(-1.16, -0.96, 0.06, 0.18, -0.08, 0.08, 'foot');

// --- lift everything above so the mole stands on longer, visible legs
const LIFT = 0.3;
for (const p of parts) { p.min[1] += LIFT; p.max[1] += LIFT; }

// --- longer chunky legs with dark hip collars, gunmetal feet with chrome claws, light-up soles
for (const s of [1, -1]) {
	const zc = 0.38 * s;
	S('HipCollar');
	B(-0.24, 0.24, 0.9, 1.02, zc - 0.24, zc + 0.24, 'P', 0, DARK);
	S('Leg');
	tube([0.0, 0.96, zc], [0.08, 0.34, zc], 0.21, 0.18, 'upper');
	S('Foot');
	B(-0.26, 0.5, 0.06, 0.34, zc - 0.26, zc + 0.26, 'foot', R);
	S('Claw');
	for (const dz of [-0.15, 0, 0.15]) B(0.5, 0.68, 0.08, 0.22, zc + dz - 0.055, zc + dz + 0.055, 'P', 0, CLAW);
	S('Sole');
	B(-0.26, 0.5, 0, 0.06, zc - 0.26, zc + 0.26, 'accent', E);
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_010_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#3F6FE0', skin: '#3F6FE0', lower: '#B8C8E8', feather: '#FF6A1A', trim: '#FFC21A', skin2: '#1A2550', foot: '#2A3550', prop: '#9FB2CF', stripe: '#2EF2FF', accent: '#FF3DD1', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// 13 Nov 2026 (animation pass): the drill cone and its spiral bands get their own bone under the
// head, on the drill axis, so the drill can spin (signature prop). The collar stays on the head.
// The toe claws share the hand claws' slot name, so a region puts them back on the legs.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	// Elbows (owner, review round 2): the arm is one tube from shoulder to hand, so the elbow sits
	// at its midpoint. The outer half of the tube, the shovel hand and its claws hang off it.
	slots: { Paw: '{side}Forearm', Claw: '{side}Forearm', Armour: 'Torso', ArmourBand: 'Torso', ArmourRim: 'Torso', Spike: 'Torso', Drill: 'Drill', DrillCollar: 'Head', DrillSpiral: 'Drill' },
	extraBones: {
		Drill: { parent: 'Head', pivot: [0.72, 2.38, 0] },
		RightForearm: { parent: 'RightArm', pivot: [0.25, 1.73, 1.01] },
		LeftForearm: { parent: 'LeftArm', pivot: [0.25, 1.73, -1.01] },
	},
	regions: [
		{ bone: 'RightForearm', region: [0.25, 2, 1, 2.4, 0.5, 2], only: /^Arm$/ },
		{ bone: 'LeftForearm', region: [0.25, 2, 1, 2.4, -2, -0.5], only: /^Arm$/ },
		{ bone: 'RightLeg', region: [0.4, 0.8, 0, 0.3, 0, 1], only: /^Claw$/ },
		{ bone: 'LeftLeg', region: [0.4, 0.8, 0, 0.3, -1, 0], only: /^Claw$/ },
	],
};
