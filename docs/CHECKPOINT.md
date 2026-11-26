# Checkpoint: free-tv Layer 1 pushed

Slice: curator service (Layer 1 of Apple TV project).
Done: merge/probe/quarantine CLI, 25 tests green, daily Pages workflow.
Remains: first workflow run + Pages live URL, UHF test, Layer 2 tvOS app.
Next command: `gh workflow run curate --repo sensei-hq/free-tv`, then enable
Pages on `gh-pages` and verify playlist URLs.
Open questions: user's country slice to add; strict-probe false positives.
Known-broken: none. (/sensei:checkpoint unavailable in this runtime.)
