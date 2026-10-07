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
| Planet1 = **Earth** | `741, 3028, -1821` |
| Planet2 = **Moon** | `739, 6963, -10239` |
| Planet3 = **Venus** | `747, 2808, 9821` |
| Planet4 = **Mars** | `747, 4130, -17324` |
| Planet5 = **Mercury** (user: "not sure") | `342, 2975, 15713`, observed **drifting** to `718, 4706, 10637` mid-story — matches "MERCURY HAS WAKEN UP ... HEADING TOWARDS VENUS" |
| Planet6 = **Pluto** | `754, 3527, -35754` |

- Planet↔name mapping is the user's (P5=Mercury is his guess), corroborated by the story messages
  and `ChangeSky.EarthSky` reading Planet1 / `ChangeSky.VenusSky` reading Planet3. Corrected from an
  older note that called Planet1 "the Moon" - Planet1 is **Earth** (City/SpawnLocation/SpaceStation
  all live there); Planet2 is the Moon.
- Planets **move** during the story (Mercury drifts toward Venus), so every teleport resolves a live
  `Centre`/`Center` child - never the table above, and never a cached pivot.
- The `Planets` folder also held `Planet8`, `Planet9` and `GasGiants` on a later server — the world
  grows with the story phase, and `VenusCity` did not exist at all in the sessions checked.
- That is why `travel.luau` resolves destinations **lazily** (a function per destination) and reports
  "not in this world yet" instead of holding stale coordinates.

## Currencies

- `LocalPlayer.Stats.Credits` — the main wallet (PurpleHologr started at 6,450).
- MoonJuice is carried as ordinary Tools in the Backpack, each with a `Credits` NumberValue, so
  "how much juice am I holding" is just a scan of the Backpack.
- `ReplicatedStorage.Values.*` are the **spendable per-planet balances**, not just readouts: every
  `Events.Buy` client check is `Values.<cur> - cost >= 0`. Observed 2026-10-07:
  `MoonJuice=993, MoonJuiceMars=264, MoonJuiceVenus=400`.
- Buildings are bought with `Events.Buy:FireServer(name, "Building", cost, planet)` — spending
  per-planet currencies (MoonJuice/Mars/Venus).
- **Pool refills follow the `Values.Fuel` cycle** (measured via a 25-min watch, 2026-10-07):
  Fuel regenerates `0 → 100` over ~20 min (tanks refuel the Nuke, see below), then drops to 0 in
  a single tick together with a global-pool collapse (`MoonJuice 545 → 3` — the Nuke firing;
  the Io arrival earlier showed the same `Fuel 75 → -inf → 0` signature). **All pools refill while
  Fuel climbs** (`MoonJuiceMars 0 → 349`, `MoonJuiceVenus 0 → ~400` in one cycle); during Fuel=0
  stretches pools sit still or creep (global ~0.2/s, Venus ~1/s after recovery). So a pool stuck
  at 0 is *phase-gated*, not dead — watch Fuel before concluding a planet is unbuyable.
- **A round restart wipes everything economy-side** (measured on the restart the watcher caught,
  2026-10-07): every `Values.*` pool → 0, `Fuel` → 0, and all bought buildings gone (SpaceStation,
  VenusCity, pumps, colonies) — only `City, SpawnLocation, FriendIndustries` stood afterwards.
  Round length is **not** constant: restarts were measured at `ClientSeconds` 2854, 3527 and 2211.
- Fuel was seen climbing past the old 100 mark (`110, 130, 150` after that restart) — treat 100 as
  "Nuke ready", not a hard cap.

## Weapons (Rail Gun / RocketLauncher)

Both ship in the Backpack as Tools; the client halves are tiny:

- **Rail Gun**: `LocalScript` connects `mouse.Button1Down` while equipped and fires
  `tool.Click:FireServer(mouse.Hit.p)` — the remote takes an **explicit world position** — then
  waits 5s *for the cursor icon only*. `Click` is a RemoteEvent child of the tool; the only tool
  attribute is `PlaySound=<assetid>`.
- **RocketLauncher**: client side is just `MouseLoc.OnClientInvoke = Mouse.Hit.p` (the server
  **pulls** the aim when it fires) plus `MouseIcon` cosmetic; `Tool.Enabled` mirrors a server
  cooldown. Tool children include server `Script`s (`Server`, `Rocket`) — server RunContext, so the
  decompiler refuses them ("Expected a Script with RunContext set to Client") and so does
  `getscriptbytecode`. Firing trigger = `tool:Activate()`.
- **RESOLVED 2026-10-07: the rail does zero damage to monsters, every way.** A 480s job caught 10
  rigs and fired 4 variants per rig (`remote-only`, `tool:Activate()+remote`,
  `activate+remote-delayed`, `activate+exactPivot`) with `mouse.Target` sometimes sitting exactly
  on the rig's own mesh (`Retopo_Cube.004`) — all 40 shots: 700>700. Same for markers with every
  aim point tried. There is no missing activation ingredient; the server simply does not award
  monster damage to normal (uninfected) accounts from `Click`.
- **HexSpitter ("Moon Gun") — full anatomy (bought 10 MoonJuice via
  `Events.Buy:FireServer("HexSpitter","Tool",10)`):** `Configuration` holds `Damage` (a
  `DoubleConstrainedValue`, current 15, min 7 max 17), `FireRate=0.06`, `Automatic=true`,
  `Range=100000`, `Accuracy=(0.5,0.5,0.5)` (client-side spread the fire loop multiplies in),
  `Ammo.Magazines` (10,000,000, server replicates it back so client decrements don't stick).
  Fire protocol lives in its `LocalScript`: input (`UserInputService.InputBegan` MouseButton1/
  Touch/ButtonR2, **requires `gameProcessedEvent == false`**) → `StartFiring` loop →
  `ServerControl:InvokeServer("Fire", true)` then per bullet `CastLaser` + `RayHit` with a
  client raycast payload `{Hit, Position, Target, Humanoid, Character}` (plus server pulls
  `ClientControl:InvokeClient("MousePosition")`). **Measured verdict: even with camera-locked
  aim where `mouse.Target` is the rig's mesh and `GetTargetPosition()` lands 2 studs from the
  pivot, 7–8s of loop fire does 700→700 — the server awards HexSpitter no monster damage either.**
  Its range (100k) and 0.06 fire rate suggest it is a spaceship/space weapon, not a monster one.
- Shipped gun mods (`combat.luau`) are client-rate only: `GunRapid` refires at `gunDelay` and
  clears the rocket's client `Enabled` gate; `GunVolley` sprays the rail remote at every monster
  in `gunRange`. Server damage math is not client-writable.

### Firing a tool's own LocalScript loop without input (executor tricks, all measured)

- `getsenv(tool.LocalScript)` exposes the script env: `StartFiring`, `StopFiring`, `MouseDown`,
  `ToolEquipped`, `Reloading`, `GetTargetPosition` are **globals in that table**. Firing =
  `se.MouseDown = true; task.spawn(se.StartFiring)`; stop = `se.MouseDown = false`. This bypasses
  the input layer entirely (background-safe, no focus needed) and was verified live: `Tool.Enabled`
  flips false, the loop completes server round-trips (~32 invokes/s: Fire+CastLaser+RayHit per
  shot, no server throttle observed).
- **VirtualInputManager exists** (`game:GetService("VirtualInputManager")`) and
  `SendMouseButtonEvent(960,540,0,true,game,0)` does reach `UserInputService.InputBegan` — but
  always with `gameProcessedEvent=true`, so the HexSpitter handler (`if not a2`) skips it. VIM
  touch/gamepad variants delivered nothing. Real's `send-input` (OS-level) works only while the
  Roblox window is focused (Win32 `SetForegroundWindow` on the process handles it) and did not
  reach `InputBegan` at all in the unfocused state. `firesignal` is a no-op in Real (per
  `click-button` docs), so GUI-signal clicks do nothing.
- **`ServerControl:InvokeServer` can wedge**: after a `tool:Activate()` + stray invokes, every
  later invoke on that RemoteFunction hung forever (even `CastLaser`), while RemoteEvents kept
  working — recover by **rejoining** (launch `%LOCALAPPDATA%\Roblox\Versions\version-02c37bc51a384b8f\RobloxPlayerBeta.exe "roblox://experiences/start?placeId=133579701570149"`; the bare
  `roblox://` protocol Start-Process fails in a non-interactive shell, pass it as the exe argument).
  From a clean client the legit loop never wedges.
- `record-session` does **not** see RemoteFunction `InvokeServer` calls (only RemoteEvents), and
  `spy-closure` on env functions gives working **call counters** but an empty log for these
  (entries/logged stay 0); its `stop` sometimes refuses to unhook ("still reports as hooked").
  Counters still prove whether a loop ran.

## Monsters & combat (measured 2026-10-07)

Two different "monsters" exist and they behave completely differently:

- **Markers** (`Workspace.Unanchored.SmallMoonMonsters/MoonMonsters`, name `Moonfected`, attr
  `LastHitPlayer=...`): Humanoid(100 or 70 hp) + `Script:AI` + `Script:HitDetector` + Animations,
  **zero BaseParts on any client**. Because they have no parts: `mouse.Target` can never be them,
  `GetBoundingBox` is 0×0×0, sword `Touched` cannot reach them, and every damage form tested did
  nothing - rail `Click:FireServer` with mouse.Hit/pivot/pivot+3/eye-projection/own-feet (camera
  locked on pivot, 18 studs), 6 sword swings, and `Events.MoonMonster.Attack:FireServer(dir)`
  (which is gated: silent reject unless the shooter's character has attr `MoonMonsterPlayer`).
  Treat them as logic/quest counters, not damageable bodies.
- **Rigs** (transient, `Workspace.Unanchored.MoonMonsters.MoonMonster`, hp **700**, parts=3,
  mesh `Retopo_Cube.004`, `AnimSaves`, animated client-side by `MoonMonsterClientAnimator` which
  requires name `MoonMonster`/`MoonMonsterTestAI` or attrs `MoonMonsterRig`/`MoonMonsterPlayer`):
  spawn roughly once a minute near (700, 4400, -1600) - often high in the air and descending -
  and vanish again within ~a minute. One volley in a 5-shot battery showed 700→0 on the first
  shot, but a LATER battery with `mouse.Target` sitting exactly on the rig's own mesh and the
  remote fired did zero damage, so that kill was almost certainly another player (the spawn area
  is busy) or a missing ingredient.
- **RESOLVED 2026-10-07 (later battery): `tool:Activate() + Click:FireServer` is NOT the missing
  ingredient.** 10 rigs × 4 fire variants (incl. real activation, delayed activation, exact-pivot
  aim, `mouse.Target` on the mesh) = zero damage across the board.
- **Complete normal-player damage battery = ZERO everywhere** (all measured 2026-10-07): rail all
  variants; HexSpitter legit loop fire with camera-locked verified aim (rigs, `Tool.Enabled=false`
  proves the loop ran); HexSpitter synthetic `RayHit` payloads with `Hit`/`Humanoid`/`Character`
  filled and aim points on the pivot and 3 studs above the floor (markers — invokes return `ok`,
  no error, no damage); Super Sword swings at 8–11 studs (markers), 3 studs (550hp rig-puppet),
  and **1.5 studs from a true zero-part marker (10× swings, 100→100)**; `Events.MoonMonster.Attack`
  (server-gated on attr `MoonMonsterPlayer`). HP attrition observed on rigs (700→550, 700→500)
  comes from other players/events — the spawn area is busy — never from our tested paths. Either
  the infected-attack path or something outside every client-facing surface awards damage.
- **Two marker families confirmed by anatomy:**
  `Unanchored.SmallMoonMonsters/Moonfected` (100 or 70 hp) = `Humanoid` + `Script:AI` +
  `Script:HitDetector` + **zero BaseParts** (server scripts, unreadable client-side);
  `Unanchored.MoonMonsters/MoonMonster` (500–700 hp) = an animated puppet with `HumanoidRootPart`
  + mesh `Retopo_Cube.004` + `InitialPoses` + `AnimSaves` (hp varies per spawn — 550 and 500 seen
  fresh-ish, so attrition or spawn variance, not only "700"). `nearestMonster` returns either
  family; discriminate by checking `FindFirstChildWhichIsA("BasePart").Name`.
- Monster-player combat (infection gamepass 1548419084 → `Events.Infected:FireServer(btn)`):
  while your character has attr `MoonMonsterPlayer`, `MoonMonsterPlayerControls` fires
  `Events.MoonMonster.Attack:FireServer(camera.LookVector)` on click/F/R2 with a 0.65s client
  gate - direction-based, no parts needed. **This is the only damage path anyone has been
  observed to make stick on markers (`LastHitPlayer` attr).**
- Gun client facts: rail = `tool.Click:FireServer(mouse.Hit.p)` (5s wait is icon-only), rocket =
  server pulls `MouseLoc` + `Tool.Enabled` gate. `Events.GetMouse` is a server→client ask that
  `PickaxeController` answers with `FireServer(LocalPlayer, mouse.Target)` - the server periodically
  reads our mouse target, which is why camera aim matters for mining.
- **Tool shop facts**: FriendIndustries buttons are plain `GuiButton`s handled client-side in
  `EarthController`/`MarsController`/`VenusController` (`MouseButton1Click` → `Events.Buy`).
  "Moon Gun" → `HexSpitter` (10), "Moon Saber" → `PurpleSaber` (20); other buttons buy buildings
  (costs read from their labels: MoonPumper 200, SpaceStation 500, Nuke 200, ForceField 500,
  RecoverEarth 1200, ColossalEngines 2000, …). The server **refuses a re-buy while the ownership
  flag persists across rejoin**, but the physical tool does not always respawn with you; delivery
  after an accepted buy can take 5+ seconds (poll, don't assume instant).

## Converters / anti-matter economy

Buildings are **phase-gated and shared**: they exist in `workspace` only while the phase allows and
somebody buys them (observed `MoonJuicePumpJack` + `MoonPumper` present early, gone later the same
session). `util.converters()` reports what is standing right now: names containing `Pump` at
workspace root + any `Planets.<p>.SpaceStation.ConverterMachine` (labelled `AntiMatter@<planet>`).

- `MoonJuicePumpJack` SurfaceGui label: **"MoonJuice Tanks Will Spawn Every 1 Minute"** — pump
  buildings spawn *tanks* (the juice pickups the ESP already highlights).
- **SpaceStation** (`Planet1.SpaceStation`, bought for 500 MoonJuice) hosts the anti-matter machine:
  `ConverterMachine.PartProximity` ProximityPrompt `ActionText="Insert Moonjuice"`, **HoldDuration
  2.0s**, at `(1825, 4484, -2215)`. Labels: "INSERT ION MOONJUICE ABOVE",
  "1 ION MOONJUICE = 1 ANTI MATTER MOONJUICE", "ANTI MOON JUICE IS WORTH …". So the chain is
  juice → (ion source, unresolved) → insert prompt → Anti Matter juice → sell (our `sellAll`
  already sells any `Credits`-valued tool generically).
- Ion source **RESOLVED and both buildings PAID for** (2026-10-07): the buys are
  `Events.Buy("IonMoonPumper","Building",800,"Venus")` (button `IonizedMoonJuicePumpJack`) and
  `Events.Buy("IonMoonJuicePumpJack","Building",850,"Venus")` (button `MercIonMoonPumpJack`), both
  in `VenusController`, both gated on `Values.MoonJuiceVenus >= cost` (staged-buy jobs observed
  `800->9` and `864->26` - PAID). **The ion juice itself does not come from the buildings**: it
  comes from mining **Planet5 = Mercury** rocks, which drop `Ionized MoonJuice` stacks (`Credits=20`).
  Planet5 is the ion field (ion-only drops, despite the buys being gated on the *Venus* pool -
  the pump button is even named `MercIonMoonPumpJack`); Earth (Planet1) drops plain
  juice. `VenusCity` itself is a streamed top-level model (`StreamingEnabled=true`) - when it is
  out of range `travel.to("Venus City")` falls back to another hub destination, and the partless
  ion tanks' `GetPivot` returns a meaningless spot (empty void, nothing loads there).
- EarthController buy buttons (FriendIndustries, MoonJuice): `Nuke` 200, `ANuke` 300 (button
  misleadingly named `AntiMatter`), `PluckRadar` 400, `VenusColony` 300, `RecoverEarth` 1200,
  `SpaceStation` 500, plus `ForceField`.
- The insert probe is now **verified end to end**: `prompt:InputHoldBegin()` → `task.wait(2.6)` →
  `InputHoldEnd()` at 4 studs fires `prompt.Triggered` on the client (so the server got it), and
  with 5 **plain** stacks aboard nothing was consumed - plain juice is definitively rejected,
  ion-only as the labels say. The auto-farm now runs this chain (`farm.convertIon`, GUI toggle
  `AutoConvert`, default on): detect ion stacks by name → hold-aware teleport to the machine →
  one verified hold per stack (aborts if a hold consumes nothing) → `sellAll` picks up the
  anti-matter tools (they carry `Credits`).
- **Full converter chain verified end to end (2026-10-07, capped run on Planet5):** farm mined
  `Ionized MoonJuice` → at threshold `convertIon` teleported to the SpaceStation machine, held the
  prompt per stack, sold the anti-matter: **4 stacks = +296 credits (74/stack)** vs 20/stack raw
  ion vs 15/stack plain Moon juice. Economics per swing: Moon plain 15/12 ≈ 1.25, Venus ion
  74/30 ≈ **2.5 → ion mining is ~2× the Moon's income per swing** (ion drops ~1 per 30 swings
  vs 12). Mercury (Planet5) is the better farm target whenever AutoConvert is on.
- **Yield-aware auto-fix (2026-10-07):** the flat `stallSwings=10` false-fired ~10 times per
  150 swings on Venus's slow ion vein. The chain threshold now scales to
  `max(stallSwings, 1.5 × observed swings-per-juice)` once the run has produced juice, keeping
  the flat floor while `gained==0` (the stuck-pickaxe signature). Measured after the change:
  **3 fixes / 111 swings** (was 10 / 150), zero false fixes after the first juice, run ~26%
  faster.
- **Mars (Planet4) experiment (2026-10-07):** rocks are `MarsRocks`, they drop **plain
  `MoonJuice=15`** (no ion), yield ~17 swings/stack → **~0.88 credits/swing - worse than the
  Moon (12 swings, 1.25) and far worse than Venus ion (30 swings, 2.5)**. Selling Mars-mined
  juice fills **no pool** (mars=0 global=0 after 4 verified sells). `MoonJuiceMars` looked dead
  (0 for 30+ min) but **refills with the Fuel cycle** (Currencies section) — it hit 349 in one
  Fuel climb. MarsController buy map (exact args, all `("Mars")` 4th arg): `PlutoColony` 300 /
  `MarsDomes` 400 (gate: `workspace.MarsCity` exists, no `MarsCity.MarsDomes`) / `Phobos` 500
  (gate: no `workspace.ProjectPhobos`) / `ExpandedPlutoColony` 500 / `MainColony` 700 /
  `TerraformPluto` 800 / `Terraform` 1000 (gate: `Planet4…Terraformed.Transparency ~= 0`, i.e.
  buyable exactly once) — the Mars menu also sells `HexSpitter` for 10 and `PurpleSaber` for 20
  from this pool. Farm economics ranking: **Venus ion (2.5/swing, needs AutoConvert) > Moon
  (1.25) > Mars (0.88)**.
- **Sell-remote semantics (measured 2026-10-07, job "sell-order"):**
  `Events.SellMoonjuice:FireServer(count, allFlag)`
  - `(n, true)` = sell everything (this is the game's own "sell everything" button,
    `MainController` line 157 fires `(#juice, true)` after previewing the total);
  - `(n, false)` = sell the **first `n` tools in Backpack insertion order - OLDEST first** (the
    game's own "sell N" dialog previews exactly `first n` credits, `MainController` line 212).
    Measured: aboard `[MoonJuice, Ionized MoonJuice]`, `(1, false)` sold the **MoonJuice** (+15)
    and left the ion. `count > available` is rejected outright: `(5, false)` with 1 stack aboard
    sold **nothing** (+0).
  - Consequence: a count-sell can only reach anti-matter if the anti tools **lead** the stack;
    older plain/ion stacks shield everything behind them.
- **Sell policy (shipped in `farm.luau`, user's rule):**
  plain/ion juice is never sold while conversion machines are absent - it is *held*;
  at the convert threshold the farm runs plain→ion→anti through whatever machines exist
  (`ionizePlain` + `convertIon`, both prompt-gated); anti-matter sells the moment it **leads**
  the stack (`util.sellableAnti()` = leading run, safe under oldest-first semantics, fired via
  `(n, false)`); a hold below `config.farm.holdCap` (16) keeps mining and pauses at the cap so
  the backpack can never clog; and when the round is about to end **everything** is dumped via
  `sellAll()` regardless of tier. The farm tab shows the tier/machine/round state on the
  "Sell policy" card.
- **Round-end dump signals (measured on TWO restarts, 2026-10-07):** the round hard-restarts with
  no warning UI, the clock length varies wildly (`2854` / `3527` / `2211` - `config.farm.roundLength`
  stays 0), and **the final story chain differs per round**:
  - round A: `HUMANITY IS EXTINCT ... MARS IMPACT` (~50s out) → `THE DYSON SPHERE GOT DESTROYED!`
    (~20s) → `THE SUN IS MOVING! BUILD MERCURY COLONY ...` (~10s) → reset. `PlayerGui.Fim` was
    never caught enabling.
  - round B: `MAIN BUNKER DESTROYED` → `EARTH IS NOW A LAVA PLANET` → `JUPITER IS GOING TO
    COLLIDE ...` (~2 min out) → **`Fim.Enabled = true`** → reset (Fim visible for 10-41s). No
    Dyson/Sun messages at all - and Fim also flashed ON for ~10s at 29m mid-round, so Fim is
    late-but-not-unique; an early dump on the flash costs only conversion value, a missed dump
    costs the whole stack, so Fim is accepted as an immediate trigger.
  - `util.roundEndSoon()` therefore layers: Text markers (event-driven, covers round-A ends) +
    `Fim.Enabled` (checked every farm pass ~1-2s, far finer than any watcher, covers the rest) +
    the disabled clock threshold. It self-clears when `ClientSeconds` rewinds (new round).
- **MoonJuiceTank pickups** (`Workspace.Unanchored`, attr `MoonJuiceTank=true`, ~35 lying around,
  kids = LocalScript + Beam + Attachment + `Credits` NumberValue): their LocalScript equips a
  Beam to `Workspace.City.Nuke.Frame.Refuel.Attachment` - tanks fuel the Nuke. **They carry NO
  Handle**, so vanilla touch-pickup is structurally impossible; standing on one does nothing,
  no ProximityPrompt exists even at close range, and no pickup remote exists in `Events`.
  A client-side `Parent` change would only be a local illusion (the sell remote counts the
  server's backpack). Working conclusion: tanks are consumed by the Nuke/server, not
  player-collectible income. `Values.Fuel` read 65 and did not move.
- `ReplicatedStorage.Values` holds the per-planet pools and story flags in one place:
  `MoonJuice` (global), `MoonJuiceMars`, `MoonJuiceVenus`, `Laser`/`Laser2`/`Laser3` (0),
  `Sun` (false), `BossCooldown` (0), `Fuel` (65) - **ion buildings gate on `MoonJuiceVenus`,
  not the global pool** (buying against the global pool gets refused silently).
- **Phase / threat system (decoded 2026-10-07):** `workspace.PlanetTracker` holds one entry per
  story threat - live children: `Io, Saturn, Jupiter, Jupiter2, Neptune, EnragedNeptune, Mars,
  Sun, BlackHole, Planet9`. Each carries attributes **`WarpActive` (bool), `WarpTime` (seconds),
  `WarpStart` (server epoch)**; arrival ETA = `WarpStart + WarpTime - GetServerTimeNow()`.
  **Warps chain**: observed live - while Io was still approaching (700s cycle), `Jupiter2`
  flipped `false/nil/nil -> true/100/<epoch>` (a fresh 100s countdown). The Io arrival itself:
  players gather at the hub (14/21 within 300 studs), `Shockwave2` impact VFX, `Values.Fuel`
  drained `75 -> -inf -> 0`, and the event moved our character 16k studs. **The farm now
  protects against this** (external-move detection, see farm section). `Rail`/`Effect`
  top-level VFX flash in/out continuously at the hub (players rail-gunning + event effects).
  `PlayerGui.ProgressBar.ProgressBarController` renders the nearest active one (ETA + progress
  bar, "No incoming planets" when idle, "Too Far From The Tracker!" beyond range of the
  physical tracker). Observed live: `Io WarpActive=true, WarpTime=700` (11.7 min cycle, ~4.5
  min remaining), transparency 0 = visible; all others inactive with `Transparency=1`. The
  `WarpActive=false + WarpTime set` state on Saturn looks like a finished/pending warp. The
  shop label "Time Left Until Jupiter Eats The Earth" is the same countdown UI. Warping planets
  = how content "appears as phases advance" (the farm's planetCooldown comment).


## Quests & playtime

- Knit `QuestService`: `GetQuests()` may return data *or* a promise — always handle both.
  `ClaimQuest("Daily"|"Weekly", id)` is safe to call.
- Playtime rewards: listen for `Events.PlaytimeReward` with `Action == "Ready"`, then
  `Events.PlaytimeClaim:FireServer()` — 1800s cycle.
- `ReplicatedStorage.RewardsConfig` (requireable module) = the playtime chest table: chest 1 pays
  Credits 30–200 (weight 50), chest 2 pays MoonJuice tool stacks 3–5 (weight 30), chest 3 pays
  OilTank tool 1–2 (weight 20) — whatever arrives, the rewards module just claims it.
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

**Moon boss / monster player roles (decoded 2026-10-07, shipped as the `MoonAttack` toggle):** the
server assigns a role by setting character attributes — `MoonBossPlayer` or `MoonMonsterPlayer`.
Both `MoonBossPlayerControls` and `MoonMonsterPlayerControls` are click/F/R2 handlers that:
1. gate on their attribute (boss wins: monster control also requires `MoonBossPlayer ~= true`),
2. enforce a client cooldown — **boss 0.35s, monster 0.65s**,
3. set a pulse attribute on the character — `MoonBossAttackPulse` / `MoonMonsterAttackPulse`,
   stamped with `os.clock()`; the matching `*ClientAnimator` scripts read it to play the swing,
4. fire `Events.<Role>.Attack:FireServer(cameraLookVector)` (fallback: HRP look vector).

Paralyz `MoonAttack` (default on) replays that exact protocol from a background loop: same remotes,
payload, cooldowns and pulse stamps, and it *defers* when a fresh vanilla pulse arrives so a user
clicking manually keeps exactly the vanilla rate. No input synthesis, no camera movement.

## Session mechanics (client hub)

- **The stance hold wins every fight it is not told about.** `farm.luau` pins `root.CFrame` per
  RenderStepped while running; a teleport that does not update `holdCF` is overwritten on the very
  next frame (symptom: "teleport does nothing until I spam it"). Every teleport now goes through
  `util.teleported(cf)` → `util.onTeleport` listener → the farm moves its hold onto the new spot;
  `rotatePlanet` uses the same path (`rotateTeleport`), which also unbinds the aim for the trip.
- **Camera aim is continuous while farming.** `util.aimAt(target, standoff, holdOnFail=true)` keeps
  the bind across batches and never restores mid-run (the lock→restore→lock churn); the view is
  handed back exactly once at `farm.stop`. Rotation unbinds (no restore) so travel is view-neutral.
- **Rotation probes, never guesses**: teleport → `settleRocks(loadWait=15s)` → only then judge;
  planets within `streamRadius` of where we stand are cooled as *proven* empty (the spawn
  neighbourhood has no rocks at all); cooldowns 45s, full-sweep pause 30s; every lifecycle message
  is `force`-notified and the stat line carries a live phase (`loading Planet3`, `mining`, …).
- **Travel lands after loading**: after `settleRocks` it re-fetches the root (the wait can outlive
  the character), re-resolves or falls back to the remembered position, teleports, verifies arrival
  within 400 studs, retries ×4. Never again "it loads but leaves me standing here".
- `dropToSurface` near-ray (from `pos+600`) only ever lands in `pos+600..pos-900`; planet centres
  are *inside* their own mesh where a ray cannot hit backfaces, so a miss retries from `+5000`
  before falling back to `pos+10`.
- Hide mining is the **default** (`state.set("HideMining", true)` at boot + a 1.5s re-assert,
  because Rayfield's autoLoad restore lands after the menu and used to win the race).
- All 6 planets sit in `workspace.Planets` even from spawn, but their **rocks** only exist within
  streaming range of a player — scanning rock counts from afar tells you nothing about emptiness.
  Planet2/Planet5 coordinates also differ between sessions: never hardcode planet positions.
- **Rayfield Gen2 `Statistic:Set()` only accepts numbers** (`assert(typeof(k)=='number')`) — a
  string stat throws every update; with the old shared pcall one throw silently froze *every*
  later stat at its initial value (Farm showed "idle", Quests "checking…" forever). Words go on
  `tab:CreateText({ name, text })` cards via the `ui.text` wrapper (`Text:Set` takes any value);
  `ui.stat` is numbers-only. Each updater now has its own pcall and each unique error is logged
  exactly once (`[Paralyz] live stats - …`). The window lives at
  `CoreGui.RobloxGui.<guid>.Paralyz`, not under a "Rayfield" name — search by `Name == "Paralyz"`.

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
