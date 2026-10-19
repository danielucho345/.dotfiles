-- Switch between US and Spanish (Spain) with Left Ctrl + Left Alt.
hl.config({
  input = {
    kb_layout = "us,es",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:lctrl_lalt_toggle",
  },
})
