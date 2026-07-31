# ShieldStat

A passive macOS menu bar monitor of local security posture. It observes and reports; it never
protects, blocks, or intervenes on its own.

**Not a VPN, firewall, or antivirus.** Nothing it does happens on its own initiative. It watches, it
tells you what is already true, and it hands you the controls — the one thing it will act on is a
button you pressed, and quitting a process you own is a user action, not the app intervening.

## What it currently checks

**Address exposure** — whether this Mac holds a globally-routable address, which is the difference
between sitting behind NAT and sitting on the open internet.

| What it sees | What it says | Severity |
|---|---|---|
| RFC1918 / IPv6 ULA only | Private | ok |
| `100.64/10` | Carrier NAT | ok |
| `169.254/16` only | No Network | ok |
| A global IPv6 address | Publicly Addressable | notice |
| A global IPv4 address | Directly Exposed | alert |
| Something listening on all interfaces | Open Ports | notice |
| Either exposure state, **and** something listening | Exposed Service | alert |

**Listening services** — TCP sockets in LISTEN state, by bind scope. Anything bound to all
interfaces is a problem waiting for a network change, so it is flagged — but a Mac has around 20 of
them, so each is individually dismissible, and there is a bulk action to accept the current set as a
baseline. The warning is then about listeners that appear *later*. The handful macOS starts on its
own behalf — AirPlay, Continuity, Handoff — are dismissed out of the box, behind a toggle you can
switch off. SSH, file sharing, NFS and Screen Sharing are not: somebody turned each of those on.

Dismissals are ignored the moment the machine becomes reachable. A dismissal means "this service is
expected on my machine", not "this service is safe to expose". A dismissal covers one port; covering
every port a process opens is a second, separate click, because Docker's whole job is publishing
ports you did not ask about individually.

Process names come from `netstat -anv` and `lsof`, both unprivileged. `netstat` names every socket
including root-owned daemons, but truncates; `lsof` is untruncated but only sees your own sockets, so
it fills in the names `netstat` mangles. On the author's machine all 22 wildcard listeners are named.
Each listener also carries a **?** button that searches the web for what it is and whether it should
be listening.

Clicking a listener opens a window naming what holds it: the pid, the executable path as the kernel
reports it, the user it runs as, when it started and how long it has run, the command line, the exact
address it bound, and every other port the same process is listening on. A port held by more than one
process — a pre-forking server, an `SO_REUSEPORT` listener — gets a section each rather than a guess
at which is the real one.

From there you can quit the process, force quit it behind a confirmation, or reveal the binary in
Finder. Quitting is the user's action, not the app's: nothing stops on its own. Processes you do not
own are read-only, and the buttons say so instead of failing when pressed — signalling them needs a
privileged helper ShieldStat does not install. A pid is only ever signalled after its start time is
re-read and still matches what the window is showing, so a pid the system has since recycled is
refused rather than killed by mistake.

Every interface that is up and running is evaluated the same way. A public address on a forgotten
secondary interface counts exactly as much as one on your primary connection — the default route
governs which way your packets *leave*, not who can reach you.

### What it deliberately does not claim

That you are **reachable**. A globally-routable address may sit behind a filtering router, and an
address can be assigned without being routed to you upstream. Neither is observable from the host.
The strongest honest claim is "this Mac holds a globally-routable address", and the app never says
more than that.

## Status

Working and in daily use by its author. Unsigned, so it is a build-it-yourself project for now.

**Notifications do not work yet.** The `.timeSensitive` interruption level requires an entitlement
that macOS refuses under ad-hoc signing — the kernel kills the app at launch if it is present, and
without it the authorization prompt never appears. This needs a Developer ID. Everything else — the
menu bar glyph, the detail panel, settings, mutes, the debounce — works today.

## Building

Requires Xcode 26 or later.

```sh
git clone https://github.com/lucascaro/shieldstat
cd shieldstat
swift test --package-path Core     # 120 tests, no network, no machine dependencies
xcodebuild -project ShieldStat.xcodeproj -scheme ShieldStat -configuration Release build
```

The logic lives in `Core/`, a plain Swift package with no dependencies. `App/` is the macOS shell.

## How it is put together

Sensors observe and emit **facts** with no judgment attached. A single **policy** function maps the
whole set of facts to a state and a severity. That split exists so a second check can correlate with
the first — "something is listening *and* you are directly exposed" is a thing this can say that
`ifconfig` cannot.

Everything in `Core/` is a pure function over data, so the entire test suite runs without a network
in under a second.

## Mutes

Mutes suppress notifications only. **The menu bar always shows the true severity** — muting is not
blinding.

You cannot mute by network or by interface. A public IP at home is exactly as exposed as a public IP
at a hotel, so location-based mutes would encode a false intuition about safety and would go quiet
in precisely the place you have stopped paying attention. Mutes are keyed to what was observed, and
anything meaning "you are on the open internet right now" can be snoozed but never permanently
silenced.

## Privacy

No telemetry. No accounts. No background network calls.

The one thing that leaves your machine is the **?** button next to a listener,
which opens a web search for what that process is and whether it should be
reachable. It only fires on a click, and it sends the process name and port to
the search engine. Nothing else in the app talks to the network.

Transitions are appended to `~/Library/Application Support/ShieldStat/transitions.jsonl`, pruned to
14 days. Records hold the timestamp, the severities, the state, interface names, and address
*classes* — never an address.

## Documentation

- [CONTEXT.md](CONTEXT.md) — the glossary. Start here; the code uses these words deliberately.
- [docs/DESIGN.md](docs/DESIGN.md) — settled design, including what was measured rather than assumed.
- [docs/adr/](docs/adr) — the three decisions that were hard to reverse.

## License

MIT
