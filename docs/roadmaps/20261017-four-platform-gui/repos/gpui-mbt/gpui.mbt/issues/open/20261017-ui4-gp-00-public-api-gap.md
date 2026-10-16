# GP-00 — 共通GUIが必要とする公開APIの差分調査と既存契約整合

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainに参照ドラフト登録（gpui.mbtは未変更）。
作成日：2026-10-17 JST。
作業先：`gpui-mbt/gpui.mbt`。段階：M0。依存：なし。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

Yamiが必要とする汎用host機能を既存GPUI公開APIへ対応付ける。実装済みモデル、実装済みhost、private実験、実行証拠のない機能を混同しない。

## 2. 実装手順

1. controls/button、core、layout、element、text、text_layoutと3 OSの公開APIについて、Yamiの呼出先、対応範囲、不足、証拠profileを列挙する。
2. Yami ButtonInteractionとGPUI Buttonを同一fixtureで比較するための最小再現を作る。Enter repeat、同時キー、disabled/loading、bounds変更、cancel、最小boundsを含める。第三の独立Button state machineを追加しない。
3. docs/text-model.mdの現行UTF-16モデルとdocs/platform.mdのM0 UTF-8設計目標の関係を明記する。境界の明示変換を維持し、全offsetを一括変更しない。
4. GP-01、GP-02-L/W/M、GP-03の各不足を既存issueへ紐付ける。公開APIで充足している項目は作り直さず、検証・公開範囲の整理に縮小する。
5. gpui.mbtがYami/Kumoをruntime importしない依存方向を維持する。OSの入力やAXをYami内で隠れて別実装しない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 同じキー列・bounds列に対する2つのButtonの結果差を記録する。
2. UTF-16/UTF-8の境界・surrogate内・scalar内offsetの既存テストを維持する。
3. private/host未実装がpublic supportedとして表に載らない。

## 4. 受入条件

- [ ] 必須host機能に公開APIか具体的なgap IDがある。
- [ ] 文字範囲の現行契約と将来目標が文書で区別される。
- [ ] Buttonをどちらへ寄せるか、既存consumerへの影響を添えてYK-00へ判断材料を渡せる。

## 5. 非対象

一度に全hostを修正する巨大PR、gpui.rsの変更、GUI実行なしでsupport tierを上げること。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [G-BUTTON: gpui.mbt: 既存Buttonモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/controls/button/button.mbt)
- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [G-PLATFORM: gpui.mbt: M0 platform設計文書](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/platform.md)
- [Y-BUTTON: Yami-kumo: 既存Native Button](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/components/button.mbt)
