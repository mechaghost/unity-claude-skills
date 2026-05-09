# Joints reference

Companion to `SKILL.md` > Joints. Joints connect two bodies — the GameObject holding the joint and `connectedBody` (null = world). Anchors in each body's local space. All expose `breakForce`/`breakTorque` — joint destroys itself when exceeded.

## 3D joints

### HingeJoint
Single rotational axis around `axis` at `anchor`. Optional `useLimits` (min/max angle, bounce, contact distance), `useMotor` (target velocity, force), `useSpring` (spring, damper, target). Doors, levers, motorized wheels.

### FixedJoint
Welds two bodies via stiff spring — flexes under heavy forces. For truly rigid attachment, parent one body under the other and remove the second Rigidbody.

### SpringJoint
Distance spring: `spring`, `damper`, `minDistance`, `maxDistance`, `tolerance`. Soft tether.

### ConfigurableJoint
General-purpose. Per-axis motion (`xMotion`, `yMotion`, `zMotion`) and rotation (`angularXMotion`, etc.) each Free/Limited/Locked. Independent linear and angular drives.

### CharacterJoint
Ragdoll limb. Twist axis + two swing axes with limits, optional drives. Pair with `Rigidbody` per bone.

## 2D joints

### HingeJoint2D
Rotational pivot at `anchor`. `useMotor` (motor speed, max torque), `useLimits` (lower/upper angle).

### FixedJoint2D
Rigid attach via stiff spring. `dampingRatio`, `frequency`. Higher frequency = stiffer.

### SpringJoint2D
Spring between anchors. `distance`, `dampingRatio`, `frequency`, `autoConfigureDistance`.

### DistanceJoint2D
Fixed distance like a rigid rod. `distance`, `maxDistanceOnly` (true = rope, only resists stretching).

### FrictionJoint2D
Linear/angular friction between bodies. Slows contact-free relative motion. `maxForce`, `maxTorque`.

### RelativeJoint2D
Maintains relative offset and angle. `linearOffset`, `angularOffset`. `correctionScale` controls snap-back aggression.

### SliderJoint2D
Linear track / piston along an angle. `useMotor`, `useLimits`, `angle`. Bodies translate along that axis; rotation unconstrained unless paired with another joint.

### TargetJoint2D
Drags one body toward a world-space `target`. `maxForce`, `dampingRatio`, `frequency`. Mouse-drag interactions.

### WheelJoint2D
Hinge + suspension. Slider (suspension) + motorized hinge (wheel). `suspension` (frequency, damping ratio, angle), `motor` (speed, max torque). One per wheel for 2D vehicles.

## Tuning notes

- `enableCollision` defaults false — connected bodies pass through. Set true if they should still collide.
- `autoConfigureConnectedAnchor` (2D) and `autoConfigureAnchor` on FixedJoint2D / SpringJoint2D hide where the joint pins. Disable when debugging.
- High `breakForce`/`breakTorque` is fine; default `Mathf.Infinity` = unbreakable. For destructible mounts pick `mass * gravity * leverArm` magnitude.
- For chains (rope, ladder), raise `Physics.defaultSolverIterations` (3D) or `Physics2D.velocityIterations`/`positionIterations` (2D) — chains relax faster at small cost.
