# Asteroid Miner sprites

141 sprites (228 PNG files) made from the approved sample canvas, plus new sprites for the Sun, all eight planets, Ceres and 20 moons.

`overview.png` shows every sprite. The ships, asteroids and bodies in it are shown lit by their normal maps, the way the shader will light them.

## Installing

Copy the `sprites` and `shaders` folders into the Godot project folder (next to `project.godot`). They become `res://sprites/` and `res://shaders/`. Godot imports the PNG files by itself. Leave `README.md` and `overview.png` out of the project.

For the Android export, PNG files are packed automatically. `sprites.json` is only packed if `*.json` is in the export filter. The data notes in the project already ask for that filter, so check it is set.

## What each file is

| File | What it is |
| --- | --- |
| `name.png` | The sprite in flat colours, with no light or shadow baked in. |
| `name_n.png` | Normal map for the lighting shader. Only for sprites that have relief. |
| `name_glow.png` | Parts that give off their own light (windows, the tanker's red light). Draw it unlit, on top, same position. |

`sprites/sprites.json` lists every sprite with its files, its size in pixels, its pivot in pixels and its scale.

## Conventions

- **Direction:** every ship, flame and parachute is drawn with the nose pointing right, which is rotation 0 in Godot.
- **Scale:** `px_per_unit` in `sprites.json` is how many pixels one drawing unit takes: 3 for ships, parts, asteroids, effects and parachutes; 2 for bodies and scenery; 1 for the plain skies. All measurements quoted in the notes are in drawing units.
- **Pivot:** the point a sprite should rotate about and be placed by, measured in pixels from the top-left corner of its image. On a Sprite2D: set `centered = false` and `offset = -pivot`.
- **Normal maps:** green channel is up, the usual convention.

## Lighting

`shaders/sprite_lit.gdshader` lights a sprite from its normal map. It has not been run in Godot yet, so expect to fix a detail or two on first use.

- **Ships and asteroids:** set `sun_dir` to the direction of the sun in the sprite's own space (the shader file shows how), and leave `sun_elevation` at about 0.56.
- **Planets and moons:** set `sun_elevation` to 0. That gives a half-lit disc whose dark side faces away from the sun.
- **Reflected light:** `fill_dir` and `fill_strength` add a weak second light, for example from the Moon's bright side.
- **Atmospheric heating:** `heat` (0 to 1) and `heat_dir` (direction of travel) add the orange glow on surfaces facing the flow.
- **Mirrored sprites:** flipping a sprite with a negative scale also flips its lighting. Mirror `sun_dir` on that axis to compensate.

## Folders

### `ships/`
The nine hull types, seen from above. Pivot is the middle of the hull.

### `ships/habitat_parts/`
For the rotating habitat with turning rings. Draw in this order:
1. `habitat_aft`
2. Ring 1: `habitat_ring_body`, then `habitat_ring_face`
3. `habitat_mid`
4. Ring 2: `habitat_ring_body`, then `habitat_ring_face`
5. `habitat_fore` and its glow

Ring 1 sits 20 units aft of the ship pivot and ring 2 sits 44 units forward. Draw each `habitat_ring_face` with `scale.x = 0.22` and rotate it; the two faces turn in opposite directions. `ships/rotating_habitat.png` is the same ship in one piece with the rings not turning.

### `ships/lander_parts/`
`lander_body` has no legs. `lander_leg` is one leg with its pivot on the hinge. The hinge is 32 units aft and 50 units to the side of the lander pivot. Use it twice, the second mirrored. Stowed is the leg rotated 185 degrees and drawn under the body. `ships/lander.png` is the lander in one piece with legs out.

### `ships/ssto_side/`
The lifting body from the side, with `gear_main` and `gear_nose` as separate parts (pivot on the hinge; stowed is rotated 90 degrees and drawn under the hull). Hinges: main gear 68 units aft and 12 below the pivot, nose gear 65 units forward and 12 below.

### `parachutes/`
Each canopy comes with its lines, and its pivot is where the lines meet. Swaying is a small rotation about the pivot. Breathing is a small change of `scale.y`. A packed or limp canopy is `scale.y` between about 0.15 and 0.3. The parachutes have normal maps but no baked shadow.

### `asteroids/` and `comets/`
Four compositions in four sizes. Comet tails are drawn at full size pointing left, with the pivot on the nucleus. Rotate them to point away from the sun, and scale and fade them with sun distance.

### `bodies/`
The Sun, the eight planets, Ceres, and the Moon, Phobos and Deimos. The other 17 moons are in `bodies/moons/`: Io, Europa, Ganymede, Callisto; Mimas, Enceladus, Tethys, Dione, Rhea, Titan, Iapetus; Miranda, Ariel, Umbriel, Titania, Oberon; Triton.

- **Size:** every round body has a disc radius of 192 px, so to draw a body with a radius of `radius_px`, scale the sprite by `radius_px / 192`. Phobos and Deimos are irregular and slightly smaller than their image.
- **Sun:** draw it unlit. Its image includes the corona glow around the disc.
- **View:** every body is seen from above the plane of the orbits, looking down on its northern half.
- **Axial tilt:** on Earth, Mars, Saturn, Uranus and Neptune the north pole is shifted toward the top of the image by the planet's tilt. Keep these sprites pointing the same way in space as the planet orbits; do not turn them with the orbit. Then the lit side sweeps across the pole over the year, which shows the seasons.
- **Ice caps:** Earth has the Arctic cap and Greenland; Mars has its north polar cap. The south caps are on the far side and cannot be seen from this view.
- **Earth's seasons:** `earth` is the northern summer state, with a small, soft-edged ice cap. `earth_snow` is a winter overlay with snow on the northern continents and a larger ice cap. Draw it over `earth` with the same position, scale, rotation and lighting, and set its opacity from the season: `snow = 0.5 - 0.5 * dot(direction_to_sun, tilt_direction)`, where `tilt_direction` is the way the north pole leans (the top of the sprite). That gives 0 when the pole leans toward the sun and 1 when it leans away. Real snow cover lags the sun by a month or so; delay the value if you want that.
- **Rings:** `saturn_rings` and `uranus_rings` are separate sprites. Draw them at the same position and scale as the planet, unlit. Saturn's rings clear the disc, so order does not matter. Draw Uranus's rings over the planet; the part behind it is already cut away.
- **Moons:** drawn without tilt, as they are tiny on screen.

### `effects/`
- **Flames:** `flame_vacuum`, `flame_atmosphere` and `flame_white`, pivot at the engine bell exit. Cross-fade between them with altitude as in the design document. The atmosphere flame is also stretched 1.5 times in length low down.
- **Heating:** `plasma_pointed`, `plasma_blunt` and `plasma_wide` are the shock front, hot gas and streaks in one image, pivot at the tip of the shock. Fade them with `heat`.
- **Burn-up:** `fireball`, eight `fragments/fragment_*` and `fragments/fragment_flame` (drawn over a fragment).
- **Generic:** `glow_white` and `puff_white` are white so they can be tinted. Use them for flashes, sparks, dust, smoke and tyre smoke.
- **Landing:** `dust_sheet`, `splash_spray` and `ripple_ring`.

### `scenery/`
Layers for the side-view landing scenes: `sky/`, `background/`, `props/`, `buildings/` and `ground/`. Backgrounds, ground tiles and the runway repeat seamlessly every 800 units (1600 px). The Moon ground is a fixed 640-unit piece. Pivots are at the bottom left, on the horizon or ground line.

## What is not here

The motion itself. The canvas samples animate these pieces; in the game that motion has to be driven by code or an AnimationPlayer. Timings and distances for each animation are in the captions on the sample canvas.
