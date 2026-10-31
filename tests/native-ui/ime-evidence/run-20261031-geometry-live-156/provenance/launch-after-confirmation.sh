#!/bin/bash
# Parent must explicitly confirm exact #156 review and ALL required CI.
set -eu
test "${YAMI_156_REVIEW_CI_CONFIRMED:-}" = acd14b8788e7ece8ce5100348bfd6703186d2e75 || {
  echo 'Live launch is gated on parent confirmation of exact #156 review and completed CI.' >&2
  exit 2
}
source /workspace/review156-live-prep-agent/env.sh
python3 /workspace/review156-live-prep-agent/verify-preparation.py
for pair in \
  '/workspace/review156-live-prep-agent/app 1a59626cf67910917c4d660dd6db8bedae55a722' \
  '/workspace/review156-live-prep-agent/framework 35b9041dfb3642b43ca37c604834942614eb50fb' \
  '/workspace/review156-live-prep-agent/harness acd14b8788e7ece8ce5100348bfd6703186d2e75'; do
  read -r source_tree source_revision <<< "$pair"
  test "$(git -C "$source_tree" rev-parse HEAD)" = "$source_revision"
  test -z "$(git -C "$source_tree" status --porcelain)"
done
export YAMI_RELEASE_OUT=/workspace/review156-live-prep-agent/live
mkdir "$YAMI_RELEASE_OUT"
# Diagnostic only: #142 app does not include the #154 P1 fix.
# Exact session creates a fresh build before it starts live services or app.
# No pre-existing binary is accepted by this launch path.
exec dbus-run-session -- xvfb-run --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
  /workspace/review156-live-prep-agent/harness/tests/native-ui/ime-harness/retained-release/session.sh
