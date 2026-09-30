#!/bin/bash
# UI 테스트: iPhone에서 전체, iPad(가로)에서 화면 캡처 테스트를 돌린다.
# 결과 요약과 스크린샷(base64)은 로그 끝에 모아 찍는다.
set -uo pipefail

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

run_tests() {
  local family="$1" log="$2"; shift 2
  local udid
  udid=$(pick_device "$family")
  echo "UI 테스트 기기 ($family): $udid"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcodebuild test -project Paws.xcodeproj -scheme Paws \
    -destination "id=$udid" \
    CODE_SIGNING_ALLOWED=NO "$@" > "$log" 2>&1
  local status=$?
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  return $status
}

run_tests iPhone test.log
STATUS=$?
run_tests iPad test-ipad.log -only-testing:PawsUITests/ScreenshotTests
IPAD_STATUS=$?

summary() {
  local log="$1"
  echo "===== 컴파일 오류 ($log) ====="
  grep -E "error:" "$log" | grep -v "XCTAssert\|failed -" | sort -u | head -40
  echo "===== 실패한 단언 ($log) ====="
  grep -E "error: -\[|: error: .*XCT|XCTAssert|Failed|failed \(" "$log" | sort -u | head -60
  echo "===== 실패 시 UI 트리 ($log) ====="
  awk '/===== UI 트리/{on=1; n=0} on{print; n++} n>150{on=0}' "$log" | head -600
}

echo "===== 스크린샷 ====="
awk '/^SCREENSHOT-BEGIN/{on=1} on{print} /^SCREENSHOT-END/{on=0}' test.log test-ipad.log
summary test.log
summary test-ipad.log
echo "===== 테스트 결과 ====="
grep -hE "Test Case .*(passed|failed)" test.log test-ipad.log | sed -E "s/^Test Case '-\[PawsUITests\.//; s/\]'//"
grep -hE "\*\* TEST (SUCCEEDED|FAILED) \*\*|Executed [0-9]+ test" test.log test-ipad.log | tail -4
[ $STATUS -eq 0 ] && [ $IPAD_STATUS -eq 0 ]
