# Exposure is a property of a link, not of the default route

Every up, running, non-loopback interface is evaluated identically. Holding a globally-routable
address on a secondary interface carries the same Severity as holding one on the interface that
carries the default route.

## Why

The default route governs egress: it decides where outbound packets go for destinations that match
no more specific route. It says nothing about which addresses the outside world can reach.

If an interface holds a globally-routable address and the upstream routes that prefix to that link,
inbound packets arrive there and macOS replies out the same interface, because the prefix is
directly connected. macOS does not apply strict reverse-path filtering by default. The default
route never enters the decision.

An earlier draft of this design weighted non-default-route interfaces lower. That was wrong, and
backwards: a public address on an interface the user has forgotten about is arguably more dangerous
than one on the interface they think about daily.

## Consequences

Default-route status is retained as display metadata — the detail panel says which interface is the
internet connection, which is genuinely useful context — but it never modifies Severity.

The strongest claim any local Sensor may make is "this machine holds a globally-routable address."
It may not claim reachability. An address can be assigned but not routed upstream (stale lease,
dead link), and a filtering firewall may sit in front of a perfectly routable one. Neither is
observable from the host. Establishing actual reachability requires something on the internet
attempting a connection inward, which is a future capability with its own infrastructure and
privacy costs.

SLAAC privacy extensions place several global IPv6 addresses on one interface simultaneously,
rotating on a timer. Facts are emitted one per `(interface, Address Class)` with a count, not one
per address — otherwise the detail panel fills with six entries that change hourly and mean one
thing.
