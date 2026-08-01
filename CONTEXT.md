# ShieldStat

A passive macOS menu bar monitor of local security posture. It observes and reports; it never
protects, blocks, or intervenes on its own. Not a VPN, firewall, or antivirus.

Passive is about initiative, not capability. Nothing here decides by itself that a process should
stop — no rules, no automatic action, nothing that runs while you are not looking. What the app does
offer is a button: quitting a process you own is a user action, and refusing to carry it out would
not make the app more honest, only less useful. The line is that every effect on the machine traces
back to a press.

## Language

### Observation

**Sensor**:
A pure function that reads system state and emits Facts. Contains no judgment about whether what
it saw is good or bad.
_Avoid_: Check, monitor, probe, scanner

**Fact**:
Something a Sensor observed, stated without evaluation. "en0 holds one global IPv4 address" is a
Fact; "en0 is dangerous" is not. For address exposure a Fact is one `(interface, Address Class,
count)` — one per class per interface, not one per address.
_Avoid_: Finding, result, reading, signal

**Address Class**:
The category a network address falls into: `private`, `carrierNAT`, `noAddress`, `globalV4`, or
`globalV6`. Derived purely from the address bits.
_Avoid_: IP type, range, scope

**Link**:
The pairing of an interface with an address it holds, and so with an Address Class. Exposure is a
property of a Link, not of a host or an interface. Policy evaluates each Link independently and
takes the highest Severity.
_Avoid_: Connection, NIC, adapter

**Default Route Interface**:
The interface carrying outbound traffic to unmatched destinations. Display context only — it
describes egress and says nothing about who can reach you.
_Avoid_: Primary interface, main connection, active interface

**Listening Socket**:
A TCP socket in LISTEN state, identified by its port and its Bind Scope, with the process name
attached wherever it can be read without privilege. The same service listening over IPv4 and IPv6 is
one Listening Socket, not two.
_Avoid_: Open port, service, daemon

**Socket Owner**:
The pairing of one Listening Socket with the pid holding it, carrying the literal bind address rather
than the Bind Scope it reduces to. Deliberately not part of a Listening Socket: that type collapses
the IPv4 and IPv6 halves of one service into a single entry, and a pid or a literal address would
split them back apart and change the count the verdict is drawn from. One port can have several
Socket Owners, from a pre-forking server or an `SO_REUSEPORT` listener.
_Avoid_: Owner, holder, binding

**Listener Process**:
What a [[Socket Owner]]'s pid turns out to be: its executable path, the user it runs as, when it
started, what it was launched with, and every Listening Socket it holds. Read only when the user asks
for it, never on the posture check's timer, and never fed back into a verdict — it answers "what is
this", which is a question the app is not willing to answer on the user's behalf.
_Avoid_: Process info, details, metadata

**Dismissal**:
A declaration that a Listening Socket is expected on this machine. Suppresses the `notice` it would
otherwise raise, and is ignored entirely once the machine becomes reachable — it means "expected",
never "safe to expose". Keyed to the port. Dismissing every port a process opens, now and in future,
is a [[Broad Dismissal]] and a separate action. Distinct from a [[Mute]], which suppresses
notifications and never changes what the glyph shows.
_Avoid_: Ignore, allowlist, exception, mute

**Broad Dismissal**:
A Dismissal keyed to a process name rather than a port, covering every port that process opens
including ones it has not opened yet. Never what a click on a listener does — Spotify's rotating
peer-discovery port is the case that wants it, and Docker publishing arbitrary ports is the case that
makes it dangerous. The [[System Service Baseline]] is the one set of Broad Dismissals the user did
not make individually, which is why it is confined to processes macOS runs and sits behind a toggle.
_Avoid_: Blanket ignore, allowlist, trust

**System Service Baseline**:
The fixed set of processes macOS starts on its own behalf, dismissed automatically so a fresh
install is not already warning. Excludes anything a user switched on — SSH, file sharing, NFS,
Screen Sharing. Automatic dismissal is a blind spot by construction, so it is a visible toggle.
_Avoid_: Whitelist, known good, safe list

**Bind Scope**:
Where a Listening Socket is bound: `loopback`, `allInterfaces`, or `specificAddress`. Decides
whether anything outside this machine could reach it at all.
_Avoid_: Interface, binding, address

### Judgment

**Policy**:
The single function mapping a set of Facts to a State and a Severity. All judgment in the system
lives here and nowhere else.
_Avoid_: Rules engine, evaluator, analyzer

**State**:
The user-facing name for a situation: Private, Carrier NAT, Open Ports, Publicly Addressable,
Directly Exposed, Exposed Service, No Network, Offline. Produced by Policy, never by a Sensor.
_Avoid_: Status, condition, mode

**Severity**:
How much a State should worry you: `ok`, `notice`, or `alert`. Produced by Policy.
_Avoid_: Level, priority, risk score

**Publicly Addressable**:
The machine holds a globally-routable address. It does not claim the machine is reachable —
whether anything filters in between is unknowable locally.
_Avoid_: Public IP, exposed, reachable, open

**Directly Exposed**:
The machine holds a globally-routable IPv4 address, meaning no NAT stands between it and the
internet.
_Avoid_: Public IP, unprotected, naked

**Exposed Service**:
The machine is Publicly Addressable or Directly Exposed *and* holds a non-loopback Listening Socket.
Neither fact alone produces this State.
_Avoid_: Open port, vulnerable, attack surface

**Reachable**:
Confirmed to accept an inbound connection originating from the internet. Reserved — no Sensor can
currently establish this, and nothing may claim it until one can.
_Avoid_: Open, exposed, accessible

### Time

**Observed Severity**:
The Severity of the most recent evaluation. Drives the menu bar glyph. Changes instantly.
_Avoid_: Current status, live severity

**Settled Severity**:
The Severity that has held steady long enough to be believed. Drives notifications. May lag
Observed Severity, which is intended — a laptop waking onto a network passes through several
transient states in seconds.
_Avoid_: Debounced status, stable state, confirmed severity

**Transition**:
A change from one Settled Severity to another. Worsening Transitions are what the app notifies
about — unless every Fact that raised the Severity is muted.
_Avoid_: Event, change, alert

### Suppression

**Mute**:
A suppression of notifications. Never suppresses the glyph — the glyph always shows true Severity.
Muting is not blinding.
_Avoid_: Ignore, disable, snooze (Snooze is one kind of Mute), exception

**Snooze**:
A Mute bounded by time, applied to exactly the Facts currently raising the Severity. The only kind
of Mute permitted against `alert` Severity. Not a separate suppression channel — a Snooze appears
in the list of Mutes and is revoked the same way.
_Avoid_: Pause, defer, remind me later

**Fact Mute**:
A Mute keyed to a specific Fact, suppressing notifications about it wherever it occurs. Permitted
permanently at `notice` Severity, never at `alert`.
_Avoid_: Rule exception, allowlist, whitelist
