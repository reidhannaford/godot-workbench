# Working on Workbench

## Layout

- `addons/workbench/`: the addon, the only folder another project needs. `plugin.gd` builds the toolbar and shortcut; `workbench_controller.gd` puts the mode on the four editor viewports and takes it off, and runs the hidden viewports for x-ray (overdraw) and wireframe; `workbench_effect.gd` is the `CompositorEffect` that drives `workbench.glsl`; `workbench_settings.gd` reads and writes the Editor Settings; `workbench_updater.gd` looks up the latest GitHub release and installs it over the folder; `matcaps/` holds the bundled matcaps.
- `test/`: a scene with heavy fog, glow and coloured lights to prove the mode on, and the headless test.
- `tools/`: `run_tests.sh`, `sync_to.sh <project>`, `capture.sh` with `capture.gd` (windowed screenshots of every mode into `docs/captures/`, gitignored) and `make_matcap.gd` (bakes every image in `matcaps/`).
- `docs/`: this file and the README images.

## Conventions

- All GDScript is statically typed: every variable, constant, parameter, return value (including `-> void`) and loop variable has a type, explicit or inferred with `:=` where the right-hand side makes it obvious. Typed collections; narrow with `as`.
- Everything in `addons/workbench/` is editor code: `@tool` on every script, nothing that runs in exported games.
- The addon depends only on Godot. It never touches the edited scene: only the editor cameras and viewports, and it restores what it changed.

## The engine proposal

The addon exists to prove the look and then propose it as an engine debug draw mode. Only part of it is that proposal; the rest is scaffolding that stands in for what an addon can't do and that an engine implementation would not carry over. Keep the two apart when adding a feature, and ask of each one: is the new code the look, or a stand-in for an engine pass, and does it stay off the scene's objects?

What carries over, the proposal:

- `workbench.glsl` apart from the `depth_export` branch: studio light, matcap, cavity, silhouette and crease lines, the x-ray blend, the wireframe compositing with its opacity and angle threshold, and the line colour and width in points. These are the decisions an engine mode has to make, and the shader states them in one place.
- The neutral view: no scene lights, fog, glow, ambient, tonemapping or exposure, a flat background, lines drawn before the sky and the transparent pass so gizmos and see-through objects land on top.
- The user-facing shape: one toggle beside the view menu, options that are Editor Settings, the shortcuts.

Neither, just the addon's housekeeping: the About dialog and the update check at the bottom of the options menu, and the dot on the menu button when a newer release is out.

What does not, the scaffolding, with what the engine would do instead:

| In the addon | Why it is there | In the engine |
| --- | --- | --- |
| Environment, attributes and compositor swapped onto the editor cameras between `frame_pre_draw` and `frame_post_draw` | The addon can only reach the render through the camera, and the editor saves what it finds on the camera | The debug draw mode skips the environment and post-processing itself, as Unshaded does |
| MSAA off on the editor viewports | A post-opaque write only survives without MSAA | The mode resolves or draws where it pleases |
| The hidden overdraw viewport for x-ray, and the layer count read back from its green channel | An addon can't render the scene a second way into the same buffers | A second pass, or the same pass without depth write, into the one frame |
| The hidden wireframe viewport, the `depth_export` effect on its camera, the depth packed into two 16-bit halves and the screen-space depth tolerance | The same, plus one viewport's effect can't read another's depth | A line-polygon-mode pass over the opaque depth with a depth bias, as Blender's overlay engine draws it |
| The wireframe threshold read off the normal buffer | The addon has no mesh | Face angles from the mesh, as Blender computes them, which also handles smooth shading |
| Random Colour's per-instance material overrides through the RenderingServer (on the `random-color` branch, not merged) | An addon has nothing per object to read from a camera or viewport | A hash of the instance index in the shader |

The scaffolding has a cost the proposal would not: x-ray and wireframe each add a full render of the scene per editor viewport, and Random Colour writes to every geometry instance for the session. That cost is accepted here to prove the look, not as the design. Random Colour is on its own branch because it is the one feature whose stand-in touches the scene's objects, even if only in the server; everything on `main` keeps to editor-owned nodes and the editor cameras.

## Running the checks

Godot 4.7.2 is assumed at `/Applications/Godot 4.7.2.app/Contents/MacOS/Godot`; set `GODOT` to use another binary.

```bash
tools/run_tests.sh
```

runs `test/plugin_test.gd` with `--headless --editor` under a throwaway `HOME`: the plugin loads, the toggle is in the toolbar, and the controller takes over and restores the viewports. Expect `FAILURES 0`. Headless Godot has no RenderingDevice, so the effect itself is inert there; the shader is only exercised windowed.

For the look:

```bash
tools/capture.sh
```

It runs `tools/capture.gd` in a windowed editor under a scratch `HOME` at 1600x900. The script reads the Camera3D in `test/test_scene.tscn` and writes the scene's edit-state file (`.godot/editor/test_scene.tscn-editstate-<md5>.cfg`, which the editor reads when it opens the scene) so the editor looks through that camera, with camera and light gizmos hidden; the scene is then opened in distraction-free mode so the viewport fills the window. It saves `docs/captures/before.png`, `studio.png`, `studio_texture.png`, `matcap_normal.png`, `matcap_contrast.png`, `studio_xray.png`, `studio_xray_wireframe.png`, `studio_wireframe.png` and `studio_wireframe_threshold.png` (the angle threshold at 30 degrees, set through Editor Settings) with cavity, outline and crease lines on, `studio_ortho.png` in the orthographic view, and `after.png` with the mode off again; each also as `<name>_view.png`, the viewport alone trimmed to a centred 16:9, the framing of the camera's own preview. The README images in `docs/images/` are taken by hand from the editor, as WebP, framed through the scene's camera; the capture's `_view` crops are a check, not the README set.

After changing `workbench.glsl`, a windowed run is also the compile check: a bad shader prints `Workbench: the compute shader failed to compile` with the GLSL error.

## Gotchas

- The `.glsl` is loaded, not preloaded: on a project's first scan it isn't imported yet when the scripts compile.
- The normal and roughness prepass only runs when the camera has a valid environment, which is one reason the controller always sets one.
- A post-opaque write only survives without MSAA; with MSAA the colour buffer is resolved after the transparent pass, overwriting it. The controller turns MSAA off per viewport while active, and the editor re-applies project settings to its viewports on a settings change, which is why MSAA is re-asserted before every draw.
- The editor saves its View Environment toggle in the per-scene edit state as `use_environment = camera->get_environment().is_valid()`, and on load toggles the menu item whenever that differs from the camera. An environment left on the camera between frames is therefore saved as the user's choice, and the scene reopens with View Environment off and a grey background. So the controller only puts its environment, compositor and debug draw on the cameras between `RenderingServer.frame_pre_draw` and `frame_post_draw`; the editor renders single-threaded, so both fire synchronously around the draw and no editor code runs in between.
- A `RefCounted` can't be named `_get`, `_set` or any other Object virtual; the settings helper is `_read`.
- Preload constants need addon-specific names (`WorkbenchSettings`, not `Settings`): a game project with a global `class_name` of the same name makes the plugin fail to parse there, even though it parses fine here.
- X-ray rests on three editor facts, all checked in the 4.7.2 source: the Overdraw debug draw replaces every material with `blend_add, unshaded`, ALBEDO (0.4, 0.8, 0.8) and ALPHA 0.1 on a black clear, so each surface adds 0.08 of green and the layer count is `g / 0.08`; the editor cameras cull the game's 20 layers plus their own gizmo, grid and tool layers at bits 24 to 30, which the x-ray camera masks out; and the RenderingServer draws child viewports before their parents, so a SubViewport added under the editor's viewport is current in the same frame. The hidden viewport renders in HDR (`use_hdr_2d`) so its texture is linear and read as stored.
- The overdraw material override only exists in builds with `DEBUG_ENABLED`, which every editor build is.
- Lines are drawn in pixels of the internal render buffer. The setting is in points: the plugin multiplies it by `EditorInterface.get_editor_scale()` (2 on a 2x display) and the effect by internal size over target size, so a 3D render scale below 1 doesn't thin them. The silhouette and crease tests look up to `outline_width` pixels along +x and +y (and -x, -y for the silhouette) so the line lands on one side of an edge at that width.
- Wireframe rests on the editor's Wireframe debug draw, which in Forward+ (checked in the 4.7.2 source) rasterizes every mesh in the line polygon mode, in the depth prepass and the opaque pass alike, with the mesh's own materials and no material override. The hidden wireframe viewport therefore has real depth for every edge pixel, but one viewport's compositor effect can't read another viewport's depth buffer, so the wireframe viewport's camera carries a second instance of the same effect with `depth_export` on, which writes 1 into red and the raw depth into green and blue (coarse and fine halves, since the HDR colour buffer is 16-bit float) for every pixel that has geometry. The main effect reads that texture and lines an edge only where it is no farther than the solid surface under it, within the surface's own depth slope across a pixel plus 0.2% of the distance. The lines are polygon-mode lines, one device pixel wide, dilated to `outline_width`. The angle threshold is the largest normal difference between an edge pixel and its eight neighbours on the same surface in the main normal buffer, which is the face angle for flat shading and next to nothing for smooth shading; a neighbour across a depth jump counts as a boundary and keeps the edge. The sliders live in a `PopupPanel`, since a `PopupMenu` can't hold controls.
- `EditorSettings.set_setting` emits `settings_changed` synchronously when the value changes. The plugin's handler reloads every setting, so during its own `save()` it would reload the ones not yet written over the ones just set; `_save_settings` sets `_saving` around the save and the handler returns while it is on.
- Check for Updates… reads `releases/latest` from the GitHub API and compares its tag with `version` in `plugin.cfg`, so a release has to be tagged `vX.Y.Z` and published for the check to see it. The install downloads the release's `.zip` asset (or GitHub's archive of the tag if there is none), writes everything under `addons/workbench/` in it over the folder, deletes the files the new release doesn't ship, rescans the filesystem, then disables and re-enables the plugin so the editor runs the new scripts. The updater is a node under the editor's base control, not the toolbar: the plugin only `queue_free`s it on the way out, so it survives the disable it caused long enough to re-enable. The startup check is skipped under the headless display server, which keeps the tests off the network; `workbench/check_for_updates` turns it off for a user.
- `RenderSceneData.get_cam_projection()` is the reversed-Z render projection, and `Projection.get_z_near()` / `get_z_far()` return -0.05 and 0.05 for it. The effect passes the matrix's `z.z` and `w.z` entries and the shader inverts the depth row itself: perspective `depth = w.z / d - z.z`, orthographic `depth = w.z - z.z * d`. The capture's `studio_ortho.png` checks the orthographic branch; it switches the view through the viewport's own view menu, since an `orthogonal` flag in the edit-state file is not honoured.

## Releasing

1. Bump `version` in `addons/workbench/plugin.cfg` and add the entry to `CHANGELOG.md`.
2. Run `tools/run_tests.sh` and the capture.
3. `git archive HEAD | tar -t` should list only the addon, `README.md`, `LICENSE` and `CHANGELOG.md`.
4. Commit, tag `vX.Y.Z` and push the tag.
5. `git archive --format=zip --prefix=workbench-X.Y.Z/ vX.Y.Z addons/ -o workbench-X.Y.Z.zip` makes the Asset Store upload: the addon folder only, with its own licence and README copies. Leave the root README, LICENSE and CHANGELOG out of this zip (a store reviewer asked for it after 1.3.0): the addon folder already has the README and licence, and loose files at the zip root are ambiguous and collide when several addons are installed into one project. Attach it to the GitHub release and upload it on the store's Versions tab.
6. `tools/make_thumbnail.sh` rebuilds `docs/store/thumbnail.png` (16:9, the store's listing image) from the README images, if they changed.
