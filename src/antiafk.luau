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
	-- Ownership claim for the single-owner listener pattern: the env token
	-- stops OTHER generations from stacking, this flag keeps stop() ->
	-- start() working inside the owning generation.
	local owns = false

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
		if conn then
			return
		end
		if not owns then
			-- Reload-safety: stacked Idled handlers are harmless but each
			-- would toast; oldest generation owns it forever.
			local env: any = getgenv()
			if env["ParalyzOwn_conn_antiafk"] then
				return
			end
			env["ParalyzOwn_conn_antiafk"] = true
			owns = true
		end
		conn = Players.LocalPlayer.Idled:Connect(onIdle)
	end

	function antiafk.stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function antiafk.isRunning(): boolean
		return conn ~= nil
	end

	function antiafk.stats(): string
		return string.format("%d kicks cancelled", cancelled)
	end

	return antiafk
end
