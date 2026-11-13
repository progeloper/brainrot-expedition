--!strict
-- Tractoro Dinosauro (BRT_030): authored animation set. Archetype: Rider on a vehicle.
-- Bones: RigTorso (the tractor; it pivots on its rear axle), four wheel hubs
-- (RigRearRightWheel ...: the glowing ring, hubcap and gem turn; the blocky tyre stays still),
-- RigExhaust (the gold stack), RigDino (the T-rex riding on top), and on the dinosaur RigHead,
-- RigJaw (the lower jaw and tongue), RigRightArm, RigLeftArm and RigTail.
-- The meme: a T-rex farmer who is also his own tractor. The engine never stops shaking, the
-- hubs really turn, and the dinosaur rides it like a rodeo: bouncing in the seat, steering
-- with his tiny arms, chewing his wheat stalk and roaring when it rears up. Written for him.
-- Bake through AnimationBaker.GroundedSet. Edit-time authoring data only.
--
-- The wheels are 0.85 (rear) and 0.62 (front) studs in radius. Walk and Run each cover three
-- turns of the rear hubs and four of the front per loop, which is rolling without slipping
-- for the rear pair and within 3 per cent for the front pair at the authored speed.
--
-- Convention (model faces -Z, right is +X): +rx tips the tractor, the dinosaur or the head up
-- at the front and lifts an arm; +ry turns left; Q.Tail(up, side).
local Q = require(script.Parent.Parent.Archetypes.Quadruped)
local R, T, wave, seg, snap, bump = Q.R, Q.T, Q.wave, Q.seg, Q.snap, Q.bump

type Poses = { [string]: CFrame }

type Options = {
	lift: number?, -- the whole tractor rises
	pitch: number?, -- tractor nose up (+); it turns on the rear axle, so this is a wheelie
	roll: number?,
	yaw: number?,
	rear: number?, -- degrees the rear wheels have rolled forward
	front: number?,
	stack: number?, -- the exhaust stack jumps by this much
	seat: number?, -- the dinosaur bounces up off the tractor
	lean: number?, -- dinosaur pitch (+ back)
	sway: number?, -- dinosaur roll
	twist: number?, -- dinosaur yaw
	head: CFrame?,
	jaw: number?, -- degrees the jaw hangs open
	armR: number?, -- arm lift
	armL: number?,
	tail: CFrame?,
}

local function pose(o: Options): Poses
	local rear, front = R(-(o.rear or 0)), R(-(o.front or 0))
	return {
		RigTorso = T(0, o.lift or 0, 0, o.pitch or 0, o.yaw or 0, o.roll or 0),
		RigRearRightWheel = rear,
		RigRearLeftWheel = rear,
		RigFrontRightWheel = front,
		RigFrontLeftWheel = front,
		RigExhaust = T(0, o.stack or 0, 0),
		RigDino = T(0, o.seat or 0, 0, o.lean or 0, o.twist or 0, o.sway or 0),
		RigHead = o.head or R(),
		RigJaw = R(-(o.jaw or 0)),
		RigRightArm = R(o.armR or 0),
		RigLeftArm = R(o.armL or 0),
		RigTail = o.tail or R(),
	}
end

local set: { [string]: any } = {}

-- Banked: parked with the engine running. The tractor shivers, the stack chugs, and the
-- dinosaur shows off: head swaying, chewing his wheat, tiny arms waving one after the other.
set.IdleDisplay = {
	name = "IdleDisplay",
	length = 3.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local bounce = math.abs(wave(t, 1.5))
		local arms = wave(t, 0.75)
		return pose({
			roll = 0.6 * wave(t, 0.2),
			stack = 0.06 * math.abs(wave(t, 0.6)),
			seat = 0.05 * bounce,
			lean = 2 * bounce,
			sway = 2 * wave(t, 3.0),
			head = R(4 + 3 * bounce, 12 * wave(t, 3.0), 6 * wave(t, 1.5)),
			jaw = 7 * math.max(0, wave(t, 0.5)),
			armR = 12 + 20 * arms,
			armL = 12 - 20 * arms,
			tail = Q.Tail(6, 22 * wave(t, 1.5)),
		})
	end,
}
set.IdleWild = {
	name = "IdleWild",
	length = 3.6,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 1.8)
		return pose({
			roll = 0.4 * wave(t, 0.2),
			stack = 0.04 * math.abs(wave(t, 0.6)),
			seat = 0.02 + 0.02 * breathe,
			lean = breathe,
			twist = 4 * wave(t, 3.6),
			head = R(2 * breathe, 18 * wave(t, 3.6, 0.05), 3 * wave(t, 1.8, 0.2)),
			jaw = 4 * math.max(0, wave(t, 0.6)),
			armR = 4 * breathe,
			armL = -4 * breathe,
			tail = Q.Tail(2 * breathe, 16 * wave(t, 3.6, 0.3)),
		})
	end,
}
-- Rare variant: he revs the engine. The stack jumps, the rear wheels spin one full turn on
-- the spot, the nose pops up, and he throws his head back and roars.
set.IdleWild2 = {
	name = "IdleWild2",
	length = 2.0,
	loop = false,
	priority = "Idle",
	pose = function(t: number): Poses
		local rev = bump(t, 0.2, 1.7)
		local pop = bump(t, 0.5, 1.1)
		return pose({
			pitch = 8 * pop,
			roll = 1.4 * rev * wave(t, 0.1),
			rear = 360 * seg(t, 0.3, 1.5),
			stack = 0.16 * rev * math.abs(wave(t, 0.2)),
			seat = 0.08 * pop,
			lean = 6 * pop,
			head = R(14 * rev, 0, 0),
			jaw = 24 * rev,
			armR = 34 * rev,
			armL = 34 * rev,
			tail = Q.Tail(14 * rev, 20 * rev * wave(t, 0.25)),
		})
	end,
}
-- The drive: wheels turning, the tractor rocking over the ground, the dinosaur bouncing in
-- his seat a beat behind it and steering with his tiny arms.
set.Walk = {
	name = "Walk",
	length = 2.6,
	loop = true,
	priority = "Movement",
	speed = 6,
	pose = function(t: number): Poses
		local bob = wave(t, 0.65)
		local steer = wave(t, 1.3)
		return pose({
			lift = 0.03 * math.abs(bob),
			pitch = 1 + bob,
			roll = 0.5 * wave(t, 0.2),
			rear = 1080 * t / 2.6,
			front = 1440 * t / 2.6,
			stack = 0.05 * math.abs(wave(t, 0.325)),
			seat = 0.05 + 0.05 * wave(t, 0.65, -0.2),
			lean = -2 - 2 * bob,
			sway = 2 * steer,
			head = R(3 + 3 * wave(t, 0.65, -0.3), -6 * steer, 0),
			jaw = 4 * math.max(0, wave(t, 0.65)),
			armR = 10 + 12 * steer,
			armL = 10 - 12 * steer,
			tail = Q.Tail(4, 20 * steer),
		})
	end,
}
-- Flat out: the nose lifted, everything rattling, the dinosaur crouched forward with his jaw
-- open, arms up and tail streaming.
set.Run = {
	name = "Run",
	length = 1.6,
	loop = true,
	priority = "Movement",
	speed = 10,
	pose = function(t: number): Poses
		local bob = wave(t, 0.4)
		return pose({
			lift = 0.05 * math.abs(bob),
			pitch = 3 + 1.5 * bob,
			roll = 1.0 * wave(t, 0.2),
			rear = 1080 * t / 1.6,
			front = 1440 * t / 1.6,
			stack = 0.1 * math.abs(wave(t, 0.2)),
			seat = 0.08 + 0.07 * wave(t, 0.4, -0.2),
			lean = -9 - 2 * bob,
			sway = 2 * wave(t, 0.8),
			head = R(6 + 3 * wave(t, 0.4, -0.3), 0, 0),
			jaw = 15 + 4 * bob,
			armR = 26 + 10 * wave(t, 0.2),
			armL = 26 - 10 * wave(t, 0.2),
			tail = Q.Tail(18, 14 * wave(t, 0.4)),
		})
	end,
}
set.Alert = {
	name = "Alert",
	length = 0.4,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local up = snap(t, 0.06, 0.24)
		local air = bump(t, 0.06, 0.36)
		return pose({
			lift = 0.15 * air,
			pitch = 3 * air,
			stack = 0.12 * air,
			seat = 0.2 * air,
			lean = 4 * up,
			head = R(14 * up, 0, 0),
			jaw = 16 * air,
			armR = 40 * air,
			armL = 40 * air,
			tail = Q.Tail(30 * up, 0),
		})
	end,
}
set.Hit = {
	name = "Hit",
	length = 0.25,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local hit = snap(t, 0, 0.08) * (1 - seg(t, 0.1, 0.25))
		return pose({
			roll = 5 * hit,
			stack = 0.06 * hit,
			seat = 0.06 * hit,
			lean = 10 * hit,
			sway = -4 * hit,
			head = R(-10 * hit, 10 * hit, 8 * hit),
			jaw = 12 * hit,
			armR = 30 * hit,
			armL = 18 * hit,
			tail = Q.Tail(10 * hit, -26 * hit),
		})
	end,
}
-- Carried: the wheels spin in the air, the tractor wobbles and the dinosaur flails.
set.Carried = {
	name = "Carried",
	length = 1.0,
	loop = true,
	priority = "Movement",
	pose = function(t: number): Poses
		local k = wave(t, 0.25)
		local flap = wave(t, 0.5)
		return pose({
			pitch = 3 * flap,
			roll = 4 * wave(t, 1.0, 0.25),
			yaw = 5 * wave(t, 1.0),
			rear = 360 * t,
			front = 720 * t,
			stack = 0.05 * math.abs(k),
			seat = 0.04 * math.abs(flap),
			lean = 4 * flap,
			sway = 5 * wave(t, 1.0),
			head = R(4 * flap, 14 * wave(t, 1.0, 0.1), 6 * wave(t, 0.5, 0.25)),
			jaw = 10 + 8 * k,
			armR = 20 + 30 * k,
			armL = 20 - 30 * k,
			tail = Q.Tail(8, 36 * flap),
		})
	end,
}
-- Asleep at the wheel: engine off and still, the dinosaur slumped forward over the hood, head
-- hanging to one side, arms dangling, jaw loose, tail drooping.
set.Sleep = {
	name = "Sleep",
	length = 4.0,
	loop = true,
	priority = "Idle",
	pose = function(t: number): Poses
		local breathe = wave(t, 4.0)
		return pose({
			seat = 0.015 * breathe,
			lean = -10 + 1.2 * breathe,
			sway = 3,
			head = R(-16 + 1.5 * breathe, 0, 9),
			jaw = 6 + 3 * breathe,
			armR = -32,
			armL = -32,
			tail = Q.Tail(-12, 12),
		})
	end,
}
-- A jump and a full spin, wheels whirling, arms up and jaw wide.
set.Celebrate = {
	name = "Celebrate",
	length = 1.2,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local air = bump(t, 0.18, 0.92)
		local spin = seg(t, 0.22, 0.88)
		local land = bump(t, 0.9, 1.2)
		return pose({
			lift = 0.9 * air,
			pitch = 5 * air,
			yaw = 360 * spin,
			rear = 360 * spin,
			front = 720 * spin,
			stack = 0.12 * air,
			seat = 0.15 * air - 0.03 * land,
			lean = 5 * air - 3 * land,
			head = R(10 * air - 5 * land, 0, 0),
			jaw = 24 * air,
			armR = 55 * air,
			armL = 55 * air,
			tail = Q.Tail(34 * air, 28 * wave(t, 0.2) * air),
		})
	end,
}
-- Signature: the wheelie roar. The tractor rears up on its back wheels, which spin two full
-- turns; the dinosaur throws his head up and roars with his arms in the air; then the front
-- end slams back down and bounces.
set.Signature = {
	name = "Signature",
	length = 1.6,
	loop = false,
	priority = "Action",
	pose = function(t: number): Poses
		local rear = seg(t, 0.08, 0.38) * (1 - snap(t, 1.14, 1.32))
		local roar = seg(t, 0.2, 0.45) * (1 - seg(t, 1.1, 1.3))
		local shake = roar * wave(t, 0.1)
		local land = bump(t, 1.3, 1.6)
		return pose({
			lift = 0.07 * land,
			pitch = 30 * rear,
			roll = 1.2 * shake,
			rear = 720 * seg(t, 0.1, 1.25),
			stack = 0.14 * roar * math.abs(wave(t, 0.2)),
			seat = 0.06 * roar + 0.1 * land,
			lean = -12 * rear,
			head = R(14 * roar + 2 * shake - 6 * land, 0, 0),
			jaw = 30 * roar + 4 * shake,
			armR = 50 * roar + 12 * shake,
			armL = 50 * roar - 12 * shake,
			tail = Q.Tail(-14 * rear + 10 * land, 14 * shake),
		})
	end,
}

return Q.Finish(set)
