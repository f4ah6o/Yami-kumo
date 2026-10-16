# 4プラットフォーム共通GUI — 計画書

**状態：計画ドラフト。製品実装・GUIテスト・支援技術テストは未着手／未実行。**

- [ROADMAP.md](ROADMAP.md) — M0〜M5の実装順・境界・受入条件。
- [Yami側の10課題](../../../issues/open/20261017-ui4-yk-00-architecture.md) — YK-00〜YK-09を`issues/open`へ配置。
- [GPUI側の6課題（参照ドラフト）](repos/gpui-mbt/gpui.mbt/issues/open/20261017-ui4-gp-00-public-api-gap.md) — 作業対象は`gpui-mbt/gpui.mbt`、今回そのリポジトリは変更していない。
- [manifest.json](manifest.json) — 16件の依存関係と配置。
- [SOURCES.md](SOURCES.md) — 参照したソースの基準SHA。
- [VALIDATION.md](VALIDATION.md) — この計画の文書整合性検査結果。製品のテスト成功ではない。

このリポジトリのルートから文書と参照の整合性を検査：

```sh
python docs/roadmaps/20261017-four-platform-gui/validate_plan.py
```

この登録は実装開始・API変更・npm/Mooncakes公開を意味しない。
