# Joints reference

Detail companion to `SKILL.md` > Joints. Joints connect exactly two bodies. The first body is the GameObject that holds the joint component; the second is `connectedBody` (null = world). Anchor points are in each body's local space. All joints expose a `breakForce` / `breakTorque` (3D) or `breakForce`/`breakTorque` (2D) — the joint destroys itself when exceeded.

Add joints with `manage_physics` (the action selects the joint type). Tune fields with `manage_components`. For exotic combinations not covered here, route through `unity_reflect` against the joint's C# type to enumerate every field.

## 3D joints

### HingeJoint
Single rotational axis around `axis` at `anchor`. Optional `useLimits` (min/max angle, bounce, contact distance). Optional `useMotor` (target velocity, force). Optional `useSpring` (spring, damper, target position). Common uses: doors, levers, wheels with a motor.

### FixedJoint
Welds two bodies. Internally uses a stiff spring, so under heavy forces it can flex; for truly rigid attachment consider parenting one body under the other and removing the second Rigidbody.

### SpringJoint
Distance spring with `spring`, `damper`, `minDistance`, `maxDistance`, `tolerance`. Acts as a soft tether.

### ConfigurableJoint
The general-purpose 3D joint. Per-axis motion (`xMotion`, `yMotion`, `zMotion`) and rotation (`angularXMotion`, `angularYMotion`, `angularZMotion`) each set to Free / Limited / Locked. Independent linear and angular drives. Use this for advanced rigs (vehicles, characters, complex machinery). Anything the other 3D joints can do, ConfigurableJoint can do — at the cost of more fields.

### CharacterJoint
Ragdoll limb joint. Twist axis + two swing axes with limits, plus optional twist/swing drives. Use for ragdoll setup; pair with `Rigidbody` per bone, and constrain to keep limbs from flailing past anatomical limits.

## 2D joints

### HingeJoint2D
Rotational pivot at `anchor`. `useMotor` (motor speed, max torque) and `useLimits` (lower/upper angle).

### FixedJoint2D
Rigid attach via stiff spring. `dampingRatio`, `frequency`. Higher frequency = stiffer.

### SpringJoint2D
Spring between two anchors. `distance`, `dampingRatio`, `frequency`, `autoConfigureDistance`.

### DistanceJoint2D
Maintains a fixed distance like a rigid rod. `distance`, `maxDistanceOnly` (true = rope-like, only resists stretching).

### FrictionJoint2D
Linear and angular friction between two bodies. Useful to slow contact-free relative motion. `maxForce`, `maxTorque`.

### RelativeJoint2D
Maintains a relative offset and angle. `linearOffset`, `angularOffset`. `correctionScale` controls how aggressively it snaps back.

### SliderJoint2D
Linear track / piston along an angle. `useMotor`, `useLimits`, `angle`. The two bodies translate along that axis; rotation is unconstrained unless paired with another joint.

### TargetJoint2D
Drags one body toward a world-space `target` point with `maxForce`, `dampingRatio`, `frequency`. Common in mouse-drag interactions.

### WheelJoint2D
Hinge + suspension. Composite of a slider (suspension) and a motorized hinge (wheel). `suspension` (frequency, damping ratio, angle), `motor` (speed, max torque). Use one per wheel for 2D vehicles.

## Tuning notes

- `enableCollision` (3D) / `enableCollision` (2D) defaults false — connected bodies pass through each other. Set true if the bodies should still collide.
- `autoConfigureConnectedAnchor` (2D) and `autoConfigureAnchor` on FixedJoint2D / SpringJoint2D can hide where the joint is actually pinned. Disable when debugging unexpected behavior.
- High `breakForce` / `breakTorque` is fine; default `Mathf.Infinity` means unbreakable. For destructible mounts pick a value in the same magnitude as `mass * gravity * leverArm`.
- For chains of joints (rope, ladder), iterate `Physics.defaultSolverIterations` (3D) or `Physics2D.velocityIterations` / `positionIterations` (2D) upward — chains relax faster with more iterations at a small cost.
