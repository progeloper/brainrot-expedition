// BRT_022 Trulimero Trulicina — Voxel V4 build (CP-C, Rare, revision 2).
// Reference: the Steal a Brainrot in-game model (stealabrainrot.noob.wiki picture; "a charming ginger
// cat with a salmon body"):
// - a big boxy ginger cat head at the front: huge green eyes, pointed ears, a pink nose
// - a grey fish body behind the head, with spiky fins on top and a pink fin on the side
// - four tan human legs with feet
// Revision 2 (owner): "go off references from other roblox games and make it v4". Other renditions
// (yumcut render, Catch a Brainrot, the italianbrainrot-games wiki: "a cat's hair on a goldfish ... four
// legs") show a ginger tabby cat head on an ORANGE GOLDFISH with flowing fancy fins, so revision 2:
// - a vivid orange goldfish body (dark back, cream belly, glowing gold lateral line, gold scale dots)
//   with ginger cat-fur tufts along the back
// - a big flowing coral triple tail, a tall flowing dorsal fin and side fins, with glowing tips
// - tabby stripes on the ginger cat head
// - the four riggable human legs stay; the soles glow cyan
// The V4 take (revision 1):
// - a big deadpan ginger cat head with a cream muzzle, pink nose, white whiskers, pink-lined pointed
//   ears and huge lime anime eyes
// - a silver-blue fish body with V4 countershading (dark back, pale belly), a glowing cyan lateral
//   line, a spiky pink dorsal fin, pink side fins and a forked tail
// - the gag: the fish walks on four human legs with bare feet and glowing soles
// Rig-ready (owner rule): the front pair and back pair of legs each match: straight, with hip and knee
// collars and flat feet pointing straight ahead.
// V4 core rules: kit anime eyes (Lime; thin lash, catchlights, blush) on white eye domes, glowing Neon
// lateral line and soles, studs on body panels only. Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const WHISKER = '#FFFFFF';

// octagon slice of the fish body lying along x (centre height CY)
const CY = 1.55;
function xslice(x0, x1, r, role, rel = R) {
	B(x0, x1, CY - r, CY + r, -0.7 * r, 0.7 * r, role, rel);
	B(x0, x1, CY - 0.66 * r, CY + 0.66 * r, -r, r, role, rel);
}

// --- silver-blue fish body behind the head (the Body), tapering to a forked tail
S('Body');
B(-0.95, 0.3, CY - 0.55, CY + 0.55, -0.385, 0.385, 'upper', R);
S('FishBody');
B(-0.95, 0.3, CY - 0.363, CY + 0.363, -0.55, 0.55, 'upper', R);
xslice(-1.3, -0.95, 0.38, 'upper');
xslice(-1.55, -1.3, 0.2, 'upper');
// countershading: dark back, pale belly; glowing cyan lateral line along both sides
S('FishBack');
B(-1.3, 0.3, CY + 0.36, CY + 0.58, -0.3, 0.3, 'feather', R);
S('FishBelly');
B(-1.3, 0.3, CY - 0.58, CY - 0.36, -0.3, 0.3, 'lower', R);
S('LateralLine');
for (const s of [1, -1]) {
	const z = s > 0 ? [0.55, 0.58] : [-0.58, -0.55];
	B(-0.95, 0.3, CY - 0.03, CY + 0.03, ...z, 'stripe', E);
	const z2 = s > 0 ? [0.38, 0.41] : [-0.41, -0.38];
	B(-1.3, -0.95, CY - 0.03, CY + 0.03, ...z2, 'stripe', E);
}
// gold scale dots in offset rows on both flanks
S('ScaleDot');
for (const s of [1, -1]) {
	const z = s > 0 ? [0.55, 0.59] : [-0.59, -0.55];
	for (const [x, y] of [[-0.7, CY + 0.22], [-0.3, CY + 0.22], [0.1, CY + 0.22], [-0.5, CY - 0.22], [-0.1, CY - 0.22]]) {
		B(x - 0.07, x + 0.07, y - 0.07, y + 0.07, ...z, 'trim', 0);
	}
}
// cat fur on a goldfish: ginger fur tufts along the back
S('FurTuft');
for (const x of [-0.05, -0.35]) B(x - 0.13, x + 0.13, CY + 0.56, CY + 0.72, -0.2, 0.2, 'skin', R);
// tall flowing coral dorsal fin with a glowing tip, flowing side fins
S('DorsalFin');
B(-1.05, -0.55, CY + 0.56, CY + 0.86, -0.05, 0.05, 'feather2', 0);
B(-1.2, -0.8, CY + 0.86, CY + 1.08, -0.04, 0.04, 'feather2', 0);
B(-1.32, -1.12, CY + 1.04, CY + 1.14, -0.04, 0.04, 'stripe', E);
S('SideFin');
for (const s of [1, -1]) {
	const z = s > 0 ? [0.55, 0.62] : [-0.62, -0.55];
	B(-0.3, 0.2, CY - 0.44, CY - 0.08, ...z, 'feather2', 0);
	B(-0.5, -0.2, CY - 0.6, CY - 0.36, ...z, 'feather2', 0);
}
// big flowing fancy goldfish tail: three lobes with glowing tips
S('TailFin');
B(-2.1, -1.5, CY + 0.08, CY + 0.6, -0.05, 0.05, 'feather2', 0);
B(-2.4, -2.0, CY + 0.5, CY + 0.86, -0.04, 0.04, 'feather2', 0);
B(-2.1, -1.5, CY - 0.6, CY - 0.08, -0.05, 0.05, 'feather2', 0);
B(-2.4, -2.0, CY - 0.86, CY - 0.5, -0.04, 0.04, 'feather2', 0);
B(-2.2, -1.5, CY - 0.16, CY + 0.16, -0.06, 0.06, 'feather2', 0);
S('TailTip');
B(-2.52, -2.36, CY + 0.78, CY + 0.94, -0.04, 0.04, 'stripe', E);
B(-2.52, -2.36, CY - 0.94, CY - 0.78, -0.04, 0.04, 'stripe', E);
B(-2.34, -2.18, CY - 0.1, CY + 0.1, -0.05, 0.05, 'stripe', E);

// --- big deadpan ginger cat head at the front
S('Head');
B(0.15, 1.35, 0.95, 2.35, -0.72, 0.72, 'skin', R);
B(0.25, 1.25, 2.35, 2.48, -0.6, 0.6, 'skin', R);
S('Muzzle');
B(1.3, 1.46, 1.0, 1.48, -0.46, 0.46, 'skin2', R);
S('TabbyStripe');                                               // tabby stripes on top and down the cheeks
for (const z of [-0.3, 0, 0.3]) B(0.3, 1.26, 2.48, 2.51, z - 0.06, z + 0.06, 'trim', 0);
for (const s of [1, -1]) for (const y of [1.7, 1.95]) {
	const z = s > 0 ? [0.72, 0.75] : [-0.75, -0.72];
	B(0.35, 0.95, y - 0.05, y + 0.05, ...z, 'trim', 0);
}
S('Nose');
B(1.46, 1.53, 1.36, 1.48, -0.12, 0.12, 'P', 0, '#FF4F7A');
S('Mouth');
B(1.46, 1.48, 1.14, 1.2, -0.2, 0.2, 'P', 0, INK);
B(1.46, 1.48, 1.2, 1.36, -0.02, 0.02, 'P', 0, INK);
S('Whisker');
for (const s of [1, -1]) for (const y of [1.22, 1.34]) B(1.42, 1.48, y, y + 0.03, (0.46) * s, (0.9) * s, 'P', 0, WHISKER);
for (const s of [1, -1]) {
	S('Ear');
	B(0.4, 0.82, 2.46, 2.8, 0.3 * s, 0.68 * s, 'skin', R);
	B(0.48, 0.74, 2.8, 3.0, 0.4 * s, 0.6 * s, 'skin', R);
	S('InnerEar');
	B(0.82, 0.84, 2.5, 2.76, 0.38 * s, 0.6 * s, 'feather2');
}
// huge lime anime eyes on white domes (deadpan stare), thin lash line
const FX = 1.36;
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.1, FX, 1.5, 2.28, 0.04 * out, 0.66 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.35 * out, top: 2.24, L: 1.02, H: 0.98, out, iris: 'Lime', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer);
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
}

// --- the gag: four human legs with bare feet (front and back pairs match), glowing soles
for (const [lx, label] of [[0.7, 'Front'], [-0.75, 'Back']]) {
	for (const s of [1, -1]) {
		const zc = 0.36 * s;
		S(label + 'HipCollar');
		B(lx - 0.2, lx + 0.2, 0.98, 1.05, zc - 0.2, zc + 0.2, 'P', 0, DARK);
		S(label + 'Thigh');
		B(lx - 0.17, lx + 0.17, 0.58, 1.0, zc - 0.17, zc + 0.17, 'prop', R);
		S(label + 'KneeCollar');
		B(lx - 0.16, lx + 0.16, 0.52, 0.59, zc - 0.16, zc + 0.16, 'P', 0, DARK);
		S(label + 'Shin');
		B(lx - 0.14, lx + 0.14, 0.2, 0.53, zc - 0.14, zc + 0.14, 'prop', R);
		S(label + 'Foot');                                       // bare foot, flat, pointing straight ahead
		B(lx - 0.18, lx + 0.32, 0.04, 0.22, zc - 0.17, zc + 0.17, 'prop', R);
		for (const dz of [-0.08, 0.08]) B(lx + 0.32, lx + 0.42, 0.04, 0.14, zc + dz - 0.07, zc + dz + 0.07, 'prop');
		S(label + 'Sole');
		B(lx - 0.18, lx + 0.42, 0, 0.04, zc - 0.17, zc + 0.17, 'accent', E);
	}
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_022_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#FF5A0A', feather: '#C42E06', lower: '#FFF1D6', stripe: '#FFE14D', trim: '#A8360A', feather2: '#FF5C8A', skin: '#FF9026', skin2: '#FFF0DC', prop: '#FFC79A', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	// animation pass (13 Nov 2026): the head turns where it meets the fish, the tail fans from the
	// middle of its root, the back fur stays on the fish, and the side and dorsal fins get joints
	slots: { SideFin: '{side}Fin', ScaleDot: 'Torso', FurTuft: 'Torso', DorsalFin: 'DorsalFin' },
	headPivot: [0.3, 1.55, 0],
	tailPivot: [-1.5, 1.55, 0],
	extraBones: {
		RightFin: { parent: 'Torso', pivot: [-0.05, 1.47, 0.55] },
		LeftFin: { parent: 'Torso', pivot: [-0.05, 1.47, -0.55] },
		DorsalFin: { parent: 'Torso', pivot: [-0.8, 2.11, 0] },
	},
};
