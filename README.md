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
| `src/esp.luau` | Highlight-pool ESP (capped per layer) + one optional label |
| `src/farm.luau` | Auto-farm: stance hold inside the server's mining range, swing, yield-aware auto-fix, collect, ion-first planet rotation, convert ion, sell |
| `src/combat.luau` | Keep-distance guard + gun mods: rail/rocket refire & volley, HexSpitter (Moon Gun) auto fire-loop with FireRate/accuracy/damage/pellet pins |
| `src/travel.luau` | Teleport, noclip, fly |
| `src/rewards.luau` | Free income: playtime chest listener + daily/weekly quest auto-claim (Knit QuestService) |
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

Any auto-farm **test** is capped at 5 collected MoonJuice stacks:

```lua
getgenv().Paralyz.farm.start({ maxJuice = 5 })
```

(`{ maxCycles = n }` also exists as a hard swing-count backstop.) The GUI's Auto Farm toggle takes
no cap and runs open-ended - the caps exist for development only. Rejoin the server before every GUI
run so each test starts from a clean DataModel.

Measured cadence note: the server answers **every** swing at the shipped `swingDelay = 0.35` (ask
count = swing count), so slower cadence buys nothing - more swings per minute is strictly better.

## GPU guard

This machine had **6 hard freezes in one night** (2026-10-07, RX 590, driver 31.0.21925.1001):
three idle/poisoned-driver locks and two load-triggered ones (GPU at ~90% seconds before death,
screen black + fans at 100%). No BSOD/TDR/WHEA event ever - the wedge is below TDR's reach.
Mitigations in place, in order of arrival:

- `ClientAppSettings.json` (`DFIntTaskSchedulerTargetFps: 20`) caps launch FPS so Roblox never
  opens at an uncapped load spike - the exact window where crashes #2 and #6 died
- `TdrDelay=8` / `TdrDdiDelay=8` (`HKLM\...\Control\GraphicsDrivers`) and `EnableUlps=0` on the
  adapter - all verified still active after every reboot
- PCIe ASPM off (AC+DC) on the Atlas Power Scheme, Fast Startup disabled
- Paralyz defaults **no-render mode ON**: `QualityLevel.Level01`, `GlobalShadows` off, post effects
  off, `setfpscap(20)` - in-game load collapses from ~80% to ~28% the moment it applies
- `gpu-load.log` / `gpu-watch.log` sample GPU load, RAM% and adapter status continuously (with
  `FREEZE-GAP`/`CLEAN-GAP` boot markers and `ROBLOX` context tags), and the `ParalyzAdmin`
  scheduled task keeps both watchers alive across reboots
- Windows Memory Diagnostic **Extended: no errors** - the mixed 8+16+8 GB sticks are exonerated

Remaining suspects: driver state (DDU clean reinstall if it recurs) and GPU thermal/power at peak
load.

## License

MIT (see `LICENSE`).
