---
name: html-report
description: 図・表を活用した自己完結HTMLレポートを作成し、希望があれば社内限定URL（Google Apps Script ウェブアプリ・自社の Google Workspace ドメイン限定）として公開する。同じレポートを更新しても公開URLは変わらない。Triggers: "HTMLファイルで図や表を活用して分かりやすく", "HTMLでまとめて", "HTMLレポートにして", "図解して教えて", "社内URLで共有", "社内限定で公開", "/html-report"
---

# HTMLレポート作成・社内限定公開

情報の整理・報告を、図・表を活用した単一の自己完結HTMLファイルとしてまとめ、必要に応じて社内限定URLで公開する。2段構成で進める。

1. **レポート作成** — 常に実施
2. **社内限定URL公開** — ユーザーが希望した場合のみ（必ず確認を取る）

## 適用しないケース

- 社外にも共有したい場合 → Artifact（claude.ai）を使う（本スキルの公開先は自社の Google Workspace ドメイン限定）

## ステップ1: レポート作成

### 設計原則

- **単一の自己完結HTML**。外部CDN・webフォント・外部画像に依存しない（画像が必要なら base64 埋め込み）
- **スキャン優先の構成**: サマリ（KPIタイル）→ 詳細、の順。読者が30秒で要点を掴めること
- **日本語タイポグラフィ**: 見出しは明朝系（`"Hiragino Mincho ProN", "Yu Mincho", serif`）、本文はゴシック系（`"Hiragino Sans", "Yu Gothic", Meiryo, sans-serif`）。数字が並ぶ箇所は `font-variant-numeric: tabular-nums`
- **ライト/ダーク両テーマ対応**: CSS変数を `:root` にライト定義 → `@media (prefers-color-scheme: dark)` でトークンのみ再定義。`body` に明示的な `background` を必ず指定
- **状態は色チップで符号化**: 進展=緑・停滞/注意=琥珀・懸念=赤・新規=青。アクセント色とは分離する
- **表は `overflow-x: auto` のコンテナで包む**（ページ全体を横スクロールさせない）
- 内容に応じて使う部品: KPIタイル / タイムライン図 / 状態チップ付きテーブル / アラートカード（日数など数値を大きく）/ 2レーン相関図

### 出力先

- プロジェクト内の適切な出力ディレクトリ（例: `outputs/drafts/`）、なければスクラッチパッド
- ファイル名は `{slug}.html` 形式（slugは英小文字・数字・ハイフン。後の公開時にそのままURL識別子になる）
- 作成したら SendUserFile（display: render）でユーザーに提示する

## ステップ2: 社内限定URL公開（希望時のみ）

レポート提示後、「社内限定URLでの公開もできます」と案内し、**ユーザーが希望した場合のみ**以下を実行する。

```bash
~/.claude/skills/html-report/scripts/deploy.sh <HTMLファイルパス> <slug> [タイトル]
```

- **slug が公開URLと1対1で対応**する。同じ slug で再実行すると既存デプロイが更新され、**公開URLは変わらない**（配布済みリンクの配り直し不要）。更新のつもりなら必ず同じ slug を使うこと
- タイトル省略時は HTML の `<title>` から自動抽出
- 公開範囲は Apps Script の `webapp.access = DOMAIN`（clasp でログインしたアカウントと同じドメインの Google アカウント限定）。Google側で遮断されるため、閲覧者はリンクを開くだけでよい（OAuth承認画面は出ない）
- 完了時に表示される公開URLをユーザーに伝える。**共有時は「会社アカウントで開いてください」と添える**（マルチアカウントログイン時に `/u/0` で開かれて拒否されるため）
- 既存レポートの slug・URL 一覧は `~/.gas-reports/registry.tsv` にある。「前に公開したやつを更新して」と言われたらここで slug を確認する

### 状態の置き場所

| パス | 内容 |
|---|---|
| `~/.gas-reports/<slug>/` | slugごとの Apps Script プロジェクト（`.clasp.json` / `.deployment` / `src/`） |
| `~/.gas-reports/registry.tsv` | slug → URL の台帳（slug / URL / 最終更新日 / タイトル） |

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| ドメインを取得できないと表示される | `GAS_DOMAIN=example.com` のように公開先ドメインを環境変数で指定して再実行 |
| `clasp が見つかりません` | `cd ~/.claude/skills/html-report && pnpm install` |
| `clasp が未ログインです` / 認証エラー | `cd ~/.claude/skills/html-report && pnpm exec clasp login`（ブラウザで会社アカウント承認。非対話セッションでは実行できないため、ユーザーにターミナルでの実行を依頼する） |
| Deployment ID 自動取得失敗 | 出力中の `AKfyc…` を `~/.gas-reports/<slug>/.deployment` に手動保存して再実行 |
| 閲覧者が「権限がありません」と言われる | 会社アカウント以外で開いている可能性が高い。シークレットウィンドウ or アカウント切替を案内 |
| 閲覧を特定メンバーに絞りたい | `~/.gas-reports/<slug>/src/Code.gs` の `ALLOWED_USERS` にメールアドレスを列挙し、`cd ~/.gas-reports/<slug> && ~/.claude/skills/html-report/node_modules/.bin/clasp push --force && ~/.claude/skills/html-report/node_modules/.bin/clasp update-deployment "$(cat .deployment)"` で反映する。deploy.sh を再実行すると Code.gs がテンプレートで上書きされ絞り込みが消える。閲覧者にOAuth承認画面が出るようになる点にも注意 |
