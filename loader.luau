--!strict
-- Paralyz / loader.luau
-- Entry point. Tiny on purpose: it pulls Rayfield Gen2, fetches the modules
-- from this repo (or reads them from the bundle the build script produced),
-- builds the menu, and wires every element through src/state.luau.
--
-- Loadstring one-liner (once the repo is public):
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/loader.luau"))()

local VERSION = "0.2.0"
local BASE = "https://raw.githubusercontent.com/MrJoneshere/Paralyz/main/src/"

-- The bundler replaces this line with a literal table of module sources.
local PARALYZ_MODULES = nil -- PARALYZ_BUNDLE

--------------------------------------------------------------- module fetch
local function fetchModule(name: string): any
	local source: string?
	if PARALYZ_MODULES then
		source = PARALYZ_MODULES[name]
		if not source then
			error("[Paralyz] module missing from bundle: " .. name, 2)
		end
	else
		local ok, result = pcall(function()
			return game:HttpGet(BASE .. name .. ".luau")
		end)
		if not ok then
			error("[Paralyz] download failed for " .. name .. ": " .. tostring(result), 2)
		end
		source = result
	end

	local chunk, err = loadstring(source, "Paralyz." .. name)
	if not chunk then
		error("[Paralyz] compile error in " .. name .. ": " .. tostring(err), 2)
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("[Paralyz] error in " .. name .. ": " .. tostring(result), 2)
	end
	return result
end

----------------------------------------------------- tear down a previous run
local previous = (getgenv and getgenv().Paralyz) or nil
if previous and previous.shutdown then
	pcall(previous.shutdown)
end

-------------------------------------------------------------- build the modules
local config = fetchModule("config") -- config and state are data, not factories
local state = fetchModule("state")
local ui = fetchModule("ui")({ state = state })
local util = fetchModule("util")({ config = config })
local perf = fetchModule("perf")({ config = config })
local esp = fetchModule("esp")({ config = config, state = state, util = util })
local farm = fetchModule("farm")({ config = config, state = state, util = util })
local travel = fetchModule("travel")({ config = config, state = state, util = util })
local rewards = fetchModule("rewards")({ config = config, state = state, util = util })

--------------------------------------------------------------- Rayfield Gen2
local okRayfield, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okRayfield or not Rayfield then
	error("[Paralyz] Rayfield Gen2 failed to load: " .. tostring(Rayfield))
end

-- Forward declarations: the Unload button closes over these before their
-- definitions are reached.
local window
local shutdown

window = Rayfield:CreateWindow({
	name = "Paralyz",
	subtitle = "The Moon Wakes Up",
	sidebarLayout = true,
	configuration = {
		autoSave = true,
		autoLoad = true,
		fileName = "Paralyz",
	},
})

util.setNotify(function(title: string, content: string?)
	window:Notify({ title = title, content = content or "", duration = 4 })
end)

pcall(function()
	window:SetProfile(game:GetService("Players").LocalPlayer.DisplayName .. "  ·  Paralyz v" .. VERSION)
end)

--------------------------------------------------------------------- the tabs
local farmTab = window:CreateTab({ name = "Farm" })
local espTab = window:CreateTab({ name = "ESP" })
local travelTab = window:CreateTab({ name = "Travel" })
local settingsTab = window:CreateTab({ name = "Settings" })

-- Farm -------------------------------------------------------------------
ui.section(farmTab, "Auto Farm")

ui.toggle(farmTab, "AutoFarm", {
	name = "Auto Farm",
	description = "Mines the nearest rock, banks the MoonJuice and sells it.",
})

ui.slider(farmTab, "SellAt", {
	name = "Sell at",
	description = "How many MoonJuice stacks to hold before selling.",
	range = { 1, 25 },
	increment = 1,
	value = config.farm.sellAt,
	suffix = " stacks",
})

ui.slider(farmTab, "SwingDelay", {
	name = "Swing delay",
	description = "Seconds between pickaxe swings.",
	range = { 0.15, 2 },
	increment = 0.05,
	value = config.farm.swingDelay,
	suffix = "s",
})

ui.toggle(farmTab, "HideMining", {
	name = "Hide mining",
	description = "Stands the character inside the rock where nobody can see it. The server only accepts swings within ~30 studs of a rock, so staying hidden and staying paid are the same spot. Default ON: visible mining was the source of the far-teleport complaints.",
	value = true,
})

ui.toggle(farmTab, "BlackScreen", {
	name = "Black screen",
	description = "Veils the whole screen - game and menu - with black while the farm runs. Input still passes through, so the toggle stays clickable.",
})

ui.toggle(farmTab, "AutoConvert", {
	name = "Convert before selling",
	description = "Ion juice runs through the SpaceStation anti-matter machine first, then everything sells. Measured: the machine rejects plain juice, so this only makes the trip when ion stacks actually exist.",
	value = true,
})

ui.button(farmTab, {
	name = "Sell everything now",
	description = "Same call the game's own sell button makes.",
	callback = function()
		local sold = util.sellAll()
		window:Notify({
			title = "Sold",
			content = sold > 0 and (sold .. " stacks") or "nothing to sell",
			duration = 3,
		})
	end,
})

ui.section(farmTab, "Wallet")

local creditsStat = ui.stat(farmTab, { name = "Credits", value = util.credits() })
local juiceStat = ui.stat(farmTab, { name = "MoonJuice on hand", value = util.juiceValue() })
local farmStat = ui.text(farmTab, { name = "Farm", text = "idle" })
local converterStat = ui.text(farmTab, { name = "Converters built", text = "checking..." })
local sellStat = ui.text(farmTab, { name = "Sell policy", text = "checking..." })

ui.section(farmTab, "Income")

ui.toggle(farmTab, "AutoRewards", {
	name = "Auto rewards",
	description = "Claims playtime chests (event push) and any completed daily/weekly quest the moment they are ready. Free income that needs no player input.",
	value = true,
})

local questStat = ui.text(farmTab, { name = "Quests", text = "checking..." })

-- ESP --------------------------------------------------------------------
ui.section(espTab, "Overlays")

ui.toggle(espTab, "ESPPlayers", {
	name = "Players",
	description = "Name, health and distance.",
	value = config.esp.players,
})
ui.toggle(espTab, "ESPMonsters", {
	name = "Monsters",
	description = "Moonfected and moon monsters.",
	value = config.esp.monsters,
})
ui.toggle(espTab, "ESPJuice", {
	name = "MoonJuice",
	description = "Juice tanks lying in the world.",
	value = config.esp.juice,
})
ui.toggle(espTab, "ESPRocks", {
	name = "Rocks",
	description = "Mineable rocks on every planet.",
	value = config.esp.rocks,
})
ui.toggle(espTab, "ESPLabels", {
	name = "Name labels",
	description = "Draw name, health and distance over the nearest visible target.",
	value = config.esp.labels,
})

-- Travel -----------------------------------------------------------------
ui.section(travelTab, "Teleport")

-- A saved "Planet 5" selection predates the real names; map it once so
-- the dropdown never shows an option that is not in its list.
local savedDest = state.get("TeleportDest")
if type(savedDest) ~= "string" then
	savedDest = "City"
else
	savedDest = travel.canonical(savedDest)
	state.set("TeleportDest", savedDest)
end

ui.dropdown(travelTab, "TeleportDest", {
	name = "Destination",
	description = "Planets use their story names (Earth, Moon, Venus, Mars, Mercury, Pluto). Structures appear when they are built.",
	options = travel.destinationNames(),
	value = savedDest,
})

ui.button(travelTab, {
	name = "Teleport",
	description = "Jump to the selected destination and verify the landing.",
	callback = function()
		local dest = state.get("TeleportDest") or "City"
		travel.to(dest)
	end,
})

ui.button(travelTab, {
	name = "To nearest rock",
	description = "Land right next to the closest rock.",
	callback = function()
		local rock = util.nearestRock()
		if rock then
			travel.toPosition(rock.Position)
		else
			window:Notify({ title = "Travel", content = "No rocks in the world right now", duration = 3 })
		end
	end,
})

ui.section(travelTab, "Chain Machines")

local machineStat = ui.text(travelTab, { name = "Machines", text = "reading..." })

ui.button(travelTab, {
	name = "To ionizer",
	description = "Go to the plain->ion machine (comes with Pluto Colony).",
	callback = function()
		if not travel.to("Ionizer") then
			window:Notify({ title = "Travel", content = "No ionizer in this world yet", duration = 3 })
		end
	end,
})

ui.button(travelTab, {
	name = "To converter",
	description = "Go to the ion->antimatter machine (Space Station).",
	callback = function()
		if not travel.to("Converter") then
			window:Notify({ title = "Travel", content = "No converter in this world yet", duration = 3 })
		end
	end,
})

ui.section(travelTab, "World Phase")

local threatStat = ui.text(travelTab, { name = "Next threat", text = "reading..." })

ui.section(travelTab, "Movement")

ui.toggle(travelTab, "Noclip", {
	name = "Noclip",
	description = "Walk through terrain and walls.",
})
ui.toggle(travelTab, "Fly", {
	name = "Fly",
	description = "WASD + Space/Ctrl, camera relative.",
})
ui.slider(travelTab, "FlySpeed", {
	name = "Fly speed",
	description = "Studs per second = value x 60. 8 is ~480/s, 32 is ~1920/s.",
	range = { 8, 32 },
	increment = 1,
	value = config.travel.flySpeed,
})

-- Settings ---------------------------------------------------------------
ui.section(settingsTab, "Performance")

ui.toggle(settingsTab, "NoRender", {
	name = "No-render mode",
	description = "Lowest quality, no shadows, no post effects, capped FPS. Protects the GPU.",
	value = true,
})
ui.slider(settingsTab, "FpsCap", {
	name = "FPS cap",
	description = "Frame cap while no-render is on.",
	range = { 10, 60 },
	increment = 5,
	value = config.perf.fps,
	suffix = " fps",
})

ui.section(settingsTab, "Hub")

ui.button(settingsTab, {
	name = "Unload Paralyz",
	description = "Stops every module and destroys the menu.",
	callback = function()
		shutdown()
	end,
})

------------------------------------------------------------------- wiring
local function applySellAt(v)
	if typeof(v) == "number" then
		config.farm.sellAt = math.clamp(math.floor(v), 1, 25)
	end
end

local function applySwingDelay(v)
	if typeof(v) == "number" then
		config.farm.swingDelay = math.clamp(v, 0.15, 2)
	end
end

local function applyFlySpeed(v)
	if typeof(v) == "number" then
		config.travel.flySpeed = v
	end
end

local function applyNoRender(v)
	local report = perf.apply(v == true)
	window:Notify({ title = "No-render", content = report, duration = 4 })
end

local function applyFpsCap(v)
	if typeof(v) ~= "number" then
		return
	end
	config.perf.fps = v
	if state.get("NoRender") and setfpscap then
		pcall(setfpscap, v)
	end
end

-- Black screen: a full-viewport veil above everything (Rayfield included).
-- Frames are transparent to input unless Active, so the menu stays clickable
-- underneath even while the screen looks dead.
local blackGui: ScreenGui? = nil

local function setBlackScreen(on: boolean)
	if on then
		if not blackGui then
			local gui = Instance.new("ScreenGui")
			gui.Name = "ParalyzBlackout"
			gui.DisplayOrder = 9999999
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.Parent = game:GetService("CoreGui")
			local frame = Instance.new("Frame")
			frame.Name = "Veil"
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(0, 0, 0)
			frame.BorderSizePixel = 0
			frame.Parent = gui
			blackGui = gui
		end
		blackGui.Enabled = true
	elseif blackGui then
		blackGui.Enabled = false
	end
end

state.on("AutoFarm", function()
	farm.sync()
end)
state.on("SellAt", applySellAt)
state.on("SwingDelay", applySwingDelay)

state.on("ESPPlayers", function()
	esp.sync()
end)
state.on("ESPMonsters", function()
	esp.sync()
end)
state.on("ESPJuice", function()
	esp.sync()
end)
state.on("ESPRocks", function()
	esp.sync()
end)
state.on("ESPLabels", function()
	esp.sync()
end)

state.on("Noclip", function()
	travel.sync()
end)
state.on("Fly", function()
	travel.sync()
end)
state.on("FlySpeed", applyFlySpeed)

state.on("AutoRewards", function()
	rewards.sync()
end)
state.on("BlackScreen", function(value)
	setBlackScreen(value == true)
end)

state.on("NoRender", applyNoRender)
state.on("FpsCap", applyFpsCap)

-- The config sliders may already hold values restored by autoLoad, and their
-- callbacks ran before these subscriptions existed: replay them once.
applySellAt(state.get("SellAt"))
applySwingDelay(state.get("SwingDelay"))
applyFlySpeed(state.get("FlySpeed"))
applyFpsCap(state.get("FpsCap"))
setBlackScreen(state.get("BlackScreen") == true)

-- Hidden mining is the default way to farm (user decision): make it true on
-- every boot unless the user turns it off during the session. Rayfield
-- applies its autoLoad restore AFTER the menu exists, and the saved config
-- still holds a false from the far-teleport debugging session, so the seed
-- above can lose the race - re-assert once after the restore has landed.
state.set("HideMining", true)
task.delay(1.5, function()
	if state.get("HideMining") ~= true then
		state.set("HideMining", true)
	end
end)

-- First sync: everything defaults off, this just primes the modules with the
-- restored state (e.g. no-render was left on last session).
farm.sync()
esp.sync()
travel.sync()
rewards.sync()
rewards.start()
if state.get("NoRender") == nil then
	state.set("NoRender", true)
else
	applyNoRender(state.get("NoRender"))
end

-------------------------------------------------------------- live stats
task.spawn(function()
	local lastStatErrs: { [string]: boolean } = {}
	-- One guard per stat: a broken updater must not starve the ones after
	-- it (they shared a single pcall, so one throw froze every later stat
	-- at its initial value), and each unique failure is surfaced exactly
	-- once instead of spamming the console every cycle.
	local function update(what: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			local msg = what .. ": " .. tostring(err)
			if not lastStatErrs[msg] then
				lastStatErrs[msg] = true
				warn("[Paralyz] live stats - " .. msg)
			end
		end
	end
	while true do
		if window.unloaded then
			break
		end
		if creditsStat then
			update("credits", function()
				creditsStat:Set(util.credits())
			end)
		end
		if juiceStat then
			update("juice", function()
				juiceStat:Set(util.juiceValue())
			end)
		end
		if farmStat then
			update("farm", function()
				farmStat:Set(farm.isRunning() and farm.stats() or "idle")
			end)
		end
		if converterStat then
			update("converters", function()
				local list = util.converters()
				converterStat:Set(#list > 0 and table.concat(list, ", ") or "none built")
			end)
		end
		if sellStat then
			update("sell", function()
				-- Tier breakdown + which machines can eat it + where the
				-- round clock stands. Plain/ion are held by policy; only the
				-- leading anti run sells (oldest-first server semantics).
				local plain = util.plainJuiceCount()
				local ion = util.ionJuiceCount()
				local anti = util.antiJuiceCount()
				local tiers = {}
				if plain > 0 then
					table.insert(tiers, plain .. " plain")
				end
				if ion > 0 then
					table.insert(tiers, ion .. " ion")
				end
				if anti > 0 then
					table.insert(tiers, anti .. " anti")
				end
				local held = #tiers > 0 and table.concat(tiers, ", ") or "empty"
				local machines = {}
				if util.ionizerPrompt() then
					table.insert(machines, "ionizer")
				end
				if util.converterPrompt() then
					table.insert(machines, "converter")
				end
				local mach = #machines > 0 and table.concat(machines, "+") or "none"
				local cs = util.storyClock()
				local clock = string.format(
					"%d:%02d",
					math.floor(cs / 60),
					math.floor(cs % 60)
				)
				sellStat:Set(
					string.format(
						"%s | machines: %s | round %s%s",
						held,
						mach,
						clock,
						util.roundEndSoon() and " - DUMPING" or ""
					)
				)
			end)
		end
		if questStat then
			update("quests", function()
				questStat:Set(rewards.stats())
			end)
		end
		if machineStat then
			update("machines", function()
				-- Where each chain machine lives right now, so the Travel
				-- tab answers "is it built and where" without a teleport.
				local ion = util.ionizerPrompt()
				local conv = util.converterPrompt()
				local function where(prompt: ProximityPrompt?): string
					if not prompt then
						return "missing"
					end
					local planet = string.match(prompt:GetFullName(), "Planet(%d)")
					return planet and util.planetLabel("Planet" .. planet) or "?"
				end
				machineStat:Set("Ionizer: " .. where(ion) .. " | Converter: " .. where(conv))
			end)
		end
		if threatStat then
			update("threat", function()
				-- PlanetTracker warp countdowns: the most urgent active
				-- threat (same pick as the game's own progress bar).
				local text = "none incoming"
				local pt = workspace:FindFirstChild("PlanetTracker")
				if pt then
					local now = workspace:GetServerTimeNow()
					local bestName, bestEta, anyActive
					for _, c in ipairs(pt:GetChildren()) do
						if c:GetAttribute("WarpActive") == true then
							anyActive = c.Name
							local t = c:GetAttribute("WarpTime")
							local s = c:GetAttribute("WarpStart")
							if typeof(t) == "number" and typeof(s) == "number" and t > 0 then
								local eta = (s + t) - now
								if eta > 0 and (not bestEta or eta < bestEta) then
									bestName, bestEta = c.Name, eta
								end
							end
						end
					end
					if bestName then
						text = string.format(
							"%s in %d:%02d",
							bestName,
							math.floor(bestEta / 60),
							math.floor(bestEta % 60)
						)
					elseif anyActive then
						text = anyActive .. " active"
					end
				end
				threatStat:Set(text)
			end)
		end
		task.wait(2)
	end
end)

------------------------------------------------------------------ shutdown
shutdown = function()
	farm.stop()
	esp.stop()
	travel.stop()
	rewards.stop()
	util.stopAim()
	util.stop() -- disconnect the round-end Text listener
	if blackGui then
		pcall(function()
			blackGui:Destroy()
		end)
		blackGui = nil
	end
	if window and not window.unloaded then
		pcall(function()
			window:Unload()
		end)
	end
	if getgenv then
		getgenv().Paralyz = nil
	end
end

if getgenv then
	getgenv().Paralyz = {
		version = VERSION,
		shutdown = shutdown,
		window = window,
		config = config,
		state = state,
		util = util,
		perf = perf,
		esp = esp,
		farm = farm,
		travel = travel,
		rewards = rewards,
	}
end

window:Notify({
	title = "Paralyz",
	content = "v" .. VERSION .. " loaded",
	duration = 3,
})

return {
	version = VERSION,
	window = window,
	state = state,
	shutdown = shutdown,
}
