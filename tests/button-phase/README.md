# Kumo Button phase oracle

The first headless measurement increment is supported on Darwin only because
its CDP keyboard input records use macOS native virtual key codes. Other hosts
write an unverified report with an unsupported-host preflight and do not
start Chromium.

On Darwin, KUMO_HEADLESS_CHROME may select a custom browser executable, but
the value must be an absolute path. The runner resolves it to a real path,
checks that it is an executable regular file, and uses that same resolved path
for hashing, spawning, and evidence. Relative overrides are rejected. Without
an override, the runner uses the standard Google Chrome application path.

The supported runner entry point is scripts/measure_button_phases.py, which
owns the Node/Chrome process group and evidence receipts. This oracle records
raw browser output and phase observations; it does not classify conformance.
