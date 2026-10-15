# Yami-kumo：Web / Nativeのcross-platform UX integration

Status: open — 設計課題。構想名Yami-kumo.mbtの作業先はこのrepo。改名・移転は対象外。
Priority: P1
Decision date: 2026-10-15
Parent: [ecosystem方針・共通マージ基準](https://github.com/gpui-mbt/gpui.mbt/pull/82)

## 1. 役割

WebとNativeで「同じ操作が同じ意味を持つ」「同じ状態が分かる」「アプリのUIを組み立て直し過ぎない」を実現するUX層。単なるKumoの見た目移植ではなく、componentの状態・イベント・semantic role・focus・responsiveな配置の契約を共有する。

描画方式やOS標準操作まで一律にするのではない。WebはDOM/CSS、Nativeはgpui.mbtを使い、OSのショートカットや文字描画の差は明示したadapter差として扱う。

## 2. 現状

[README](../../README.md)では`main`がstarter、`demo`がshowcaseで、純MoonBitの`f4ah6o/yami_kumo`と独立した`f4ah6o/yami_kumo_native`がある。WebのKumo parity galleryと、NativeのText/Button/Card/AppShellの限定sliceを既に持つ。Native Input／IMEは実装済みとされていない。[native README](../../native/README.md)と[UX guide](../../docs/UX.md)の境界を引き継ぐ。

本課題は既存生成・parity・native作業を統合する上位課題であり、それらを作り直さない。

## 3. 境界

1. gpui.mbtはlayout・input routing・focus・text/IME・描画hostの基盤を所有する。Yami-kumoがOS backendやengineの代替実装を抱え込まない。
2. Cloudflare Kumoの固定版からの抽出・生成と、Yami独自のAppShell契約を区別する。upstream由来のAPIと独自拡張を同一視しない。
3. Web moduleをNativeの依存で重くしない。Native adapterを使うconsumerだけがgpui.mbtを必要とする。新たなpublic package／npm配布を伴う場合は独立の配布課題とし、この文書PRでは公開しない。
4. vlmkitは実画面・操作の検証に用い、UXの期待値はこのrepoのfixtureで定義する。gpui.rs互換性そのものはgpui-conformanceが判定する。
5. MZedは部分置換PoC、dshは任意のhobby consumer。どちらかの専用画面・provider設定を共通componentの必須機能にしない。
6. turtles/hotpath/vlmkitは開発用。consumer runtimeにテスト・計測toolを必須化しない。

## 4. 実装単位

1. **version付きsemantic contract**：component ID、props、状態遷移、操作、発火event、disabled/loading時の規則、focus、role/name/stateを定義する。Web/Native共通部分とplatform差分を分ける。Kumo version・生成元・契約versionを追跡する。
2. **最小縦切り**：既存Buttonを最初の対象にし、enabled/disabled/loading/focusとactivationを共有fixtureにする。Text/Cardは表示・semanticの範囲を明示し、AppShellは任意領域の有無と開閉・focus復帰を定義する。
3. **adapterとparity**：同じfixture IDと初期状態からWeb/Nativeを実行し、操作後のdomain state・event列・semantic情報を比較する。画像はそのprofileのvisual regressionとして別に扱う。
4. **未対応機能の表現とconsumer**：Native Input／IME／AXなど不足能力を表示し、no-opで成功扱いしない。Web用とNative用の最小consumerを持ち、アプリsourceのコピーやprivate APIなしでpublic APIを使えることを確認する。

## 5. 最初の受入matrix

| 対象 | 共通に保証すること | 許容する差／未検証 |
| --- | --- | --- |
| Button | enabled時の1操作1event、disabled/loading時の規定、focus可視性 | OS別キー表現やraster差は明示 |
| Text / Card | 内容・階層・配置上の意味・overflow方針 | font rasterのpixel完全一致は要求しない |
| AppShell | brand/main必須、任意領域の省略、navigationとcontextの区別 | mobile drawerとdesktop panelの配置差 |
| Panel開閉 | 開閉状態・操作の意味・適切なfocus復帰 | profile固有のfocus実装は別途証拠化 |
| Input / IME | 対応したprofileだけで入力・composition契約を検証 | Native未対応をWeb成功で埋めない |
| Accessibility | 検査可能なrole/name/stateと操作の対応 | DOMがあるだけ／画像が似るだけではNative AX合格にしない |

対応範囲はcomponent×state×操作×platform×観測層で表示する。初回はWebと利用可能なNative profileのButton縦切りを必須とし、macOS Apple Silicon／Linux／Windowsの未実行profileは明記する。対応OS全部の成功を一つの実行から推定しない。

## 6. 検証方法・反例

1. 既存Web手順`vp check`、`vp exec tsc --noEmit`、`vp test`、`vp build`とparity手順を変更範囲に合わせて実行する。MoonBit browser moduleの生成順序はREADMEの既存pipelineを守る。
2. Nativeはnative READMEのOS別手順を使い、同じfixture・候補SHA・toolchainと操作logを保存する。vlmkitを使う場合は対象windowを束縛し、安全に観測できない条件では停止する。
3. disabled Buttonがeventを発火する、panel close後にfocusを失う、契約versionがずれる、必要profileを実行していないケースを検査が検出する。
4. visual差の許容値は対象profileで事前に定義する。失敗後のbaseline更新だけで通さず、semantic不一致を画像の近さで免除しない。

上記は今後の実装検証。今回の文書追加ではWeb/Nativeテストは未実行。実行時は対象・コマンド・PASS/FAIL/未実行と理由を記録する。

## 7. マージ基準・完了条件

共通`ecosystem-merge-v1`に従う。**最新HEADの必要CIがすべてcompleted/success AND 同じHEADに対する実際の`gpt-6.1-sol/xhigh`のApprove相当**。モデル・effort・SHA・判定・指摘処置・証拠をGitHubに記録する。P0/P1、必要checkのskip、未実行、古い承認を合格にせず、HEAD更新後は再検証・再レビューする。既存保護を維持する。

1. [ ] 共通semantic contractとplatform差分・未対応が識別できる。
2. [ ] Buttonの同じ操作fixtureをWeb／実Native profileで検証する。
3. [ ] AppShellの任意領域と開閉の意味をconsumerが共有できる。
4. [ ] Web/Nativeのpublic consumerを検証し、private APIや開発toolへの実行時依存を増やさない。
