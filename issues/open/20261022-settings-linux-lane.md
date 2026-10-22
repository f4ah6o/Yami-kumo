# Shared Settings Linux レーン — Wayland 入力経路の資格付け

状態：candidate CI pending（単独ブランチのローカルPASSは統合候補のPASSではない）
Model: deepseek-v4.1-flash:1017-cloud
作成日：2026-10-22 JST
作業先：`f4ah6o/Yami-kumo`。段階：M4。依存：YK-08、PR #61。
ブランチ：`feat/settings-linux-lane-20261022`（既存 `feat/settings-linux-lane-20261021` / PR #61 を引き継ぐ）

## 概要

Linux（Weston + Xvfb）実機で Shared Settings レーンのキー入力経路を資格付けし、`settings-flow` を CI の PASS 行にする。text-input-v1 が無い環境で `begin_text_session` が拒否される現状を、key 経路または入力メソッドのどちらで成立させるかを確定する。

## 背景

- `ubuntu.TextHostRoute` を entry に接続し、`settings_runner` に `next_platform_event` を追加済み（PR #61）。`drive_settings.py --platform linux` が xdotool で起動・入力・Tab・Dialog を駆動する。
- CI では `begin_text_session: invalid_input` で abort していたため、transport 拒否を「unavailable」として継続するよう変更した。現在は window と `focus:"name"` まで進むが、`abc` がモデルに入らない。
- text-input-v1 は Weston の構成に依存し、IBus/Mozc のような engine を入れない限り commit が来ない可能性がある。一方、Yami の TextField は `KeyPressed(Character)` も受けるため、key 経路だけで編集できる余地がある。
- 証拠形式は `settings-lane/v1`、集約は `tests/shared-ui/matrix.mjs`。

## 問題

1. xdotool のキーが Wayland の focused surface に届いているか（kiosk shell の focus）が不明。ウィンドウ内クリックを追加したが、モデルは空のまま。
2. `Mounted::handle_event` は `window_focused` が false の Input を拒否する。composition は届くが、key 経路は捨てられている可能性がある。
3. `ubuntu.TextHostRoute` の `begin_text_session` が失敗した場合、`text unavailable` として継続するが、その後のキー経路が実際に動く保証がない。
4. 入力メソッドを CI に入れる場合、Weston の text-input manager と engine の用意が必要で、再現性と実行時間のコストが高い。

## 目標

- Linux 実機で `settings-flow` が PASS し、`settings-linux.json` が `status: pass` で残る。
- text-input-v1 を使う場合と key 経路を使う場合を区別し、IME は `NOT_RUN` と明記する。
- どちらも成立しない場合は、レーンの claim を window/focus/validation に絞り、text を `NOT_RUN` に落として matrix の required 行を更新する（flow PASS を偽装しない）。

## 対象外

- 実日本語 IME の変換、AT-SPI プロバイダ。
- Windows/macOS のレーン（Windows は別 issue）。
- X11 専用経路。

## 提案する方針

1. 実機で再現する（CI では既定 off。`YAMI_SETTINGS_LANE=1` を設定して実行する）。
   - `sh scripts/native_ui_linux.sh` を実行し、`_build/native-ui/linux/settings-linux.log` と `settings-linux.json` を保存する。
   - 直接駆動する場合は workspace wrapper で `moon build` してから `ubuntu --settings-e2e` を起動し、`drive_settings.py --platform linux` を当てる。
2. `xdotool getwindowfocus` と `windowactivate` の結果、`GetForeground` 相当の焦点を log に残す。クリック座標はフィールド上に固定し、`focus:"name"` だけで判断しない。
3. `Mounted::handle_event` の `window_focused` 条件と、gpui `ubuntu` backend が `KeyPressed(Character)` を emit するかを切り分ける。emit しているのに捨てられているなら adapter 側、emit していないなら host 側を直す。
4. text-input-v1 を使う場合は、CI に IBus/Mozc を追加するのではなく、まず「Weston が text-input manager を広告しているか」を `wayland-info` で記録する。engine 無しで commit が来ないなら IME 行は `NOT_RUN`。
5. 文字が資格付けできない場合は claim を絞り、matrix と `docs/shared-settings.md` を同時に更新する。

## 受け入れ条件

- [ ] Linux 実機で `settings-linux.json` が `status: pass`、`name: "abc"`、`dialog: true`、`status: saved` を記録する。
- [ ] key 経路か text-input-v1 かを log で判定でき、IME は `NOT_RUN` と明記される。
- [ ] `node tests/shared-ui/matrix.mjs --dir <evidence> --candidate-sha <sha>` が PASS する（required を絞る場合は理由とともに更新）。
- [ ] CI の `ubuntu-wayland` が green。
- [ ] `docs/shared-settings.md` と STATUS に実測結果を追記。

## テスト計画

- `sh scripts/native_ui_linux.sh`（Weston/Xvfb/xdotool が必要）
- `wayland-info` の text-input 広告と `weston.log` を artifact に残す
- `moon test ui --target native`
- `node --test tests/shared-ui/matrix.test.mjs`
- 実機で `abc` → Tab → Enter → Enter を手動でも確認し、marker とスクリーンショットを残す。

## リスク

- kiosk shell の focus は環境依存。クリック座標と `getwindowfocus` を log に残し、失敗を FAIL として扱う。
- text-input-v1 の engine を CI に入れると実行時間と再現性のコストが増える。まず広告と commit の有無を記録する。
- required 行を絞る変更は M4 の claim を弱めるため、matrix と文書を同時に更新し、PASS の代用にしない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- Linux Settings lane: run the shared model over `ubuntu.TextHostRoute` with `next_platform_event`, and record key-path text separately from text-input-v1/IME.

## 注記

- PR #61 は draft。Windows レーンも同じブランチで作業中。
- 失敗時の artifact: `yami-native-ui-ubuntu`（`settings-linux.log`、`settings-linux.json`、`weston.log`、`native-ui-report.json`）。
- 実機ログには `moon version --all`、Weston/Wayland の版、`wayland-info` の text-input 行を含める。
