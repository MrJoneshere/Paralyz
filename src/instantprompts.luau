--!strict
-- Paralyz / src/instantprompts.luau
-- Instant proximity prompts - a direct port of Infinite Yield's ;instantpp.
--
-- IY does NOT zero HoldDuration. Its trick: connect
-- ProximityPromptService.PromptButtonHoldBegan and call the executor builtin
-- fireproximityprompt() the moment the player BEGINS holding a prompt, so the
-- hold never has to finish. uninstantpp disconnects; this module exposes the
-- same thing as start/stop behind the Settings -> Instant Prompts toggle.
--
-- Notes:
--   * fireproximityprompt is a Real builtin (confirmed via search-api).
--   * The connection callback is pcall-wrapped so a bad prompt can never kill
--     the connection or spam errors.
--   * start() is idempotent (conn guard), stop() disconnects cleanly - same
--     reconnect-first shape as IY's execCmd("uninstantproximityprompts").
--   * util.singleOwner: after a live-reload the OLDER generation still holds
--     the one real connection, so start/stop/isRunning delegate to it and the
--     reloaded menu keeps steering that connection instead of a dead local.

return function(deps)
	local util = deps.util

	local instantprompts = {}

	local PPS = game:GetService("ProximityPromptService")
	local conn: RBXScriptConnection? = nil
	-- Stable impl table handed to util.singleOwner (owner identity).
	local IMPL: any = {}

	local function fire(prompt: ProximityPrompt)
		pcall(fireproximityprompt, prompt)
	end

	function instantprompts.start()
		local ctl = util.singleOwner("conn_instantprompts", IMPL)
		if ctl ~= IMPL then
			ctl.start() -- an older generation holds the live connection
			return
		end
		if conn then
			return
		end
		if type(fireproximityprompt) ~= "function" then
			if util and util.notify then
				util.notify("Instant Prompts", "this executor has no fireproximityprompt")
			end
			return
		end
		conn = PPS.PromptButtonHoldBegan:Connect(fire)
	end

	function instantprompts.stop()
		local ctl = util.stopOwner("conn_instantprompts", IMPL)
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

	function instantprompts.isRunning(): boolean
		local owner = util.ownerOf("conn_instantprompts")
		if owner ~= nil and owner ~= IMPL then
			return owner.isRunning()
		end
		return conn ~= nil
	end

	IMPL.start = instantprompts.start
	IMPL.stop = instantprompts.stop
	IMPL.isRunning = instantprompts.isRunning

	return instantprompts
end
