# Shared Settings Windows レーン — 実機での入力経路資格付け

状態：open／レーン実装済み・入力経路未達
Model: deepseek-v4.1-flash:1017-cloud
作成日：2026-10-22 JST
作業先：`f4ah6o/Yami-kumo`。段階：M4。依存：YK-08、PR #61。
ブランチ：`feat/settings-windows-lane-20261022`（既存 `feat/settings-linux-lane-20261021` / PR #61 を引き継ぐ）

## 概要

Windows 実機で Shared Settings レーンの文字入力経路を資格付けし、`settings-flow` を CI の PASS 行にする。ASCII 入力が IMM32 経路でモデルに届かない現状を、実機のログと最小修正で解消する。

## 背景

- M4 の同一 consumer は `examples/shared_settings`（model/view/update）で、DOM と macOS は接続済み。Windows は `windows.TextHostRoute` を entry に接続し、`--settings-e2e` と `tests/native-ui/drive_settings.py` まで実装済み（PR #61）。
- レーンは起動し、`YAMI_NATIVE_UI_SETTINGS` の frame で `focus:"name"` まで確認できる。しかし `abc` を送っても `name` が空のままで、dialog も開かない。
- 現行 driver は foreground HWND を確認し、`KEYEVENTF_UNICODE` で文字を送り、ダメなら Enter で確定を試す。CI では「sample exited early」または「timed out waiting for Settings output」で終わる。
- 証拠形式は `settings-lane/v1`、集約は `tests/shared-ui/matrix.mjs`。

## 問題

1. `WM_CHAR` が Yami の `Mounted::handle_event`（`KeyPressed(Character)`）に届くのか、`windows.TextHostRoute` の composition として park されるのかが未確定。
2. `windows.TextHostRoute` の `begin_text_session` が実機で成功しているか、失敗を握りつぶしてキー経路に落ちているかがログから判別できない。
3. SendInput のフォーカスが一瞬でも外れると、文字が console 側へ流れる。CI では再現しにくい。
4. レーンの寿命（tick limit）と driver の待機が競合し、途中で sample が終了する場合がある。

## 目標

- Windows 実機で `settings-flow` が PASS し、`settings-windows.json` が `status: pass` で残る。
- 文字が IMM32 由来か key 由来かをログで区別でき、IME / UIA は `NOT_RUN` と明記される。
- 実機で再現できない場合は、レーンの claim を dialog/focus に絞り、text を `NOT_RUN` に落として matrix の required 行を更新する（flow PASS を偽装しない）。

## 対象外

- 日本語 IME の実変換、UIA プロバイダ、AX 編集。
- macOS/Linux の入力経路（別 issue）。
- Web レーン。

## 提案する方針

1. 実機で再現する。
   - `pwsh scripts/native_ui_windows.ps1` を実行し、`_build/native-ui/windows/settings-windows.log` と `settings-windows.json` を保存する。
   - 直接駆動する場合は workspace wrapper で `moon build` してから `windows.exe --settings-e2e` を起動し、`drive_settings.py --platform windows` を当てる。
2. `platform/windows` の `WM_CHAR` / `WM_IME_*` と `windows/text_host.mbt` の写像を確認する。`Inserted` が出るなら `TextInputEvent::Commit` まで届いているかを marker で確認する。
3. Yami 側は `Mounted::text_input` の Commit（preedit なし置換）と `KeyPressed(Character)` の両経路を切り分ける。片方だけ通るなら、通らない経路を adapter で補うのではなく、host の写像を直す。
4. 文字がどうしても資格付けできない場合は、`--settings-e2e` の claim を「window/focus/validation/dialog dismissal」に限定し、`settings-flow` を required から外して `settings-text` を `NOT_RUN` にする。matrix と `docs/shared-settings.md` を同時に更新する。
5. CI の `native_ui_windows.ps1` は失敗時に JSON とログを artifact に残す（既存の upload を利用）。

## 受け入れ条件

- [ ] Windows 実機で `settings-windows.json` が `status: pass`、`name: "abc"`、`dialog: true`、`status: saved` を記録する。
- [ ] `settings-windows.log` に text transport の開始または unavailable の marker が残る。
- [ ] `node tests/shared-ui/matrix.mjs --dir <evidence> --candidate-sha <sha>` が PASS する（required を絞る場合は理由とともに更新）。
- [ ] IME / UIA が `NOT_RUN` と明記され、PASS に置換されていない。
- [ ] CI の `windows-d3d11` が green。
- [ ] `docs/shared-settings.md` と STATUS に実測結果を追記。

## テスト計画

- `pwsh scripts/native_ui_windows.ps1`（GPUI pinned revision と MSVC 環境が必要）
- `moon test ui --target native`（`native/`、86 tests の回帰）
- `node --test tests/shared-ui/matrix.test.mjs`
- `node tests/shared-ui/matrix.mjs --dir <artifact-dir> --candidate-sha <sha>`
- 実機で `abc` → Tab → Enter → Enter を手動でも確認し、marker とスクリーンショットを残す。

## リスク

- SendInput のフォーカスは CI で不安定。foreground 確認を維持し、外れたら FAIL として記録する（skip しない）。
- IMM32 の composition を Enter で確定すると、同じ Enter が submit も兼ねる場合がある。marker で二重 action を検出する。
- required 行を絞る変更は M4 の claim を弱めるため、matrix と文書を同時に更新し、PASS の代用にしない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- Windows Settings lane: run the shared model through `windows.TextHostRoute`, with `--settings-e2e` and a CI lane report. Text delivery and IME scope are recorded separately.

## 注記

- PR #61 は draft。Ubuntu レーンも同じブランチで作業中。
- 失敗時の artifact: `yami-native-ui-windows`（`settings-windows.log`、`settings-windows.json`、`settings-target/`）。
- 実機ログには `moon version --all`、Windows build、IME 名を含める。
