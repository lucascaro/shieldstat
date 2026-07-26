# ShieldStat

A passive macOS menu bar monitor of local security posture. It observes and reports; it never
protects, blocks, or intervenes. Not a VPN, firewall, or antivirus.

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

**Policy**:
The single function mapping a set of Facts to a State and a Severity. All judgment in the system
lives here and nowhere else.
_Avoid_: Rules engine, evaluator, analyzer

**State**:
The user-facing name for a situation: Private, Carrier NAT, Publicly Addressable, Directly
Exposed, Exposed Service, No Network, Offline. Produced by Policy, never by a Sensor.
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
