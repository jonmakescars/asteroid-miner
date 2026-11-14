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
