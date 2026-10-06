# Paralyz

A modular cheat hub for **[PROXIMA!] The Moon Wakes Up** (placeId `133579701570149`), built on
[Rayfield Gen2](https://sirius.menu/gen2).

The delivery is a tiny `loader.luau` that pulls each module from this repo at run time, so the thing
you paste into an executor is always a few lines - never one giant script.

```lua
-- once the repo is public:
loadstring(game:HttpGet("https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/loader.luau"))()
```

While the repo is still **private**, HttpGet cannot read it, so use the bundled build instead
(`dist/paralyz.bundle.luau`), which carries every module inline.

## Layout

| Path | What it is |
| --- | --- |
| `loader.luau` | Entry point: fetches modules, builds the Rayfield window, wires every element through `state` |
| `src/config.luau` | Every tunable, in one place. Data only. |
| `src/state.luau` | The single owner of every value the menu shows |
| `src/ui.luau` | Defensive wrappers over Rayfield Gen2 elements, bound to state keys |
| `src/util.luau` | Character, tool, juice, rock and camera-aim helpers |
| `src/perf.luau` | No-render mode (quality, shadows, post effects, FPS cap) |
| `src/esp.luau` | Drawing-library overlays for players, monsters, juice and rocks |
| `src/farm.luau` | Auto-farm: aim, swing, collect, sell |
| `src/combat.luau` | Auto-swing, keep-distance, best-effort damage guard |
| `src/travel.luau` | Teleport, noclip, fly |
| `scripts/build.mjs` | Packs everything into `dist/paralyz.bundle.luau` |
| `dist/paralyz.bundle.luau` | Self-contained build for the private-repo phase |
| `NOTES.md` | Reversing notes: what the game actually does |

## Modules

Every module is a factory that receives its dependencies explicitly:

```lua
-- src/farm.luau
return function(deps)
    local config = deps.config
    local state = deps.state
    local util = deps.util
    ...
end
```

`config` and `state` are the two exceptions: they are data, not factories, and the loader pulls them
without calling the result.

## Build

```powershell
node scripts/build.mjs
```

The bundler replaces the `local PARALYZ_MODULES = nil -- PARALYZ_BUNDLE` sentinel in `loader.luau`
with a literal table of the `src/*.luau` sources, picked long-bracket levels and all. The dev path
(loading `loader.luau` directly from `main`) never sees the bundle and fetches modules one at a time.

## One owner per value

The menu and the code both talk to `src/state.luau`, never to each other:

- an element callback writes state (`state.set`)
- code writes state
- state pushes changes back to the element with `Set(value, true)`, which skips the element's callback

That is why toggling can never feed back into itself, and why the UI and the truth cannot disagree.

## Testing policy

Any auto-farm **test** is capped at 5 cycles:

```lua
getgenv().Paralyz.farm.start({ maxCycles = 5 })
```

The GUI's Auto Farm toggle takes no cap and runs open-ended - the cap exists for development only.
Rejoin the server before every GUI run so each test starts from a clean DataModel.

## GPU guard

This machine's screen has died once to what looked like a GPU failure (RX 590, driver 31.0.21925.1001),
so:

- `ClientAppSettings.json` caps launch FPS and texture quality
- Paralyz defaults **no-render mode ON**: `QualityLevel.Level01`, `GlobalShadows` off, post effects off,
  `setfpscap(20)`
- `gpu-load.log` / `gpu-watch.log` sample GPU load and adapter status continuously, and the
  `ParalyzAdmin` scheduled task keeps both watchers alive across reboots

## License

MIT (see `LICENSE`).
