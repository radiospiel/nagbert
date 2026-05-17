# Nagbert

A macOS app for **actionable notifications**, driven from the command line. A
small, deeply Germanic functionary who will not rest until you've restarted the
VPN.

Two binaries from one Swift package:

- **`nag`** — thin CLI. Sends a payload to the daemon and exits.
- **`nagbertd`** — GUI daemon. Listens on a Unix socket and shows notifications
  as floating panels in the top-right corner.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Build

```sh
swift build -c release
```

Binaries land in `.build/release/`. Install both into the same directory (or
into `/usr/local/bin` or `/opt/homebrew/bin`):

```sh
cp .build/release/nag .build/release/nagbertd /usr/local/bin/
```

`nag` will auto-launch `nagbertd` on first use if it's not already running.

## Usage

```sh
nag --title "Restart VPN" \
    --body  "Tunnel down for 3 minutes" \
    --level URGENT \
    --perform-action "scutil --nc start MyVPN" \
    --check-action   "scutil --nc status MyVPN | grep -q Connected" \
    --documentation  "https://wiki.example.com/vpn"
```

### Flags

| Flag | Meaning |
|---|---|
| `--id ID` | Explicit identity for dedupe (otherwise auto-hashed) |
| `--title TITLE` | Title (required) |
| `--body BODY` | Body text |
| `--level LEVEL` | `INFO` / `WARN` / `URGENT` (default `INFO`) |
| `--perform-action CMD` | Bash command run when user clicks **Perform** |
| `--check-action CMD` | Bash command for resolution checks (exit 0 = resolved) |
| `--documentation URL` | URL opened on **Docs** click |
| `--hide-after SECONDS` | Auto-hide delay for plain INFO toasts |

## Examples

### Plain toast — auto-hides

```sh
nag --title "Build finished"
nag --title "Tests passed" --body "234 examples, 0 failures" --hide-after 3
```

### WARN / URGENT — stay until dismissed

```sh
nag --title "Disk almost full" --level WARN --body "12 GB free on /"
nag --title "Production deploy in 5 min" --level URGENT
```

### One-click fixer with auto-resolve

A perform action runs when the user clicks **Perform**. If a `--check-action`
is also given, the notification keeps re-checking every 2s until the check
passes (exit 0), then dismisses itself.

```sh
nag --id vpn \
    --title "Restart VPN" \
    --body  "Tunnel has been down for 3 minutes" \
    --level URGENT \
    --perform-action "scutil --nc start MyVPN" \
    --check-action   "scutil --nc status MyVPN | grep -q Connected" \
    --documentation  "https://wiki.example.com/vpn"
```

### Passive watcher — check only

No button, just a self-resolving warning. Useful for "remind me when something
comes back".

```sh
nag --id docker-up \
    --title "Docker is down" \
    --level WARN \
    --check-action "docker info >/dev/null 2>&1"
```

### Dedupe & shake

Re-sending the same `--id` while the notification is still on screen shakes
the existing one instead of stacking duplicates.

```sh
nag --id vpn --title "VPN down" --level WARN
sleep 1
nag --id vpn --title "VPN down" --level WARN   # shakes the first one
```

### Inline errors

If `--perform-action` exits non-zero, the first two stderr lines appear in the
notification; **Show full error** expands the rest (up to 16 KB).

```sh
nag --title "Rebuild index" \
    --perform-action "false; echo 'connection refused on :5432' 1>&2"
```

### Wire it into your tools

```sh
# In a long-running script
make deploy && \
  nag --title "Deploy complete" --hide-after 4 || \
  nag --title "Deploy failed" --level URGENT \
      --perform-action "make deploy" \
      --documentation "https://wiki.example.com/deploy"

# From a cron / launchd job that checks battery
pmset -g batt | grep -q "AC Power" || \
  nag --id battery --title "On battery" --level WARN \
      --check-action "pmset -g batt | grep -q 'AC Power'"
```

## Socket

`~/Library/Application Support/Nagbert/nagbert.sock`, mode `0600`. One JSON
payload per connection terminated by `\n`; daemon replies with one JSON
`NotifyReply` and closes.

## Security

Trust the caller. Single-user machine; anyone who can run `nag` already has
shell access. No allowlist, no shared secret. See `DESIGN.md` §5.
