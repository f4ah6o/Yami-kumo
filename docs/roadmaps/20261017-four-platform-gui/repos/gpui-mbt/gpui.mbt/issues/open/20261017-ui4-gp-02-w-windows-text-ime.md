# GP-02-W — WindowsのTextField・日本語IME host接続

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainに参照ドラフト登録（gpui.mbtは未変更）。
作成日：2026-10-17 JST。
作業先：`gpui-mbt/gpui.mbt`。段階：M3。依存：GP-01。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

Windowsの実host入力をGP-01の公開契約へ接続し、YamiのTextFieldから利用可能にする。

## 2. 実装手順

1. 既存Win32 fieldとprivate IMM32実験の充足範囲を調べ、必要な公開session経路へ接続する。IME方式を推測で入れ替えず、候補位置、DPI、HWNDの所有者と世代を検証する。UIAはGP-03と整合する。
2. 入力配送の対象window/field/世代とfocusを検査し、未対応・permission拒否・session競合をtyped結果にする。
3. 文字計測、selection、caret、IME preview表示、commit/cancel、undo単位を整合する。文字列だけをappendしてIME実装と呼ばない。
4. 既存OSのCI/実行scriptにテスト入口を追加する。実行前提が不足したら観測事実と未実行の範囲を記録する。
5. 候補SHA/依存版/OS/IME/font/toolchainとログを保存し、同じYami候補からpublic APIでconsumerを実行する。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. Windows x64の実日本語IMEと所有HWNDで、composition中resize/DPI変更、focus移動、確定/取消、選択置換、候補位置を検証する。
2. 旧windowのイベント、unmount後commit、重複commit、invalid rangeを拒否する。
3. synthetic/model testsと実IME/物理入力の証拠を分ける。

## 4. 受入条件

- [ ] 実際の入力結果が共通modelへ一度だけ反映される。
- [ ] Yamiからprivate opt-in経路を直接呼ばず利用できる。
- [ ] 未実行/unsupported項目が表に残り、能力があるだけで証拠ありにならない。

## 5. 非対象

他OSの成功推定、OS全体のproduction宣言、実行不能なconsoleで操作を強行すること。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [G-PLATFORM: gpui.mbt: M0 platform設計文書](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/platform.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
