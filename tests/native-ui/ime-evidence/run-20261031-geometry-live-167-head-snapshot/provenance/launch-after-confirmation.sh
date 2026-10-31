#!/bin/bash
# Parent must explicitly confirm BOTH exact #166/#167 reviews and CI 7/7.
set -eu
test "${YAMI_166_167_REVIEW_CI_CONFIRMED:-}" = aa7c81288b81617a5e8a346347fe355e38d5b834 || {
  echo 'Live launch is gated on parent confirmation of exact #166 and #167 reviews and both CI 7/7.' >&2
  exit 2
}
source /workspace/review167-live-prep-agent/env.sh
python3 /workspace/review167-live-prep-agent/verify-preparation.py
for pair in \
  '/workspace/review167-live-prep-agent/app e9fe5fe06111dce33be20f3f93d8be819194486f' \
  '/workspace/review167-live-prep-agent/framework 35b9041dfb3642b43ca37c604834942614eb50fb' \
  '/workspace/review167-live-prep-agent/harness aa7c81288b81617a5e8a346347fe355e38d5b834'; do
  read -r source_tree source_revision <<< "$pair"
  test "$(git -C "$source_tree" rev-parse HEAD)" = "$source_revision"
  test -z "$(git -C "$source_tree" status --porcelain)"
done
export YAMI_RELEASE_OUT=/workspace/review167-live-prep-agent/live
mkdir "$YAMI_RELEASE_OUT"
# Diagnostic only: #166 diagnostic app does not include the #154 P1 fix.
# A native FIFO-head snapshot does not authorize ACK, dispatch or recovery.
# Exact session creates a fresh build before it starts live services or app.
# No pre-existing binary is accepted by this launch path.
exec dbus-run-session -- xvfb-run --auto-servernum --server-args='-screen 0 960x640x24 -nolisten tcp -ac +extension GLX +render' \
  /workspace/review167-live-prep-agent/harness/tests/native-ui/ime-harness/retained-release/session.sh
