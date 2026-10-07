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
- **Never install `spy-namecall` / remote-spy / any `__namecall` hook in this game** — it kicks with
  Error 257 within seconds. Safe patterns proven here: `OnClientEvent:Connect`, `OnServerEvent`-side
  observation, plain `FireServer` calls. Rejoining wipes `getgenv` and every hook anyway.

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
- **The folders are filled by proximity.** Folders fill ~3s after a player gets near a planet
  (Planet5 = 18 rocks) and empty again when the player leaves — an empty folder means *move closer*,
  not *broken*. No client script mentions `Rocks` or `Minable`, so the spawner is server-owned.
  Hence farm rotation: teleport → wait ~3s → farm → next planet when empty.
- The `Minable` BoolValue is inconsistent (observed `false` on rocks that still accepted a swing), so
  it is never used as a filter.

### The server's two hard rules (measured)

- **Mining range ≤ ~30 studs from the rock centre.** Binary search across jobs: swings accepted at
  30 studs, rejected at 37, 55, 90 (12-swing batches, zero juice at range). Position is *never*
  rolled back — holding 2000 studs away for minutes is fine — the server only checks swing distance.
  So far-hide is impossible; the shipped "hide mining" stance puts the character **inside the rock**
  (`hideOffset = 4` from centre): server-accepted (+2 juice / 12 swings) and the character is hidden.
- **Every swing is answered at the shipped cadence.** At `swingDelay = 0.35` the ask count equals
  the swing count (7 asks / 6 swings, 6/6 at 1.2s too) — the server does not throttle fast swings,
  so more swings per minute is strictly better; cadence stays 0.35.
- Observed yield this build: **~5–8% per swing** (~20 swings per rock-break). Earlier 17–25%
  numbers were small-sample luck, not a different rule.
- **Healthy equip is mandatory.** Setting `tool.Parent = character` leaves a *stuck* tool where
  `Tool.Activated` never fires. The working path: unequip everything to Backpack, then
  `Humanoid:EquipTool(pick)`. When mining stops for no reason, the farm's auto-fix chain runs
  1) reequip → 2) switch rock (20s cooldown) → 3) settle, unattended.

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

## Quests & playtime

- Knit `QuestService`: `GetQuests()` may return data *or* a promise — always handle both.
  `ClaimQuest("Daily"|"Weekly", id)` is safe to call.
- Playtime rewards: listen for `Events.PlaytimeReward` with `Action == "Ready"`, then
  `Events.PlaytimeClaim:FireServer()` — 1800s cycle.
- `MineHits` quest never counts progress (server-side gap), and the `Minable` flag is useless as a
  filter — don't build anything on either.

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
  `send-input` is focus-dependent, so it is only usable for manual testing, never for shipped
  features; everything shipped must run in the background (camera aim + `Tool:Activate` do).
- `BindToRenderStep` lives on `RunService`, not `Camera`.
- Drawing overlays must project with `Camera:WorldToViewportPoint`, not `WorldToScreenPoint`.
- Rayfield Gen2: `window:Unload()` (not `Destroy`), element `Set(value, true)` skips the callback,
  dropdown `.value` is always a table even in single mode, keybinds must be `Enum.KeyCode`.
- Rejoin (TeleportService back into the same place) wipes `getgenv` and every hook — the DataModel is
  new even though the process id is unchanged.
