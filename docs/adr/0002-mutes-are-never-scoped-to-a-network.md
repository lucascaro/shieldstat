# Mutes are never scoped to a network or interface

Mutes may be scoped by duration (Snooze) or by Fact, and never by network or by interface. This
looks like a missing feature — "mute notifications on my home wifi" is the first thing anyone asks
for — so it is recorded here to stop it being added as an oversight.

## Why

A public IP at home is exactly as exposed as a public IP at a hotel. The packets do not know where
the router lives. Location-based mutes encode an intuition about safety that is simply false, and
they suppress the signal precisely where the user has stopped paying attention — which is where a
monitor earns its keep.

Interface-scoped mutes are worse. `en0` is `en0` at home, at a hotel, and at a conference. Muting
`en0` mutes the product.

## Consequences

Mute-by-Fact carries the same danger in a different key: a permanent mute on "global IPv6 on any
interface" silences that signal everywhere, forever. So Mutes are graded by Severity — `notice`
Facts may be muted permanently (a user who always has IPv6 is entitled to stop hearing about it),
while `alert` Severity accepts only a Snooze, which expires. Nothing that means "you are on the
open internet right now" can be permanently silenced.

All active Mutes are listed in settings with the date they were created and are individually
revocable. A Mute the user cannot see is a Mute they cannot reconsider.

Mutes are keyed to Facts while notifications are triggered by Severity Transitions, so the two must
be reconciled explicitly: a worsening Transition notifies unless *every* Fact that raised the
Severity is muted. A user who has permanently muted global IPv6 and then joins a network handing
out both a global IPv6 and a public IPv4 is still notified, because the `globalV4` Fact that drove
the `alert` is not muted.

Mutes suppress notifications only. The menu bar glyph always reflects true Severity, muted or not.
The glyph never lies.
