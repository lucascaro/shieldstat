# Sensors emit facts; a single policy function assigns severity

Sensors observe system state and emit Facts with no judgment attached; one Policy function maps
the full set of Facts to a State and a Severity. We chose this over the simpler design where each
sensor returns its own `ok | notice | alert` because severity is frequently a function of *several*
facts at once, and a sensor can only see its own.

## Considered Options

**Sensors emit severity directly.** Roughly one type and one function smaller. Rejected because it
breaks on the second check. "A service is listening on 0.0.0.0" is a shrug on a NAT'd laptop and an
emergency on a machine holding a public IPv4 — but the listening-ports sensor cannot see the
address sensor's facts. The options are to hardcode pessimism (false alarms), or to let sensors
read each other (the coupling this design exists to avoid).

**Sensors emit facts; policy assigns severity.** Chosen. Cross-fact correlation is the actual
product; "do I have a public IP" alone is something `ifconfig` already answers.

## Consequences

Sensors are pure functions over captured system state, so they test against fixture tables with no
network and no machine-specific behaviour. Policy is a pure function over Facts and tests the same
way. Everything that touches the live system is confined to one thin adapter that is not
unit-tested.

The user-facing vocabulary (Publicly Addressable, Directly Exposed) belongs to Policy, not to
Sensors. A Sensor saying `.directlyExposed` would be smuggling a judgment back in — the terms are
inferences about NAT and filtering, not observations.

This is deliberately not a rules engine. Policy is one function with a switch, readable end to end
in under a minute. If it ever stops being readable, that is a signal to reconsider the domain
model, not to add a rules DSL.
