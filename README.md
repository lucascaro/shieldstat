# ShieldStat

A passive macOS menu bar monitor of local security posture. It observes and reports; it never
protects, blocks, or intervenes.

**Not a VPN, firewall, or antivirus.** It changes nothing about your machine. The only thing it does
is tell you what is already true.

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
baseline. The warning is then about listeners that appear *later*.

Dismissals are ignored the moment the machine becomes reachable. A dismissal means "this service is
expected on my machine", not "this service is safe to expose".

Process names come from an unprivileged `lsof`, which sees the current user's sockets — enough to
name Spotify, Docker and the like. System daemons show as bare port numbers; naming those would need
a root helper, and a passive monitor should not require more privilege than the thing it monitors.

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
swift test --package-path Core     # 67 tests, no network, no machine dependencies
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
