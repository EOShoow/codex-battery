#!/usr/bin/env python3
"""Exercise routing, actual process supervision, cancellation, locking and UI without model calls."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid

root = Path(__file__).resolve().parents[1]
runner = root / 'Resources/task_runner.py'
harness = r'''
import AppKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let now = Date()
func quota(_ used: Double, age: Double = 0) -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot(checkedAt: now.addingTimeInterval(-age),
        fiveHour: ProviderQuotaWindow(used: 20, resetsAt: now.addingTimeInterval(14400)),
        week: ProviderQuotaWindow(used: used, resetsAt: now.addingTimeInterval(432000)))
}
func choose(_ c: ProviderQuotaSnapshot?, _ a: ProviderQuotaSnapshot?, last: QuotaProvider? = nil,
            requested: QuotaProvider? = nil) -> TaskRouteDecision {
    TaskRouter.choose(codex: c, claude: a, codexReliable: c != nil, claudeReliable: a != nil,
        requested: requested, lastProvider: last, now: now, chinese: true)
}
precondition(choose(quota(80), quota(20)).provider == .claude)
precondition(choose(quota(20), quota(80)).provider == .codex)
precondition(choose(quota(20), quota(22), last: .codex).provider == .claude)
precondition(choose(quota(20), quota(22), last: .claude).provider == .codex)
precondition(choose(quota(20), nil).provider == nil)
precondition(choose(quota(20, age: 901), quota(20)).provider == nil)
precondition(choose(quota(20), nil, requested: .codex).provider == .codex)
precondition(choose(quota(99), quota(20), requested: .codex).provider == nil)
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for provider in [QuotaProvider.codex, .claude] {
    let spec = TaskLaunchSpec(provider: provider, executable: folder.appendingPathComponent("fake_cli.py"),
        directory: folder, prompt: "spaces ' quotes ; $(touch NEVER)\nsecond line", allowEdits: false,
        jobDirectory: folder.appendingPathComponent("jobs/" + provider.rawValue))
    precondition(!spec.arguments.contains(spec.prompt), "prompt must use stdin, never shell arguments")
    precondition(!spec.arguments.contains("--dangerously-skip-permissions"))
    if provider == .claude {
        precondition(spec.arguments.contains("--restricted"))
        precondition(!spec.arguments.contains("Bash"))
        precondition(!spec.arguments.contains("Edit,Write"))
    } else { precondition(spec.arguments.contains("read-only")) }
    try JSONSerialization.data(withJSONObject: spec.payload).write(to: folder.appendingPathComponent(provider.rawValue + ".json"))
}
if CommandLine.arguments.count > 2 {
    let suite = "local.codex.battery.task.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = TaskLauncherMenuController(defaults: defaults, chinese: true,
        quotas: { (quota(80), quota(20), true, true) }, refresh: {})
    let view = controller.previewForTest()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("Routing, fresh-quota gates, safe argv and task window: ok")
'''


def wait_for(predicate, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(.02)
    raise AssertionError('Timed out waiting for local test')


with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    main = folder / 'main.swift'
    main.write_text(harness)
    menu = folder / 'TaskLauncherMenu.swift'
    menu.write_text((root / 'Sources/TaskLauncherMenu.swift').read_text() + '''
extension TaskLauncherMenuController {
    func previewForTest() -> NSView { buildWindow(); updateRoute(); return window!.contentView! }
}
''')
    binary = folder / 'check-task-routing'
    subprocess.run(['swiftc', str(main), str(root / 'Sources/ClaudeQuota.swift'),
                    str(root / 'Sources/TaskDispatch.swift'), str(menu), '-framework', 'AppKit', '-o', str(binary)], check=True)
    command = [str(binary), str(folder)]
    if preview := os.environ.get('CODEX_BATTERY_TASK_PREVIEW'):
        path = Path(preview).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        command.append(str(path))
    subprocess.run(command, check=True)
    fake = folder / 'fake_cli.py'
    fake.write_text('''#!/usr/bin/python3
import json,os,pathlib,subprocess,sys,time
root=pathlib.Path.cwd()
with (root/'calls.txt').open('a') as f:f.write('called\\n')
text=sys.stdin.read()
if text=='slow':
 child=subprocess.Popen(['/usr/bin/python3','-c','import time;time.sleep(60)'])
 (root/'grandchild.pid').write_text(str(child.pid))
 time.sleep(60)
if '--output-last-message' in sys.argv:
 if text!='missing-result':
  pathlib.Path(sys.argv[sys.argv.index('--output-last-message')+1]).write_text('ok:'+text)
else:
 print(json.dumps({'result':'ok:'+text,'is_error':text=='semantic-failure','subtype':'success'}))
''')
    fake.chmod(0o700)
    base = {p: json.loads((folder / (p + '.json')).read_text()) for p in ['codex', 'claude']}
    for spec in base.values():
        spec['owner_pid'] = os.getpid()

    def specification(provider='codex', prompt=None, timeout=10):
        spec = dict(base[provider])
        spec['arguments'] = list(spec['arguments'])
        spec['job_dir'] = str(folder / 'jobs' / str(uuid.uuid4()))
        if '--output-last-message' in spec['arguments']:
            spec['arguments'][spec['arguments'].index('--output-last-message') + 1] = str(Path(spec['job_dir']) / 'result.txt')
        spec['timeout_seconds'] = timeout
        if prompt is not None:
            spec['prompt'] = prompt
        return spec

    def execute(spec):
        result = subprocess.run([sys.executable, str(runner)], input=json.dumps(spec), text=True, timeout=15)
        status = json.loads((Path(spec['job_dir']) / 'status.json').read_text())
        return result, status

    for provider in ['codex', 'claude']:
        spec = specification(provider)
        result, status = execute(spec)
        assert result.returncode == 0 and status['state'] == 'completed', status
        assert (Path(spec['job_dir']) / 'result.txt').read_text() == 'ok:' + spec['prompt']
        assert (Path(spec['job_dir']) / 'result.txt').stat().st_mode & 0o777 == 0o600
    assert not (folder / 'NEVER').exists(), 'Prompt must never be evaluated as a shell command'
    for provider, prompt in [('claude', 'semantic-failure'), ('codex', 'missing-result')]:
        _, status = execute(specification(provider, prompt))
        assert status['state'] == 'failed', status

    _, status = execute(specification(prompt='slow', timeout=1))
    assert status['state'] == 'timed_out', status
    grandchild = int((folder / 'grandchild.pid').read_text())

    def stopped(pid):
        result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
        return result.returncode != 0 or result.stdout.strip().startswith('Z')
    wait_for(lambda: stopped(grandchild))

    spec = specification(prompt='slow', timeout=10)
    calls_before_start = (folder / 'calls.txt').read_text().count('called')
    (folder / 'grandchild.pid').unlink(missing_ok=True)
    first = subprocess.Popen([sys.executable, str(runner)], stdin=subprocess.PIPE, text=True)
    first.stdin.write(json.dumps(spec))
    first.stdin.close()
    def running():
        try:
            return json.loads((Path(spec['job_dir']) / 'status.json').read_text())['state'] == 'running'
        except (OSError, ValueError):
            return False
    wait_for(running)
    wait_for(lambda: (folder / 'calls.txt').read_text().count('called') == calls_before_start + 1
             and (folder / 'grandchild.pid').exists())
    calls = (folder / 'calls.txt').read_text().count('called')
    _, busy = execute(specification())
    assert busy['state'] == 'busy', busy
    assert (folder / 'calls.txt').read_text().count('called') == calls
    first.send_signal(signal.SIGTERM)
    first.wait(timeout=5)
    state = json.loads((Path(spec['job_dir']) / 'status.json').read_text())
    assert state['state'] == 'cancelled', state
    grandchild = int((folder / 'grandchild.pid').read_text())
    wait_for(lambda: stopped(grandchild))

    orphan = specification()
    orphan['owner_pid'] = -1
    calls = (folder / 'calls.txt').read_text().count('called')
    _, status = execute(orphan)
    assert status['state'] == 'cancelled'
    assert (folder / 'calls.txt').read_text().count('called') == calls
    print('Actual supervisor: stdin, result parsing, lock, timeout, child cleanup, cancellation and owner guard: ok')
