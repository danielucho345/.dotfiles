#!/usr/bin/env python3
"""Complete installs and plugin restoration in disposable homes, with no network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CompleteConfig(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='dotfiles-complete-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.repo = self.base / 'dotfiles'
        (self.repo / 'install').mkdir(parents=True)
        self.mock = self.base / 'mock'
        self.mock.mkdir()
        self.log = self.base / 'commands'
        self.catalog = self.base / 'catalog.json'
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        XDG_DATA_HOME=str(self.home / '.local/share'),
                        XDG_STATE_HOME=str(self.home / '.local/state'),
                        PATH=f'{self.mock}:{os.environ["PATH"]}',
                        TEST_LOG=str(self.log), TEST_CATALOG=str(self.catalog),
                        GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.env.pop('STOW_DIR', None)
        self.plugins = self.home / '.config/omarchy/plugins'
        self.shell = self.plugins.parent / 'shell.json'
        self.cache = self.home / '.local/share/dotfiles/omarchy-plugins'
        self.copy('install-all.sh')
        self.copy('install/install-plugins.sh')
        self.write_command('omarchy-shell', '''#!/bin/bash
[[ "${TEST_OFFLINE:-false}" != true ]]
''')
        self.write_command('omarchy', '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
catalog = pathlib.Path(os.environ['TEST_CATALOG'])
if args[:2] == ['plugin', 'validate']:
    plugin = pathlib.Path(args[2])
    data = json.loads((plugin / 'manifest.json').read_text())
    sys.exit(0 if data['schemaVersion'] == 1 and
             all((plugin / ep).is_file() for ep in data['entryPoints'].values()) else 1)
if args == ['plugin', 'list', '--json']:
    data = json.loads(catalog.read_text())
    if os.environ.get('TEST_UNDISCOVERED'):
        data = [p for p in data if p['id'] != 'custom.media']
    print(json.dumps(data))
    sys.exit(0)
if args[:2] in (['plugin', 'enable'], ['plugin', 'disable']):
    with open(os.environ['TEST_LOG'], 'a') as log:
        log.write(' '.join(args) + '\\n')
    if os.environ.get('TEST_NO_STATE_CHANGE'):
        sys.exit(0)
    data = json.loads(catalog.read_text())
    for plugin in data:
        if plugin['id'] == args[2]:
            plugin['enabled'] = args[1] == 'enable'
    catalog.write_text(json.dumps(data))
    config = pathlib.Path(os.environ['XDG_CONFIG_HOME']) / 'omarchy/shell.json'
    settings = json.loads(config.read_text()) if config.exists() else {'version': 1}
    settings['plugins'] = [{'id': p['id']} for p in data if p['enabled']]
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(json.dumps(settings))
    sys.exit(0)
sys.exit(1)
''')

    def copy(self, relative):
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)

    def write_command(self, name, source):
        path = self.mock / name
        path.write_text(source)
        path.chmod(0o755)

    def run_script(self, *args, ok=True):
        result = subprocess.run(['bash', str(self.repo / 'install-all.sh'), *args],
                                env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def git(self, directory, *args):
        return subprocess.check_output(['git', '-C', str(directory), *args],
                                       env=self.env, text=True, stderr=subprocess.DEVNULL).strip()

    def snapshot(self, path=None):
        path = path or self.home
        return [(str(p.relative_to(path)), ('link', os.readlink(p)) if p.is_symlink()
                 else ('dir',) if p.is_dir() else ('file', p.read_bytes(), p.stat().st_mtime_ns))
                for p in sorted(path.rglob('*'))]

    def plugin_fixture(self):
        local = self.repo / 'config/omarchy/plugins/daniel.window-switcher'
        local.mkdir(parents=True)
        self.write_plugin(local, 'daniel.window-switcher')
        upstream = self.base / 'upstream'
        upstream.mkdir()
        self.write_plugin(upstream, 'custom.media')
        self.git(upstream, 'init', '-q')
        self.git(upstream, 'add', '.')
        self.git(upstream, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                 'commit', '-qm', 'Pinned plugin')
        self.revision = self.git(upstream, 'rev-parse', 'HEAD')
        # A newer upstream commit must not be installed in place of the pin.
        (upstream / 'Service.qml').write_text('// newer upstream\n')
        self.git(upstream, 'add', '.')
        self.git(upstream, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                 'commit', '-qm', 'Newer plugin')
        self.upstream = upstream
        self.manifest = {'version': 1, 'plugins': [
            {'id': 'daniel.window-switcher', 'enabled': True,
             'path': 'config/omarchy/plugins/daniel.window-switcher'},
            {'id': 'custom.media', 'enabled': False, 'url': str(upstream),
             'revision': self.revision}]}
        self.save_manifest()
        self.catalog.write_text(json.dumps([
            {'id': 'daniel.window-switcher', 'enabled': False},
            {'id': 'custom.media', 'enabled': True},
            {'id': 'unrelated.plugin', 'enabled': True}]))
        self.shell.parent.mkdir(parents=True, exist_ok=True)
        self.shell.write_text(json.dumps({'version': 1, 'other': {'keep': True},
                                         'plugins': [{'id': 'unrelated.plugin'}]}))

    def save_manifest(self):
        (self.repo / 'install/plugins.json').write_text(json.dumps(self.manifest))

    @staticmethod
    def write_plugin(path, plugin_id):
        (path / 'manifest.json').write_text(json.dumps({'schemaVersion': 1, 'id': plugin_id,
            'name': plugin_id, 'version': '1', 'kinds': ['service'],
            'entryPoints': {'service': 'Service.qml'}}))
        (path / 'Service.qml').write_text('// pinned plugin\n')

    def test_plugins_pinned_states_backup_repeat_and_dry_run(self):
        self.plugin_fixture()
        before = self.snapshot()
        result = self.run_script('--dry-run', 'plugins')
        self.assertIn(self.revision, result.stdout)
        self.assertIn('enabled=false', result.stdout)
        self.assertEqual(before, self.snapshot())
        original = self.shell.read_bytes()
        self.run_script('plugins')
        source = self.cache / 'custom.media' / self.revision
        self.assertEqual(self.git(source, 'rev-parse', 'HEAD'), self.revision)
        self.assertEqual((source / 'Service.qml').read_text(), '// pinned plugin\n')
        self.assertEqual((self.plugins / 'custom.media').resolve(), source)
        backup = next(self.shell.parent.glob('shell.json.bak.*/shell.json'))
        self.assertEqual(backup.read_bytes(), original)
        settings = json.loads(self.shell.read_text())
        self.assertEqual(settings['other'], {'keep': True})
        self.assertEqual(settings['plugins'], [{'id': 'daniel.window-switcher'},
                                               {'id': 'unrelated.plugin'}])
        self.assertEqual(self.log.read_text().splitlines(),
                         ['plugin disable custom.media', 'plugin enable daniel.window-switcher'])
        before = self.snapshot()
        self.run_script('plugins')
        self.assertEqual(before, self.snapshot())
        self.assertEqual(len(self.log.read_text().splitlines()), 2)

    def test_reuse_existing_clean_checkout_without_fetching(self):
        self.plugin_fixture()
        target = self.plugins / 'custom.media'
        self.git(self.base, 'clone', '-q', str(self.upstream), str(target))
        self.git(target, 'checkout', '-q', '--detach', self.revision)
        before = self.git(target, 'rev-parse', 'HEAD')
        self.run_script('plugins')
        self.assertFalse(target.is_symlink())
        self.assertEqual(before, self.git(target, 'rev-parse', 'HEAD'))
        self.assertFalse(self.cache.exists())

    def test_conflicts_force_backups_and_dirty_checkout(self):
        self.plugin_fixture()
        target = self.plugins / 'custom.media'
        self.git(self.base, 'clone', '-q', str(self.upstream), str(target))
        self.git(target, 'checkout', '-q', '--detach', self.revision)
        (target / 'Service.qml').write_text('// local edits\n')
        before = self.snapshot()
        self.run_script('plugins', ok=False)
        self.run_script('--dry-run', '--force', 'plugins')
        self.assertEqual(before, self.snapshot())
        self.run_script('--force', 'plugins')
        backup = next((self.home / '.local/state/dotfiles-backups').glob('plugins.*/custom.media'))
        self.assertEqual((backup / 'Service.qml').read_text(), '// local edits\n')
        self.assertTrue(target.is_symlink())
        (target / 'Service.qml').write_text('// dirty managed cache\n')
        before = self.snapshot()
        result = self.run_script('--force', 'plugins', ok=False)
        self.assertIn('managed checkout is modified', result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_offline_install_then_activate(self):
        self.plugin_fixture()
        self.env['TEST_OFFLINE'] = 'true'
        original = self.shell.read_bytes()
        result = self.run_script('plugins')
        self.assertIn('activation PENDING', result.stdout)
        self.assertIn('./install-all.sh plugins', result.stdout)
        self.assertEqual(original, self.shell.read_bytes())
        self.assertFalse(self.log.exists())
        self.env.pop('TEST_OFFLINE')
        self.run_script('plugins')
        self.assertIn('plugin enable daniel.window-switcher', self.log.read_text())

    def test_discovery_and_state_verification_failures(self):
        self.plugin_fixture()
        self.env['TEST_UNDISCOVERED'] = 'true'
        result = self.run_script('plugins', ok=False)
        self.assertIn('plugin discovery did not finish', result.stderr)
        self.assertFalse(self.log.exists())
        self.env.pop('TEST_UNDISCOVERED')
        self.env['TEST_NO_STATE_CHANGE'] = 'true'
        result = self.run_script('plugins', ok=False)
        self.assertIn('states did not match', result.stderr)

    def test_bad_manifest_fetch_and_linked_parent_are_safe(self):
        self.plugin_fixture()
        self.manifest['plugins'][1]['revision'] = 'not-a-sha'
        self.save_manifest()
        before = self.snapshot()
        self.run_script('plugins', ok=False)
        self.assertEqual(before, self.snapshot())
        self.manifest['plugins'][1]['revision'] = 'f' * 40
        self.save_manifest()
        self.run_script('plugins', ok=False)
        self.assertFalse(self.plugins.exists())
        self.assertEqual(list(self.cache.rglob('.fetch.*')), [])
        self.manifest['plugins'][1]['revision'] = self.revision
        self.save_manifest()
        self.plugins.symlink_to(self.repo / 'config/omarchy/plugins')
        before = self.snapshot(self.repo)
        result = self.run_script('--force', 'plugins', ok=False)
        self.assertIn('shared directory is symlinked', result.stderr)
        self.assertEqual(before, self.snapshot(self.repo))

    def test_wrong_plugin_id_is_rejected_before_live_links(self):
        self.plugin_fixture()
        self.manifest['plugins'][1]['id'] = 'different.plugin'
        self.save_manifest()
        self.run_script('plugins', ok=False)
        self.assertFalse(self.plugins.exists())

    def orchestrator_fixture(self):
        # Log only the dispatch boundary; the actual plugin installer has its
        # separate Git and IPC tests above.
        for name in ('pacman', 'yay', 'sudo'):
            self.write_command(name, '#!/bin/bash\nexit 0\n')
        for relative, step in (
                ('install-dotfiles.sh', 'dotfiles'), ('install/install-shell.sh', 'shell'),
                ('install/install-desktop-settings.sh', 'desktop-settings'),
                ('install/install-wallpapers.sh', 'wallpapers'),
                ('install-hyprland-overrides.sh', 'hyprland'),
                ('install/install-activitywatcher.sh', 'activitywatch'),
                ('install/install-plugins.sh', 'plugins'),
                ('desktop-generator.sh', 'desktop-launchers'),
                ('install/check-complete-config.sh', 'preflight')):
            path = self.repo / relative
            path.write_text(f'''#!/bin/bash
printf '%s\\n' '{step}'" $*" >> "$TEST_LOG"
[[ "${{TEST_FAIL:-}}" != '{step}' ]] || exit 7
''')
            path.chmod(0o755)
        (self.repo / 'install/packages.conf').write_text('pacman:stow\naur:activitywatch-bin\n')

    def test_complete_order_flags_skip_plain_all_and_failures(self):
        self.orchestrator_fixture()
        self.run_script('--dry-run', 'all')
        self.assertEqual(self.log.read_text().splitlines(),
                         [f'{s} --dry-run' for s in ('dotfiles', 'shell', 'desktop-launchers')])
        self.log.unlink()
        result = self.run_script('--dry-run', '--complete-config', '--force', 'all')
        steps = ['preflight', 'dotfiles', 'shell', 'desktop-settings', 'wallpapers',
                 'hyprland', 'activitywatch', 'plugins', 'desktop-launchers']
        lines = self.log.read_text().splitlines()
        self.assertEqual([line.split()[0] for line in lines], steps)
        for step in ('dotfiles', 'desktop-settings', 'plugins'):
            self.assertIn(f'{step} --dry-run --force', lines)
        for step in ('shell', 'wallpapers', 'hyprland', 'activitywatch'):
            self.assertIn(f'{step} --dry-run', lines)
        self.assertLess(result.stdout.index('Operation: packages'), result.stdout.index('Operation: dotfiles'))
        self.log.unlink()
        self.run_script('--dry-run', '--complete-config', '--skip', 'activitywatch-bin', 'all')
        self.assertNotIn('activitywatch --dry-run', self.log.read_text())
        self.assertIn('preflight --skip activitywatch-bin', self.log.read_text())
        self.log.unlink()
        self.run_script('--skip', 'activitywatch-bin', 'activitywatch')
        self.assertFalse(self.log.exists())
        self.env['TEST_FAIL'] = 'wallpapers'
        result = self.run_script('--dry-run', '--complete-config', 'all', ok=False)
        self.assertEqual(result.returncode, 7)
        self.assertIn('operation: wallpapers', result.stderr)
        self.assertNotIn('hyprland --dry-run', self.log.read_text())
        self.log.unlink()
        self.env['TEST_FAIL'] = 'preflight'
        result = self.run_script('--complete-config', 'all', ok=False)
        self.assertNotIn('Operation: packages', result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ['preflight '])

    def test_complete_flag_rejected_outside_all(self):
        self.orchestrator_fixture()
        for operation in ('plugins', 'packages', 'dotfiles', 'desktop-settings', 'unknown'):
            result = self.run_script('--complete-config', operation, ok=False)
            self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_real_preflight_checks_submodules_and_missing_tools(self):
        self.orchestrator_fixture()
        self.copy('install/check-complete-config.sh')
        self.write_command('git', '''#!/bin/bash
printf '%s\\n' "${TEST_SUBMODULE_STATUS:- 000 config/nvim}"
''')
        self.env['TEST_SUBMODULE_STATUS'] = '-000 config/nvim'
        result = self.run_script('--complete-config', '--skip', 'activitywatch-bin', 'all', ok=False)
        self.assertIn('submodule update --init --recursive', result.stderr)
        self.assertNotIn('Operation: packages', result.stdout)
        self.assertFalse(self.log.exists())
        self.write_command('cargo', '#!/bin/bash\nexit 1\n')
        for name in ('rustc', 'cc', 'make', 'pkg-config', 'systemctl'):
            self.write_command(name, '#!/bin/bash\nexit 0\n')
        result = self.run_script('--complete-config', 'all', ok=False)
        self.assertIn('Rust toolchain is unavailable', result.stderr)
        self.assertNotIn('Operation: packages', result.stdout)

    def test_fresh_stow_keeps_shared_plugin_directory_real(self):
        self.plugin_fixture()
        self.copy('install-dotfiles.sh')
        before = self.snapshot(self.repo / 'config')
        subprocess.run(['bash', str(self.repo / 'install-dotfiles.sh'), '--only', 'omarchy'],
                       env=self.env, check=True, capture_output=True)
        self.assertTrue(self.plugins.is_dir())
        self.assertFalse(self.plugins.is_symlink())
        self.assertTrue((self.plugins / 'daniel.window-switcher').is_symlink())
        self.run_script('plugins')
        self.assertEqual(before, self.snapshot(self.repo / 'config'))

    def test_complete_install_with_real_scripts_and_five_local_plugins(self):
        self.plugin_fixture()
        for relative in ('install/check-complete-config.sh', 'install-dotfiles.sh',
                         'install-hyprland-overrides.sh', 'install/install-shell.sh',
                         'install/install-desktop-settings.sh', 'install/install-wallpapers.sh',
                         'install/install-activitywatcher.sh', 'desktop-generator.sh',
                         'defaults/omarchy-shell.json', 'defaults/monitor-backgrounds.json',
                         'bin/hypr-window-switcher', 'bin/wallpaper-monitor',
                         'config/hypr/hyprland-overrides.lua', 'desktop-apps/WhatsApp.desktop'):
            self.copy(relative)
        for relative in ('config/nvim/init.lua', 'config/oh-my-posh/custom.json'):
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
        background_path = 'config/omarchy-wallpapers/plugins/daniel.background'
        shutil.copytree(ROOT / background_path, self.repo / background_path)
        self.manifest['plugins'].insert(0, {'id': 'daniel.background', 'enabled': True,
                                          'path': background_path})
        for plugin_id in ('crmne.hyprmoncfg', 'jankeesvw.notification-center'):
            upstream = self.base / plugin_id
            upstream.mkdir()
            self.write_plugin(upstream, plugin_id)
            self.git(upstream, 'init', '-q')
            self.git(upstream, 'add', '.')
            self.git(upstream, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                     'commit', '-qm', plugin_id)
            self.manifest['plugins'].append({'id': plugin_id, 'enabled': True,
                'url': str(upstream), 'revision': self.git(upstream, 'rev-parse', 'HEAD')})
        for plugin in self.manifest['plugins']:
            plugin['enabled'] = True
        self.save_manifest()
        self.catalog.write_text(json.dumps([{'id': p['id'], 'enabled': not p['enabled']}
                                           for p in self.manifest['plugins']]))
        wallpapers = self.repo / 'config/omarchy-wallpapers/themes/tokyo-night-wallpapers/backgrounds'
        wallpapers.mkdir(parents=True)
        defaults = json.loads((ROOT / 'defaults/monitor-backgrounds.json').read_text())
        for name in defaults['outputs'].values():
            (wallpapers / name).write_bytes(b'fixture image')
        self.git(self.repo, 'init', '-q')
        hypr = self.home / '.config/hypr'
        hypr.mkdir()
        (hypr / 'hyprland.lua').write_text('-- existing Omarchy base\n')
        for name in ('pacman', 'yay', 'sudo'):
            self.write_command(name, '#!/bin/bash\nexit 0\n')
        (self.repo / 'install/packages.conf').write_text('pacman:stow\naur:activitywatch-bin\n')
        before = self.snapshot()
        sources_before = self.snapshot(self.repo / 'config')
        result = self.run_script('--dry-run', '--complete-config', '--force',
                                 '--skip', 'activitywatch-bin', 'all')
        self.assertIn('preflight passed', result.stdout)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(sources_before, self.snapshot(self.repo / 'config'))
        result = self.run_script('--complete-config', '--force', '--skip', 'activitywatch-bin', 'all')
        self.assertIn('all declared states verified', result.stdout)
        catalog = {p['id']: p['enabled'] for p in json.loads(self.catalog.read_text())}
        for plugin in self.manifest['plugins']:
            self.assertEqual(catalog[plugin['id']], plugin['enabled'])
            self.assertTrue((self.plugins / plugin['id']).is_dir())
        self.assertEqual(sources_before, self.snapshot(self.repo / 'config'))
        self.assertFalse(self.plugins.is_symlink())
        self.assertIn('require("hypr.hyprland-overrides")', (hypr / 'hyprland.lua').read_text())
        self.assertTrue((self.home / '.local/bin/wallpaper-monitor').is_symlink())
        self.assertTrue((self.home / '.local/bin/hypr-window-switcher').is_symlink())
        # Complete setup must defer both first-party activations until the
        # plugin step, so its backup precedes every state change.
        self.assertEqual(self.log.read_text().splitlines(), [
            'plugin enable daniel.background', 'plugin enable daniel.window-switcher',
            'plugin enable custom.media', 'plugin enable crmne.hyprmoncfg',
            'plugin enable jankeesvw.notification-center'])
        backups_before = sorted(self.shell.parent.glob('shell.json.bak.*'))
        self.run_script('--complete-config', '--force', '--skip', 'activitywatch-bin', 'all')
        self.assertEqual(backups_before, sorted(self.shell.parent.glob('shell.json.bak.*')))
        self.assertEqual(len(self.log.read_text().splitlines()), 5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
