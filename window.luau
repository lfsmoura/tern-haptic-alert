--!strict
-- MX Master 4 haptics for Tern agents, after lfsmoura/herdr-haptic-alert:
-- a damped pulse when an agent finishes, a collision pulse when it needs you.
-- `haptics.mjs` (node-hid, HID++ 0x19b0) does the device work.

local agents = require("./agents")

-- Waveforms: "damp-state-change" or "subtle-collision"; false silences one.
local CONFIG: { done: string | false, blocked: string | false, serial: string? } = {
	done = "damp-state-change",
	blocked = "subtle-collision",
	-- Exact serialNumber from "Haptic: list mice" when several are connected.
	serial = nil,
}

local HOME = tern.getenv("HOME") or ""
-- Windows started from the Dock have a PATH without mise's shims.
local NODE = { HOME .. "/.local/share/mise/shims/node", "/opt/homebrew/bin/node", "/usr/local/bin/node", "node" }
local NPM = { HOME .. "/.local/share/mise/shims/npm", "/opt/homebrew/bin/npm", "/usr/local/bin/npm", "npm" }

local playing = false
local installing = false
local last_error: string? = nil

local function find(candidates: { string }): string?
	for _, c in candidates do
		if c == "node" or c == "npm" or tern.fs.exists(c) then
			return c
		end
	end
	return nil
end

local function first_line(s: string): string
	return string.match(s, "[^\n]+") or s
end

-- node-hid is a native module: install it on first use.
local function ensure_deps(cx: WindowCx, done: () -> ())
	if tern.fs.exists(tern.plugin.dir .. "/node_modules/node-hid") then
		done()
		return
	end
	if installing then
		return
	end
	local npm = find(NPM)
	if not npm then
		cx:toast("error", "Haptic Alert needs npm", "Install Node.js 22+.")
		return
	end
	installing = true
	cx:toast("info", "Haptic Alert: installing node-hid…")
	tern.process.run({ npm, "install", "--no-audit", "--no-fund" }, { cwd = tern.plugin.dir, timeout_ms = 180000 }, function(r, cx2)
		installing = false
		if r.status == 0 then
			done()
		elseif cx2 then
			cx2:toast("error", "Haptic Alert: npm install failed", first_line(r.stderr))
		end
	end)
end

-- Plays `waveform`; errors toast once until they change or a play succeeds.
local function play(cx: WindowCx, waveform: string, test: boolean)
	if playing then
		return
	end
	local node = find(NODE)
	if not node then
		cx:toast("error", "Haptic Alert needs node", "Install Node.js 22+.")
		return
	end
	ensure_deps(cx, function()
		playing = true
		local argv = { node, "cli.mjs", "play", waveform }
		if CONFIG.serial then
			table.insert(argv, CONFIG.serial)
		end
		tern.process.run(argv, { cwd = tern.plugin.dir, timeout_ms = 10000 }, function(r, cx2)
			playing = false
			if r.status == 0 then
				last_error = nil
				if test and cx2 then
					cx2:toast("success", "Haptic played", waveform)
				end
				return
			end
			local err = first_line(if r.timed_out then "mouse did not answer within 10 s" else r.stderr)
			tern.log.warn("haptic-alert:", err)
			if cx2 and (test or err ~= last_error) then
				cx2:toast("error", "Haptic Alert", err)
			end
			last_error = err
		end)
	end)
end

agents.watch(function(change, cx)
	if change.to ~= "done" and change.to ~= "blocked" then
		return
	end
	local waveform = CONFIG[change.to]
	if waveform then
		play(cx, waveform, false)
	end
end)

local function test(status: "done" | "blocked"): (cx: WindowCx) -> ()
	return function(cx)
		local waveform = CONFIG[status]
		if waveform then
			play(cx, waveform, true)
		else
			cx:toast("info", "Haptic for " .. status .. " is off")
		end
	end
end

tern.command({ id = "test", title = "Haptic: test done", icon = "bell", run = test("done") })
tern.command({ id = "test-blocked", title = "Haptic: test blocked", icon = "bell", run = test("blocked") })
tern.command({
	id = "list",
	title = "Haptic: list mice",
	icon = "bell",
	run = function(cx)
		local node = find(NODE)
		if not node then
			cx:toast("error", "Haptic Alert needs node")
			return
		end
		ensure_deps(cx, function()
			tern.process.run({ node, "cli.mjs", "list" }, { cwd = tern.plugin.dir, timeout_ms = 10000 }, function(r, cx2)
				if not cx2 then
					return
				end
				local ok, list = pcall(tern.json.decode, r.stdout)
				if r.status ~= 0 or not ok then
					cx2:toast("error", "Haptic: list failed", first_line(r.stderr))
					return
				end
				local names = {}
				for _, d in list do
					table.insert(names, tostring(d.product) .. " — serial " .. tostring(d.serialNumber))
				end
				if #names == 0 then
					cx2:toast("info", "No Bluetooth MX Master 4 found")
				else
					cx2:copy(table.concat(names, "\n"))
					cx2:toast("success", #names .. " mouse(s), copied", table.concat(names, "; "))
				end
			end)
		end)
	end,
})
