#!/bin/bash
# 시뮬레이터에서 앱을 데모 데이터로 실행하고, 크래시 여부와 스크린샷을 남긴다.
# 스크린샷은 작게 줄여 base64로 로그에도 찍는다 (로그만 읽을 수 있는 환경에서 확인용).
set -uo pipefail
APP="$1"
BUNDLE_ID=com.gomyong.paws
mkdir -p screenshots
FAILED=0
SUMMARY=()

pick_device() {
  xcrun simctl list devices available -j | python3 -c "
import json,sys
data=json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    if 'iOS' not in runtime: continue
    for d in data[runtime]:
        if d['name'].startswith('$1'):
            print(d['udid']); sys.exit()
"
}

run_on() {
  local family="$1"; shift
  local udid
  udid=$(pick_device "$family")
  if [ -z "$udid" ]; then echo "::warning::$family 시뮬레이터 없음"; return; fi
  echo "===== $family ($udid) ====="
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$APP"
  for scenario in "$@"; do
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$udid" "$BUNDLE_ID" --demo "--demo-open=$scenario" >/dev/null
    sleep 8
    if ! xcrun simctl spawn "$udid" launchctl list | grep -q "$BUNDLE_ID"; then
      echo "::error::$family / $scenario: 앱이 종료됨 (크래시 의심)"
      SUMMARY+=("❌ $family / $scenario 크래시")
      FAILED=1
      ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i paws | head -1 | while read f; do
        echo "----- crash report: $f -----"; head -120 ~/Library/Logs/DiagnosticReports/"$f"
      done
      continue
    fi
    local shot="screenshots/${family// /_}-$scenario.png"
    xcrun simctl io "$udid" screenshot "$shot" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 45 -Z 520 "$shot" --out "$shot.small.jpg" >/dev/null
    echo "SCREENSHOT-BEGIN $shot"
    base64 -i "$shot.small.jpg" | tr -d '\n'; echo
    echo "SCREENSHOT-END $shot"
    SUMMARY+=("✅ $family / $scenario 실행 중 (스크린샷 $(stat -f%z "$shot.small.jpg") bytes)")
  done
  xcrun simctl spawn "$udid" log show --last 3m --predicate "process == \"Paws\" AND messageType == fault" --style compact 2>/dev/null | tail -30
  xcrun simctl shutdown "$udid" || true
}

run_on "iPhone" home trip stop map reading
run_on "iPad" trip stop

# 로그 끝에서 바로 읽을 수 있도록 요약을 마지막에 찍는다
echo "===== 빌드 경고 (Paws 소스) ====="
grep -E "warning:" build.log 2>/dev/null | grep "/Paws/" | sed -E 's#.*/Paws/Paws/#Paws/#' | sort -u | head -60
echo "===== 실행 요약 ====="
printf '%s\n' "${SUMMARY[@]}"
exit $FAILED
