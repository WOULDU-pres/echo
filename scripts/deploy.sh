#!/usr/bin/env bash
# Echo 빌드 + ~/Applications/Echo.app 재배포.
# 바탕화면 바로가기(~/Desktop/Echo.app → ~/Applications/Echo.app)가 가리키는 위치에
# 새 빌드를 설치한다. 코드 수정 후 이 스크립트를 돌리면 바로가기로 바로 새 버전이 뜬다.
#
# 사용: ./scripts/deploy.sh   (프로젝트 루트 어디서든)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC="$ROOT/build/Build/Products/Debug/Echo.app"
DST="$HOME/Applications/Echo.app"

echo "▶ 빌드…"
xcodebuild -scheme Echo -derivedDataPath build -configuration Debug build \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

[ -d "$SRC" ] || { echo "✗ 빌드 산출물 없음: $SRC"; exit 1; }

# 교체 안전: 실행 중이면 종료
osascript -e 'tell application "Echo" to quit' >/dev/null 2>&1 || true
pkill -x Echo 2>/dev/null || true
sleep 1

mkdir -p "$HOME/Applications"
if [ -d "$DST" ]; then
  TS=$(date +%Y%m%d_%H%M%S)
  mv "$DST" "$HOME/Applications/Echo.app.bak_$TS"
  echo "▶ 기존 앱 백업: Echo.app.bak_$TS"
fi

ditto "$SRC" "$DST"   # 번들·ad-hoc 코드서명 보존
echo "✓ 설치: $DST  ($(stat -f '%Sm' "$DST/Contents/MacOS/Echo"))"

# 백업은 최근 3개만 유지(이름의 타임스탬프 기준 — mv가 mtime을 보존하므로 이름순이 정확).
ls -d "$HOME"/Applications/Echo.app.bak_* 2>/dev/null | sort -r | tail -n +4 | while read -r old; do
  rm -rf "$old" && echo "  - 오래된 백업 정리: $(basename "$old")"
done

echo "✓ 완료 — 바탕화면 Echo 바로가기를 누르면 새 버전이 뜹니다."
