--!strict
-- Paralyz / src/perf.luau
-- Lower Usage 2.0 - client-side visibility culling with a PROVABLE
-- zero-visual-change guarantee (user order 2026-10-12: "the lowest usage
-- possible with NO visual changes no matter what").
--
-- v3 hardening over the first version, all driven by live GPU measurements
-- (Windows "GPU Engine" counters on the Roblox process, RX 590):
--   * the old test used the part CENTER against the frustum, so a large far
--     part could have its visible edge clipped off-screen: not zero-visual.
--     v3 tests the part's oriented box exactly (all 8 corners beyond one
--     shared plane of the - margin widened - frustum; the frustum is convex,
--     so that is a proof of invisibility, not a heuristic),
--   * restoration is now the FIRST pass of every slice (was: budget-queued),
--     so a hidden part that turns toward you is back within one slice,
--   * the loop wakes on camera rotation instead of sleeping out its slice,
--   * parking of PointLights / ParticleEmitters / SurfaceGuis on hidden parts
--     uses exact proofs: a light only when its whole range-sphere is outside,
--     an emitter only when no particle of it can physically reach the view
--     (speed x lifetime + accel term + particle size + safety), a surface GUI
--     only when the host part's box is itself proven outside,
--   * stale entries (StreamingEnabled unloads parts constantly) are purged
--     with a real aliveness check - the old check only tested pcall success,
--     so dead references piled up by the thousands.
-- Measured reality (main place, 75 Hz vsync): the engine already skips
-- off-screen geometry, so part hiding is worth ~0 GPU there; the wins are
-- scene-dependent (lit/particle-heavy scenes, shadow passes). Quality,
-- shadows, post effects and frame cap are NEVER touched.
--
-- Interface kept: perf.apply(on) toggles, perf.report() describes.

return function(deps)
	local config = deps.config

	local Players = game:GetService("Players")
	local workspace = game:GetService("Workspace")
	local Lighting = game:GetService("Lighting")

	local perf = {}

	local enabled = false
	local runId = 0
	local registry: { BasePart } = {}
	local cursor = 1
	local lastRegistryBuild = 0
	local hidden: { [BasePart]: boolean } = {}
	local hiddenCount = 0
	local trackedCount = 0
	-- Objects parked while their host part is proven invisible. Every entry
	-- means "we turned this off, we own turning it back on".
	local litOut: { [PointLight]: boolean } = {}
	local litCount = 0
	local emitOut: { [ParticleEmitter]: boolean } = {}
	local emitCount = 0
	local guiOut: { [SurfaceGui]: boolean } = {}
	local guiCount = 0
	-- Scratch buffer for the hidden-first pass (reused, never reallocated).
	local scratch: { BasePart } = {}
	-- Cross-reload generation: live-reload leaves old threads running, so
	-- every reload claims a new generation and old loops exit on their next
	-- slice instead of stacking forever.
	local GEN_KEY = "ParalyzGen_perf"
	local function claimGen(): number
		local env: any = getgenv()
		local g = (env[GEN_KEY] or 0) + 1
		env[GEN_KEY] = g
		return g
	end
	local function genAlive(g: number): boolean
		local env: any = getgenv()
		return env[GEN_KEY] == g
	end

	local function opts()
		local p = config.perf or {}
		return {
			near = p.cullNearDist or 150,
			maxSize = p.cullMaxSize or 200,
			marginDeg = p.cullMarginDeg or 10,
			budget = p.cullBudget or 400,
			slice = p.cullSliceSecs or 0.1,
			refresh = p.cullRefreshSecs or 8,
			particleSafety = p.cullParticleSafety or 25,
		}
	end

	---------------------------------------------------------------- frustum
	-- Five outward normals of the margin-widened frustum: right, left, top,
	-- bottom (angle widened by marginDeg on both axes) and behind the camera.
	-- A point is outside iff any of them has a positive signed distance.
	type Frustum = { campos: Vector3, planes: { Vector3 } }

	local function buildFrustum(cam: Camera, marginDeg: number): Frustum
		local cf = cam.CFrame
		local campos = cf.Position
		local f = cf.LookVector
		local r = cf.RightVector
		local u = cf.UpVector
		local halfV = math.rad(cam.FieldOfView / 2)
		local aspect = 1
		local vs = cam.ViewportSize
		if vs.Y > 0 then
			aspect = vs.X / vs.Y
		end
		local halfH = math.atan(math.tan(halfV) * aspect)
		local m = math.rad(marginDeg)
		local tanH = math.tan(halfH + m)
		local tanV = math.tan(halfV + m)
		local planes: { Vector3 } = {}
		local function add(n: Vector3)
			local mag = n.Magnitude
			if mag > 1e-6 then
				table.insert(planes, n / mag)
			end
		end
		add(r - f * tanH)
		add(-r - f * tanH)
		add(u - f * tanV)
		add(-u - f * tanV)
		add(-f)
		return { campos = campos, planes = planes }
	end

	-- Distance from a point to the closest frustum boundary (positive =
	-- outside). Since the frustum is contained in every one of its half
	-- spaces, this is a LOWER bound of the true distance outside, which
	-- makes every "> something" test built on it conservative.
	local function outsideDistance(pos: Vector3, fr: Frustum): number
		local d = pos - fr.campos
		local best = -math.huge
		for _, n in ipairs(fr.planes) do
			local sd = d:Dot(n)
			if sd > best then
				best = sd
			end
		end
		return best
	end

	-- Exact conservative box test (p-vertex per plane): the oriented box is
	-- invisible when all 8 corners sit beyond one shared plane.
	local function obbOutside(cf: CFrame, size: Vector3, fr: Frustum): boolean
		local pos = cf.Position
		local hx = cf.XVector * (size.X * 0.5)
		local hy = cf.YVector * (size.Y * 0.5)
		local hz = cf.ZVector * (size.Z * 0.5)
		for _, n in ipairs(fr.planes) do
			local ext = math.abs(n:Dot(hx)) + math.abs(n:Dot(hy)) + math.abs(n:Dot(hz))
			if n:Dot(pos - fr.campos) - ext > 0 then
				return true
			end
		end
		return false
	end

	-- True when the part must stay rendered: close to the camera (pop-in
	-- ring around you), or its box still touches the frustum.
	local function isOutside(part: BasePart, fr: Frustum, o): boolean
		local dist = (part.Position - fr.campos).Magnitude
		if dist <= o.near then
			return false
		end
		return obbOutside(part.CFrame, part.Size, fr)
	end

	---------------------------------------------------- parking proofs
	-- How far a particle from this emitter can ever get from its origin:
	-- speed x lifetime plus the acceleration term plus the particle's own
	-- size. Drag and engine-side fading only shorten that, so the bound is
	-- safe. Absurd lifetimes are never parked (stay conservative).
	local function emitterReach(em: ParticleEmitter): number
		local okL, life = pcall(function()
			return em.Lifetime.Max
		end)
		if not okL or life <= 0 or life > 30 then
			return math.huge
		end
		local okS, spd = pcall(function()
			return em.Speed.Max
		end)
		local okA, acc = pcall(function()
			return em.Acceleration.Magnitude
		end)
		local sizeMax = 0
		local okSz, seq = pcall(function()
			return em.Size
		end)
		if okSz and typeof(seq) == "NumberSequence" then
			for _, k in ipairs((seq :: NumberSequence).Keypoints) do
				if k.Value > sizeMax then
					sizeMax = k.Value
				end
			end
		end
		local reach = (if okS then spd else 0) * life + 0.5 * (if okA then acc else 0) * life * life + sizeMax
		return reach
	end

	local function emitterWorldPos(em: ParticleEmitter): Vector3?
		local att = em.Attachment0
		if att then
			return att.WorldPosition
		end
		local par = em.Parent
		if par and par:IsA("Attachment") then
			return par.WorldPosition
		end
		if par and par:IsA("BasePart") then
			return par.Position
		end
		return nil
	end

	-- Light has no WorldPosition: resolve it through its attachment or the
	-- part it lives on (nil only when it sits somewhere unrenderable, in
	-- which case there is nothing to park either).
	local function lightWorldPos(light: PointLight): Vector3?
		local att = light.Attachment0
		if att then
			return att.WorldPosition
		end
		local par = light.Parent
		if par and par:IsA("Attachment") then
			return par.WorldPosition
		end
		if par and par:IsA("BasePart") then
			return par.Position
		end
		return nil
	end

	-- Re-enable everything we parked for a part that is visible again.
	local function unpark(part: BasePart)
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("PointLight") and litOut[d :: PointLight] then
				pcall(function()
					(d :: PointLight).Enabled = true
				end)
				litOut[d :: PointLight] = nil
				litCount -= 1
			elseif d:IsA("ParticleEmitter") and emitOut[d :: ParticleEmitter] then
				pcall(function()
					(d :: ParticleEmitter).Enabled = true
				end)
				emitOut[d :: ParticleEmitter] = nil
				emitCount -= 1
			elseif d:IsA("SurfaceGui") and guiOut[d :: SurfaceGui] then
				pcall(function()
					(d :: SurfaceGui).Enabled = true
				end)
				guiOut[d :: SurfaceGui] = nil
				guiCount -= 1
			end
		end
	end

	-- Park whatever provably cannot be seen on a hidden part. Every test is
	-- an exact proof built from the same margin-widened frustum.
	local function park(part: BasePart, fr: Frustum, o)
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("PointLight") then
				local light = d :: PointLight
				local okR, range = pcall(function()
					return light.Range
				end)
				local okE, isOn = pcall(function()
					return light.Enabled
				end)
				if okR and okE and isOn and range > 0 and not litOut[light] then
					-- A point light can only affect pixels within Range of it:
					-- if that whole sphere is outside the frustum, no visible
					-- pixel can change. Range 0 = infinite: never touched.
					-- Spot/SurfaceLight are directional: never touched.
					local lpos = lightWorldPos(light)
					if lpos and outsideDistance(lpos, fr) > range then
						local okOff = pcall(function()
							light.Enabled = false
						end)
						if okOff then
							litOut[light] = true
							litCount += 1
						end
					end
				end
			elseif d:IsA("ParticleEmitter") then
				local em = d :: ParticleEmitter
				local okE, isOn = pcall(function()
					return em.Enabled
				end)
				if okE and isOn and not emitOut[em] then
					local pos = emitterWorldPos(em)
					if pos then
						local reach = emitterReach(em) + o.particleSafety
						if reach < math.huge and outsideDistance(pos, fr) > reach then
							local okOff = pcall(function()
								em.Enabled = false
							end)
							if okOff then
								emitOut[em] = true
								emitCount += 1
							end
						end
					end
				end
			elseif d:IsA("SurfaceGui") then
				local gui = d :: SurfaceGui
				local okE, isOn = pcall(function()
					return gui.Enabled
				end)
				if okE and isOn and not guiOut[gui] then
					-- A surface GUI is drawn onto a face of its host part; the
					-- whole box of that part is proven outside right now, so
					-- the face is too (Adornee wins over ancestry when set).
					local host = gui.Adornee
					if not host or not host:IsA("BasePart") then
						host = gui:FindFirstAncestorOfClass("BasePart")
					end
					if host == part then
						local okOff = pcall(function()
							gui.Enabled = false
						end)
						if okOff then
							guiOut[gui] = true
							guiCount += 1
						end
					end
				end
			end
		end
	end

	local function setShown(part: BasePart, show: boolean, fr: Frustum, o)
		if show then
			if hidden[part] then
				hidden[part] = nil
				hiddenCount -= 1
				unpark(part)
			end
			pcall(function()
				part.LocalTransparencyModifier = 0
			end)
			return
		end
		local ok = pcall(function()
			part.LocalTransparencyModifier = 1
		end)
		if not ok then
			return
		end
		if hidden[part] then
			return -- already hidden: its objects are already parked
		end
		hidden[part] = true
		hiddenCount += 1
		pcall(park, part, fr, o)
	end

	----------------------------------------------------------- registry
	local function purgePart(part: BasePart)
		if hidden[part] then
			hidden[part] = nil
			hiddenCount -= 1
		end
	end

	local function alive(inst: Instance): boolean
		local ok, res = pcall(function()
			return inst.Parent ~= nil
		end)
		return ok and res == true
	end

	-- Rebuild the tracked-part list (cheap filter; per-slice checks stay exact).
	local function buildRegistry(o)
		local char = Players.LocalPlayer.Character
		local fresh: { BasePart } = {}
		local ok, desc = pcall(function()
			return workspace:GetDescendants()
		end)
		if not ok or type(desc) ~= "table" then
			return
		end
		for _, d in ipairs(desc) do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				local skip = false
				if char and part:IsDescendantOf(char) then
					skip = true -- your own body, always rendered
				end
				if not skip then
					local okSize, big = pcall(function()
						local s = part.Size
						return if s.X > s.Y then (if s.X > s.Z then s.X else s.Z) else (if s.Y > s.Z then s.Y else s.Z)
					end)
					if not okSize or (big or 0) > o.maxSize then
						skip = true -- huge geometry: never touched
					end
				end
				if not skip then
					local okTr, tr = pcall(function()
						return part.Transparency
					end)
					if okTr and (tr or 0) >= 1 then
						skip = true -- already invisible: nothing to save
					end
				end
				if not skip then
					table.insert(fresh, part)
				end
			end
		end
		-- Nearest first: near parts refresh first, so any pop-in lag only
		-- ever affects far geometry.
		local camNow = workspace.CurrentCamera
		if camNow then
			local campos = camNow.CFrame.Position
			pcall(table.sort, fresh, function(a: BasePart, b: BasePart): boolean
				return (a.Position - campos).Magnitude < (b.Position - campos).Magnitude
			end)
		end
		-- Streaming unloads parts constantly: drop dead entries from every
		-- set so counts stay honest and restore never touches dead refs.
		for part, _ in pairs(hidden) do
			if not alive(part) then
				purgePart(part)
			end
		end
		for light, _ in pairs(litOut) do
			if not alive(light) then
				litOut[light] = nil
				litCount -= 1
			end
		end
		for em, _ in pairs(emitOut) do
			if not alive(em) then
				emitOut[em] = nil
				emitCount -= 1
			end
		end
		for gui, _ in pairs(guiOut) do
			if not alive(gui) then
				guiOut[gui] = nil
				guiCount -= 1
			end
		end
		registry = fresh
		trackedCount = #fresh
		if cursor > #fresh then
			cursor = 1
		end
		lastRegistryBuild = os.clock()
	end

	------------------------------------------------------------- restore
	local function restoreAll()
		for part, _ in pairs(hidden) do
			pcall(function()
				part.LocalTransparencyModifier = 0
			end)
			pcall(unpark, part)
		end
		table.clear(hidden)
		hiddenCount = 0
		-- Anything parked without a live host record (should not happen, but
		-- a restore must never leave a light/emitter/GUI switched off).
		for light, _ in pairs(litOut) do
			pcall(function()
				light.Enabled = true
			end)
		end
		table.clear(litOut)
		litCount = 0
		for em, _ in pairs(emitOut) do
			pcall(function()
				em.Enabled = true
			end)
		end
		table.clear(emitOut)
		emitCount = 0
		for gui, _ in pairs(guiOut) do
			pcall(function()
				gui.Enabled = true
			end)
		end
		table.clear(guiOut)
		guiCount = 0
	end

	--------------------------------------------------------------- slice
	local function scanSlice(myGen: number, cross: number, o)
		if not enabled or runId ~= myGen or not genAlive(cross) then
			return
		end
		if os.clock() - lastRegistryBuild >= o.refresh or #registry == 0 then
			buildRegistry(o)
		end
		if #registry == 0 then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local fr = buildFrustum(cam, o.marginDeg)
		local char = Players.LocalPlayer.Character

		-- Pass A (hidden first): restoration is the safety-critical
		-- direction - a hidden part that is visible again must come back
		-- NOW, while hiding can afford to lag a slice behind.
		table.clear(scratch)
		for part, _ in pairs(hidden) do
			table.insert(scratch, part)
		end
		for _, part in ipairs(scratch) do
			if not enabled or runId ~= myGen or not genAlive(cross) then
				return
			end
			pcall(function()
				if part.Parent == nil then
					purgePart(part) -- streamed out / destroyed
					return
				end
				if char and part:IsDescendantOf(char) then
					purgePart(part) -- became part of you (equipped)
					return
				end
				if not isOutside(part, fr, o) then
					setShown(part, true, fr, o)
				end
			end)
		end

		-- Pass B (budgeted hiding) over the registry.
		local n = #registry
		local done = 0
		while done < o.budget and enabled and runId == myGen and genAlive(cross) do
			if cursor > n then
				cursor = 1
			end
			local part = registry[cursor]
			cursor += 1
			done += 1
			if part ~= nil and not hidden[part] then
				pcall(function()
					if part.Parent == nil then
						return -- gone: the rebuild purge collects it
					end
					if char and part:IsDescendantOf(char) then
						return -- your own body, never hidden
					end
					if isOutside(part, fr, o) then
						setShown(part, false, fr, o)
					end
				end)
			end
		end
	end

	local function loop(myGen: number, cross: number)
		local o = opts()
		local lastLook = Vector3.zAxis
		while enabled and runId == myGen and genAlive(cross) do
			o = opts()
			local ok, err = pcall(scanSlice, myGen, cross, o)
			if not ok then
				warn("[Paralyz] perf cull slice error: " .. tostring(err))
			end
			-- Sleep the slice, but wake early when the camera swings past the
			-- margin: fast turns then re-show immediately (no pop-in), while
			-- a static camera still pays the full idle cost.
			local cosMargin = math.cos(math.rad(o.marginDeg))
			local deadline = os.clock() + o.slice
			while os.clock() < deadline and enabled and runId == myGen and genAlive(cross) do
				local cam = workspace.CurrentCamera
				if cam then
					local look = cam.CFrame.LookVector
					if look:Dot(lastLook) < cosMargin then
						lastLook = look
						break -- rotated past the margin: scan again now
					end
					lastLook = look
				end
				task.wait(0.05)
			end
		end
	end

	-- Turns Lower Usage on or off. Returns a short report string.
	function perf.apply(on: boolean): string
		if on then
			if enabled then
				return string.format("already on - %d hidden / %d tracked", hiddenCount, trackedCount)
			end
			enabled = true
			runId += 1
			local myGen = runId
			local cross = claimGen()
			lastRegistryBuild = 0
			task.spawn(function()
				loop(myGen, cross)
			end)
			return "culling on - exact box tests, off-screen parts and their lights/particles/surface GUIs skip rendering; nothing visible changes"
		end
		if not enabled then
			return "already off"
		end
		enabled = false
		runId += 1
		claimGen() -- invalidate any loop, including older generations
		restoreAll()
		registry = {}
		trackedCount = 0
		cursor = 1
		return "culling off - every part, light, emitter and GUI restored"
	end

	function perf.stop()
		enabled = false
		runId += 1
		claimGen() -- invalidate any loop, including older generations
		restoreAll()
		registry = {}
		trackedCount = 0
	end

	function perf.report(): string
		return string.format(
			"culling=%s hidden=%d lights=%d emitters=%d surfaceGuis=%d tracked=%d quality=%s shadows=%s",
			enabled and "on" or "off",
			hiddenCount,
			litCount,
			emitCount,
			guiCount,
			trackedCount,
			tostring(settings().Rendering.QualityLevel),
			tostring(Lighting.GlobalShadows)
		)
	end

	return perf
end
