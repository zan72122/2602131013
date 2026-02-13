# GitHub CLI (gh) で最短セットアップ

`HTTP 404: workflow ... not found` の原因は、対象ワークフローが
**GitHub上のデフォルトブランチに未反映** か、**別ブランチにしかない** ためです。

- ここでの前提: ローカルで `fetch_booking_slots.sh` と `mihara-booking-saturday-watch.yml` は用意済み
- あなたはほぼ `gh` 実行だけで完了できる状態です

## 1) まず gh を確認
```bash
gh --version
```

## 2) 1回だけ認証
```bash
gh auth login --hostname github.com --web --scopes repo
```

## 3) workflow が GitHub にあるか先に確認
```bash
export GH_REPO="OWNER/REPO"

echo "== default branch =="
gh repo view "$GH_REPO" --json defaultBranchRef -q '.defaultBranchRef.name'

echo "== workflows =="
gh workflow list --repo "$GH_REPO"
```

## 4) workflow が見えない場合（最短修正版）
ローカルのファイルをリポジトリへ反映してから実行します。

```bash
export GH_REPO="OWNER/REPO"
export MAIL_USERNAME="your@gmail.com"
export MAIL_PASSWORD="your-app-password"
export MAIL_TO="iphone-notify@example.com"
export MAIL_FROM="your@gmail.com"
export WORKFLOW_LOCAL="/Users/b_hk/Documents/Unclassified/2026/260213_11_reserve/.github/workflows/mihara-booking-saturday-watch.yml"

cat >/tmp/setup_mihara_watch.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?required: OWNER/REPO}"
: "${MAIL_USERNAME:?required}"
: "${MAIL_PASSWORD:?required}"
: "${MAIL_TO:?required}"
: "${MAIL_FROM:?required}"
: "${WORKFLOW_LOCAL:?required}"

if [[ ! -f "$WORKFLOW_LOCAL" ]]; then
  echo "[ERROR] local workflow not found: $WORKFLOW_LOCAL" >&2
  exit 1
fi

echo "[1] set secrets"
for KEY in MAIL_USERNAME MAIL_PASSWORD MAIL_TO MAIL_FROM; do
  gh secret set "$KEY" --repo "$GH_REPO" --body "${!KEY}"
done

DEFAULT_BRANCH="$(gh repo view "$GH_REPO" --json defaultBranchRef -q '.defaultBranchRef.name')"
TMPDIR="$(mktemp -d)"
TMP_REPO="$TMPDIR/repo"
git clone "https://github.com/${GH_REPO}.git" "$TMP_REPO"
mkdir -p "$TMP_REPO/.github/workflows"
cp "$WORKFLOW_LOCAL" "$TMP_REPO/.github/workflows/mihara-booking-saturday-watch.yml"

cd "$TMP_REPO"
if [[ -n "$(git status --short)" ]]; then
  git add .github/workflows/mihara-booking-saturday-watch.yml
  git commit -m "chore: add mihara booking workflow"
  git push origin "$DEFAULT_BRANCH"
else
  echo "[INFO] workflow already exists and unchanged"
fi

echo "[2] dispatch workflow"
gh workflow run mihara-booking-saturday-watch --repo "$GH_REPO" --ref "$DEFAULT_BRANCH"
RUN_ID="$(gh run list --repo "$GH_REPO" --workflow mihara-booking-saturday-watch --limit 1 --json databaseId -q '.[0].databaseId')"
echo "[3] run id: $RUN_ID"
gh run view "$RUN_ID" --repo "$GH_REPO" --log
EOF

chmod +x /tmp/setup_mihara_watch.sh
WORKFLOW_LOCAL="$WORKFLOW_LOCAL" bash /tmp/setup_mihara_watch.sh
```

## 5) workflow が既に見えている場合（既にpush済み）
```bash
export GH_REPO="OWNER/REPO"
export MAIL_USERNAME="your@gmail.com"
export MAIL_PASSWORD="your-app-password"
export MAIL_TO="iphone-notify@example.com"
export MAIL_FROM="your@gmail.com"

for KEY in MAIL_USERNAME MAIL_PASSWORD MAIL_TO MAIL_FROM; do
  gh secret set "$KEY" --repo "$GH_REPO" --body "${!KEY}"
done

gh workflow run mihara-booking-saturday-watch --repo "$GH_REPO"
```

## 6) 直近ログを確認
```bash
gh run list --repo "$GH_REPO" --workflow mihara-booking-saturday-watch --limit 3
RUN_ID="$(gh run list --repo "$GH_REPO" --workflow mihara-booking-saturday-watch --limit 1 --json databaseId -q '.[0].databaseId')"
gh run view "$RUN_ID" --repo "$GH_REPO" --log
```

## 補足
- 404エラーは「ワークフローがデフォルトブランチに存在しない」ことが主因です。
- `--workflow mihara-booking-saturday-watch` でも、`.yml` でも、`gh` は対象ファイルがデフォルトブランチにないと実行できません。
- `--ref` は `workflow` があるブランチを指定できますが、最終的にはデフォルト側に入っているのが安全です。
