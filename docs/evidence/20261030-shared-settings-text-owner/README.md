# Shared Settings text-owner checks — 2026-10-30

These are local checks of Yami commit
[`e4bb9ac5fdcc1a5bde0c98d4953e6b3723d9e8b5`](https://github.com/f4ah6o/Yami-kumo/commit/e4bb9ac5fdcc1a5bde0c98d4953e6b3723d9e8b5).
The consumer, harness and application source revisions are all that commit.
This evidence record was added later and does not claim a test of its own commit.
The tests ran on Debian 13 Linux x86_64, with moon `0.1.20261012`, moonc
`0.10.15+943464bfa`, Node `v24.19.0` and Chromium `154.0.8037.57`.

The native test manifest resolves published `f4ah6o/gpui@0.10.6` and
`f4ah6o/yami_kumo@0.2.3`. The framework source SHA for the registry package
was not established in this run. The earlier [published package audit](../../../tests/published-settings/README.md)
records the `0.10.6` archive digest as
`1f525737423f7ca83410fd23184f9bdea0a8eda81e7711b6e6dee968d7ab8b88`;
that historical digest was not independently rechecked for this run. The Web
DOM app uses the consumer's `pnpm-lock.yaml` and does not load gpui.

| Profile / command | Result | Retained output SHA-256 |
| --- | --- | --- |
| Scripted Linux native: `moon -C native test examples/common --target native --deny-warn` | PASS 6/6 | [native-common.txt](native-common.txt): `06cf40c963e0602c339d3575dbfd3f5d0e25fb183b57aa8023d5e70439dd65c1` |
| Portable adapter on Linux: `moon -C native test ui --target native --deny-warn` | PASS 86/86 | [native-ui.txt](native-ui.txt): `88875367177e00395d57a5eb9911ac03fbad7e6cd2445f08eef8fe75805f4e75` |
| Chromium headless: `SHARED_UI_CHROMIUM_EXECUTABLE=/usr/bin/chromium node --test tests/shared-ui/settings.test.mjs` | PASS 1/1 | [web-settings.txt](web-settings.txt): `9d96066a5c2a6cdf88487fa5f3ca9d86fc2c72193c9fb0208f2c695c46db5565` |

The Web build command was `moon build examples/shared_settings_dom --target js
--release --deny-warn`. The resulting `shared_settings_dom.js` SHA-256 was
`431fc252cf3d0b530e8ce05f0a7d6b17e785a8c238c57878d4530abb2cd695a0`.
The local [settings-web.json](settings-web.json) reports the same candidate
revision and synthetic composition. Native test executable hashes were not
captured. These local runs have no run URL.

The scripted regression asserts that a commit for an old session cannot reach
another focused field and that the replacement session can commit. Removing
the binding check made that regression fail. The Web check uses synthetic
composition events, not a live IME. It exercises validation, field-submit,
Tab / Shift-Tab, background key suppression, cancellation and field focus
restoration, then button-open, reopen and confirmation. It does not establish
live IME, candidate selection, physical keyboard or accessibility acceptance.
The native checks are portable tests and do not establish GUI or OS IME use.

The corresponding earlier-HEAD [CI run](https://github.com/f4ah6o/Yami-kumo/actions/runs/41071387379)
published a [`shared-ui-evidence` artifact](https://github.com/f4ah6o/Yami-kumo/actions/runs/41071387379/artifacts/12985216647)
with service-reported archive digest
`sha256:d69a97292f0a704834ef5023003f858a142322556335cb626c8d827ea1f71c51`.
Artifact download returned HTTP 403 in this environment, so its contents and
digest were not independently verified and are not substituted for the local
logs. Check the workflow conclusion and candidate SHA before using CI evidence.
