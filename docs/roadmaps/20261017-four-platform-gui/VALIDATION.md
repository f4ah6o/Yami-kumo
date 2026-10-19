# 計画文書の検査結果

状態：文書検査 completed。製品テストの結果ではない。
日付：2026-10-17 JST。対象：Yami-kumo mainへ登録する計画文書と16個のドラフト。

実行したコマンド：

```sh
python docs/roadmaps/20261017-four-platform-gui/validate_plan.py
```

検証対象：パケットID、依存グラフ、相対リンク、Markdown code fence、基準SHA、実装前ステータス。

MoonBit/JS/Nativeビルド、日本語IME、ブラウザE2E、外部アクセシビリティ、CI、独立レビューは**未実行**。
この記録は作業ブランチ／GitHubのコード上で実施した製品検証ではない。

## 2026-10-19 追記

`STATUS.md` と YK-01/02/06/07 の状態行を更新した後の再検査：

```sh
python3 docs/roadmaps/20261017-four-platform-gui/validate_plan.py
```

- PASS: 16 packet files、依存グラフ16 nodes、ローカルリンク45件、code fence。
- `manifest.json` は 2026-10-17 の凍結スナップショットのまま。現在値は `STATUS.md`。
- 製品ビルド、MoonBitテスト、DOM/Native E2E、IME、AXは引き続き未実行。この追記は文書検査のみ。
