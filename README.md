# html-report

Claude Code に「HTMLでまとめて」「社内限定で公開して」と頼むと、図表つきの HTML レポートを作り、Google Workspace のドメイン内の人だけが見られる URL で公開する Agent Skill です。

- 公開先は Google Apps Script のウェブアプリです。`webapp.access = DOMAIN` により、同じドメインの Google アカウント以外は Google 側で拒否されます
- 同じレポートを更新しても公開 URL は変わりません
- 閲覧者はリンクを開くだけで見られます（OAuth の承認画面は出ません）

## 必要なもの

- Claude Code
- Google Workspace のアカウント（個人の Gmail アカウントではドメイン限定公開ができません）
- Node.js 20 以上と pnpm
- [Apps Script API](https://script.google.com/home/usersettings) を有効にしていること

## インストール

```bash
git clone https://github.com/cm-AndoSadayoshi/html-report-skill.git ~/.claude/skills/html-report
cd ~/.claude/skills/html-report
pnpm install
pnpm exec clasp login
```

`clasp login` ではブラウザが開くので、公開先ドメインの Google アカウントで承認してください。

## 使い方

Claude Code との会話で次のように頼みます。

```text
この調査結果、HTMLレポートにまとめて社内限定で公開して
```

Claude がレポートを作り、公開してよいか確認したうえで `scripts/deploy.sh` を実行し、公開 URL を返します。スクリプトを直接実行することもできます。

```bash
~/.claude/skills/html-report/scripts/deploy.sh <HTMLファイル> <slug> [タイトル] [--dry-run]
```

- slug は英小文字・数字・ハイフンのレポート識別子です。同じ slug で再実行すると既存のデプロイを更新するので、URL は変わりません
- 公開 URL のドメインは、clasp でログインしているアカウントから自動で取得します。別のドメインを使う場合は `GAS_DOMAIN=example.com` を指定してください

## 状態の置き場所

| パス | 内容 |
|---|---|
| `~/.gas-reports/<slug>/` | slug ごとの Apps Script プロジェクト |
| `~/.gas-reports/registry.tsv` | slug と公開 URL の対応表 |

置き場所は環境変数 `GAS_REPORTS_DIR` で変更できます。

## 制限

- 閲覧者を特定のメンバーに絞る `ALLOWED_USERS` は、deploy.sh を再実行するとテンプレートの空の値に戻ります。絞り込みの手順は SKILL.md のトラブルシューティングを参照してください
- ブラウザで複数の Google アカウントにログインしていると、既定のアカウントで開かれて「権限がありません」と表示されることがあります。共有時は「会社のアカウントで開いてください」と添えてください

## 解説記事

[AIが作ったHTMLをGoogle Workspaceで社内限定公開してみた | DevelopersIO](https://dev.classmethod.jp/articles/html-service-20260924/)

## License

MIT
