---
name: unity-input-system
description: 'Use when wiring input through Unity''s NEW Input System package via Unity MCP — anything involving InputAction assets, action maps, control schemes, bindings, composites, interactions, processors, PlayerInput / PlayerInputManager, the Input System UI Input Module, on-screen controls, runtime rebinding, or migrating code that calls legacy `Input.GetKey/GetAxis/GetButton/mousePosition/touchCount`. (trigger: input system, new input system, InputAction, Input Actions, action map, control scheme, binding, composite, interaction, processor, PlayerInput, PlayerInputManager, OnScreenStick, OnScreenButton, Input System UI Input Module, Gamepad.current, Keyboard.current, Touchscreen.current, Mouse.current, generate C# class, .inputactions, migrate from legacy Input, Input.GetAxis, Input.GetKey, local multiplayer, rebinding)'
---

## When to use

Any input task — jumping, movement, action buttons, gamepad, mouse-look, touch controls, local multiplayer, rebinding UI, porting code that uses `Input.GetKey` / `GetAxis` / `GetButton` / `mousePosition` / `touchCount`. This skill targets the package `com.unity.inputsystem`, NOT the legacy `UnityEngine.Input` class.

Cross-links: `unity-ugui` (EventSystem swap on UI prefabs), `unity-best-practices` (pick one input pipeline and stay consistent across the project).

## Setup

- Install `com.unity.inputsystem` via the package manager. Unity 6+ projects should use it as the primary input stack.
- Project Settings → Player → **Active Input Handling**: choose `Input System Package (New)` as the final state. Switching prompts an Editor restart.
- `Both` runs TWO input pipelines simultaneously. Use it only during a bounded migration from legacy `UnityEngine.Input`, then switch to `Input System Package (New)` once legacy call sites and the old Standalone Input Module are gone.
- First use auto-creates `Assets/InputSystem_Actions.inputactions`. Otherwise create one yourself as an `InputActionAsset`, or via `Assets > Create > Input Actions`.

## Input Actions asset

The `.inputactions` file is JSON edited via the Input Actions editor (double-click the asset). Three-level hierarchy:

- **Action Maps** — gameplay contexts: `Player`, `UI`, `Driving`. Typically only one map active at a time per consumer; switch maps when entering menus.
- **Actions** — abstract verbs: `Move`, `Jump`, `Fire`, `Submit`, `Cancel`.
- **Bindings** — concrete physical inputs: `<Keyboard>/space`, `<Gamepad>/buttonSouth`, `<Mouse>/leftButton`.

Tick **Generate C# Class** on the asset to produce a strongly-typed wrapper (e.g. `class @PlayerControls : IInputActionCollection2`). Regenerate after every asset edit (toggle the checkbox or click Apply) — the generated file is otherwise stale.

## Action types

- **Button** — discrete press / release. Phases: `started` → `performed` → `canceled`. `ReadValue<float>()` returns 0 or 1.
- **Value** — continuous; sends every frame the value changes. `ReadValue<Vector2>()` for sticks, `ReadValue<float>()` for triggers. **Initial State Check** flag fires the current value at enable.
- **Pass-Through** — like Value but reports EVERY contributing device separately. Use when more than one device of the same class drives the same action (e.g. four gamepad sticks competing for `Move`). Default for local multiplayer.

## Bindings and composites

Single binding = one path string. Composite bindings synthesize a value from multiple inputs:

- **1D Axis** — two keys → -1..+1 float (e.g. `A` / `D`).
- **2D Vector** — four keys → `Vector2` (WASD). Modes: Digital, Digital Normalized, Analog.
- **3D Vector** — six keys → `Vector3` (rare, 6-DOF).
- **Button With One Modifier** / **Button With Two Modifiers** — `Ctrl+Z`, `Ctrl+Shift+S`.
- **One Modifier / Two Modifiers** — value-bearing variants.

Path syntax: `<Gamepad>/leftStick`, `<Keyboard>/anyKey`, `<XRController>{LeftHand}/trigger`, wildcard `*` for any device of a class. Full table in `references/composites.md`.

## Interactions and processors

**Interactions** modify when an action triggers:

- **Press** (default) — performed on press, canceled on release.
- **Hold** — performed only after `Hold Time` (default 0.4s).
- **Tap** — performed only on quick press+release within `Max Tap Duration`.
- **MultiTap** — performed after N taps within window (double-click).
- **SlowTap** — like Hold but performs on release.

**Processors** transform the value before delivery:

- Scalar: **Invert**, **Normalize**, **Scale**, **Clamp**, **Axis Deadzone**.
- Vector2: **Stick Deadzone** (radial), **Invert Vector 2**, **Normalize Vector 2**.

Apply at the binding level (per-binding) or the action level (all bindings).

## Consuming input (3 paths)

**a) PlayerInput component** — add a `PlayerInput` component to the GameObject and assign the `.inputactions` asset. Behavior modes:

- **Send Messages** — calls `OnJump(InputValue value)` on this GameObject's components by reflection.
- **Broadcast Messages** — same but recurses into children.
- **Invoke Unity Events** — drag-and-drop hookup per Action.
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

**c) Direct devices** — bypass Actions entirely. Use sparingly: skips rebinding, control schemes, multiplayer pairing.

```csharp
if (Gamepad.current != null && Gamepad.current.buttonSouth.wasPressedThisFrame) Jump();
var move = Keyboard.current.aKey.isPressed ? -1f
         : Keyboard.current.dKey.isPressed ?  1f : 0f;
```

## PlayerInput component

Configurable fields:

- **Actions** — the `.inputactions` asset.
- **Default Map** / **Default Scheme** — which Action Map and Control Scheme are active on spawn.
- **Camera** — bound camera, used by SplitScreen / `PlayerInputManager`.
- **Behavior** — dispatch mode (above).
- **Auto-Switch** — with Control Schemes, automatically swap to whichever device the player most recently used.

## Local multiplayer (PlayerInputManager)

`PlayerInputManager` on a manager GameObject spawns a player prefab when a new device joins.

- **Join Behavior** — `Join Players When Button Is Pressed` / `When Joining Action Is Triggered` / `Manually`.
- **Player Prefab** must have a `PlayerInput`.
- Enforces device pairing — each player owns their devices. Split one keyboard via two Control Schemes (`Keyboard&Mouse Left`, `Keyboard Right`).
- Split-screen camera assignment is driven by Player Index → viewport.

## UI integration

Replace EventSystem's `Standalone Input Module` with **Input System UI Input Module**. The new module references the same `.inputactions` and binds UI actions: `Navigate`, `Submit`, `Cancel`, `Point`, `Click`, `ScrollWheel`, `MiddleClick`, `RightClick`, `TrackedDevicePosition`, `TrackedDeviceOrientation`. Without the swap, UI either does not receive input or warnings flood the Editor console. Remove the legacy module and add the new one. See `unity-ugui`.

## Mobile and on-screen controls

- **OnScreenButton**, **OnScreenStick** — components on UI Image / Button GameObjects, pointed at a Control Path (`<Gamepad>/buttonSouth`). They synthesize device input as if a real gamepad were connected.
- **EnhancedTouch** — `using UnityEngine.InputSystem.EnhancedTouch;` then `EnhancedTouchSupport.Enable();` for multi-touch APIs.
- Raw `Touchscreen` device: `Touchscreen.current.touches`, `Touchscreen.current.primaryTouch`.

## Rebinding at runtime

Use the operation builder. Save overrides as JSON, restore at startup.

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

Quick mappings (full table in `references/migration-table.md`):

- `Input.GetKey(KeyCode.Space)` → `Keyboard.current.spaceKey.isPressed` or Action `<Keyboard>/space`.
- `Input.GetKeyDown(...)` → `wasPressedThisFrame` or Action's `started`.
- `Input.GetAxis("Horizontal")` → 1D Axis composite on `Move`, read `Vector2.x`.
- `Input.GetButton("Fire1")` → Action `Fire` (Button type).
- `Input.GetMouseButton(0)` → `Mouse.current.leftButton.isPressed`.
- `Input.mousePosition` → `Mouse.current.position.ReadValue()`.
- `Input.touchCount` / `GetTouch(i)` → `Touchscreen.current.touches[i]` (or EnhancedTouch).

Do not migrate piecemeal — switch the map for an entire feature in one PR so two pipelines do not fight.

## Common patterns

- **WASD + gamepad stick on one action** — 2D Vector composite (WASD) plus `<Gamepad>/leftStick` on the same `Move` action; add Stick Deadzone processor at action level.
- **Hold-to-charge attack** — Hold interaction, `Hold Time` 0.6s; `performed` fires at full charge (release).
- **Double-tap dodge** — MultiTap with Tap Count 2.
- **Pause toggles map** — `controls.Player.Disable(); controls.UI.Enable();` on pause; reverse on resume.
- **Vibration** — `Gamepad.current.SetMotorSpeeds(low, high);`.

## Gotchas

- **Active Input Handling = Input Manager (Old)** → the new package does not deliver events; the asset works but actions silently never fire. PlayerInput shows a yellow warning; verify in the Editor console.
- **Generated C# class is stale** until you regenerate after every asset edit.
- **Send Messages is reflective** — typo on the method name = silent no-op. Prefer Invoke C# Events.
- **`performed` fires repeatedly for Value actions** (every value change). For one-shot, use Button type or filter on `started`.
- **No `Input.GetAxis` smoothing by default** — replicate via Processors or smooth the read value yourself.
- **EventSystem with both UI modules attached** = double events. Remove `Standalone Input Module` entirely.
- **Rigidbody movement** — read in `FixedUpdate` via `action.ReadValue<Vector2>()`, not in `performed` callbacks (which fire outside FixedUpdate).
- **Switching Active Input Handling** triggers Editor restart and may invalidate scene references that pointed at legacy input — recompile before testing.
- **Background focus** — desktop builds auto-disable input on focus loss; configure `InputSystem.settings.backgroundBehavior` if needed.
- **`Touchscreen.current` is null** on devices without touch — null-check before reading.
- **OnScreenStick + real gamepad both connected** — readings can conflict (both feed `<Gamepad>/leftStick`). Gate on `Touchscreen.current != null` or hide on-screen controls when a real pad is paired.

## Verification

- Open the **Input Debugger** (`Window > Analysis > Input Debugger`) to confirm devices are detected and actions fire. The Actions tab shows live phase transitions.
- For a feature, log on `OnEnable` of the consumer to confirm the expected map is active, or watch the Actions tab.
- Editor console clean of `InputSystem` warnings (missing UI module, action asset not assigned, no devices paired).
- Confirm legacy calls are gone: search migrated files for `Input.GetKey`, `Input.GetAxis`, `Input.GetButton`, `Input.mousePosition`, `Input.touchCount`. Any hit means the migration is incomplete.
- Reflect on the live type or consult the Unity manual when an API or path string is uncertain rather than guessing binding paths.
