--!strict
-- Paralyz / src/config.luau
-- Every tunable in one place. Modules read it; nothing in here reads anything else.

return {
	-- Where the loader fetches module sources from when it is not running as a bundle.
	remoteBase = "https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/src/",

	farm = {
		-- Seconds between mine swings. The server answers each swing, so this is also
		-- how fast a rock can actually be consumed.
		swingDelay = 0.35,
		-- Camera stand-off distance from the rock while aiming.
		aimDistance = 35,
		-- Convert threshold: once this many stacks are aboard, the farm
		-- walks them through the ionizer/converter chain. Antimatter is
		-- sold whenever it leads the stack (see util.sellableAnti), so
		-- this no longer gates the sell itself.
		sellAt = 10,
		-- Hold ceiling: with no conversion machines available the farm
		-- keeps stacking plain/ion juice (it is all dumped at round end),
		-- but pauses mining at this many stacks so the backpack can never
		-- clog and dead swings cannot pile up.
		holdCap = 16,
		-- Round length in story seconds (Values.ClientSeconds), measured
		-- from the round-end watcher. 0 = still unknown, which disables
		-- the clock-based dump; the Fim "The End" screen always dumps.
		roundLength = 0,
		-- Dump everything when the clock is within this many seconds of
		-- roundLength (the user's ~30s rule).
		endDumpWindow = 30,
		-- Rocks stream by proximity and in waves: when the folders are empty,
		-- wait this long and look again.
		noRockDelay = 4,
		-- Grace after equipping a tool before the first swing.
		equipDelay = 0.25,

		-- Stance geometry. Measured: the server drops a swing made from more
		-- than ~30 studs of the rock's centre (30 accepted, 37 rejected) and
		-- never rolls the character back, so every stance stays inside
		-- maxRange. The "Hide mining" menu toggle switches from standing on
		-- top of the rock to standing inside its mesh, invisible to others.
		maxRange = 26,
		hideOffset = 4,

		-- Auto-fix chain, in order, when swings go dead: 1) re-equip the
		-- pickaxe, 2) switch to another rock, 3) settle-wait. Any juice
		-- resets the chain. stallSwings is the floor: a run producing juice
		-- scales the threshold to 1.5x the observed swings-per-juice, so a
		-- healthy slow vein (ion on Venus, ~1 per 30 swings) does not read
		-- as a dead tool, while a run with no juice at all - the stuck
		-- pickaxe signature - still fixes at the flat floor.
		stallSwings = 10,
		rockSwitchDelay = 20,
		-- An outside move (event gathering players, cutscene, server warp)
		-- released the stance pin: pause this long before re-planning so
		-- the farm does not teleport out of a story event mid-flight.
		externalPause = 20,

		-- No rocks anywhere near the character: after this many empty waits
		-- the farm probes another planet.
		planetWaits = 3,
		-- Arriving somewhere: rocks stream in a few seconds after the
		-- character lands, so after a teleport the farm waits this long for
		-- the destination to load before deciding it is empty. Travel uses
		-- the same wait to confirm a load.
		loadWait = 15,
		-- How far from the character rocks still count as "here". Rocks from
		-- the previous planet linger while streaming out, and swinging at
		-- them is pointless anyway (the server range rule), so every
		-- proximity question filters by this.
		streamRadius = 2500,
		-- A planet that loaded empty goes on "not right now" for this long.
		-- Never forever: content appears later as phases advance.
		planetCooldown = 45,
		-- Rotation preference: Planet5 drops ion juice, worth ~2x plain
		-- Moon juice once converted (74 vs 15 per stack). rotatePlanet
		-- ranks preferred planets first within the same has-rocks tier,
		-- and probes them first when every planet looks empty. Data, not
		-- logic: add a name here to bias the farm toward it.
		preferPlanets = { Planet5 = true },
		-- Every planet in the world probed and found empty: pause this long
		-- before starting another sweep instead of bouncing map-edge to
		-- map-edge.
		emptyPause = 30,
	},

	esp = {
		players = true,
		monsters = true,
		juice = true,
		rocks = false,
		labels = true, -- the single nearest-target name label
		throughWalls = true, -- Highlight depth mode: AlwaysOnTop vs Occluded
		maxDistance = 3000,
		refresh = 0.25, -- seconds between scans; Highlights follow targets for free
		fill = 0.72, -- Highlight fill transparency (1 = invisible)
		outline = 0.0, -- Highlight outline transparency
		-- Per-layer caps: the pool can never grow past the sum of these.
		limits = { players = 16, monsters = 16, juice = 20, rocks = 30 },
		colors = {
			player = Color3.fromRGB(120, 170, 255),
			monster = Color3.fromRGB(255, 96, 96),
			juice = Color3.fromRGB(255, 214, 96),
			rock = Color3.fromRGB(210, 210, 210),
		},
	},

	travel = {
		-- Fly speed, studs per second is this times 60: 8 -> ~480 studs/s,
		-- which crosses the 10k-stud gaps between planets in a usable time.
		flySpeed = 8,
		-- Hubs are folders of structures that stream with distance: from the
		-- far side of the world their resolve() is nil even though they
		-- exist (measured: Bunker folder present, zero BaseParts loaded at
		-- 11k studs). These are their measured spawn-area coordinates, used
		-- only as "go stand here until it loads" anchors - travel re-resolves
		-- and re-lands after the wait, so stale coords never become landings.
		hubFallbacks = {
			Bunker = Vector3.new(725, 3033, -1332),
			City = Vector3.new(654, 3063, -1230),
		},
	},

	rewards = {
		-- How often the daily/weekly quest list is polled for claims.
		-- Playtime chests are push (event listener), so this only covers
		-- quests -45s keeps Knit calls negligible.
		pollDelay = 45,
		-- A quest pass that takes longer than this is treated as a wedged
		-- RemoteFunction and abandoned (one zombie thread, never more).
		passTimeout = 15,
	},

	perf = {
		fps = 20, -- frame cap while no-render is on
		restoreFps = 0, -- 0 = Roblox default when no-render is off
	},
}
