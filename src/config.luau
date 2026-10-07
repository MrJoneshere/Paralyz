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

		-- No rocks anywhere in the world: after this many empty waits the farm
		-- teleports to another planet and lets the rocks stream in there.
		planetWaits = 3,
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
		-- Seconds between swings of the auto-attack.
		swingDelay = 0.45,
		-- How close a monster has to be before we swing at it.
		swingRange = 18,
		-- Keep-distance when Avoid is on: monsters inside this radius trigger a step back.
		avoidRadius = 14,
	},

	travel = {
		-- Fly speed, studs per frame multiplier of the camera direction.
		flySpeed = 2.5,
	},

	perf = {
		fps = 20, -- frame cap while no-render is on
		restoreFps = 0, -- 0 = Roblox default when no-render is off
	},
}
