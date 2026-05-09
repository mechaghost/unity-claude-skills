# Legacy `Input` → new Input System

Two replacement styles: **direct device read** (fast, bypasses rebinding/control schemes/multiplayer) or **Action-based** (preferred for player-facing).

## Keyboard

| Legacy | Direct device | Action |
|---|---|---|
| `Input.GetKey(KeyCode.Space)` | `Keyboard.current.spaceKey.isPressed` | `Jump` (Button) bound to `<Keyboard>/space`, `IsPressed()` |
| `Input.GetKeyDown(KeyCode.Space)` | `Keyboard.current.spaceKey.wasPressedThisFrame` | Action `started` |
| `Input.GetKeyUp(KeyCode.Space)` | `Keyboard.current.spaceKey.wasReleasedThisFrame` | Action `canceled` |
| `Input.anyKeyDown` | `Keyboard.current.anyKey.wasPressedThisFrame` | Action bound to `<Keyboard>/anyKey` |
| `Input.inputString` | `Keyboard.current.onTextInput += ch => ...` | n/a |

## Mouse

| Legacy | New |
|---|---|
| `Input.mousePosition` | `Mouse.current.position.ReadValue()` (Vector2; no z) |
| `Input.GetMouseButton(0)` | `Mouse.current.leftButton.isPressed` |
| `Input.GetMouseButtonDown(0)` | `Mouse.current.leftButton.wasPressedThisFrame` |
| `Input.GetMouseButton(1)` | `Mouse.current.rightButton.isPressed` |
| `Input.mouseScrollDelta` | `Mouse.current.scroll.ReadValue()` |
| `Input.GetAxis("Mouse X")` | `Mouse.current.delta.ReadValue().x` (raw, no smoothing) |

## Axes / virtual buttons (Project Settings → Input Manager)

| Legacy | New |
|---|---|
| `Input.GetAxis("Horizontal")` | `Move` (Value, Vector2), 2D Vector composite WASD + `<Gamepad>/leftStick`; `.x` |
| `Input.GetAxisRaw("Horizontal")` | Same minus smoothing processors |
| `Input.GetButton("Fire1")` | `Fire` (Button) bound to `<Mouse>/leftButton` and `<Gamepad>/rightTrigger` |
| `Input.GetButtonDown("Jump")` | `Jump` `started` callback |

`Input.GetAxis` smoothing has no built-in equivalent. Accept raw, add a smoothing processor, or `Vector2.SmoothDamp` the read value.

## Gamepad / Joystick

| Legacy | New |
|---|---|
| `Input.GetJoystickNames()` | iterate `Gamepad.all` |
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
| `Input.multiTouchEnabled` | always on; gate via `EnhancedTouchSupport.Enable()` |

## Accelerometer / Gyro

| Legacy | New |
|---|---|
| `Input.acceleration` | `Accelerometer.current?.acceleration.ReadValue()` |
| `Input.gyro.attitude` | `AttitudeSensor.current?.attitude.ReadValue()` |

Sensors disabled by default — `InputSystem.EnableDevice(Sensor.current)` first.

## Migration order

1. Add `com.unity.inputsystem`, set Active Input Handling to `Both`.
2. Author `.inputactions` for ONE feature (e.g. Player movement).
3. Replace all legacy `Input` calls in that feature.
4. Verify in console and Input Debugger.
5. Repeat per feature. Don't mix per-call.
6. Once all features migrated, switch Active Input Handling to `Input System Package (New)` and delete unused `InputManager.asset` axes.
