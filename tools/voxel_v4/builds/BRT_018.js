// BRT_018 Zibra Zubra Zibralini — Voxel V4 build (CP-B, Uncommon, revision 3).
// Revision 2 (owner): "use references online instead and go crazy v4". Revision 1's human legs in
// khakis are dropped. This follows the original meme image (brainrotcharacters.net and the image's
// alt text):
// - a whole round watermelon body, with a dark green rind and pale stripes
// - a cut at the chest showing red flesh with black seeds, where the zebra head joins
// - a bold black-and-white zebra head with an upright mane
// - four brown horse legs and a short dark tail; the original setting is a cactus desert
// - the Steal a Brainrot model adds brown boots to the front legs
// The V4 take, pushed bold:
// - the zebra neck bursts out of the cut red flesh on the chest
// - the gag: a desert cowboy zebra, with chestnut cowboy boots with gold stitching and glowing spurs
//   on the front legs, and neon-tipped mane spikes
// Revision 3 (owner): a longer body, zigzag stripes, brighter and higher-contrast greens; long, slim
//   zebra-striped legs with cowboy boots on all four.
// Rig-ready (owner rule): the front pair and the back pair of legs each match, in a neutral standing
// pose, with dark knee and hock collars.
// V4 core rules: kit anime eyes (Candy; thin lash line, small brows with a gap, catchlights, blush) on
// white eye domes, glowing Neon spurs and mane tips, light-up soles, studs on body panels only.
// Dopamine palette. Design units, y up, front = +x.
const K = typeof module !== 'undefined' ? require('../kit.js') : { createKit, skinFor, GLOBAL_PALETTES };
const kit = K.createKit();
const { S, B, MZ, frontEye } = kit;
const R = 1, E = 4;
const parts = kit.parts;
const DARK = '#1D2133';
const INK = '#141018';
const IVORY = '#FFF6DE';
const NOSE = '#3A3A46';
const HOOF = '#2A2230';

// octagon slice of a round watermelon lying along x (centre height CY)
const CY = 2.75;                                                // revision 3: raised for longer legs
function xslice(x0, x1, r, role, rel = R) {
	B(x0, x1, CY - r, CY + r, -0.7 * r, 0.7 * r, role, rel);
	B(x0, x1, CY - 0.66 * r, CY + 0.66 * r, -r, r, role, rel);
}

// --- long watermelon body (revision 3: longer; the middle slice's tall box is the Body)
S('Body');
B(-0.95, 0.95, CY - 0.85, CY + 0.85, -0.595, 0.595, 'upper', R);
S('Watermelon');
B(-0.95, 0.95, CY - 0.56, CY + 0.56, -0.85, 0.85, 'upper', R);
for (const [x0, x1, r] of [[-1.45, -1.25, 0.46], [-1.25, -0.95, 0.72], [0.95, 1.22, 0.72]]) xslice(x0, x1, r, 'upper');
// bold zigzag stripes running pole to pole (each stripe jogs from side to side every segment):
// top, upper diagonals, sides
S('RindStripe');
const SEGS = [[-1.25, -0.95, 0.72]];
for (let k = 0; k < 5; k++) SEGS.push([-0.95 + 0.38 * k, -0.95 + 0.38 * (k + 1), 0.85]);
SEGS.push([0.95, 1.22, 0.72]);
SEGS.forEach(([x0, x1, r], k) => {
	const j = k % 2 ? 0.07 : -0.07;                             // zigzag jog
	B(x0, x1, CY + r - 0.02, CY + r + 0.04, j - 0.12, j + 0.12, 'feather', 0);                 // top
	for (const s of [1, -1]) {
		const d = s > 0 ? [0.7 * r - 0.02, 0.7 * r + 0.06] : [-0.7 * r - 0.06, -0.7 * r + 0.02];
		B(x0, x1, CY + 0.6 * r + j, CY + 0.86 * r + j, ...d, 'feather', 0);                  // upper diagonal
		const sd = s > 0 ? [r - 0.02, r + 0.04] : [-r - 0.04, -r + 0.02];
		B(x0, x1, CY - 0.14 + j, CY + 0.14 + j, ...sd, 'feather', 0);                        // side
	}
});
// the chest is cut open: pale rind ring, red flesh, black seeds (the neck bursts out of it)
S('RindRing');
xslice(1.22, 1.26, 0.7, 'feather2', 0);
S('Flesh');
xslice(1.26, 1.3, 0.6, 'lower', R);
S('Seed');
for (const [y, z] of [[-0.3, -0.3], [-0.3, 0.3], [-0.05, -0.44], [-0.05, 0.44], [0.24, -0.4], [0.24, 0.4], [-0.44, 0]]) {
	B(1.3, 1.32, CY + y - 0.07, CY + y + 0.07, z - 0.04, z + 0.04, 'P', 0, INK);
}
// short dark zebra tail with a tuft
S('Tail');
B(-1.6, -1.42, CY - 0.3, CY + 0.25, -0.06, 0.06, 'skin2');
S('TailTuft');
B(-1.68, -1.4, CY - 0.7, CY - 0.26, -0.12, 0.12, 'skin2', R);

// --- black-and-white banded zebra neck bursting out of the flesh, upright striped mane with neon tips
S('Neck');
const NA = [1.3, CY + 0.2], NB = [1.72, CY + 1.2], NN = 5;
for (let k = 0; k < NN; k++) {
	const t = (k + 0.5) / NN, cx = NA[0] + (NB[0] - NA[0]) * t, cy = NA[1] + (NB[1] - NA[1]) * t;
	B(cx - 0.27, cx + 0.27, cy - 0.13, cy + 0.13, -0.24, 0.24, k % 2 ? 'skin2' : 'skin', R);
}
S('Mane');
for (let k = 0; k < NN; k++) {
	const t = (k + 0.5) / NN, cx = NA[0] + (NB[0] - NA[0]) * t, cy = NA[1] + (NB[1] - NA[1]) * t;
	B(cx - 0.38, cx - 0.14, cy, cy + 0.34, -0.08, 0.08, k % 2 ? 'skin' : 'skin2', 0);
	B(cx - 0.34, cx - 0.18, cy + 0.34, cy + 0.42, -0.05, 0.05, 'stripe', E);                // neon tip
}

// --- bold zebra head (built at unit scale, then scaled 1.25x onto the top of the neck): long striped
// muzzle, dark nose, buck-toothed grin, upright ears, forelock, huge anime eyes
const HEAD_START = parts.length;
S('Head');
B(1.04, 1.66, 3.72, 4.36, -0.31, 0.31, 'skin', R);
S('Muzzle');
B(1.6, 2.12, 3.54, 4.06, -0.25, 0.25, 'skin', R);
S('HeadStripe');
B(1.2, 1.3, 3.7, 4.38, -0.33, 0.33, 'skin2', 0);
for (const x of [1.74, 1.94]) B(x - 0.045, x + 0.045, 3.52, 4.08, -0.27, 0.27, 'skin2', 0);
S('Nose');
B(2.1, 2.3, 3.54, 4.02, -0.23, 0.23, 'P', 0, NOSE);
S('Nostril');
MZ(2.3, 2.32, 3.84, 3.94, 0.06, 0.15, 'P', 0, INK);
S('Mouth');
B(2.3, 2.32, 3.6, 3.7, -0.2, 0.2, 'P', 0, INK);
S('BuckTooth');
MZ(2.24, 2.33, 3.46, 3.64, 0.01, 0.1, 'P', 0, IVORY);
for (const s of [1, -1]) {
	S('Ear');
	B(1.1, 1.3, 4.34, 4.76, 0.1 * s, 0.28 * s, 'skin', R);
	S('EarTip');
	B(1.12, 1.28, 4.76, 4.9, 0.12 * s, 0.26 * s, 'skin2');
}
S('Forelock');
B(1.32, 1.5, 4.34, 4.56, -0.08, 0.08, 'skin2');
B(1.36, 1.5, 4.56, 4.68, -0.06, 0.06, 'skin');
const FX = 1.72;
for (const out of [1, -1]) {
	S('EyeDome');
	B(1.44, FX, 3.98, 4.58, 0.02 * out, 0.5 * out, 'P', 0, '#FFFFFF');
	const eye = frontEye({ faceX: FX, zc: 0.26 * out, top: 4.54, L: 0.88, H: 0.9, out, iris: 'Candy', lash: false, blush: true });
	const z0 = Math.min(eye.inner, eye.outer), z1 = Math.max(eye.inner, eye.outer), zm = (z0 + z1) / 2;
	S('Lash');
	B(FX, FX + 0.05, eye.whiteTop - 0.01, eye.whiteTop + 0.035, z0 - 0.01, z1 + 0.01, 'P', 0, '#000000');
	S('Brow');
	B(1.44, FX + 0.04, eye.whiteTop + 0.05, eye.whiteTop + 0.09, zm - 0.11, zm + 0.11, 'skin2');
}
// pivot (1.3, 3.86) moves onto the neck top and scales up 1.25x
const HP = [1.3, 3.86, 0], HT = [NB[0] + 0.02, NB[1] - 0.04, 0];
for (const p of parts.slice(HEAD_START)) for (const i of [0, 1, 2]) {
	p.min[i] = HT[i] + (p.min[i] - HP[i]) * 1.25; p.max[i] = HT[i] + (p.max[i] - HP[i]) * 1.25;
}

// --- four long, slim zebra-striped horse legs (revision 3), all four in chestnut cowboy boots with
// gold stitching, glowing spurs and light-up soles (front pair and back pair each match)
for (const s of [1, -1]) {
	const zc = 0.42 * s;
	for (const [lx, w] of [[0.66, 0.13], [-0.78, 0.15]]) {
		S('Leg');                                                   // upper leg: three black/white bands
		for (const [y0, y1, role] of [[1.66, 1.98, 'skin'], [1.39, 1.66, 'skin2'], [1.12, 1.39, 'skin']]) {
			B(lx - w, lx + w, y0, y1, zc - w, zc + w, role, R);
		}
		S('KneeCollar');
		B(lx - w + 0.01, lx + w - 0.01, 1.04, 1.12, zc - w + 0.01, zc + w - 0.01, 'P', 0, DARK);
		S('Leg');                                                   // lower leg: two bands above the boot
		B(lx - w + 0.02, lx + w - 0.02, 0.91, 1.04, zc - w + 0.02, zc + w - 0.02, 'skin2', R);
		B(lx - w + 0.02, lx + w - 0.02, 0.78, 0.91, zc - w + 0.02, zc + w - 0.02, 'skin', R);
		S('CowboyBoot');
		B(lx - 0.17, lx + 0.17, 0.04, 0.8, zc - 0.17, zc + 0.17, 'foot', R);
		B(lx + 0.17, lx + 0.38, 0.04, 0.26, zc - 0.14, zc + 0.14, 'foot');
		S('BootStitch');
		B(lx - 0.18, lx + 0.18, 0.62, 0.68, zc - 0.18, zc + 0.18, 'trim');
		S('Spur');
		B(lx - 0.29, lx - 0.17, 0.1, 0.2, zc - 0.05, zc + 0.05, 'stripe', E);
		S('Sole');
		B(lx - 0.17, lx + 0.38, 0, 0.04, zc - 0.17, zc + 0.17, 'accent', E);
	}
}

// Dopamine high-contrast palette (docs/creatures/V4/BRT_018_reference.md); mutations use the global palettes.
const PALETTES = Object.assign(
	{ normal: { upper: '#06702A', feather: '#C6FF2E', feather2: '#F2FFE0', lower: '#FF2D55', skin: '#FAFAFF', skin2: '#17171F', prop: '#C46A2A', foot: '#6E2A10', trim: '#FFC21A', stripe: '#FF2DD1', accent: '#2EF2FF', mode: 0 } },
	K.GLOBAL_PALETTES,
);
const skin = K.skinFor(parts, PALETTES);
if (typeof module !== 'undefined') module.exports = { parts, PALETTES, skin };
// Rig plan overrides for tools/voxel_v4/rig.js (owner, 7 Nov 2026: make the models riggable).
// Animation pass (13 Nov 2026): the neck and its mane get their own joint where the neck leaves the melon, the head
// turns at the top of the neck, and the mouth goes on the head (one mouth piece was left on the torso).
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	slots: { BuckTooth: 'Head', Mouth: 'Head' },
	neck: { pivot: [1.3, 2.95, 0], slots: ['Neck', 'Mane'] },
	headPivot: [1.72, 3.92, 0],
};
