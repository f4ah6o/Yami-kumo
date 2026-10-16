# GP-01 — TextField向けの公開編集session・IME host契約

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainに参照ドラフト登録（gpui.mbtは未変更）。
作成日：2026-10-17 JST。
作業先：`gpui-mbt/gpui.mbt`。段階：M3。依存：GP-00, YK-01。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

既存text値モデルとhostの実入力を結ぶ共通の公開契約を整える。UTF-16値モデルや既存編集処理をYami側に複製させない。

## 2. 実装手順

1. TextDocument/TextCompositionと既存field APIを棚卸しし、公開adapterで必要な値、directional selection、composition session、caret geometryを定義する。
2. window/root/fieldの世代、document revision、session ID、preview/commit/cancelを明確にする。古いsessionや別fieldからのcommitを拒否する。
3. 値とhost表示の同期、外部値更新との衝突、focus移動でのcommit/cancel結果の取り込みを定義する。OSがcommitした結果を無条件cancelへ書き換えない。
4. UTF-16/UTF-8/native range変換は既存厳密変換を使う。grapheme移動・caret geometry・undoが未充足なら能力を別項目にする。
5. 3 OSが実装する公開テストseamを用意する。private opt-in routeを有効にしただけでpublic supportへ昇格しない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. preview更新が元範囲に置換され、commitは一回、cancelは契約の元状態に戻る。
2. 古いrevision/session、surrogate分断、異なるowner、destroy後commitを拒否する。
3. host要求と観測された編集結果の順序を検査する。

## 4. 受入条件

- [ ] 3 OSに共通するpublic contractとheadless fixtureがある。
- [ ] モデル成功と実IME輸送成功を別結果として出せる。
- [ ] GP-02-L/W/Mがprivate内部APIなしで実装できる。

## 5. 非対象

OS固有の全文編集エンジン再実装、Rich text、複数cursor、UTF-16からの無断変更。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [G-PLATFORM: gpui.mbt: M0 platform設計文書](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/platform.md)
