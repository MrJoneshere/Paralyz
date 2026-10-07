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
		-- Sell once this many MoonJuice stacks are sitting in the Backpack.
		sellAt = 10,
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

		-- Auto-fix chain, in order, after stallSwings swings with no juice:
		-- 1) re-equip the pickaxe, 2) switch to another rock, 3) settle-wait.
		-- Any juice resets the chain.
		stallSwings = 10,
		rockSwitchDelay = 20,

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

	combat = {
		-- Keep-distance when Avoid is on: monsters inside this radius trigger a step back.
		avoidRadius = 14,
		-- Gun mods: refire cadence while a mod is armed, and the range the
		-- volley sprays monsters at. Client-side only - server rate limits
		-- and damage math are not writable from here.
		gunDelay = 0.4,
		gunRange = 800,
	},

	travel = {
		-- Fly speed, studs per second is this times 60: 8 -> ~480 studs/s,
		-- which crosses the 10k-stud gaps between planets in a usable time.
		flySpeed = 8,
	},

	perf = {
		fps = 20, -- frame cap while no-render is on
		restoreFps = 0, -- 0 = Roblox default when no-render is off
	},
}
