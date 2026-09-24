/**
 * HTMLレポートを社内限定で配信するウェブアプリ（html-report スキルが自動生成）。
 *
 * アクセス制御は二段構え:
 *   1. appsscript.json の webapp.access = DOMAIN
 *      → 自ドメインの Google アカウント以外はそもそも到達できない（Google 側で遮断）
 *   2. 下の ALLOWED_USERS
 *      → 空配列なら「ドメイン内の全員」、メールアドレスを列挙すればその人だけに絞る
 *
 * ALLOWED_USERS を埋めると Session.getActiveUser() を呼ぶことになり、
 * userinfo.email スコープが要求される。すると閲覧者に OAuth の承認画面
 * （未検証アプリの警告つき）が出るようになる。空のあいだは Session に
 * 一切触れないので、閲覧者はリンクを開くだけで見られる。
 */

// 空配列 = ドメイン内の全員に公開。絞る場合はメールアドレスを列挙する。
const ALLOWED_USERS = [];

function doGet() {
  if (!isAllowed_()) {
    return HtmlService.createHtmlOutput(
      '<meta charset="utf-8">' +
      '<p style="font-family:system-ui,-apple-system,sans-serif;padding:24px;line-height:1.7">' +
      'このページの閲覧権限がありません。</p>'
    ).setTitle('アクセス権限がありません');
  }

  return HtmlService.createHtmlOutputFromFile('index')
    .setTitle('__REPORT_TITLE__')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function isAllowed_() {
  // 絞り込みなしのときは Session を参照しない。参照すると閲覧者全員に
  // OAuth 承認画面が出てしまうため。
  if (ALLOWED_USERS.length === 0) return true;
  return ALLOWED_USERS.indexOf(Session.getActiveUser().getEmail()) !== -1;
}
