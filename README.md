# Wildlight

A procedurally generated photography and hunting game, built in **Godot 4.3**
with GDScript.

You are a naturalist with a camera and a rifle in procedurally generated
wilderness. You scan the ground for prints, stand still and listen for calls,
work out where an animal went — and then you photograph it. **The photograph is
what enters it into your Discovery Book**, and the first one you ever take of a
species becomes the cover of its page for good.

Everything is generated: the land, the animals, the villages, the weather — and
every sound in the game, which is synthesised at runtime rather than shipped as
audio files. The repository contains no binary assets, no meshes and no
textures. Every triangle you see is built by code at load time.

---

## The loop

1. **Find sign.** Hold `Q` to scan the ground. Prints are reported by species,
   age ("minutes old", "cold"), bearing and the direction the animal was
   heading. Scat, rubs, beds and dropped feathers turn up too.
2. **Listen.** Hold `E` to stand still and read the bearing ring: nearby animals
   show up by direction and loudness. Listening carefully makes them more likely
   to give themselves away.
3. **Stalk.** Wildlife reacts to three things you control — the noise you make
   (crouch, don't sprint, mind the surface), your outline in their vision cone,
   and your scent on the wind. Get downwind of a boar and you can walk
   astonishingly close.
4. **Photograph.** Hold right mouse to raise the camera. Set aperture, shutter
   and ISO against the actual light. Press left mouse.
5. **Get scored.** Composition, subject, focus, exposure, light and moment, all
   measured from the real scene at the instant of capture.
6. **Then hunt, if you want to.** Swap to the rifle with `X`. Harvesting records
   measurements — but it opens no page. Only a photograph does that.

---

## Lighting

Lighting is the point of the game, so it is a first-class system rather than a
backdrop.

- A full day/night cycle drives sun elevation, colour temperature, ambient
  light, sky gradient, star cover and fog. Golden hour, blue hour, twilight,
  overcast and flat overhead sun are all distinct named states.
- The sky computes a real **EV (exposure value)** for the current conditions.
  Your camera computes its own EV from aperture, shutter and ISO. The difference
  between them is what you see in the viewfinder: get it wrong and the frame
  goes black or white long before the scorer says anything.
- Weather drifts through a Markov chain — clear, fair, overcast, mist, rain,
  storm, snowfall — changing cloud cover, fog density, light level,
  precipitation, wildlife activity and how well rain masks your approach.
  Storms flash and the thunder arrives late, by distance.
- Village lanterns and cabin hearths come on after dark.

## Atmosphere

- The sky is a custom shader: a gradient with **real drifting cloud layers**
  whose coverage is driven by the weather system, plus a sun disc, horizon haze
  and stars. Godot caches its radiance map, so the clouds also tint the ambient
  light landing on the ground.
- **Wind is simulated and visible.** The weather system publishes a wind vector
  that wanders over time; vegetation shaders bend grass, bushes and tree crowns
  along it, and the water shader gets choppier as it rises. That same vector is
  what carries your scent to an animal's nose, so what you can see the wind
  doing is what the wildlife is reacting to.
- Ground, bark and leaves go **wet after rain** and dry out slowly.
- Height fog pools in the valleys overnight and burns off through the morning;
  aerial perspective separates far ridges; on desktop, volumetric fog turns a
  low sun into shafts through the canopy.

---

## Photography

Seven lenses, earned with reputation (all unlocked in Sandbox):

| Lens | Character |
|---|---|
| Standard 50mm f/1.8 | Sees roughly what you see |
| Wide 24mm f/2.8 | Landscapes, interiors |
| Ultrawide 16mm f/4 | Fits a whole cabin interior in frame |
| Portrait 85mm f/1.4 | Backgrounds melt; unforgiving about focus |
| Telephoto 70-200mm f/2.8 | The working zoom |
| Super Telephoto 400mm f/5.6 | Reaches a wolf on a ridge; heavy and dim |
| Macro 100mm f/2.8 | Tracks, feathers, frost |

Field of view comes from real focal length on a 36×24 mm sensor. Depth of field
is computed from the hyperfocal distance, so f/1.4 on the 85 really does give
you centimetres of sharpness. Too slow a shutter for the focal length smears the
saved image; too much ISO puts grain in it.

The viewfinder carries a rule-of-thirds grid, a **live luminance histogram**
sampled from the actual frame, an exposure meter in stops, a level, a focus box
and subject boxes.

### Genres

The genre is inferred from what is actually in the frame, then scored against
what that genre cares about:

**Wildlife · Portrait · Group · Landscape · Street · Interior · Wedding · Detail**

Each photo is graded S–E with a six-axis breakdown and written notes —
"Horizon cuts the frame in half", "Rim light around the subject", "Blown out by
1.8 stops", "Turned away — a portrait wants the eyes".

Scoring reads the real scene: where the subject landed in frame, its apparent
size against the ideal for that genre, whether the lens was focused on it,
whether it was clipped by the frame edge, whether terrain or leaves were in the
way (terrain hides a subject outright, foliage only veils it), whether the sun
was on it or behind it, and what it was doing at the moment of capture.

---

## The Discovery Book

Open with `Tab`, in game or from the title screen.

- Species are grouped by family and start as `- - - - -`. Sign you have found,
  and calls you have heard, appear under an unrecorded entry.
- Photograph one and it opens a page. **That first frame is the cover.** You can
  promote a better shot from the gallery later.
- **Field Notes** unlock by observation, not by discovery: habitat after seeing
  it in two places, an activity chart after three different hours, diet after
  watching it feed, tendencies after several behaviours, features after three
  photographs or a harvest, and tracks after finding sign three times.
- **Gallery** holds every photo of that species with grade, genre, hour and
  light.
- **Range** plots your own sightings on a map rendered straight out of the
  terrain generator.

15 species across the biomes — whitetail deer, red stag, moose, grey wolf, red
fox, brown bear, wild boar, snowshoe hare, great horned owl, raven, mallard,
bighorn ram, pronghorn, bobcat, river otter — each with its own senses, herd
behaviour, activity window, habitat weighting, call and track shape.

---

## Worlds

Seven biomes, chosen by temperature, moisture and altitude: **Emerald Vale,
Amber Woods, Boreal Taiga, Mistwood Marsh, Golden Steppe, Ochre Badlands,
Alpine Ridge**. Rivers are carved by ridged noise, and every world has a seed
you can type in on the title screen, with a live map preview and a description
of what is in it.

Villages are generated on a coarse grid and are a pure function of the seed, so
the map can show one you have not walked to yet. Each has a plaza, a well,
paths, lantern posts and cabins with **real interiors** — floor, door, windows,
hearth, bed, table, candle — which is what makes the interior and street genres
work. Some are markets, some have a wedding in progress with a bride, groom,
officiant and guests. Villagers notice a raised camera and hold still for it.
Wildlife does not.

---

## Modes

- **Expedition** — assignments from the society, reputation, lenses to earn.
  Three live assignments at a time: species studies, genre commissions, surveys
  of N species, and difficult-conditions briefs.
- **Free Roam** — the same world with no assignments.
- **Sandbox** — every lens unlocked, plus a control panel (`G`) for scrubbing
  the clock, freezing time, forcing any weather, spawning any species in front
  of you, and travelling to a named biome or the nearest village.

---

## Controls

**Desktop**

| | |
|---|---|
| Move / sprint / crouch | `WASD` · `Shift` · `Ctrl` |
| Look | Mouse |
| Raise camera | Right mouse (hold) |
| Shoot photo / fire | Left mouse |
| Swap camera / rifle | `X` |
| First ⇄ third person | `V` |
| Scan for sign | `Q` (hold) |
| Listen | `E` (hold) |
| Aperture / shutter / ISO | `1` `2` · `3` `4` · `5` `6` |
| Focus near / far · autofocus | `,` `.` · `R` |
| Change lens · zoom | `[` `]` · wheel |
| Discovery Book · map | `Tab` · `M` |
| Interact / harvest | `F` |
| Sandbox panel | `G` |
| Pause | `Esc` |

Gamepad is mapped throughout (sticks, triggers to aim and shoot, shoulders to
scan and listen).

**Mobile** — landscape only. Left thumb drives a floating stick, dragging the
right half looks around, and a short tap there fires the shutter. Aim, shoot,
swap, scan, listen, crouch, view, book and menu are on-screen buttons. Enable
them by hand in Settings on desktop.

---

## Running it

Open the folder in Godot 4.3 (Forward+) and press play.

Headless checks, no editor needed:

```bash
# parse every script and build the class cache
godot --headless --path . --import

# boot a real world, photograph an animal, walk into a village, report
godot --headless --path . -- --smoke
godot --headless --path . -- --smoke --seed=991337
godot --headless --path . -- --smoke --sandbox --seed=777
```

The smoke test generates terrain, spawns wildlife, finds a clear sightline,
frames an animal, runs analysis and scoring, commits it to the Discovery Book,
then walks into the nearest village and reports on all of it. A typical run:

```
[smoke] clear sightline found after 5 tries
[smoke] subjects in frame: 5
[smoke] genre group, grade B, score 74.8, subject 'Whitetail Deer'
[smoke] breakdown { "composition": 51.8, "subject": 48.8, "focus": 100, ... }
[smoke] initial load took 2.3s for 150 chunks
[smoke] villagers within 45m: 7, interiors mapped: 133
```

---

## Playing it in a browser

The project exports to WebAssembly and is set up to deploy as a static site.

```bash
bash build.sh          # fetches Godot + the web template, exports to ./build
```

`vercel.json` is committed, so importing this repository into Vercel needs no
configuration: it picks up the build command, the output directory, and the
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers the
threaded web build needs for `SharedArrayBuffer`.

To serve the build locally you need those same two headers — a plain
`python -m http.server` will not work, because without cross-origin isolation
the engine cannot start its threads.

What differs in the browser:

- The web build runs on **WebGL2 via the Compatibility renderer**, which has no
  depth of field, SSAO or volumetric fog. Focus still governs scoring, and a
  missed focus visibly softens the saved photograph so the mistake is not
  invisible — but you do not get live bokeh in the viewfinder.
- Web starts from a lighter preset (lower quality, shorter view distance, a
  tighter initial load ring). Anything you change in Settings overrides it.
- Photos are written to the browser's IndexedDB-backed storage rather than a
  folder on disk, so the Discovery Book persists per browser.

---

## How it is built

```
scripts/
  autoload/    settings + runtime input map, save system, Discovery Book data,
               audio director, game state
  audio/       the synthesiser: every sound is generated here at boot
  world/       terrain generator, biomes, chunk builder, voxel mesher, prop
               cache, structures/villages, sky, weather, streaming, world root
  player/      character controller, camera rig
  photo/       lenses, the camera, the scorer
  animals/     species tables, procedural voxel bodies, AI, the director
  npc/         villagers
  tracking/    footprints and field sign, scan and listen
  hunting/     rifle and ballistics
  contracts/   assignments
  ui/          HUD, viewfinder, Discovery Book, review, menus, map, touch
tools/         headless validator
```

Some notes on the implementation:

- **Terrain is a continuous surface** sampled from the height field on
  `WorkerThreadPool` threads, with per-vertex normals taken from its gradient.
  Gentle ground uses those smooth normals so hills roll; steep ground blends
  toward flat face normals so a cliff breaks into rocky facets instead of a
  draped sheet. Everything about a world is a pure function of its seed and a
  coordinate, so chunks can be built in any order and still agree, and the game
  can answer "how high is the ground there" for places that have never been
  meshed.
- **Trees are instanced, not merged.** Each is grown once per
  (biome, kind, variant) from tapered limbs and faceted blobs, then drawn with
  `MultiMesh` — one instance transform per tree. A trunk blocks movement and
  bullets; the crown only blocks line of sight, which is what lets you see an
  animal through a stand of trees.
- **Animals move against the height field** rather than through the physics
  solver, so a valley full of deer costs almost nothing. Their collision shape
  exists purely so bullets and autofocus have something to hit.
- **Creatures are built from the same primitives as the trees** — limbs and
  blobs, flat shaded — because they are the subject of every photograph and
  have to hold up under a 400mm lens. Buildings stay on a one-metre voxel grid,
  where blockiness reads as carpentry rather than as a compromise.
- **Falling through the world is impossible**: the player is clamped to the
  terrain height field, which is defined everywhere even where nothing has
  streamed in yet.
- Data shared with worker threads is kept to plain values. Copying a nested
  container out of a shared script constant on several threads at once is not
  safe, which is why the mesher's face tables are flat arrays of vectors.

## Status

This is a complete, playable vertical slice rather than a finished game. The
whole loop works end to end — track, stalk, photograph, score, record, hunt —
across all seven biomes and eight genres, and it has been exercised headlessly
across many seeds. What it most wants next is real playtesting for feel: the
tuning of scoring weights, animal wariness and lens unlock pacing are first
drafts, not settled numbers.
