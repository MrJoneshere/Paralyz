# Paralyz

Rayfield Gen2 hub for **[PROXIMA!] The Moon Wakes Up** (place `133579701570149`, universe `8751492147`).

## Layout

The hub is split into small, single-purpose modules that a thin loader wires together.
Nothing here is one giant script: each feature owns one file and exposes one table.

```
loader.luau          entry point - creates the window, requires and wires every module
src/
  config.luau        tunables: farm delays, sell thresholds, teleport destinations
  state.luau         shared flags + the one-owner value store the GUI writes to
  util.luau          character/camera/remote helpers used by more than one module
  perf.luau          no-render mode + GPU guard (low quality, shadow off, fps cap, minimise)
  esp.luau           ore / monster / player ESP
  farm.luau          auto-mine loop + auto-sell of MoonJuice
  combat.luau        god mode, auto-swing, damage helpers
  travel.luau        teleport + noclip + fly
scripts/
  build.luau         bundles src/* into dist/paralyz.bundle.luau for one-paste execution
dist/
  paralyz.bundle.luau  the built, ready-to-run script
```

## Why split

Each module can be reloaded, reviewed and pushed on its own. `loader.luau` is the only file
that knows about the window; a module never reaches into another module's internals, it
goes through `state`.

## Build

Run the bundler, paste the result:

```powershell
node scripts/build.mjs
```

## Research notes

The reversing work that produced these modules (remotes, mining flow, sell protocol)
is recorded in-game with Real's memory store and summarised in `NOTES.md`.
