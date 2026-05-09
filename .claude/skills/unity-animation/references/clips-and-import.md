# AnimationClip authoring and FBX import reference

## FBX importer — Rig tab

- **Animation Type** — None / Legacy / Generic / Humanoid. Pick once per asset; flipping retroactively breaks references.
- **Avatar Definition**:
  - `Create From This Model` — generates an Avatar alongside this FBX.
  - `Copy From Other Avatar` — share one Avatar across multiple character FBXs (preferred when many clips target the same skeleton).
- **Skin Weights** — max bones per vertex. Default 4; raise only for high-end PC.
- **Optimize Game Objects** — strips bone Transforms from runtime hierarchy. Saves CPU on animator update; breaks code that walks `GetComponentsInChildren<Transform>()` for bones, and prop attachment targeting bone GameObjects. Use **Extra Transforms to Expose** to whitelist needed bones.
- **Configure...** — opens Avatar editor. Fix bone mappings if humanoid retarget looks broken.

## FBX importer — Animation tab

Per-clip (each FBX can hold many clips):

- **Clip range** — Start/End frames. Trim authoring padding.
- **Loop Time** — enable looping playback.
- **Loop Pose** — blends start/end pose for seamless loops. Required for cyclic locomotion.
- **Cycle Offset** — phase shift on loop start.
- **Root Transform Rotation / Position (Y) / Position (XZ)**:
  - **Bake Into Pose** — strips that channel from root motion (clip won't drive that axis).
  - **Based Upon** — Original / Body Orientation / Center of Mass / Feet (root position only).
  - **Offset** — adjustment to the bake.
- **Mirror** — flip left/right (cheap symmetry).
- **Mask** — per-clip avatar mask (rare; usually mask at layer level).
- **Curves** — additional curves driving parameters by name.
- **Events** — AnimationEvent list. EDIT EVENTS HERE for FBX-imported clips, not on the `.anim` subasset.

## Hand-authored .anim

- Animation window's record button on a GameObject creates a `.anim` and controller if missing.
- Records property changes as keyframes. Right-click property → Constant / Linear / Auto tangents.
- Curves Editor (bottom of Animation window): edit tangent handles directly. Useful for UI ease curves.
- Add Property: any serialized property on the GO or children (transform, material color, custom MonoBehaviour fields with `[SerializeField]`).
- Sample Rate (fps) — display only; clip is keyframed at exact times.

## Loop checklist

- Loop Pose ON for cyclic clips.
- First and last keyframe match (run animation: foot positions, body position).
- Cycle Offset 0 unless phasing a duplicate.

## Retargeting troubleshooting

- Limb twists: bone roll wrong. Re-Configure Avatar's T-pose; Enforce T-Pose then Apply.
- Sunken hips: source rig hip height differs. Adjust Root Transform Position (Y) > Based Upon to "Feet".
- Sliding feet: scale mismatch source vs target. Match Avatar Definition or bake root motion in DCC.

## File-on-disk conventions

- Character FBX: `Char_<Name>.fbx` with skeleton + bind pose.
- Animation-only FBX: `Anim_<Name>_<Clip>.fbx` — no mesh, just skeleton + animation. Avatar Definition = Copy From Other Avatar (point at character FBX's avatar).
- `.controller` and `.overrideController` next to the character.
- Avatar masks under `Assets/Animation/Masks/`.
