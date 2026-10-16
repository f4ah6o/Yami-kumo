# 4プラットフォーム共通GUI — ロードマップ・実装計画 v1

状態：計画案 completed／Yami-kumo mainへ計画文書登録／製品コード未変更／実装・GUIテスト未実行。
作成日：2026-10-17 JST。これは承認済みADRや実装完了報告ではない。

## 1. 目標と固定する方針

Linux、Windows、macOS、Webを対等な4つの実行プラットフォームとして扱う。アプリ開発者は同じMoonBitの画面定義・状態・意味的な操作APIを使用する。WebはDOM/CSS、3つのデスクトップOSはgpui.mbtで実現する。4つが対等であることは、内部実装・完成時期・証拠が同一であることを意味しない。

1. Kumo互換を新共通APIの必須条件にしない。Zag、React等の第三者JS GUI/runtime frameworkを標準実行経路に要求しない。
2. gpui.mbtの既存Canvas型ブラウザ経路は維持する。DOMバックエンドは部品の意味が残る上位層で分岐し、SceneSnapshotからbuttonやinputを逆推定しない。
3. 既存Yami-kumoを作業先とする。名称・org・公開パッケージ名を今回一括変更しない。
4. 既存Web/Native API、npm preview、Kumo由来CSSの利用者を壊さない。新APIは追加的に導入し、互換コードと新標準経路を分離する。
5. 薄い自前DOM FFIは許容する。MoonBit標準ライブラリ、gpui.mbt、OS・ブラウザ、ビルド・テスト用ツールまで依存ゼロと呼ばない。
6. JSとNativeを最初の実行ターゲットにする。Wasm/WasmGCは別の後続ゲートとし、コンパイル成功をブラウザ実行成功にしない。

根拠：既存の責務分割は [Y-UX](SOURCES.md#y-ux)、Canvas路線は [G-BROWSER](SOURCES.md#g-browser)、MoonBitのターゲット境界は [M-TARGET](SOURCES.md#m-target)。本計画のDOM経路は追加設計である。

## 2. 現状の再利用先と、最初に解く差分

基準SHAは [SOURCES.md](SOURCES.md) に固定した。次表はソース・文書の読取結果であり、この計画の動作テスト結果ではない。

| 既存資産 | 再利用方針 | 注意点 |
|---|---|---|
| Yami `components.mbt` / `html.mbt` | 安全な文字・属性の扱いと旧HTML APIを維持 | 戻り値`Html`を新しい全プラットフォーム共通APIにはしない |
| Yami `native/components/button.mbt` | 既存操作・cancel回帰ケースを保存 | `ButtonInteraction`とGPUI Buttonを並行して二重駆動しない |
| GPUI `controls/button/button.mbt` | Nativeの再利用候補として比較する | loading、最小bounds、キーrepeatの契約差があるため無条件置換しない |
| GPUI `text/` / `docs/text-model.md` | UTF-16範囲と厳密なUTF-8変換、composition値モデルを利用 | これはhost IMEではない。新しい文字編集エンジンをYami側で再実装しない |
| Yami `dom/` / npm preview | 既存Field状態、form reset、明示的DOM導入、配布検査を維持 | 新DOM runtimeはroot単位のmount/update/unmountを別契約で追加 |
| Yami AppShell / fixtures / Native scripts | 画面の役割、比較入力、3 OSの実行導線を再利用 | 過去SHAのGUI成功を新コードの成功として流用しない |

調査で判明した調整事項：

1. YamiのNative ButtonはEnterのrepeatでもactivateする一方、GPUIの現モデルは最初の非repeat key-downでactivateする。共通契約のrepeat方針をYK-00/GP-00で測定・固定し、既存APIの意味は暗黙に変更しない。[Y-BUTTON / G-BUTTON]
2. GPUIの現在の文字値モデルはUTF-16。M0の`docs/platform.md`には設計目標としてUTF-8範囲の記述が残る。現行モデル・将来目標を区別する文書修正をGP-00へ含める。実装を文書に合わせて勝手に切り替えない。[G-TEXT / G-PLATFORM]
3. 3 OSのhostとブラウザの存在は、一般部品の入力・IME・支援技術が完成した証拠ではない。コンポーネント単位・profile単位で必要能力を測る。[Y-NATIVE / G-README]

## 3. リポジトリの責務

| 作業先 | 所有するもの | 所有しないもの |
|---|---|---|
| `f4ah6o/Yami-kumo` | 共通部品API、View構造、テーマ、DOM adapter、GPUI adapter、共通fixture、consumer | OSのIME/providerやGPU backendの別実装 |
| `gpui-mbt/gpui.mbt` | 既存core/layout/input/textの再利用、汎用focus/IME/AX等の不足を埋める公開API | Kumo互換やYami固有の画面・theme |
| `gpui-mbt/gpui-conformance` | gpui.rsとの既存互換性ゲートを維持 | Yamiの部品仕様の正解を代わりに決めること |
| `f4ah6o/vlmkit` | 必要時の実画面・対象window限定の操作検証 | consumer runtimeの必須依存 |
| `MZed` / `dsh.mbt` | MVP後の任意consumer | MVP完成の前提条件、独自のprovider仕様を共通部品へ入れること |

新しい汎用機能が既存GPUIの公開APIで足りると分かった場合、該当GPUI変更は縮小・完了扱いにする。Yamiのprivate API呼び出しで不足を隠さない。gpui-conformance/vlmkitには本計画だけを理由に新しい並行実装を増やさない。

## 4. 実装アーキテクチャ

### 4.1 共通化する境界

```text
一つのmodel + 一つのview + 一つのupdate
                    |
     共通部品API / 意味を持つView / 安定したID
                    |
             hostへの要求と結果
       +------------+------------+------------+
       |            |            |            |
     Linux       Windows       macOS         Web
   GPUI adapter GPUI adapter GPUI adapter   DOM adapter
       |            |            |            |
   gpui.mbt      gpui.mbt      gpui.mbt     DOM / CSS
```

画面定義の中ではプラットフォームを判定しない。起動・ビルドのcomposition rootだけがadapterを選ぶ。アプリ固有stateは一つだけを所有し、Nativeの`App/Entity`と別コピーを二重更新しない。共通UI runtimeは部品instance・購読・要求の寿命だけを管理し、別の汎用アプリフレームワークを作らない。

共通public型は`HTMLElement`、JS object、ReactNode、GPUI Window/Scene型を含まない。実装内部で既存のportable GPUI型・関数を再利用する場合、ターゲットと依存graphを検査する。型の隔離と、既存純粋ロジックの複製は同義ではない。

### 4.2 提案する配置（まだ存在しないパスを含む）

```text
Yami-kumo/
  ui/core/                 部品ID、契約、イベント、typed capability結果
  ui/components/           共通props・意味を持つView
  ui/runtime/              keyed更新・要求/購読の寿命
  ui/theme/                新標準tokens。Kumo生成処理を必須にしない
  ui/dom/                  JS限定DOM adapter
  native/ui/               既存Native module内のGPUI adapter
  examples/shared_settings/ 一つのmodel/view/update
  fixtures/shared-ui/      期待値・操作・profile差分
  tests/shared-ui/         model/host/runtime比較と証拠出力
  styles/shared-ui.css     新標準のscoped CSS
```

フォルダー名・型名は実装案。module/package境界はYK-01のJS/Native独立consumerで確定する。全てを一つのmoduleへ押し込み、Web installでOS backendのビルドを要求する構成は不可。既存root module、独立Native module、npm previewの分離を活かす。

### 4.3 lifecycleとイベント

1. `NodeKey`は画面内で安定し、mount instanceの世代と組で識別する。重複キーは拒否し、配列indexを部品identityにしない。
2. `mount → update → unmount`で、同じキー・部品型ならDOM/Native instanceを保持する。選択・focus・compositionを再描画で破壊しない。型が変わる場合は古いinstanceを正しく終了してから作る。
3. hostイベントは所有root/windowと世代を検査して取り込む。unmount後・別window・古いasync完了で新しい部品を更新しない。
4. `FocusRequested`と実際の`FocusChanged`は別。失敗や未対応はtyped結果とし、状態だけを先行して成功にしない。
5. ブラウザのdefault actionを止める判断は必要なら同期的なDOM boundaryで行う。アプリactionのqueue処理を待ってからpreventDefaultする設計にしない。
6. gesture許可が必要なhost操作はその場で受理・拒否し、結果をqueueに返す。一般イベントと同じ遅延経路に載せて許可を失う構造を避ける。
7. `dispose`は冪等。listener、observer、timer、購読、pending effectをroot単位で解除する。

### 4.4 部品と標準要素

Web Buttonは本物のbuttonを使用し、共通Activateの入口はclickに一本化する。キー監視が必要でも別経路のActivateを発火しない。disabled/loadingによる抑止はDOMと共通側の双方で安全に検証し、支援技術由来clickをキーボードイベント不足だけで拒否しない。

Web TextFieldはinputの編集を利用する。値・選択・compositionの実測結果を共通契約へ写し、compositionendと後続inputから同じ確定を二重適用しない。キーから文字を作らず、非cancelable beforeinputをキャンセルできた前提で扱わない。[W-INPUT]

DialogはWebでdialog/showModalを候補とする。開閉状態をアプリが所有し、Escape、取消、確認、外部closeを理由付きで正規化する。ブラウザが確定したcloseとアプリ要求の再反映を区別し、通知ループを防ぐ。初期/復帰focus、背景操作抑止、composition中Escapeもfixtureにする。[W-DIALOG / W-APG]

### 4.5 layout・theme

初期範囲はRow/Column、gap、padding、min/max、grow/shrink、alignment、制限されたoverflow、Text/Button/Card/AppShell。DOMはCSS、Nativeは既存GPUI layout。共通ではlogical unitと意図を表し、任意CSS・DOM tree・GPUI描画命令を要求しない。

サイズ固定・フォント非依存fixtureの位置/寸法許容差は提案値1 logical pixel以内とし、採用前にM0/M2の証拠で固定する。文字のpixel完全一致は要求せず、欠落、クリップ、意図しない重なり、focus可視性を別判定する。画像基準は各profileに持ち、semantic不一致を画像許容差で免除しない。

テーマは初期に一つの新標準テーマのlight/darkのみ。既存Kumo themeは互換用として残すが、新ビルドにKumo抽出器やTailwindの処理を要求しない。既存ライセンス表示は維持する。

## 5. ロードマップ — 6段階

日程ではなく受入条件で進む。下位ゲート未達のprofileを、他profileの成功で補わない。

| 段階 | 成果物 | 完了時に新しくできること | 主パケット |
|---|---|---|---|
| M0 契約と差分整理 | ADR、再利用表、依存/能力表、初期fixture、証拠schema | 同じ部品・同じ操作の意味と、未対応の扱いが固定される | YK-00、GP-00 |
| M1 一つの画面を4経路へ | 共通view/runtime、DOM/GPUI adapter、Text+Button+counter | 一つの画面sourceを4つのbootstrapから起動し、操作・再描画・破棄できる | YK-01〜03 |
| M2 小さな部品ライブラリ | Button完全状態、Text/Card、layout/theme/AppShell | サイズ変更・theme切替でもstate/focusを保持し、画面を共通部品で組める | YK-04〜05 |
| M3 入力とモーダル | TextField、Dialog、3 OSの必要host機能 | 日本語入力→検証→保存→確認→focus復帰を同じ画面で行える | GP-01、GP-02-L/W/M、GP-03、YK-06〜07 |
| M4 4プラットフォームMVP検証 | 同一settings consumer、証拠matrix、回帰/寿命検査 | 宣言した4 profileで一連の操作と必要な支援技術経路を証明できる | YK-08 |
| M5 配布と段階移行 | 独立MoonBit/JS/TS consumer、tarball、移行文書 | checkoutやMoonBit compilerなしで生成済Web版を利用でき、旧APIも維持される | YK-09 |

M1は「Text+Buttonの経路が動く」だけであり、TextField/IMEや一般GUIの4環境対応完了ではない。M3の難所調査はM1と並行し、M2完了までIMEの存在確認を先送りしない。M4はライブラリの宣言範囲のMVP判定であり、gpui.mbt全体のproduction/Tier 1への昇格ではない。

## 6. MVPの一画面

画面名：Shared Settings。外部認証・ネットワーク・DB・実ファイル保存を必須にしない。

1. AppShellにタイトル、名前のTextField、説明Text、保存Buttonを表示する。
2. 日本語名を入力し、選択範囲変更、貼付、削除、undo/redoを試す。composition中の確定前文字を保存しない。
3. 空欄では保存不可とし、エラー名・説明の関係を検査する。
4. 保存で確認Dialogを開く。取消では編集値を維持し、保存開始しない。
5. 確認後は共通の明示的完了actionを持つ模擬保存へ遷移し、loading中の重複操作を抑止する。実保存機能とは呼ばない。
6. 完了で保存済み表示を更新し、閉じた後に正しいfocusへ戻る。
7. resize、light/dark変更、別UI rootの追加、mount/unmount後もイベント・購読・対象が混線しない。

必須ソースはmodel/view/updateを一つずつ。OS別に同じ画面をコピーするPRは受け入れない。起動・サービス実装・テストdriverだけを分ける。

## 7. プラットフォームとターゲットの検証範囲

| profile | 初期対象 | MVPへ必要な実測 | 推定してはいけないこと |
|---|---|---|---|
| Linux | 固定したUbuntu/Wayland、compositor/font/IME版を記録 | visible native window、入力、IME確定/取消、candidate位置、Linuxの外部AX経路 | WSL/headless/他distro全体の対応 |
| Windows | x64、固定OS/toolchain/IME | visible HWND、Microsoft IME等の実経路、UIAの必要操作 | synthetic eventのみで物理/IME対応 |
| macOS | Apple Siliconのみ | unlocked console、実際の入力/日本語IME、候補位置、AX/VoiceOverの対象範囲 | hosted build成功、Intel Mac対応 |
| Web | JS + DOM、desktop Chrome/Chromium・Firefox・Safari | browser操作、DOM editing、3 engine自動回帰、対象実ブラウザのIME/支援技術 | ChromiumだけでWeb全般対応、WebKit自動化をSafari実測と呼ぶこと |

最初の開発ループはLinux + Web/Chromium。WindowsとMacのコンパイル/lifecycleはM1から併走し、実機証拠は各担当へ分担する。4プラットフォームを目標にすることを、Linux先行を理由に変更しない。iOS/Android Native、mobile Safariの正式対応、WasmGC/Wasmのbrowser実行は後続。

## 8. 受入テストと結果の表現

### 8.1 6つの観測層

| 観測層 | 何を比較するか |
|---|---|
| 純粋model | 同じ意味的操作→同じ値・選択・開閉・要求 |
| host contract | ownership、世代、順序、cancel、未対応/拒否の型付き結果 |
| 実runtime | 本物のDOM/Native windowで操作→同じdomain結果 |
| semantic/AX | role/name/state/relationと、外部の必要操作→同じdomain結果 |
| layout/visual | 固定geometryの差、profile別画像、focus ring/clip/contrast等 |
| lifecycle/package | root間隔離、dispose、古い完了拒否、独立consumerと依存graph |

traceは低レベルOSイベントの全一致を要求しない。意味的なevent/actionと結果を正規化し、raw traceも残す。repeatやblur/composition順など意図的なprofile差は版付きallowlistへ限定し、未知の差は失敗させる。許容差を勝手に増やして結果を合わせない。

各証拠にはcandidate SHA、依存SHA/公開version、toolchain、OS/architecture、browser/IME/font、fixture版、実コマンド、起動/終了、exit code、PASS/FAIL/未実行、失敗理由、artifactを記録する。Inputの実値を既定で外部送信せず、機微情報のないfixture文字列を使う。

能力状態とテスト結果を分離する。能力がunsupportedなら呼出しは明示的に拒否する。一方、実行していないテストは「未実行」でありPASSではない。必要能力がunsupportedまたは必要証拠が欠落しているprofileはMVPゲート不合格とする。

### 8.2 維持する既存コマンド（今回未実行）

Yamiの現在のpackage.jsonとNative READMEにある入口を変更範囲に応じて実行する。以下は実行済み報告ではない。[Y-SCRIPTS / Y-NATIVE]

```sh
pnpm run moon:check
pnpm run moon:test
pnpm run build:parity
pnpm run build:npm
pnpm run test:npm
```

既存Native scriptsは`native/README.md`のOS別前提条件に従う。旧Kumo parityは旧API保護用に残し、新UIの合否基準とは分ける。新規DOM/host/fixture/packageテストのコマンドは、各実装PRで追加し、存在しないコマンドを実行済みとして記録しない。

### 8.3 マージと公開

既存ecosystem基準を維持する：最新候補HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なし。head変更後は再検証する。実装・レビューlaneの提案上の分担はgpt-6-luna/maxとgpt-6.1-sol/xhighだが、本計画作成時にそれらのジョブを起動した事実はない。[Y-UX]

文書PRと段階実装PRはそのスコープでマージ可能にするが、M4の未達を非表示にしてsupport claimを昇格させない。名前・権限・版・公開先を確認し、明示的な公開判断なしにnpm/Mooncakesへpublishしない。既存private設定やdemo公開先を変更しない。

## 9. 主要リスクと縮小手段

| リスク | 最初の検出 | 対処 |
|---|---|---|
| Nativeの日本語IME / AXがpublic APIで不足 | GP-00、M1のhost spike | gpui側でOS別に補強。Yamiで私的APIを隠して使わない |
| DOMとGPUIのlayout差 | M1最小Box、M2固定fixture | 共通layout範囲を限定し、差を数値化。任意CSS変換へ拡張しない |
| 再描画でfocus/選択/compositionが消える | YK-02/06 | keyed identity、編集中property書換抑止、世代付き要求 |
| 既存2つのButton契約差 | GP-00 | 同じfixtureで比較し、旧API維持とvNextの方針を分離 |
| 依存graphがターゲット非互換 | YK-01 | 独立JS/Native consumerで早期確認、leaf adapter分離 |
| 新UIのビルドが依然Kumo/Zag/Reactを必要とする | YK-02/09 | 新経路のclean consumer・artifact/module graph検査。dev依存とruntimeを別集計 |
| CIでIME/AXを合格に見せてしまう | YK-08 | 実機、synthetic、model、browser自動化を別行にする |
| 複数agentが同じ公共型やCIを競合変更 | 全段階 | 下記責務表と先行contract、短い縦切りPR、共通ファイルは統合担当 |

## 10. 分担と統合順

共通API/runtime担当、DOM担当、Native adapter担当、Linux/Windows/Mac host担当、検証担当へ分ける。これは計画上の担当領域で、実際の委譲・runningジョブを示さない。

1. YK-00とGP-00で共通型・必要能力・差分を定義する。
2. YK-01後にDOM（YK-02）とGPUI adapter（YK-03）を並行する。同時にGP-01/GP-03のhost不足解消を開始できる。
3. 共通fixture/schema、module manifest、CI入口は一担当が統合し、同じファイルを並行改変しない。
4. GP-01後にOS別IMEを独立PRで進める。Yamiのconsumerは公開または明示pinしたcandidateを使い、ローカルprivate patchだけで通さない。
5. YK-06/07を同じsettings画面へ組み込み、YK-08で各profileを資格付けする。
6. YK-09で独立配布物と旧consumer回帰を確認する。配布名変更や公開は別の明示判断とする。

## 11. MVP後の拡張順

MVP後はCheckbox/Switch、Tabs、Menu/Popover、Select/Combobox、List/Tableの順を候補とする。各部品は必要profileの操作・AX・状態を先に定義して追加する。Rich text、code editor、Dock、巨大DataGrid、任意HTML/CSSの変換、Reactアプリの無改変Native化、汎用状態機械DSL、自動upstream移植器は初期計画に含めない。

npm/Mooncakesの消費経路が安定した後で、MZed/dshの一部分に段階導入する。dev用turtles/hotpath/vlmkitを製品runtimeへ追加しない。

## 12. 作業パケット一覧

YKパケット10件はYami-kumoの`issues/open`へ登録。GPパケット6件は本計画内の参照ドラフトとして保管し、gpui.mbtの`issues/open`にはまだ反映していない。パケットは責務単位であり、特にOS hostやAXは複数の小さいPRに分けてよい。下記依存関係は実装順の提案であり、既存PR番号ではない。

| ID | 作業先 | 内容 | 依存 |
|---|---|---|---|
| [YK-00](../../../issues/open/20261017-ui4-yk-00-architecture.md) | Yami | 4プラットフォーム共通GUIの契約と移行ADR | なし |
| [GP-00](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-00-public-api-gap.md) | GPUI | 共通GUIが必要とする公開APIの差分調査と既存契約整合 | なし |
| [YK-01](../../../issues/open/20261017-ui4-yk-01-neutral-runtime.md) | Yami | 共通View・安定ID・寿命管理と独立consumerの最小骨格 | YK-00 |
| [YK-02](../../../issues/open/20261017-ui4-yk-02-dom-backend.md) | Yami | root単位のDOMバックエンドとkeyed更新 | YK-01 |
| [YK-03](../../../issues/open/20261017-ui4-yk-03-gpui-adapter.md) | Yami | 共通ViewのGPUI adapterと3 OS bootstrap | YK-01, GP-00 |
| [YK-04](../../../issues/open/20261017-ui4-yk-04-baseline-controls.md) | Yami | Button/Text/Cardの共通部品契約と全状態 | YK-02, YK-03 |
| [YK-05](../../../issues/open/20261017-ui4-yk-05-layout-theme-shell.md) | Yami | 制限付き共通layout・標準theme・AppShell | YK-04 |
| [GP-01](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-01-text-host-contract.md) | GPUI | TextField向けの公開編集session・IME host契約 | GP-00, YK-01 |
| [GP-02-L](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-l-linux-text-ime.md) | GPUI | Linux/WaylandのTextField・日本語IME host接続 | GP-01 |
| [GP-02-W](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-w-windows-text-ime.md) | GPUI | WindowsのTextField・日本語IME host接続 | GP-01 |
| [GP-02-M](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-02-m-macos-text-ime.md) | GPUI | macOS Apple SiliconのTextField・日本語IME host接続 | GP-01 |
| [YK-06](../../../issues/open/20261017-ui4-yk-06-textfield.md) | Yami | 共通TextFieldとDOM編集・GPUI接続 | YK-02, YK-03, GP-01 |
| [GP-03](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-03-focus-accessibility.md) | GPUI | Dialog/TextFieldに必要なfocus scopeと外部semantic action | GP-00, YK-01 |
| [YK-07](../../../issues/open/20261017-ui4-yk-07-dialog.md) | Yami | 共通Dialogと開閉・focusの往復 | YK-05, YK-06, GP-03 |
| [YK-08](../../../issues/open/20261017-ui4-yk-08-qualification.md) | Yami | Shared Settingsの4プラットフォーム資格付けと証拠matrix | YK-04, YK-05, YK-06, YK-07, GP-02-L, GP-02-W, GP-02-M, GP-03 |
| [YK-09](../../../issues/open/20261017-ui4-yk-09-distribution.md) | Yami | 独立MoonBit/JS/TS consumerと配布・段階移行 | YK-08 |


## 13. この計画で実際に行ったこと

1. GitHubからmainの基準SHAと関連コード・文書を確認した。
2. 上位部品層とGPUI host層を分けたロードマップ・実装パケットを作成した。
3. 文書bundleの構造・依存関係・リンク検査は添付の`VALIDATION.md`に実行結果を記録する。
4. 製品のビルド、MoonBitテスト、ブラウザ/Native E2E、IME、支援技術のテストは全て未実行。
5. 製品コード変更、PR作成、merge、registry公開は実施していない。Yami-kumo mainへ計画文書を登録した。gpui.mbtは未変更。
