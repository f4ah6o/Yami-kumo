# YK-02 — root単位のDOMバックエンドとkeyed更新

状態：proposed／実装未着手／製品テスト未実行／Yami-kumo mainへ計画ドラフト登録。
作成日：2026-10-17 JST。
作業先：`f4ah6o/Yami-kumo`。段階：M1。依存：YK-01。

本ファイルは計画ドラフトであり、承認済み仕様・既存PR番号・実装完了を示さない。実装開始時に最新mainと関連PRを再確認する。

## 1. 目的・範囲

自前MoonBit/JS FFIでDOMへmount/update/unmountする。第三者JS GUI frameworkを標準経路に含めない。旧renderHtmlとenhanceYamiKumoは破壊しない。

## 2. 実装手順

1. ui/domにDOM要素の生成、属性/property更新、listener登録/解除を実装する。root外のDOMを書き換えず、二つの独立rootを同時mountするfixtureを作る。
2. Textはtext node、Buttonはbutton、containerは適切なDOM要素にする。ユーザー文字列をinnerHTMLへ流さず、許可する属性/URL/propertyを限定する。
3. keyed instanceを保持し、label・状態変更でfocused elementを作り直さない。更新不要なpropertyを書き戻さず、listener/observerを重複登録しない。
4. Button Activateをclickへ一本化する。キー処理はdefault action制御に必要な範囲に限定し、別のActivateを合成しない。root/世代チェックと古いcallback拒否を行う。
5. 明示mount前のimportは副作用なしとする。common entryはNodeでimportでき、DOM entryはmount時に環境を判定する。resize/frameはブラウザのcallbackで扱い、busy waitしない。
6. 成果物・依存graphを検査し、Kumo/Zag/Reactのimportや隠れた実行時同梱を新経路へ入れない。build/testツールは別扱いで記録する。

## 3. テスト対象と反例

以下は実施予定。すべて未実行。実装PRで実際のコマンド・candidate SHA・profile・exit code・artifact・PASS/FAIL/未実行を記録する。

1. 実ブラウザでcounterが1操作につき契約どおり更新される。
2. listener重複、別root混線、unmount後click/resize、悪意ある文字列を検査する。
3. 繰返しmount/update/unmount後に所有listener/observer数が基準へ戻る。
4. 既存npm/旧HTML consumerを維持する。

## 4. 受入条件

- [ ] 実DOMでText+Button共通画面が動く。
- [ ] keyed更新とroot隔離のbrowserテストがある。
- [ ] Canvasはこの標準DOM画面の表示経路に使わない。

## 5. 非対象

Input/IME完成の主張、Shadow DOM強制、全HTML/任意CSS互換、framework依存。

## 6. PR・統合ルール

責務を超える場合は小さいPRへ分ける。OS別hostは並行可能だが公共型・module manifest・共通CIは統合担当を一人にする。最新HEADの必要CI completed/success、同じHEADへの実際のgpt-6.1-sol/xhigh独立レビューApprove相当、未解決P0/P1なしを維持する。未実行profileを他環境の成功で埋めず、合格したscopeのみ報告する。公開・push・mergeをこの計画ファイルの存在だけで実行しない。

## 7. 調査根拠

- [Y-WEB: Yami-kumo: HTML部品API](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/components.mbt)
- [Y-NPM: Yami-kumo: npm previewの利用・配布契約](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/npm/README.md)
- [Y-SCRIPTS: Yami-kumo: 既存のビルド・テストコマンド](https://github.com/f4ah6o/Yami-kumo/blob/7a2c088934e2104e48b9f58b23724c2160520202/package.json)
- [G-BROWSER: gpui.mbt: 既存Canvas型ブラウザ計画](https://github.com/gpui-mbt/gpui.mbt/blob/a99e111a37c0ac98bd847e9ea493c78589207875/issues/open/0009-browser-backend.md)
