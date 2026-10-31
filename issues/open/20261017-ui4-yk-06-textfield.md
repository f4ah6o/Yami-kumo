# YK-06 — 共通TextFieldとDOM編集・GPUI接続

AD
状態：DOM slice実装済み（#38）／native単一行adapter実装済み（#40）／OS IMEはrevision限定の部分観測のみ・AXはNOT_RUN。契約は [shared-textfield.md](../../docs/shared-textfield.md)。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M3。依存：YK-02, YK-03, GP-01。

本ファイルは計画と現在状態を併記する。DOMとnativeの単一行sliceは実装済みだが、OS IMEとaccessibilityの資格付けは未完了であり、製品対応を主張しない。

## 1. 目的・範囲

値・選択・検証・compositionの意味を共通にし、実編集はDOMまたはGPUI hostへ委譲する。3 OSのruntime検証は各GP-02の完了に依存するが、DOM/model開発は先行可能。

## 2. 実装手順

1. 単一行TextFieldから始める。label、description、error、required、read-only/disabled、value/revisionを共通APIに定義する。多行やパスワード保存は初期必須にしない。
2. DOMはinputを使い、編集中の.value書戻しでselection/compositionを破壊しない。未確認の古い外部revisionを上書き採用しない。
3. compositionstart/update/endとinput/beforeinputの実測列をGP-01へ変換する。non-cancelable eventやcommit後inputでも二重挿入しない。編集hostのundoを二重実行しない。
4. 貼付、cut、選択、delete、undo/redo、form resetを含む。旧DOM Fieldのreset後pristine/filled/invalid再同期を回帰として残す。
5. NativeはGP-01と3 OSの公開bridgeを使う。未対応profileではcapability不足を明示し、Textで偽装してTextField対応と呼ばない。現状は`native/ui`がGPUI `controls/text_field`を保持し、click/focus、caret、編集、submit/blur、host `Composition` eventを処理する。copy/pasteとOS IME/AXは未対応。
6. IME中の保存やDialog Escapeについて、未確定値の扱いとキーの優先順をYK-00の契約どおり実装する。

## 3. テスト対象と反例

DOM sliceはPR #38、native sliceはPR #40で実装した。以下は未完了項目を含む。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 日本語、絵文字、結合文字、surrogate境界、RTLを含むoffset入力の拒否/維持を検査する。RTL完全編集対応をfixture存在だけで主張しない。
2. composition後のnon-cancelable beforeinput/inputで重複しない。
3. 値の外部更新、re-render、blur、remove、reset中の状態を確認する。
4. label/name/error relation、値変更の外部操作を検査する。

## 4. 受入条件

- [ ] 共通のsettings viewにTextFieldを追加できる。
- [ ] Web実編集が動き、NativeはGP-02ごとの実測状態が明示される。
- [ ] 全4 profileのTextField完了は3 OS bridgeの資格付け後に判定する。

## 4a. 実装済みの証拠

- DOM: 実Chromiumでcommit、composition deferral、rapid edit、submit、focusを確認（#38）。
- Native: GPUI `0.10.0`（release tree `fffe79168e7ad79dffe2002e83a570551b1ae8f1`）に対し、native/ui 49/49、native ui + shared counter 66/66、Yami root 58/58。
- Native composition: previewは`TextChanged`を出さず、commitは1回だけ出し、cancelはactionを出さないheadless test。
- macOS Kotoeri、candidate window、copy/paste、AX: **NOT RUN**。synthetic compositionは実IMEの合格ではない。
- `text_session.TextSession`のowner/revision統合は未接続。native adapterは現在`TextField`を直接保持し、共通runtime tokenでactionをgateする。

### 2026-10-30: focus loss 時の observed commit 消失

PR [#83](https://github.com/f4ah6o/Yami-kumo/pull/83) の field binding
guard は旧 session の記録を別 field に適用しないが、focus loss 時に cancel が
未取得の同 epoch `Commit` を破棄するケースを解決しない。[最小再現と FAIL
ログ](../../docs/evidence/20261030-shared-settings-text-owner/README.md) を参照。
これは GUI native 受入の blocker であり、portable suite の PASS は代替にならない。

次に [GP-01B text-host issue](https://github.com/gpui-mbt/gpui.mbt/blob/main/issues/open/20261019-gp-01b-text-host-contract.md)
と [text-host contract](https://github.com/gpui-mbt/gpui.mbt/blob/main/docs/text-host-contract.md)
と [M3 coordination](https://github.com/gpui-mbt/gpui.mbt/blob/main/issues/open/20261019-m3-textfield-dialog-coordination.md)
へ結び付け、focus / close / replacement の境界で pending observation の取得終了と
`TextSession` の `request_end` / `complete_blur` または `complete_replacement` を
どう同期するか確定する。既観測 commit は旧 owner に保存し、revocation 後の
epoch / target は拒否する。空の一回の poll だけを排他 barrier と扱わず、host が
提供する順序・quiescence の保証を調査して必要な契約変更から着手する。

### 2026-10-31: Shared Settings の部分 live 観測と残る owner 境界

上の「OS IME NOT RUN」は以前の対象 revision の記録であり、後続の独立した部分実行を消さない。現在の本ゴールは **未達**。

- **実装の所在**：Yami [#117](https://github.com/f4ah6o/Yami-kumo/pull/117) `585ff82109df0fa006f3031258476257d0b9cc86` と gpui [#200](https://github.com/gpui-mbt/gpui.mbt/pull/200) `53e42a5888167fd9203b27f6558deabaf5c54e4b` は作業時点では PR-only。same-HEAD の独立レビューと必要な CI は実施済みだが、公開 registry だけの依存解決ではない。現行 package の不足は [#90](https://github.com/f4ah6o/Yami-kumo/pull/90) の clean fixture を参照。
- **Linux live の実行結果**：[#119](https://github.com/f4ah6o/Yami-kumo/pull/119) の独立監査済み raw 記録は、同じ #117 source から build した binary SHA-256 `8355c8c861faa784fe3c0a94ae663caad04c41a5d7fb2b35354f4c29f0f5b7f6`、harness `b6e77fb61a38b3ca763b4bc7729ad837e2182fc2`、nested Weston／live IBus-Mozc／X11 注入の組を使用した。preedit 8件と `Commit("日本")` 1件を記録し、native sequence 24 の独立した local receipt stage は `ModelApplied`。raw manifest SHA-256 `e31640497f7ba99151df07cd018420e741e061f4f05892bb7eebcf42f9d89563`。これはその receipt の stage 証拠であり、scene／caret、undo 履歴全般、候補 UI、物理 keyboard の合格ではない。
- **候補・操作・終了**：IBus log は `日本` 等の lookup state と後続 hidden state を含むが、候補行／選択／画面の同期照合は **NOT_RUN**。Dialog、focus 復帰、再open、resize／blur／close 競合もこの run では **NOT_RUN**。stop は拒否され、隔離テスト process の SIGTERM により in-memory owner は保存されなかったため cleanup は **FAIL**。
- **bounded scene の blocker**：suspended `advance_once` は field/model 適用後に戻り dirty scene／caret を present しない（再現 fixture branch `aafa76977033c453b14e9598db16901215a767cd`）。[Yami #120](https://github.com/f4ah6o/Yami-kumo/pull/120)、[#121](https://github.com/f4ah6o/Yami-kumo/pull/121)、[#122](https://github.com/f4ah6o/Yami-kumo/pull/122) は元 owner の preview／rollback を再測定し local candidate を保持する PR-only 作業で、host geometry receipt、runtime/focus・scene の coordinated publication、失敗後の rollback／reconcile は未実装。候補は publish を拒否し、実アプリ resize 回復の証拠ではない。
- **旧 owner／直接入力の blocker**：Tab cutoff 後も元 terminal owner と direct receipt は残り、次 epoch は旧 owner の明示解決まで拒否される。direct receipt の frame prefix／retirement は [#118](https://github.com/f4ah6o/Yami-kumo/pull/118) でも通常の未分類 key が先行すると保留される。gpui #200 の inherited XKB compose は Ctrl／Meta press で未解決 composition を破棄し得る P1 が独立 fixture で発見され、[gpui #203](https://github.com/gpui-mbt/gpui.mbt/pull/203) は fail-closed 候補にすぎず recovery として未受入。これを IBus/Mozc の #119 観測と混同しない。

次は同一 owner の accepted record／action／model、host cutoff、geometry、scene を段階別に保持し、失敗後も再適用や新 epoch への付替えをせず復旧できる transaction を実装・検証する。候補 UI、Dialog 再open、race、cleanup、公開依存、macOS 実機は別 gate のまま残す。

### 2026-10-31: geometry intent と後着 record の controlled fixture

- **所在とレビュー**：gpui [#210](https://github.com/gpui-mbt/gpui.mbt/pull/210) `6f7fbd20c4e916e64f13aaeaf58aaa410a1e9d20` と Yami [#134](https://github.com/f4ah6o/Yami-kumo/pull/134) `3039ff9d996854703aec6c31c2f35f95db7e0536` は PR-only、公開 dependency ではない。#210 の同一 HEAD の [scoped 独立レビュー](https://github.com/gpui-mbt/gpui.mbt/pull/210#pullrequestreview-5720657887) は記録済み。これは live IME や consumer 適用の承認ではない。候補は native 未試行の geometry intent、native 呼出し後の結果不明、native 受理 receipt を分け、元 owner に後着 text を保持する。native sequence と portable text ordinal の混同は [#128 の P1](https://github.com/f4ah6o/Yami-kumo/pull/128#pullrequestreview-5720577918) で確認され、[#132](https://github.com/f4ah6o/Yami-kumo/pull/132) `b221a8e7b8d4b4968dfe4fad7deace056601db71` で独立に検査する修正が scoped review 済み。
- **controlled 実行**：[#135](https://github.com/f4ah6o/Yami-kumo/pull/135) `172b7328c8fea48f65f473349a866a07c48563ad` の [独立 audit](https://github.com/f4ah6o/Yami-kumo/pull/135#pullrequestreview-5720670169) は digest と source 関係を確認した。raw log に source SHA／toolchain stamp はなく app binary も未保持のため、digest だけで過去の実行 revision／toolchain を独立認証できない。この制限は [#139](https://github.com/f4ah6o/Yami-kumo/pull/139) で明記した。product source は上の #134／#210、実行した Yami test source は `61abf307b0e92b5bdc25d4ad9f7b97a2522f9952`、test-only GPUI wrapper は `b714dce0d285f434becc258a224068767ff956f5`。実 native FIFO／decoder／ACK と mock Wayland protocol を用い、元 Shared Settings owner の予約、native seq 2／text ordinal 1 の commit、FIFO Busy、handoff、同じ intent の submit と host-local receipt まで 8/8 PASS。raw manifest SHA-256 `850c6000c651d556b5f7168633ec9da7a3271c6ef165be359394aa86b9718dd2`。これは test executable の記録で、実 app binary の digest は捕捉していない。
- **未受入と次の境界**：後着 commit は元 owner／route slot で未適用のまま、共有 model は空のまま。scene／caret、実 model 反映、Dialog／focus 復帰、resize／blur／close 競合、安全な cleanup、live IBus／Mozc、clean registry、Apple Silicon 実機はいずれもこの fixture では **NOT_RUN**。複数到着や非 text head は一件 slot では詰まり得る。native 未試行 intent と受理済み receipt を consumer 側の action／model／runtime／focus／scene へ順序を守って結び、失敗後も元 owner を維持する必要がある。
- **別の既知問題**：上記は #200 inherited XKB compose の P1 を修正・受入した証拠ではない。#203 は破棄を避ける fail-closed 候補だが latch 後の有限回復は未達。#209 は preflight 未到達を識別する別案であり、#210 の intent と同じ実装や統合済み release と扱わない。

### 2026-10-31: 元 owner の保持と後続 live probe

本節は調査時点の revision を固定する。次の候補はすべて PR-only であり、main への統合、公開済み package、元の runner P1 の解消を意味しない。Yami [#88](https://github.com/f4ah6o/Yami-kumo/pull/88)／[#89](https://github.com/f4ah6o/Yami-kumo/pull/89) は **DO NOT MERGE** を維持する。

- **一件の元 owner 保持**：[Yami #149](https://github.com/f4ah6o/Yami-kumo/pull/149) `da7fc485c89a04d3c7dc05c5386276c173a542ea` は geometry 受理後の後着 native text record 一件を元 owner へ予約し、一度だけ引き渡す候補。host の receipt は host 内の受理のみを表す。元 owner への TextSession／model 適用や scene 公開、安全な終了は本候補の対象外。[#150](https://github.com/f4ah6o/Yami-kumo/pull/150) `e465ee9c16fb0bdbfcd855620b765b9327bbf9ef` は制御命令に元 native sequence を要求し、遅延命令と二重 take を拒否する。同一 HEAD の [独立レビュー](https://github.com/f4ah6o/Yami-kumo/pull/150#pullrequestreview-5720950954) では socket baseline 13/13、独立 AF_UNIX fixture 9/9 PASS、対象差分に新たな P0/P1/P2 なし。CI は 7/7 jobs PASS。この結果を runner 全体の承認や既存 P1 の解消と読み替えない。
- **後続の Linux 実行**：[#151](https://github.com/f4ah6o/Yami-kumo/pull/151) `abb31886b9127cff243215f87d90bf9696de2352` に同一 session の build record／binary／raw log を保存し、[独立 audit](https://github.com/f4ah6o/Yami-kumo/pull/151#pullrequestreview-5720923346) を行った。framework は gpui #211 `35b9041dfb3642b43ca37c604834942614eb50fb`、consumer root／app source は Yami #142 `1a59626cf67910917c4d660dd6db8bedae55a722`、harness は #148 `f8022d251a52a198a5af01cc2ec9f7b757e277c1`、app binary SHA-256 は `1e6d5050e5605b0415df978a07493ce5cb52a75749c46c9d0ce6d2ce88547b8c`。Linux x86_64 の nested Xvfb／Weston 14.0.2、live IBus 1.5.32／Mozc、X11 注入であり、physical keyboard ではない。コマンドは保存した `launch.sh` の環境で `dbus-run-session`／`xvfb-run` の下に harness `session.sh` を実行。source override を使用し registry-only lock はない。run URL はなく、toolchain と manifest の詳細は保存 artifact を参照。
- **観測と限界**：preedit `ｎ` と native seq 11 の release-policy ACK が観測され、1 回の advance は seq 12 を処理。その後 `geometry-submit` は `dirty_scene: original owner is not ready to stage`、handoff は `geometry_pending_missing` を返した。どの stage guard が拒否したかはログにないため、Busy 等を原因と確定しない。transport に後続の `に` はあるが consumer 適用、commit、model は観測されず、scene／caret、候補選択、Dialog／focus、blur／resize／close race は **NOT_RUN**。stop が拒否され SIGTERM となり cleanup は **FAIL**。原 manifest SHA-256 `b4778105c885f4d9142cfd18d5b8e6782abffb0fa23506614637dc6d7ae3b7dd`；copy 時の digest は一致したが `/proc` で 669 process にアクセスできず、writer 終了／artifact 安定性は **UNVERIFIED**。local metadata は署名付き attestation ではない。上の #119 の model 適用をこの app/harness に流用しない。
- **次の probe の証拠記録**：[#152](https://github.com/f4ah6o/Yami-kumo/pull/152) `bf77ed8c6d730146ccde59b58c323826d04ad3a7` は新しい consumer preedit marker を最大 8 回の個別 advance で待つ。7/7 CI は PASS したが、[独立レビュー](https://github.com/f4ah6o/Yami-kumo/pull/152#pullrequestreview-5720950958) は generation／advance timeout 時に試行 command と geometry の NOT_RUN が記録されない P2 を発見した。geometry 自体は起動されないため false PASS ではなく、証拠欠落である。[#153](https://github.com/f4ah6o/Yami-kumo/pull/153) `ecc63bbe8ed2efc219fbea5fa9d6d4631ed46531` は別 draft の修正候補で、synthetic probe 7/7 PASS。正確な HEAD の [独立レビュー](https://github.com/f4ah6o/Yami-kumo/pull/153#pullrequestreview-5720964391) は元の timeout 記録欠落の修正を確認した一方、新たな P2 を発見した。receipt／stage の timeout 時、部分 stdout を成功と読み、依存操作を続け得る。controlled full-driver fixture で再現され、実機合格ではない。修正・再レビューと正確な HEAD の CI、同一 session の新規 build と live run が必要。

- **元 owner への一回適用候補**：[#154](https://github.com/f4ah6o/Yami-kumo/pull/154) `efd6abfad47a3f51293b14f9737ab495b4698956` は #150 と gpui #211 に依存し、引き取った record を元 Settings owner の field／model に一回反映し、delivery／action を中断中も保持する限定実装。controlled native common 124/124、Ubuntu native `moon check --target native --deny-warn` と `git diff --check` は PASS。scene と host geometry は以前の状態のままで、通常 drive／focus／cutoff／frame 公開／stop は封鎖したままのため、**DO NOT MERGE**。cross-layer transaction、live IME、cleanup、registry consumer の受入ではない。正確な HEAD の独立レビューは本記録時点で未完了。

| 場所 | 観測した原因・状態 | 必要な対処 | 影響範囲 |
| --- | --- | --- | --- |
| Yami 元 owner／dirty scene／gpui host | controlled fixture では #149 の slot transfer 後、pending dirty stage と未検証 host epoch が consumer 適用を拒否した。#154 は元 owner への一回適用を限定的に許すが scene／host は古いまま。host geometry の受理だけでは scene／focus との一致を保証しない。 | 同じ owner、epoch、sequence と未適用 action を保持し、失敗・retry 時も二重適用しない回復可能な field／model／host／scene／focus の順序を実装・検証する。 | commit の反映完了、resize／blur／close、Dialog 復帰、cleanup |
| gpui XKB compose | #200 の継承経路で Ctrl／Meta press が未解決 compose を破棄し得ることを controlled fixture で確認。#203 は fail-closed だが latch 後の有限回復は未成立。実 compositor での発生は未確認。 | 既存 compose と受理済み record を維持した bounded admission と有限 recovery を確立する。 | 該当する direct XKB composition／終了。#151 の IBus 観測とは別。 |
| 公開依存 | [#90](https://github.com/f4ah6o/Yami-kumo/pull/90) では clean registry の gpui 0.10.6／Yami root 0.2.3／native 0.2.14 で旧 scripted fixture 1/1 PASS、#89 source は必要な 4 API 不足で compile FAIL。固定版より後の候補の registry consumer は未検証。 | 解決済み候補を必要な CI／同一 HEAD 独立レビュー後に依存・公開版へ反映し、空 cache・source override なしで build と操作を再検証する。 | 公開 API の外部 consumer 受入 |
| OS profile | 最新候補で Web 合成 composition、Apple Silicon macOS 実機、Windows 実 IME は **NOT_RUN**。以前の macOS 証拠や Windows fixture は独立した revision／範囲。 | 同じ操作契約と正確な revision の組で各 profile を別々に検証する。 | 対象 OS ごとの受入。Linux 結果で代用しない。 |

## 5. 非対象

inputのふりをしたCanvas編集、全キーからの文字列自作、Rich text、古い文字モデルの複製。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-WEB: Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [W-INPUT: W3C Input Events Level 2](https://www.w3.org/TR/input-events-2/)
