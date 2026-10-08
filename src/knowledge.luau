--!strict
-- Paralyz / src/knowledge.luau
-- The Assistant tab's knowledge base: wiki facts + live measurements,
-- distilled from the local KNOWLEDGE.md (the source stays off-repo).
--
-- Structure: flat entry list, each entry self-contained so any single one
-- can be shown in the answer card. Search is a scored substring match over
-- title/keys/body - no dependencies, works offline inside the bundle.

local entries = {
	----------------------------------------------------------- basics
	{
		id = "juice-variants",
		cat = "Basics",
		title = "Juice: the 5 variants",
		keys = "moon juice variants plain ionized antimatter methanized omega",
		body = "Moon Juice is the main currency (Credits is the other). Plain: Moon, Mars, Venus, "
			.. "Charon, Phobos, Deimos, Ganymede rocks. Ionized: Mercury rocks right away, or ionize "
			.. "plain at the Pluto Colony. Antimatter: Space Station converter. Methanized: Titan. "
			.. "Omega: Omega Smelter (Pluto from Kuiper, Earth from Andromeda).",
	},
	{
		id = "juice-worth",
		cat = "Basics",
		title = "Juice: what a mined item is worth",
		keys = "sell value credits fuel worth 20",
		body = "A mined juice item converts to 20L / 10 Fuel / 5 Credits at shops. Measured live "
			.. "2026-10-08: selling the TOOL pays 20 cr for Ionized and 34 cr for Anti Matter. "
			.. "Wiki exchange: 1 Moon Juice -> 5 Credits at the Earth shop.",
	},
	{
		id = "juice-chain",
		cat = "Basics",
		title = "Juice: conversion chain",
		keys = "convert chain ionizer anti matter plain to ion 1:1 machine",
		body = "Plain -> ionized at the Pluto Colony ionizer (1:1, comes with Pluto Colony 300). "
			.. "Ionized -> antimatter at the Space Station converter (500, global pool). Dec 2025: "
			.. "converters no longer require holding an item in - a 2s proximity hold still works "
			.. "(hub measured). Antimatter pays best: 34 cr per stack.",
	},
	{
		id = "juice-passive",
		cat = "Basics",
		title = "Juice: passive producers",
		keys = "pumper pumpjack passive oil tank income per second",
		body = "Buy once per round, they run forever: Moon Juice Pumper 200L (Earth, 2L/s), "
			.. "Pumpjack 375L (1 tank/20-20-20 per min), Ionized Pumper 800L (Venus, 4L/s Venus, "
			.. "2L/s Earth, 1L/s Mars), Mercury Pumpjack 850L (ion tank per min), Omega Pumper 300L. "
			.. "Round restart wipes buildings - pools reset and you re-buy next round.",
	},
	{
		id = "currencies",
		cat = "Basics",
		title = "Currencies & exchange",
		keys = "currency exchange credits moon juice 5 shop",
		body = "Two currencies: Moon Juice and Credits. Exchange: 1 Moon Juice -> 5 Credits at the "
			.. "Earth shop (wiki). Mined juice TOOLS sell for more (Ionized 20 cr, Anti 34 cr "
			.. "measured). Credits persist across round restarts; the carried juice stack does not.",
	},

	----------------------------------------------------------- prices
	{
		id = "shop-earth",
		cat = "Prices",
		title = "Prices: Earth shop",
		keys = "earth shop prices moon gun space station nuke rebuild city",
		body = "Moon Gun 10, Moon Saber 20, Umbra Zone 100, Pumper 200, Demolish Debris 250, "
			.. "Pumpjack 375, Mars Colony 350, Item's Shop 450, Venus Colony 300, Space Station 500, "
			.. "Nuclear Plants 400, Rebuild City 1000, Nuke 200, Anti Matter Nuke 300, Pluck Radar 400, "
			.. "Forcefield 500, Recover Earth 1200, Omega Nuke/Pumper 300, Omega Smelter 350, "
			.. "Collosal Moondrive 2000, FRIEND Moon 1500, Pulsar Forcefield 500 / Laser 1000.",
	},
	{
		id = "shop-venus",
		cat = "Prices",
		title = "Prices: Venus shop",
		keys = "venus shop prices sky bases terraform dyson stargoose mercury colony",
		body = "Moon Gun 10, Moon Saber 20, Sky Bases 500 -> 300 (pre-Vercury), Ionized Pumper 800, "
			.. "Demolish Debris 500 (only when Mercury crashes into Venus), Surface Colony 500, "
			.. "Venusian City 1000, Stargoose Spawner 600, Forcefield 500, Terraform Venus 1500. "
			.. "After Mercury x Iapetus: Mercury Colony 300, Cool Mercury 700, Mercury Pumpjack 850, "
			.. "Terraform Mercury 1500. After Neptune: Dyson Sphere 600.",
	},
	{
		id = "shop-mars",
		cat = "Prices",
		title = "Prices: Mars shop",
		keys = "mars shop prices pluto colony phobos terraform domes",
		body = "Moon Gun 10, Moon Saber 20, Mars Domes 400, Main Colony 700, Terraform Mars 1000 "
			.. "(blocks Project Phobos), Pluto Colony 300 (brings the ionized converter). "
			.. "After Pluto colony: Expand Pluto Colony 500, Terraform Pluto 800 (Pluto never wakes). "
			.. "After Neptune: Project Phobos 500.",
	},
	{
		id = "shop-credits",
		cat = "Prices",
		title = "Prices: Credits shop",
		keys = "credits shop pickaxe sword railgun rocket vip spaceship moondrive",
		body = "Electric Sword 100, Iron Pickaxe 110, Super Sword 300, Metal Pickaxe 325, "
			.. "Railgun 500, Diamond Pickaxe 1000, Rocket Launcher 1500, VIP spaceship 6000, "
			.. "Moondrive 70 (reaches Kuiper, Proxima, Sirius). Gamepasses: Speed Coil 40 R$, "
			.. "Omega Pickaxe 19 R$ - both also obtainable in-game or via dailies.",
	},
	{
		id = "shop-pluto",
		cat = "Prices",
		title = "Prices: Pluto / Kuiper shop",
		keys = "pluto kuiper shop raygun laser omega smelter hyper station prices",
		body = "At the Pluto colony: Moon Gun 10, Moon Saber 20, Moonjuice Pumper Jack 200, "
			.. "Raygun 400 (GUI shows 350, actually 400), Laser 400 (destroy Neptune or WISE 0855), "
			.. "Omega Smelter 500, Omega Laser 500 (kill SIMP0136), Kuiper Space Station 1000 "
			.. "(kill PSO J318 + red giant Betelgeuse), Hyper Laser 600 (kill Betelgeuse).",
	},
	{
		id = "shop-veylora",
		cat = "Prices",
		title = "Prices: Veylora (Andromeda)",
		keys = "veylora andromeda shop dyson duo laser terraform power plants",
		body = "Power Plants 400, Terraform 1000, Dyson Sphere 1000 (starts the Sirius -> Earth "
			.. "event), Duo Laser 700 (destroys Sirius + Sirius Black Hole). Omega nukes live here: "
			.. "Omega Nuke and Omega Pumper 300, Omega Smelter 350.",
	},
	{
		id = "shop-no-shops",
		cat = "Prices",
		title = "Where Mercury & Pluto buy things",
		keys = "mercury pluto no shops venus mars buy upgrades",
		body = "Mercury and Pluto have NO shops of their own - every upgrade for them is bought "
			.. "from the Venus or Mars shop (wiki). Mercury Colony 300 and Terraform Mercury 1500 "
			.. "are on Venus; Pluto Colony 300 and Expand 500 are on Mars.",
	},

	----------------------------------------------------------- endings
	{
		id = "endings-solar-1",
		cat = "Endings",
		title = "Endings: Solar System (1/2)",
		keys = "ending solar survive moon impact nuke gas giants jupiter phobos mars time travel",
		body = "Survive The Moon Impact - Nuke The Moon - Gas Giants Arrival - Sun Wakes Up - "
			.. "Red Giant Sun - Neptune Arrival - Time Travel (forcefield around Ganymede + Time "
			.. "Machine within ~20 min: Theia hits Earth) - Jupiter Ending (Io mishandled: Jupiter "
			.. "eats Earth) - Nuke Jupiter's Moon - Project Phobos - Awakened Mars Ending - "
			.. "Mars Ending (colonize, Jupiter eats Earth).",
	},
	{
		id = "endings-solar-2",
		cat = "Endings",
		title = "Endings: Solar System (2/2)",
		keys = "ending anti matter nuke moons crash interstellar neptune planet x pluto black hole",
		body = "Antimatter Nuke (destroy Neptune) - The Moons Crash - Interstellar (Moon Drive -> "
			.. "Proxima or Sirius) - Enraged Neptune (let it eat Earth) - Neptune's Bodyguard "
			.. "(destroy Triton) - Earth Awakens - Planet X ending (let it eat Earth) - Planet X "
			.. "destroyed (Space Station laser, NOT the nuke) - Pluto Awakens - Black Hole wakes Up "
			.. "(Dyson spheres + Moondrives -> explode Sun -> laser Earth -> kill Black Hole).",
	},
	{
		id = "endings-proxima-kuiper",
		cat = "Endings",
		title = "Endings: Proxima & Kuiper",
		keys = "ending proxima centauri kuiper freedom colonized warrior savior liberator",
		body = "Proxima: Proxima System - Alpha Centauri Collision (upgrade B fully -> C crashes "
			.. "into B) - Alpha Centauri Dead. Kuiper: Freedom! - Colonized - Diplomatic / Enemies "
			.. "Forever - Neptune Ending 2 - Laser - Traitor - Wise 0855 - Liberator - United Kuiper "
			.. "Belt - Savior - Warrior (kill Wise as it eats Pluto - hardest) - SIMP0136 - PSO J318 "
			.. "- Good Kuiper - Betelgeuse / star exterminator.",
	},
	{
		id = "endings-sirius-gorlon",
		cat = "Endings",
		title = "Endings: Sirius & Gorlon",
		keys = "ending sirius gorlon andromeda meltdown freezedown core worker true pulsar",
		body = "Sirius: Artificial Swarm (both Dyson spheres) - Core Activation - Meltdown "
			.. "(black hole >100M C: do NOT unawaken) - Freezedown (<0 C: spam Super Freeze Beam) "
			.. "- Core Worker (1h) - Elite Core Worker (2h). Gorlon/Andromeda: Andromeda - Omega "
			.. "nuke - Lasered - Brown Dwarf - Lord of the Rings - True ending (Pulsar destroys "
			.. "Earth without Forcefield) - Pulsar - Second true (destroy Gorlon) - Sirius - Black "
			.. "Hole - Undefeatable.",
	},

	----------------------------------------------------------- awaken
	{
		id = "awaken-solar",
		cat = "Awaken",
		title = "Awaken: Solar System",
		keys = "awaken sun mercury venus moon mars jupiter saturn neptune conditions",
		body = "Sun: awake from game start (Red Giant when the Mercury-colony laser fires, then "
			.. "explodes). Mercury: after Saturn releases Iapetus toward Venus (needs Venus Colony). "
			.. "Venus: just before Mercury x Iapetus, sleeps after. Moon: 15-min impact timer. "
			.. "Mars: Project Phobos. Jupiter/Saturn/Uranus: after Moon impact. Neptune: after "
			.. "Taxman plucks the gas giants (Proteus is private-server only).",
	},
	{
		id = "awaken-kuiper",
		cat = "Awaken",
		title = "Awaken: Kuiper Belt",
		keys = "awaken pluto charon planet x wise simp pso betelgeuse dwarf planets",
		body = "Pluto: wakes after Charon crashes (post-colony), heads to Mars; nukeable; "
			.. "terraforming PREVENTS awakening. Charon: always awake. Planet X: Space Station "
			.. "exists AND Callisto nuked AND enraged Neptune destroyed. WISE 0855-0714: appears "
			.. "once the Sun starts moving. SIMP 0136: after WISE (Omega Laser). PSO J318: cooks "
			.. "Pluto, Kuiper Space Station laser saves. Betelgeuse: 10-minute window after PSO.",
	},
	{
		id = "awaken-beyond",
		cat = "Awaken",
		title = "Awaken: beyond & Andromeda",
		keys = "awaken proxima sirius black hole sagittarius gorlon pulsar brown dwarf thalaan",
		body = "Proxima C: its moon collides with B (building level 5 on Proxima B). Sirius A/B: "
			.. "stare at Earth after Andromeda - Duo Laser on Veylora kills them; Sirius B first "
			.. "flings itself into Sagittarius A. Black Hole Core: both Sirius stars dead -> "
			.. "expands. Sagittarius A*: 5 minutes to antimatter-laser it after the warp. Thalaan: "
			.. "wakes shortly after landing. Gorlon trio: outer gas giants moving at Earth. Brown "
			.. "Dwarf: after the trio (3 Omega Nukes). Pulsar: after Brown Dwarf.",
	},

	----------------------------------------------------------- story
	{
		id = "story-moon",
		cat = "Story & Planets",
		title = "Story: the Moon",
		keys = "moon crash 15 minutes monsters boss patricia infection bunker",
		body = "The Moon awakens first and needs 15 minutes to hit Earth: volcano, tsunami, "
			.. "MoonInfection, falling satellites, earthquakes. Spawns MoonInfected + Moon Monster "
			.. "every 40-50s; Moon Boss only with >=10 players. Nuke it (fuel found on Mars) for "
			.. "the good path - if nuked, Patricia returns and builds a second Moon that ALWAYS "
			.. "crashes into Earth.",
	},
	{
		id = "story-sequence-1",
		cat = "Story & Planets",
		title = "Full sequence: steps 1-4",
		keys = "story order sequence moon jupiter gas giants neptune planet x earth awakens",
		body = "1) Moon awakens -> humanity nukes it -> Patricia's second Moon crashes into Earth. "
			.. "2) Jupiter/Saturn/Uranus arrive -> nuke Callisto -> Io+Rhea+Oberon launched -> nuke "
			.. "all 3 -> Jupiter eats Earth -> Pluck Radar plucks the gas giants. 3) Neptune arrives "
			.. "-> Proteus + Triton -> antimatter nuke x2 destroys it. 4) Planet X arrives, shoots "
			.. "Moon Juice -> Earth awakens -> Space Station laser destroys Planet X -> Forcefield "
			.. "puts Earth back to sleep.",
	},
	{
		id = "story-sequence-2",
		cat = "Story & Planets",
		title = "Full sequence: steps 5-9",
		keys = "story order dyson sphere sun andromeda omega pulsar sirius black hole veylora",
		body = "5) FRIEND lasers Phobos -> Mars awakens & heads to Earth -> antimatter nuke. "
			.. "6) Dyson Sphere -> Sun angry, moves toward Earth -> Mercury laser turns it red "
			.. "giant -> explodes -> Colossal Moondrives warp Earth -> Sagittarius A* -> antimatter "
			.. "laser -> Andromeda (Gorlon). 7) Galius/Kalius/Ralius -> Omega Nuke x3 -> Brown Dwarf "
			.. "-> nuke x3. 8) Pulsar -> upgraded forcefield survives -> antimatter laser. "
			.. "9) Sirius A/B + Black Hole Core -> Duo Laser on Veylora.",
	},
	{
		id = "planet-venus",
		cat = "Story & Planets",
		title = "Planets: Venus",
		keys = "venus terraform foggy mercury collision sky bases planet3",
		body = "Terraformable, no satellites, between Mercury and Earth. Wakes before Mercury x "
			.. "Iapetus then falls asleep again. If Venus Colony is bought before the gas giants "
			.. "arrive, Mercury can collide with Venus (sky bases destroyed, Friend shop lands). "
			.. "Venus, Mercury and Iapetus never collide with Earth. Surface vision is foggy "
			.. "orange-brown.",
	},
	{
		id = "planet-mars",
		cat = "Story & Planets",
		title = "Planets: Mars",
		keys = "mars phobos deimos awaken project colony planet4 plain juice",
		body = "Satellites Phobos + Deimos (mineable for plain juice). Wakes via Project Phobos "
			.. "(bought on the Mars shop; auto after Planet X destroyed / Dyson Sphere built / "
			.. "Neptune leaves). Awakened Mars heads to Earth - a few minutes of control before it "
			.. "crashes (Awakened Mars Ending). Destroyed by anti-matter nuke -> Dyson Sphere then "
			.. "builds around the Sun. 'Mars has the most awaken versions.'",
	},
	{
		id = "planet-mercury",
		cat = "Story & Planets",
		title = "Planets: Mercury",
		keys = "mercury ionized lava terraform laser red giant planet5 best mining",
		body = "Terraformable, no satellites. Wakes to collide with Venus; Iapetus intercepts -> "
			.. "lava world (or lands on Venus if Venus Colony exists). MINING MERCURY GIVES "
			.. "IONIZED JUICE DIRECTLY - best raw income with no machine needed. Mercury Colony's "
			.. "laser turns the Sun into a red giant (which then explodes).",
	},
	{
		id = "planet-pluto",
		cat = "Story & Planets",
		title = "Planets: Pluto",
		keys = "pluto charon terraform kuiper awaken planet6 colony lava",
		body = "Satellite Charon (always awake; crashes into Pluto after the colony is built - "
			.. "harmless to the colony). If colony built and never terraformed -> awakens, heads to "
			.. "Mars, collision destroys the Mars colony. Terraformed beforehand -> NEVER awakens. "
			.. "Nuke destroys it (explains a completely empty Pluto mid-round). Kuiper path: colony "
			.. "-> expand -> terraform -> FRIEND war -> dwarfs -> Planet X -> ... -> Betelgeuse.",
	},
	{
		id = "planet-earth",
		cat = "Story & Planets",
		title = "Planets: Earth",
		keys = "earth awaken planet x satellite states pangea ice age planet1",
		body = "Between Venus and Mars, one satellite (the Moon), normally cannot awaken. Awakens "
			.. "after Planet X fires Moon Juice into its core; Forcefield puts it back to sleep; "
			.. "stays stationary until destroyed or forced asleep. Visual states: Asleep/Frozen/"
			.. "Lava/Warm/Recovered, Proto Earth, Pangea, Ice Age. Jupiter eats it if the Callisto "
			.. "/Io/Rhea/Oberon chain is mishandled.",
	},

	----------------------------------------------------------- progression
	{
		id = "daily-rewards",
		cat = "Progression",
		title = "Daily rewards",
		keys = "daily reward streak 200 seconds credits rocket launcher pickaxe",
		body = "No streak -> wait 200 seconds, then the daily popup appears. Days: Moon Saber, "
			.. "Iron Pickaxe, Speed Coil, 300 credits, Diamond Pickaxe, Rail Gun, Rocket Launcher. "
			.. "Streak >7 days = 400 credits daily. Miss a day -> lose everything EXCEPT the Rocket "
			.. "Launcher if day 7 was reached. Wiki pages disagree on day 1 vs 2 - verify live.",
	},
	{
		id = "nuke-targets",
		cat = "Progression",
		title = "Nuke targets",
		keys = "nuke anti matter destroy moon pluto mars neptune callisto io rhea oberon",
		body = "Nuke (200): destroys Moon, Pluto, Callisto, Io, Rhea, Oberon. Anti Matter Nuke "
			.. "(300): destroys Mars and enraged Neptune (Triton tanks the first hit). Nuke, Moon "
			.. "Gun and Moon Saber can be bought multiple times. Nuking the Moon = the good path; "
			.. "anti-nuking Mars triggers the Dyson Sphere build.",
	},
	{
		id = "key-builds",
		cat = "Progression",
		title = "Key builds (what unlocks what)",
		keys = "build order venus colony pluto colony space station ionizer unlocks chain",
		body = "Venus Colony 300 unlocks the Mercury chain (Iapetus, Mercury Colony laser). "
			.. "Pluto Colony 300 (Mars shop) brings the IONIZER (plain -> ion). Space Station 500 "
			.. "(global pool) brings the ANTI-matter converter + laser. Mars Colony 350 and Main "
			.. "Colony 700 progress the Mars story. Mercury/Pluto have no shops - buy their stuff "
			.. "from Venus/Mars.",
	},
	{
		id = "round-rules",
		cat = "Progression",
		title = "How a round works",
		keys = "round restart wipes pools fuel credits buildings length fim",
		body = "Live measured: a round restart wipes pools, Fuel, bought buildings and the carried "
			.. "juice stack - CREDITS STAY. Round length varies (measured 2211-3527 seconds, never "
			.. "constant). The Fim overlay plus a frozen story clock mark the end. Dump your juice "
			.. "before the reset - the hub does this automatically.",
	},
	{
		id = "pools",
		cat = "Progression",
		title = "Building pools (how buys work)",
		keys = "pool buy global venus mars fills reset fire server space station",
		body = "Buildings are bought from POOLS (global, Venus, Mars), not personal credits - "
			.. "pools fill as players mine and sell, and reset each round. Rejected buys cost "
			.. "nothing. Measured: SpaceStation global 500, PlutoColony mars 300, Ionized Pumper "
			.. "venus 800, Main Colony mars 700, Venus Sky Bases venus 500->300.",
	},

	----------------------------------------------------------- tips
	{
		id = "tips-income",
		cat = "Tips",
		title = "Best income math",
		keys = "income best mining credits per swing ion mercury moon value",
		body = "Measured: ion conversion pays ~2.5 cr/swing vs the Moon's plain 1.25. Raw ion "
			.. "sells at 20 cr/stack = 0.67/swing, BELOW plain. So run the converter chain: mine "
			.. "where plain -> ion -> anti can complete (Pluto ionizer + Space Station). Mercury "
			.. "surface gives ionized juice straight away when no chain is available.",
	},
	{
		id = "tips-survival",
		cat = "Tips",
		title = "Survival tips",
		keys = "tips survive monsters moon infected bunker gas giants eat ships",
		body = "Moon impact at ~15 min: monsters spawn every 40-50s, Moon Boss only at >=10 "
			.. "players. Eating juice makes you MoonInfected. Items save after death EXCEPT fuels "
			.. "and Moon Juice. Bunker door wait: 100s (was 200). Gas giants eat players who fly "
			.. "too close to Callisto/Titan/Ariel/Oberon; Neptune eats spaceships.",
	},
	{
		id = "tips-machines",
		cat = "Tips",
		title = "Where the machines live",
		keys = "converter hierarchy insert moonjuice hold prompt ionizer station industries",
		body = "Hub-measured: anti converter = <planet>.SpaceStation.ConverterMachine.PartProximity"
			.. " 'Insert Moonjuice' (hold 2s, dist 10); ionizer = same names under a *Industries "
			.. "folder (Pluto's is Planet6.Center.PlutoIndustries). Pumpers are passive - no "
			.. "prompt. Converters no longer need holding since Dec 2025; the hold still works.",
	},
	{
		id = "tips-pickaxes",
		cat = "Tips",
		title = "Pickaxes & weapons",
		keys = "pickaxe iron metal diamond omega best sword saber railgun",
		body = "Credits shop pickaxes: Iron 110, Metal 325, Diamond 1000. Rank order (hub): "
			.. "Op > Omega > Diamond > Metal > Iron > plain. Omega Pickaxe: 1% chance when "
			.. "smelting plain juice in an Omega Smelter (99% = Omega Moon Juice), or 19 R$. "
			.. "Day-2 daily reward grants a melee (wiki conflicts: Saber vs Iron).",
	},
	{
		id = "changelog-recent",
		cat = "Change Log",
		title = "Recent updates",
		keys = "change log update pulsar kuiper lobby sirius proxima planet x",
		body = "2026-05-30 Pulsar - 2026-05-23 PSO / Heat Laser / Lava Pluto - 2026-02-21 Kuiper "
			.. "Belt pt1 - 2026-01-10 Lobby (70-player servers, credits leaderboard, permanent "
			.. "credit items) - 2026-01-04 Sirius/Black Hole - 2025-12-20 Interstellar (Proxima, "
			.. "Oil/Stone/Iron) - 2025-12-07 Planet X (antimatter + Space Station + Diamond "
			.. "Pickaxe & Rocket Launcher in credit shop).",
	},
	{
		id = "changelog-balance",
		cat = "Change Log",
		title = "Balance changes worth knowing",
		keys = "balance converters no hold moon boss nerf ion spawn venus mercury change",
		body = "2025-12-17: Moon Boss HP 10k->5k, Saber cd 2s->1.7s, converters no-hold, ion spawn "
			.. "1.4x, anti 1.3x. 2025-11-18: Sun->Earth 1000s->666s; items save after death except "
			.. "fuels/juice. 2025-11-09: ionized ONLY from Mercury (Venus surface removed). "
			.. "2025-12-02: daily rewards added; Moon Monsters drop Moon Juice.",
	},
	{
		id = "wiki-info",
		cat = "Change Log",
		title = "Game & wiki info",
		keys = "creator cr7siuuu wiki discord horror mr friend antagonists",
		body = "The Moon Wakes Up by Cr7SIUUU, based on the cosmic analogue horror 'The Moon Woke "
			.. "Up' by Mr. Friend. Discord 13+. Wiki: the-moon-wakes-up-roblox.fandom.com. Main "
			.. "antagonist: the Awaken Planets. Key wiki articles: Items, Change Log, Endings, "
			.. "Awaken Planets, Currencies.",
	},
}

local knowledge = {}
knowledge.entries = entries

-- Titles in display order (the dropdown's option list).
function knowledge.topicList()
	local out = {}
	for _, e in ipairs(entries) do
		out[#out + 1] = e.title
	end
	return out
end

function knowledge.get(title)
	for _, e in ipairs(entries) do
		if e.title == title then
			return e.body, e.cat
		end
	end
	return nil, nil
end

function knowledge.random()
	return entries[math.random(1, #entries)]
end

-- Scored search: every query token counts hits in title (x3), keys (x2)
-- and body (x1). Returns up to `limit` entries, best first.
function knowledge.search(query, limit)
	limit = limit or 3
	local q = string.lower(query or "")
	local tokens = {}
	for w in string.gmatch(q, "[%w']+") do
		if #w >= 2 then
			tokens[#tokens + 1] = w
		end
	end
	local scored = {}
	if #tokens > 0 then
		for _, e in ipairs(entries) do
			local title = string.lower(e.title)
			local keys = string.lower(e.keys)
			local body = string.lower(e.body)
			local score = 0
			for _, w in ipairs(tokens) do
				if string.find(title, w, 1, true) then
					score += 3
				end
				if string.find(keys, w, 1, true) then
					score += 2
				end
				if string.find(body, w, 1, true) then
					score += 1
				end
			end
			if score > 0 then
				scored[#scored + 1] = { e = e, score = score }
			end
		end
		table.sort(scored, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.e.title < b.e.title
		end)
	end
	local out = {}
	for i = 1, math.min(limit, #scored) do
		out[#out + 1] = scored[i].e
	end
	return out
end

return knowledge
