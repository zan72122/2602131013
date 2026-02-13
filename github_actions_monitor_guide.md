# GitHub Actions + Gmailメール通知（非エンジニア向け）

目的は「**06:00〜21:00の間、5分ごと**」に監視し、**土曜の空きあり**を見つけたらすぐ通知することです。

## 1) 事前準備
- GitHubにこのフォルダの内容をコミットして、任意のリポジトリへpush
- 予約APIの情報はスクリプト内の初期値で固定済み
  - `SLUG`: `hg10297`
  - `MEDICAL_DEPARTMENT_ID`: `39bebe97-8094-4291-9d5f-70bdff003371`
  - `BOOKING_MENU_ID`: `c609658c-74df-463c-849f-b9c06a9ec2fe`

## 2) Gmail側の準備
1. Gmail利用アカウントを用意
2. 2段階認証を有効化（推奨）
3. アプリ パスワードを作成
   - Googleアカウント → セキュリティ → 2段階認証 → アプリ パスワード
4. 受信できるメールアドレス（iPhoneに入るアドレス）を決める

## 3) GitHub の Secrets 設定
GitHubリポジトリの `Settings > Secrets and variables > Actions` に、下記を登録してください。

| Secret名 | 内容 |
|---|---|
| `MAIL_USERNAME` | Gmailのメールアドレス |
| `MAIL_PASSWORD` | 作成したGmailアプリパスワード |
| `MAIL_TO` | 通知を受けるメールアドレス（iPhoneで開封可能なもの） |
| `MAIL_FROM` | 送信元として表示したいメールアドレス |

## 4) ワークフローファイル
このリポジトリの `.github/workflows/mihara-booking-saturday-watch.yml` をそのまま使います。

### 設定ポイント
- 実行時刻
  - `*/5 21-23,0-12 * * *`
  - GitHub ActionsはUTCなので、**JST 06:00〜21:00**対応
- 実行範囲
  - `CHECK_DAYS: 7`（今日〜土日含む1週間）
- 通知条件
  - スクリプト出力の `hasSaturdayAvailable: true` のときだけメール送信

## 5) 手動テスト（初心者向け）
1. GitHubページで当該ワークフローを開く
2. `Run workflow` を押して実行
3. 完了後、ログにエラーが出ていないか確認
4. `actions/runs` で履歴を確認

## 6) iPhoneでの通知確認
- iPhoneのメールアプリ（またはPush通知設定）で通知を有効化
- 指定アドレス（`MAIL_TO`）を受信可にする
- 既読前提ではなく「常に通知」を許可すると取りこぼしにくい

## 7) もし通知が来ない場合
- `MAIL_PASSWORD` が誤り（アプリパスワード期限切れ含む）
- 「送信元」と「Gmailアプリパスワード」の整合
- スパム/迷惑メールフォルダ確認
- ワークフローの履歴で `has_saturday=true` が出ているか確認

## 8) 補足
- `workflow_dispatch` があるので、PCを起動し続ける必要はありません
- 6:00〜21:00のみ実行するため、要求どおり「Mac常駐監視」を使いません
