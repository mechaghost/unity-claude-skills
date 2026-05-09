# Composites and binding paths

## Composite types

| Composite | Output | Typical use |
|---|---|---|
| 1D Axis | `float` -1..+1 | A/D, Q/E throttle, brake/accelerate split |
| 2D Vector | `Vector2` | WASD, arrow keys, dpad-as-stick |
| 3D Vector | `Vector3` | 6-DOF flight controls |
| Button With One Modifier | button | `Ctrl+Z` |
| Button With Two Modifiers | button | `Ctrl+Shift+S` |
| One Modifier | value | Held modifier alters a value binding |
| Two Modifiers | value | Two held modifiers alter a value binding |

## 2D Vector composite modes

- **Digital** — keys produce raw -1 / 0 / +1; diagonals reach length sqrt(2).
- **Digital Normalized** (default) — diagonals clamped to length 1; matches gamepad-stick magnitude.
- **Analog** — for already-continuous axes.

Use `Digital Normalized` for keyboard movement mixed with a gamepad stick on the same action — otherwise diagonals are 41% faster on keyboard.

## Path syntax

```
<DeviceLayout>{usage}/control
```

- `<Keyboard>/space` — single device class.
- `<Gamepad>/buttonSouth` — abstracted face button (A on Xbox, X on PlayStation).
- `<Gamepad>/leftStick` — stick as Vector2.
- `<Gamepad>/leftStick/x` — single axis.
- `<XRController>{LeftHand}/trigger` — usage tag in braces.
- `<Mouse>/delta` — mouse delta (Vector2) for look.
- `<Mouse>/scroll/y` — scroll wheel y.
- `*/{PrimaryAction}` — any device exposing `PrimaryAction` usage.

## Common gamepad face button paths

| Logical | Path | Xbox | PlayStation | Switch |
|---|---|---|---|---|
| South | `<Gamepad>/buttonSouth` | A | Cross | B |
| East  | `<Gamepad>/buttonEast`  | B | Circle | A |
| West  | `<Gamepad>/buttonWest`  | X | Square | Y |
| North | `<Gamepad>/buttonNorth` | Y | Triangle | X |

Use abstract `buttonSouth` etc. Never bind vendor-specific layouts unless console-specific control is needed.

## Processor stacking

Multiple processors compose left-to-right; order matters:

- `invert,scale(factor=2)` — invert, then scale.
- `axisDeadzone(min=0.125),scale(factor=1.1)` — kill stick noise before amplifying.

Stick deadzone for gamepads should be radial (Stick Deadzone), not per-axis, to avoid the square corners Axis Deadzone creates.
