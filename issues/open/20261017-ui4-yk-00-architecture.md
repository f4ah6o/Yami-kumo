# YK-00 — 4プラットフォーム共通GUIの契約と移行ADR

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M0。依存：なし。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

既存のWeb/Native UX計画を上書きせず、4プラットフォーム共通APIへ発展させるADRを追加する。Kumo互換・第三者JS GUI実行時依存を新標準経路の必須条件から外す。旧API・生成CSS・npm previewは維持する。

## 2. 実装手順

1. 既存issues/open/20261015-ecosystem-web-native-ux-integration.mdと20261005-kumo-gpui-shared-ux.mdから、本計画へ継承する項目・旧互換専用になる項目を表にする。完了済み課題を未完了へ戻さない。
2. Platform、BackendKind、CompilerTarget、runtime dependencyとbuild/test dependencyを区別する。Web DOMと既存Canvasの位置付け、標準テーマとlegacy Kumo themeを定義する。
3. ButtonのEnter repeat、loading時のfocus、TextField外部値更新とcompositionの競合、Dialog Escapeとcompositionの優先順を契約論点として明記する。GP-00の比較後、YK-04/06/07着手前に決定表を固定する。推測だけで旧動作を変更しない。
4. fixture ID、期待domain結果、profile差分allowlist、candidate/依存SHAを含むresult schemaの最小版を追加する。fixtureを後から生成結果に合わせる方式にしない。
5. 新APIは追加導入とし、名前変更、private削除、npm/Mooncakes公開、demo/main切替はこのPRでしない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 契約に4プラットフォームとDOM/Canvasの区別がある。
2. 新経路と旧互換経路の依存方針が区別される。
3. 証拠欠落・unsupportedをPASSに変換するschemaを拒否する。

## 4. 受入条件

- [ ] ADRに既存計画との差分と初期スコープが明記される。
- [ ] YK-01とGP-00が参照できる共通語彙、fixture/result schemaがある。
- [ ] この文書PRのCI成功を新GUI実装の成功として報告しない。

## 5. 非対象

コード全移動、改名、全Kumo移植、全Zag移植、OS backend実装。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-UX: Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)
- [Y-README: Yami-kumo: 現在の構成と対応範囲](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/README.md)
- [G-BROWSER: gpui.mbt: 既存Canvas型ブラウザ計画](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/issues/open/0009-browser-backend.md)
- [Y-NPM: Yami-kumo: npm previewの利用・配布契約](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/npm/README.md)
