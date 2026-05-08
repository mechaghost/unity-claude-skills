# Legacy `Input` → new Input System

Two replacement styles exist for almost every entry: a **direct device read** (fast, but bypasses rebinding / control schemes / multiplayer) and an **Action-based** path (preferred for anything player-facing).

## Keyboard

| Legacy | Direct device | Action |
|---|---|---|
| `Input.GetKey(KeyCode.Space)` | `Keyboard.current.spaceKey.isPressed` | Action `Jump` (Button) bound to `<Keyboard>/space`, read `IsPressed()` |
| `Input.GetKeyDown(KeyCode.Space)` | `Keyboard.current.spaceKey.wasPressedThisFrame` | Action's `started` callback |
| `Input.GetKeyUp(KeyCode.Space)` | `Keyboard.current.spaceKey.wasReleasedThisFrame` | Action's `canceled` callback |
| `Input.anyKeyDown` | `Keyboard.current.anyKey.wasPressedThisFrame` | Action bound to `<Keyboard>/anyKey` |
| `Input.inputString` | `Keyboard.current.onTextInput += ch => ...` | n/a |

## Mouse

| Legacy | New |
|---|---|
| `Input.mousePosition` | `Mouse.current.position.ReadValue()` (Vector2; note: no z) |
| `Input.GetMouseButton(0)` | `Mouse.current.leftButton.isPressed` |
| `Input.GetMouseButtonDown(0)` | `Mouse.current.leftButton.wasPressedThisFrame` |
| `Input.GetMouseButton(1)` | `Mouse.current.rightButton.isPressed` |
| `Input.mouseScrollDelta` | `Mouse.current.scroll.ReadValue()` |
| `Input.GetAxis("Mouse X")` | `Mouse.current.delta.ReadValue().x` (raw, no smoothing) |

## Axes / virtual buttons (Project Settings → Input Manager)

| Legacy | New |
|---|---|
| `Input.GetAxis("Horizontal")` | Action `Move` (Value, Vector2) with 2D Vector composite WASD + `<Gamepad>/leftStick`; read `.x` |
| `Input.GetAxisRaw("Horizontal")` | Same Action minus smoothing processors |
| `Input.GetButton("Fire1")` | Action `Fire` (Button) bound to `<Mouse>/leftButton` and `<Gamepad>/rightTrigger` |
| `Input.GetButtonDown("Jump")` | Action `Jump`'s `started` callback |

`Input.GetAxis` smoothing does NOT have a built-in equivalent. Either accept raw values, add a smoothing processor, or implement your own `Vector2.SmoothDamp` on the read value.

## Gamepad / Joystick

| Legacy | New |
|---|---|
| `Input.GetJoystickNames()` | iterate `Gamepad.all` (richer info) |
| `Input.GetAxis("Joystick Axis 1")` | `Gamepad.current.leftStick.ReadValue().x` |
| `Input.GetButton("joystick button 0")` | `Gamepad.current.buttonSouth.isPressed` |
| Vibration (n/a in legacy) | `Gamepad.current.SetMotorSpeeds(low, high)` |

## Touch

| Legacy | New |
|---|---|
| `Input.touchCount` | `Touchscreen.current?.touches.Count` or `EnhancedTouch.Touch.activeTouches.Count` |
| `Input.GetTouch(i)` | `Touchscreen.current.touches[i]` |
| `touch.phase == TouchPhase.Began` | `touch.phase.ReadValue() == UnityEngine.InputSystem.TouchPhase.Began` |
| `touch.position` | `touch.position.ReadValue()` |
| `Input.multiTouchEnabled` | always on; gate via `EnhancedTouchSupport.Enable()` for the ergonomic API |

## Accelerometer / Gyro

| Legacy | New |
|---|---|
| `Input.acceleration` | `Accelerometer.current?.acceleration.ReadValue()` (call `InputSystem.EnableDevice(Accelerometer.current)`) |
| `Input.gyro.attitude` | `AttitudeSensor.current?.attitude.ReadValue()` |

Sensors are disabled by default — `InputSystem.EnableDevice(Sensor.current)` first.

## Migration order

1. Add `com.unity.inputsystem`, set Active Input Handling to `Both`.
2. Author the `.inputactions` asset for ONE feature (e.g. Player movement).
3. Replace all legacy `Input` calls in that feature.
4. Verify via `read_console` and Input Debugger.
5. Repeat per feature. Do NOT mix per-call.
6. Once every feature is migrated, switch Active Input Handling to `Input System Package (New)` and delete the legacy `InputManager.asset` axes you no longer need.
