# YK-06 — 共通TextFieldとDOM編集・GPUI接続

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M3。依存：YK-02, YK-03, GP-01。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

値・選択・検証・compositionの意味を共通にし、実編集はDOMまたはGPUI hostへ委譲する。3 OSのruntime検証は各GP-02の完了に依存するが、DOM/model開発は先行可能。

## 2. 実装手順

1. 単一行TextFieldから始める。label、description、error、required、read-only/disabled、value/revisionを共通APIに定義する。多行やパスワード保存は初期必須にしない。
2. DOMはinputを使い、編集中の.value書戻しでselection/compositionを破壊しない。未確認の古い外部revisionを上書き採用しない。
3. compositionstart/update/endとinput/beforeinputの実測列をGP-01へ変換する。non-cancelable eventやcommit後inputでも二重挿入しない。編集hostのundoを二重実行しない。
4. 貼付、cut、選択、delete、undo/redo、form resetを含む。旧DOM Fieldのreset後pristine/filled/invalid再同期を回帰として残す。
5. NativeはGP-01と3 OSの公開bridgeを使う。未対応profileではcapability不足を明示し、Textで偽装してTextField対応と呼ばない。
6. IME中の保存やDialog Escapeについて、未確定値の扱いとキーの優先順をYK-00の契約どおり実装する。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 日本語、絵文字、結合文字、surrogate境界、RTLを含むoffset入力の拒否/維持を検査する。RTL完全編集対応をfixture存在だけで主張しない。
2. composition後のnon-cancelable beforeinput/inputで重複しない。
3. 値の外部更新、re-render、blur、remove、reset中の状態を確認する。
4. label/name/error relation、値変更の外部操作を検査する。

## 4. 受入条件

- [ ] 共通のsettings viewにTextFieldを追加できる。
- [ ] Web実編集が動き、NativeはGP-02ごとの実測状態が明示される。
- [ ] 全4 profileのTextField完了は3 OS bridgeの資格付け後に判定する。

## 5. 非対象

inputのふりをしたCanvas編集、全キーからの文字列自作、Rich text、古い文字モデルの複製。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-WEB: Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)
- [Y-NATIVE: Yami-kumo: Nativeの実装・検証境界](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/native/README.md)
- [G-TEXT: gpui.mbt: UTF-16文字・compositionモデル](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/docs/text-model.md)
- [W-INPUT: W3C Input Events Level 2](https://www.w3.org/TR/input-events-2/)
