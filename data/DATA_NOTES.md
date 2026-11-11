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
