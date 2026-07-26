# ShieldStat — settled design

Decisions that are settled but too reversible to warrant an ADR. Vocabulary is defined in
[CONTEXT.md](../CONTEXT.md); the three load-bearing decisions are in [docs/adr](./adr).

## Check #1 — address exposure

Classifies every address on every up, running, non-loopback interface:

| Range | Address Class |
|---|---|
| `10/8`, `172.16/12`, `192.168/16`, `fc00::/7` | `private` |
| `100.64/10` | `carrierNAT` |
| `169.254/16` | `noAddress` |
| `2000::/3` | `globalV6` |
| other IPv4 | `globalV4` |
| `127/8`, `::1`, `fe80::/10` | excluded |
| `0/8`, `224/4`–`255/4`, `ff00::/8` | excluded — unspecified, multicast, reserved, broadcast |

`carrierNAT` is `ok` and silent. It is the one row where the app knows less than it appears to:
Tailscale's mesh and a carrier's CGNAT are indistinguishable from these bits alone. Both are
unreachable from the internet, so the verdict is right for the wrong reason.

## Policy table

Policy classifies each Link independently, then takes the **maximum Severity** across all Links.
The State is named from the highest-severity Link. There is no match ordering and no quantifier
over the whole set — a machine with a failed DHCP lease on ethernet and a working private address
on wifi is Private, because `max(ok, ok)` is `ok` and the private Link names it.

| Address Class of a Link | State | Severity | Notify |
|---|---|---|---|
| `private` | Private | `ok` | — |
| `carrierNAT` | Carrier NAT | `ok` | no |
| `noAddress` | No Network | `ok` | no |
| `globalV6` | Publicly Addressable | `notice` | yes, debounced |
| `globalV4` | Directly Exposed | `alert` | yes, immediate |

With no up interfaces there are no Links: Offline, `ok`.

**Correlation.** If the address severity is at least `notice` *and* something is listening on a
non-loopback socket, the state becomes **Exposed Service** at `alert`. Neither fact alone justifies
it: a typical Mac has ~25 wildcard listeners at all times, so listening is `ok` by itself, and being
reachable with nothing listening is milder than being reachable with an open door. This is the
correlation the sensor/policy split exists for — check #1 and check #2 each know only their own
facts, and only Policy sees both.

Ties between equal-Severity Links are broken by table order, so Private wins over Carrier NAT
which wins over No Network. This only affects the words shown, never the glyph.

Offline is `ok` rather than unknown: from this check's perspective a machine with no network is
genuinely safe. This is the classic monitoring failure mode (green when blind) and is accepted only
because the claim is narrow. A future check whose subject can be *unobservable* needs a distinct
unknown Severity.

## Check #2 — listening services

TCP sockets in LISTEN state, classified by bind scope: `loopback` (`127.0.0.1`, `::1`),
`allInterfaces` (`*`, `0.0.0.0`, `::`), or `specificAddress`. A port listening on tcp4 and tcp6 is
one service, not two.

Read by parsing `netstat -an -p tcp`, unprivileged. `lsof` would name the process but sees only the
current user's sockets without root — measured, 27 of 45 on a real machine — and closing that gap
needs a permanently installed root helper. A passive monitor should not require more privilege than
the thing it monitors, so the check reports ports and not process names.

Sockets are enumerated only when the address check already reports at least `notice`. Behind NAT
they cannot change the verdict, so the common case spawns no subprocess at all.

TCP only. UDP has no listen state, so a bound UDP socket may be a client's ephemeral port rather
than a service.

## Timing

`NWPathMonitor` for change events, plus a 60-second safety poll. Path events are not reliable for
this: measured, adding a public IPv4 to a secondary interface produced no path event at all, and the
change was only picked up by the poll. SLAAC and DHCP renewals are similarly quiet. The poll is
therefore the real floor on staleness, not a backstop — `getifaddrs` costs microseconds, so a short
interval is nearly free. The panel also has a manual Refresh for when the user does not believe it.

Observed Severity updates instantly and drives the glyph. Settled Severity requires 30 seconds of
stability and drives notifications. Entry into `alert` bypasses the debounce entirely. Debounce
duration and bypass exceptions are configurable. No notification fires on the first evaluation
after launch.

The debounce uses an injected clock so it tests without sleeping.

## Notifications

`.timeSensitive` interruption level — presents immediately, lights the screen, breaks through Focus.
`.critical` requires an Apple-approved entitlement that is not available for this. Whether the
notification persists as an alert or fades as a banner is the user's System Settings choice and
cannot be forced.

**Notifications do not work under ad-hoc signing, and this is not a bug to fix in code.** Measured
on macOS 26.4 with a probe bundle:

- With `com.apple.developer.usernotifications.time-sensitive` embedded and ad-hoc signing, the
  kernel SIGKILLs the app at launch (exit 137). The same bundle without the entitlement runs.
- Without the entitlement, `requestAuthorization` returns `false` and `authorizationStatus` stays
  `notDetermined` — no prompt is ever shown to the user.

So the entitlement is declared in `Config/ShieldStat.entitlements` but deliberately *not* wired into
`App.xcconfig`. Notification delivery stays untestable until Developer ID signing lands, which
promotes signing from a packaging concern to a functional prerequisite for the notification feature.
Everything else — glyph, panel, settings, mutes, debounce — works ad-hoc today.

`Notifier` re-reads authorization on every delivery rather than caching it at launch, so a user who
answers the prompt late, or grants permission afterwards in System Settings, is heard from without
relaunching.

## UI

Single shield glyph, differentiated by *shape* rather than colour alone, so Severity survives
colourblindness and monochrome menu bar rendering. A short text label appears alongside it —
`always | never | whenNotOK`, default `whenNotOK`. Clicking opens the detail panel listing each
Fact, which interface carries the default route, and recent Transitions.

`NSStatusItem` with an `NSPopover`, not `MenuBarExtra`; `LSUIElement` set so there is no Dock icon.

The switch was made while diagnosing an invisible menu bar item, and the diagnosis was wrong — a
menu bar manager (Barbee) was hiding it, and `MenuBarExtra` would very likely have worked. The
switch was kept anyway for one reason: `MenuBarExtra` cannot report whether an item exists, how wide
it is, or where it was placed, so "why can't I see it" is unanswerable without someone looking at a
screen. `NSStatusItem` logs its own geometry, which is what finally identified the cause — the item
was 82pt wide with its symbol resolved, at y 1084–1117 (correctly in the menu bar strip) and
x −9366 on a 1728-wide screen.

Settings open via a `Window` scene, `openWindow`, and `NSApp.activate()`. Apple's blessed
`Settings` scene with `SettingsLink`/`openSettings` does not front reliably from an `.accessory`
app on macOS 26, and the published workarounds require toggling activation policy with timing
delays. The chosen path is entirely public API.

Verified empirically on macOS 26.4 with a throwaway `LSUIElement` build: `openWindow(id:)` alone
produces a window that is visible but neither key nor main; `NSApp.activate()` then makes it key
and main. `activationPolicy` stays `.accessory` throughout — no policy toggling, no timing hacks.
`makeKeyAndOrderFront` afterwards changes nothing. Both calls are required; neither is optional.

Settings surface: label display mode, debounce duration, debounce bypass exceptions, launch at
login, and the list of active Mutes.

## State

`UserDefaults` for settings and Mutes. The last ~50 Transitions are held in memory for the detail
panel and are lost on quit.

Transitions are **also** appended to a JSONL journal at
`~/Library/Application Support/ShieldStat/transitions.jsonl`. This reverses the original decision to
keep history in memory only. That decision assumed the trade was "forensic value versus owning a
file of the user's network history" — but with launch at login, the in-memory buffer only ever
covers the time since the last reboot, so the app could not answer the questions a trial exists to
ask. Unified logging was tried first and persists nothing for an ad-hoc-signed bundle.

The privacy objection is answered by what gets written, not by refusing to write: a record holds the
timestamp, both Severities, the State, the interface names, and the **Address Classes** — never an
address. "globalV4 on en0" answers how often and whether it flapped; the address itself adds nothing
a trial needs.

Retention is the policy the original decision asked for: 14 days, pruned once at launch rather than
on every append, with a 5,000-record hard cap as a backstop against a pathological flap. Encoding
and retention live in `TransitionJournal`, which is pure and tested; the file adapter only touches
the disk. A corrupt line loses one record, never the file.

Launch at login uses `SMAppService.mainApp`, revocable by the user in System Settings.

## Naming deviation

The glossary term is **State**; the Swift type is `PostureState`. A type named `State` is ambiguous
with SwiftUI's property wrapper in every view file. The glossary word is unchanged.

## Build

Plain Xcode project, single target. Kept deliberately boring — no custom build phases, no per-file
settings, configuration in `.xcconfig` files rather than clicked into the GUI — so migrating to
XcodeGen later stays an afternoon rather than an archaeology project.

Tests use Swift Testing. Sensors and Policy are pure and test against fixture tables covering the
real `ifconfig` output, CGNAT, multi-GUA SLAAC, and secondary-interface exposure.

## Deferred

- **Check B — external reachability.** Upgrades "Publicly Addressable" to confirmed reachable or
  confirmed filtered. Requires something on the internet connecting inward, meaning infrastructure
  that would log every user's IP over time. Acceptable to run for oneself; an ugly thing to own on
  others' behalf.
- **Developer ID signing and notarization.** Blocks handing a build to a friend, since Gatekeeper
  refuses unsigned apps and the override is buried. Packaging, not architecture.
- **Any settings beyond the five listed above.**

## Dogfooding instrumentation

Review a trial with:

    jq -r '"\(.at) \(.state) \(.from)->\(.to) \(.interfaces|join(","))"' \
      ~/Library/Application\ Support/ShieldStat/transitions.jsonl

Transitions are also emitted to unified logging (`subsystem: dev.lucascaro.ShieldStat`). That
channel persists **nothing** for an ad-hoc-signed bundle — measured: zero entries by subsystem or by
process name. It is left in place because it should start working under a real signature, but the
JSONL journal is the one to trust.
