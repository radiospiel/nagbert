# Nagbert — Design Decisions & Conversation Summary

A macOS app for **actionable notifications**, driven from the command line. The
small, deeply Germanic functionary who will not rest until you've restarted the
VPN.

---

## 1. Concept

Nagbert displays notifications that can:

- run a **`perform_action`** (bash command) when the user clicks a button
- run a **`check_action`** (bash command) to verify a state and auto-resolve
- link to **`documentation`** (URL)
- auto-hide after **`hide_after`** seconds for simple INFO cases

Two binaries, one Swift package:

- **`nag`** — thin CLI. Parses args, serializes JSON, sends to daemon, exits.
- **`nagbertd`** — long-running GUI daemon. Listens on a Unix socket, displays
  notifications as floating panels, runs bash commands, manages state.

---

## 2. Payload

Every notification has this shape (serialized as JSON over the socket):

| Field            | Type               | Notes                                                 |
|------------------|--------------------|-------------------------------------------------------|
| `id`             | string, optional   | Explicit identity for dedupe. Falls back to auto-hash |
| `title`          | string, required   |                                                       |
| `body`           | string, optional   |                                                       |
| `level`          | `INFO` / `WARN` / `URGENT` | controls icon + color                         |
| `perform_action` | bash command, optional |                                                   |
| `check_action`   | bash command, optional |                                                   |
| `documentation` | URL, optional      | opened in browser when user clicks                    |
| `hide_after`    | seconds, optional  | default 5s for INFO-with-no-actions                   |

---

## 3. State machine

Phase is decided at creation time from payload contents, then evolves:

```
                ┌─ INFO + no actions ──> info ──(hide_after)──> dismissed
                │
  payload ──────┼─ check only ─────────> checking ──(exit 0)──> resolved ──> dismissed
                │                              └──(exit≠0)──> retry every 2s
                │
                ├─ perform + check ────> idle ──(click perform)──> performing
                │                                                       │
                │                              ┌────────────────────────┘
                │                              ▼
                │                          checking ──(exit 0)──> resolved ──> dismissed
                │                                  └──(exit≠0, retry every 2s)
                │
                ├─ perform only ───────> idle ──(click perform)──> performing ──> resolved ──> dismissed
                │
                └─ WARN/URGENT + no actions ──> persistent (until user dismisses)
```

A `perform_action` that exits non-zero transitions to **failed**, surfacing the
error inline (see §6).

---

## 4. Dedupe & shake behavior

When a notification arrives with an ID matching one already on screen:

- If it **has no `perform_action`** → shake the existing one for 2 seconds.
- If it **has `perform_action` but it hasn't been pressed yet** → shake.
- If it **has `perform_action` and it has already been performed** → replace
  with fresh state (cancel timers, kill running process, reset error log).

Identity:

- **Explicit `--id`** flag on the CLI is preferred (sender controls identity;
  body/title can change without breaking dedupe).
- **Auto-hash** fallback over (title, body, level, perform, check) when `--id`
  is omitted.

---

## 5. Security model

**Trust the caller.** Personal tool on a single-user machine; anyone who can
run `nag` already has shell access, so allowlisting commands doesn't add
meaningful safety. The socket is per-user at
`~/Library/Application Support/Nagbert/nagbert.sock` with mode `0600`.

No allowlist, no shared secret. Documented as such.

---

## 6. Error handling

When `perform_action` exits non-zero:

- **Inline preview**: first two non-empty lines of stderr shown in the
  notification body, monospaced.
- **"Show full error" button** expands to show the full captured stderr
  (scrollable, max ~160px tall, text-selectable).
- **Buffer caps**: soft limit 10 KB (this is what "show full" displays
  comfortably), **hard cap 16 KB**. Past 16 KB, further output is dropped and a
  trailing `[…truncated]` marker is appended.
- **Lifecycle**: the buffer is wiped the moment the notification is dismissed
  — no lingering stderr in memory.

`check_action` stderr is discarded; only perform errors are surfaced.

---

## 7. UI

- **Custom NSPanel** (borderless, floating, non-activating) hosting a SwiftUI
  view, styled to mimic macOS Notification Center: rounded corners, vibrancy
  background, drop shadow, level icon on the left, title + body + action row.
- Stacked vertically in the top-right corner of the main display.
- Hover reveals a close button.
- Shake animation is a horizontal sinusoidal `GeometryEffect` over ~0.55s.
- Level icons: `info.circle.fill` (blue) / `exclamationmark.triangle.fill`
  (orange) / `exclamationmark.octagon.fill` (red).

**Why custom and not the system Notification Center?** Notification Center
can't show custom buttons that run bash, can't show a spinner, can't shake,
can't surface inline error text, and dismisses on its own schedule. All of
those are core requirements here.

---

## 8. Naming

- **App / brand**: **Nagbert** — a small, deeply Germanic functionary who will
  not rest until you've restarted the VPN.
- **CLI binary**: **`nag`** — short, ergonomic:
  `nag --title "Restart VPN" --perform-action "..."`.
- **Daemon binary**: **`nagbertd`** — Unix `d` suffix convention.
- **Swift modules**: `Nagbert` (daemon), `NagCLI` (CLI), `NagbertCore` (shared
  types).
- **Repo**: `nagbert`.

---

## 9. Transport

- **Unix domain socket** at `~/Library/Application Support/Nagbert/nagbert.sock`,
  mode `0600`.
- **Wire format**: one JSON-encoded `NotifyPayload` per connection, terminated
  by `\n`. Daemon replies with one JSON-encoded `NotifyReply` (`ok`, `action`
  ∈ {`shown`, `shaken`, `replaced`, `error`}, optional `message`), then closes.
- The CLI **auto-launches `nagbertd`** if the socket isn't there (looks
  alongside its own binary first, then `/usr/local/bin`, then
  `/opt/homebrew/bin`).
- Considered: HTTP server, named pipe, "all of the above". Rejected as
  overkill — CLI-driven was the user's preference.

---

## 10. Stack & rejected alternatives

**Chosen**: Swift + SwiftUI for views, AppKit (NSPanel, NSStatusItem) for
windowing. SwiftUI alone can't produce borderless floating panels well; the
realistic interpretation of the user's "1 if possible, else 2" is a SwiftUI
view hosted in a custom NSPanel.

**Rejected**:

- Pure SwiftUI app — windowing limitations.
- Electron / Tauri — heavyweight for a single-purpose menu-bar daemon, and
  Notification-Center–style theming is harder to nail with web tech.
- Native macOS `UserNotifications` framework — see §7.

---

## 11. Outstanding / not yet implemented at conversation pause

Files completed at the point of summary:

- `Package.swift` (manifest, needs to be re-saved with the final nagbert name)
- `Sources/NagbertCore/Protocol.swift` — payload, reply, socket path, identity
  hash
- `Sources/NagCLI/main.swift` — argv parsing, daemon auto-launch, socket I/O
- `Sources/Nagbert/App.swift` — `NSApplication` setup, menu bar status item,
  socket server wiring
- `Sources/Nagbert/SocketServer.swift` — Unix domain socket server
- `Sources/Nagbert/NotificationStore.swift` — model, phases, error buffer
- `Sources/Nagbert/NotificationManager.swift` — orchestration, process
  spawning, timers, dedupe logic
- `Sources/Nagbert/NotificationView.swift` — **interrupted mid-file** in the
  action-row section

Not yet written:

- Rest of `NotificationView.swift` (action row: Perform / Show full error /
  Documentation / Dismiss buttons)
- `Sources/Nagbert/NotificationPanel.swift` — `NSPanel` subclass, fade in/out,
  hosts the SwiftUI view
- `Sources/Nagbert/StackController.swift` — top-right vertical layout of
  multiple panels, re-layout on add/remove
- `Sources/Nagbert/ShakeEffect.swift` — `GeometryEffect` for the 2-second
  shake
- `README.md` — install / usage / examples
- `.gitignore` — `.build/`, `.swiftpm/`, DerivedData
- A few smoke-test invocations to copy-paste

Internal symbol names in the source files still reference the old `Notifyd` /
`NotifyCLI` / `Shared` naming and need a global rename to `Nagbert` /
`NagCLI` / `NagbertCore` once the rest is done.

---

## 12. Open questions deferred

None outstanding. The user explicitly confirmed:

1. CLI-only trigger transport.
2. Custom NSWindow approach over the system Notification Center.
3. Swift + SwiftUI, falling back to AppKit where needed.
4. Trust-the-caller security model (option **a**).
5. Explicit `--id` with auto-hash fallback (option **b**).
6. INFO-no-actions auto-hides; WARN/URGENT-no-actions stays.
7. Error handling: first two lines inline, "Show full error" button, 10 KB
   soft / 16 KB hard cap, wiped on dismiss.
8. Name: **Nagbert**.
