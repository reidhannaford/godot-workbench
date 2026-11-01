# Changelog

## Unreleased

- **Wireframe**: a line along every mesh edge, as Blender's Wireframe overlay draws, in the options menu and on Alt+Shift+W by default (`workbench/toggle_wireframe`). **Wireframe Options…** opens Blender's two sliders: the lines' opacity, and an angle threshold that keeps only the edges where the surfaces either side meet at that angle or more, so the diagonals across flat quads go first; both are also `workbench/wireframe_opacity` and `workbench/wireframe_threshold` in Editor Settings. The width follows `workbench/outline_width`. Only the edges in front are drawn. The edges come from a second hidden render per editor viewport, in the editor's Wireframe debug draw, whose depth is exported and tested against the solid surfaces; with X-ray on, the hidden edges show through as much as the front surface does. Godot draws every triangle edge, so quads show their diagonals.
- Fixed: changing two options in one go, such as picking a bundled matcap while in studio lighting, could lose one of them. The editor reports each setting as it is written, and the plugin reloaded all of them half-way through its own save, so a value not yet written overwrote the new one. The capture's x-ray and orthographic shots were being taken in the Contrast matcap because of it.

## 1.3.1, 2026-10-29

- The release ZIP for the Asset Store holds only `addons/workbench/`, which already carries its own licence and README. The root README, LICENSE and CHANGELOG are no longer at the ZIP's root, where they were ambiguous and collided when several addons were installed into one project. No change to the addon itself.

## 1.3.0, 2026-10-28

- Renamed to **Workbench**, after the Blender engine that draws its Solid mode, since the addon covers that mode's whole range: studio light, matcaps, texture colour, cavity, outlines and x-ray. The folder is `addons/workbench/`, the toolbar toggle says Workbench, the Editor Settings live under `workbench/…` and the shortcuts under `workbench/toggle` and `workbench/toggle_xray`. **Upgrading from Solid View:** delete `addons/solid_view/` (or run `tools/sync_to.sh`, which does), enable Workbench under Project Settings > Plugins, and set your options and shortcut bindings again, since the keys moved.
- A copy of the licence and a short README ship inside the addon folder, and each release carries a ZIP of the addon, for the Asset Store.
- README images in six panels, through the test scene's own camera: as lit, solid, texture colour, x-ray, and the normal and contrast matcaps.

## 1.2.0, 2026-10-28

- Six more bundled matcaps beside clay, in a **Bundled MatCaps** submenu: Normal (the normal as a colour, like Blender's check_normal), Contrast (two tones with a rim), Toon (three cel bands), Zebra (a reflection check), Wax (red sculpting wax) and Chrome (sky over floor). All are baked by `tools/make_matcap.gd`.
- A matcap is shown at its own brightness in flat colour, instead of dimmed to 80%; clay is baked darker to keep matching the studio light. Texture colour still multiplies the matcap by the albedo.

## 1.1.0, 2026-10-28

- **X-ray**: see through the front surfaces to the geometry behind them, as Blender's X-ray does. In the options menu, Alt+Shift+Z by default (`solid_view/toggle_xray`), opacity under `solid_view/xray_alpha` in Editor Settings. Hidden geometry comes from a hidden per-viewport overdraw render, so it shows as a ghost with silhouette lines rather than shaded.
- **Crease Lines** option: with Outline on, a line along creases sharper than 45 degrees within a surface, so a box's corner edges get lines, not only its silhouette.
- **Outline width** setting (`solid_view/outline_width`, in points), scaled to the display and to the 3D render scale, so the outline is no longer a single device pixel on a 2x display. X-ray's hidden-silhouette lines follow the same width.
- Edits in Editor Settings > Solid View apply at once instead of at the next editor start.
- The editor cameras also get neutral camera attributes during the draw, so a scene's exposure or auto-exposure no longer changes the solid shading.
- Fixed: the outline, crease and cavity tests worked from wrong distances. The projection the effect receives is Godot's reversed-Z render matrix, and `Projection.get_z_near()` / `get_z_far()` return nonsense for it (-0.05 and 0.05), which squashed every depth to about the same value. The silhouette only ever fired against the sky or on very close objects, which the small test scene hid. Distances now come from the matrix's own depth entries, in perspective and orthographic views.
- Fixed: gaps in the line where an edge turns from a contact into an overhang, such as the foot of a post, and dashes along the base of anything sitting a hair above or below its floor. The crease test now scores a depth jump the way the silhouette test does, against the surface's own slope, and hands over to it only once its line is fully on.

## 1.0.2, 2026-10-27

- Fixed: a scene saved while Solid was on reopened with the editor's View Environment off and a grey background. The addon now only puts its environment, compositor and debug draw on the editor cameras while a frame is being drawn, so the editor's own view state is what gets saved. Scenes already affected: tick View Environment in the viewport's View menu once and save.

## 1.0.1, 2026-10-27

- The outline now draws on smaller depth steps, so a box top against the floor behind it keeps its edge from a steep view. Flat surfaces are still edge-free.
- README images retaken with cavity and outline on.

## 1.0.0, 2026-10-27

First release.

- A **Solid** toggle in the 3D toolbar, Alt+Z by default.
- Studio lighting or a matcap, flat or texture colour, cavity and outline.
- A bundled clay matcap and a file picker for any other image.
- Options kept in Editor Settings under `solid_view/`; the options menu stays open while ticking them.
