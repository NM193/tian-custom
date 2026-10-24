# tian-custom backlog

Personal fork of [tian](https://github.com/psycoder-sup/tian) (MIT). Single user, no distribution.

**Why it exists:** I run 7+ Claude Code sessions in parallel across client projects. The fork
changes how tian looks and adds what my workflow is missing, while the released tian stays my
daily tool and is never put at risk.

## Ground rules

- Work happens on `custom`. `main` mirrors upstream: `git switch main && git pull`, then merge
  `main` into `custom`.
- New code goes in fork-only places: `tian/Custom/`, `scripts/custom/`, `project.dev.yml`.
  Upstream files change only when unavoidable, and every such edit carries a `tian-custom:` comment
  (`grep -rn "tian-custom:"` lists them all).
- Keep `LICENSE` and `THIRD-PARTY-NOTICES.md`.
- Build: `scripts/custom/build-ghostty.sh` (first time and on Ghostty pin bumps), then
  `scripts/custom/build-dev.sh [--open]`. The result is `tian-dev.app` in `.build/dev`. Never run
  `scripts/install.sh`, which overwrites `/Applications/tian.app`.
- Tests: `xcodebuild test -project tian-dev.xcodeproj -scheme tian -configuration Debug -derivedDataPath .build/dev`

- **Visual work is approved in the browser first.** Every visual change starts as an HTML mockup,
  including transitions and animations. It gets implemented in SwiftUI only after I approve it.

Status values: `idea` → `refined` → `designed` → `in progress` → `done`.
Every item gets its own design → plan → implementation cycle before any code.

## Priority

1. Visual redesign
2. Workspace organization: client folders, in-app creation, color/icon, task templates, archive
3. Attention: status clarity, notifications, next waiting session, menu bar item, quick reply
4. Cost and context % per session
5. Command palette (⌘K)
6. Client reporting: time per client, daily summary
- Quick win, any time: open the project in Zed/Cursor

## Items

### 1. Visual redesign
**Status:** refined

**Want:** both a new visual style and a different layout, across all four areas:
- sidebar
- overview (⌘⇧O)
- inspect panel
- session area and window (header, terminal panel, divider, titlebar)

**Direction:** decided with side-by-side browser mockups. The options:
- **(A) Tzz** (`../yt-mp3`, tokens at the top of `src/styles.css`):
  - **Palette:** dark only, warm monochrome, editorial. Bone text `#fffddc` on `#181616`, three
    greys, one amber accent `#f7ab29`, 1px hairlines, no shadows. Native vibrancy under a warm
    tint.
  - **Type:** Instrument Serif for headings only, SF for the interface, SF Mono for labels.
    Rule: "clickable = sans and brighter; read-only = mono, uppercase, dim".
  - **Motion:** one gesture, a wipe from below (900 ms, `cubic-bezier(.7,0,.2,1)`); rules draw
    from the left.
  - **Status:** idle is muted, busy is an accent pulse, done is bone. There is no red or green.
- **(B)** a new direction designed together.

**Any direction must solve:**
- **More states than Tzz has.** Item 3 asks for clearer states, and with one accent they have
  to come from shape, motion and text, not just hue.
- **The terminal itself.** Ghostty draws pane content with its own theme, so the chrome and the
  terminal colors must match. tian can already override Ghostty settings.
- **Fonts.** Bundling Instrument Serif (SIL OFL) means adding it to `THIRD-PARTY-NOTICES.md`.

**Today:** theming is not centralized. `Utilities/Colors.swift` holds 2 colors, and about 240
hardcoded color lines are spread across 33 view files. Restyling in place would conflict with
every upstream UI change.

**Approach:**
1. **Theme layer first (sub-project 1a).** Extract design tokens (colors, type, spacing,
   radii) into `tian/Custom/Theme`. Upstream views switch to tokens once. That is a one-time diff
   in upstream files; after it, style changes live in fork files only.
2. **Replacement views.** Then replace views area by area with fork-owned views, swapped in at
   one or two seams per area: 1b sidebar, 1c overview, 1d inspect panel, 1e session area and
   window.

The sidebar comes first because items 2 and 3 render there.

### 2. Workspace organization: client folders, in-app creation, color/icon, task templates, archive
**Status:** idea (the client model gets discussed when this is designed)

**Want:**
- **Client folders.** Add a parent folder (for example a client's folder) whose subfolders
  become workspaces, shown grouped under that client in the sidebar.
- **In-app creation.** Create folders and workspaces from inside the app.
- **Color/icon per client,** applied to all of that client's workspaces and sessions.
- **Task templates per client:** a new session with a preset prompt or mode (plan mode,
  worktree) in one click.
- **Session archive:** finished sessions leave the sidebar instead of being closed, and can be
  resumed later. tian already records `claude --resume <id>` as each pane's restore command.

**Today:**
- The hierarchy is Workspace → Session (upstream flattened it in ADR 0004) with no grouping level.
- ⌘⇧N opens the standard macOS folder picker (`Utilities/DirectoryPicker.swift`; it can create a
  folder). There is no in-app "new project" flow.
- Workspaces have no color or icon. `tian workspace create <name> --directory <dir>` exists.

**Approach sketch:**
- Model: Client folder (group) → Workspace (project) → Session (task).
- Groups are a fork-only layer: a fork-owned file maps groups to workspace ids and holds
  color/icon. That means no `state.json` migration and no clash with upstream persistence.
- The redesigned sidebar renders the groups.

**Open questions:**
- Does importing a folder create workspaces for all subfolders, or let me pick?
- Should new subfolders that appear on disk show up automatically?
- Is a new project just a folder, or also `git init`, a clone, or a template?
- Icon type: SF Symbol, emoji, or logo image?

### 3. Attention: status clarity, notifications, next waiting session, menu bar item, quick reply
**Status:** idea

**Want:** see at a glance, and get notified, when a session:
- asks me something (a question or a permission prompt)
- is working
- finished and asks me to test or review
- anything else that needs me

Plus ways to act on it:
- **Next waiting session:** one shortcut jumps to the session that has waited longest;
  repeating it cycles.
- **Menu bar item:** count of sessions waiting for me, plus a jump list; works when tian isn't
  focused.
- **Quick reply:** answer Allow/Deny or a short reply from a notification or the overview
  without switching sessions. `tian pane send` already exists as the primitive.

**Today:**
- **States.** Six states shown as dots: `needs_attention`, `active`, `busy`, `idle`, `failed`,
  `inactive`. `needs_attention` lumps permission prompts and questions together. `idle` lumps
  "finished, your turn" together with "nothing going on".
- **Reasons are thrown away.** Hook payloads already carry the reason (`tool_name`,
  `notification_type`, `message`), but `tian-hook-log.sh` only logs it. `tian status set`
  accepts a free-form label that the hooks never use.
- **Notifications.** `ClaudeSessionNotifier` posts banners on `needs_attention` and on "done",
  stays quiet while I'm viewing that session, and focuses the pane on click. It has no client
  name, no settings and no `failed` notification.

**Ideas:**
- **Distinct states with reason text:** "Permission: Bash", "Question", "Your turn" (unread
  until I look), "Asks you to test" (detected from the last assistant message), "Working 12m",
  "Background work", "Failed".
- **Waiting time** on waiting rows.
- **Same semantics everywhere:** sidebar, overview, notifications (with client name) and a Dock
  badge.
- **Notification settings:** per-event toggles and sound.

### 4. Cost and context % per session
**Status:** idea

**Today:** nothing. tian does not read transcripts or the statusline.

**Data source options:**
- **Claude Code statusLine JSON:** it carries `cost.total_cost_usd`; which context-window fields
  it carries depends on the Claude Code version, so verify that. Catch: I already have my own
  `statusLine` in `~/.claude/settings.json`, and tian's `--settings` would replace it. tian would
  have to wrap my command and pass its output through.
- **Transcript JSONL:** every hook payload includes `transcript_path`. Read the last assistant
  `usage` and divide context tokens by the model's window. Compute cost from tokens times a
  price table.

**Display:** sidebar row and/or overview card, with warning colors past thresholds.

**Open questions:** is $ meaningful on my plan, or is it tokens and usage limits? Which matters
more, cost or context?

**Risk:** medium to high. It depends on formats Claude Code can change.

### Quick win: open the project in Zed or Cursor
**Status:** idea

**Today:** nothing. There is no open-in-editor action and no Finder reveal.

**Approach:**
- a key action plus a menu item
- the folder is the active session's worktree or working directory, resolved the same way the
  inspect panel does it
- the folder opens through `NSWorkspace`

The shortcut needs a free combo, checked against tian's and Ghostty's bindings.

**Effort:** small. A good first feature for exercising the fork workflow end to end.

### 5. Command palette (⌘K)
**Status:** idea

**Want:** type to jump to any session or workspace, or run an action (new session, open in
editor, toggle panels).

**Note:** ⌘K is Ghostty's default clear-screen binding, so the palette shortcut needs a
deliberate choice: take over ⌘K or use another combo.

### 6. Client reporting: time per client, daily summary
**Status:** idea

**Want:**
- **Time per client:** how long sessions worked per client per day, for invoicing; exportable.
- **Daily summary:** what each session did today (prompts, commits), for standups and client
  reports.

**Depends on:** the client model (item 2). The activity data comes from the same hook stream
as item 3: busy/idle transitions with timestamps, plus prompts.

### Fork infrastructure (small, as needed)
- **Hook log namespacing:** `tian-hook-log.sh` writes `~/Library/Logs/tian/claude-hooks.log`
  for both apps.
- **A distinct tian-dev app icon,** to tell the two apps apart in the Dock and ⌘-Tab.
- **Agent instructions for the fork.** `CLAUDE.md` belongs to upstream; Claude sessions in this
  repo must use `scripts/custom/*` instead of upstream's build scripts.
- **Upstream sync routine:** merge `main` into `custom`, rebuild Ghostty if the pin moved, build,
  run tests.
- **Later:** a Release build of the fork as the daily driver, with its own identity, no Sparkle,
  and state migrated from tian.
