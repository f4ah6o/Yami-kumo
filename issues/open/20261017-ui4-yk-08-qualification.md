# YK-08 — Shared Settingsの4プラットフォーム資格付けと証拠matrix

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M4。依存：YK-04, YK-05, YK-06, YK-07, GP-02-L, GP-02-W, GP-02-M, GP-03。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

M0から育てたfixture/harnessを使い、同じsettings画面の意味的結果と実行証拠を完成させる。CIを最後に初めて作るパケットではない。

## 2. 実装手順

1. model/view/updateが一つのsourceであることをconsumerとbuild graphで検証し、別targetへのコピーを検出する。
2. 契約版・fixture版・candidate/依存SHAを固定し、raw traceとnormalized action/result traceを保存する。欠落profileや古いSHAを明示的に失敗させる。
3. Linux/Windows/macOSのvisible windowと、Chromium/Firefox/WebKitの自動browserテストを実行する。実Safari、IME、実支援技術は別のprofile行で証拠化する。
4. 日本語編集→空欄validation→Dialog取消/確認→模擬保存loading→完了の一連フロー、resize/theme、2 root、disposeを実行する。
5. 外部GUI操作は対象windowを束縛して実行する。鍵付きconsoleや別windowしか操作できない条件では観測事実を記録し停止する。
6. model/host/runtime/AX/visual/lifecycle/packageを分離したmatrixを生成する。失敗後に画像baselineだけを更新して緑にしない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 必須profile欠落、意図的な二重activation、composition二重commit、wrong focusを検出する。
2. 画像が同じでもdomain stateが異なる反例をFAILにする。
3. 100回のmount/unmountなど明示的な反復試験で所有listener/timer/購読の残留を確認する。これは一般的なメモリリーク不存在の証明ではない。
4. 各実行はコマンド、exit code、profile、SHA、artifactを記録する。

## 4. 受入条件

- [ ] 4プラットフォームの宣言範囲でMVP必須フローがPASS。
- [ ] 必須実機IME/AXの証拠があり、未実行をPASSに置換していない。
- [ ] 全gpui production supportではなく共通UIのMVP範囲を明示する。

## 5. 非対象

一つのCI runから全OS推定、WebKit自動化をSafariの実機検証と同一視、未対応を画像で隠すこと。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-UX: Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [W-INPUT: W3C Input Events Level 2](https://www.w3.org/TR/input-events-2/)
- [W-APG: WAI-ARIA APG: Modal Dialog](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
