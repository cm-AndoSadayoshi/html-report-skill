#!/usr/bin/env bash
# HTMLレポートを社内限定の Apps Script ウェブアプリとして公開・更新する。
#
# 使い方:
#   deploy.sh <HTMLファイル> <slug> [タイトル] [--dry-run]
#
#   <HTMLファイル> : 公開したい自己完結HTML（<!DOCTYPE> なしの Artifact 形式でも可）
#   <slug>         : レポート識別子（英小文字・数字・ハイフン）。URL と1対1で対応する。
#                    同じ slug で再実行すると既存デプロイを更新し、公開URLは変わらない。
#   [タイトル]     : ブラウザタブに出すタイトル。省略時は HTML の <title> から抽出。
#   --dry-run      : src/ の同期まで行い、clasp の push/deploy は実行しない（動作確認用）。
#
# 状態の置き場所:
#   ~/.gas-reports/<slug>/        … slug ごとの Apps Script プロジェクト（.clasp.json / .deployment / src/）
#   ~/.gas-reports/registry.tsv   … slug → URL の台帳（slug \t URL \t 最終更新日 \t タイトル）
#
# 環境変数（任意）:
#   GAS_DOMAIN       … 公開URLに入る Google Workspace ドメイン。省略時は clasp のログイン中アカウントから取得
#   GAS_REPORTS_DIR  … 状態の置き場所。省略時は ~/.gas-reports
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${GAS_REPORTS_DIR:-$HOME/.gas-reports}"
GAS_DOMAIN="${GAS_DOMAIN:-}"

usage() { grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | sed -n '2,19p' >&2; exit 1; }

DRY_RUN=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--dry-run" ]; then DRY_RUN=1; else ARGS+=("$a"); fi
done
[ "${#ARGS[@]}" -ge 2 ] || usage

HTML_FILE="${ARGS[0]}"
SLUG="${ARGS[1]}"
TITLE="${ARGS[2]:-}"

[ -f "$HTML_FILE" ] || { echo "HTMLファイルが見つかりません: $HTML_FILE" >&2; exit 1; }
# 後段で cd するため絶対パスに正規化
HTML_FILE="$(cd "$(dirname "$HTML_FILE")" && pwd)/$(basename "$HTML_FILE")"
printf '%s' "$SLUG" | grep -qE '^[a-z0-9][a-z0-9-]*$' || {
  echo "slug は英小文字・数字・ハイフンのみにしてください: $SLUG" >&2; exit 1; }

# タイトル未指定なら HTML の <title> から抽出（先頭8KBのみ走査）
if [ -z "$TITLE" ]; then
  TITLE="$(head -c 8192 "$HTML_FILE" | tr -d '\n' | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p')"
  [ -n "$TITLE" ] || TITLE="$SLUG"
fi

CLASP="$SKILL_DIR/node_modules/.bin/clasp"
if [ "$DRY_RUN" -eq 0 ] && [ ! -x "$CLASP" ]; then
  echo "clasp が見つかりません。次を実行してください: cd $SKILL_DIR && pnpm install" >&2
  exit 1
fi
if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$HOME/.clasprc.json" ]; then
  echo "clasp が未ログインです。次を実行してください（会社アカウントで承認）:" >&2
  echo "  cd $SKILL_DIR && pnpm exec clasp login" >&2
  exit 1
fi

# 公開URLのドメインは、未指定ならログイン中アカウントのメールアドレスから取る
if [ "$DRY_RUN" -eq 0 ] && [ -z "$GAS_DOMAIN" ]; then
  GAS_DOMAIN="$("$CLASP" show-authorized-user 2>/dev/null | grep -oE '@[A-Za-z0-9.-]+\.[A-Za-z]+' | head -1 | tr -d '@' || true)"
  if [ -z "$GAS_DOMAIN" ]; then
    echo "ログイン中アカウントのドメインを取得できませんでした。GAS_DOMAIN=example.com のように指定して再実行してください。" >&2
    exit 1
  fi
fi

PROJ_DIR="$BASE_DIR/$SLUG"
mkdir -p "$PROJ_DIR/src"
cd "$PROJ_DIR"

# ---- 1. HTML を src/index.html に同期 -------------------------------------
# Artifact 形式（<!DOCTYPE> なし）は外側を補う。<base target="_top"> は
# Apps Script が中身を iframe で描画する際にリンクを親フレームで開かせる定番指定。
DEST="$PROJ_DIR/src/index.html"
if head -c 512 "$HTML_FILE" | grep -qi '<!doctype'; then
  cp "$HTML_FILE" "$DEST"
else
  {
    echo '<!DOCTYPE html>'
    echo '<html lang="ja">'
    echo '<base target="_top">'
    cat "$HTML_FILE"
    echo '</html>'
  } > "$DEST"
fi

# ---- 2. Code.gs / appsscript.json をテンプレートから生成 -------------------
cp "$SKILL_DIR/templates/appsscript.json" "$PROJ_DIR/src/appsscript.json"
# タイトル差し込み（sed のメタ文字をエスケープ）
ESCAPED_TITLE="$(printf '%s' "$TITLE" | sed -e 's/[&\\/]/\\&/g')"
sed "s/__REPORT_TITLE__/$ESCAPED_TITLE/" "$SKILL_DIR/templates/Code.gs" > "$PROJ_DIR/src/Code.gs"

echo "同期しました: $HTML_FILE -> $DEST ($(wc -c < "$DEST" | tr -d ' ') バイト)"
echo "タイトル: $TITLE"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--dry-run のためここで終了します（push/deploy は未実行）。"
  exit 0
fi

# ---- 3. Apps Script プロジェクト作成（初回のみ） ---------------------------
if [ ! -f "$PROJ_DIR/.clasp.json" ]; then
  echo "→ Apps Script プロジェクトを新規作成しています: $TITLE"
  # clasp 3.x の --type はコンテナバインド用（docs/sheets 等）のみ。
  # Webアプリは standalone（デフォルト）で作成し、manifest の webapp 設定＋デプロイで実現する。
  "$CLASP" create-script --title "$TITLE" --rootDir ./src
  # create が rootDir に雛形を書いた場合に備え、テンプレートを再適用
  cp "$SKILL_DIR/templates/appsscript.json" "$PROJ_DIR/src/appsscript.json"
  sed "s/__REPORT_TITLE__/$ESCAPED_TITLE/" "$SKILL_DIR/templates/Code.gs" > "$PROJ_DIR/src/Code.gs"
fi

# ---- 4. push & デプロイ（既存デプロイ更新で URL 固定） ---------------------
echo "→ Apps Script に push しています..."
"$CLASP" push --force

if [ -f "$PROJ_DIR/.deployment" ]; then
  DEPLOYMENT_ID="$(tr -d '[:space:]' < "$PROJ_DIR/.deployment")"
  echo "→ 既存デプロイを更新しています（URL は変わりません）: $DEPLOYMENT_ID"
  "$CLASP" update-deployment "$DEPLOYMENT_ID" --description "$(date '+%Y-%m-%d') 更新"
else
  echo "→ 初回デプロイを作成しています..."
  OUT="$("$CLASP" create-deployment --description "$TITLE" 2>&1)"
  echo "$OUT"
  DEPLOYMENT_ID="$(printf '%s' "$OUT" | grep -oE 'AKfyc[A-Za-z0-9_-]+' | head -1 || true)"
  if [ -n "$DEPLOYMENT_ID" ]; then
    printf '%s\n' "$DEPLOYMENT_ID" > "$PROJ_DIR/.deployment"
  else
    echo "Deployment ID を自動で取得できませんでした。上の出力から AKfyc… の ID を控えて" >&2
    echo "  echo '<Deployment ID>' > $PROJ_DIR/.deployment" >&2
    echo "を実行してください。" >&2
    exit 1
  fi
fi

URL="https://script.google.com/a/macros/$GAS_DOMAIN/s/$DEPLOYMENT_ID/exec"

# ---- 5. 台帳更新 -----------------------------------------------------------
REGISTRY="$BASE_DIR/registry.tsv"
touch "$REGISTRY"
TMP="$(mktemp)"
grep -v "^$SLUG	" "$REGISTRY" > "$TMP" || true
printf '%s\t%s\t%s\t%s\n' "$SLUG" "$URL" "$(date '+%Y-%m-%d')" "$TITLE" >> "$TMP"
mv "$TMP" "$REGISTRY"

echo ""
echo "完了しました。"
echo "公開 URL: $URL"
echo "（社内 Google アカウント限定。共有時は「会社アカウントで開いてください」と添える）"
