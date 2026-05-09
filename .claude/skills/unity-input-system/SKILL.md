---
name: unity-input-system
description: 'Use for Unity 6+ New Input System: InputAction assets, maps, bindings, composites/interactions/processors, PlayerInput/PlayerInputManager, UI Input Module, on-screen controls, rebinding, Gamepad/Keyboard/Touchscreen/Mouse, legacy Input migration.'
---

## When to use

Any input task — jump, movement, action buttons, gamepad, mouse-look, touch, local multiplayer, rebinding UI, porting `Input.GetKey/GetAxis/GetButton/mousePosition/touchCount`. Targets `com.unity.inputsystem`, NOT legacy `UnityEngine.Input`.

## Setup

- Install `com.unity.inputsystem`. Unity 6+ uses it as primary.
- Project Settings → Player → **Active Input Handling**: `Input System Package (New)` as final state. Switching prompts an Editor restart.
- `Both` runs two pipelines simultaneously. Migration only — switch to `New` after.
- First use auto-creates `Assets/InputSystem_Actions.inputactions`. Or `Assets > Create > Input Actions`.

## Input Actions asset

JSON file edited via Input Actions editor (double-click). Three levels:

- **Action Maps** — gameplay contexts: `Player`, `UI`, `Driving`. One active per consumer; switch on menu entry.
- **Actions** — abstract verbs: `Move`, `Jump`, `Fire`, `Submit`, `Cancel`.
- **Bindings** — physical inputs: `<Keyboard>/space`, `<Gamepad>/buttonSouth`, `<Mouse>/leftButton`.

Tick **Generate C# Class** for a typed wrapper (`class @PlayerControls : IInputActionCollection2`). Regenerate after every asset edit — file is otherwise stale.

## Action types

- **Button** — discrete press/release. Phases: `started` → `performed` → `canceled`. `ReadValue<float>()` returns 0 or 1.
- **Value** — continuous; sends every change. `ReadValue<Vector2>()` for sticks, `ReadValue<float>()` for triggers. **Initial State Check** fires the current value at enable.
- **Pass-Through** — like Value but reports EVERY contributing device. For multi-device-of-same-class on one action (four sticks competing for `Move`). Default for local multiplayer.

## Bindings and composites

Single binding = one path string. Composites synthesize a value from multiple inputs:

- **1D Axis** — two keys → -1..+1 (`A`/`D`).
- **2D Vector** — four keys → `Vector2` (WASD). Modes: Digital, Digital Normalized, Analog.
- **3D Vector** — six keys → `Vector3` (rare).
- **Button With One/Two Modifiers** — `Ctrl+Z`, `Ctrl+Shift+S`.
- **One/Two Modifiers** — value-bearing variants.

Path syntax: `<Gamepad>/leftStick`, `<Keyboard>/anyKey`, `<XRController>{LeftHand}/trigger`, wildcard `*`. Full table: `references/composites.md`.

## Interactions and processors

**Interactions** modify when an action triggers:

- **Press** (default) — performed on press, canceled on release.
- **Hold** — performed after `Hold Time` (default 0.4 s).
- **Tap** — performed on quick press+release within `Max Tap Duration`.
- **MultiTap** — performed after N taps within window (double-click).
- **SlowTap** — like Hold but performs on release.

**Processors** transform value before delivery:

- Scalar — **Invert**, **Normalize**, **Scale**, **Clamp**, **Axis Deadzone**.
- Vector2 — **Stick Deadzone** (radial), **Invert Vector 2**, **Normalize Vector 2**.

Apply per binding or per action.

## Consuming input (3 paths)

**a) PlayerInput component** — assign the `.inputactions` asset. Behavior modes:

- **Send Messages** — calls `OnJump(InputValue value)` by reflection on this GameObject's components.
- **Broadcast Messages** — same, recurses into children.
- **Invoke Unity Events** — drag-and-drop per Action.
- **Invoke C# Events** — `playerInput.onActionTriggered += ctx => ...`.

**b) Generated C# class** — best for type safety:

```csharp
private PlayerControls controls;
void Awake() { controls = new PlayerControls(); }
void OnEnable()
{
    controls.Player.Jump.performed += OnJump;
    controls.Player.Enable();
}
void OnDisable() { controls.Player.Disable(); }
void OnJump(InputAction.CallbackContext ctx) { /* ... */ }
```

**c) Direct devices** — bypasses Actions. Skips rebinding, control schemes, multiplayer pairing. Use sparingly.

```csharp
if (Gamepad.current != null && Gamepad.current.buttonSouth.wasPressedThisFrame) Jump();
var move = Keyboard.current.aKey.isPressed ? -1f
         : Keyboard.current.dKey.isPressed ?  1f : 0f;
```

## PlayerInput component

- **Actions** — `.inputactions` asset.
- **Default Map** / **Default Scheme** — active on spawn.
- **Camera** — bound camera, used by SplitScreen / `PlayerInputManager`.
- **Behavior** — dispatch mode.
- **Auto-Switch** — swap to whichever device the player most recently used (with Control Schemes).

## Local multiplayer (PlayerInputManager)

`PlayerInputManager` spawns a player prefab when a new device joins.

- **Join Behavior** — `Join Players When Button Is Pressed` / `When Joining Action Is Triggered` / `Manually`.
- **Player Prefab** must have a `PlayerInput`.
- Enforces device pairing — each player owns their devices. Split one keyboard via two Control Schemes (`Keyboard&Mouse Left`, `Keyboard Right`).
- Split-screen camera assignment driven by Player Index → viewport.

## UI integration

Replace EventSystem's `Standalone Input Module` with **Input System UI Input Module**. References the same `.inputactions` and binds: `Navigate`, `Submit`, `Cancel`, `Point`, `Click`, `ScrollWheel`, `MiddleClick`, `RightClick`, `TrackedDevicePosition`, `TrackedDeviceOrientation`. Without the swap, UI receives no input or warnings flood the console. Remove the legacy module. See `unity-ugui`.

## Mobile and on-screen controls

- **OnScreenButton**, **OnScreenStick** — components on UI Image / Button GameObjects pointed at a Control Path (`<Gamepad>/buttonSouth`). Synthesize device input as if a real gamepad were connected.
- **EnhancedTouch** — `using UnityEngine.InputSystem.EnhancedTouch;` then `EnhancedTouchSupport.Enable();`.
- Raw `Touchscreen`: `Touchscreen.current.touches`, `Touchscreen.current.primaryTouch`.

## Rebinding at runtime

Save overrides as JSON, restore at startup.

```csharp
private InputActionRebindingExtensions.RebindingOperation rebind;

void StartRebind(InputAction action, int bindingIndex)
{
    action.Disable();
    rebind = action.PerformInteractiveRebinding(bindingIndex)
        .WithControlsExcluding("<Mouse>/position")
        .WithCancelingThrough("<Keyboard>/escape")
        .OnComplete(op => { op.Dispose(); action.Enable(); Save(action); })
        .OnCancel(op =>   { op.Dispose(); action.Enable(); })
        .Start();
}

void Save(InputAction a) =>
    PlayerPrefs.SetString("rebinds", a.actionMap.asset.SaveBindingOverridesAsJson());

void Load(InputActionAsset asset) =>
    asset.LoadBindingOverridesFromJson(PlayerPrefs.GetString("rebinds", ""));
```

## Migration from legacy Input

Quick mappings (full table: `references/migration-table.md`):

- `Input.GetKey(KeyCode.Space)` → `Keyboard.current.spaceKey.isPressed` or Action `<Keyboard>/space`.
- `Input.GetKeyDown(...)` → `wasPressedThisFrame` or Action `started`.
- `Input.GetAxis("Horizontal")` → 1D Axis composite on `Move`, read `Vector2.x`.
- `Input.GetButton("Fire1")` → Action `Fire` (Button type).
- `Input.GetMouseButton(0)` → `Mouse.current.leftButton.isPressed`.
- `Input.mousePosition` → `Mouse.current.position.ReadValue()`.
- `Input.touchCount` / `GetTouch(i)` → `Touchscreen.current.touches[i]` (or EnhancedTouch).

Don't migrate piecemeal — switch the map for an entire feature in one PR so pipelines don't fight.

## Common patterns

- **WASD + gamepad stick on one action** — 2D Vector composite (WASD) + `<Gamepad>/leftStick` on `Move`; add Stick Deadzone at action level.
- **Hold-to-charge attack** — Hold interaction, `Hold Time` 0.6 s; `performed` fires at full charge (release).
- **Double-tap dodge** — MultiTap, Tap Count 2.
- **Pause toggles map** — `controls.Player.Disable(); controls.UI.Enable();` on pause; reverse on resume.
- **Vibration** — `Gamepad.current.SetMotorSpeeds(low, high);`.

## Gotchas

- **Active Input Handling = Old** → new package delivers no events; actions silently never fire. PlayerInput shows yellow warning.
- **Generated C# class is stale** until you regenerate after every asset edit.
- **Send Messages is reflective** — method-name typo = silent no-op. Prefer Invoke C# Events.
- **`performed` fires repeatedly for Value actions** (every change). For one-shot, use Button type or filter on `started`.
- **No `Input.GetAxis` smoothing by default** — use Processors or smooth manually.
- **EventSystem with both UI modules attached** = double events. Remove the legacy module.
- **Rigidbody movement** — read in `FixedUpdate` via `action.ReadValue<Vector2>()`, not in `performed` (fires outside FixedUpdate).
- **Switching Active Input Handling** triggers Editor restart and may invalidate scene references — recompile before testing.
- **Background focus** — desktop builds auto-disable on focus loss; configure `InputSystem.settings.backgroundBehavior` if needed.
- **`Touchscreen.current` is null** on devices without touch — null-check.
- **OnScreenStick + real gamepad** can conflict (both feed `<Gamepad>/leftStick`). Gate on `Touchscreen.current != null` or hide on-screen when a real pad is paired.

## Verification

- **Input Debugger** (`Window > Analysis > Input Debugger`) — devices detected, Actions tab shows live phase transitions.
- Log on `OnEnable` to confirm expected map is active, or watch Actions tab.
- Console clean of `InputSystem` warnings (missing UI module, action asset not assigned, no devices paired).
- Search migrated files for `Input.GetKey`, `Input.GetAxis`, `Input.GetButton`, `Input.mousePosition`, `Input.touchCount`. Any hit = migration incomplete.
- Reflect on the live type or check the Unity manual rather than guessing path strings.
