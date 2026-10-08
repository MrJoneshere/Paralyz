--!strict
-- Paralyz / src/util.luau
-- Character, tool, juice, rock and camera-aim helpers shared by every module.

return function(deps)
	local config = deps.config

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local util = {}

	util.Players = Players
	util.ReplicatedStorage = ReplicatedStorage
	util.RunService = RunService

	local LocalPlayer = Players.LocalPlayer

	------------------------------------------------------------------ character
	function util.character()
		return LocalPlayer.Character
	end

	function util.humanoid(): Humanoid?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	end

	function util.root(): BasePart?
		local char = util.character()
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	function util.alive(): boolean
		local hum = util.humanoid()
		return hum ~= nil and hum.Health > 0
	end

	-------------------------------------------------------------------- tools
	local function toolList(): { Instance }
		local char = util.character()
		local out = {}
		for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
			table.insert(out, t)
		end
		if char then
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") then
					table.insert(out, t)
				end
			end
		end
		return out
	end

	function util.findTool(namePattern: string): Tool?
		local needle = string.lower(namePattern)
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), needle, 1, true) then
				return t
			end
		end
		return nil
	end

	-- Pickaxes, best first: Op > Omega > Diamond > Metal > Iron > plain Pickaxe.
	local PICKAXE_RANK = { "op", "omega", "diamond", "metal", "iron", "pickaxe" }

	function util.bestPickaxe(): Tool?
		local found = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), "pickaxe", 1, true) then
				table.insert(found, t)
			end
		end
		if #found == 0 then
			return nil
		end
		local best, bestRank = found[1], #PICKAXE_RANK
		for _, t in ipairs(found) do
			local low = string.lower(t.Name)
			for i, key in ipairs(PICKAXE_RANK) do
				if string.find(low, key, 1, true) and i < bestRank then
					best, bestRank = t, i
					break
				end
			end
		end
		return best
	end

	function util.isEquipped(tool: Tool): boolean
		local char = util.character()
		return char ~= nil and tool.Parent == char
	end

	-- Equip through the Humanoid. Never set tool.Parent = char directly:
	-- that leaves a stuck tool whose Tool.Activated never fires, so mining
	-- silently dies. Unequip strays first, then Humanoid:EquipTool - the
	-- sequence the game itself uses (user's fix: unequip -> re-equip).
	function util.equip(tool: Tool, timeout: number?): boolean
		if not tool then
			return false
		end
		if util.isEquipped(tool) then
			return true
		end
		local char = util.character()
		local hum = util.humanoid()
		if not char or not hum then
			return false
		end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t ~= tool then
				t.Parent = LocalPlayer.Backpack
			end
		end
		hum:EquipTool(tool)
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline do
			if util.isEquipped(tool) then
				return true
			end
			task.wait(0.05)
		end
		return util.isEquipped(tool)
	end

	-- Full heal for a stuck pickaxe: send it back to the Backpack, let the
	-- character settle, then re-equip through the Humanoid. This is the
	-- only sequence proven to restore Tool.Activated on a stuck tool, and
	-- what the farm loop's auto-fix uses when swings stop landing.
	function util.reequip(tool: Tool, timeout: number?): boolean
		if not tool then
			return false
		end
		local hum = util.humanoid()
		if not hum then
			return false
		end
		tool.Parent = LocalPlayer.Backpack
		task.wait(0.15)
		hum:EquipTool(tool)
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline do
			if util.isEquipped(tool) then
				return true
			end
			task.wait(0.05)
		end
		return util.isEquipped(tool)
	end

	function util.equippedTool(): Tool?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Tool") :: Tool?
	end

	-------------------------------------------------------------------- juice
	-- MoonJuice is carried as ordinary Tools that own a Credits NumberValue;
	-- the sell remote counts them, so this list is the whole currency model.
	function util.juiceTools(): { { tool: Tool, credits: number } }
		local out = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") then
				local c = t:FindFirstChild("Credits")
				if c and c:IsA("NumberValue") then
					table.insert(out, { tool = t, credits = c.Value })
				end
			end
		end
		return out
	end

	function util.juiceCount(): number
		return #util.juiceTools()
	end

	function util.juiceValue(): number
		local total = 0
		for _, entry in ipairs(util.juiceTools()) do
			total += entry.credits
		end
		return total
	end

	function util.credits(): number
		local stats = LocalPlayer:FindFirstChild("Stats")
		local credits = stats and stats:FindFirstChild("Credits")
		return credits and (credits :: NumberValue).Value or 0
	end

	-- Sells the whole stack. This is the exact call the game's own
	-- "sell everything" button makes, so the server treats it identically.
	function util.sellAll(): number
		local count = util.juiceCount()
		if count == 0 then
			return 0
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("SellMoonjuice")
		if remote then
			(remote :: RemoteEvent):FireServer(count, true)
		end
		return count
	end

	-- Ion juice: the anti-matter machine's input. Plain MoonJuice does NOT
	-- match (measured: a verified hold at the converter consumed nothing
	-- with5 plain stacks aboard - the machine is ion-only per its labels).
	function util.ionJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if string.find(string.lower(entry.tool.Name), "ion", 1, true) then
				n += 1
			end
		end
		return n
	end

	-- The three juice tiers, split by name: plain MoonJuice (15/stack),
	-- "Ionized MoonJuice" (20), "Anti Matter MoonJuice" (74).
	function util.isIon(tool: Instance): boolean
		return string.find(string.lower(tool.Name), "ion", 1, true) ~= nil
	end

	function util.isAnti(tool: Instance): boolean
		return string.find(string.lower(tool.Name), "anti", 1, true) ~= nil
	end

	function util.plainJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if not util.isIon(entry.tool) and not util.isAnti(entry.tool) then
				n += 1
			end
		end
		return n
	end

	function util.antiJuiceCount(): number
		local n = 0
		for _, entry in ipairs(util.juiceTools()) do
			if util.isAnti(entry.tool) then
				n += 1
			end
		end
		return n
	end

	-- How many anti-matter stacks can be sold RIGHT NOW without touching a
	-- non-anti stack. MEASURED (2026-10-07, job "sell-order"): the server
	-- sells the OLDEST tools first, in Backpack insertion order - firing
	-- (1,false) with [MoonJuice, Ionized] aboard removed the MoonJuice, and
	-- the game's own sell preview sums `first N` the same way. So the safe
	-- subset = the leading run of anti-matter tools; anything behind an
	-- older plain/ion stack stays held until it converts (or the round
	-- end dump fires).
	function util.sellableAnti(): number
		local list = util.juiceTools()
		local n = 0
		for i = 1, #list do
			if util.isAnti(list[i].tool) then
				n += 1
			else
				break
			end
		end
		return n
	end

	-- Sells ONLY the leading anti-matter run (the game's own "sell N"
	-- contract: (count, false)). Returns the stacks sold.
	function util.sellAnti(): number
		local n = util.sellableAnti()
		if n == 0 then
			return 0
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("SellMoonjuice")
		if remote then
			(remote :: RemoteEvent):FireServer(n, false)
		end
		return n
	end

	-- Is any sell/convert action actually pending right now? Used to decide
	-- whether a swing batch must yield; a plain hold below the cap keeps
	-- mining (stacking for the round-end dump) instead of spinning. The
	-- conversion check mirrors the loop's threshold: below sellAt the
	-- machines are deliberately NOT used yet, so they are not "pending".
	function util.sellActionPending(): boolean
		if util.juiceCount() == 0 then
			return false
		end
		if util.roundEndSoon() then
			return true
		end
		if util.sellableAnti() > 0 then
			return true
		end
		if util.juiceCount() >= config.farm.sellAt then
			if util.ionJuiceCount() > 0 and util.converterPrompt() then
				return true
			end
			if util.plainJuiceCount() > 0 and util.ionizerPrompt() then
				return true
			end
		end
		return false
	end

	---------------------------------------------------------------- round end
	-- Values.ClientSeconds is the story clock; it resets when the round
	-- restarts (measured: 3527 -> 5 after the final story chain).
	function util.storyClock(): number
		local values = ReplicatedStorage:FindFirstChild("Values")
		local cs = values and values:FindFirstChild("ClientSeconds")
		return cs and (cs :: NumberValue).Value or 0
	end

	-- End-of-round signals, MEASURED on the restart the round-end watcher
	-- caught (round ended at ClientSeconds=3527):
	--   * The final story chain arrives over the Text remote shortly before
	--     the hard reset: "THE DYSON SPHERE GOT DESTROYED!" (~20s to go)
	--     and "THE SUN IS MOVING! ..." (~10s). Both are inside the user's
	--     ~30s dump window.
	--   * PlayerGui.Fim ("The End") as generic backup - it NEVER enabled in
	--     the measured round, so it cannot be the only signal.
	--   * config.farm.roundLength clock threshold, disabled (0) until the
	--     watcher proves the length constant - measured rounds ended at
	--     2854 and 3527, so it is NOT constant.
	-- The flag clears itself when the clock rewinds: that is a new round.
	-- Fim ALONE is not an end signal: measured 2026-10-08, the current game
	-- version keeps PlayerGui.Fim enabled from round start (it stayed on the
	-- whole round while the clock climbed past 3000s - a "hide in the
	-- bunker" overlay). Fim only counts together with a STOPPED story clock,
	-- the state measured right before every hard reset (clock freezes, Fim
	-- shows 10-41s, then the wipe) and during the 2026-10-08 server wedge.
	local lastCs = util.storyClock()
	local lastCsAt = os.clock()
	local END_MARKERS = {
		"dyson sphere got destroyed",
		"the sun is moving",
	}
	local endMarker = false
	local endClock = 0
	local endWatch: RBXScriptConnection? = nil

	local function hookEndWatch()
		if endWatch then
			return
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("Text")
		if remote then
			endWatch = (remote :: RemoteEvent).OnClientEvent:Connect(function(msg)
				if typeof(msg) ~= "string" then
					return
				end
				local low = string.lower(msg)
				for _, marker in ipairs(END_MARKERS) do
					if string.find(low, marker, 1, true) then
						endMarker = true
						return
					end
				end
			end)
		end
	end
	hookEndWatch()

	-- Called on shutdown/reload so the old bundle's listener cannot keep
	-- setting the flag after a live-reload.
	function util.stop()
		if endWatch then
			endWatch:Disconnect()
			endWatch = nil
		end
	end

	-- The round is about to restart: everything in the backpack is lost, so
	-- the farm dumps the whole stack regardless of tier.
	function util.roundEndSoon(): boolean
		local cs = util.storyClock()
		if cs < endClock then
			-- clock rewind = a fresh round; the old round's warning expires
			endMarker = false
		end
		endClock = cs
		if endMarker then
			return true
		end
		if cs ~= lastCs then
			-- the round is live: the story clock advances, whatever Fim shows
			lastCs = cs
			lastCsAt = os.clock()
			return false
		end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local fim = pg and pg:FindFirstChild("Fim")
		if fim and (fim :: ScreenGui).Enabled and os.clock() - lastCsAt >= 8 then
			return true
		end
		local len = config.farm.roundLength
		if len and len > 0 then
			local win = config.farm.endDumpWindow or 30
			if cs >= len - win then
				return true
			end
		end
		return false
	end

	-- The only conversion interface in the game: the SpaceStation's
	-- "Insert Moonjuice" prompt (2.0s hold, 10 studs, line of sight).
	-- Buildings phase in and out, so this resolves freshly every call.
	function util.converterPrompt(): ProximityPrompt?
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return nil
		end
		for _, planet in ipairs(planets:GetChildren()) do
			local station = planet:FindFirstChild("SpaceStation")
			local machine = station and station:FindFirstChild("ConverterMachine")
			local well = machine and machine:FindFirstChild("PartProximity")
			local prompt = well and well:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				return prompt
			end
		end
		return nil
	end

	-- The ionizer (plain -> ion), measured once Pluto's colony was built:
	--   Planets.Planet6.Center.PlutoIndustries.ConverterMachine.PartProximity
	-- It reuses the anti converter's exact machine and prompt names
	-- ("ConverterMachine" + "Insert Moonjuice", 2s hold, 10 studs), so the
	-- ONLY reliable identity is the structure above: the anti converter
	-- lives under a SpaceStation, the ionizer under a "<Planet>Industries"
	-- folder. Hierarchy probe first (cheap), then a text fallback for
	-- machines whose shape is not known yet (the Venus/Mercury ion pumps).
	-- Short TTL because the probe walks every planet's descendants.
	local function underStation(inst: Instance): boolean
		local cur: Instance? = inst
		while cur do
			if cur.Name == "SpaceStation" then
				return true
			end
			cur = cur.Parent
		end
		return false
	end

	local ionizerCache: ProximityPrompt? = nil
	local ionizerAt = 0
	function util.ionizerPrompt(): ProximityPrompt?
		if os.clock() - ionizerAt < 2 then
			return ionizerCache
		end
		ionizerAt = os.clock()
		ionizerCache = nil
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, planet in ipairs((planets :: Folder):GetChildren()) do
				for _, inst in ipairs((planet :: Instance):GetDescendants()) do
					if inst.Name == "ConverterMachine" and not underStation(inst) then
						local well = inst:FindFirstChild("PartProximity")
						local prompt = well and well:FindFirstChildWhichIsA("ProximityPrompt", true)
						if prompt then
							ionizerCache = prompt
							return ionizerCache
						end
					end
				end
			end
		end
		-- Unknown-hierarchy fallback: name/text match, anti converter
		-- excluded by the SpaceStation check above so "Insert Moonjuice"
		-- on the station can never be mistaken for the ionizer.
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and not underStation(d) then
				local holder = d.Parent
				local machine = holder and holder.Parent
				local hay = string.lower(
					d.ActionText
						.. " "
						.. d.ObjectText
						.. " "
						.. (holder and holder.Name or "")
						.. " "
						.. (machine and machine.Name or "")
				)
				if string.find(hay, "ioniz", 1, true) or string.find(hay, "ionmoon", 1, true) then
					ionizerCache = d
					return ionizerCache
				end
			end
		end
		return nil
	end

	-------------------------------------------------------------------- rocks
	-- Rocks live in a folder called "Rocks" somewhere under each planet - on
	-- some planets it is a direct child, on others it hangs off the planet's
	-- Center part - and the server fills it in waves.
	function util.rocks(): { BasePart }
		local out = {}
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return out
		end
		for _, planet in ipairs(planets:GetChildren()) do
			for _, inst in ipairs(planet:GetDescendants()) do
				if inst:IsA("Folder") and inst.Name == "Rocks" then
					for _, rock in ipairs((inst :: Folder):GetChildren()) do
						if rock:IsA("BasePart") then
							table.insert(out, rock)
						end
					end
				end
			end
		end
		return out
	end

	function util.minableRocks(): { BasePart }
		local out = {}
		for _, rock in ipairs(util.rocks()) do
			local flag = rock:FindFirstChild("Minable")
			-- Minable=false has been observed on rocks that still accept a swing,
			-- so the flag is reported but never used as a filter by default.
			if flag == nil or flag:IsA("BoolValue") then
				table.insert(out, rock)
			end
		end
		return out
	end

	function util.nearestRock(from: Vector3?): BasePart?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, rock in ipairs(util.minableRocks()) do
			local d = (rock.Position - origin).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = rock, d
			end
		end
		return best
	end

	-- A part inside some planet's Rocks folder - what the server accepts as
	-- a swing target (aiming at any other part drops the swing, measured).
	function util.isRockPart(inst: Instance?): boolean
		local p: Instance? = inst
		while p and p ~= workspace do
			if p:IsA("Folder") and p.Name == "Rocks" then
				return true
			end
			p = p.Parent
		end
		return false
	end

	-- Rocks within radius of a point: what "loaded around me" means. Rocks
	-- from the planet you just left linger while they stream out, and the
	-- server range rule makes swinging at them useless anyway, so every
	-- proximity question in the farm is asked through this.
	function util.rocksNear(origin: Vector3, radius: number): { BasePart }
		local out = {}
		for _, rock in ipairs(util.rocks()) do
			if (rock.Position - origin).Magnitude <= radius then
				table.insert(out, rock)
			end
		end
		return out
	end

	-- After a teleport, wait until the destination has actually streamed in:
	-- the server spawns rocks a few seconds after the character arrives, and
	-- judging emptiness from far away (the old behaviour) just bounced the
	-- farm across unloaded space. Returns the rock count when the wait ends;
	-- 0 means still empty after `timeout` seconds.
	function util.settleRocks(pos: Vector3, timeout: number, radius: number?): number
		local r = radius or config.farm.streamRadius
		local deadline = os.clock() + timeout
		local origin = pos
		while os.clock() < deadline do
			local root = util.root()
			origin = root and root.Position or pos
			local n = #util.rocksNear(origin, r)
			if n > 0 then
				return n
			end
			task.wait(0.5)
		end
		local root = util.root()
		origin = root and root.Position or pos
		return #util.rocksNear(origin, r)
	end

	-- Where a teleport should land: raycast down from above the point so the
	-- character ends on the surface instead of inside the geometry. The
	-- near ray covers hubs and small structures (and only ever lands in
	-- pos+600..pos-900); planet centres sit INSIDE their own mesh, where a
	-- ray starting inside cannot hit the surface (backfaces), so a miss
	-- retries from high above before giving up.
	function util.dropToSurface(pos: Vector3): Vector3
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { util.character() }
		local hit = workspace:Raycast(pos + Vector3.new(0, 600, 0), Vector3.new(0, -1500, 0), params)
		if hit then
			return hit.Position + Vector3.new(0, 5, 0)
		end
		hit = workspace:Raycast(pos + Vector3.new(0, 5000, 0), Vector3.new(0, -10000, 0), params)
		if hit then
			return hit.Position + Vector3.new(0, 5, 0)
		end
		return pos + Vector3.new(0, 10, 0)
	end

	-- Every teleport in the hub fires this (travel and the farm both call
	-- it): the farm pins the character with a per-frame hold, so a teleport
	-- the hold does not know about gets overwritten on the very next frame.
	-- The farm assigns a listener that moves the hold onto the new spot.
	local teleportListener: ((CFrame) -> ())? = nil

	function util.onTeleport(fn: ((CFrame) -> ()))
		teleportListener = fn
	end

	function util.teleported(cf: CFrame)
		if teleportListener then
			task.spawn(pcall, teleportListener, cf)
		end
	end

	-- The story's planet names (user mapping): the folders are internal
	-- Planet1..Planet6, but everything user-facing shows these.
	local PLANET_LABELS = {
		Planet1 = "Earth",
		Planet2 = "Moon",
		Planet3 = "Venus",
		Planet4 = "Mars",
		Planet5 = "Mercury",
		Planet6 = "Pluto",
	}

	function util.planetLabel(name: string): string
		return PLANET_LABELS[name] or name
	end

	-- Every planet that exists right now: centre plus how many rocks are
	-- streaming at it. Rocks only exist while somebody is near the planet,
	-- so this doubles as "where can I actually mine".
	function util.planetScan(): { { name: string, label: string, centre: Vector3, rocks: number } }
		local out = {}
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return out
		end
		for _, planet in ipairs(planets:GetChildren()) do
			local centre: Vector3? = nil
			if planet:IsA("BasePart") then
				centre = (planet :: BasePart).Position
			else
				local c = (planet :: any):FindFirstChild("Center")
				if c and c:IsA("BasePart") then
					centre = (c :: BasePart).Position
				else
					local p = (planet :: any):FindFirstChildWhichIsA("BasePart", true)
					centre = p and (p :: BasePart).Position or nil
				end
			end
			if centre then
				local rocks = 0
				for _, inst in ipairs((planet :: any):GetDescendants()) do
					if inst:IsA("Folder") and inst.Name == "Rocks" then
						rocks += #(inst :: Folder):GetChildren()
					end
				end
				table.insert(out, { name = planet.Name, label = util.planetLabel(planet.Name), centre = centre, rocks = rocks })
			end
		end
		return out
	end

	-- Converter economy: PumpJack/Pumper buildings ("MoonJuice Tanks Will
	-- Spawn Every 1 Minute"), and the SpaceStation anti-matter machine
	-- (prompt "Insert Moonjuice": 1 Ion MoonJuice -> 1 Anti Matter
	-- MoonJuice, worth more than plain juice). None of these are permanent -
	-- they only exist once somebody spends Events.Buy on them, so phases
	-- bring them and go. This reports what is actually standing in the
	-- world right now; the use-it options wait on live observation.
	function util.converters(): { string }
		local out, seen = {}, {}
		local function add(label: string)
			if not seen[label] then
				seen[label] = true
				table.insert(out, label)
			end
		end
		for _, child in ipairs(workspace:GetChildren()) do
			if string.find(child.Name, "Pump", 1, true) then
				add(child.Name)
			end
		end
		local planets = workspace:FindFirstChild("Planets")
		if planets then
			for _, planet in ipairs(planets:GetChildren()) do
				local station = (planet :: any):FindFirstChild("SpaceStation")
				if station and (station :: any):FindFirstChild("ConverterMachine") then
					add("AntiMatter@" .. util.planetLabel(planet.Name))
				end
			end
		end
		return out
	end

	------------------------------------------------------------------ monsters
	function util.monsters(): { Model }
		local out = {}
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, folderName in ipairs({ "MoonMonsters", "SmallMoonMonsters" }) do
			local folder = unanchored:FindFirstChild(folderName)
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					if child:IsA("Model") then
						table.insert(out, child)
					end
				end
			end
		end
		return out
	end

	function util.aliveMonsters(): { Model }
		local out = {}
		for _, model in ipairs(util.monsters()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(out, model)
			end
		end
		return out
	end

	function util.nearestMonster(from: Vector3?, maxDist: number?): Model?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, model in ipairs(util.aliveMonsters()) do
			local pivot = model:GetPivot().Position
			local d = (pivot - origin).Magnitude
			if (not maxDist or d <= maxDist) and (not bestDist or d < bestDist) then
				best, bestDist = model, d
			end
		end
		return best
	end

	--------------------------------------------------------------------- aim
	-- The game asks the client for Mouse.Target when a tool is activated, so
	-- a swing only pays while the camera's ray through the mouse lands on a
	-- rock the character is in range of (both rules measured: non-rock targets
	-- and >30-stud distance are dropped, and firing the remote directly
	-- without a real Tool.Activated is ignored outright). aimAt therefore
	-- tries several camera bases - side, straight up, far side - and ALWAYS
	-- releases the camera again when every base fails; an unbound-on-fail
	-- solve is what used to leave the view glued to the rock while no swings
	-- happened at all.
	local AIM_BIND = "ParalyzAim"

	function util.stopAim()
		pcall(function()
			RunService:UnbindFromRenderStep(AIM_BIND)
		end)
	end

	local function solveToward(cam: Camera, targetPos: Vector3, base: Vector3): CFrame
		local mouse = LocalPlayer:GetMouse()
		local px = Vector2.new(mouse.X, mouse.Y)
		local cf = CFrame.lookAt(base, targetPos)
		for _ = 1, 12 do
			cam.CFrame = cf
			local ray = cam:ViewportPointToRay(px.X, px.Y)
			local desired = targetPos - ray.Origin
			if desired.Magnitude < 1 then
				break
			end
			desired = desired.Unit
			cf = cf
				* CFrame.lookAt(Vector3.zero, ray.Direction)
					:ToObjectSpace(CFrame.lookAt(Vector3.zero, desired))
		end
		return cf
	end

	-- True when this hit would really be paid out: any rock part within the
	-- server's swing range of the character (a neighbouring rock is a valid
	-- target too - rejecting those was the aim-failure storm), or, for bare
	-- positions such as a monster pivot, a hit close to that point.
	local function aimValid(mt: BasePart?, target: Vector3): boolean
		if not mt then
			return false
		end
		if util.isRockPart(mt) then
			local root = util.root()
			return root ~= nil and util.dist(root.Position, mt.Position) <= config.farm.maxRange + 4
		end
		return util.dist(mt.Position, target) <= 12
	end

	-- holdOnFail: keep the camera where the last attempt left it instead of
	-- snapping it back to the pre-aim view. The farm passes this while it
	-- runs: restore-then-relock every batch was the visible camera churn
	-- (lock, restore, lock, restore). While running the aim simply moves
	-- from target to target; the view is handed back exactly once, when the
	-- farm stops.
	function util.aimAt(targetPos: Vector3?, standOff: number?, holdOnFail: boolean?): boolean
		local target = targetPos or (util.root() and util.root().Position)
		if not target then
			return false
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return false
		end
		local startCF = cam.CFrame
		local so = standOff or config.farm.aimDistance
		local side = startCF.Position - target
		if side.Magnitude < 1 then
			side = Vector3.new(0, 1, 0)
		end
		side = side.Unit
		-- Bases in order of robustness. Straight up is the reliable one:
		-- nothing on the ground can occlude a rock seen from directly above,
		-- and after a long teleport the old single side-basis pointed into
		-- unloaded geometry, which is where the permanent failures came from.
		local bases = {
			target + side * so + Vector3.new(0, 3, 0),
			target + Vector3.new(0, math.max(so, 30), 0),
			target - side * so + Vector3.new(0, 3, 0),
		}
		for _, base in ipairs(bases) do
			local cf = solveToward(cam, target, base)
			util.stopAim()
			RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
				cam.CFrame = cf
			end)
			task.wait() -- let the frame land so Mouse.Target refreshes
			if aimValid(util.mouseTarget(), target) then
				return true
			end
			if holdOnFail then
				-- Leave the last attempt bound: the next aim call rebinds
				-- anyway, and a mid-run restore is exactly the snap the user
				-- sees as camera jitter.
				continue
			end
			util.stopAim()
		end
		if holdOnFail then
			return false
		end
		-- Nothing worked and nobody is mid-run: hand the view back exactly as it was.
		cam.CFrame = startCF
		return false
	end

	function util.mouseTarget(): BasePart?
		return LocalPlayer:GetMouse().Target :: BasePart?
	end

	-------------------------------------------------------------------- misc
	function util.dist(a: Vector3, b: Vector3): number
		return (a - b).Magnitude
	end

	function util.lookAt(pos: Vector3)
		local cam = workspace.CurrentCamera
		local root = util.root()
		if cam and root then
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
		end
	end

	-- Notification hook the loader installs once the window exists.
	local notifyFn: ((title: string, content: string?) -> ())? = nil

	function util.setNotify(fn)
		notifyFn = fn
	end

	function util.notify(title: string, content: string?)
		if notifyFn then
			task.spawn(pcall, notifyFn, title, content)
		end
	end

	function util.safe(fn, ...)
		local args = table.pack(...)
		local ok, res = pcall(function()
			return fn(table.unpack(args, 1, args.n))
		end)
		if ok then
			return res
		end
		return nil
	end

	return util
end
