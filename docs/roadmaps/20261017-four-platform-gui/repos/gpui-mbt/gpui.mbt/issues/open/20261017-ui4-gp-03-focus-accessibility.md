# GP-03 — Dialog/TextFieldに必要なfocus scopeと外部semantic action

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainに参照ドラフト登録（gpui.mbtは未変更）。
作成日：2026-10-17 JST。
作業先：`gpui-mbt/gpui.mbt`。段階：M3。依存：GP-00, YK-01。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

共通部品が必要とするfocus・modal境界・role/name/state/relation/actionをGPUIの汎用host機能で提供する。既存projectionやsample限定AXを一般実装完了と混同しない。

## 2. 実装手順

1. 既存element focus・semantic projectionを調べ、scope内のTab/Shift+Tab、初期/復帰focus、背景操作抑止、消失した復帰先へのfallbackを公開契約へ整える。
2. Button、TextField、Dialogに必要なrole/name/state/relationと操作を既存値から投影する。描画boundsとowner/世代を保持し、画面とAXが異なる対象を指さない。
3. Linux/Windows/macOSの外部adapterをOS別の小さいPRに分ける。既に利用可能な経路を再利用し、不足のある経路のみ実装する。
4. 外部からのinvoke、focus、必要なvalue/selection操作を同じApp/Entityへ配送する。参照scope・対象世代・windowを再検証する。
5. model/projectionテスト、外部API query/action、実際の支援技術操作を別結果で記録する。gpui全体のAX完成を主張しない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. Dialog表示中のTabがscope外へ出ない、背景が操作できない、閉じた後のfocusが実際に復帰する。
2. 古いlayout/別window/削除済nodeのAX actionを拒否する。
3. 外部のButton操作がcounterを更新し、TextField値が同じmodelへ反映される。
4. 対象OSの支援技術でMVP画面の主要フローを検証する。

## 4. 受入条件

- [ ] 必要3部品のfocus/semantic公開契約と各profileの証拠がある。
- [ ] 未対応adapterはUnsupportedCapabilityを返し、sample projection成功で埋めない。
- [ ] Yami側がOS APIを直接再実装しなくてよい。

## 5. 非対象

全widget AX、全OSメニュー、ブラウザDOMの代行、無制限の画面操作。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [G-PLATFORM: gpui.mbt: M0 platform設計文書](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/platform.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [W-APG: WAI-ARIA APG: Modal Dialog](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
