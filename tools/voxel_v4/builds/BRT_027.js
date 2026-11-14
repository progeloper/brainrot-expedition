// BRT_027 Tralalero Tralala — Voxel V4 reference build (approved 3 Nov 2026). Worked example of the per-brainrot workflow.
// Steal a Brainrot reference: blue shark, three fin-legs in blue sneakers, smile, three black back stripes, white belly.
// BRT_027 Tralalero Tralala — Voxel V4 (reference: blue shark, three fin-legs in blue sneakers, smile, three black back stripes)
// units = design units, y up, nose = +x. Same role system as BRT_019.
const R=1,E=4;
const parts=[];let SLOT='Part';function S(n){SLOT=n;}
function B(x0,x1,y0,y1,z0,z1,role,flags=0,col=null){if(z0>z1)[z0,z1]=[z1,z0];parts.push({slot:SLOT,min:[x0,y0,z0],max:[x1,y1,z1],role,flags,col});}
function MZ(x0,x1,y0,y1,z0,z1,role,flags,col){B(x0,x1,y0,y1,z0,z1,role,flags,col);B(x0,x1,y0,y1,-z1,-z0,role,flags,col);}
const DARK='#1D2133';

// --- torpedo body: [x0,x1,yBottom,yTop,halfWidth,relief]
const secs=[
 [-5.0,-3.9,3.55,4.55,0.5,1],
 [-3.9,-2.7,3.15,4.95,0.85,1],
 [-2.7,-1.2,2.85,5.3,1.15,1],
 [-1.2,0.5,2.65,5.55,1.32,1],
 [0.5,3.0,2.6,6.3,1.38,0],   // head (no studs: eye panel)
 [3.0,3.85,2.8,5.75,1.2,0],
 [3.85,4.55,3.15,5.15,0.92,0],
 [4.55,5.0,3.55,4.55,0.55,0]];
S('BodySection');for(const [x0,x1,yb,yt,hw,rel] of secs){
  const yw=yb+0.42*(yt-yb);           // countershading waterline
  B(x0,x1,yb,yw,-hw,hw,'lower',rel?R:0);
  B(x0,x1,yw,yw+0.16,-hw-0.02,hw+0.02,'stripe',E);
  B(x0,x1,yw+0.16,yt,-hw,hw,'upper',rel?R:0);
}
// --- three black back stripes (reference detail) wrapping the top
S('BackStripe');for(const x of [-2.55,-1.75,-0.95]){
  const hw=x<-1.2?1.15:1.32, top=x<-1.2?5.3:5.55;
  B(x,x+0.36,top,top+0.04,-hw,hw,'P',0,DARK);
  MZ(x,x+0.36,3.95,top,hw,hw+0.03,'P',0,DARK);
}
// --- dorsal fin (stepped, swept back)
S('DorsalFin');B(-1.4,0.5,5.55,6.25,-0.28,0.28,'upper',R);
B(-1.3,0.0,6.25,6.95,-0.24,0.24,'upper',R);
B(-1.15,-0.45,6.95,7.6,-0.2,0.2,'upper',R);
B(-1.05,-0.75,7.6,7.95,-0.16,0.16,'upper',R);
// --- caudal fin: upper lobe up and back
S('CaudalFin');B(-5.8,-4.9,4.3,5.0,-0.3,0.3,'upper',R);
B(-6.4,-5.5,4.9,5.7,-0.26,0.26,'upper',R);
B(-6.9,-6.1,5.6,6.5,-0.22,0.22,'upper',R);

// --- sneaker builder (chunky light-up kicks; no logos)
function shoe(x,z,len){ // x = heel, toe at +x
  S('Sneaker');
  B(x,x+len,0,0.22,z-0.42,z+0.42,'accent',E);                 // light-up sole
  B(x,x+len,0.22,0.46,z-0.42,z+0.42,'trim');                 // white midsole
  B(x+0.05,x+len-0.3,0.46,1.05,z-0.38,z+0.38,'foot',R);      // upper
  B(x+len-0.32,x+len,0.46,0.85,z-0.36,z+0.36,'foot');        // toe cap
  B(x+len-0.3,x+len+0.02,0.46,0.6,z-0.37,z+0.37,'trim');     // toe bumper
  for(const lx of [x+0.5,x+0.85,x+1.2]) B(lx,lx+0.22,1.05,1.14,z-0.24,z+0.24,'trim'); // laces
  B(x+0.05,x+len-0.35,0.62,0.78,z+0.38,z+0.41,'trim');        // side flash
  B(x+0.05,x+len-0.35,0.62,0.78,z-0.41,z-0.38,'trim');
  B(x-0.06,x+0.22,0.5,1.15,z-0.2,z+0.2,'accent',E);          // glowing heel tab
  B(x+0.05,x+0.75,1.05,1.25,z-0.36,z+0.36,'P',0,DARK);        // ankle collar
}
// --- pectoral fin-legs (front pair)
for(const s of [1,-1]){
  const z=1.05*s;
  S('FinLeg');
  B(0.3,1.9,2.25,2.75,z-0.35,z+0.35,'upper',R);   // fin root
  B(0.2,1.6,2.6,2.85,z+0.25*s,z+0.85*s,'upper',R); B(0.0,1.0,2.45,2.65,z+0.7*s,z+1.05*s,'upper',R); // flared fin
  B(0.55,1.45,1.25,2.3,z-0.3,z+0.3,'upper',R);    // thigh
  B(0.7,1.3,1.2,1.3,z-0.28,z+0.28,'upper');
  S('Sneaker');
  shoe(0.2,z,1.75);
}
// --- third leg from the tail (lower caudal lobe becomes the leg)
S('TailLeg');B(-5.2,-4.3,2.6,3.6,-0.32,0.32,'upper',R);
B(-5.15,-4.4,1.25,2.6,-0.3,0.3,'upper',R);
S('Sneaker');shoe(-5.45,0,1.75);

// --- face: anime eyes (same spec as BRT_019), gills, grin with teeth
for(const s of [1,-1]){
  const zz=(a,b)=>s>0?[a,b]:[-b,-a];
  const zf=1.38;
  const [w0,w1]=zz(zf,zf+0.04),[i0,i1]=zz(zf+0.04,zf+0.07),[p0,p1]=zz(zf+0.07,zf+0.1),[c0,c1]=zz(zf+0.1,zf+0.12);
  const X=1.45; // eye rear x
  S('EyeWhite');
  B(X+0.12,X+1.27,4.20,5.85,w0,w1,'P',0,'#ffffff'); B(X,X+1.39,4.35,5.70,w0,w1,'P',0,'#ffffff');
  S('Iris');
  B(X+0.22,X+1.17,5.10,5.65,i0,i1,'P',0,'#7a2a10');
  B(X+0.22,X+1.17,4.65,5.10,i0,i1,'P',0,'#ff6a1a');
  B(X+0.22,X+1.17,4.27,4.65,i0,i1,'P',0,'#ffcf45');
  S('Pupil');
  B(X+0.47,X+0.94,4.70,5.35,p0,p1,'P',0,'#1a0b06');
  S('Catchlight');
  B(X+0.32,X+0.68,5.13,5.51,c0,c1,'P',E,'#ffffff');
  B(X+0.88,X+1.06,4.45,4.63,c0,c1,'P',E,'#ffffff');
  B(X+1.0,X+1.08,5.21,5.29,c0,c1,'P',E,'#ffffff');
  const [l0,l1]=zz(zf,zf+0.14);
  S('Lash');
  B(X-0.06,X+1.47,5.77,6.01,l0,l1,'P',0,'#000000');
  B(X-0.28,X+0.02,5.90,6.20,l0,l1,'P',0,'#000000');
  B(X+1.32,X+1.52,5.65,5.83,l0,l1,'P',0,'#000000');
  S('Blush');
  B(X+0.05,X+0.75,3.80,4.05,w0,w1,'P',E,'#ff6fa3');            // blush
  // gill slits behind the eye
  S('Gill');
  for(const gx of [0.75,0.95,1.15]) B(gx-0.05,gx+0.05,3.95,4.95,...zz(1.38,1.41),'P',0,DARK);
}
// grin: dark mouth band wrapping snout front + both sides, white teeth row, tongue, upturned corners
S('Mouth');B(2.3,4.6,3.25,3.62,-1.0,1.0,'P',0,'#6e0e2c');
B(4.6,4.72,3.4,3.62,-0.5,0.5,'P',0,'#6e0e2c');
for(const [x0,x1,hw] of [[2.25,3.0,1.38],[3.0,3.85,1.2],[3.85,4.55,0.92],[4.55,4.72,0.55]]){
  S('Mouth');MZ(x0,x1,3.25,3.62,hw,hw+0.03,'P',0,'#6e0e2c');
  S('Teeth');
  for(let tx=x0+0.06;tx+0.2<=x1;tx+=0.34) MZ(tx,tx+0.2,3.47,3.62,hw+0.03,hw+0.05,'P',0,'#ffffff');
}
S('Mouth');MZ(2.0,2.3,3.4,3.85,1.38,1.41,'P',0,'#6e0e2c');
MZ(1.85,2.1,3.75,4.0,1.38,1.41,'P',0,'#6e0e2c');
S('Teeth');B(4.62,4.73,3.62,3.68,-0.5,0.5,'P',0,'#ffffff');
S('Tongue');B(2.8,4.4,3.25,3.36,-0.7,0.7,'P',0,'#ff4f7a');
MZ(3.0,3.8,3.25,3.34,1.23,1.24,'P',0,'#ff4f7a');
// nostrils
S('Nostril');MZ(4.3,4.5,5.15,5.19,0.3,0.5,'P',0,DARK);

const PALETTES={
 normal:{upper:'#3A9BFF',lower:'#F7F5FC',stripe:'#2EE9FF',trim:'#F7F5FC',foot:'#1E6BFF',accent:'#2EE9FF',mode:0},
 shiny:{upper:'#FF87B7',lower:'#FFF4CD',stripe:'#FFFFFF',trim:'#FFE3EE',foot:'#FF9CC6',accent:'#FF87B7',mode:5},
 golden:{upper:'#D99510',lower:'#FFD447',stripe:'#FFF0A3',trim:'#FFE27A',foot:'#D99510',accent:'#FFF0A3',mode:1},
 glitched:{upper:'#FF49E1',lower:'#2B0F52',stripe:'#3EFFF0',trim:'#5A1F9A',foot:'#3EFFF0',accent:'#3EFFF0',mode:4},
 radioactive:{upper:'#DCFF2B',lower:'#182018',stripe:'#DCFF2B',trim:'#2A3A20',foot:'#DCFF2B',accent:'#DCFF2B',mode:2},
 astral:{upper:'#6D74FF',lower:'#2A1F6E',stripe:'#EDE0FF',trim:'#3B2F8F',foot:'#6D74FF',accent:'#EDE0FF',mode:3}
};
function skin(name){const p=PALETTES[name];return parts.map(b=>({min:b.min,max:b.max,flags:b.flags|(b.role!=='P'?2:0),col:b.role==='P'?b.col:p[b.role]}));}

if (typeof module!=='undefined') module.exports={parts,PALETTES,skin};
// Rig plan overrides for tools/voxel_v4/rig.js. Animation pass (13 Nov 2026): the front of the shark (the head and
// snout, with the face) gets a head joint where it meets the body; each leg gets a knee where the sneaker meets the
// fin-leg; every piece of the tail leg's sneaker goes on the tail leg (its two side flashes were on the front legs); and
// the wide root fins at the top of each fin-leg stay on the body, so only the thigh and sneaker swing.
if (typeof module !== 'undefined') module.exports.rigOverrides = {
	extraBones: {
		Head: { parent: 'Torso', pivot: [0.5, 4.3, 0] },
		RightLowerLeg: { parent: 'RightLeg', pivot: [1.0, 1.25, 1.05] },
		LeftLowerLeg: { parent: 'LeftLeg', pivot: [1.0, 1.25, -1.05] },
		CentreLowerLeg: { parent: 'CentreLeg', pivot: [-4.77, 1.25, 0] },
	},
	regions: [
		{ bone: 'Head', region: [0.5, 6, 0, 9, -3, 3], only: /^(BodySection|Mouth|Teeth|Tongue|Nostril|EyeWhite|Iris|Pupil|Catchlight|Lash|Blush|Gill)$/ },
		{ bone: 'Torso', region: [-1, 3, 2.3, 3, -3, 3], only: /^FinLeg$/ },
		{ bone: 'RightLowerLeg', region: [-1, 3, 0, 1.3, 0, 3], only: /^Sneaker$/ },
		{ bone: 'LeftLowerLeg', region: [-1, 3, 0, 1.3, -3, 0], only: /^Sneaker$/ },
		{ bone: 'CentreLowerLeg', region: [-6, -3, 0, 1.3, -1, 1], only: /^Sneaker$/ },
	],
};
