# Reversing notes — [PROXIMA!] The Moon Wakes Up

Universe `8751492147`, place `133579701570149`. Index: 166 scripts, placeVersion 4315,
`failedToDecompile: 0`. All findings below were verified live in-game, not inferred.

## Anti-cheat / injection status

- `dump-anticheat-hooks` came back with clean C closures and no injected connections.
- The 32 remotes in `ReplicatedStorage.Events` are plain `RemoteEvent`/`RemoteFunction` — no
  BufferNet, no ByteNet, no custom serialisation. **RakNet work and an HWID spoofer were judged
  unnecessary**, which is why the account with progress (PurpleHologr) stays in use.
- Damage appears to be applied server-side: no client script takes damage, so a client-side god mode
  can only block what the client itself applies. Paralyz says so in the menu instead of pretending.

## Mining (the auto-farm core)

Verified sequence:

1. Aim the camera so `Mouse.Target` is a part inside a planet's `Rocks` folder.
2. `Tool:Activate()` sends the swing.
3. The server answers on `Events.Pickaxe.OnClientEvent`; the game's own `PickaxeController` then
   fires `FireServer(mouse.Target)`.
4. A `MoonJuice` **Tool** with a `Credits` NumberValue appears in the Backpack.
5. `Events.SellMoonjuice:FireServer(count, true)` sells every juice tool → `LocalPlayer.Stats.Credits`.

Consequences the code respects:

- **Aiming is mandatory.** `util.aimAt` solves a camera CFrame whose ray through the mouse actually
  lands on the rock (iterative NDC solve), then holds it on `RunService:BindToRenderStep`.
- **Rocks are recursive.** The `Rocks` folder is a direct child on Planet4/Planet5 but hangs off the
  planet's `Center` part on Planet3/Planet6/Planet8/Planet9, so the lookup walks descendants.
- **The folders are filled in waves.** All six were empty across several servers and many minutes of
  watching — an empty folder means *wait*, not *broken*. No client script mentions `Rocks` or
  `Minable`, so the spawner is server-owned.
- The `Minable` BoolValue is inconsistent (observed `false` on rocks that still accepted a swing), so
  it is never used as a filter.

## World layout (one server's snapshot — phases change this)

| Landmark | Position |
| --- | --- |
| Bunker | `725, 3033, -1332` |
| City | `654, 3063, -1230` |
| Sun | `464, 3101, 468` |
| Planet1 | `741, 3028, -1821` |
| Planet2 | `739, 6963, -10239` |
| Planet3 | `747, 2808, 9821` |
| Planet4 | `747, 4130, -17324` |
| Planet5 | `342, 2975, 15713` |
| Planet6 | `754, 3527, -35754` |

- The `Planets` folder also held `Planet8`, `Planet9` and `GasGiants` on a later server — the world
  grows with the story phase, and `VenusCity` did not exist at all in the sessions checked.
- That is why `travel.luau` resolves destinations **lazily** (a function per destination) and reports
  "not in this world yet" instead of holding stale coordinates.

## Currencies

- `LocalPlayer.Stats.Credits` — the main wallet (PurpleHologr started at 6,450).
- MoonJuice is carried as ordinary Tools in the Backpack, each with a `Credits` NumberValue, so
  "how much juice am I holding" is just a scan of the Backpack.
- `ReplicatedStorage.Values.*` also carries `MoonJuice*` and `Fuel` readouts.
- Buildings are bought with `Events.Buy:FireServer(name, "Building", cost, planet)` — spending
  per-planet currencies (MoonJuice/Mars/Venus), a possible later module.

## Remotes (32 in `ReplicatedStorage.Events`)

`Pickaxe`, `SellMoonjuice`, `Buy`, `QuestMine`, `QuestKill`, `QuestBuild`, `QuestRequest`,
`QuestEvent`, `Fly`, `Jump`, `Respawn`, `Infected`, `Award`, `Leaderboard`, `Leaderboard2`,
`PlaytimeReward`, `PlaytimeClaim`, `CameraShake`, `Shake`, `VFXEvent`, `Text`, `Tutorial`,
`DeviceTypeRemote`, `getsettings`, `Robux`, `EntitlementPrompt`, `SatelliteEvent`, `TrainEvent`,
`SpaceShip` (folder), `MoonMonster` (folder), `MoonBoss` (folder), `8e2f3bb1-…` (unnamed).

Also `ReplicatedStorage.SpaceShipControl` (RemoteEvent) and `ReplicatedStorage.VIPspaceship`.

## Infection gameplay

`Players.<you>.PlayerScripts.MoonMonsterPlayerControls` gates on
`Character:GetAttribute("MoonMonsterPlayer") == true` (and `MoonBossPlayer ~= true`), and uses
`Events.MoonMonster.Attack` — that remote is for *becoming* a moon monster, not for monsters hurting
you. Monsters themselves are `Moonfected` models under `Workspace.Unanchored.SmallMoonMonsters`
(Humanoid 100/100); `MoonMonsters` was empty in the sessions checked.

## Executor gotchas hit here

- `firesignal` is a silent no-op in Real — use `send-input` for anything that must really happen.
- `BindToRenderStep` lives on `RunService`, not `Camera`.
- Drawing overlays must project with `Camera:WorldToViewportPoint`, not `WorldToScreenPoint`.
- Rayfield Gen2: `window:Unload()` (not `Destroy`), element `Set(value, true)` skips the callback,
  dropdown `.value` is always a table even in single mode, keybinds must be `Enum.KeyCode`.
- Rejoin (TeleportService back into the same place) wipes `getgenv` and every hook — the DataModel is
  new even though the process id is unchanged.
