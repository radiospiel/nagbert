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

### Smoke tests

```sh
# Plain INFO toast that auto-hides after 5s
nag --title "Build finished"

# WARN that sticks around until dismissed
nag --title "Disk almost full" --level WARN --body "12 GB free on /"

# Actionable: click Perform, then check confirms
nag --title "Restart Docker" \
    --level URGENT \
    --perform-action "killall Docker && open -a Docker" \
    --check-action   "docker info >/dev/null 2>&1"

# Dedupe: second invocation shakes the existing one
nag --id vpn --title "VPN down" --level WARN
nag --id vpn --title "VPN down" --level WARN
```

## Socket

`~/Library/Application Support/Nagbert/nagbert.sock`, mode `0600`. One JSON
payload per connection terminated by `\n`; daemon replies with one JSON
`NotifyReply` and closes.

## Security

Trust the caller. Single-user machine; anyone who can run `nag` already has
shell access. No allowlist, no shared secret. See `DESIGN.md` §5.
