// Voxel V4 design kit for new species (same conventions as the approved reference
// builds: design units, y up, nose/front = +x, z = left/right). Exports helpers and
// the anime-eye construction from the owner spec (section 2.4), measured against the
// approved BRT_019 eye so the proportions match exactly.
function createKit() {
	const R = 1, E = 4;
	const parts = [];
	let SLOT = 'Part';
	const S = (n) => { SLOT = n; };
	function B(x0, x1, y0, y1, z0, z1, role, flags = 0, col = null) {
		if (z0 > z1) [z0, z1] = [z1, z0];
		if (x0 > x1) [x0, x1] = [x1, x0];
		parts.push({ slot: SLOT, min: [x0, y0, z0], max: [x1, y1, z1], role, flags, col });
	}
	function MZ(x0, x1, y0, y1, z0, z1, role, flags, col) {
		B(x0, x1, y0, y1, z0, z1, role, flags, col);
		B(x0, x1, y0, y1, -z1, -z0, role, flags, col);
	}
	const IRIS = {
		Amber: ['#7a2a10', '#ff6a1a', '#ffcf45'], Ocean: ['#0b2e6b', '#1e8bff', '#7fe8ff'],
		Candy: ['#6b0f45', '#ff3da8', '#ffb3e0'], Lime: ['#1f4a0b', '#45d11e', '#c8ff6a'],
		Violet: ['#2e0f6b', '#8a4dff', '#d8b8ff'], Ruby: ['#5a0a14', '#f0283c', '#ff9aa5'],
	};
	// Front-facing anime eye on a panel whose face is at x = faceX (eye looks along +x).
	// u runs along z; `out` (+1/-1) is the outer side, which plays the role of the
	// side eye's "rear" (wing flick, big catchlight, blush). L/H are the eye panel.
	function frontEye({ faceX, zc, top, L, H, out, iris, lash = true, blush = true }) {
		const [dark, mid, bright] = IRIS[iris];
		const u = (a, b) => { const p = zc + out * a, q = zc + out * b; return [Math.min(p, q), Math.max(p, q)]; };
		const coreW = 0.48 * L, coreH = 0.67 * H, wideW = 0.58 * L, inset = 0.06 * H;
		const y0 = top - coreH, y1 = top;
		const d = (a, b) => [faceX + a, faceX + b];
		S('EyeWhite');
		B(...d(0, 0.04), y0, y1, ...u(-coreW / 2, coreW / 2), 'P', 0, '#ffffff');
		B(...d(0, 0.04), y0 + inset, y1 - inset, ...u(-wideW / 2, wideW / 2), 'P', 0, '#ffffff');
		// iris: 68% of white width x 84% of white height, bands bottom->top 27/33/40
		const iw = 0.68 * wideW, ih = 0.84 * coreH, ib = y0 + 0.042 * coreH;
		S('Iris');
		B(...d(0.04, 0.07), ib + 0.60 * ih, ib + ih, ...u(-iw / 2, iw / 2), 'P', 0, dark);
		B(...d(0.04, 0.07), ib + 0.27 * ih, ib + 0.60 * ih, ...u(-iw / 2, iw / 2), 'P', 0, mid);
		B(...d(0.04, 0.07), ib, ib + 0.27 * ih, ...u(-iw / 2, iw / 2), 'P', 0, bright);
		// pupil 49% x 47% of iris, centred, top 0.30 (scaled from the 2.45-unit head) below iris top
		const pw = 0.49 * iw, ph = 0.47 * ih, pTop = ib + ih - 0.30 * (H / 2.45);
		S('Pupil');
		B(...d(0.07, 0.1), pTop - ph, pTop, ...u(-pw / 2, pw / 2), 'P', 0, '#1a0b06');
		S('Catchlight');
		// big 38% x 28%, upper-outer overlapping the pupil corner
		const bw = 0.38 * iw, bh = 0.28 * ih, bTop = pTop + 0.16 * (H / 2.45);
		B(...d(0.1, 0.12), bTop - bh, bTop, ...u(iw / 2 - 0.1 * (L / 2.4) - bw, iw / 2 - 0.1 * (L / 2.4)), 'P', E, '#ffffff');
		// small 19% x 13%, lower-inner
		const sw = 0.19 * iw, sh = 0.13 * ih, sBottom = ib + 0.13 * ih;
		B(...d(0.1, 0.12), sBottom, sBottom + sh, ...u(-iw / 2 + 0.11 * (L / 2.4), -iw / 2 + 0.11 * (L / 2.4) + sw), 'P', E, '#ffffff');
		// sparkle 8% x 6%, upper-inner of the pupil
		const kw = 0.08 * iw, kh = 0.06 * ih, kTop = pTop - 0.14 * (H / 2.45);
		B(...d(0.1, 0.12), kTop - kh, kTop, ...u(-pw / 2 - 0.02, -pw / 2 - 0.02 + kw), 'P', E, '#ffffff');
		// upper lash 0.10H, overhanging both ends; wing flick up at the outer end; inner end droops
		const lashBottom = y1 - 0.08 * (H / 2.45), lashTop = lashBottom + 0.10 * H;
		if (lash) {
			S('Lash');
			B(...d(0, 0.14), lashBottom, lashTop, ...u(-wideW / 2 - 0.06, wideW / 2 + 0.08), 'P', 0, '#000000');
			B(...d(0, 0.14), lashTop - 0.11 * H, lashTop + 0.08 * H, ...u(wideW / 2 - 0.05, wideW / 2 + 0.12 * L + 0.03), 'P', 0, '#000000');
			B(...d(0, 0.14), lashBottom - 0.07 * H, lashBottom, ...u(-wideW / 2 - 0.1, -wideW / 2 + 0.1), 'P', 0, '#000000');
		}
		if (blush) {
			// blush 0.29L x 0.10H under the outer half
			S('Blush');
			B(...d(0, 0.04), y0 - 0.10 * H - 0.04, y0 - 0.04, ...u(0, 0.29 * L), 'P', E, '#ff6fa3');
		}
		// geometry for callers that build their own lids/brows
		return { lashTop: lashTop + 0.08 * H, bottom: y0 - 0.10 * H - 0.04, whiteTop: y1, whiteBottom: y0, pupilTop: pTop, inner: zc - out * wideW / 2, outer: zc + out * wideW / 2 };
	}
	return { parts, S, B, MZ, frontEye, R, E };
}
function skinFor(parts, PALETTES) {
	return (name) => {
		const p = PALETTES[name];
		return parts.map((b) => ({ min: b.min, max: b.max, flags: b.flags | (b.role !== 'P' ? 2 : 0), col: b.role === 'P' ? b.col : p[b.role] }));
	};
}
const GLOBAL_PALETTES = {
	shiny: { upper: '#FF87B7', lower: '#FFF4CD', stripe: '#FFFFFF', trim: '#FFE3EE', skin: '#FFE0EC', skin2: '#FFB6D3', feather: '#FF5FA0', feather2: '#FFFFFF', foot: '#FF9CC6', prop: '#FFF4CD', accent: '#FF87B7', mode: 5 },
	golden: { upper: '#D99510', lower: '#FFD447', stripe: '#FFF0A3', trim: '#FFE27A', skin: '#FFD447', skin2: '#E5A520', feather: '#8C4A08', feather2: '#FFF0A3', foot: '#D99510', prop: '#FFD447', accent: '#FFF0A3', mode: 1 },
	glitched: { upper: '#FF49E1', lower: '#2B0F52', stripe: '#3EFFF0', trim: '#5A1F9A', skin: '#FF8AF0', skin2: '#3EFFF0', feather: '#2B0F52', feather2: '#FF49E1', foot: '#3EFFF0', prop: '#FF49E1', accent: '#3EFFF0', mode: 4 },
	radioactive: { upper: '#DCFF2B', lower: '#182018', stripe: '#DCFF2B', trim: '#2A3A20', skin: '#C9FF5A', skin2: '#9FE01A', feather: '#182018', feather2: '#DCFF2B', foot: '#DCFF2B', prop: '#182018', accent: '#DCFF2B', mode: 2 },
	astral: { upper: '#6D74FF', lower: '#2A1F6E', stripe: '#EDE0FF', trim: '#3B2F8F', skin: '#C4B6FF', skin2: '#8F80FF', feather: '#140D38', feather2: '#EDE0FF', foot: '#6D74FF', prop: '#6D74FF', accent: '#EDE0FF', mode: 3 },
};
if (typeof module !== 'undefined') module.exports = { createKit, skinFor, GLOBAL_PALETTES };
