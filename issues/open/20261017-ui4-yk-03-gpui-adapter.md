# YK-03 — 共通ViewのGPUI adapterと3 OS bootstrap

状態：bounded implementation candidate／共通counterとGPUI adapterの実装候補／実機結果は候補HEADのCI artifactで判定。macOS runtime・AXは未実行、M1全体は未完了。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M1。依存：YK-01, GP-00。

本ファイルの存在だけでは公開・mergeを承認しない。bounded実装はText/Button/Column/Rowと単一App Entityに限定し、Box・一般layout・IME/AXは含まない。実機profile未実行を他OSの成功から補完しない。

## 1. 目的・範囲

共通Viewを既存GPUI layout/element/sceneへ接続する。3 OSの起動部分以外で画面sourceを複製しない。

## 2. 実装手順

1. 既存native moduleへnative/uiを追加し、共通NodeKeyとNative element/scene IDをprivateに対応付ける。root/window/世代を区別する。
2. Text/Box/Buttonを既存Native部品・GPUIモデルへ接続する。Button入力を既存2 controllerへ二重配送せず、GP-00で確定した再利用先を一つ使う。
3. GPUIの既存App/Entity、notify、focus、layout、paintを再利用する。共通modelの更新後だけ必要な再描画を要求する。
4. Linux/Windows/macOSのbootstrapを追加する。共通画面・操作定義は一ファイル群を使用し、OS差は能力・adapterに閉じる。
5. destroy/resize/focus loss/bounds invalidationで古い入力・scene・targetを拒否する。既存sampleの実行導線・target安全策を再利用する。

## 3. テスト対象と反例

portable adapter/App testsはJS/native/wasm/wasm-gcで実行する。Linux/Windowsは同一fixtureの実host click・completed frame・destroyを別workflowで検証し、macOSはbuild/portable testsのみ。各結果は実装PRのcandidate SHA・profile・exit code・artifactで記録する。

1. 3 OSのビルド/portable testsと、実行したOSのvisible-window click/frame/teardownを分けて記録する。
2. 同じButton IDでも別windowや古いmountからの操作を拒否する。
3. resize中のheld gesture、unmatched release、destroy後eventを検査する。

## 4. 受入条件

- [ ] 同じText+Button画面が3 OSの公開API経路で起動する。
- [ ] M1の4経路完了はYK-02と本パケットの全必須実機証拠が揃ってからとする。
- [ ] 未実行OSをLinuxの成功から推定しない。

## 5. 非対象

新OS backend、独自GPU renderer、private API依存、一般IME/AX完成の主張。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [Y-BUTTON: Yami-kumo: 既存Native Button](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/components/button.mbt)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [G-BUTTON: gpui.mbt: 既存Buttonモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/controls/button/button.mbt)
