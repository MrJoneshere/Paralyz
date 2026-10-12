--!strict
-- Paralyz / src/antiafk.luau
-- Keeps an AFK session alive (user order: the hub is meant to run unattended
-- while farming, but Roblox kicked the client after ~20 idle minutes on
-- 2026-10-12 and dropped the whole session).
--
-- How it works: Players.LocalPlayer.Idled fires right before Roblox's
-- inactivity kick. Capturing the virtual input controller and acknowledging
-- with an in-capture right-click cancels the kick - the same mechanism every
-- anti-idle script uses, and the only client-side one that is not a lie
-- (the server never sees input from us; the kick is client-side only).
-- It never touches the camera, never presses a real key, and no game remote
-- is fired - so it cannot trip the namecall kick or move the character.
--
-- Interface: antiafk.start()/stop() plus antiafk.stats() for the menu.

return function(deps)
	local util = deps.util

	local antiafk = {}

	local Players = game:GetService("Players")
	local VirtualUser = game:GetService("VirtualUser")

	local conn: RBXScriptConnection? = nil
	local cancelled = 0
	-- Stable impl table handed to util.singleOwner: the first generation
	-- to start owns the live listener, later generations (after a reload)
	-- delegate start/stop/status to it, so the newest menu steers the one
	-- connection that actually exists.
	local IMPL: any = {}

	local function onIdle()
		cancelled += 1
		local ok = pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
		if ok and util and util.notify then
			util.notify("Anti idle", "idle kick cancelled (#" .. cancelled .. ")")
		end
	end

	function antiafk.start()
		local ctl = util.singleOwner("conn_antiafk", IMPL)
		if ctl ~= IMPL then
			ctl.start() -- an older generation holds the live Idled handler
			return
		end
		if conn then
			return
		end
		conn = Players.LocalPlayer.Idled:Connect(onIdle)
	end

	function antiafk.stop()
		local ctl = util.stopOwner("conn_antiafk", IMPL)
		if ctl == nil then
			return -- nobody is listening
		end
		if ctl ~= IMPL then
			ctl.stop()
			return
		end
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function antiafk.isRunning(): boolean
		local owner = util.ownerOf("conn_antiafk")
		if owner ~= nil and owner ~= IMPL then
			return owner.isRunning()
		end
		return conn ~= nil
	end

	function antiafk.stats(): string
		local owner = util.ownerOf("conn_antiafk")
		if owner ~= nil and owner ~= IMPL then
			return owner.stats()
		end
		return string.format("%d kicks cancelled", cancelled)
	end

	IMPL.start = antiafk.start
	IMPL.stop = antiafk.stop
	IMPL.isRunning = antiafk.isRunning
	IMPL.stats = antiafk.stats

	return antiafk
end
