-- Pull in the wezterm API
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action

config.automatically_reload_config = false
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- set leader
config.leader = { key = 'a',mods="CMD", timeout_milliseconds = 2000 }

-- font size
config.font_size = 14.0
wezterm.font("Hack Nerd Font", {weight="Regular", stretch="Normal", style="Normal"})

-- right status
wezterm.on('update-right-status', function(window)
  window:set_right_status(window:active_workspace())
end)

-- use jp lang
config.use_ime = true

-- opacity
config.window_background_opacity = 0.92
config.macos_window_background_blur = 20

-- color scheme
-- config.color_scheme = 'Aci (Gogh)'
-- config.color_scheme = 'Ef-Deuteranopia-Dark'
-- config.color_scheme = 'ENCOM'
config.color_scheme = 'Ef-Night'

-- tab bar
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.window_decorations = "RESIZE"
config.show_new_tab_button_in_tab_bar = false
config.tab_bar_at_bottom = false
config.colors = {
  tab_bar = {
    inactive_tab_edge = "none",
  },
},
--
wezterm.on("format-tab-title", function(tab)
  local scheme = wezterm.color.get_builtin_schemes()[config.color_scheme]
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

-- tab bar color asnc color_scheme
config.colors = {
  tab_bar = {
    background = wezterm.color.get_builtin_schemes()[config.color_scheme].background,
  },
}

config.keys = {
  -- reload
  {
    key = 'r',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ReloadConfiguration,
  },
  -- close tab
  {
    key = "w",
    mods = "CMD",
    action = act.CloseCurrentPane { confirm = true },
  },
  -- pane split
  {
    key = ",",
    mods = "CMD",
    action = act { SplitVertical = { domain = "CurrentPaneDomain" } },
  },
  {
    key = ".",
    mods = "CMD",
    action = act { SplitHorizontal = { domain = "CurrentPaneDomain" } },
  },
  {
    key = 'LeftArrow',
    mods = 'CMD',
    action = act.ActivatePaneDirection('Left')
  },
  {
    key = 'RightArrow',
    mods = 'CMD',
    action = act.ActivatePaneDirection('Right')
  },
  {
    key = 'UpArrow',
    mods = 'CMD',
    action = act.ActivatePaneDirection('Up')
  },
  {
    key = 'DownArrow',
    mods = 'CMD',
    action = act.ActivatePaneDirection('Down')
  },
  -- workspace
  {
    key = 'LeftArrow',
    mods = 'ALT',
    action = act.SwitchWorkspaceRelative(1)
  },
  {
    key = 'RightArrow',
    mods = 'ALT',
    action = act.SwitchWorkspaceRelative(-1)
  },
  {
    key = '9',
    mods = 'ALT',
    action = act.ShowLauncherArgs {
      flags = 'FUZZY|WORKSPACES'
    }
  },
}
return config, {}
