# Codex Battery

[中文说明](README.zh-CN.md)

A tiny macOS menu bar battery for your Codex quota.

![Codex Battery menu bar screenshot](assets/codex-battery-en.png)

Codex Battery turns Codex usage limits into a compact menu bar signal:

- Outer ring: weekly quota remaining
- Inner ring: 5-hour quota remaining
- Menu details: reset times, today's token burn, weekly budget forecast, and the top active Codex thread

It is local-only, lightweight, and designed for people who keep checking quota while doing long agentic work.

## Why

Codex is powerful enough that quota becomes a real workflow constraint. The official usage UI is useful, but it lives inside the app. Codex Battery keeps the important signal in your macOS menu bar, like a laptop battery indicator.

Use it to answer:

- Am I close to the 5-hour wall?
- Will my weekly quota last until reset?
- Is today's usage unusually heavy?
- Which Codex thread is burning the most tokens?

## Install

Requirements:

- macOS 14+
- Xcode Command Line Tools, including `swiftc`
- Codex desktop app with local state under `~/.codex`

### Homebrew

```bash
brew install EOShoow/tap/codex-battery
codex-battery
```

Optional login startup:

```bash
codex-battery-login install
```

Remove the login item:

```bash
codex-battery-login uninstall
```

### From Source

```bash
git clone https://github.com/EOShoow/codex-battery.git
cd codex-battery
./install.sh
```

The app is built to:

```text
~/Applications/CodexBattery.app
```

The login item is installed at:

```text
~/Library/LaunchAgents/local.codex.battery.menu.plist
```

### About the "unidentified developer" warning

![macOS unidentified developer warning](assets/unsigned-developer-warning-en.png)

Codex Battery is not signed with a paid Apple Developer ID yet, so macOS may show it as coming from an "unidentified developer" in Login Items or Gatekeeper prompts.

That warning is about Apple code-signing identity, not about network access or data collection. This project is open source, installs from this repository, and reads only local Codex state under `~/.codex`.

If you are cautious, inspect the source first and install from source with `./install.sh`. The current Homebrew formula also builds the app locally from this repository instead of downloading a closed binary.

## Reading The Menu

Example in English:

```text
5h left     99%    May 2 02:16
1w left     82%    May 5 14:04
Today burn  183.8M 14.1x    spike today
Forecast    lasts to reset  0.4x budget
Top         PoQ Mac clone  91.7M
```

Example in Chinese:

```text
5小时剩余  99%    5月2日 02:16
1周剩余    82%    5月5日 14:04
今日消耗    183.8M 14.1x    今日冲高
周预测      可撑到重置  0.4x预算
Top         PoQ Mac 复刻  91.7M
```

`1.0x budget` means your weekly usage is exactly on the linear budget line. For example, if 50% of the week has passed and you have used 50% of the weekly quota, you are at `1.0x budget`.

- Below `1.0x`: safer than budget
- Around `1.0x`: on track to reach reset exactly
- Above `1.0x`: ahead of budget and may run out early

## Refresh Behavior

Codex Battery refreshes:

- At startup
- Every 5 minutes
- When you open the menu
- When you click `Refresh`

## Accuracy

This is an unofficial local estimator. It reads Codex state and rollout logs from your machine. If Codex has not flushed the latest usage event yet, Codex Battery cannot see it.

Treat it as a fast dashboard, not an accounting source of truth.

## Compatibility

Codex Battery depends on Codex Desktop's local state format, especially `~/.codex/state_5.sqlite` and the rollout log entries referenced by that database.

This is not an official Codex API. If a future Codex Desktop update changes the local database schema, log path layout, or `token_count` event format, Codex Battery may stop showing data until it is updated.

Current known baseline:

- Verified with Codex Desktop local state as of 2026-05-03
- Reads `~/.codex/state_5.sqlite`
- Reads recent rollout logs that contain `token_count.rate_limits`

If it breaks after a Codex update, please open an issue with your Codex version, macOS version, and the error text shown by the menu. Do not paste private rollout logs unless you have reviewed and redacted them.

## Privacy

Codex Battery does not upload anything and does not make network requests.

It reads:

- `~/.codex/state_5.sqlite`
- recent rollout log paths referenced by that database

Thread titles are displayed locally so you can see which conversation is consuming tokens.

## Update

```bash
git pull
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

## Build Manually

```bash
./build.sh
open ~/Applications/CodexBattery.app
```

## Status

Early release. Codex's local state format may change, so pull requests and issue reports are welcome.

## License

MIT
