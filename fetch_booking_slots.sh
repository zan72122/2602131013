#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://api.wakumy.lyd.inc}"
SLUG="${SLUG:-hg10297}"
MEDICAL_DEPARTMENT_ID="${MEDICAL_DEPARTMENT_ID:-39bebe97-8094-4291-9d5f-70bdff003371}"
BOOKING_MENU_ID="${BOOKING_MENU_ID:-c609658c-74df-463c-849f-b9c06a9ec2fe}"
DATE_TZ="${DATE_TZ:-Asia/Tokyo}"
CHECK_DAYS="${CHECK_DAYS:-7}"

OUTPUT_JSON="${OUTPUT_JSON:-0}"
if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_JSON=1
  shift
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
使い方:
  ./fetch_booking_slots.sh [--json] [FROM_DATE [TO_DATE]]

説明:
  指定した日付範囲の予約枠状態を取得して「満席」「予約不可能」「予約可能(空きあり)」を判定します。
  引数なしで実行すると、今日(Asia/Tokyo)からCHECK_DAYS日分を監視します。

環境変数:
  BASE_URL, SLUG, MEDICAL_DEPARTMENT_ID, BOOKING_MENU_ID
  FROM_DATE, TO_DATE, CHECK_DAYS(既定: 7)
  DATE_TZ(既定: Asia/Tokyo)
  OUTPUT_JSON=1 でJSON 1行出力
EOF
  exit 0
fi

if [[ $# -gt 2 ]]; then
  echo "Usage: ./fetch_booking_slots.sh [--json] [FROM_DATE [TO_DATE]]" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v date >/dev/null 2>&1; then
  echo "[ERROR] curl, jq, date are required." >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  FROM_DATE="$1"
  TO_DATE="$1"
elif [[ $# -eq 2 ]]; then
  FROM_DATE="$1"
  TO_DATE="$2"
else
  FROM_DATE="${FROM_DATE:-$(TZ="$DATE_TZ" date +%F)}"
  if ! [[ "$CHECK_DAYS" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] CHECK_DAYS must be positive integer (given: $CHECK_DAYS)" >&2
    exit 1
  fi
  TO_DATE="${TO_DATE:-$(TZ="$DATE_TZ" date -d "$FROM_DATE +$((CHECK_DAYS - 1)) days" +%F)}"
fi

if [[ ! "$FROM_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ ! "$TO_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "[ERROR] FROM_DATE and TO_DATE must be YYYY-MM-DD (given: $FROM_DATE, $TO_DATE)" >&2
  exit 1
fi

if ! date -d "$FROM_DATE" >/dev/null 2>&1 || ! date -d "$TO_DATE" >/dev/null 2>&1; then
  echo "[ERROR] Invalid date value (given: $FROM_DATE, $TO_DATE)" >&2
  exit 1
fi

if (( $(TZ="$DATE_TZ" date -d "$FROM_DATE" +%s) > $(TZ="$DATE_TZ" date -d "$TO_DATE" +%s) )); then
  echo "[ERROR] FROM_DATE must be same or before TO_DATE (given: $FROM_DATE > $TO_DATE)" >&2
  exit 1
fi

API_PATH="${BASE_URL}/dailyBookingTimeFrames/public/${SLUG}/${MEDICAL_DEPARTMENT_ID}/weeklyTimeFramesList"
URL="${API_PATH}?bookingMenuId=${BOOKING_MENU_ID}&from=${FROM_DATE}&to=${TO_DATE}"
REFERER="https://wakumy.lyd.inc/clinic/${SLUG}/booking/select-time-slot?medicalDepartmentId=${MEDICAL_DEPARTMENT_ID}&bookingMenuId=${BOOKING_MENU_ID}"

tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT

http_status="$(curl -sS -w "%{http_code}" -o "$tmp_json" \
  -H 'Accept: application/json' \
  -H "User-Agent: curl/8.6.0" \
  -H "Referer: $REFERER" \
  "$URL")"
raw_response="$(cat "$tmp_json")"

if [[ "$http_status" == "403" ]]; then
  echo "[WARN] first request returned 403, retry with browser-like headers" >&2
  http_status="$(curl -sS -w "%{http_code}" -o "$tmp_json" \
    -H 'Accept: application/json' \
    -H 'Accept-Language: ja,en-US;q=0.9,en;q=0.8' \
    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15' \
    -H 'Referer: https://wakumy.lyd.inc/' \
    -H 'Origin: https://wakumy.lyd.inc' \
    "$URL")"
  raw_response="$(cat "$tmp_json")"
fi

if [[ "$http_status" != 2* ]]; then
  echo "[ERROR] API request failed (HTTP ${http_status})" >&2
  echo "$raw_response" >&2
  exit 1
fi

if [[ -z "$raw_response" ]]; then
  echo "[ERROR] empty response from API" >&2
  exit 1
fi

if ! echo "$raw_response" | jq empty >/dev/null 2>&1; then
  echo "[ERROR] response is not valid JSON" >&2
  echo "$raw_response"
  exit 1
fi

dates=()
current="$FROM_DATE"
while true; do
  dates+=("$current")
  if [[ "$current" == "$TO_DATE" ]]; then
    break
  fi
  next="$(TZ="$DATE_TZ" date -d "$current +1 day" +%F)"
  if [[ -z "$next" ]]; then
    echo "[ERROR] failed to build date range" >&2
    exit 1
  fi
  current="$next"
done

day_summaries=()
for target_date in "${dates[@]}"; do
  day_summary="$(
    jq -c --arg date "$target_date" '
      . as $root
      | ($root.dayInformationList[]? | select(.date == $date)) as $day
      | ($root.timeFrames[$date] // {}) as $frames
      | ($root.timeStrings // []) as $times
      | (reduce $times[] as $t ({full:[], unavailable:[], available:[]};
          .[(if ($frames[$t] == null) then "unavailable"
            elif ($frames[$t].capacityLevel == "full") then "full"
            elif ($frames[$t].capacityLevel == "none") then "unavailable"
            else "available" end
           )] += [$t]
        )
        ) as $slots
      | {
          date: $date,
          wday: ($day.wdayForFront // ""),
          isSaturday: (($day.wdayForFront // "") == "土"),
          isPublicBookableNow: ($day.isPublicBookableNow // false),
          availability: {
            full: ($slots.full | sort),
            unavailable: ($slots.unavailable | sort),
            available: ($slots.available | sort)
          }
        }' "$tmp_json"
  )"
  day_summaries+=("$day_summary")
done

days_json="$(printf '%s\n' "${day_summaries[@]}" | jq -s '.')"
has_saturday_available="$(echo "$days_json" | jq -r '[.[] | select(.isSaturday and (.availability.available | length > 0))] | length > 0')"

result_json="$(jq -nc \
  --arg dateFrom "$FROM_DATE" \
  --arg dateTo "$TO_DATE" \
  --arg fetchedAt "$(TZ="$DATE_TZ" date '+%Y-%m-%d %H:%M:%S %Z')" \
  --arg timezone "$DATE_TZ" \
  --arg endpoint "$URL" \
  --arg hasSaturday "$has_saturday_available" \
  --argjson days "$days_json" \
  '{fetchedAt:$fetchedAt,timeZone:$timezone,fromDate:$dateFrom,toDate:$dateTo,endpoint:$endpoint,hasSaturdayAvailable:($hasSaturday=="true"),days:$days}')"

if [[ "$OUTPUT_JSON" == "1" ]]; then
  echo "$result_json"
  exit 0
fi

echo "[INFO] endpoint: $URL"
echo "[INFO] range: $FROM_DATE 〜 $TO_DATE (timezone: $DATE_TZ)"
echo "$days_json" | jq -r '
  .[] |
  "[RESULT] \(.date) \(.wday // \"\") " +
  "満席(full): " + (.availability.full | join(", ")) + " / " +
  "予約不可能(unavailable): " + (.availability.unavailable | join(", ")) + " / " +
  "予約可能(空きあり): " + (.availability.available | join(", "))
'

if [[ "$has_saturday_available" == "true" ]]; then
  echo "[ALERT] 今回の監視範囲に土曜日の予約可能(空きあり)があります。"
else
  echo "[INFO] 今回の監視範囲の土曜日は空きなし。"
fi
