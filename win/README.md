# noteアカウントスイッチャー（Windows版）

アカウントごとに独立したGoogle Chromeのデータ領域を作り、noteをワンクリックで開くWindows用ランチャーです。

## 動作環境

- Windows 10 / 11
- Google Chrome
- Windows PowerShell 5.1（Windows標準搭載）

追加インストールやビルドは不要です。

## 使い方

1. `noteアカウントスイッチャー.exe` をダブルクリックします。
2. 「追加」から識別名と色を登録します。
3. 「開く」を押し、専用Chromeでnoteへログインします。
4. 次回以降は「開く」だけで、そのアカウントのログイン状態を引き継ぎます。

パスワードを本ツール内に保存することはありません。ChromeのCookieなどは次のフォルダにアカウント別で保存されます。

`%LOCALAPPDATA%\NoteAccountSwitcher\Profiles\`

## 削除について

アカウントの「…」メニューから削除を選ぶと、次のいずれかを選択できます。

- 「はい」：一覧と専用Chrome領域（ログイン情報）を削除
- 「いいえ」：一覧からのみ削除し、専用Chrome領域は残す
- 「キャンセル」：削除しない

本ツールのファイルを削除しただけでは、保存済みのChromeデータは削除されません。

## ファイル構成

- `noteアカウントスイッチャー.exe`：アプリ本体です。通常はこちらを起動します。
- `NoteAccountSwitcher.cs`：Windows版のソースコードです。
- `build.ps1`：EXEを再ビルドするためのスクリプトです。
- `NoteAccountSwitcher.ps1` / `noteアカウントスイッチャー.vbs`：旧PowerShell版です。
