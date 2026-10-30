# YK-06 — 共通TextFieldとDOM編集・GPUI接続

AD
状態：DOM slice実装済み（#38）／native単一行adapter実装済み（#40）／OS IME・AXはNOT_RUN。 契約は [shared-textfield.md](../../docs/shared-textfield.md)。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M3。依存：YK-02, YK-03, GP-01。

本ファイルは計画と現在状態を併記する。DOMとnativeの単一行sliceは実装済みだが、OS IMEとaccessibilityの資格付けは未完了であり、製品対応を主張しない。

## 1. 目的・範囲

値・選択・検証・compositionの意味を共通にし、実編集はDOMまたはGPUI hostへ委譲する。3 OSのruntime検証は各GP-02の完了に依存するが、DOM/model開発は先行可能。

## 2. 実装手順

1. 単一行TextFieldから始める。label、description、error、required、read-only/disabled、value/revisionを共通APIに定義する。多行やパスワード保存は初期必須にしない。
2. DOMはinputを使い、編集中の.value書戻しでselection/compositionを破壊しない。未確認の古い外部revisionを上書き採用しない。
3. compositionstart/update/endとinput/beforeinputの実測列をGP-01へ変換する。non-cancelable eventやcommit後inputでも二重挿入しない。編集hostのundoを二重実行しない。
4. 貼付、cut、選択、delete、undo/redo、form resetを含む。旧DOM Fieldのreset後pristine/filled/invalid再同期を回帰として残す。
5. NativeはGP-01と3 OSの公開bridgeを使う。未対応profileではcapability不足を明示し、Textで偽装してTextField対応と呼ばない。現状は`native/ui`がGPUI `controls/text_field`を保持し、click/focus、caret、編集、submit/blur、host `Composition` eventを処理する。copy/pasteとOS IME/AXは未対応。
6. IME中の保存やDialog Escapeについて、未確定値の扱いとキーの優先順をYK-00の契約どおり実装する。

## 3. テスト対象と反例

DOM sliceはPR #38、native sliceはPR #40で実装した。以下は未完了項目を含む。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 日本語、絵文字、結合文字、surrogate境界、RTLを含むoffset入力の拒否/維持を検査する。RTL完全編集対応をfixture存在だけで主張しない。
2. composition後のnon-cancelable beforeinput/inputで重複しない。
3. 値の外部更新、re-render、blur、remove、reset中の状態を確認する。
4. label/name/error relation、値変更の外部操作を検査する。

## 4. 受入条件

- [ ] 共通のsettings viewにTextFieldを追加できる。
- [ ] Web実編集が動き、NativeはGP-02ごとの実測状態が明示される。
- [ ] 全4 profileのTextField完了は3 OS bridgeの資格付け後に判定する。

## 4a. 実装済みの証拠

- DOM: 実Chromiumでcommit、composition deferral、rapid edit、submit、focusを確認（#38）。
- Native: GPUI `0.10.0`（release tree `fffe79168e7ad79dffe2002e83a570551b1ae8f1`）に対し、native/ui 49/49、native ui + shared counter 66/66、Yami root 58/58。
- Native composition: previewは`TextChanged`を出さず、commitは1回だけ出し、cancelはactionを出さないheadless test。
- macOS Kotoeri、candidate window、copy/paste、AX: **NOT RUN**。synthetic compositionは実IMEの合格ではない。
- `text_session.TextSession`のowner/revision統合は未接続。native adapterは現在`TextField`を直接保持し、共通runtime tokenでactionをgateする。

### 2026-10-30: focus loss 時の observed commit 消失

PR [#83](https://github.com/f4ah6o/Yami-kumo/pull/83) の field binding
guard は旧 session の記録を別 field に適用しないが、focus loss 時に cancel が
未取得の同 epoch `Commit` を破棄するケースを解決しない。[最小再現と FAIL
ログ](../../docs/evidence/20261030-shared-settings-text-owner/README.md) を参照。
これは GUI native 受入の blocker であり、portable suite の PASS は代替にならない。

次に [GP-01B text-host issue](https://github.com/gpui-mbt/gpui.mbt/blob/main/issues/open/20261019-gp-01b-text-host-contract.md)
と [text-host contract](https://github.com/gpui-mbt/gpui.mbt/blob/main/docs/text-host-contract.md)
と [M3 coordination](https://github.com/gpui-mbt/gpui.mbt/blob/main/issues/open/20261019-m3-textfield-dialog-coordination.md)
へ結び付け、focus / close / replacement の境界で pending observation の取得終了と
`TextSession` の `request_end` / `complete_blur` または `complete_replacement` を
どう同期するか確定する。既観測 commit は旧 owner に保存し、revocation 後の
epoch / target は拒否する。空の一回の poll だけを排他 barrier と扱わず、host が
提供する順序・quiescence の保証を調査して必要な契約変更から着手する。

## 5. 非対象

inputのふりをしたCanvas編集、全キーからの文字列自作、Rich text、古い文字モデルの複製。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-WEB: Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [W-INPUT: W3C Input Events Level 2](https://www.w3.org/TR/input-events-2/)
