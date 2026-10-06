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
		-- Rocks spawn in waves: when the folders are empty, wait this long and look again.
		noRockDelay = 4,
		-- Grace after equipping a tool before the first swing.
		equipDelay = 0.25,
		-- How far past a rock's edge to stand while swinging it.
		edgeMargin = 14,
		-- Hard stop for test runs. The GUI never passes this; only tests do.
		testCycles = 5,
	},

	esp = {
		players = true,
		monsters = true,
		juice = true,
		rocks = false,
		maxDistance = 3000,
		refresh = 0.10, -- seconds between scans of the world (labels redraw every frame)
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
