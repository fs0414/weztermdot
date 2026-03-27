local wezterm = require("wezterm")
local config = wezterm.config_builder()
local act = wezterm.action

-- Helper function to run a command in an overlay pane
local function spawn_overlay_pane(command)
	return wezterm.action_callback(function(window, pane)
		local new_pane = pane:split({
			direction = "Bottom",
			args = { os.getenv("SHELL") or "/bin/zsh", "-ic", command },
		})
		window:perform_action(act.TogglePaneZoomState, new_pane)
	end)
end

-- Process-tree-aware agent scanner with caching
local agent_cache = { result = {}, timestamp = 0 }
local CACHE_TTL = 3
local STATUS_ICON = { idle = "○", running = "●", unknown = "?" }

-- Walk ppid chain to find a claude ancestor pid
local function find_claude_ancestor(pid, procs, claude_pids)
	local visited = {}
	local current = pid
	while current and current > 1 and not visited[current] do
		visited[current] = true
		if claude_pids[current] then
			return current
		end
		local info = procs[current]
		if not info then
			break
		end
		current = info.ppid
	end
	return nil
end

-- Detect agent status for a single pane; returns status string or nil
local function detect_pane_agent(p, procs, claude_pids, claude_status)
	local ok_info, fg_info = pcall(function()
		return p:get_foreground_process_info()
	end)
	local fg_pid = ok_info and fg_info and fg_info.pid

	if fg_pid and procs[fg_pid] then
		local cpid = find_claude_ancestor(fg_pid, procs, claude_pids)
		return cpid and (claude_status[cpid] or "idle") or nil
	end

	-- Fallback: use process name matching
	local proc_path = p:get_foreground_process_name() or ""
	local proc_name = proc_path:match("([^/]+)$") or proc_path

	if proc_name:find("claude") then
		return "idle"
	end

	for pid, info in pairs(procs) do
		if info.name == proc_name or info.fullpath == proc_path then
			local cpid = find_claude_ancestor(pid, procs, claude_pids)
			if cpid then
				return claude_status[cpid] or "idle"
			end
		end
	end
	return nil
end

local function scan_agent_panes()
	local now = os.time()
	if now - agent_cache.timestamp < CACHE_TTL then
		return agent_cache.result
	end

	-- Build pid → {ppid, name} map and children reverse index via ps
	local ok, stdout = wezterm.run_child_process({ "ps", "-eo", "pid,ppid,comm" })
	local procs = {}
	local children = {} -- ppid → [pid, ...]
	local claude_pids = {}
	if ok and stdout then
		for line in stdout:gmatch("[^\n]+") do
			local pid_s, ppid_s, comm = line:match("(%d+)%s+(%d+)%s+(.+)")
			if pid_s then
				local pid = tonumber(pid_s)
				local ppid = tonumber(ppid_s)
				local name = comm:gsub("^%s+", ""):gsub("%s+$", "")
				local basename = name:match("([^/]+)$") or name
				procs[pid] = { ppid = ppid, name = basename, fullpath = name }
				if not children[ppid] then
					children[ppid] = {}
				end
				table.insert(children[ppid], pid)
				if basename:find("claude") then
					claude_pids[pid] = true
				end
			end
		end
	end

	-- Determine claude's status via children index.
	-- Claude Code spawns caffeinate while running and kills it when idle.
	local claude_status = {}
	for cpid in pairs(claude_pids) do
		local is_active = false
		for _, child_pid in ipairs(children[cpid] or {}) do
			if procs[child_pid].name == "caffeinate" then
				is_active = true
				break
			end
		end
		claude_status[cpid] = is_active and "running" or "idle"
	end

	-- Scan all panes
	local agents = {}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		local workspace = mux_win:get_workspace()
		for _, tab in ipairs(mux_win:tabs()) do
			for _, p in ipairs(tab:panes()) do
				local status = detect_pane_agent(p, procs, claude_pids, claude_status)
				if status then
					local cwd = p:get_current_working_dir()
					local dir = cwd and cwd.file_path or "unknown"
					table.insert(agents, {
						workspace = workspace,
						pane_id = p:pane_id(),
						project = dir:match("([^/]+)$") or dir,
						dir = dir,
						status = status,
					})
				end
			end
		end
	end

	agent_cache.result = agents
	agent_cache.timestamp = now
	return agents
end

-- Action: switch to the given workspace
local function switch_to_workspace(ws)
	return wezterm.action_callback(function(win, p)
		win:perform_action(act.SwitchToWorkspace({ name = ws }), p)
	end)
end

-- Agent dashboard: show all running agents via InputSelector, jump to selected
local function open_agent_dashboard()
	return wezterm.action_callback(function(window, pane)
		agent_cache.timestamp = 0
		local agents = scan_agent_panes()
		if #agents == 0 then
			window:toast_notification("wezterm", "No running agents", nil, 3000)
			return
		end

		local choices = {}
		for _, agent in ipairs(agents) do
			table.insert(choices, {
				label = string.format(
					"%s %s [%s] %s  (%s)",
					STATUS_ICON[agent.status] or "?",
					agent.status,
					agent.workspace,
					agent.project,
					agent.dir
				),
				id = agent.workspace,
			})
		end

		window:perform_action(act.InputSelector({
			title = string.format("Running Agents (%d)", #agents),
			choices = choices,
			action = wezterm.action_callback(function(win, p, id)
				if id then
					win:perform_action(act.SwitchToWorkspace({ name = id }), p)
				end
			end),
		}), pane)
	end)
end

config.automatically_reload_config = true
config.hyperlink_rules = wezterm.default_hyperlink_rules()

config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 2001 }

config.font_size = 14.0
config.font = wezterm.font("Hack Nerd Font", { weight = "Regular", stretch = "Normal", style = "Normal" })

wezterm.on("update-right-status", function(window)
	window:set_right_status(window:active_workspace())
end)

config.use_ime = true

config.window_background_opacity = 0.92
config.macos_window_background_blur = 20

config.color_scheme = "Ef-Night"

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.window_decorations = "RESIZE"
config.show_new_tab_button_in_tab_bar = false

local scheme = wezterm.color.get_builtin_schemes()[config.color_scheme]

config.colors = {
	tab_bar = {
		inactive_tab_edge = "none",
		background = scheme.background,
	},
}

wezterm.on("format-tab-title", function(tab)
	local background = scheme.background
	local foreground = scheme.foreground

	if tab.is_active then
		foreground = scheme.brights[8]
	end

	return {
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
	}
end)

-- Launcher choices
local launcher_choices = {
	{ label = "Neovim", command = "nvim", icon = "md_file_edit" },
	{ label = "Lazygit", command = "lazygit", icon = "md_git" },
	{ label = "Zsh", command = "zsh", icon = "md_console" },
}

config.keys = {
	{ key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
	{ key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = ",", mods = "CMD", action = act({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
	{ key = ".", mods = "CMD", action = act({ SplitHorizontal = { domain = "CurrentPaneDomain" } }) },
	{ key = "LeftArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow", mods = "SHIFT", action = act.ActivatePaneDirection("Down") },
	{ key = "LeftArrow", mods = "CMD", action = act.SwitchWorkspaceRelative(-1) },
	{ key = "RightArrow", mods = "CMD", action = act.SwitchWorkspaceRelative(1) },
	{ key = "9", mods = "ALT", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
	{ key = "Enter", mods = "SHIFT", action = act.SendString("\n") },
	{ key = "n", mods = "CTRL", action = act.TogglePaneZoomState },
	-- Select a command via fuzzy finder and run it in an overlay pane
	{
		key = "l",
		mods = "LEADER",
		action = act.InputSelector({
			title = "Launcher",
			choices = (function()
				local choices = {}
				for _, item in ipairs(launcher_choices) do
					table.insert(choices, { label = item.label })
				end
				return choices
			end)(),
			action = wezterm.action_callback(function(window, pane, _id, label)
				if not label then
					return
				end
				for _, item in ipairs(launcher_choices) do
					if item.label == label then
						local new_pane = pane:split({
							direction = "Bottom",
							args = { os.getenv("SHELL") or "/bin/zsh", "-ic", item.command },
						})
						window:perform_action(act.TogglePaneZoomState, new_pane)
						return
					end
				end
			end),
		}),
	},
	-- Agent dashboard: list all running agents across workspaces
	{
		key = "a",
		mods = "LEADER",
		action = open_agent_dashboard(),
	},
}

wezterm.on("augment-command-palette", function()
	local entries = {
		{
			brief = "Agent Dashboard",
			icon = "md_robot",
			action = open_agent_dashboard(),
		},
	}
	for _, item in ipairs(launcher_choices) do
		table.insert(entries, {
			brief = "Launch: " .. item.label,
			icon = item.icon,
			action = spawn_overlay_pane(item.command),
		})
	end

	-- Use cached results (updated every 3s by status bar) to avoid blocking the palette
	for _, agent in ipairs(agent_cache.result) do
		table.insert(entries, {
			brief = string.format(
				"%s %s Agent: %s [%s]",
				STATUS_ICON[agent.status] or "?",
				agent.status,
				agent.project,
				agent.workspace
			),
			icon = "md_robot_outline",
			action = switch_to_workspace(agent.workspace),
		})
	end

	return entries
end)

return config
