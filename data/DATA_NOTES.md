# Prototype body data: notes

Files:

- `data/bodies.json` – Sun, Earth, Moon, Mars, Phobos, Deimos and Ceres, following the data model in the design document.
- `data/facilities.json` – the Ceres propellant plant (exists from the start in this prototype).
- `scripts/kepler.gd` – Kepler orbit maths (position of a body on rails at any date).
- `scripts/system_view.gd` – a small test view that draws one system at a time and has time warp (build order step 4).

## Using them in the Godot project

1. Copy the three files into the project, keeping the folders (`res://data/`, `res://scripts/`).
2. Create a new scene with a **Node2D** as root, attach `system_view.gd`, save it as `main.tscn` and set it as the main scene. Bodies are plain circles, so no graphics are needed.
3. Run it. Tab (or a tap on the top half of the screen) switches between the Sun, Earth and Mars systems, Space pauses, and `+` / `-` (or a tap on the bottom right / left) change the time warp.
4. **Android export:** Godot only packs `.json` files if told to. In Project, Export, Resources, add `*.json` to "Filters to export non-resource files/folders". Without it the phone build shows an empty screen and logs "Cannot read res://data/bodies.json".

These scripts were not run in Godot (it is not available where they were written). The orbit maths was mirrored line by line in Python and checked (see below), but expect to fix a typo or two the first time you press Play. Send me the error text if so.

## Units and conventions

Kilometres, days (Julian Date), degrees, GM in km³/s², mass in kg. The game starts on 2035-01-01 00:00 (JD 2464328.5). Dates are treated as a plain continuous day count, with no leap-second or time-scale corrections.

## Sources

| Data | Source |
| --- | --- |
| Earth and Mars orbits | [JPL, Approximate Positions of the Planets](https://ssd.jpl.nasa.gov/planets/approx_pos.html), Table 1 (valid 1800–2050), base values at J2000 |
| Moon, Phobos, Deimos orbits | [JPL, Planetary Satellite Mean Elements](https://ssd.jpl.nasa.gov/sats/elem/sep.html), epoch 2000-01-01.5 |
| Ceres orbit | [Space Reference](https://spacereference.org/asteroid/1-ceres-a801-aa), which lists the JPL Small-Body Database elements for epoch JD 2460200.5 (rounded values) |
| GM of Sun, Earth, Moon, Mars | [JPL, Astrodynamic Parameters](https://ssd.jpl.nasa.gov/astro_par.html) (DE440); astronomical unit 149 597 870.7 km |
| Radius and GM of Moon, Phobos, Deimos | [JPL, Planetary Satellite Physical Parameters](https://ssd.jpl.nasa.gov/sats/phys_par) |
| Mass, radius, atmosphere of Earth, Mars; Sun mass and radius | NASA fact sheets: [Earth](https://nssdc.gsfc.nasa.gov/planetary/factsheet/earthfact.html), [Mars](https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html), [Sun](https://nssdc.gsfc.nasa.gov/planetary/factsheet/sunfact.html) |
| Moon mass | NASA Moon fact sheet (archived copy) |
| Ceres mass and radius | [Wikipedia, Ceres](https://en.wikipedia.org/wiki/Ceres_(dwarf_planet)) infobox (mass from Dawn) |

## Derived values (computed, not copied)

- **Earth and Mars elements:** semi-major axis = a (AU) × AU; argument of periapsis = long.peri. − long.node; mean anomaly = L − long.peri.; mean motion = rate of L ÷ 36525 (gives 365.256 d and 686.980 d, matching the NASA fact sheets).
- **Phobos and Deimos mean motion:** Kepler's third law from a and GM (Mars + moon). Periods come out at 0.31898 d and 1.26243 d.
- **Ceres mean motion and GM:** mean motion from Kepler's third law (period 1681 d); GM = mass × G (62.63 km³/s²).
- **Phobos and Deimos mass:** GM ÷ G.
- **Moon mean motion:** from JPL's period of 27.322 d. Kepler's law with the mean semi-major axis would give 27.285 d (the Sun perturbs the Moon's orbit), which would drift the phase noticeably over decades.

## Simplifications to keep in mind

- **2D map:** inclination is ignored. Each orbit is an ellipse in the map plane, rotated by the longitude of periapsis (node + argument of periapsis).
- **Apsides held fixed:** only the mean anomaly advances over time. Against JPL's own formula with precession rates, the Earth ends up about 10 000 km off in 2035 and Mars about 77 000 km (about 0.0005 AU), which is invisible on a map and irrelevant to transfer planning.
- **Earth** is placed on the Earth-Moon barycentre orbit from Table 1. The offset between the barycentre and Earth's centre is ignored.
- **Mars GM** is the Mars system value, including Phobos and Deimos.
- **Phobos and Deimos** use mean elements referred to Mars's local Laplace plane. JPL says these are not meant for ephemeris use, and in a 2D map their orientation angles only set the starting phase.
- **Ceres elements** come from a secondary mirror and are rounded (a to 0.001 AU, angles to 0.01°). The error is small for a game, but the exact SBDB values should replace them when convenient.
- **Orbit segments:** each body has a list. A later segment (for example after an impact) is added with its epoch set to the time of the change, and `Kepler.segment_at` picks the one that applies.

## Proposals for you to review (not from sources)

- **Resources:** each entry has `quantity_kg` (-1 = infinite) and `availability` (0 to 1, high = easy to extract). Availability sets the output per unit of time for given labour and equipment; cost differences only follow from needing more labour, equipment, life support or robots. Water (one id, `water`, for liquid and ice alike) is infinite on Earth (availability 1.0, already liquid), the Moon (0.15), Mars (0.3) and Ceres (0.4). The availability numbers are placeholders for balancing. Sun, Phobos and Deimos have none.
- **Home flag:** Earth.
- **Impact thresholds:** left as `null` until the impact system is built.
- **Atmosphere:** only surface density and scale height are set (exponential model). The altitude where an atmosphere starts to matter is left to a game constant, so it can be tuned.
- **Draw colours:** only used by the test view.

## Checks performed

- On 2035-01-01 Earth is at heliocentric longitude 99.9° and 0.9833 AU, as expected shortly before the early-January perihelion.
- On 2035-09-15 Earth and Mars are at the same heliocentric longitude (351.5° and 351.8°), which fits the Mars opposition of mid-September 2035 (the date is from memory, not from a source). This checks both orbits and their mean motions together.
- The mean motions from the table and from Kepler's third law agree to 4 × 10⁻⁶ (Earth) and 2 × 10⁻⁵ (Mars).
- After exactly one period every orbit returns to its starting position to within 0.0002 km, so the Kepler solver converges.

## Facilities and routes (build step 8)

- **Ceres propellant plant** (`facilities.json`): turns water into propellant. Output per day = peak output (1000 kg/day) x availability of water on Ceres (0.4) x conversion (1.0), so 400 kg/day. Storage 500 000 kg, starts empty at the game start. All numbers are placeholders.
- **Arrival orbit altitude** (`default_orbit_altitude_km` in `bodies.json`): Earth 400, Moon 100, Mars 400, Ceres 100, Phobos 20, Deimos 20. Placeholders.
- **Destinations** from a body: its own moons; if it is a moon, its planet and the planet's other moons; and the other planets and dwarf planets that orbit the Sun.
- **Route types** (all 2D patched conics): a moon of the body the ship orbits; from a moon to its planet (no window, leaves at once); between two bodies around the same body (two planets, or two moons of one planet); from a moon to another planet (the escape from the moon is estimated assuming the best direction, the moon's phase is not modelled). The transfer is a half ellipse between the actual distances at departure and arrival.
- **Fuel:** the ship's tank is a delta-v tank. The design screen saves the total propellant and delta-v, and the game derives an equivalent single stage from them with the rocket equation (average exhaust velocity weighted by propellant mass, and the dry mass that gives the same delta-v). So the propellant mass and the delta-v of the tank always match, and burns and refuelling move along that curve. Stage structure is ignored.

## Settings and facility types (step 8c)
- `settings.json`: start budget (EUR, placeholder 1e12) and the facilities present at game start (a shipyard at Earth).
- `facilities.json`: facility *types*. A type with a `kit` can be bought at a shipyard (cost_eur, mass_kg of the ship's payload) and deployed from orbit at a body where its resource is available. The Ceres propellant plant is no longer prebuilt.

## Aerobraking (step 9)
- `atmosphere` in bodies.json (Earth, Mars): surface_density_kg_m3, scale_height_km, min_periapsis_altitude_km (placeholder floor for the planner). Exponential atmosphere; a pass starts where the density is 1e-8 kg/m3.
- Pass physics: RK4 in the orbit plane, drag = rho v^2 / (2 beta), beta = mass / (1.5 x area); heating = Sutton-Graves (1.7415e-4 sqrt(rho / nose radius) v^3), nose radius = sqrt(area / pi); peak deceleration in g. No lift.
- Ship size: sphere of 300 kg/m3 average density (placeholder until hull types exist). Shield: 3 kg per m2 per cm of thickness, 15 MJ/m2 of heat load per cm (placeholders). Planner uses at most 80% of the remaining shield and a 10 g limit (cargo only).
- Several passes use the same periapsis altitude; the trim burns between passes are ignored.
- A pass that overloads the shield or the g limit damages ship health in proportion to the excess. `shield_cost_eur_per_kg` (settings.json) is the price of a replacement shield at a shipyard.

## Target orbit and warnings (step 9b)
- Every transfer ends in a target orbit {rp_alt_km, ra_alt_km, offset_deg} (altitudes above the surface), chosen with the `OrbitControl` (periapsis, apoapsis, axis offset) and remembered per destination body in `GameState.target_orbits`. Default: circular at the body's `default_orbit_altitude_km`. The control keeps apoapsis > periapsis by an invisible 0.001 km (lowering the apoapsis below the periapsis pulls the periapsis down; raising the periapsis above the apoapsis pushes the apoapsis up). A gap below 0.0105 km counts as circular; then the offset is greyed out.
- Capture burn = burn at the target periapsis from the arrival energy (`TransferPlanner.capture_dv`). The axis offset only turns the drawn orbit (it counts from the arrival direction, costs no delta-v, and makes the ship jump to the rotated orbit at the end); a ship leaves a non-circular orbit from its periapsis.
- Aerobraking passes aim at the target apoapsis, then burns raise the periapsis to the target and fix the apoapsis (`AeroBraking.final_dv`). The periapsis slider covers +/- 8 km around the current setting (`BAND_KM`); the number box takes any altitude.
- The shield display is the shield's capacity before the manoeuvre, saturated between that and 0%.
- Nothing is blocked: the planner only warns (plan["outcome"], plan["warning"]). Outcomes: `too_slow` (the ship slows down too much to leave the atmosphere), `escape` (still too fast), `crash` (target periapsis below the surface), `burn_up` (below `min_periapsis_altitude_km`). On arrival such a ship is lost (health 0; placeholder rules). A target periapsis inside the upper atmosphere only warns that the orbit will decay.
- Axis offset (revised): when a ship arrives from outside the sphere of influence, the arrival periapsis is assumed to be aimed at the target orbit's axis, so passes and the final apoapsis already sit where the target orbit wants them (no cost, no jump). The Moon-to-Earth transfer cannot be aimed; there the axis is turned with a burn at the crossing of the two ellipses (`AeroBraking.axis_turn_dv`, 2 e sqrt(mu/p) sin(offset/2)), added to the arrival burn.
- Departure from a non-circular parked orbit (planets/moons leaving the origin's sphere of influence): the periapsis direction needed for the escape is `TransferPlanner.escape_axis_deg`; within `AXIS_TOLERANCE_DEG` (10) the ship leaves from the periapsis at no extra cost, otherwise the plan adds a circularisation burn at the apoapsis and leaves from the apoapsis radius (included in dv_departure, shown in the plan text; plan["dv_circularize"]). Transfers to a moon of the origin body use the ship's real orbit position already; departures from a moon to another planet are unchanged (direction not modelled).
- If periapsis and apoapsis of the parked orbit differ by less than 5% of the apoapsis (`MissionPlanner.NEARLY_CIRCULAR`), the orbit's axis is ignored for departures: no circularisation, the ship leaves from the periapsis radius.
- Launch safeguards: a plan that ends badly asks for confirmation ("Launch anyway"). "Abort launch" is available between Launch and the departure burn: refunds the launch cost, uncommits the plan and keeps all its settings. A plan can still be launched up to 5 minutes after its departure time (`LATE_LAUNCH_DAYS` in orbit_view.gd).

## Course changes in flight (step 9g)
- The mission can be changed at any time during a transfer: Plan is available in flight (not during aerobraking passes). `CourseChange` solves Lambert's problem from the ship's position (on its current leg) to the chosen destination for 160 + 60 flight times and takes the cheapest burn + capture. Destinations are the bodies that orbit the body the ship is flying around. Hyperbolic/retrograde solutions and ones that dip below 1.05 x the central body's radius are skipped.
- The plan being followed is kept (`GameState.saved_plan`) while a draft is open ("Keep current course" drops the draft); time keeps running on the saved plan. Launching the change replaces the later legs; "Abort launch" before the burn restores the old plan. A course change costs no launch cost, only propellant: nothing stops the player from planning something the fuel cannot finish, and a ship left on a bad course is lost.
- Warnings about an unsafe plan are shown in an orange line above the plan text before launching; the button stays "Launch", and the confirmation dialog appears when pressing it.
- Fix (9i): course-change plans now get their capture legs/aerobraking data (`AeroBraking.setup_plan`); before, the ship never switched to the orbit around the destination.
- The destination list always includes the body the ship is at (parked) or flying around (in flight), shown as "Orbit around X". Parked: `MissionPlanner._plan_orbit_change` (two apsis burns, defaults to the current orbit). In flight around a planet/moon: `CourseChange._central_plan` finds the cheapest burn onto a path with the chosen periapsis (any periapsis direction), then the usual capture/aerobraking applies. Not offered in the Sun's frame.
- Top bar (9m): shows the ship name next to the date, and a line about the current orbit (`GameState.orbit_status_text`): periapsis/apoapsis altitude, axis angle (or "circular"), current altitude, speed relative to the body ("Airspeed" while below the atmosphere's upper limit; on-rails legs do not model the speed lost in a pass).
- Landscape/phone (9p): the top bar's content sits in a ScrollContainer whose height is limited to 70% (portrait) or 55% (landscape) of the screen; the rest scrolls (drag or scroll bar). Set the orientation in Project Settings > Display > Window > Handheld.

## Orbit decay and the launch popup (9q)
- A parked orbit whose periapsis is inside the atmosphere now decays. On first use `GameState._ensure_decay(leg)` simulates
  the passes with `AeroBraking.simulate_pass` (periapsis fixed, energy lost per pass; once there are many passes, one
  simulated pass stands for a group of them, at most 60 groups). Each group sets the leg's orbit lower at its last pass.
- Time warp drops to 1 min/s at the start of every pass (`_next_decay_entry`). Heat goes to the shield and g-load damages
  the ship via `_take_aerobraking_effects`. When the apoapsis falls to the top of the atmosphere (or a pass crashes) the
  ship is lost (placeholder: health 0 + message). Changing the orbit before that replaces the leg, so the decay stops.
- The launch warning popup wraps its text and is sized from the window width (autowrap, `wrap_controls`).

## Ship lost animation (9r)
- `art/burnup/lander_000..119.png`: 10 s, 12 fps, 480x300, transparent. Rendered from the "Burning up / Lander burning up"
  SVG of the "Ship sprite samples" canvas (Heating board) with Playwright (SMIL time stepped per frame). The lifting-body
  version can be rendered the same way when that hull exists.
- `GameState.lost_event` {text, burn} is set by `_lose_ship` (doomed arrival, or decay) and pauses time. `burn` is true when
  the loss happened at a body with an atmosphere. The orbit view shows `ShipLostOverlay` (new class_name: run
  `godot --headless --import` once): animation, tap to skip, then an AcceptDialog "Ship lost". Crashes on bodies without an
  atmosphere (Moon) show only the popup.

## Cargo mass in the delta-v (9s)
- `GameState.dry_mass_kg()` = empty ship + cargo kits. `fuel_for_dv`, `dv_for_fuel`, the aerobraking ballistic coefficient and
  `ship_mass_after_departure` use it, so loading a kit lowers the delta-v for the same propellant and deploying it raises it again.
  Propellant mass is unchanged by loading/deploying. (The shield mass is still part of the empty ship.)

## Delta-v with and without payload (9t)
- Ship design screen shows "Delta-v without payload" (only the shield on top of the stages) and "Delta-v with full payload".
  The saved design adds `dry_empty_kg` and `empty_dv_ms`. Before this the saved `dry_eff_kg` included the full payload mass,
  which made 9s count the payload twice. `GameState.ship_dry_kg` is now the EMPTY ship (older saves: dry_eff minus payload);
  `dry_mass_kg()` adds the kits actually carried. The tank capacity in the orbit screen is the delta-v of a full tank with the
  current cargo. Re-open the ship design screen once so it re-saves the design.

## Launch window search from a high orbit (9u)
- Ship in orbit around a planet, target one of its moons: the window search now covers at least 1.2 synodic periods of ship
  and moon (up to 40 ship orbits) instead of 1.5 ship orbits. Example: ship at 4000 km around Mars to Phobos (synodic
  period about 3 ship orbits) found no window when the ship was on the wrong side.

## Step 10a: automatic view switching
- The "auto" view (default) now follows the ship's distance, not only the leg it is on. Each body has a view radius =
  the distance its view shows at the edge of a portrait screen (the widest orbit of its children, or 4 body radii, or 1.5x the
  ship's orbit when it has no children; divided by VIEW_FILL 0.9). The view shows the body with the smallest view radius that
  contains the ship (Moon -> Earth -> Sun). It switches in at the radius and out at 1.15x the radius (VIEW_HYSTERESIS).
- So arriving at Mars, Ceres or Earth shows the local view as soon as the ship is that close, not at the insertion burn.
- Not done yet: the same rule for manual panning/zooming, and the transfer route is only drawn in the view of the frame it was
  planned in (so right after leaving Earth the route appears once the view has switched out to the Sun).

## Step 10b: local route, warp slowdown, orbit morph
- Local route: the model jumps from the orbit around the origin to the transfer orbit (and from it to the orbit around
  the target) at one point. `GameState.transfer_leg_for_plan` stores that jump (`from_offset`/`to_offset`, with
  `from_ref`/`to_ref`) in the transfer leg; `leg_rel_with_offsets` fades it out over 6x its size, so the ship leaves
  the parking orbit and arrives at the first orbit without a jump. The map draws the same path (`_draw_local_route`) in the
  view of the origin body (escape) and of the target body (insertion), plus the orbits the plan creates there
  (aerobraking passes faint, final orbit stronger). Course changes in flight have no escape part.
- Warp: when the ship is about to get inside the view of a smaller body (smallest_view), time is stopped at the moment it
  gets in and the warp drops to AERO_WARP_INDEX (1 min/s). Leaving a view does not change the warp.
- Morph: legs have `morph_days` = burn time of the burn (`GameState.burn_days`, from the ship's thrust: new
  `thrust_kn` in the saved design = thrust of stage 1, default 1000 kN until the design screen has been opened) or the
  time of one aerobraking pass (`aero["pass_days"]`). Around the start of such a leg (centred on it) the shown orbit goes
  linearly from the old periapsis/apoapsis/axis to the new ones (`GameState.morph_at`); the top bar numbers follow. At
  an insertion the orbit shrinks from a wide ellipse with the same periapsis. No morph for departure to another body.
- Aerobraking warnings: the planner keeps 20% of the remaining shield in reserve (HEAT_MARGIN 0.8). Below that margin it
  suggests propulsive capture (message now says so); if the player switches aerobraking on anyway, the plan shows a
  "Warning: heat shield will have only X% left" line.

## Step 10c: tangential escape/insertion, morph slowdown
- Near the origin / target body the displayed path is now a hyperbola (`GameState._hyperbola`, Kepler's equation for H) with
  its periapsis at the point where the ship leaves the parking orbit / enters the first orbit, so it joins that orbit
  tangentially, and the speed at infinity of the transfer (arrival: sqrt(2 * arrival_energy); departure: the speed of the
  transfer relative to the body). Far away the transfer's own path is used, turned about the body by `delta` so that it comes
  in / goes out along the hyperbola's asymptote; the two are blended between 3 and 12 periapsis radii (`_blend_hyperbola`). It is only
  used when the transfer starts / ends at the body itself; otherwise (for example a moon leaving for another planet) the older
  faded offset is used. The ship follows the same path, with the periapsis at the burn time.
- `_leg_rel` subtracts the body's position inside the leg's own system when the view body is a moon of the leg's parent
  (full precision for Phobos/Deimos views).
- Warp drops to 1 min/s at the start of every visible morph (burns and aerobraking passes that change the orbit), so the morph
  can be watched at high warp. Departure for another body has no morph and no slowdown.

## Orbit change from a circular orbit (10d)
- The burn happens where the ship is, so the transfer ellipse's axis is now taken from the ship's position at the burn (it was the
  circular orbit's arbitrary axis, which showed the ship on an offset ellipse until the second burn). The final circular
  orbit uses the same axis, so the ship continues from where it is. Non-circular orbits are unchanged (burns at the apsides).

## Orbit change ends with its last burn (10e)
- When only one apsis changes (second burn below 0.1 m/s), the orbit change is a single burn: the plan ends one second after it
  (the ship is at the burn point on the new orbit) instead of waiting half an orbit for a zero burn at the other apsis.

## Orbit change from a circular orbit to an orbit with an axis (10f)
- The axis offset counts from the circular orbit's axis (0 deg, as the top bar shows axes). The burns now happen where the new
  periapsis / apoapsis will be, so the ship first flies to that point (no "orbiting through the body"). No extra axis-turn burn.
- If the first burn would be zero (only the second apsis changes), it is skipped: the mission is one burn, at whichever apsis
  point of the new orbit the ship reaches first, and the plan ends with it.

## Step 10h – revert of 10g
The offset is the angle of the PERIAPSIS axis again (0 deg = right, counter-clockwise), for orbit changes and transfers alike, as in 10f.
The top bar shows "axis" again (periapsis direction). 10g and the first 10h attempt were withdrawn.

## Step 10i – approach/escape path lies on the real hyperbola line
- The far part of an insertion / escape path (the transfer's own path) used to aim at the body's centre, so near the body it
  had to bend sharply into the hyperbola ("hook"). The far path is now also moved sideways by the impact parameter
  (`hyp["shift"]`, `_asymptote_shift`), so it lies on the asymptote of the hyperbola that touches the orbit tangentially.
- The blend zone now reaches from 3 rp out to max(12 rp, 6 a), so the hyperbola takes over smoothly.

## Step 10j – view entry found at any warp
- The view-switch logic is generic (every body: view radius = widest child orbit / 0.9), but `_next_view_entry` only compared the
  views at the start and end of a time step. At a high warp the ship can fly through a small view (Mars: ~26,000 km) and out
  again within one step, so the slowdown never triggered and the view only changed when the aerobraking pass stopped the warp.
  Earth/Moon have big views, so the ship was still inside at the end of the step. The interval is now sampled (every 0.01 day, at
  most 160 samples) and the entry time is found by bisection.

## Step 10k – earliest stop event wins
- Real cause of the missed view change: `advance()` handled the stop events one after the other (aerobraking entry, morph start,
  view entry) and only looked at the next one if the previous had not already slowed the warp. At a high warp the pass/morph start
  came first, time jumped straight to it and the (earlier) view entry was never considered. Now all three are computed for the
  step and the earliest is used, so the ship stops where it enters the smaller view (the view then switches there).

## Step 10l – ship-lost texts in the past tense
- The text after a loss on arrival is built by `GameState._lost_text(outcome, target)` (crash, burn_up, too_slow, too fast) in the
  past tense; the planner's `outcome_text` (future tense) is still used for the warnings before launch. The decay message
  was already in the past tense.

## Step 10m – burn-up / crash handling
- Why the ship is lost below 25 km at Mars: `min_periapsis_altitude_km` in bodies.json (Mars 25, Earth 60) is a placeholder rule: a target
  orbit with its periapsis below it means "burn up", no matter the heat or the g-force (the heat shield display is only about the passes).
- When the target periapsis is lower than that limit the heat shield prediction is locked to 0% (`_set_target_outcome`).
- A predicted shield capacity below 20% (1 - HEAT_MARGIN) after the manoeuvre is shown in the colour of the warnings (the info label is a
  RichTextLabel now; a line starting with `WARNING_MARK` is coloured).
- The ship is lost when it blows up, not when the manoeuvre would have finished: `GameState._loss_time()` = the first arrival at the
  periapsis of the target orbit (the arrival itself for a propulsive capture). Time stops exactly there; `GameState.ship_lost` makes the
  screen draw no ship and no course, and the burn-up animation plays (not for a crash).
- A target periapsis altitude of 0 or less is a crash (also where there is no atmosphere). Text only for now: "The ship crashed into the
  surface of X and was lost." (animation later).

## Step 10n – top bar near another body
- While the ship is still on a transfer leg (Sun-centred) but inside the local view of a body, the top bar now shows
  "Approaching/Leaving X: altitude ... km | Speed ... km/s (relative to X)" instead of the periapsis, apoapsis and altitude of the
  transfer orbit around the Sun. The first aerobraking leg then takes over as before.

## Step 10o – zoom between views, double tap to focus
- Every change of the view (auto switching, the View button, a double tap) is now a zoom of `ZOOM_SECONDS` (0.7 s, real time) instead of a cut.
  `shown_frame` is the view that is drawn; `_update_zoom` starts a zoom (`zoom_from` -> `zoom_to`) when the chosen view (`_frame_id()`)
  differs. During the zoom both scenes are drawn (`_draw_scene`), the scale changes in equal ratios, the camera moves from one body to the
  other (linear in 1/scale, so it behaves like a real zoom into the point) and the scene that is left fades out, the one it goes to fades in
  (`scene_alpha`, `_fade`). If the chosen view changes during a zoom, that zoom is finished at once and the next one starts.
- Double tap (two taps within 400 ms) on a body of the shown view: the view focuses on it (View shows its name). A double tap on the body the
  view is centred on zooms out to the body it orbits (to "auto" for the Sun). A tap on a body does not change the warp any more; taps elsewhere
  in the bottom third still do.
- Not done yet: pinch zoom and panning by hand, and the automatic widening of the view when doing that.

## Step 10p – pinch zoom (camera instead of fixed frames)
- The view is now a camera: `cam_body` + `cam_offset` (km, the point at the screen centre relative to that body) + `cam_scale` (px/km).
  Zooming to a view (double tap, auto switching, View button) animates the camera (`_update_camera`, `_start_zoom`): scale in equal ratios,
  position linear in 1/scale; this replaces the two-scene cross-fade of 10o.
- Pinch with two fingers (or the mouse wheel on the PC) zooms about the point under the fingers and moves the view with them
  (`_zoom_about`); the view is then "free" (top bar: "View: free") and stays where it is. Pressing View once brings it back to the chosen
  view; a double tap on a body zooms to it; a change of the automatic view zooms there as before. Limits: MAX_PX_PER_KM (2 px/km) and
  MIN_SUN_FIT (a quarter of the scale that fits the Sun's system).
- `_draw` draws the scene of the camera's body, of its parent and of its children together (`_draw_scene`); a scene fades in when its view
  radius is more than ~16-60 px on the screen, its orbit lines fade out when it is much bigger than the screen (markers stay).
  `_rebase` moves the camera's reference body to the one whose own view has about the current scale (nothing changes on the screen).
- `GameState.body_rel_to(from, to, jd)` gives the position of one body relative to another with small numbers.
- A tap now counts when the finger is lifted, and not right after a pinch.

## Step 10q – no View button, always the automatic view
- The View button is gone (TopBar.setup with "" leaves it out); the chosen view is always the automatic one (`_frame_id()`), the camera
  follows it and zooms when it changes. Pinch / wheel / double tap move the camera by hand ("free") until the automatic view changes or until
  two quick taps on empty space bring the camera back to the automatic view.
- Double tap on a body: zoom to it (the camera then stays on it). Double tap on the body the camera is already on: zoom out to the body it
  orbits (for the Sun: back to the automatic view).

## Step 10r – drag to move, snap out to the parent's view, planner resets the view
- One finger (or the left mouse button) drags the view (`_pan`, from InputEventMouseMotion, which Godot also makes from a single touch; it is
  ignored while two fingers are down). After DRAG_START_PX the gesture is a drag, the release is not a tap.
- Zooming out by hand below SNAP_OUT (0.8) of the normal view of the body the camera is on zooms (animated) to the normal view of the body it
  orbits: Moon -> Earth -> Sun. Pinch input is ignored while a zoom to a view is running.
- Pressing Plan (a draft was made) zooms back to the automatic view.

## Step 10s – ship orbit always visible and green, smaller rings
- The ship's orbit (and the morphing orbit) is drawn in `_draw_ship_orbit`, not inside the scene of its body, so it no longer fades away when
  the scene is much bigger than the screen (zoomed in at Earth). It is hidden only when it is less than ~2 px above the body (fades in
  2-6 px) or more than 8 half-screens wide. Colour green; planned courses stay blue.
- The ring around small bodies is drawn when the body's true radius is below RING_BELOW_PX (2 px), so Earth has none in its default view
  (about 4 px), while the Moon in the Earth view and the moons of Mars still have one.

## Step 10t – snap-out threshold
- SNAP_OUT is 1/1.5: the view zooms out to the parent's view once it is 50% wider than the body's own default view (was 20%).

## Step 10u – drag delay after zooming
- One-finger dragging is blocked for PAN_DELAY_MS (0.5 s) after the last pinch / wheel movement; while blocked the drag start point follows the
  finger, so that the view does not jump when one finger leaves the screen a little before the other.

## Step 10v - body sprites (untested)
- New `scripts/sprite_library.gd` (`class_name SpriteLibrary`): finds the pack in `res://sprites/` or `res://asteroid-miner-sprites/sprites/`, loads textures, normal maps, pivots from `sprites.json` (image centre if the json is unreadable) and the shader `sprite_lit.gdshader`. **Run `godot --headless --import` once** (new class_name).
- `orbit_view.gd`: bodies are drawn as Sprite2D nodes in a layer behind the control's own drawing, scale = radius_px / 192. They fade in over the coloured disc between 2.5 and 7 px radius; the small-body ring is unchanged. No rotation (tilted planets stay fixed in space). Light direction = Sun direction on screen (planets/moons elevation 0). Sun unlit. Earth snow overlay opacity = 0.5 - 0.5 * dot(to_sun, up). Rings drawn if a `<id>_rings` sprite exists.
- Ship sprites (glow, flame) and the landing/burn-up animations are not yet integrated.

## Step 10w - sprite jitter fix
A body drawn by two scenes (e.g. Ceres by the Sun's scene and its own) used the far, 32-bit-imprecise position. Sprite requests now carry the scene rank; the camera body's own scene wins, opacity is the larger of the two.

## Step 10x - body drawn once
Bodies that two scenes both draw (e.g. Ceres in the Sun's scene and its own) now get their disc, name and sprite from one scene only (the camera's own scene if visible), with the larger opacity.

## Step 10y - capture burn at the last aerobraking pass
Before, when the passes left the apoapsis above the target apoapsis, the ship coasted out to that far apoapsis, raised the periapsis there (cheap) and came back to lower the apoapsis at the new periapsis. Not a g-limit: just the cheapest sequence in delta-v, but it takes weeks. Now `AeroBraking.burns_at_once`: if the apoapsis after the last pass is below the target periapsis or more than 0.5% above the target apoapsis, the apoapsis is set to the target apoapsis with a burn right after the last pass; the periapsis is raised half an orbit later. A few % more delta-v at most. Several passes (planner or player) work as before; the burn follows the last one.

## Step 10z - ship sprite (untested)
- The ship is drawn with `ships/modular` (constant `SHIP_SPRITE` in orbit_view.gd, until ship design picks the hull), 36 px long at every zoom, pointing along its velocity on the screen, lit by the Sun (elevation 0.56), with the `_glow` layer added on top (additive blend).
- Engine flame (`effects/flame_vacuum`) while a burn is going on: `GameState.burning_at(jd)` (morph window of a non-pass leg; capture legs now carry `is_pass`). The flame is placed at the left edge of the hull (+12 px); adjust `ship_flame.position` if it sits wrong.
- The triangle is still drawn if the sprite pack is missing. Aerobraking plasma and the other effects are not integrated yet.

## Step 10aa - ship view changes
- One-finger drag delay after a zoom: 0.25 s (`PAN_DELAY_MS`).
- The ship is the white triangle until the sprite (36 px) would cover at most 25% of the diameter of the body it orbits (body radius >= 72 px); between 48 and 72 px the two cross-fade.
- Ship lock: when the camera is on the body the ship orbits and that body's centre is farther than half the smaller screen dimension from the screen centre, `cam_offset` follows the ship. Dragging releases the lock until the body centre is in view again; zooming out by hand and the automatic view change work as before.
- Shadow: the ship is lit at 25% (`SHIP_SHADOW_LIGHT`) inside the cylinder shadow of the body it orbits (soft edge, 2% of the radius); the glow layer stays bright. Done through `sun_strength` and `ambient` of the shader.

## Step 10ab - ship focus, tap pool, lock fix
- Ship lock now needs the view to be zoomed beyond the normal view of the body the ship orbits (`_ship_locked`), works whatever body the camera is counted from, and dragging is ignored while locked (zoom out to leave). The old "released by dragging" flag (which could stay stuck after a stray drag at the end of a pinch) is gone.
- Double tap on the ship (target `"@ship"`, tappable when the view shows the ship's body in its own size) zooms to the ship (0.7 s, same animation as bodies); the ship then stays locked in the centre. Double tap again: zoom out to the body it orbits. `_ship_focus_scale()` puts the orbit at 1.5 x half the smaller screen dimension.
- Taps hit only: the camera body, its parent, and either its moons and the ship (view at least 0.7 x the body's own view) or the parent's other children (zoomed out). A tap on a planet in the solar view no longer hits the moon on top of it.

## Step 10ac - lock only near the ship, softer shadow
- `_ship_locked` also requires the ship to be within 0.6 x the larger screen dimension of the screen centre. Zooming to the Moon (ship orbits Earth) or to Mars no longer snaps to the ship.
- Shadow edge width grows with the ship's altitude: 2% of the body radius near the surface up to 62% at three radii.

## Step 10ad - time controls under big bodies
A body whose on-screen radius is over 60 px no longer takes taps in the bottom third of the screen (the tap changes the warp); before, a zoomed-in planet covering the bottom swallowed them.

## Step 10ae - aerobraking heating effect (untested)
- `GameState.heat_at(jd)` (0..1): during an aerobraking pass (morph window of a pass leg) a bell curve (sin^2) times the pass's strength, which is the plan's peak heat flux mapped logarithmically between `heat_effect_min_mw_m2` (0.1) and `heat_effect_max_mw_m2` (20) from `data/settings.json` (tuning values; the pass legs carry `heat_peak`). One strength for all passes of a plan (the largest peak flux).
- Ship: orange hull glow through the shader's `heat` uniform (hull points along its flight, so `heat_dir` stays (1,0)); `effects/plasma_wide` additive at the nose, faded and slightly pulsing with the heat; the triangle marker turns orange. Plasma variant per hull (pointed/blunt/wide) comes with the hull choice.
- Not yet: the fireball and fragments of the burn-up (the overlay still plays the old frames).

## Step 10af - ship attitude: retrograde burns and aerobraking (untested)
- The ship flies nose first. Before a retrograde burn and before every aerobraking pass it turns tail first (engine and heat shield are at the tail), and turns back afterwards. The engine flame only shows when the ship has turned the right way round. The plasma and the hull's heat glow are on the tail while it flies tail first (assumption: the heat shield is at the tail end of the hull; flip it in `_apply_ship` if the shield is at the nose).
- `GameState.attitude_at(jd)` is a pure function of time: the turn is a smooth ramp over the turning time before the burn/pass window and back after it, so it is right at any warp. Prograde or retrograde comes from the velocity just before and after the burn (cached in `leg["prograde"]`).
- Turning rate: 180 deg/s for ships up to 5,000 kg total mass, 10 deg/s from 100,000 kg, logarithmic in between (`rotation_*` in `data/settings.json`); the example ship uses 10 deg/s, a half turn takes 18 game seconds. The ramps run before the burn window, which is played at 1 min/s, so at high warp the turn is a blink.

## Step 10ag - real time for turns, burns and passes
- `advance()` now drops the warp to real time (index 0) one half-turn time (`half_turn_days()`) before every burn or aerobraking pass window (and before the atmosphere entry), so the turn and the burn/pass are played in real time. Before, it dropped to 1 min/s at the start of the window. The player can speed up again at once. Moving into a smaller view still only drops to 1 min/s. All burn windows count now, also the departure burn (its morph is not drawn, but the ship turns and the flame shows).
- Fix: the prograde/retrograde test of a burn measures the velocity relative to the lower of the two bodies (the moon at an insertion), because in the Earth frame the capture burn at the Moon came out prograde.

## Step 10ah - turn only as long as needed
- The ship keeps the attitude of its last burn or pass (nose first / tail first). `GameState.manoeuvre_windows()` lists all burns and passes with the attitude each needs and `lead` = the half-turn time if that differs from the attitude before it, else 0. The warp drops to real time at `t0 - lead` (the start of the turn; at the window start itself if no turn is needed); `attitude_at` turns the ship over the lead time. A retrograde burn after a retrograde burn needs no turn, a prograde one after it turns back.
- A new plan starts at least a half-turn time (+3 min) after now (`_min_launch_delay`), so a relaunch right after an insertion has time to turn first.
- Test sprite: `ships/ssto_side/ssto_side` (not symmetrical). The earlier modular hull is symmetrical, so its turns could not be seen.

## Step 10ai - first burn at least 20 s away, skip stops before the turn
- A plan's first burn now starts at least 20 s (`MIN_LAUNCH_DELAY_DAYS`) after now, counted from the start of the ship's turn for it: departure time >= now + 20 s + turn time + half the burn time (`_plan_with_delay`, which re-plans from a later start if the planner returned an earlier one).
- "Skip to departure" stops 5 s before the start of the turn for the first burn (before: 2 min before the departure time, which could already be inside the burn window, so the ship's attitude changed instantly).

## Step 10aj - ship heading from one leg, test line for turning
- The ship's flight direction is now measured along the leg it is on (`leg_rel_with_offsets` of that one leg at t +- 60 s) instead of `ship_rel` at both times, which could mix two legs close to a leg change.
- Test line in the info text while the ship turns: "Turning: x% of a half turn | rate .. deg/s, a half turn takes .. s" (remove when the turning is confirmed).
- The shown attitude (`retro_shown`) now follows the plan's attitude no faster than the turning rate (in game time): aborting a launch after the ship turned makes it turn back over the turn time instead of snapping, and any other jump of the plan's attitude is smoothed the same way. The flame shows only when the shown attitude is right.

## Step 10ak - route check, lander test sprite, warp-stop reason
- Test sprite for the ship: `ships/lander` (SSTO brakes nose first, the lander tail first).
- Route check: `GameState.route_conflict(plan, parked)` samples the planned route (departure to arrival, 0.5 day steps, refined near a body) and reports the first body other than the origin, the target and their ancestors whose sphere of influence (Laplace radius `soi_radius_km`; tiny moons without a real SOI are ignored) the ship enters. `_postpone_for_route` then re-plans from later starts (1 day, growing by 1.4x each try, at most 25 tries) until the route is clear, and reports the postponement (or a warning) in the message. Not done for course changes during a flight.
- Test line "Warp stopped: <reason>" for 20 s after every automatic warp drop (atmosphere entry, a burn or pass with its leg label, a smaller view), to find unexpected stops.

## Step 10al: lock fixes, gradual burns, heat shield in percent, fly-by, top third, retracted lander (version 0.1)

- **Ship view lock** (`orbit_view.gd`): the view follows the ship only after a zoom by hand (pinch, wheel) or a double tap on the ship, never from a drag. It follows only while the ship is really in orbit around the body the camera is on (leg kind `orbit` or `aero`, not a transfer). It lets go when the view is zoomed out to less than 1/1.5 of the scale at which it began to follow, or when the ship's orbit body changes, and then centres smoothly on that body (the scale stays).
- **Burns** (`game_state.gd`): propellant of the departure and the arrival burns is taken out of the tanks while the burn runs (`_burn_fuel_gradually`), by the share of the burn window that is over; the arrival burn is shared among the propulsive capture legs by their duration. The plan is finished (arrival message, plan cleared) only after the last burn or pass of its capture legs (`_plan_finish_time`), not at the middle of the burn. The time flow is no longer dropped at the arrival. The departure can be aborted until the burn starts (`departure_done` is set at the start of the burn window).
- **Warp at the atmosphere**: reaching the outer limit of the atmosphere of an aerobraking plan only slows the time flow down to 1 min/s (`AERO_WARP_INDEX`); it drops to real time at the start of the turn for the pass. (Orbit decay passes still drop to real time.)
- **Heat shield in percent**: arrival message, status line and planner show the share of the shield capacity (used / left). `GameState.aerobraking_damage(heat, peak_g)` is the damage (health share) that the arrival uses and the planner predicts: "Expected damage: health 100% -> 62%". Heat stays in MJ/m2 internally.
- **Fly-by** (`aero_braking.gd`): if the passes leave the ship too fast, the planner looks for a burn right after the last pass (`escape_capture_dv`: set the apoapsis, raise the periapsis half an orbit later) and uses it if the tanks hold enough delta-v ("burn_assist"). Otherwise the outcome is `flyby`: no capture legs, the ship stays on its transfer orbit around the Sun and is not lost. Simplifications: the energy the passes took and the deflection are not added to the heliocentric orbit; the burn is after the pass only (not before or during it).
- **Top bar**: at most the top third of the screen (`MAX_HEIGHT_*` 0.34). A drag with a finger or the left button scrolls it, and the wheel scrolls it without zooming the map.
- **Ship sprite**: `ships/lander_parts/lander_body` (legs retracted), 22.6 px long (`SHIP_LENGTH_PX`), 30% smaller than the extended lander at 36 px.
- **Start date** (`bodies.json` `game_start`): 2047-02-23 (JD 2468764.5). The first Earth to Ceres window after it (about 2047-03-19) sends the ship through the sphere of influence of the Moon (about 1,700 km from the Moon's centre in a straight-line model), to test the route check. Press Reset game to start from it.

## Step 10am: launch moved a few days to clear a body, top bar 45%
- `_postpone_for_route` (orbit_view.gd) first tries shifting the departure by 1, -1, 2, -2 ... up to 30 days (`ROUTE_SHIFT_*`): the nearest time whose route clears every sphere of influence, whose burn can still start in time and whose total delta-v (departure + propulsive arrival) is within the ship's delta-v (or 5% above the planned cost, if aerobraking is needed anyway). Message: "Optimal launch window not possible. Launch moved +x days until <Body> is out of the way." Only if nothing works the old postponement to a later window is used.
- `TransferPlanner.lambert_transfer`: conic through the origin and the target position (counter-clockwise, no full revolutions) for a departure off the window, with the same flight time as the window's transfer. The transfer stores `v_dep` / `v_arr`; `departure_velocity` / `arrival_velocity` give the tangential velocities for the Hohmann transfers, so the burn functions work for both. Checked in a Python port: the conic ends at the target position (0 km miss) for shifts of -10 to +10 days. Planets and moon-to-planet transfers only (`MissionPlanner._transfer`); other plans fall back to postponing.
- `MissionPlanner.make_plan(..., fixed_departure, quick)`: `quick` skips the aerobraking setup (cheap, for trying the shifts).
- Top bar: 45% of the screen height (`MAX_HEIGHT_*`).

## Step 10an: follow the ship through burns, release at 25%, moon departure display, route-shift test line
- Ship follow (`orbit_view.gd`): releases at 1/1.25 of the scale where it began (`FOLLOW_RELEASE_FACTOR`, before 1/1.5). It keeps following through an escape or transfer burn and while the ship is far from the body (no centring on the body, no zoom change). It lets go only when the view is zoomed out past the factor, when the player taps out (any zoom to a body) or when the ship goes into orbit around another body (then the view centres on that body, the scale stays), or when the ship is lost.
- Moon departure display (`game_state.gd`): a transfer from a moon to another planet is calculated from the planet's centre. The transfer leg now carries `anc_offsets`: for every body above the moon (the planet, the Sun) the jump between the ship's place at departure (moon position plus parking orbit point) and the transfer's own start, faded out (`_faded`) as the ship moves away. In the planet view the ship therefore leaves from the moon. Cost and timing are unchanged. A proper solution is planned for version 0.2.
- Test line (remove after the route shift works): when the launch had to be postponed, the message ends with "[Route shift test: tried N, no plan, other time, too soon, too costly (cheapest, limit), still blocked, full plan failed]".

## Step 10ao: fly-by course and heating
- A fly-by plan (outcome `flyby`, aerobraking on) now has its own local course in the target's view: `transfer_leg_for_plan` sets `to_body`, `to_ref` and `to_hyp` for it. The course is a hyperbola round the target with the periapsis at the aerobraking altitude (target radius + `aero["h_km"]`), approaching along the real direction of the transfer. The way out is turned by the swing round the body (`delta_out` / `shift_out`, used by `_blend_hyperbola` for times after the periapsis). The planned route is drawn in the target's view also for the way out (60 days at most, until the path leaves the view). The Sun-centred path is unchanged (no energy change or deflection is added to it).
- The pass of a fly-by now exists as an event of the transfer leg (`flyby_t`, `flyby_days`, `flyby_heat`, set in `set_morph_times`). `heat_at` uses it, so the triangle glows, the hull heats and the plasma shows during the pass. `manoeuvre_windows` has a window for it (tail first, turn before, warp drops to real time for it like for a normal pass). `aero["pass_days"]` is set also for a fly-by.
- Ship / triangle fade (`orbit_view.gd`): zooming in, the sprite fades in completely over the first half of the range (`SHIP_FADE_FROM` to full size) and only then the triangle fades out over the second half; zooming out is the reverse.
- Route-shift test line is still in (waiting for its result).
- The menu shows the build next to "Prototype": "Prototype, version 0.1 - Step 10 ao" (`BUILD_LABEL` in `menu_view.gd`). Update it with every new build.


## Step 10ap: precision near small bodies, approach direction

- B-014: `Kepler.position_xy` returns a position as two 64-bit floats. `GameState._leg_rel` and `body_rel_to` now add and subtract in 64-bit and convert to Vector2 only at the end (Vector2 is 32-bit: about 32 km steps at the distance of Ceres, which made the route jagged and the ship shake).
- B-015: the capture orbit stays counter-clockwise (direction of the body's rotation). After building the approach hyperbola, `transfer_leg_for_plan` samples the drawn course over the last 2 days before arrival; if it sweeps clockwise round the target it sets `leg["to_mirror"]` (the capture point's angle) and `leg_rel_with_offsets` mirrors the course about that axis. The capture point itself is on the axis, so nothing jumps. The delta-v cost of a real reversal is left for version 0.2 (target orbit direction slider).
- Build label: "version 0.1 - Step 10 ap".

Step 10ap, second round: after the first 10ap test (Ceres) the course was smooth but still came in clockwise and the ship reversed during the capture. The Ceres approach had no hyperbola (the plain faded course), so the clockwise check now runs for every capture, and the mirror is applied in both cases (hyperbola and faded course) in `leg_rel_with_offsets`.


## Step 10aq: complete package

No code change beyond the build label ("version 0.1 - Step 10 aq"). This zip holds the whole pkg folder (scripts, data, art) as of 10ap second version, so that nothing can be a mixed-up older file.

## Step 10ar: capture at the natural point of arrival

- In a planet-to-planet (or moon-to-moon) transfer the periapsis of the capture orbit used a fixed direction (0 deg), so an approach from above had to be mirrored (10ap/10aq). Now `GameState.natural_capture_axis_deg` gives the periapsis direction from the real arrival: the direction of the ship's velocity relative to the target at arrival, turned back by atan(sqrt(e^2-1)) of the arrival hyperbola (e = 1 + rp * v_inf^2 / gm). The ship passes the target on the side where it sweeps round counter-clockwise (the body's rotation). It is stored in `plan["capture_phase_deg"]` by `MissionPlanner.make_plan` for aimable arrivals.
- The delta-v does not change: `TransferPlanner.capture_dv` depends only on the arrival energy and the target orbit. The planned course still aims at the body's centre; the side the ship passes on is the display/orbit geometry (hyperbola shift) and costs nothing in this model.
- The mirror of 10ap stays as a guard (it only acts if a course would still sweep clockwise) and should not trigger any more.
- The axis offset of the target orbit still counts from the arrival direction.
- Build label: "version 0.1 - Step 10 ar".

## Step 10as: curved approach for transfers that miss the centre

- The curved approach (hyperbola round the target, `to_hyp`) was only used if the transfer missed the target's centre by less than twice the capture radius. At Earth (about 13,000 km) and at Ceres with an axis offset the transfer misses by more, so the course ran straight to the capture point, through the planet. Now the limit is `APPROACH_MAX_MISS_KM` (1e6 km). The far part of the course keeps its own miss (it is shifted by the same impact parameter as before), and near the body the hyperbola takes over.
- A line for the Godot output shows the miss distance, the capture radius and whether the curved approach was used ("approach to ...", printed when it changes).
- Build label: "version 0.1 - Step 10 as".

## Step 10at: only the local course in the target's view

- B-018: in the view of the target body (`leg_rel_with_offsets`, `to_hyp` case) the course is now the hyperbola alone (`_hyperbola_pos`), no longer blended with the transfer's own course. With an axis offset the hyperbola comes in from another direction than the transfer (which aims at the centre), which showed as a visible transition on entering the target's view. For a fly-by the way out is the other arm of the same hyperbola. The Sun view still shows the transfer itself. The departure side (`from_hyp`) still blends.
- The axis angle shown for the orbit ("axis 276 deg") is measured from the right-hand direction (0 deg, east), counter-clockwise: arrival point at 186 deg plus offset 90 deg = 276 deg. See B-019.
- Build label: "version 0.1 - Step 10 at".

## Step 10au: universal orbit axis (B-019)

- The axis of a non-circular target orbit is now measured in the frame of the whole solar system (counter-clockwise from east) and is the same for every body: `AeroBraking._axis_deg` returns `offset_deg` itself, no longer arrival angle + offset. A circular orbit has no axis and continues from the arrival.
- Option 3 (aim, then turn): the arrival aim point can turn the periapsis towards the target axis by up to `AIM_RANGE_DEG` (20 deg) for free (`_arrival_axis`). What is left (`axis_turn_deg`) is turned with a burn at the crossing point of the two ellipses (`axis_turn_dv`, included in the capture burn). Arrivals that cannot be aimed (moon to its planet, orbit changes, central-body course changes) turn the whole gap.
- Course changes during a flight (`course_change.gd`) now take the natural capture axis too (it was 0 before).
- Quick plans (used for the shifted-launch search) include the turn burn, so the cost is the same as in the full plan.
- Orbit changes: the offset is the absolute axis as well (`_plan_orbit_change`).
- The plan text has a new line: "Orbit axis: ... (solar system frame), arrival aimed at ...; turning the axis by ... costs ... m/s".
- `AIM_RANGE_DEG` is a guess; change it in aero_braking.gd if the free range should be bigger or smaller.
- Build label: "version 0.1 - Step 10 au".

## Step 10av: the orbit after capture ends at the universal axis (B-020)

- Cause of the 10au test failures: `_use_propulsive_capture` (capture without aerobraking) put the target orbit at `_arrival_axis` (the aimed axis, at most 20 deg from the natural direction) instead of `_axis_deg` (the universal axis), so the turn burn was paid but never carried out (Earth to Moon with offset 90 stayed at 260 deg; Earth to Ceres gave 166 deg). The aerobraking path already used `_axis_deg` for its last leg.
- Now, if a turn is left after aiming (more than 0.5 deg), the propulsive capture has two legs: "Capture orbit" at the arrival axis, and half an orbit later (at the apoapsis, where the turn burn is) the target orbit at the universal axis. Without a turn it is one leg at the universal axis. `t_end` is the time of the turn.
- Build label: "version 0.1 - Step 10 av".

## Step 10aw: the axis turn happens at the crossing point of the two orbits (B-021)

- 10av turned the axis at the apoapsis, where the old and the new ellipse do not meet, so the ship jumped to the new orbit (position snap during the burn). Now (`AeroBraking._append_turn_leg`) the ship coasts on the capture orbit (target shape, aimed axis) to the first of the two points where this orbit crosses the target orbit (axis universal). These lie on the line that bisects the two axes: true anomaly turn/2 or turn/2 + 180 deg on the old orbit, minus the turn on the new one. At a crossing both orbits have the same position and speed, only the radial speed changes sign, so the burn is radial and costs exactly what `axis_turn_dv` says (2 e v sin(turn/2)). No position jump.
- It is used for the propulsive capture (turn starts at the periapsis, anomaly 0) and after the last aerobraking pass (ship at the apoapsis or periapsis of the target-shaped orbit, `final_anomaly`). The label of the first leg is "Capture orbit around X" (kind aero), the leg after the turn "Orbit around X" (kind orbit). `t_end` is the time of the turn burn.
- Aiming (20 deg free, `AIM_RANGE_DEG`) is unchanged.
- Helper `_mean_anomaly_deg(e, nu)` (true to mean anomaly).
- Build label: "version 0.1 - Step 10 aw".

## Step 10ax: the axis-turn burn is shown as a rotation and stretch (B-022)

- During the burn the shown orbit (`GameState.morph_at`) was a linear blend of periapsis, apoapsis and axis between the old and the new orbit, which looks like morphing and moves the orbit away from the ship. For the legs flagged `axis_turn` (the leg after the turn, set in `AeroBraking._append_turn_leg`) `_axis_turn_orbit` is used instead: P is the crossing point, the velocity goes linearly from the old to the new one (only the radial part differs), and the orbit shown is the one through P with that velocity (`CourseChange.state_segment`). The orbit therefore turns about P and shrinks and grows a little in between, and the ship stays on it.
- `set_morph_times`: the axis turn is its own burn window (duration from `axis_turn_dv`), the other capture burn gets the rest of the delta-v (was the whole delta-v for each leg).
- Build label: "version 0.1 - Step 10 ax".

## Step 10ay: view zoom with the ship's apoapsis, slider limit, planner stays open (B-023)

- `GameState.view_extent_km`: a ship that is in orbit around the body (leg parent = the body, kind not "transfer") and whose apoapsis is inside the sphere of influence keeps its whole orbit in the view: extent = max(standard, apoapsis * 1.1). Before, a wide orbit around Mars (apoapsis 40,000 km, wider than Deimos) made the automatic view jump out to the Sun.
- `GameState.max_orbit_altitude_km(id)`: sphere of influence minus the radius (at least one radius); 100 radii for bodies without a sphere of influence. `OrbitControl.setup` uses it for the sliders and the spin boxes; an altitude can no longer be typed above it (`allow_greater` is off for the altitude boxes, and `_commit` limits the value).
- Changing the destination while the planner is open (`OrbitView._on_target_changed`): the planner stays open. The orbit (periapsis, apoapsis, offset) is kept (`_orbit_for_body`), but the periapsis is raised to the atmosphere limit of the new body if needed and the altitudes are limited to its maximum; then `_make_plan(false)` plans again, so aerobraking and the limits start fresh for the new body. Without an open planner (or during a flight) nothing changed.
- Build label: "version 0.1 - Step 10 ay".

## Step 10az: ship attitude during the axis-turn burn (B-024)

- Cause: the ship's heading is the velocity direction on the current leg (flipped for a retrograde burn). The axis-turn burn is radial at the crossing point, so `_burn_is_prograde` was practically random (it showed retrograde the whole time), and the heading followed the old course until the leg switched, then snapped to the new one.
- Now the windows of axis-turn legs (`GameState.manoeuvre_windows`, flag `fixed`) carry `fixed_angle` = direction of the velocity change at the crossing point (`_burn_heading`, cached in the leg as `burn_heading`; screen angle, the nose points along the thrust). `attitude_at` returns `fixed` (0..1) and `fixed_angle`: the ship turns from its course to that heading during the usual lead time (a half turn at the rotation rate) before the burn, keeps it fixed in space for the whole burn (`burn` = 2), and turns back to its course afterwards. `OrbitView` blends the heading with `lerp_angle`; the flame burns for `burn == 2`.
- Retro state (nose first / tail first) is not changed by this burn; the next burn uses the same previous attitude as before.
- Not changed: other burns, aerobraking passes, the line fade (still planned, B-025).
- Build label: "version 0.1 - Step 10 az".

## Step 10ba: orbit change with a new axis at the body the ship orbits (B-025)

- Seen in 10az: changing the orbit at Ceres from offset +90 to -90 made the ship jump to the old periapsis and then to the new one: no turn of the ship, no burn. Cause (`MissionPlanner._plan_orbit_change`): the two apsis burns lead to the target shape at the axis of the old orbit, but the final orbit leg was drawn at the universal target axis directly (and with zero delta-v for the burns when only the axis differs), so the ship switched orbits without any burn. `capture_phase_deg` was also the axis of the old orbit even when the first burn already put the new periapsis on the target axis (circular start).
- Now `capture_phase_deg` is the axis of the orbit the burns lead to (`middle_axis`). If a turn to the universal axis is left (`AeroBraking.axis_turn_deg` > 0.5 deg), the capture leg is the target shape at that axis, starting where the apsis burns end (`final_anomaly`), and `AeroBraking._append_turn_leg` adds the radial burn at the crossing point of the two orbits (same as after an arrival; `axis_turn_dv` is in `dv_arrival`; `t_end` is the time of the turn). The ship attitude for this burn is the one from 10az.
- Build label: "version 0.1 - Step 10 ba".

## Step 10bb: the turn to and from the axis-turn burn heading at the ship's turning rate (B-026)

- Seen in 10ba: the ship still turned instantly to the burn heading before the axis-turn burn and back afterwards. In 10az the blend between the course and the burn heading was a function of the game time only (smoothstep over one half-turn time); the other turns (retro/prograde, aerobraking) additionally go through `OrbitView._turn_towards`, which never lets the shown attitude change faster than `GameState.rotation_rate_deg_s()` in game seconds.
- Now `GameState.attitude_at` returns `fixed` as the wanted value (1 from one half-turn time before the burn until the end of the burn, otherwise 0; `burn` = 2 only inside the burn) and `OrbitView` runs it through the same `_turn_towards` (new parameter `fixed_heading`, own state `fixed_shown`/`fixed_jd`; the body of the function is the same for both). The heading is `lerp_angle(course heading, fixed_angle, fixed_shown)`; the flame burns only when `fixed_shown` has reached 1.
- The test line "Turning: ..." (top left) is now also shown during this turn.
- Build label: "version 0.1 - Step 10 bb".

## Step 10bc: the change-over from the local course to the transfer when leaving an eccentric orbit (B-027)

- Seen in 10bb: leaving an eccentric orbit of Phobos (periapsis 20 km, apoapsis 500 km) for Deimos, the blue course left the moon on a line that bent away well inside the parking orbit: the change-over from the local course (hyperbola round the moon) to the transfer's own course happened too close in.
- Cause: `GameState._blend_hyperbola` uses the periapsis radius `rp` of the local hyperbola for its sizes (pure hyperbola inside 3 rp, pure transfer course beyond max(6 a, 12 rp)). For an eccentric parking orbit the periapsis is much smaller than the orbit, and for a tiny moon `a` is a few metres, so 12 rp (about 400 km here) was less than the apoapsis.
- Now `transfer_leg_for_plan` stores `hyp["scale"]` = the apoapsis radius of the parking orbit (`a (1 + e)`), and `_blend_hyperbola` uses `max(rp, scale)` in place of rp. For circular parking orbits nothing changes (apoapsis = periapsis radius). Arrival side unchanged (it does not blend).
- Build label: "version 0.1 - Step 10 bc".

## Step 10bd: the view includes the intended and the future orbits; no warp drop inside an orbit around a tiny moon (B-028, B-029)

- Seen in 10bc: (B-028) with the planner open the view could not be zoomed out far enough to show the intended orbit (it snapped out to the Martian view); (B-029) in an orbit around Phobos (periapsis 20 km, apoapsis 500 km) the time flow dropped to 1 min/s once per orbit at about 440 km altitude ("the ship enters a smaller view").
- Cause: `GameState.view_extent_km` only counted the orbit the ship is on now, and only if its apoapsis was within the sphere of influence. Tiny moons (Phobos, Deimos) have no sphere of influence (`soi_radius_km` = 0), so their orbits were never counted; the view of a body without moons was 1.5 a (semi-major axis) which is smaller than the apoapsis (1.88 a here), so the ship left the Phobos view on every orbit and `_next_view_entry` dropped the warp when it came back.
- Now: new `GameState.max_orbit_radius_km(id)` = sphere of influence (at least two radii), 100 radii above the surface for bodies without one, infinite for the Sun. `view_extent_km` includes the apoapsis + 10% of every orbit leg round the body from the current leg on (the orbit of the ship and the orbits of a launched plan) and of the intended orbit of the plan in the planner (`plan["ra_t"]` of `plan["target_id"]`), as long as the apoapsis is within `max_orbit_radius_km`. Since the planner limits the altitude of orbits to the same value (`max_orbit_altitude_km`), an orbit always fits in its view: the altitude where the ship is "approaching" (enters the view of the body and drops the warp) is never lower than the highest orbit.
- Build label: "version 0.1 - Step 10 bd".

## Step 10be: the route leaves an eccentric orbit tangentially (B-031)

- Seen in 10bd: leaving an eccentric orbit of Phobos for Deimos, the blue route left the orbit at a sharp angle at the ship's position instead of continuing along the direction of flight.
- Cause: the local hyperbola in `GameState.transfer_leg_for_plan` had its periapsis at the departure point, so it left across the radius. That equals the direction of flight only at an apsis (or on a circular orbit). On an eccentric orbit the ship's velocity at the departure point can be tens of degrees off that.
- Now: the hyperbola is built to pass through the departure point with the same radius, the same speed at infinity and the same direction as the orbit's velocity there (angular momentum from the flight-path angle, eccentricity from it, periapsis angle and time of periapsis back-calculated from the true anomaly). Circular orbits, orbits at an apsis (angle < ~3 deg from the radius normal) and clockwise orbits keep the old construction.
- Build label: "version 0.1 - Step 10 be".

## Step 10bf: the context of the ship (B-032)

- Seen in 10bc/10bd: the time flow dropped to 1 min/s at an altitude inside the highest orbit round Phobos ("the ship enters a smaller view"), and leaving a small moon the view did not go back to the larger body. The drop and the view switch followed the size of the view, not a real boundary.
- Now every body has a context radius, `GameState.context_radius_km(id)` = `max_orbit_radius_km(id)` (the edge of the sphere of influence, at least two body radii; 100 radii above the surface for bodies without one: small moons, asteroids, comets; infinite for the Sun). The ship has a context, `GameState.ship_context_id` (a ship parameter; one ship for now), worked out by `update_ship_context(jd)` every step: the body with the smallest context radius that contains the ship. It is left at `CONTEXT_HYSTERESIS` (1.05) times the radius, so a ship on the edge does not flip.
- The warp drop to 1 min/s now happens only when the ship gets into the context of a smaller body than its own (`_next_context_entry`, message "the ship enters the space of a smaller body"), never from the view size or a zoom.
- The view of a body is only used inside its context (`smallest_view`), and the automatic view goes to the next larger body at once when the ship is beyond the context of the body it shows (`OrbitView._update_auto_frame`). The planner's altitude limit is the same value (`max_orbit_altitude_km`, from 10bd).
- Not in this build: the minimum zoom from the ship's scale (B-033), which waits for ship sprite scaling.
- Build label: "version 0.1 - Step 10 bf".

## Step 10bg: the view follows the context (B-032, second part)

- Seen in 10bf (Jon): (1) the warp no longer dropped in orbits, but after planning at Phobos, panning by hand and launching to Mars the camera stayed where it was panned (on Phobos); (2) arriving at Mars the warp dropped at the edge of the sphere of influence but the view changed only much later, at the edge of the Martian moon system's view: two different thresholds.
- Cause: (1) a pan sets `free_camera`, which only ends when the view target changes; at launch the target (Mars) did not change, so the hand-placed camera stayed. (2) The view switch used the size of the view of the body (`view_radius_km`), the warp drop the context radius.
- Now: `OrbitView._update_context_zoom` starts a zoom to the view of the moment (and ends the free camera) every time the ship's context changes (`GameState.ship_context_id`), when leaving the highest altitude of a body and when entering a smaller context. `GameState.view_extent_km` of the context body of a ship that is flying through it (transfer leg) includes the ship's distance (+10%), so the view of the body is entered at the same moment as the context, and the view fits the ship until it leaves the context.
- Build label: "version 0.1 - Step 10 bg".

## Step 10bh: the context ends at the normal view size (B-032, third part)

- Seen in 10bg (Jon): entering the space of Mars the warp dropped and the view changed, but at the extreme edge of the sphere of influence, so the view was much wider than the normal Martian view.
- Now `GameState.context_radius_km(id, jd)` = the distance the view of the body shows at the edge of the screen (`view_radius_km`, which contains the orbits of its moons and of the ship) but not more than the edge of its sphere of influence (`max_orbit_radius_km`). The warp drop, the change of the view and the leaving of a context all use it. The distance of a ship flying through is no longer added to the view size (10bg).
- Build label: "version 0.1 - Step 10 bh".

## Step 10bi: small moons with a tiny sphere of influence: Deimos (B-034)

- Seen in 10bh (Jon): after capture into a circular 20 km orbit round Deimos the view stayed in the Martian context.
- Cause: `soi_radius_km` gives Deimos a sphere of influence of 8.1 km (radius 6.2 km; Phobos: 7.2 km, below its radius 11.1 km so it counted as none). `max_orbit_radius_km` therefore gave Deimos a context limit of 2 radii = 12.4 km and `max_orbit_altitude_km` 6.2 km, so an orbit at 20 km altitude was outside its own context. Phobos was fine only because its sphere of influence is smaller than the body.
- Now a body whose sphere of influence is smaller than `TINY_SOI_RADII` (5) body radii counts as having none, like Phobos: `max_orbit_radius_km` = 101 radii, `max_orbit_altitude_km` = 100 radii (Deimos: about 620 km). Moon (38 radii), Ceres (164) and the planets are unchanged.
- Build label: "version 0.1 - Step 10 bi".

## Step 10bj: ship design screen in portrait and with the on-screen keyboard (B-012)

- Not run on a phone (cannot be tested here): the layout has to be tried on the Fairphone in portrait.
- The content scale on phones is 2.5, so a portrait screen is only about 430 units wide. The screen did not wrap anything: the long lines of the result text ("Warning: acceleration above ...", "For comparison ...") and the titles of the sliders gave the scrolled column a minimum width wider than the screen. Now the result text, the headings and the slider titles wrap (`AUTOWRAP_WORD_SMART`, minimum width 70-100 units), the text boxes are narrower (110 units, the name 180).
- The on-screen keyboard: `_process` reads `DisplayServer.virtual_keyboard_get_height()` (screen pixels, divided by the content scale) and adds it to the bottom margin of the scrolled screen, and `ScrollContainer.ensure_control_visible` scrolls the text box in focus into view when it gets the focus or when the keyboard appears.
- The start menu was not changed: it is a centred column of fixed-width buttons (320 units), which fits a portrait phone at scale 2.0 (about 540 units wide).
- Build label: "version 0.1 - Step 10 bj".

## Step 10bk: line fade (B-030), one course line near a moon (B-035 part), spacing of the text list

- Not run (no Godot here): to be tried by Jon.
- The green ship orbit now fades with the same zoom rule as the blue lines (`OrbitView._too_big_fade`, the size of the view of the body it orbits against the screen: 1.6 to 5 half-screens), next to its own fade at the tiny end (2 to 6 px above the body). `_draw_map` uses the same function for the scenes.
- While a transfer leg is flown inside the context of another body (`GameState.ship_context_id` differs from the parent of the leg: approaching or leaving the Moon, Phobos ...), the green orbit of the leg is not drawn: the blue route of that body's view is the ship's course and the ship is drawn on it (it follows `leg_rel_with_offsets`), so there are no longer two lines that disagree.
- `TopBar.STATUS_ITEM_GAP` (10 units, about half a line) is the spacing between the items of the text list (VBox separation of the bar's box).
- Not changed: the departure from a moon or a moon system to a planet is still not tangential (B-008 second part, B-035): 0.2.
- Build label: "version 0.1 - Step 10 bk".

## Step 10bl: fade distances of the orbit lines (B-030, second part)

- Not run (no Godot here): to be tried by Jon.
- Seen in 10bk (Jon): green and blue lines now fade together, but too soon: at 4000 km altitude round Earth they began to fade when Earth was about 1/10 of the screen width (should be about 1/2); zooming out they should fade about 20% later.
- The code that was meant to give the scene lines the shared `_too_big_fade` had not been applied in 10bk (the scene loop still had its own copy of the formula with the same numbers, so it behaved the same); both now use `_too_big_fade`.
- New constants in `orbit_view.gd`: `LINE_FADE_BIG_HALF_SCREENS` = (8, 25) half-screens (was 1.6 and 5: five times later when zooming in) and `LINE_FADE_SMALL_PX` = (13, 48) px (was 16 and 60: 20% smaller views keep their lines when zooming out).
- Because the lines now stay until they are up to 25 half-screens big, the green orbit is hidden only beyond 25 half-screens (was 8), and long lines get more points (`_sample_count`: the base count times the line's size in screens, at most 2048) so that no corners show: green orbit (128), the orbits of the moons (160), the capture rings (64).
- `_half_screen()` returns the half size of the map area (used by `_fit_scale` and `_draw_map`).
- Build label: "version 0.1 - Step 10 bl".

## Step 11a: city lights on the night side (shader support)

- Not run (no Godot here): to be tried by Jon. The art (`earth_glow.png`, same size as `earth.png`, in the sprite pack next to `earth.png` and `earth_n.png`) is not in the repository I can see (the last version there has no `earth_glow.png`), so it has to be in `asteroid-miner-sprites/sprites/bodies/` for the lights to show. Without it nothing changes.
- New shader `asteroid-miner-sprites/shaders/city_lights.gdshader` (copy it into the project with the zip): additive (`blend_add`) layer that shows the glow texture only where the Sun does not light the body. The lit side is worked out like in `sprite_lit.gdshader` for a planet (`sun_elevation` 0) from the body's own normal map and `sun_dir`, so the lights fade out where the daylight fades in (smoothstep from 0.04 to -0.30 of the lit value; `strength` scales the brightness).
- (23 Nov) The shader samples `TEXTURE` itself and multiplies by a `modulate` varying (like sprite_lit.gdshader) instead of reading `COLOR`.
- `SpriteLibrary.night_material(normal)` makes the material (null when the shader or the normal map is missing; then the lights are not shown at all, instead of showing all round).
- `OrbitView._place_body_sprites` asks for the layer of any body that has a `<key>_glow.png` (so far only Earth): drawn above the body and its snow, lit by the body's normal map, with the body's opacity. `_request_sprite` has a new `night_of` parameter (the key of the body whose normal map is used) and `_apply_sprites` creates the night material for such a node.
- The menu now shows only the build name: "Alpha v0.1.11.a Testing" (the word "Prototype, " in front is gone). Names from now on: Alpha v0.1.[step].[sub-step] Testing.
- Not done in this build: the atmospheric halo (11b).

## Step 11b: atmospheric halo

- Not run (no Godot here): to be tried by Jon. The art (`atmo_day.png`, `atmo_twilight.png`, two generic white layers) is in the sprite pack of 23 Nov, but not in the repository I can see, so I could not look at it: the code looks for the files in `sprites/bodies/`, `sprites/scenery/` and `sprites/effects/` (`SpriteLibrary.atmo_key`), and draws nothing when they are missing.
- Assumptions to check: both layers use the same scale as the body sprites (disc radius 192 px, pivot from sprites.json or the image centre), and the Sun is on the right of the picture (like `sun_dir` = right in the lighting shader). If the halo points the wrong way, change `ATMO_ROTATION_OFFSET_DEG` in `orbit_view.gd`.
- New file `data/atmospheres.json`: per body id the day tint, the twilight tint (RGB 0-1) and the strengths of both layers. Earth blue with orange twilight, Mars butterscotch with blue twilight, Venus, Titan, Jupiter, Saturn, Uranus and Neptune with their own colours (only Earth and Mars exist in the game so far). These are my starting values, written without seeing the `atmosphere` entries of the pack's sprites.json, which are not read.
- `OrbitView._place_body_sprites` asks for the two layers for every body listed there, with the body's position, scale and opacity times the strength; `_request_sprite` has new `tint` and `rotation_rad` parameters; `_apply_sprites` gives these nodes an additive material (`CanvasItemMaterial` blend add), the tint as colour and the rotation toward the Sun (the layers do not turn with the planet's own rotation or tilt).
- Build label: "Alpha v0.1.11.b Testing".

## Step 11b2: fix for the missing atmospheric halo

- Not run (no Godot here): to be tried by Jon.
- Seen in 11b (Jon, 24 Nov): no haze or twilight glow at Earth or Mars; the files `atmo_day.png` and `atmo_twilight.png` are in `asteroid-miner-sprites/sprites/effects/` (found by the code), both 460 x 460 px, Sun on the right.
- Cause: `SpriteLibrary._setup()` never read `data/atmospheres.json` (the edit that added the loading did not apply in 11b), so `SpriteLibrary.atmosphere(id)` was empty for every body and no layer was requested. Now `_setup()` reads it, and writes a warning to the output when the file cannot be read.
- Build label: "Alpha v0.1.11.b2 Testing".

## Step 12a: Settings screen

- Not run (no Godot here): to be tried by Jon.
- New button "Settings" on the menu (between Ship design and Quit) opens `settings.tscn` (`scripts/settings_view.gd`); Back returns to the menu. The menu shows "Alpha v0.1.12.a Testing".
- New class `UserSettings` (`scripts/user_settings.gd`): all settings are in one file, `user://user_settings.json` (on Windows `%APPDATA%/Godot/app_userdata/<project name>/`), written at every change. `UserSettings.DEFAULTS` holds the default of every setting; `get_value(key)`, `set_value(key, value)`, `reset_all()`, `is_imperial()`, and `on_changed(callable)` for screens that must apply a change at once (called with the key, or "" after a reset). A saved value of the wrong type is ignored. (`data/settings.json` is the starting conditions of a new game, a different thing.)
- The screen has one row so far: Units (Metric or Imperial, default metric whatever the device language). The choice is saved, but the screens do not show imperial units yet (step 12c); a grey note says so.
- `Reset to defaults` puts every setting back and shows the defaults in the rows.
- Rows are made by `_add_choice` (drop-down list). The slider helper (slider with its number next to it) is written with the first slider setting in 12b, so that it is tested on a real setting.
- The settings file is in `user://`, so the export filter does not matter for it.
- Build label: "Alpha v0.1.12.a Testing".

## Step 12b: visual settings

- Not run (no Godot here): to be tried by Jon. (12a: the Settings screen was blank when the game was started with Run from the project list, and fine after Edit and Run: the new files had not been imported.)
- `UserSettings` has the new settings (defaults in `DEFAULTS`): `milkyway_brightness` 1, `star_brightness` 1, `parallax_strength` 0.5 (saved only; the star background itself is 12d), `text_scale` 1 (menu and panel text), `map_label_scale` 1 (body names, ship name, numbers of the top bar), `line_brightness` 1, `line_width` 1, `effects_intensity` 1, `colour_blind` false, `show_body_names`, `show_moon_orbits`, `show_tiny_rings` (all true). New helpers: `number(key)`, `flag(key)`, `colour(name)` (palette: warning, paused, ship_orbit, course; normal and colour-blind version), `text_px(base)`, `map_text_px(base)`, `apply_text_scale(root)`, `remove_listener`.
- The settings screen has sliders (with the number next to each, two decimals), check boxes and the Units list, in sections: Background, Text size, Orbit lines, Effects, Colours, Labels, Units. Reset to defaults sets everything back and shows it.
- Menu and panel text: `apply_text_scale(self)` gives the root of the menu, the settings screen, the ship design screen and the orbit map a Theme with `default_font_size` 16 x the setting (everything without an own font size follows; the headings with their own size use `text_px`). The settings screen follows the slider at once; the other screens read it when they are opened. Map labels: `map_text_px(16)` for the body names, the ship name, and the labels of the top bar (`TopBar.refresh`).
- Orbit lines: `OrbitView._fade` multiplies the opacity by `line_brightness` (at most 1); `_lw(width)` multiplies the width by `line_width` for the orbit lines, the planned course, the capture rings and the green ship orbit.
- Effects: `effects_intensity` scales the plasma (opacity), the hull glow (`heat` of the lighting shader) and the engine flame (opacity, off at 0) in `_apply_ship`.
- Colour-blind palette: the green ship orbit and the blue planned course become yellow and sky blue, the orange warning line yellow, the red "Paused" reddish purple (`UserSettings.colour`). Colours of other panels are not changed yet. The orange heating triangle and the orange facility squares are unchanged.
- Labels: `show_body_names` hides the names of the bodies (not the ship name), `show_moon_orbits` hides the orbit lines of moons (the planets round the Sun stay), `show_tiny_rings` hides the rings round bodies smaller than 2 px.
- Build label: "Alpha v0.1.12.b Testing".

## Step 12c: behaviour and display settings (units not yet)

- Not run (no Godot here): to be tried by Jon. 12b was tested OK by Jon on 24 Nov.
- The imperial display of the Units setting is not in this build: it touches about 60 texts (distances, speeds, masses, accelerations on the map, in the planner and on the ship design screen) and the input boxes with km and kg values, so it gets its own build (12c2). The setting is only saved so far.
- New settings (defaults in `UserSettings.DEFAULTS`): `animations` true, `ship_sprites` true, `orientation` "auto", `frame_cap` 60.0, `lighting_shader` true. Settings screen: sections Behaviour (Animations, Ship sprites) and Display (Screen orientation, Frame rate limit, Lighting shader) above Units.
- Animations: `OrbitView._process` shows the burn-up animation only when `animations` is on (the "Ship lost" message is always shown).
- Ship sprites: off = the ship is always the triangle icon, never the sprite (`_draw_map`, the same as when the ship sprite is missing).
- Screen orientation and frame rate: `UserSettings.apply_display()` sets `Engine.max_fps` (30 or 60) and, on phones and tablets only (`OS.has_feature("mobile")`), `DisplayServer.screen_set_orientation` (sensor, sensor portrait or sensor landscape). It is called when the menu and the map open and when one of the two settings changes. If the Android export has its own orientation setting, this call overrides it while the game runs.
- Lighting shader: off = `SpriteLibrary.lit_material` and `night_material` return null, so planets, moons and the ship are drawn flat (no light and shadow, no city lights); the atmospheric halo (additive layers) is not affected. The nodes are made when the map opens, so the change shows after it is opened again.
- Build label: "Alpha v0.1.12.c Testing".

## Step 12c2: imperial units

- Not run (no Godot here): to be tried by Jon. (12c was split: this is the units part.)
- New class `UnitFormat` (`scripts/unit_format.gd`): the game still works in metric inside; only what is shown and typed is converted when the Units setting is imperial. Distances and altitudes km -> miles (1.609344 km), speeds km/s -> mi/s, small speeds (burns) m/s -> ft/s, masses kg -> lb, larger masses t -> US tons (907.18 kg), accelerations m/s2 -> ft/s2, areas m2 -> ft2, and in the ship design boxes kg -> lb, cm -> in, kN -> klbf (thousand pounds-force). Heat (MJ/m2, MW/m2) and g stay. Costs (EUR) and times are not touched.
- Places changed: the status texts (`GameState.orbit_status_text`, `_km_text`), the planner and info lines in `orbit_view.gd` (fuel, burns, aerobraking, cargo, facilities, refuel and buy messages), the messages of `aero_braking.gd` (crash, burn-up, decay, fly-by), the periapsis and apoapsis boxes (`OrbitControl`: the boxes show miles and the value is converted back to km when typed) and the aerobraking altitude box (`altitude_spin`), the sliders' text boxes and the result text of the ship design screen. Not changed: debug texts (the route shift test report, the approach diagnostic) and the sliders' own scales.
- The screens read the setting when they are opened (the planner boxes are made then), so a change shows when the map or ship design screen is opened again. A plan made earlier keeps the texts it was made with (outcome and warning lines) until it is planned again.
- Rounding: the altitude boxes show one decimal in the shown unit, as before for km, so a typed value in miles is converted to km with a small rounding.
- Build label: "Alpha v0.1.12.c2 Testing".

## Step 12d: star background

- Not run (no Godot here): to be tried by Jon. 12c2 was tested OK by Jon on 24 Nov. Build label: "Alpha v0.1.12.d Testing".
- Art not in the code package: `sky_milkyway.png` and `sky_stars.png` (the night sky from NASA SVS Deep Star Maps, 2048 x 2048 px, 110 degrees across). Put them in `asteroid-miner-sprites/sprites/scenery/` (or `res://sprites/scenery/`). `SpriteLibrary.sky_texture(layer)` also looks in effects, bodies, backgrounds and sky, in that order. If a file is missing, that layer is simply not drawn (no error).
- `OrbitView._update_sky()` (called every frame from `_process`): two Sprite2D nodes in a Node2D (`show_behind_parent`, first child, so behind the body sprites), additive blending (`BLEND_MODE_ADD`), linear filtering. Brightness: `modulate` = (b, b, b, 1) with b = `milkyway_brightness` / `star_brightness`; 0 hides the layer.
- ASSUMPTIONS (images not seen by the code author): opaque or black background (additive blending makes black invisible), square, any pixel size (the larger side is scaled to 1.5 x the larger screen side), no rotation (screen right = ecliptic longitude 0, up = 90 degrees, as the map's x and y).
- Parallax: shift = -strength x (camera distance from the Sun in AU x 20 px + view drag in screen pixels x 0.05), the y axis flipped like the map, limited to 20 % of the larger screen side; plus a slight zoom of the sky: scale x clamp(1 + strength x 0.02 x log10(px per km), 0.9, 1.3). Strength 0 = fixed sky.
- Settings screen: the note of the Parallax slider no longer says "saved only".

## Step 12d2: star background, first corrections

- Not run (no Godot here). Jon's 12d findings: formats and orientation of both images OK (both 2048 x 2048); the Milky Way layer had much too much grey haze; the sky shifted strongly in the last bit of zooming towards a body and the map seemed to snap sideways. Build label: "Alpha v0.1.12.d2 Testing".
- Haze: the Milky Way layer now uses a small canvas_item shader (`OrbitView.SKY_SHADER_CODE`, `blend_add`) that subtracts a black level from each colour channel and rescales: rgb = max(texel - black, 0) / (1 - black), then times the brightness. Setting `milkyway_black_level` (default 0.10, slider "Milky Way haze cut", 0 to 0.3). Measured on the image: the dark parts have a mean of about 0.065 (noise about 0.04), the haze of the band about 0.14, the bright band up to about 0.5. The stars layer is unchanged (CanvasItemMaterial add and modulate).
- Parallax default 0.25 (was 0.5). Note: a value already saved in user_settings.json (0.5) stays until "Reset to defaults" is used.
- Panning: the part of the shift that follows the view offset (`cam_offset` x `cam_scale`) is cut to 10 % (`SKY_PX_PER_SCREEN_PX` 0.05 -> 0.005) and has its own slider `pan_parallax` (0 to 1, default 1, "Background movement when panning"). Probable cause of the snap sideways: `cam_offset` is counted from `cam_body`, so the term jumps when the camera changes its body while zooming in or out. The distance-from-Sun term and the slight zoom of the sky (both scaled by the parallax strength) are continuous and unchanged.

## Step 12d3: sky panning scaled by the zoom within the body's context

- Not run (no Godot here). Jon: the snap and the strong shift come from the panning part being based on the view's position relative to the whole solar system, not on the current view context. Build label: "Alpha v0.1.12.d3 Testing".
- `OrbitView._context_zoom_fraction()`: 0 when the camera is zoomed out as far as the view of its body goes (`SNAP_OUT x _fit_scale(cam_body)`, beyond which the parent's view takes over; for the Sun `MIN_SUN_FIT x _fit_scale("sun")`), 1 at the highest zoom (`MAX_PX_PER_KM`), in between by the logarithm of the scale. `_update_sky` multiplies the panning part of the shift (view offset x scale, slider `pan_parallax`, 10 % constant of 12d2) by it. The distance-from-Sun term and the zoom of the sky are unchanged.
- Caveat: when the camera changes its body during a zoom (Moon -> Earth), the fraction is counted for the new body and can jump a little; the effect is small because it is multiplied by the already small panning constant.

## Step 12d4: sky follows the map movement seen on the screen (no more Sun-distance term)

- Not run (no Godot here). Jon on 12d3: panning in the Earth, Moon and Ceres views, even fully zoomed in, moved the sky not at all (the movement was still linked to the solar system map), and the snap when switching between the solar and a local view was still significant. Build label: "Alpha v0.1.12.d4 Testing".
- Cause: the shift was a function of the camera's absolute position (the AU term, 20 px per AU, jumps when the camera body changes and is large for the outer planets) and of `cam_offset x cam_scale x 0.005`, which is only a fraction of a pixel for a local pan.
- New: `OrbitView._update_sky` keeps an accumulated shift `sky_shift`. Every frame the movement of the camera relative to the body it is on (`cam_offset` in the frame of the previous frame's body, `body_rel_to(sky_prev_body, cam_body) + cam_offset - sky_prev_offset`, so a change of the camera's body does not move it, and neither does the orbital motion of the body being followed) is turned into the screen movement of the map (km x `cam_scale`, y flipped) and a part of it is added to the sky: `parallax_strength x pan_parallax x SKY_PAN_FACTOR (0.3) x _context_zoom_fraction()`, per frame at most 5 % of the larger screen side, the total limited to +-20 %. So a drag of 500 px at full zoom with strength 0.25 moves the sky about 37 px (strength 1: 150 px). Nothing in the formula depends on the position in the solar system, so there is no snap when the context changes (only later movement is weighted differently).
- Removed: the distance-from-Sun term (`SKY_PX_PER_AU`) and the old offset term. The slight zoom of the sky (strength x 0.02 x log10 of the scale, 0.9 to 1.3) is kept and continuous. Strength 0 = fixed sky.

## Step 12e: Credits screen (and new defaults)

- Not run (no Godot here). 12d4 was tested OK by Jon on 24 Nov (no snapping, even with the parallax at maximum). New scene `credits.tscn` with `scripts/credits_view.gd`: a new class/scene, so open the project with Edit first. Build label: "Alpha v0.1.12.e Testing".
- New defaults (Jon): `milkyway_black_level` 0.20 (was 0.10), `parallax_strength` 0.5 (was 0.25). Values already saved in user_settings.json stay until "Reset to defaults".
- Menu: a "Credits" button (third entry, after Settings) opens the Credits screen: title, a scroll list of credits (heading and text) and a Back button to the menu. The credits are the constant `CREDITS` in `credits_view.gd` (add new entries there). For now one entry: NASA, for the star background (Deep Star Maps of the Scientific Visualization Studio; public domain; NASA does not endorse this game). The NASA logo is not used.
- The text follows the text size setting (`apply_text_scale`), the heading uses `text_px`.

## Step 12f: frame rate display

- Not run (no Godot here). 12e was tested OK, and the 12c rows (animations, ship sprites, screen orientation, lighting shader) were reported OK by Jon on 24 Nov; the frame rate limit could not be checked without a display. Build label: "Alpha v0.1.12.f Testing".
- The info text of the orbit map (`OrbitView._info_text`) has a new line after the budget: "Frame rate: N fps (limit L)" with N = `Engine.get_frames_per_second()` (updated by Godot about once a second) and L the Frame rate limit setting. New setting `show_frame_rate` (default true; check box "Show frame rate" in the Display section of Settings) switches the line off.

## Step 12g: B-038 target orbit altitude when the destination changes

- Not run (no Godot here). 12f was tested OK by Jon on 24 Nov. Build label: "Alpha v0.1.12.g Testing".
- B-038 (found by Jon in 12f): with the ship in orbit of Mars, a transfer to Ceres with a target orbit of 7 km, then the destination changed to Earth: the target orbit altitude set itself to 60 km, inside the atmosphere. Cause: `OrbitView._orbit_for_body` (the orbit kept for another body) raised the periapsis only to `min_periapsis_altitude_km` (60 km at Earth), which is the lower limit for aerobraking. Now it is raised to the upper limit of the atmosphere, `AeroBraking.interface_altitude_km(atmosphere)` (about 158 km at Earth: scale height 8.5 km x ln(1.217 / 1e-8)), where the orbit does not decay.
- Not changed: `min_periapsis_altitude_km` and everything that uses it for aerobraking (`aero_braking.gd`: the aerobraking altitude limits, the burn-up check), and typed or dragged values of the target orbit (below the upper limit they still give the decay warning, as before).

## Step 12g2: B-038 rounding

- Not run (no Godot here). Jon on 12g: the periapsis came out at 158.2 km and still gave the decay warning ("below 158 km"), because the upper limit of the atmosphere is 158.17 km. Now `OrbitView._orbit_for_body` raises the periapsis to `ceil(limit) + 1` km (Earth: 160 km), so it is clearly above the limit. Build label: "Alpha v0.1.12.g2 Testing".

## Step 12h: Settings button on the orbital map

- Not run (no Godot here). B-038 was tested OK in 12g2 (Jon, 24 Nov). Build label: "Alpha v0.1.12.h Testing".
- `TopBar.SCREENS` has a new entry "Settings" (between Ship design and Menu), so the top bar of the orbit map (the only screen using `TopBar`) has a Settings button. It opens `settings.tscn` through the same `navigate` signal as the other buttons (`OrbitView._goto`, which also remembers the selected target).
- Back from Settings: new `UserSettings.settings_return` (default `res://menu.tscn`). The Settings button of the top bar sets it to the screen the bar is on (the orbit map); `SettingsView._on_back` goes there and resets it to the menu; the menu's `_ready` sets it to the menu too. So Back from Settings returns to the orbit map when opened from there, and to the menu when opened from the menu.
- Note: the orbit map is reloaded when Back is pressed (it starts again as when opened from the menu; the game state in `GameState` is kept as for the other buttons).

## Alpha v0.1 Stable

- Not run (no Godot here). The code is the same as step 12h (tested OK by Jon on 24 Nov); only the build label changes: "Alpha v0.1 Stable". All 0.1 steps (to 12h) are built and tested; the 0.1 bugs that are not fixed (B-008, B-009, B-010, B-013, B-033, B-035) and B-036, B-037 are planned for 0.2.

## Version 0.2, step 1: the course to a target joins the capture orbit (B-036)

- Not run (no Godot here): to be tried by Jon. Version 0.1 was released as "Alpha v0.1 Stable" (the code of step 12h). This code is the draft kept aside during 0.1, merged (three-way, from the 10bl base) into the 12h code.
- Seen in 10bl (Jon): Earth to Moon with the target orbit at the highest altitude (circular, 64,407 km): the course in the Earth view still aims at the centre of the Moon when the ship enters the Moon's context.
- `GameState.leg_rel_with_offsets` now also handles the view of the body the target orbits (Earth for the Moon, Sun for a planet, a planet for its moon): once the local approach position (`to_hyp`, mirrored by `to_mirror` through the new helper `_mirrored`, which the view of the target uses too) is inside the blend range, the path is stretched from the transfer's own path to the position of the target plus the local approach course. Weight 1 at the periapsis radius of the approach (the capture orbit), 0 at the larger of the context radius of the target and twice the periapsis radius (so that an orbit at the edge of the context still stretches smoothly). Fuel, timing and the view of the target itself do not change.
- `OrbitView._draw_scene` draws the planned transfer course from `leg_rel_with_offsets` of the plan's transfer leg (instead of the raw segment), so the line, the ship and the local route agree, also at the departure; with 240 points spaced by a cosine so that both ends (where the course bends) have more points (`TRANSFER_PATH_POINTS`).
- Not changed: the green orbit of the transfer leg (the full ellipse of the leg) in the Earth view, and the departure from a moon to a planet (B-008, B-035).
- Build label: "Alpha v0.2.1 Testing".


## Version 0.2, step 1b: the course blend of B-036 is taken out

The blend added in 0.2.1 (in the view of the body the target orbits, the course faded from the transfer path to the target's position plus the local approach hyperbola) made a new spline between two different curves, and the ship followed it. It is removed from `GameState.leg_rel_with_offsets`; the course and the ship path in that view are those of Alpha v0.1 Stable again. The 240-point drawing of the planned course (`TRANSFER_PATH_POINTS`) is kept. B-036 stays open: the transfer is aimed at the target's centre while the capture orbit is far from it, so the proper fix is to aim the transfer at the capture point (together with the Lambert solver).


## Version 0.2, step 2: minimum thrust for lift-off

- `ShipCalc.LIFTOFF_MIN_TWR` = 1.5: a ship leaving a surface needs a net acceleration of 1 g (to overcome the local gravity) plus 0.5 g, both in the local surface gravity (0.5 g is 4.9 m/s2 on Earth), so a thrust-to-weight ratio of at least 1.5 at lift-off. The atmosphere is ignored; lifting bodies and winged hulls get no bonus (low down the wings meet much more air resistance, high up there is little lift without extreme speeds).
- Surface gravity = GM / radius^2 from `bodies.json` (`ShipCalc.surface_gravity_ms2`): Earth 9.80 m/s2, Moon 1.62, Mars 3.71, Ceres 0.28. Phobos and Deimos have about 0.006 and 0.002 m/s2 (every body except the Sun counts as having a surface).
- `GameState.can_lift_off(body_id)` compares the first stage's thrust with the ship's weight (empty mass plus the propellant it has now). Nothing in the game departs from a surface yet, so the mission planner does not use it yet; the Ship design screen lists for every body the thrust-to-weight ratio of the design (first stage, full mass), whether it can lift off and the thrust it would need.


## Version 0.2, step 3a: leaving a moon for a planet as patched conics (physics only; B-035, B-008)

- Applies to a ship in orbit round a moon (the Moon, Phobos, Deimos) with a planet or dwarf planet as the destination. The heliocentric transfer still starts at the centre of the moon's planet; what changed is the burn and the departure time.
- `TransferPlanner.moon_escape`: the transfer needs the excess speed v_dep - v_planet relative to the planet. The ship must leave the moon on an escape orbit of the planet that passes through the moon's place (counter-clockwise, outward bound) with that excess speed and with the outgoing asymptote in the right direction. The orbit is found by trying the angle psi (0 to 90 degrees) of the velocity at the moon's place against the radius, with the speed sqrt(v_inf^2 + 2 GM/r); the root of the asymptote direction error is refined by bisection. The excess speed relative to the moon is the difference of that velocity and the moon's own velocity; the burn is the usual escape burn from the circular parking orbit (periapsis radius of the ship's orbit). Of several roots the cheapest one is used. The moon's SOI is treated as a point (zero-radius patch).
- Launch windows: the moon has to be in the right place for the escape, so with no fixed departure time `MissionPlanner.make_plan` tries `MOON_WINDOW_STEPS` + 1 = 49 departure times over one orbit of the moon around the planet's own best departure time (never before the start time), each with its own Lambert transfer (same flight time as the window's transfer), and takes the cheapest burn. A fixed departure time (the departure time control) is judged for the moon where it is then; if no escape orbit exists then, the old estimate (best direction, any moon phase) is used.
- Not changed: the drawn course (the Moon hyperbola, the Earth hyperbola, the Sun transfer) and the ship's path in the views. That is step 3b.


## Version 0.2, step 3b: the drawn course when leaving a moon for a planet (B-035, B-008)

- `MissionPlanner.make_plan` stores the escape orbit found in step 3a as `plan["moon_escape"]` (the ship's velocity round the planet at the moon's place, the excess speeds relative to the planet and to the moon). `TransferPlanner.moon_escape` now also refuses escape orbits whose periapsis round the planet is lower than the planet's radius + `MOON_ESCAPE_CLEARANCE_KM` (300 km), so the ship no longer flies through the planet (this can change a burn or the departure time of 0.2.3 a little).
- `GameState._add_moon_escape_course` gives the transfer leg two hyperbolas (built with `_escape_hyperbola`, the B-030 construction for a hyperbola through a given point with a given velocity):
  - `planet_hyp`: round the planet, through the moon's place at the departure time with the ship's velocity; far away it turns into the transfer's own path (relative to the planet; it starts at the planet's centre) like the departure from a planet. Its blend zone is made as large as the moon's orbit (`scale`).
  - `from_hyp`: round the moon, from the ship's place in its orbit, tangentially, with the excess speed relative to the moon. Its far path is the planet course seen from the moon (`_moon_far_course`: the planet course minus the moon's own position), the direction is taken over 1.5 hours after departure (not a day, because the moon moves 90,000 km a day).
- Views (`leg_rel_with_offsets`): the moon's view shows from_hyp blended into the planet course; the planet's view shows the planet course (the escape orbit through the moon's place, leaving tangentially); the Sun view is as before (the ship starts at the moon, the offset fades out).
- Plans without a moon escape (a fixed departure with no escape orbit then) keep the old display.


## Version 0.2, step 3c: a moon leaving for a higher orbit round its planet (B-039), and the aerobraking suggestion check (B-037)

- B-039: `TransferPlanner.transfer_to_central` assumed the ship always goes down (it starts at the apoapsis of the transfer ellipse). Leaving Phobos for a circular orbit at 10,000 km altitude (higher than Phobos) put the ellipse the wrong way round: it started and ended at the target orbit and never touched Phobos' orbit. Going up (r2 > r1) the ship now starts at the periapsis (`peri_longitude` = the departure direction, mean anomaly 0); going down is as before.
- B-037: `AeroBraking.setup_plan` no longer suggests aerobraking when (1) the arrival orbit has less energy than the target orbit (arrival energy <= -GM / (rp_t + ra_t); aerobraking only takes energy away), or (2) the plan with aerobraking needs as much delta-v after arrival as the propulsive capture (it is only suggested when it is cheaper). The player can still switch it on; the message says why it is off.
