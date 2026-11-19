#!/usr/bin/env python3
"""Run one local CLI session; no retry, fallback, shell interpolation, or credential handling."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def run(spec):
    job = Path(spec['job_dir'])
    job.mkdir(parents=True, mode=0o700, exist_ok=False)
    os.chmod(job.parent, 0o700)
    state = {'provider': spec['provider'], 'state': 'preparing', 'started_at': time.time()}

    def save(**values):
        state.update(values)
        temp = job / 'status.tmp'
        temp.write_text(json.dumps(state, ensure_ascii=False, indent=2))
        os.chmod(temp, 0o600)
        temp.replace(job / 'status.json')

    lock = (job.parent / 'active.lock').open('a')
    os.chmod(job.parent / 'active.lock', 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        save(state='busy', message='Another task is still running. No session was started.')
        return 2
    child = None
    cancelled = False

    def cancel(signum, frame):
        nonlocal cancelled
        cancelled = True
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)

    def stop_child():
        if child is None:
            return
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        # Also terminate descendants that survived the session leader.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()

    output = job / 'stdout.jsonl'
    errors = job / 'stderr.txt'
    try:
        command = [spec['executable'], *spec['arguments']]
        if not Path(command[0]).is_absolute() or not all(isinstance(arg, str) for arg in command):
            raise ValueError('Invalid command')
        cwd = Path(spec['cwd']).resolve(strict=True)
        if not cwd.is_dir():
            raise ValueError('Working directory is not a folder')
        prompt = spec['prompt'].encode('utf-8')
        if not prompt.strip() or len(prompt) > 128 * 1024:
            raise ValueError('Task must be between 1 and 131072 UTF-8 bytes')
        timeout = min(900, max(1, float(spec.get('timeout_seconds', 900))))
        env = os.environ.copy()
        # Prefer the subscription logins behind the displayed quotas, not inherited API credentials.
        for name in ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL',
                     'OPENAI_BASE_URL', 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_USE_BEDROCK',
                     'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY']:
            env.pop(name, None)
        env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        env['CLAUDE_CODE_DISABLE_BACKGROUND_TASKS'] = '1'
        parent = int(spec.get('owner_pid', os.getppid()))
        started = time.monotonic()
        with output.open('wb') as out, errors.open('wb') as err:
            os.chmod(output, 0o600)
            os.chmod(errors, 0o600)
            if cancelled or os.getppid() != parent:
                save(state='cancelled', message='Cancelled before launch')
                return 2
            child = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                     stdout=out, stderr=err, start_new_session=True)
            save(state='running', pid=child.pid)
            # A separate stdin writer keeps cancellation responsive if the CLI stops reading input.
            import threading
            def feed():
                try:
                    child.stdin.write(prompt)
                    child.stdin.close()
                except (BrokenPipeError, OSError):
                    pass
            threading.Thread(target=feed, daemon=True).start()
            reason = None
            while child.poll() is None:
                if cancelled or os.getppid() != parent:
                    reason = 'cancelled'
                elif time.monotonic() - started >= timeout:
                    reason = 'timed_out'
                elif output.stat().st_size + errors.stat().st_size > 16 * 1024 * 1024:
                    reason = 'output_limit'
                if reason:
                    stop_child()
                    break
                time.sleep(0.2)
        code = child.wait()
        stop_child()  # No detached work is retained after a session completes.
        if reason:
            save(state=reason, exit_code=code, message='Session stopped; partial file edits may remain. No retry was started.')
            return 2
        result_path = job / 'result.txt'
        if spec['provider'] == 'claude':
            try:
                response = json.loads(output.read_text())
                if isinstance(response, list):
                    response = response[-1]
                result = response.get('result', '')
                if isinstance(result, str) and result:
                    result_path.write_text(result)
                    os.chmod(result_path, 0o600)
                if response.get('is_error') or response.get('subtype', 'success') != 'success':
                    code = code or 1
            except (ValueError, TypeError, IndexError, AttributeError):
                code = code or 1
        if result_path.exists():
            os.chmod(result_path, 0o600)
        success = code == 0 and result_path.exists() and result_path.stat().st_size > 0
        save(state='completed' if success else 'failed', exit_code=code,
             message='Finished' if success else 'No successful result. Inspect local stderr/stdout; no automatic retry was made.')
        return 0 if success else 1
    except Exception as error:
        stop_child()
        save(state='failed', message=type(error).__name__ + ': ' + str(error))
        return 1
    finally:
        lock.close()


if __name__ == '__main__':
    os.umask(0o077)
    try:
        incoming = sys.stdin.buffer.read(512 * 1024 + 1)
        if len(incoming) > 512 * 1024:
            raise ValueError('Task specification too large')
        sys.exit(run(json.loads(incoming)))
    except Exception:
        sys.exit(2)
