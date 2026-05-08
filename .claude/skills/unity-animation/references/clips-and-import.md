# AnimationClip authoring and FBX import reference

## FBX importer — Rig tab

- **Animation Type**: None / Legacy / Generic / Humanoid. Pick once per asset; flipping retroactively breaks references.
- **Avatar Definition**:
  - `Create From This Model` — generates an Avatar asset alongside this FBX.
  - `Copy From Other Avatar` — share a single Avatar across multiple character FBX files (preferred when many clips target the same skeleton).
- **Skin Weights** — max bones per vertex. Default 4; raise only if shipping high-end PC.
- **Optimize Game Objects** — strips bone Transforms from the runtime hierarchy. Saves CPU on the animator update but breaks code that walks `GetComponentsInChildren<Transform>()` looking for bones, and any prop attachment that targets a bone GameObject. Use **Extra Transforms to Expose** to whitelist the bones you actually parent props to.
- **Configure...** — opens the Avatar editor. Use to fix bone mappings if a humanoid retarget looks broken.

## FBX importer — Animation tab

Per-clip settings (each FBX can hold many clips):

- **Clip range** — Start / End frames. Trim idle padding from authoring.
- **Loop Time** — enable looping playback.
- **Loop Pose** — when on, blends start and end pose for seamless loops. Required for cyclic locomotion clips.
- **Cycle Offset** — phase shift on the loop start.
- **Root Transform Rotation / Position (Y) / Position (XZ)**:
  - **Bake Into Pose** — strips that channel from root motion (the clip won't drive that axis).
  - **Based Upon** — Original / Body Orientation / Center of Mass / Feet (root position only).
  - **Offset** — adjustment to the bake.
- **Mirror** — flip left/right (cheap symmetry).
- **Mask** — per-clip avatar mask (rare; usually mask at the layer level).
- **Curves** — additional curves to drive parameters by name.
- **Events** — AnimationEvent list. EDIT EVENTS HERE for FBX-imported clips, not on the `.anim` subasset.

## Hand-authored .anim

- Create via the Animation window's record button on a GameObject — Unity creates a `.anim` and a controller if missing.
- Records property changes as keyframes. Right-click a property to add Constant / Linear / Auto tangents.
- Curves Editor (bottom of Animation window): edit tangent handles directly. Useful for UI ease curves.
- Add Property: any serialized property on the GameObject or its children (transform, material color, custom MonoBehaviour fields with `[SerializeField]`).
- Sample Rate (frames per second) — affects display only; clip is keyframed at exact times.

## Loop checklist

- Loop Pose ON for cyclic clips.
- First and last keyframe match (run-through animation: foot positions, body position).
- Cycle Offset 0 unless you need to phase a duplicate.

## Retargeting troubleshooting

- Limb twists: bone roll is wrong. Re-Configure the Avatar's T-pose; press Enforce T-Pose then Apply.
- Sunken hips: source rig hip height differs. Adjust Root Transform Position (Y) > Based Upon to "Feet".
- Sliding feet: scale mismatch between source clip and target rig. Match Avatar Definition or bake root motion in DCC.

## File-on-disk conventions

- Character FBX: `Char_<Name>.fbx` with skeleton + bind pose.
- Animation-only FBX: `Anim_<Name>_<Clip>.fbx` with no mesh, just skeleton + animation. Set Avatar Definition to Copy From Other Avatar (point at the character FBX's avatar).
- `.controller` and `.overrideController` next to the character.
- Avatar masks under `Assets/Animation/Masks/`.
