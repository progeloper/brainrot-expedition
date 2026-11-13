// Voxel V4 rig planner (owner, 7 Nov 2026: "make them riggable"). Pure function of a design build's boxes plus
// optional per-species `rigOverrides` exported by the build. Produces a Motor6D bone hierarchy in DESIGN units
// (y up, front = +x, z = left/right). The Luau builder turns it into invisible bone parts, Motor6D joints and
// WeldConstraints. Side naming follows the creature facing its front: +z is its Right, -z its Left (design z maps
// to model X, and the model faces -Z).
//
// Bones: Torso (child of Root); Head (if the species has a separate head); legs and arms per side (with a lower
// segment where a knee/elbow collar exists); wings per side; Tail. Everything not matched stays on the Torso.
const LEG = /^(Leg|Legs|Thigh|Shin|Calf|Knee|KneeCollar|KneeJoint|KneeGuard|HipCollar|LegCollar|AnkleCollar|Foot|Feet|Sole|Sneaker|SneakerStripe|SneakerToe|Shoe|Boot|BootCuff|BootShaft|BootSole|BootStitch|CowboyBoot|Spur|Lace|Laces|Midsole|HeelTab|HighTop|HighTopCollar|ToeCap|Toe|ToeNail|Toenail|Spat|Ribbon|PointeShoe|SandalSole|SandalStrap|SlipperSole|SlipperTrim|SlipperUpper|Web|ScaleRing|ShortsLeg|UpperLeg|LowerLeg|FrontThigh|FrontShin|FrontFoot|FrontSole|FrontKneeCollar|FrontHipCollar|BackThigh|BackShin|BackFoot|BackSole|BackKneeCollar|BackHipCollar|RearLeg|FinLeg|TailLeg|CactusToe)$/;
const ARM = /^(Arm|UpperArm|Forearm|Biceps|Bicep|Deltoid|ElbowCollar|WristCollar|Wristband|ShoulderCollar|Hand|Hand_R|Glove|GloveCuff|Fist|Finger|FingerBone|Thumb|Knuckle|Armband|Bracer|Pauldron|PauldronSpike|PauldronTrim|CactusArm|Flipper|FlipperEdge|WristClaw)$/;
const WING = /^(Wing|WingBar|WingBone|WingCovert|WingPanel|WingRoot|WingTrim|FlightFeather|PrimaryFeather|Chevron)$/;
const TAIL = /^(Tail|TailBase|TailBelly|TailFin|TailHatch|TailPlume|TailRidge|TailSpade|TailTip|TailTuft|Fluke|FlukeGlow|CaudalFin)$/;
const HEAD_CORE = /^(Head|HeadDome|HeadJaw|HeadStripe|Snout|SnoutJaw|SnoutTip|SnoutTipJaw|Muzzle|Face|Jaw|LowerJaw|Beak|BeakTip|Mandible)$/;
const KNEE = /Knee/;
const ELBOW = /^ElbowCollar$/;
const UPPER_LEG = /^(HipCollar|FrontHipCollar|BackHipCollar|Thigh|FrontThigh|BackThigh|UpperLeg)$/;
const UPPER_ARM = /^(ShoulderCollar|Shoulder|Deltoid|UpperArm|Biceps|Bicep|Armband|Pauldron|PauldronTrim|PauldronSpike)$/;
const HEAD_ATTACH = /^(Ear|EarTip|InnerEar|EarGlow|Horn|Crown|CrownGem|HatBrim|HatCrown|HatBand|HatBuckle|Helmet|HelmetBand|HelmetLamp|VisorRim|Antenna|Ossicone|Crest|Tusk|Trunk|TrunkTip|TrunkWrinkle|GoggleFrame|GoggleLens|GoggleRing|GoggleStrap|ShadeFrame|ShadeLens|ShadeArm|ShadeBridge|Whisker|Beard|Forelock|Lid|ScowlLid|BrowRidge|Cheekbone|ChinTuft|BuckTooth|GoldTooth|Fang|Tooth|Teeth|Tongue|Mouth|Nose|NosePad|NoseRing|Nostril|EyeDome|EyePatch|EyeWhite|Iris|Pupil|Catchlight|Lash|LashLine|Brow|Blush|Cheek|Lip|Tear|Headlamp|HeadlampLens|ToothSparkle|Blaze|Spot|FaceSpot|Tuft)$/;

const centre = (p) => [(p.min[0] + p.max[0]) / 2, (p.min[1] + p.max[1]) / 2, (p.min[2] + p.max[2]) / 2];
const r3 = (v) => v.map((n) => Math.round(n * 1000) / 1000);

function bbox(list) {
	const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
	for (const p of list) for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], p.min[i]); hi[i] = Math.max(hi[i], p.max[i]); }
	return { lo, hi };
}

// cluster boxes whose x-intervals overlap (legs/arms at different x on one side)
function clusterX(list) {
	const sorted = [...list].sort((a, b) => a.min[0] - b.min[0]);
	const groups = [];
	for (const p of sorted) {
		const g = groups[groups.length - 1];
		if (g && p.min[0] <= g.hi + 0.02) { g.items.push(p); g.hi = Math.max(g.hi, p.max[0]); }
		else groups.push({ items: [p], hi: p.max[0] });
	}
	return groups.map((g) => g.items);
}

// fold clusters of fewer than 3 boxes into the nearest bigger cluster (stray heel tabs, toe caps)
function mergeSmall(clusters) {
	if (clusters.length < 2) return clusters;
	const big = clusters.filter((c) => c.length >= 3);
	if (!big.length) return clusters;
	const mid = (cl) => { const b = bbox(cl); return (b.lo[0] + b.hi[0]) / 2; };
	for (const c of clusters) if (c.length < 3) {
		const m = mid(c);
		big.reduce((a, g) => (Math.abs(mid(g) - m) < Math.abs(mid(a) - m) ? g : a)).push(...c);
	}
	return big;
}

function sideOf(p) {
	const z = centre(p)[2];
	return Math.abs(z) < 0.08 ? 'Centre' : z > 0 ? 'Right' : 'Left';
}

function planRig(parts, ov = {}) {
	const bone = new Array(parts.length).fill('Torso');
	const slotBone = ov.slots || {};
	const kind = (p) => {
		if (slotBone[p.slot]) return 'forced';
		if (ov.noLegs !== true && LEG.test(p.slot)) return 'leg';
		if (ov.noArms !== true && ARM.test(p.slot)) return 'arm';
		if (WING.test(p.slot)) return 'wing';
		if (ov.noTail !== true && TAIL.test(p.slot)) return 'tail';
		return null;
	};
	const bones = [];
	const add = (name, parent, pivot) => { bones.push({ name, parent, pivot: r3(pivot) }); return name; };

	// --- torso pivot: centre of the Body box (largest upper box)
	let body = null, bv = -1;
	parts.forEach((p) => { if (p.role === 'upper') { const v = (p.max[0] - p.min[0]) * (p.max[1] - p.min[1]) * (p.max[2] - p.min[2]); if (v > bv) { bv = v; body = p; } } });
	const torsoPivot = ov.torsoPivot || centre(body);
	add('Torso', 'Root', torsoPivot);

	// --- limbs
	const limb = { leg: [], arm: [], wing: [], tail: [] };
	parts.forEach((p, i) => { const k = kind(p); if (k && k !== 'forced') limb[k].push(i); });

	const sideGroups = (idx) => {
		const by = { Left: [], Right: [], Centre: [] };
		for (const i of idx) by[sideOf(parts[i])].push(i);
		return by;
	};
	const posName = (n, k) => (n === 1 ? [''] : n === 2 ? ['Front', 'Back'] : n === 3 ? ['Front', 'Middle', 'Back'] : Array.from({ length: n }, (_, j) => 'Pair' + (j + 1)))[k];

	// legs: hip at the top of the upper segment; knee where a knee collar exists (split by part names, else height)
	const legs = sideGroups(limb.leg);
	for (const side of ['Right', 'Left', 'Centre']) {
		let clusters = clusterX(legs[side].map((i) => Object.assign({ i }, parts[i]))).sort((a, b) => bbox(b).hi[0] - bbox(a).hi[0]);
		clusters = mergeSmall(clusters);
		clusters.forEach((cl, k) => {
			const pre = posName(clusters.length, k) + side;
			const ups = cl.filter((c) => UPPER_LEG.test(c.slot));
			const top = (ups.length ? ups : cl).reduce((a, c) => (c.max[1] > a.max[1] ? c : a));
			const hipC = ups.find((c) => /HipCollar/.test(c.slot)) || top;
			const hip = add(pre + 'Leg', 'Torso', [(hipC.min[0] + hipC.max[0]) / 2, hipC.max[1], (hipC.min[2] + hipC.max[2]) / 2]);
			const knee = cl.find((c) => KNEE.test(c.slot));
			if (!knee || ov.noKnees === true) { for (const c of cl) bone[c.i] = hip; return; }
			const lower = add(pre + 'LowerLeg', hip, centre(knee));
			const byName = ups.length > 0 && ov.kneeByHeight !== true;
			const ky = centre(knee)[1];
			for (const c of cl) bone[c.i] = KNEE.test(c.slot) ? lower : byName ? (UPPER_LEG.test(c.slot) ? hip : lower) : centre(c)[1] < ky ? lower : hip;
		});
	}
	// arms: shoulder at the inner face of the innermost box (raised and hanging arms both work); elbow collar splits
	const arms = sideGroups(limb.arm);
	for (const side of ['Right', 'Left']) {
		const items = arms[side].map((i) => Object.assign({ i }, parts[i]));
		if (!items.length) continue;
		const clusters = ov.armClusterX ? mergeSmall(clusterX(items)) : [items];
		clusters.forEach((cl, k) => {
			const pre = posName(clusters.length, k) + side;
			const ups = cl.filter((c) => UPPER_ARM.test(c.slot));
			const pool = ups.length ? ups : cl;
			const inner = pool.reduce((a, c) => (Math.min(Math.abs(c.min[2]), Math.abs(c.max[2])) < Math.min(Math.abs(a.min[2]), Math.abs(a.max[2])) ? c : a));
			const zi = Math.abs(inner.min[2]) < Math.abs(inner.max[2]) ? inner.min[2] : inner.max[2];
			const sh = add(pre + 'Arm', 'Torso', ov.shoulderY != null ? [(inner.min[0] + inner.max[0]) / 2, ov.shoulderY, zi] : [(inner.min[0] + inner.max[0]) / 2, (inner.min[1] + inner.max[1]) / 2, zi]);
			const elbow = cl.find((c) => ELBOW.test(c.slot));
			if (!elbow || ov.noElbows === true || !ups.length) { for (const c of cl) bone[c.i] = sh; return; }
			const lower = add(pre + 'Forearm', sh, centre(elbow));
			for (const c of cl) bone[c.i] = UPPER_ARM.test(c.slot) ? sh : lower;
		});
	}
	// wings: root at the inner face
	const wings = sideGroups(limb.wing);
	for (const side of ['Right', 'Left']) {
		const cl = wings[side].map((i) => Object.assign({ i }, parts[i]));
		if (!cl.length) continue;
		const b = bbox(cl);
		const zi = side === 'Right' ? b.lo[2] : b.hi[2];
		const w = add(side + 'Wing', 'Torso', [(b.lo[0] + b.hi[0]) / 2, (b.lo[1] + b.hi[1]) / 2, zi]);
		for (const c of cl) bone[c.i] = w;
	}
	// tail: root at the end nearest the body (largest x), mid height
	if (limb.tail.length) {
		const cl = limb.tail.map((i) => Object.assign({ i }, parts[i]));
		const b = bbox(cl);
		const near = cl.reduce((a, c) => (c.max[0] > a.max[0] ? c : a));
		const t = add('Tail', 'Torso', ov.tailPivot || [b.hi[0], (near.min[1] + near.max[1]) / 2, 0]);
		for (const c of cl) bone[c.i] = t;
	}

	// --- head: core head slots plus anything whose centre sits in the head region (face, ears, horns, hats)
	if (ov.noHead !== true) {
		const core = parts.map((p, i) => (HEAD_CORE.test(p.slot) && bone[i] === 'Torso' && p !== body ? i : -1)).filter((i) => i >= 0);
		if (core.length) {
			const b = bbox(core.map((i) => parts[i]));
			const m = ov.headMargin ?? 0.3, up = ov.headUp ?? 1.6;
			const lo = [b.lo[0] - m, b.lo[1] - m, b.lo[2] - m], hi = [b.hi[0] + m, b.hi[1] + up, b.hi[2] + m];
			const heads = core.map((i) => parts[i]).filter((p) => p.slot === 'Head');
			const neckY = ov.neckY ?? (heads.length ? Math.min(...heads.map((p) => p.min[1])) : b.lo[1]);
			// optional neck bone between Torso and Head (rigOverrides.neck = { pivot, slots }); opt-in per species.
			// neck.base = { pivot } adds a NeckBase bone under it for a two-joint neck (a long S-shaped neck):
			// Torso > NeckBase > Neck > Head. Boxes are moved onto NeckBase with a `regions` entry.
			const neckBase = ov.neck && ov.neck.base ? add('NeckBase', 'Torso', ov.neck.base.pivot) : null;
			const neck = ov.neck ? add('Neck', neckBase || 'Torso', ov.neck.pivot) : null;
			const h = add('Head', neck || 'Torso', ov.headPivot || [(b.lo[0] + b.hi[0]) / 2, neckY, 0]);
			parts.forEach((p, i) => {
				if (bone[i] !== 'Torso' || p === body) return;
				const c = centre(p);
				const attach = HEAD_ATTACH.test(p.slot) || HEAD_CORE.test(p.slot);
				const e = attach ? (ov.headAttachMargin ?? 0.8) : 0.15;
				// attachments: centre inside the loose region; anything else must sit fully inside the head region
				const inside = attach
					? c[0] >= lo[0] - e && c[0] <= hi[0] + e && c[1] >= neckY - 0.02 && c[1] <= hi[1] + 2 * e && c[2] >= lo[2] - e && c[2] <= hi[2] + e
					: p.min[0] >= lo[0] - e && p.max[0] <= hi[0] + e && p.min[1] >= neckY - 0.05 && p.max[1] <= hi[1] + e && p.min[2] >= lo[2] - e && p.max[2] <= hi[2] + e;
				if (inside) bone[i] = h;
			});
		}
	}

	// --- attach small unassigned pieces (claws, toe caps, paws) that touch a limb and sit on no bigger torso box
	if (ov.noAttach !== true) {
		const vol = (p) => (p.max[0] - p.min[0]) * (p.max[1] - p.min[1]) * (p.max[2] - p.min[2]);
		const touch = (p, q, t = 0.021) => p.min[0] <= q.max[0] + t && p.max[0] >= q.min[0] - t && p.min[1] <= q.max[1] + t && p.max[1] >= q.min[1] - t && p.min[2] <= q.max[2] + t && p.max[2] >= q.min[2] - t;
		for (let pass = 0; pass < 2; pass++) {
			parts.forEach((p, i) => {
				if (bone[i] !== 'Torso' || p === body || HEAD_ATTACH.test(p.slot)) return;
				const v = vol(p);
				let onTorso = false, best = null, bestV = -1;
				parts.forEach((q, j) => {
					if (i === j || !touch(p, q)) return;
					if (bone[j] === 'Torso') { if (vol(q) >= v) onTorso = true; }
					else if (bone[j] !== 'Head' && vol(q) > bestV) { best = bone[j]; bestV = vol(q); }
				});
				if (best && !onTorso && v <= 0.5 * bestV * 4) bone[i] = best;
			});
		}
	}

	// --- explicit slot assignments last (props in hands etc.)
	if (ov.neck) parts.forEach((p, i) => { if (ov.neck.slots.includes(p.slot)) bone[i] = 'Neck'; });
	parts.forEach((p, i) => { if (slotBone[p.slot]) bone[i] = slotBone[p.slot].replace('{side}', sideOf(p)); });
	for (const [name, b] of Object.entries(ov.extraBones || {})) add(name, b.parent, b.pivot);
	// region assignments: [{ bone, region: [x0,x1,y0,y1,z0,z1] }] applied last
	for (const r of ov.regions || []) {
		const [x0, x1, y0, y1, z0, z1] = r.region;
		parts.forEach((p, i) => { const c = centre(p); if (c[0] >= x0 && c[0] <= x1 && c[1] >= y0 && c[1] <= y1 && c[2] >= z0 && c[2] <= z1 && (!r.only || r.only.test(p.slot))) bone[i] = r.bone; });
	}
	// drop bones with no parts and no children
	const used = new Set(bone);
	const keep = bones.filter((b) => b.name === 'Torso' || used.has(b.name) || bones.some((c) => c.parent === b.name && used.has(c.name)));
	return { bones: keep, bone };
}

if (typeof module !== 'undefined') module.exports = { planRig };
