// Proves a slot-labelled build is geometrically identical to the approved reference build.
const [,, ref, labelled] = process.argv;
const a = require(require('path').resolve(ref)), b = require(require('path').resolve(labelled));
const strip = p => p.map(x => JSON.stringify([x.min, x.max, x.role, x.flags, x.col]));
const A = strip(a.parts), Bp = strip(b.parts);
const same = A.length === Bp.length && A.every((v, i) => v === Bp[i]) && JSON.stringify(a.PALETTES) === JSON.stringify(b.PALETTES);
console.log(JSON.stringify({ reference: ref, boxes: A.length, identical: same, unlabelled: b.parts.filter(p => p.slot === 'Part').length }));
process.exit(same ? 0 : 1);
