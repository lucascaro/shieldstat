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

Ties between equal-Severity Links are broken by table order, so Private wins over Carrier NAT
which wins over No Network. This only affects the words shown, never the glyph.

Offline is `ok` rather than unknown: from this check's perspective a machine with no network is
genuinely safe. This is the classic monitoring failure mode (green when blind) and is accepted only
because the claim is narrow. A future check whose subject can be *unobservable* needs a distinct
unknown Severity.

## Timing

`NWPathMonitor` for change events, plus a 5-minute safety poll — SLAAC and DHCP renewals do not
reliably surface as path changes, and a confidently wrong widget is worse than a 4-minute stale one.

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

## UI

Single shield glyph, differentiated by *shape* rather than colour alone, so Severity survives
colourblindness and monochrome menu bar rendering. A short text label appears alongside it —
`always | never | whenNotOK`, default `whenNotOK`. Clicking opens the detail panel listing each
Fact, which interface carries the default route, and recent Transitions.

`MenuBarExtra` with `.window` style; `LSUIElement` set so there is no Dock icon.

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

`UserDefaults` for settings and Mutes. The last ~50 Transitions are held in memory only and are
lost on quit — including the auto-start after every reboot. Persisting them would make the app
useful for forensics and would also create a file recording the user's network history, which is
itself a privacy artifact worth protecting. Revisit only with a retention policy.

Launch at login uses `SMAppService.mainApp`, revocable by the user in System Settings.

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
- **Persisted Transition history.**
- **Any settings beyond the five listed above.**
