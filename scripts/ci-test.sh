#!/bin/bash
# iPhone 시뮬레이터에서 UI 테스트를 돌리고, 결과와 실패 원인을 로그 끝에 요약한다.
set -uo pipefail
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
data=json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    if 'iOS' not in runtime: continue
    for d in data[runtime]:
        if d['name'].startswith('iPhone'):
            print(d['udid']); sys.exit()
")
echo "UI 테스트 기기: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

rm -rf TestResults.xcresult
xcodebuild test -project Paws.xcodeproj -scheme Paws \
  -destination "id=$UDID" \
  CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath TestResults.xcresult > test.log 2>&1
STATUS=$?

echo "===== 컴파일 오류 ====="
grep -E "error:" test.log | grep -v "XCTAssert\|failed -" | sort -u | head -40
echo "===== 실패한 단언 ====="
grep -E "error: -\[|: error: .*XCT|XCTAssert|Failed|failed \(" test.log | sort -u | head -60
echo "===== 실패 시 UI 트리 ====="
awk '/===== UI 트리/{on=1; n=0} on{print; n++} n>150{on=0}' test.log | head -600
echo "===== 테스트 결과 ====="
grep -E "Test Case .*(passed|failed)" test.log | sed -E "s/^Test Case '-\[PawsUITests\.PawsUITests //; s/\]'//"
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*|Executed [0-9]+ test" test.log | tail -3
exit $STATUS
