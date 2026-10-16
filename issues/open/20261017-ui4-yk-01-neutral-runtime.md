# YK-01 — 共通View・安定ID・寿命管理と独立consumerの最小骨格

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M1。依存：YK-00。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

UIの意味を持つ共通Viewと、host固有型を外へ出さない最小runtimeを導入する。単なる共通データ型だけでなく、同じ画面sourceを異なるhostへ接続できることを実証する。

## 2. 実装手順

1. 提案配置ui/core、ui/components、ui/runtimeにNodeKey、mount世代、部品props、意味的action、host request/resultを定義する。型名・package分割は実装時に独立consumerで確認する。
2. アプリmodel/updateは一つだけが所有する。NativeのApp/Entityを使用する際、別modelの同期ループを作らない。汎用reactivity/virtual-DOM frameworkは作らずText/Button/containerに必要な更新から始める。
3. 重複キー拒否、同一キー/typeのinstance維持、削除後イベントの拒否、冪等disposeを実装する。Native IDとDOM IDはprivate mapで変換する。
4. 受信イベント、host要求、観測結果の順序を定義する。native callbackからの再入を避け、DOM default actionの同期判断とaction queueを混同しない。
5. JS用とNative用の独立consumerで、共通model/view sourceをコピーせずコンパイルする。OS backendやReact/ZagがWeb runtimeへ入らないことを確認する。未実装hostは明示する。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 重複キー、古いmount世代、unmount後timer/async結果を拒否する。
2. 同一state入力から決定的なview/action traceが出る。
3. JS/Native consumerは同一view sourceを参照する。
4. privateなDOM/GPUI handleが公開型へ露出しない。

## 4. 受入条件

- [ ] 同じText+Button画面のモデルを両targetでビルドできる。
- [ ] pure model/runtimeテストと依存境界検査がCIにある。
- [ ] runtime表示は後続YK-02/03の証拠として分ける。

## 5. 非対象

全面的な独自DSL、signals framework、ReactNode互換、Wasm/WasmGC runtime。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-WEB: Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [G-README: gpui.mbt: パッケージと現在の対応範囲](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/README.md)
- [M-TARGET: MoonBit: package / conditional compilation / JS exports](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html)
