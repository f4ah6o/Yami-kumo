# YK-05 — 制限付き共通layout・標準theme・AppShell

状態：部分実装候補／closed-token Row・Column gap/padding限定slice／theme・AppShell・一般layout・YK-05全体は未完了。
限定契約と検証境界は [shared-stack-spacing.md](../../docs/shared-stack-spacing.md) を参照。
この更新自体は実ブラウザ・Native windowの新candidate合格を意味しない。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M2。依存：YK-04。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

Row/Columnなどの共通レイアウトをDOM/CSSとGPUIへ対応付ける。通常画面を同じsourceで構成できる最小範囲を固定する。

## 2. 実装手順

1. ui/themeとstyles/shared-ui.cssに同じtokensからlight/darkを提供する。新標準buildはKumo/Tailwind抽出処理不要とし、旧CSS/noticeは維持する。
2. Row/Column、gap、padding、grow/shrink、min/max、alignment、限定overflowを定義する。DOMとGPUIで同じ名前だけを根拠に同じ結果と主張しない。
3. 固定サイズfixtureを用意し、logical coordinatesの結果を計測する。文字計測依存fixtureは切り分け、1 logical pixelの提案予算を採用前に固定する。
4. AppShellのbrand/main必須、navigation/context任意という既存役割を継承する。共通viewport幅から同じresponsive branchを選び、CSSとNativeで別のbreakpointを隠して持たない。
5. theme変更・resize・panelの有無の変更で部品ID/値/focusを保持する。focusするべき要素が消えた際の復帰先を契約化する。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 狭幅/通常幅、min/max、overflow、theme変更のgeometryと画面を検査する。
2. 入力要素の文字やfocus ringがclipされない。
3. ホストページのbodyや他rootのスタイルを変更しない。
4. font差を理由に本当のlayout/semantic不一致を無条件許容しない。

## 4. 受入条件

- [ ] 同じAppShell画面が4経路の対応範囲で組める。
- [ ] scoped CSSとNative themeが同じtoken意図を使用する。
- [ ] 新標準経路とlegacy Kumoのbuild/runtime依存が分かれる。

## 5. 非対象

任意CSS→GPUI変換、CSS Grid全体、multi-theme marketplace、pixel raster統一。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-UX: Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)
- [Y-README: Yami-kumo: 現在の構成と対応範囲](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/README.md)
- [Y-NPM: Yami-kumo: npm previewの利用・配布契約](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/npm/README.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)

## 2026-10-17 bounded palette consumer candidate

Additive per-Button `Light`/`Dark` metadata and a common palette-toggle model
are implemented in this candidate; see `docs/shared-button-palettes.md` for the
exact opaque roles, unchanged geometry/identity contract, host-state differences,
and evidence requirements. None preserves legacy behavior. No global/system
appearance, Card theme, AppShell or general layout expansion is included.
Final-head CI and independent actual-artifact review are required before this
slice is qualified; the broader unchecked acceptance criteria remain open.
