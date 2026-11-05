-- Pestinha, the desktop pet (github.com/Andersonk01/pestinha, branch hyprland),
-- run and configured through `ryoku-pestinha` and Hub > Desktop > Pestinha.
-- It runs under XWayland: every one of its small windows has the class
-- "pestinha" and a title starting with "pestinha:janela", so they float on
-- every workspace without borders, shadow, blur or animation and never take
-- the focus away from what you are doing.
local K = require("modules.rebind")

hl.window_rule({
    name             = "pestinha-overlay",
    match            = { class = "^pestinha$", title = "^pestinha:janela(:.*)?$" },
    float            = true,
    pin              = true,
    no_focus         = true,
    no_initial_focus = true,
    border_size      = 0,
    rounding         = 0,
    no_shadow        = true,
    no_blur          = true,
    no_anim          = true,
    no_dim           = true,
})

-- panic key: the pet and everything it put on screen vanish at once
-- (Hub > Pestinha > TURN BACK ON, or `ryoku-pestinha religar`, brings it back)
hl.bind(K("CTRL + ALT + SHIFT + B"), hl.dsp.exec_cmd("ryoku-pestinha panic"))

-- login: opens the pet when it is on in the Hub (`autostart` does nothing while
-- it is off). Starts are serialised, so the same hook in user.lua is harmless.
hl.on("hyprland.start", function() hl.exec_cmd("ryoku-pestinha autostart") end)
