# YK-09 — 独立MoonBit/JS/TS consumerと配布・段階移行

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M5。依存：YK-08。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

新APIを通常のライブラリとして配布できる形へ仕上げる。公開の実行は名前・権限・版を確認した別の明示判断とし、この計画は自動publishを許可しない。

## 2. 実装手順

1. 既存npm previewのbuild/test/packとprovenanceを再利用し、新共通APIのentry、DOM entry、types、scoped CSSを追加する。React入口は既存任意入口を維持し、新coreへ必須化しない。
2. 新経路だけのstandalone consumerをclean environmentでビルドし、Kumo/Zag/Reactをruntime/import/同梱経路へ入れていないことを検査する。ビルド時の既存legacyツールとの違いは依存表へ記録する。
3. 通常JS/TS consumerはMoonBit compilerやsource checkoutなしでtarballから起動する。MoonBit consumerは公開/検証済moduleを使用し、Native moduleだけが必要なGPUI依存を持つ。
4. 旧Web/Native/npm consumerを固定し、旧APIやCSS、optional React AppShellが壊れていないことをテストする。追加APIと破壊的変更を混ぜない。
5. module version整合、deps pin、LICENSE/notice、artifact hash、候補SHAを記録する。npm scope、公開version、tag、Mooncakesの順序とrollback手順をrelease checklistにする。
6. MZed/dshへの最初の導入は、一画面または一部品の別PRとして提案する。consumer専用仕様を共通UIへ持ち込まない。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. JS/TS/MoonBitの独立consumerがpackaged artifactを使用する。
2. React/Kumo/Zagなしの新標準consumerが動く。
3. 旧consumer回帰とnative dependency isolationが成立する。
4. 製品runtimeにturtles/hotpath/vlmkit/テストdriverを含めない。

## 4. 受入条件

- [ ] 配布可能artifact、型、style、導入例、移行文書が揃う。
- [ ] 名前/権限/版未確認のregistry公開を実行していない。
- [ ] 4プラットフォーム対応の範囲と証拠matrixを配布物に紐付ける。

## 5. 非対象

無承認publish、既存private設定削除、repo/package一括改名、MZed/dsh全面書換。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-NPM: Yami-kumo: npm previewの利用・配布契約](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/npm/README.md)
- [Y-SCRIPTS: Yami-kumo: 既存のビルド・テストコマンド](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/package.json)
- [Y-UX: Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)
- [M-TARGET: MoonBit: package / conditional compilation / JS exports](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html)
