// BRT_019 Trenostruzzo Turbo 3000 — Voxel V4 reference build (approved 3 Nov 2026).
// Ground truth for geometry, roles and palettes. Design units, y up, nose = +x. Normalise total height (8.6) to ~6.7 studs.
// Trenostruzzo Turbo 3000 v4: Shinkansen (E5-style long nose, two-tone + stripe) + anime-eyed ostrich
// units = studs, y up, nose = +x. role decides mutation colour; P = protected (never recoloured)
// flags: 1 relief(studs), 4 emissive
const R=1,E=4;
const parts=[];let SLOT='Part';function S(n){SLOT=n;}
function B(x0,x1,y0,y1,z0,z1,role,flags=0,col=null){if(z0>z1)[z0,z1]=[z1,z0];parts.push({slot:SLOT,min:[x0,y0,z0],max:[x1,y1,z1],role,flags,col});}
function MZ(x0,x1,y0,y1,z0,z1,role,flags,col){B(x0,x1,y0,y1,z0,z1,role,flags,col);B(x0,x1,y0,y1,-z1,-z0,role,flags,col);}

// --- body sections: [x0,x1, top, stripeY, halfWidth]
const secs=[[-4.8,1.2,3.6,2.2,1.6],[1.2,2.6,3.15,2.0,1.56],[2.6,3.8,2.6,1.8,1.48],[3.8,4.9,2.05,1.55,1.34],[4.9,5.8,1.55,1.25,1.12],[5.8,6.4,1.3,0.98,0.84]];
S('BodySection');for(const [x0,x1,top,sy,hw] of secs){
  B(x0,x1,0.8,sy,-hw,hw,'lower',R);
  B(x0,x1,sy,sy+0.17,-hw-0.02,hw+0.02,'stripe',E);
  if(top>sy+0.17) B(x0,x1,sy+0.17,top,-hw,hw,'upper',R);
}
S('RoofCap');B(-4.6,1.0,3.6,3.85,-1.3,1.3,'upper',R);           // roof cap
// windshield (dark, glossy) on nose top steps
S('Windshield');B(2.6,3.75,2.6,2.68,-1.15,1.15,'P',0,'#141a2e');
B(3.8,4.85,2.05,2.1,-1.0,1.0,'P',0,'#141a2e');
MZ(2.62,3.7,2.35,2.6,1.48,1.52,'P',0,'#141a2e');
// headlights (always cyan glow)
S('Headlight');MZ(5.5,5.8,1.05,1.22,1.12,1.16,'P',E,'#bff8ff');
// side windows (dark blue glass, protected)
S('SideWindow');for(let i=0;i<6;i++){const x=-4.4+i*0.92; MZ(x,x+0.6,2.6,3.15,1.6,1.65,'P',0,'#1b2a5c'); MZ(x+0.06,x+0.3,2.95,3.1,1.65,1.67,'P',0,'#6fa8ff');}
// door
// undercarriage + bogies
S('Undercarriage');B(-4.6,5.6,0.45,0.8,-1.3,1.3,'P',0,'#1d2133');
S('Bogie');for(const x of [-4.1,-1.4,1.8]) MZ(x,x+1.1,0.2,0.75,1.25,1.45,'P',0,'#2a2f45');

// --- ostrich feet poking out in front of the nose
S('Foot');for(const s of [1,-1]){
  const zc=0.62*s;
  B(4.6,5.3,0.1,0.8,zc-0.3,zc+0.3,'foot');
  B(5.2,6.2,0,0.42,zc-0.44,zc+0.44,'foot');
  for(const dz of [-0.3,0,0.3]){const len=dz===0?0.95:0.72;
    B(6.2,6.2+len,0,0.36,zc+dz-0.14,zc+dz+0.14,'foot');
    B(6.2+len,6.2+len+0.36,0,0.3,zc+dz-0.12,zc+dz+0.12,'P',0,'#262a3a');}
}

// --- neck rising out of the cockpit, feather collar
S('FeatherCollar');B(1.3,2.75,3.1,3.75,-0.8,0.8,'feather');
for(const [x,z] of [[1.35,-0.65],[1.75,-0.72],[2.2,-0.72],[2.65,-0.5],[2.7,0],[2.65,0.5],[2.2,0.72],[1.75,0.72],[1.35,0.65],[1.3,0]])
  B(x-0.22,x+0.22,3.65,4.1,z-0.22,z+0.22,'feather2');
S('Neck');B(1.65,2.55,3.75,5.6,-0.5,0.5,'skin',R);
B(1.85,2.8,5.1,5.9,-0.52,0.52,'skin',R);

// --- head (big), anime eyes
S('Head');B(1.45,3.85,5.4,7.85,-1.0,1.0,'skin');
B(1.35,1.9,6.0,7.7,-0.92,0.92,'skin2');
// tuft (spiky, anime-ish)
S('Tuft');for(const [x,y,z,h] of [[1.9,7.85,-0.35,0.55],[2.35,7.85,0.15,0.75],[2.85,7.85,-0.2,0.5],[1.6,7.75,0.3,0.45]])
  B(x-0.22,x+0.22,y,y+h,z-0.2,z+0.2,'skin2');
for(const s of [1,-1]){
  const zz=(a,b)=>s>0?[a,b]:[-b,-a];
  const [w0,w1]=zz(1.0,1.04),[i0,i1]=zz(1.04,1.07),[p0,p1]=zz(1.07,1.1),[c0,c1]=zz(1.1,1.12);
  S('EyeWhite');
  // eye white (stepped rounded rect)
  B(2.1,3.25,5.85,7.5,w0,w1,'P',0,'#ffffff'); B(1.98,3.37,6.0,7.35,w0,w1,'P',0,'#ffffff');
  S('Iris');
  // iris gradient (dark top -> bright bottom)
  B(2.2,3.15,6.75,7.3,i0,i1,'P',0,'#7a2a10');
  B(2.2,3.15,6.3,6.75,i0,i1,'P',0,'#ff6a1a');
  B(2.2,3.15,5.92,6.3,i0,i1,'P',0,'#ffcf45');
  S('Pupil');
  // pupil
  B(2.45,2.92,6.35,7.0,p0,p1,'P',0,'#1a0b06');
  S('Catchlight');
  // catchlights: big upper + small lower + tiny sparkle
  B(2.3,2.66,6.78,7.16,c0,c1,'P',E,'#ffffff');
  B(2.86,3.04,6.1,6.28,c0,c1,'P',E,'#ffffff');
  B(2.98,3.06,6.86,6.94,c0,c1,'P',E,'#ffffff');
  S('Lash');
  // thick upper lash with a wing at the back
  B(1.92,3.45,7.42,7.66,w0,i1+0.02*s,'P',0,'#000000');
  B(1.7,2.0,7.55,7.85,w0,i1+0.02*s,'P',0,'#000000');
  B(3.3,3.5,7.3,7.48,w0,i1+0.02*s,'P',0,'#000000');
  S('Blush');
  // blush
  B(2.05,2.75,5.45,5.7,w0,w1,'P',E,'#ff6fa3');
}
// open smiling beak, tapered
S('Beak');B(3.85,4.9,6.25,6.8,-0.62,0.62,'P',0,'#ffa0a8');
B(4.9,5.6,6.3,6.75,-0.46,0.46,'P',0,'#ff94a0');
B(5.6,5.95,6.2,6.68,-0.3,0.3,'P',0,'#ff8a96');
B(3.85,4.7,5.6,6.02,-0.56,0.56,'P',0,'#e2647a');
B(4.7,5.3,5.72,6.02,-0.4,0.4,'P',0,'#d95870');
S('Mouth');B(3.85,4.9,6.02,6.25,-0.5,0.5,'P',0,'#6e0e2c');
S('Tongue');B(4.0,4.75,6.02,6.14,-0.34,0.34,'P',0,'#ff4f7a');
S('Mouth');MZ(3.75,3.95,6.0,6.35,0.6,0.66,'P',0,'#6e0e2c');
MZ(5.05,5.2,6.75,6.79,0.12,0.26,'P',0,'#6e0e2c');

// --- meme prop: toilet on the roof
S('Toilet');B(-3.3,-2.3,3.85,4.4,-0.45,0.45,'prop',R);
B(-3.75,-1.7,4.4,5.05,-0.9,0.9,'prop',R);
S('ToiletRim');B(-3.77,-1.68,4.7,4.82,-0.92,0.92,'accent',E);
S('ToiletSeat');B(-3.55,-1.9,5.05,5.12,-0.7,0.7,'P',0,'#1d2133');
S('ToiletTank');B(-4.35,-3.55,4.4,6.0,-0.9,0.9,'prop',R);
S('ToiletLid');B(-4.45,-3.45,6.0,6.22,-1.0,1.0,'accent',E);
B(-3.6,-3.3,5.7,5.82,0.9,1.15,'accent',E);

const PALETTES={
 normal:{upper:'#14c79f',lower:'#f7f5fc',stripe:'#ff3d9e',trim:'#e9e5f2',skin:'#ffd0b0',skin2:'#ffb08a',feather:'#2c2033',feather2:'#7b3f8f',foot:'#ff8a2a',prop:'#f7f5fc',accent:'#2ee9ff',mode:0},
 shiny:{upper:'#ff87b7',lower:'#fff4cd',stripe:'#ffffff',trim:'#ffe3ee',skin:'#ffe0ec',skin2:'#ffb6d3',feather:'#ff5fa0',feather2:'#ffffff',foot:'#ff9cc6',prop:'#fff4cd',accent:'#ff87b7',mode:5},
 golden:{upper:'#d99510',lower:'#ffd447',stripe:'#fff0a3',trim:'#ffe27a',skin:'#ffd447',skin2:'#e5a520',feather:'#8c4a08',feather2:'#fff0a3',foot:'#d99510',prop:'#ffd447',accent:'#fff0a3',mode:1},
 glitched:{upper:'#ff49e1',lower:'#2b0f52',stripe:'#3efff0',trim:'#5a1f9a',skin:'#ff8af0',skin2:'#3efff0',feather:'#2b0f52',feather2:'#ff49e1',foot:'#3efff0',prop:'#ff49e1',accent:'#3efff0',mode:4},
 radioactive:{upper:'#dcff2b',lower:'#182018',stripe:'#dcff2b',trim:'#2a3a20',skin:'#c9ff5a',skin2:'#9fe01a',feather:'#182018',feather2:'#dcff2b',foot:'#dcff2b',prop:'#182018',accent:'#dcff2b',mode:2},
 astral:{upper:'#6d74ff',lower:'#2a1f6e',stripe:'#ede0ff',trim:'#3b2f8f',skin:'#c4b6ff',skin2:'#8f80ff',feather:'#140d38',feather2:'#ede0ff',foot:'#6d74ff',prop:'#6d74ff',accent:'#ede0ff',mode:3}
};
function skin(name){const p=PALETTES[name];return parts.map(b=>({min:b.min,max:b.max,flags:b.flags|(b.role!=='P'?2:0),col:b.role==='P'?b.col:p[b.role]}));}

if (typeof module!=='undefined') module.exports={parts,PALETTES,skin};
// Rig (animation brief v5, 13 Nov 2026): vehicle-hybrid. Chassis = Torso; the neck swings from the feather
// collar; the head nods on the neck; the two front feet step; the toilet lid flaps (signature prop).
// Bogies are rigid boxes on the chassis: they are not wheels, so they get no joints.
if (typeof module!=='undefined') module.exports.rigOverrides={
  neck:{pivot:[2.1,3.75,0],slots:['Neck']},
  headPivot:[2.3,5.5,0],
  extraBones:{ToiletLid:{parent:'Torso',pivot:[-4.45,6.0,0]}},
  slots:{ToiletLid:'ToiletLid'},
};
