// BRT_007 Tung Tung Tung Sahur — Voxel V4 build (CP-A first new species, awaiting owner review).
// Tough revision (owner, 4 Nov 2026): scowl, clenched smirk, no blush.
// Revision 5 (owner, 4 Nov 2026): taller/slimmer log, smaller face, bigger bat, longer arms.
// Revision 6 (owner, 4 Nov 2026): body widens to the head like a club / baseball bat.
// Identity: a living kentongan (wooden slit-drum log) with a big front face, thin arms,
// long thin legs on big bare feet, holding a small bat downward at its side.
// Project direction kept (AGENTS.md): upright body, smaller primitive bat held downward,
// longer legs, right hand wrapped around the bat handle. The parallel-sides rule is
// superseded by the owner's revision 6 club/bat taper (base stays wide enough for the hips). Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';

// --- body (revision 6, owner 4 Nov 2026): a club / baseball-bat log, widest at the head
// and tapering in stepped octagonal bands to a narrower (not thin) base above the legs.
// This supersedes the earlier parallel-sides direction at the owner's request.
S('Body');
B(-0.5, 0.5, 3.0, 8.3, -0.66, 0.66, 'upper', R);         // full-height trunk core
S('BodyBand');
for (const [y0, y1, cx, cz, rx, rz] of [
	[3.0, 4.2, 0.5, 0.66, 0.6, 0.54],    // base (narrowest, still clears both hips)
	[4.2, 5.3, 0.56, 0.74, 0.67, 0.61],
	[5.3, 6.2, 0.62, 0.82, 0.74, 0.68],
	[6.2, 8.3, 0.7, 0.94, 0.84, 0.78],   // head barrel (widest); face plate at x = 0.84
]) {
	B(-cx, cx, y0, y1, -cz, cz, 'upper', R);
	B(-rx, rx, y0, y1, -rz, rz, 'upper', R);
}
S('BodyTop');                                            // rounded barrel end
B(-0.62, 0.62, 8.3, 8.55, -0.84, 0.84, 'upper', R);
B(-0.74, 0.74, 8.3, 8.55, -0.7, 0.7, 'upper', R);
B(-0.52, 0.52, 8.55, 8.72, -0.6, 0.6, 'upper', R);
S('EndGrain');
B(-0.4, 0.4, 8.72, 8.8, -0.46, 0.46, 'skin2', R);        // light cut top
// --- dark rim where the legs meet the log (joint contrast)
S('BaseRim');
B(-0.62, 0.62, 2.92, 3.04, -0.56, 0.56, 'P', 0, DARK);
B(-0.52, 0.52, 2.92, 3.04, -0.68, 0.68, 'P', 0, DARK);
// --- wood grain streaks on the sides (per band face) and rear
S('Grain');
for (const [x, y0, y1, zf] of [[-0.35, 6.4, 8.0, 0.94], [0.3, 6.6, 7.8, 0.94], [0.05, 5.35, 6.15, 0.82], [-0.25, 4.25, 5.2, 0.74], [0.2, 3.2, 4.1, 0.66]]) {
	MZ(x - 0.05, x + 0.05, y0, y1, zf, zf + 0.03, 'trim');
}
for (const [z, y0, y1, xf] of [[-0.45, 6.3, 8.1, 0.84], [0.42, 6.5, 7.6, 0.84], [-0.4, 5.35, 6.15, 0.74], [0.35, 4.25, 5.2, 0.67]]) {
	B(-xf - 0.03, -xf, y0, y1, z - 0.05, z + 0.05, 'trim');
}
// --- kentongan slit on the back of the head barrel: glowing slot in a dark frame
S('DrumSlit');
B(-0.87, -0.84, 6.4, 8.1, -0.16, 0.16, 'P', 0, DARK);
B(-0.9, -0.87, 6.55, 7.95, -0.08, 0.08, 'accent', E);

// --- face (revision 5: ~70% of the previous size so more wood shows around it).
// Approved anime-eye construction under steep V-scowl lids, heavy dark brows, nose, clenched smirk.
const FX = 0.84, TOP = 8.15;
for (const out of [1, -1]) {
	const eye = frontEye({ faceX: FX, zc: 0.34 * out, top: TOP, L: 1.0, H: 1.4, out, iris: 'Ocean', lash: false, blush: false });
	const z = (a, b) => [Math.min(eye.inner + out * a, eye.inner + out * b), Math.max(eye.inner + out * a, eye.inner + out * b)];
	S('ScowlLid');
	for (const [a0, a1, drop] of [[-0.06, 0.19, 0.29], [0.19, 0.39, 0.18], [0.39, 0.64, 0.07]]) {
		B(FX, FX + 0.1, TOP - drop + 0.1, TOP + 0.13, ...z(a0, a1), 'upper');
		B(FX, FX + 0.11, TOP - drop, TOP - drop + 0.1, ...z(a0, a1), 'P', 0, '#000000');
	}
	S('Brow');
	for (const [a0, a1, rel] of [[-0.07, 0.19, -0.15], [0.19, 0.39, -0.04], [0.39, 0.66, 0.07]]) {
		B(FX, FX + 0.17, TOP + rel, TOP + rel + 0.18, ...z(a0, a1), 'P', 0, DARK);
	}
}
S('Nose');
B(FX, FX + 0.26, 6.85, 7.18, -0.14, 0.14, 'upper');
B(FX, FX + 0.14, 7.18, 7.34, -0.09, 0.09, 'upper');
MZ(FX + 0.26, FX + 0.28, 6.88, 6.97, 0.035, 0.1, 'P', 0, '#6e0e2c');
S('Jaw');
B(FX, FX + 0.12, 6.27, 6.39, -0.52, 0.52, 'upper');
B(FX, FX + 0.08, 6.66, 6.72, -0.55, 0.55, 'upper');
S('Mouth');
B(FX, FX + 0.04, 6.38, 6.66, -0.5, 0.5, 'P', 0, '#6e0e2c');
B(FX, FX + 0.04, 6.63, 6.81, 0.5, 0.59, 'P', 0, '#6e0e2c');     // hitched corner (+z)
B(FX, FX + 0.04, 6.38, 6.5, -0.59, -0.5, 'P', 0, '#6e0e2c');    // flat corner (-z)
S('Teeth');
for (let z = -0.46; z + 0.12 <= 0.48; z += 0.155) {
	B(FX + 0.04, FX + 0.07, 6.53, 6.64, z, z + 0.12, 'P', 0, '#ffffff');
	B(FX + 0.04, FX + 0.07, 6.4, 6.51, z + 0.06, Math.min(z + 0.18, 0.49), 'P', 0, '#ffffff');
}
S('Scar');
for (const [y0, z0] of [[6.74, -0.6], [6.84, -0.53], [6.94, -0.46]]) B(FX, FX + 0.04, y0, y0 + 0.1, z0, z0 + 0.08, 'P', 0, DARK);

// --- arms (revision 5: longer): start about halfway down the log and hang well below
// its bottom edge, ending in big fists at mid-thigh height.
for (const s of [1, -1]) {
	S('ShoulderCollar');
	B(-0.24, 0.24, 5.6, 6.0, 0.8 * s, 1.0 * s, 'P', 0, DARK);
	S('Arm');
	B(-0.17, 0.17, 2.6, 5.9, 0.9 * s, 1.14 * s, 'skin', R);
	S('WristCollar');
	B(-0.2, 0.2, 2.45, 2.62, 0.88 * s, 1.16 * s, 'P', 0, DARK);
}
S('Hand');
B(-0.3, 0.3, 1.88, 2.48, 0.8, 1.24, 'skin', R);
// right hand (-z, hero side) wraps the bat handle: fist + thumb on the front
S('Hand_R');
B(-0.32, 0.32, 1.86, 2.5, -0.8, -1.32, 'skin', R);
B(0.32, 0.4, 2.02, 2.34, -0.96, -1.16, 'skin');
// --- bat (revision 5: bigger, chunkier): angled down and outward from the fist
// (stepped staircase), barrel thickening towards the tip near the ground.
S('Bat');
B(-0.13, 0.13, 2.5, 2.72, -0.93, -1.19, 'P', 0, DARK);       // knob above the fist
for (const [y1, y0, zc, h] of [[1.95, 1.55, -1.2, 0.13], [1.65, 1.25, -1.45, 0.17], [1.35, 0.95, -1.72, 0.22], [1.05, 0.65, -2.0, 0.27], [0.75, 0.35, -2.3, 0.32], [0.45, 0.1, -2.62, 0.37]]) {
	B(-h, h, y0, y1, zc - h, zc + h, 'prop', R);
}
B(-0.3, 0.3, 0.0, 0.1, -2.92, -2.32, 'prop');               // end cap
B(-0.15, 0.15, 1.75, 1.85, -1.05, -1.35, 'P', 0, DARK);      // grip tape
S('BatGlow');
B(-0.24, 0.24, 1.1, 1.22, -1.96, -1.48, 'accent', E);        // glowing bands on the barrel
B(-0.34, 0.34, 0.5, 0.62, -2.64, -1.96, 'accent', E);

// --- long thin legs on big bare feet (closer together under the slimmer log)
for (const s of [1, -1]) {
	const zc = 0.42 * s;
	S('HipCollar');
	B(-0.26, 0.26, 2.78, 2.96, zc - 0.26, zc + 0.26, 'P', 0, DARK);
	S('Leg');
	B(-0.19, 0.19, 0.5, 2.82, zc - 0.19, zc + 0.19, 'skin', R);
	S('AnkleCollar');
	B(-0.23, 0.23, 0.38, 0.52, zc - 0.23, zc + 0.23, 'P', 0, DARK);
	S('Foot');
	B(-0.38, 0.8, 0, 0.4, zc - 0.3, zc + 0.3, 'foot', R);
	for (const dz of [-0.19, 0, 0.19]) {
		const len = dz === 0 ? 0.32 : 0.24;
		B(0.8, 0.8 + len, 0, 0.28, zc + dz - 0.08, zc + dz + 0.08, 'foot');
		B(0.8 + len, 0.8 + len + 0.06, 0.04, 0.22, zc + dz - 0.065, zc + dz + 0.065, 'P', 0, '#262a3a');
	}
}

// Reference-derived default palette (docs/creatures/V4/BRT_007_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#C76030', trim: '#8A3E1C', skin: '#E08A48', skin2: '#F0A04A', foot: '#E89A58', prop: '#E8963E', accent: '#FFB347', mode: 0 } },
	K.GLOBAL_PALETTES,
);
// Species overrides (inside each mutation's colour family) so the bat stays readable.
PALETTES.glitched = Object.assign({}, PALETTES.glitched, { prop: '#5A1F9A' });
PALETTES.astral = Object.assign({}, PALETTES.astral, { prop: '#2A1F6E' });
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Rig (animation brief v5, 13 Nov 2026): the bat was welded to the body, so it stayed behind when the arm
// holding it moved. It now sits on its own Bat bone under that arm (signature prop), pivoting at the grip.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	noHead: true,
	extraBones: { Bat: { parent: 'LeftArm', pivot: [0, 2.18, -1.06] } },
	slots: { Bat: 'Bat', BatGlow: 'Bat' },
};
