# 4プラットフォーム共通GUI — 計画書

**状態：この計画は 2026-10-17 の凍結スナップショット。現在の実装状況は [STATUS.md](STATUS.md) を参照。M3 の製品実装・IME/AX 資格付けは進行中で、未実行の profile は未実行のまま。**

- [STATUS.md](STATUS.md) — 2026-10-19 時点の実装・証拠・pin。`manifest.json` の `proposed / not_started / not_run` は凍結時点の計画値であり、現在値ではない。
- [ROADMAP.md](ROADMAP.md) — M0〜M5の実装順・境界・受入条件。
- [Yami側の10課題](../../../issues/open/20261017-ui4-yk-00-architecture.md) — YK-00〜YK-09を`issues/open`へ配置。
- [GPUI側の6課題（参照ドラフト）](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-00-public-api-gap.md) — 作業対象は`gpui-mbt/gpui.mbt`。
- [manifest.json](manifest.json) — 凍結時点の16件の依存関係と配置。
- [SOURCES.md](SOURCES.md) — 参照したソースの基準SHA。
- [VALIDATION.md](VALIDATION.md) — この計画の文書整合性検査結果。製品のテスト成功ではない。

このリポジトリのルートから文書と参照の整合性を検査：

```sh
python docs/roadmaps/20261017-four-platform-gui/validate_plan.py
```

この登録は実装開始・API変更・npm/Mooncakes公開を意味しない。
