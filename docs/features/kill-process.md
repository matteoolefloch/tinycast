# Kill Process

`Kill Process` lists every running process as a palette screen, heaviest CPU users first, so a
runaway helper, a hung app or a stray dev server can be found by name, path or PID and ended without
opening Activity Monitor. One `ps` sample fills a snapshot, ranking runs in memory over it, and a
kill re-proves the process's identity before it signals.

## Invariants

- **A signal only reaches the process the row sampled.** Every entry carries the kernel's start stamp
  (`kinfo_proc.p_starttime`), and `ProcessKiller` re-reads it immediately before `kill(2)`. A PID that
  exited, or that the kernel has handed to a new process since the sample, reports `.gone` and is
  never signalled.
- **The snapshot never reorders under the selection.** The palette's selection is an index into
  `session.filtered`, so a timer-driven refresh would slide a different process under ↵. A reload
  happens only on open and on ⌘R, and ⌘R puts the highlight back on the same PID. A kill never
  removes its row: `signalledPIDs` dims it in place, so a repeated ↵ lands on the same, now ended,
  process instead of the one below it.
- **The kernel, `launchd` and Tinycast are never listed.** `ProcessListParser.isListed` drops PID 0,
  PID 1 and the running PID, so none of them can be selected, let alone signalled.
- **Privilege is escalated only on request, through macOS's own prompt.** A process another user owns
  answers `EPERM`; the coordinator then asks through `DialogController` whether to kill it as an
  administrator, and only a yes runs `osascript … with administrator privileges`, whose password
  prompt macOS draws. The prompt can outlast the process, so the root line built by
  `AdministratorKillCommand` re-checks `ps`'s `lstart` stamp itself before it kills. It carries two
  integers and that stamp, vetted to letters, digits, colons and spaces, so nothing a process
  controls (its name, its path) ever reaches a shell.
- **↵ asks, ⌘↵ insists.** `Kill Process` asks a Dock app to quit through `NSRunningApplication.terminate()`,
  so unsaved documents still get their save sheet, and sends any other process `SIGTERM`, which it
  may catch to clean up or refuse; `Force Kill Process` sends `SIGKILL`, which nothing can catch.
  Neither confirms first, matching Raycast: the identity check above is what makes a mistaken kill
  impossible, not a dialog.
- **The palette stays up after a kill**, so a family of helpers can be cleared one row at a time;
  a HUD reports each result.
- **Sampling runs off-main and holds no actor state.** `ProcessSampler.sample` is `@concurrent`;
  `NSRunningApplication` is read on the main actor first and handed in as a `Sendable` table.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/ProcessEntry.swift` | one sampled process: PID, name, path, CPU, memory, owner, start stamp, icon bundle |
| `Model/ProcessListParser.swift` | the `ps` arguments, the line parser and the listing rule |
| `Model/ProcessQuery.swift` | the empty-query order (CPU, then memory, then name) and ranking |
| `Model/ProcessKillOutcome.swift` | `kill(2)`'s answer as a case, and the two signals |
| `Model/AdministratorKillCommand.swift` | the root shell line and the stamp vetting it relies on |
| `Service/ProcessSampler.swift` | **Impure.** runs `ps`, reads `proc_pidpath` and `sysctl(KERN_PROC_PID)` |
| `Service/ProcessKiller.swift` | **Impure.** `kill(2)`, and the administrator path through `osascript` |
| `Service/KillProcessSession.swift` | the observable state — sample lifecycle, snapshot, filtered rows |
| `UI/KillProcessCoordinator.swift` | kill, copy and reveal actions, the administrator confirmation, reports |
| `UI/KillProcessScreen.swift` | the `PaletteScreen` conformance, ⌘K actions and chords |
| `UI/KillProcessList.swift` | the row: icon, name, PID (with a lock for another user's), CPU, memory |

`ps` is used rather than `proc_pidinfo` because it is setuid: it reads CPU and memory for processes
other users own, which `PROC_PIDTASKINFO` refuses an unprivileged caller. It runs with `LC_ALL=C` so
`%cpu` always uses a decimal point, and its output is read to EOF before the wait, since a full
listing outgrows a pipe's buffer.

A process's name is its `NSRunningApplication.localizedName` when it has one, otherwise the last
component of its executable path. Its icon is the innermost `.app` its executable sits in, so a
`Chrome Helper (Renderer)` shows its own helper bundle and a bare daemon shows a terminal glyph.
Ranking matches the name as a name and the path as an owner — the same split Window Switcher uses —
and a query that is exactly a PID ranks that process first.

## Actions

| Action | Key | Effect |
| --- | --- | --- |
| Kill Process | ↵ | a Dock app's own Quit, otherwise `SIGTERM` |
| Force Kill Process | ⌘↵ | `SIGKILL` |
| Copy Name | ⌥⌘C | |
| Copy Path | ⌃⌘C | |
| Copy PID | | |
| Show in Finder | ⌘F | the app bundle when there is one, else the executable |
| Reload Processes | ⌘R | a fresh sample, the highlight kept on its PID |

## Where it is reachable from

The launcher, as `CommandID.killProcess` (`command:kill-process`), so it takes aliases and a global
shortcut like any other command and ships unbound. No pane owns it, so it is listed under Settings ›
Commands; it adds no `AppEntry.Kind`, no preference and no `VisibilityStore` category.
