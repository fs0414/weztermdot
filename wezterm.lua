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
}

wezterm.on("augment-command-palette", function()
	local entries = {}
	for _, item in ipairs(launcher_choices) do
		table.insert(entries, {
			brief = "Launch: " .. item.label,
			icon = item.icon,
			action = spawn_overlay_pane(item.command),
		})
	end
	return entries
end)

return config
