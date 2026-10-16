# YK-04 — Button/Text/Cardの共通部品契約と全状態

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M2。依存：YK-02, YK-03。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

最小の表示・操作から、利用者に提供する共通部品APIへ仕上げる。Kumoのvariant表を新APIの完成基準にはしない。

## 2. 実装手順

1. Buttonのenabled/disabled/loading、label、focus-visible、hover、held/cancel、default actionを共通契約へ整理する。YK-00のrepeat決定と旧API維持条件を適用する。
2. Nativeにあるloading/disabled gateを利用し、新共通APIへ投影する。loading中に保持するfocus、aria-busy等の状態、支援技術actionの抑止を明示する。
3. Textは内容・意味と対応style、Cardはcontainerとしての階層とpadding/borderに限定する。未対応font/shapeを無言の近似成功にしない。
4. 同じ意味的操作fixtureをDOMと3 Nativeに適用する。raw event列の違いを意味的操作へ正規化し、許容されたprofile差以外は拒否する。
5. 旧Kumo Button API・既存fixtureは別の互換テストとして保持する。新APIの仕様変更で旧APIのEnter/sizeを暗黙に変えない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. disabled/loadingでactivateしない、blur/remove/resizeでheld stateが残らない。
2. Enter/Space/click/AX actionが二重発火しない。
3. loading切替中のrelease、repaint後のfocus/hover、長押しrepeatを契約どおり判定する。

## 4. 受入条件

- [ ] Button/Text/Cardを両adapterで同じpublic APIから使用できる。
- [ ] 全宣言stateの期待event・表示意味・未対応がfixtureにある。
- [ ] 第三の独立Button controllerを増やしていない。

## 5. 非対象

Kumo全variant完全再現、新しい複雑なwidget追加、pixel完全一致。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-BUTTON: Yami-kumo: 既存Native Button](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/components/button.mbt)
- [G-BUTTON: gpui.mbt: 既存Buttonモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/controls/button/button.mbt)
- [Y-UX: Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
