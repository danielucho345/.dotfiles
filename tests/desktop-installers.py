#!/usr/bin/env python3
"""Exercise real installers in disposable homes; never contact a desktop session."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopInstallers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-desktop-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.mock = self.base / 'mock'
        self.mock.mkdir()
        scripts = {
            'omarchy': '''#!/bin/bash
case "$*" in
  'plugin list --json') echo '[{"id":"daniel.background"},{"id":"daniel.window-switcher"}]' ;;
  'plugin validate '*) test -f "$3/manifest.json" ;;
  'plugin enable '*|'theme set '*) exit 0 ;;
  *) exit 1 ;;
esac
''',
            'omarchy-shell': '''#!/bin/bash
[[ "$*" != 'shell ping' || "${TEST_OFFLINE:-false}" != true ]]
''',
            'hyprctl': '''#!/bin/bash
case "$*" in
  reload) exit 0 ;;
  configerrors) printf '%s' "${TEST_CONFIG_ERRORS:-}" ;;
  *) exit 1 ;;
esac
''',
        }
        for name, script in scripts.items():
            path = self.mock / name
            path.write_text(script)
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        XDG_DATA_HOME=str(self.home / '.local/share'),
                        XDG_STATE_HOME=str(self.home / '.local/state'),
                        PATH=f'{self.mock}:{os.environ["PATH"]}')
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.env.pop('STOW_DIR', None)
        self.config = self.home / '.config'
        self.state = self.home / '.local/state/omarchy/monitor-backgrounds.json'
        self.shell = self.config / 'omarchy/shell.json'

    def run_script(self, script, *args, ok=True, root=ROOT):
        result = subprocess.run(['bash', str(root / script), *args], env=self.env,
                                text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def write_json(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def mock_chromium(self):
        command = self.mock / 'chromium'
        command.write_text('#!/bin/sh\nprintf "%s\\0" "$@" > "$TEST_CHROMIUM_ARGS"\n')
        command.chmod(0o755)

    def test_whatsapp_install_backup_repeat_and_dry_run(self):
        self.mock_chromium()
        launcher = self.home / '.local/share/applications/WhatsApp.desktop'
        launcher.parent.mkdir(parents=True)
        original = 'original WhatsApp launcher\n'
        launcher.write_text(original)
        flags = self.config / 'chromium-flags.conf'
        flags.parent.mkdir(parents=True)
        flags.write_text('--ozone-platform=wayland\n')
        before = self.snapshot()
        self.run_script('install-all.sh', '--dry-run', 'whatsapp')
        self.assertEqual(before, self.snapshot())
        self.run_script('install-all.sh', 'whatsapp')
        self.assertEqual(launcher.read_bytes(), (ROOT / 'desktop-apps/WhatsApp.desktop').read_bytes())
        backup = next(launcher.parent.glob('WhatsApp.desktop.bak.*/WhatsApp.desktop'))
        self.assertEqual(backup.read_text(), original)
        self.assertEqual(flags.read_text(), '--ozone-platform=wayland\n')
        self.assertFalse((self.config / 'chromium-whatsapp').exists())
        before = self.snapshot()
        self.run_script('install/install-whatsapp.sh')
        self.assertEqual(before, self.snapshot())

    def test_whatsapp_desktop_launch_uses_isolated_profile(self):
        try:
            from gi.repository import GLib
        except ImportError:
            self.skipTest('PyGObject is required to parse desktop Exec values')
        self.mock_chromium()
        desktop = GLib.KeyFile()
        desktop.load_from_file(str(ROOT / 'desktop-apps/WhatsApp.desktop'), GLib.KeyFileFlags.NONE)
        _, argv = GLib.shell_parse_argv(desktop.get_string('Desktop Entry', 'Exec'))
        capture = self.base / 'chromium-args'
        for custom_config in (None, self.home / 'config with spaces $literal `text`'):
            with self.subTest(custom_config=custom_config):
                env = dict(self.env, TEST_CHROMIUM_ARGS=str(capture))
                env.pop('XDG_CONFIG_HOME', None)
                if custom_config is not None:
                    env['XDG_CONFIG_HOME'] = str(custom_config)
                subprocess.run(argv, env=env, check=True)
                args = capture.read_bytes().decode().rstrip('\0').split('\0')
                config = custom_config if custom_config is not None else self.config
                self.assertEqual(args, [f'--user-data-dir={config}/chromium-whatsapp',
                                        '--disable-gpu', '--app=https://web.whatsapp.com/'])

    def snapshot(self):
        return [(str(p.relative_to(self.home)),
                 ('link', os.readlink(p)) if p.is_symlink() else
                 ('dir',) if p.is_dir() else ('file', p.read_bytes(), p.stat().st_mtime_ns))
                for p in sorted(self.home.rglob('*'))]

    def hypr_files(self):
        hypr = self.config / 'hypr'
        hypr.mkdir(parents=True, exist_ok=True)
        main = hypr / 'hyprland.lua'
        main.write_text('-- preserve main\nrequire("hypr.input")\nrequire("hyprland-overrides")\n')
        bindings = hypr / 'bindings.lua'
        bindings.write_text('-- preserve bindings\ndofile(os.getenv("HOME") .. "/.config/hypr/hyprland-overrides.lua")\n'
                            "require ( 'hypr.hyprland-overrides' ) -- duplicate\n")
        return main, bindings

    def test_shell_merge_conflicts_backups_and_repeat(self):
        self.write_json(self.shell, {'version': 1, 'bar': {'position': 'bottom'},
                                     'idle': {'lock': 999}, 'plugins': [{'id': 'custom'}],
                                     'disabledPlugins': ['example'], 'other': {'keep': True}})
        before = self.snapshot()
        self.run_script('install-all.sh', '--dry-run', 'desktop-settings', ok=False)
        self.run_script('install-all.sh', '--dry-run', '--force', 'desktop-settings')
        self.assertEqual(before, self.snapshot())
        self.run_script('install-all.sh', 'desktop-settings', ok=False)
        self.assertEqual(before, self.snapshot())
        self.run_script('install-all.sh', '--force', 'desktop-settings')
        result = json.loads(self.shell.read_text())
        template = json.loads((ROOT / 'defaults/omarchy-shell.json').read_text())
        self.assertEqual(result['bar'], template['bar'])
        self.assertEqual(result['idle'], template['idle'])
        self.assertEqual(result['plugins'], [{'id': 'custom'}])
        self.assertEqual(result['disabledPlugins'], ['example'])
        self.assertEqual(result['other'], {'keep': True})
        self.assertFalse(self.shell.is_symlink())
        backup = next(self.shell.parent.glob('shell.json.bak.*/shell.json'))
        self.assertEqual(json.loads(backup.read_text())['idle']['lock'], 999)
        before = self.snapshot()
        self.run_script('install-all.sh', 'desktop-settings')
        self.assertEqual(before, self.snapshot())

    def test_shell_fresh_invalid_and_symlink(self):
        self.run_script('install-all.sh', 'desktop-settings')
        self.assertEqual(json.loads(self.shell.read_text())['plugins'], [])
        self.shell.write_text('invalid')
        before = self.snapshot()
        self.run_script('install-all.sh', '--force', 'desktop-settings', ok=False)
        self.assertEqual(before, self.snapshot())
        self.shell.unlink()
        external = self.home / 'original-shell.json'
        external.write_text((ROOT / 'defaults/omarchy-shell.json').read_text())
        self.shell.symlink_to(external)
        original = external.read_bytes()
        self.run_script('install-all.sh', 'desktop-settings', ok=False)
        self.run_script('install-all.sh', '--force', 'desktop-settings')
        self.assertFalse(self.shell.is_symlink())
        self.assertEqual(external.read_bytes(), original)

    def test_wallpapers_fresh_repeat_and_dry_run(self):
        before = self.snapshot()
        self.run_script('install-all.sh', '--dry-run', 'wallpapers')
        self.assertEqual(before, self.snapshot())
        self.run_script('install-all.sh', 'wallpapers')
        state = json.loads(self.state.read_text())
        defaults = json.loads((ROOT / 'defaults/monitor-backgrounds.json').read_text())
        for output, name in defaults['outputs'].items():
            self.assertEqual(state['outputs'][output], str(self.config / 'omarchy/backgrounds/tokyo-night' / name))
            self.assertTrue(Path(state['outputs'][output]).is_file())
        before = self.snapshot()
        self.run_script('install-all.sh', 'wallpapers')
        self.assertEqual(before, self.snapshot())

    def test_wallpaper_partial_state_preserved_and_backed_up(self):
        original = {'version': 1, 'outputs': {'DP-1': '/my/custom.jpg', 'HDMI-A-1': '/other.jpg'}, 'other': 42}
        self.write_json(self.state, original)
        self.run_script('install-all.sh', 'wallpapers')
        seeded = json.loads(self.state.read_text())
        self.assertEqual(seeded['outputs']['DP-1'], '/my/custom.jpg')
        self.assertEqual(seeded['outputs']['HDMI-A-1'], '/other.jpg')
        self.assertEqual(seeded['other'], 42)
        self.assertIn('DP-2', seeded['outputs'])
        backup = next(self.state.parent.glob('monitor-backgrounds.json.bak.*/monitor-backgrounds.json'))
        self.assertEqual(json.loads(backup.read_text()), original)

    def test_wallpaper_invalid_state_and_conflicting_link_do_not_mutate(self):
        self.write_json(self.state, {'version': 1, 'outputs': {'DP-1': 123}})
        before = self.snapshot()
        self.run_script('install-all.sh', 'wallpapers', ok=False)
        self.assertEqual(before, self.snapshot())
        self.state.unlink()
        helper = self.home / '.local/bin/wallpaper-monitor'
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_text('user owned')
        before = self.snapshot()
        self.run_script('install-all.sh', 'wallpapers', ok=False)
        self.assertEqual(before, self.snapshot())

    def test_relocated_checkout_and_invalid_defaults(self):
        relocated = self.base / 'another checkout'
        shutil.copytree(ROOT, relocated, ignore=shutil.ignore_patterns('.git', '.agents', '.aws', '.codex', '__pycache__'))
        manifest = relocated / 'defaults/monitor-backgrounds.json'
        original = manifest.read_text()
        self.write_json(manifest, {'version': 1, 'outputs': {'DP-1': '../outside.jpg'}})
        before = self.snapshot()
        self.run_script('install-all.sh', 'wallpapers', root=relocated, ok=False)
        self.assertEqual(before, self.snapshot())
        manifest.write_text(original)
        self.run_script('install-all.sh', 'wallpapers', root=relocated)
        for image in json.loads(self.state.read_text())['outputs'].values():
            self.assertTrue(str(Path(image).resolve()).startswith(str(relocated)))
            self.assertNotIn('/home/daniel/', image)

    def test_hyprland_duplicate_loads_dry_run_backups_repeat(self):
        main, bindings = self.hypr_files()
        before = self.snapshot()
        self.run_script('install-all.sh', '--dry-run', 'hyprland')
        self.assertEqual(before, self.snapshot())  # override hasn't been stowed yet
        self.run_script('install-dotfiles.sh', '--force', '--only', 'hypr')
        original_main, original_bindings = main.read_text(), bindings.read_text()
        self.env['TEST_OFFLINE'] = 'true'
        self.run_script('install-all.sh', 'hyprland')
        self.assertEqual(main.read_text().count('hypr.hyprland-overrides'), 1)
        self.assertNotIn('hyprland-overrides', bindings.read_text())
        self.assertIn('-- preserve bindings', bindings.read_text())
        backups = next(main.parent.glob('dotfiles.bak.*'))
        self.assertEqual((backups / main.name).read_text(), original_main)
        self.assertEqual((backups / bindings.name).read_text(), original_bindings)
        before = self.snapshot()
        self.run_script('install-all.sh', 'hyprland')
        self.assertEqual(before, self.snapshot())

    def test_hyprland_legacy_and_error_detection(self):
        hypr = self.config / 'hypr'
        hypr.mkdir(parents=True)
        legacy = hypr / 'hyprland.conf'
        line = f'source = {ROOT}/hyprland-overrides.conf'
        legacy.write_text(f'# keep\n{line}\n{line}\n')
        self.env['HYPRLAND_INSTANCE_SIGNATURE'] = 'test'
        self.run_script('install-all.sh', 'hyprland')
        self.assertEqual(legacy.read_text().count(line), 1)
        self.env['TEST_CONFIG_ERRORS'] = 'broken configuration'
        self.run_script('install-all.sh', 'hyprland', ok=False)

    def test_all_keeps_desktop_opt_in(self):
        for command in ('pacman', 'yay'):
            stub = self.mock / command
            stub.write_text('#!/bin/bash\nexit 0\n')
            stub.chmod(0o755)
        before = self.snapshot()
        result = self.run_script('install-all.sh', '--dry-run', 'all')
        self.assertNotIn('Would seed missing', result.stdout)
        self.assertNotIn('normalize override loads', result.stdout)
        self.assertFalse(self.shell.exists())
        self.assertFalse(self.state.exists())
        self.assertEqual(before, self.snapshot())

    def test_lua_reload_has_one_wallpaper_binding(self):
        script = r'''package.path = os.getenv("TEST_ROOT") .. "/config/?.lua;" .. package.path
local bindings = {}
hl = {
  unbind = function(key) bindings[key] = {} end,
  workspace_rule = function(_) end,
  config = function(settings)
    assert(settings.input.kb_layout == "us,es")
    assert(settings.input.kb_options == "compose:caps,shift:both_capslock_cancel,grp:lctrl_lalt_toggle")
  end,
}
o = {bind = function(key, _, command)
  bindings[key] = bindings[key] or {}
  table.insert(bindings[key], command)
end}
for _ = 1, 2 do
  package.loaded["hypr.hyprland-overrides"] = nil
  require("hypr.hyprland-overrides")
  assert(#bindings["SUPER + CTRL + SHIFT + code:65"] == 1)
  assert(bindings["SUPER + CTRL + SHIFT + code:65"][1] == "wallpaper-monitor select")
end
require("hypr.input")
'''
        result = subprocess.run(['lua', '-'], input=script, text=True,
                                env=dict(self.env, TEST_ROOT=str(ROOT)), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dotfiles_fresh_repeat_force_and_targeted_preservation(self):
        alacritty = self.config / 'alacritty/alacritty.toml'
        alacritty.parent.mkdir(parents=True)
        alacritty.write_text('old settings')
        unrelated = self.config / 'alacritty/keep.txt'
        unrelated.write_text('keep')
        before = self.snapshot()
        self.run_script('install-dotfiles.sh', '--only', 'alacritty', ok=False)
        self.run_script('install-dotfiles.sh', '--dry-run', '--force', '--only', 'alacritty')
        self.assertEqual(before, self.snapshot())
        self.run_script('install-dotfiles.sh', '--force', '--only', 'alacritty', '--only', 'tmux')
        self.assertTrue(alacritty.is_symlink())
        self.assertEqual(unrelated.read_text(), 'keep')
        self.assertFalse((self.config / 'systemd').exists())
        backup = next((self.home / '.local/state/dotfiles-backups').glob('*/alacritty/alacritty.toml'))
        self.assertEqual(backup.read_text(), 'old settings')
        before = self.snapshot()
        self.run_script('install-dotfiles.sh', '--only', 'alacritty', '--only', 'tmux')
        self.assertEqual(before, self.snapshot())

    def test_dotfiles_force_accepts_absolute_links_without_moving_sources(self):
        relocated = self.base / 'checkout'
        shutil.copytree(ROOT, relocated, ignore=shutil.ignore_patterns('.git', '.agents', '.aws', '.codex', '__pycache__'))
        plugins = self.config / 'omarchy/plugins'
        plugins.mkdir(parents=True)
        source_plugin = relocated / 'config/omarchy/plugins/daniel.window-switcher'
        (plugins / source_plugin.name).symlink_to(source_plugin)
        units = self.config / 'systemd/user'
        units.mkdir(parents=True)
        for name in ('aw-awatcher.service', 'aw-server-rust.service'):
            (units / name).symlink_to(relocated / 'config/systemd/user' / name)
        (units / 'unrelated.service').write_text('keep')
        sources = {p: p.read_bytes() for p in (relocated / 'config').rglob('*') if p.is_file()}
        before = self.snapshot()
        args = ('--force', '--only', 'omarchy', '--only', 'systemd')
        self.run_script('install-dotfiles.sh', '--dry-run', *args, root=relocated)
        self.assertEqual(before, self.snapshot())
        self.run_script('install-dotfiles.sh', *args, root=relocated)
        self.assertEqual(sources, {p: p.read_bytes() for p in sources})
        self.assertEqual((units / 'unrelated.service').read_text(), 'keep')
        self.assertEqual((plugins / source_plugin.name).resolve(), source_plugin)
        self.assertFalse((self.home / '.local/state/dotfiles-backups').exists())
        before = self.snapshot()
        self.run_script('install-dotfiles.sh', *args, root=relocated)
        self.assertEqual(before, self.snapshot())

    def test_dotfiles_force_keeps_linked_package_root(self):
        self.config.mkdir()
        (self.config / 'tmux').symlink_to(ROOT / 'config/tmux')
        before = self.snapshot()
        self.run_script('install-dotfiles.sh', '--force', '--only', 'tmux')
        self.assertEqual(before, self.snapshot())


if __name__ == '__main__':
    unittest.main(verbosity=2)
