#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# Common Utilities
# 공통 유틸리티 함수 및 상수 정의
# ═══════════════════════════════════════════════════

# ─────────────────────────────────────────────────────
# VERSION 정보 (소스 직접 실행시 사용, 빌드시 자동 주입됨)
# ─────────────────────────────────────────────────────
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
VERSION="$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || echo "dev")"
RELEASE_DATE="$(date +%Y-%m-%d)"
#@@BUILD_EXCLUDE_END

# ─────────────────────────────────────────────────────
# 색상 및 스타일 정의
# ─────────────────────────────────────────────────────
RED='\033[1;31m'     # 빨간색
GREEN='\033[1;32m'   # 초록색
YELLOW='\033[1;33m'  # 노란색
BLUE='\033[1;34m'    # 파란색
# shellcheck disable=SC2034  # Used in other modules after build
PURPLE='\033[1;35m'  # 보라색
CYAN='\033[1;36m'    # 볼드와 옥색
BOLD='\033[1m'       # 볼드
# shellcheck disable=SC2034  # Used in other modules after build
DIM='\033[2m'        # 흐리게
NC='\033[0m'         # 색상 없음

# shellcheck disable=SC2034  # Used in other modules after build
BARROW="${BLUE}==>${NC}"
# shellcheck disable=SC2034  # Used in other modules after build
GARROW="${GREEN}==>${NC}"
ERROR="${RED}==>${NC} ${BOLD}Error:${NC}"

#@@BUILD_EXCLUDE_START
# ─────────────────────────────────────────────────────
# 디버그 로그 시스템
# ─────────────────────────────────────────────────────

# 디버그 로그 설정
# SCRIPT_DIR이 설정되어 있으면 프로젝트 루트를 찾고, 없으면 현재 디렉토리 사용
if [ -n "$SCRIPT_DIR" ]; then
  # build/ak 실행시: SCRIPT_DIR = .../build
  # src/ak 실행시: SCRIPT_DIR = .../src
  DEBUG_LOG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/build"
else
  DEBUG_LOG_DIR="$(pwd)/build"
fi
DEBUG_LOG_FILE="${DEBUG_LOG_DIR}/debug.log"

# 디버그 로그 함수
debug_log() {
  if [ "${AK_DEBUG:-0}" = "1" ]; then
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local caller_info="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    echo "[$timestamp] [$caller_info] $*" >> "$DEBUG_LOG_FILE"
  fi
}

# 디버그 초기화 (첫 실행시 로그 파일 초기화)
debug_init() {
  if [ "${AK_DEBUG:-0}" = "1" ]; then
    mkdir -p "$DEBUG_LOG_DIR"
    echo "=== Debug Log Started at $(date) ===" > "$DEBUG_LOG_FILE"
    echo "AK_DEBUG=${AK_DEBUG}" >> "$DEBUG_LOG_FILE"
    echo "SCRIPT_DIR=${SCRIPT_DIR}" >> "$DEBUG_LOG_FILE"
    echo "DEBUG_LOG_DIR=${DEBUG_LOG_DIR}" >> "$DEBUG_LOG_FILE"
    echo "DEBUG_LOG_FILE=${DEBUG_LOG_FILE}" >> "$DEBUG_LOG_FILE"
    echo "" >> "$DEBUG_LOG_FILE"
  fi
}
#@@BUILD_EXCLUDE_END

# ─────────────────────────────────────────────────────
# 버전 정보 출력
# ─────────────────────────────────────────────────────
show_version() {
  local script_name
  script_name=$(basename "$0")
  local adb_version
  adb_version=$(adb version 2>/dev/null | head -n 1 | awk '{print $5}' || echo "Not found")
  
  echo
  echo -e "                                        ${BOLD}${script_name}${NC} ${GREEN}${VERSION}${NC} - Released on ${RELEASE_DATE}"
  echo -e "        ${GREEN}::${NC}                   ${GREEN}.::${NC}        ------------------------------------"
  echo -e "       ${GREEN}:#*+.${NC}                ${GREEN}:+*#.${NC}       ${BOLD}${YELLOW}ADB Version:${NC} ${adb_version}"
  echo -e "        ${GREEN}:**+:${NC}    ${GREEN}......${NC}    ${GREEN}-+**.${NC}        ${BOLD}${YELLOW}Author:${NC} Claude Hwang"
  echo -e "         ${GREEN}.*+=---::::::::---+*+${NC}          ${BOLD}${YELLOW}License:${NC} MIT"
  echo -e "        ${YELLOW}:-=----:--------:---==-.${NC}        ${BOLD}${YELLOW}Language:${NC} Bash"
  echo -e "      ${YELLOW}:++=---==============---=+=.${NC}      ${BOLD}${YELLOW}Supported OS:${NC} macOS, Linux"
  echo -e "    ${RED}.+*+=+*%#++++++++++++++##+=+**-${NC}     ${BOLD}${YELLOW}Dependencies:${NC} adb, aapt, apksigner"
  echo -e "   ${RED}.****+%@@%+++++++++++++*@@@#+**#+${NC}    ${BOLD}${YELLOW}Repository:${NC} https://github.com/luminousvault/homebrew-adb-extensions"
  echo -e "   ${CYAN}*#*****#*+++++++++++++++*##*****#=${NC}   "
  echo -e "  ${BLUE}-%#*****++++++++++++++++++++****##%.${NC}  ${BOLD}${YELLOW}Purpose:${NC} ADB extensions kit - Essential ADB utilities"
  echo -e "                                        ${BOLD}${YELLOW}Features:${NC} APK install, Device management, App control"
  echo
}

# ─────────────────────────────────────────────────────
# 패키지 관리 유틸리티
# ─────────────────────────────────────────────────────

# 현재 포그라운드 앱의 패키지명을 ADB를 통해 추출
# 인자: [device_id] - 선택적. 지정하지 않으면 G_SELECTED_DEVICE 사용
detect_foreground_package() {
    local target_device="${1:-$G_SELECTED_DEVICE}"
    adb -s "$target_device" shell dumpsys activity activities | grep -i Hist | head -n 1 | sed -n 's/.* u0 \([^\/ ]*\)\/.*/\1/p'
}

# 패키지 이름 형식이 유효한지 확인
validate_package_name() {
    local pkg="$1"
    [[ "$pkg" =~ ^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$ ]]
}

# 패키지 설치 여부 확인
is_package_installed() {
    local package_name="$1"
    adb -s "$G_SELECTED_DEVICE" shell pm list packages --user 0 | grep -q "^package:$package_name$"
    return $?
}

# 패키지명 형식과 설치 여부를 확인하고 실패 시 종료
validate_package_or_exit() {
    local package_name="$1"
    if ! validate_package_name "$package_name"; then
        echo -e "${RED}ERROR: Invalid package name format:${NC} $package_name"
        echo
        exit 1
    fi
    if ! is_package_installed "$package_name"; then
        echo -e "${RED}ERROR: Package not installed on the device:${NC} $package_name"
        echo
        exit 1
    fi
}

# 지정한 패키지의 APK 경로를 디바이스에서 추출하여 반환합니다. 실패 시 1을 반환
# 인자: package_name [device_id]
#   - package_name: 패키지명 (필수)
#   - device_id: 대상 디바이스 ID (선택, 기본값: $G_SELECTED_DEVICE)
get_apk_path_for_package() {
    local package_name=$1
    local target_device="${2:-$G_SELECTED_DEVICE}"
    local apk_paths apk_path
    
    # pm path로 모든 APK 경로 가져오기
    apk_paths=$(adb -s "$target_device" shell pm path "$package_name" 2>/dev/null)
    
    # 패키지가 존재하지 않으면 빈 출력
    if [ -z "$apk_paths" ]; then
        echo -e "${RED}ERROR: Package not found:${NC} $package_name"
        echo
        return 1
    fi
    
    # base.apk 우선 선택 (Split APK 대응)
    apk_path=$(echo "$apk_paths" | grep "base\.apk" | head -n 1)
    
    # base.apk가 없으면 첫 번째 APK 선택 (시스템 앱 대응)
    if [ -z "$apk_path" ]; then
        apk_path=$(echo "$apk_paths" | head -n 1)
    fi
    
    # "package:" 접두사 제거 및 공백/캐리지 리턴 제거
    apk_path=$(echo "$apk_path" | cut -d':' -f2 | tr -d '\r\n')
    
    echo "$apk_path"
}

# ─────────────────────────────────────────────────────
# ADB 필수 체크
# ─────────────────────────────────────────────────────

# ADB 사용 가능 여부 확인
check_adb_available() {
  if ! command -v adb >/dev/null 2>&1; then
    echo
    echo -e "${ERROR} ADB is not installed."
    echo
    echo -e "${YELLOW}Installation:${NC}"
    echo -e "  ${BOLD}macOS:${NC}   brew install android-platform-tools"
    echo -e "  ${BOLD}Ubuntu:${NC}  sudo apt install adb"
    echo -e "  ${BOLD}Manual:${NC}  https://developer.android.com/studio/releases/platform-tools"
    echo
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────
# Android SDK 도구 탐지
# ─────────────────────────────────────────────────────

# Android SDK 홈 디렉토리 탐지 (3단계 폴백)
detect_android_home() {
  # 1순위: 환경변수
  if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/build-tools" ]; then
    echo "$ANDROID_HOME"
    return 0
  fi
  
  local sdk_root=""
  
  # 2순위: which adb로 유추
  # 주의: brew install android-platform-tools로 ADB만 설치된 경우
  # (예: /opt/homebrew/bin/adb)는 build-tools가 없으므로 SDK root로 인정하지 않음
  # 이 경우 aapt/apksigner 기능을 사용할 수 없음
  local adb_path
  adb_path=$(which adb 2>/dev/null)
  if [ -n "$adb_path" ]; then
    # realpath로 심볼릭 링크 추적
    if command -v realpath >/dev/null 2>&1; then
      adb_path=$(realpath "$adb_path")
    fi
    
    # adb가 platform-tools 디렉토리에 있는 경우만 SDK root로 추론
    # (예: $ANDROID_HOME/platform-tools/adb 형태)
    local parent_dir
    parent_dir=$(dirname "$adb_path")
    if [[ "$(basename "$parent_dir")" == "platform-tools" ]]; then
      local candidate
      candidate=$(dirname "$parent_dir")
      # build-tools가 실제로 존재하고 비어있지 않은지 확인
      if [ -d "$candidate/build-tools" ] && [ -n "$(ls -A "$candidate/build-tools" 2>/dev/null)" ]; then
        sdk_root="$candidate"
      fi
    fi
  fi
  
  # 3순위: 일반적인 설치 경로
  if [ -z "$sdk_root" ]; then
    local common_paths=(
      "$HOME/Library/Android/sdk"        # macOS 기본
      "$HOME/Android/Sdk"                # Linux 기본
      "/usr/local/share/android-sdk"     # Homebrew
    )
    for path in "${common_paths[@]}"; do
      if [ -d "$path/build-tools" ] && [ -n "$(ls -A "$path/build-tools" 2>/dev/null)" ]; then
        sdk_root="$path"
        break
      fi
    done
  fi
  
  # SDK를 찾았으면 현재 세션에 ANDROID_HOME 설정 (다음 호출 시 1순위에서 바로 찾음)
  if [ -n "$sdk_root" ]; then
    export ANDROID_HOME="$sdk_root"
    echo "$sdk_root"
    return 0
  fi
  
  return 1
}

# Android SDK 도구 찾기 (최신 버전 선택)
find_android_tool() {
  local tool_name=$1
  
  # 먼저 PATH에서 찾기 (시스템에 직접 설치된 경우)
  if command -v "$tool_name" >/dev/null 2>&1; then
    echo "$tool_name"
    return 0
  fi
  
  # Android SDK 찾기
  local android_home
  android_home=$(detect_android_home)
  if [ -z "$android_home" ]; then
    return 1
  fi
  
  local build_tools_dir="$android_home/build-tools"
  if [ ! -d "$build_tools_dir" ] || [ -z "$(ls -A "$build_tools_dir" 2>/dev/null)" ]; then
    return 1
  fi
  
  # 최신 버전 찾기 (버전 정렬)
  local latest_version
  latest_version=$(ls -1 "$build_tools_dir" | sort -V | tail -n1)
  if [ -z "$latest_version" ]; then
    return 1
  fi
  
  local tool_path="$build_tools_dir/$latest_version/$tool_name"
  if [ -x "$tool_path" ]; then
    echo "$tool_path"
    return 0
  fi
  
  return 1
}

# aapt 도구 찾기
find_aapt() {
  find_android_tool "aapt"
}

# apksigner 도구 찾기
find_apksigner() {
  find_android_tool "apksigner"
}

# ─────────────────────────────────────────────────────
# 배열 유틸리티
# ─────────────────────────────────────────────────────

# 목록에서 중복 확인
contains() {
    local value="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" == "$value" ]; then
            return 0
        fi
    done
    return 1
}

# ─────────────────────────────────────────────────────
# APK 파일 관리
# ─────────────────────────────────────────────────────

# 지정한 디렉토리에서 APK 파일 목록을 가져옵니다.
# 결과는 전역 배열 APK_LIST에 저장됩니다.
#
# 사용법: get_apk_list [directory_path] [sort_option]
#
# 인자:
#   directory_path - APK 파일을 검색할 디렉토리 (기본값: ".")
#   sort_option    - 정렬 방식 (기본값: "name")
#                    - "name" 또는 빈 값: 이름순 정방향 (A-Z)
#                    - "name-reverse": 이름순 역방향 (Z-A)
#                    - "time-newest": 시간순 최신순
#                    - "time-oldest": 시간순 오래된순
#
# 반환:
#   APK_LIST - 전역 배열에 APK 파일 경로 목록 저장
#   반환값 0: 성공, 1: APK 파일 없음
#
# 예시:
#   get_apk_list "." "name"
#   get_apk_list "/path/to/dir" "time-newest"
#
get_apk_list() {
    local dir_path="${1:-.}"
    local sort_option="${2:-name}"
    
    # 전역 배열 초기화
    APK_LIST=()
    
    # 디렉토리 존재 확인
    if [ ! -d "$dir_path" ]; then
        return 1
    fi
    
    # 정렬 방식에 따라 find 명령 구성
    case "$sort_option" in
        "name"|"")
            # 이름순 정방향 (기본)
            while IFS= read -r -d '' file; do
                APK_LIST+=("$file")
            done < <(find "$dir_path" -maxdepth 1 -type f -name "*.apk" -print0 | sort -z)
            ;;
        "name-reverse")
            # 이름순 역방향
            while IFS= read -r -d '' file; do
                APK_LIST+=("$file")
            done < <(find "$dir_path" -maxdepth 1 -type f -name "*.apk" -print0 | sort -zr)
            ;;
        "time-newest")
            # 시간순 최신순
            while IFS= read -r -d '' file; do
                APK_LIST+=("$file")
            done < <(find "$dir_path" -maxdepth 1 -type f -name "*.apk" -print0 | xargs -0 ls -t 2>/dev/null | tr '\n' '\0')
            ;;
        "time-oldest")
            # 시간순 오래된순
            while IFS= read -r -d '' file; do
                APK_LIST+=("$file")
            done < <(find "$dir_path" -maxdepth 1 -type f -name "*.apk" -print0 | xargs -0 ls -tr 2>/dev/null | tr '\n' '\0')
            ;;
        *)
            # 알 수 없는 정렬 옵션 - 기본값 사용
            while IFS= read -r -d '' file; do
                APK_LIST+=("$file")
            done < <(find "$dir_path" -maxdepth 1 -type f -name "*.apk" -print0 | sort -z)
            ;;
    esac
    
    # 결과가 있으면 0, 없으면 1 반환
    [ ${#APK_LIST[@]} -gt 0 ]
    return $?
}
