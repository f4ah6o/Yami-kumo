# 調査根拠

確認日：2026-10-17 JST。GitHubの観測は以下のmain SHAを基準とする。仕様サイトは確認時点の公開文書であり、実装時には検証に使用する版・ブラウザ版を別途記録する。

- Yami-kumo: `7a2c088934e2104e48b9f58b23724c2160520202`
- gpui.mbt: `a99e111a37c0ac98bd847e9ea493c78589207875`

## Y-README

[Yami-kumo: 現在の構成と対応範囲](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/README.md)

## Y-UX

[Yami-kumo: 既存のecosystem共通UX計画](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/issues/open/20261015-ecosystem-web-native-ux-integration.md)

## Y-WEB

[Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)

## Y-BUTTON

[Yami-kumo: 既存Native Button](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/components/button.mbt)

## Y-NATIVE

[Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)

## Y-NPM

[Yami-kumo: npm previewの利用・配布契約](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/npm/README.md)

## Y-SCRIPTS

[Yami-kumo: 既存のビルド・テストコマンド](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/package.json)

## G-README

[gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)

## G-BUTTON

[gpui.mbt: 既存Buttonモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/controls/button/button.mbt)

## G-TEXT

[gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)

## G-PLATFORM

[gpui.mbt: M0 platform設計文書](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/platform.md)

## G-BROWSER

[gpui.mbt: 既存Canvas型ブラウザ計画](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/issues/open/0009-browser-backend.md)

## W-INPUT

[W3C Input Events Level 2](https://www.w3.org/TR/input-events-2/)

## W-DIALOG

[WHATWG HTML: dialog](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-dialog-element)

## W-APG

[WAI-ARIA APG: Modal Dialog](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)

## M-TARGET

[MoonBit: package / conditional compilation / JS exports](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html)

文書やREADMEにある過去のPASSは今回の実行結果ではない。未マージPR、全CI、全OSの実機状態は今回網羅調査していない。実装開始時に最新mainと関連PRを再確認する。
