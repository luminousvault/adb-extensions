#!/bin/bash
# ═══════════════════════════════════════════════════
# Build Script for ADB extensions kit (ak)
# 모듈화된 소스를 단일 파일로 빌드하거나 개발용 로컬 설치
# ═══════════════════════════════════════════════════

VERSION="$(cat src/VERSION)"
BUILD_DIR="build"
SRC_DIR="src"

# 색상 정의
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────────────────────────────────────────────
# 개발용 로컬 설치
# ─────────────────────────────────────────────────────

install_local() {
  # 1. 빌드 파일 존재 확인
  if [ ! -f "${BUILD_DIR}/ak" ]; then
    echo
    echo -e "${RED}ERROR: Build file not found.${NC}"
    echo -e "${YELLOW}Please run './build.sh' first to build the project.${NC}"
    echo
    exit 1
  fi
  
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Installing ADB extensions kit (ak)${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo
  echo -e "${CYAN}==> Installing from build directory...${NC}"
  
  # 2. 권한 확인
  if [ ! -w "/usr/local/bin" ]; then
    echo -e "${RED}ERROR: Permission denied. Try running with 'sudo'.${NC}"
    exit 1
  fi
  
  # 3. 쉘 스크립트 설치
  cp "${BUILD_DIR}/ak" /usr/local/bin/ak
  chmod +x /usr/local/bin/ak
  xattr -d com.apple.quarantine /usr/local/bin/ak 2>/dev/null || true
  echo -e "${GREEN}✓ Installed: /usr/local/bin/ak${NC}"
  
  # 4. Completion 설치
  if [ -f "${BUILD_DIR}/completions/_ak" ]; then
    mkdir -p /usr/local/share/zsh/site-functions
    cp "${BUILD_DIR}/completions/_ak" /usr/local/share/zsh/site-functions/
    echo -e "${GREEN}✓ Installed: /usr/local/share/zsh/site-functions/_ak${NC}"
  fi
  
  echo
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Installation completed!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo
  echo -e "${YELLOW}Note: Using build files from '${BUILD_DIR}/'${NC}"
  echo -e "${YELLOW}This is the same as Homebrew installation.${NC}"
  echo
  echo -e "${YELLOW}To enable tab completion:${NC}"
  echo -e "  1. Restart your terminal, or"
  echo -e "  2. Run: ${BOLD}exec zsh${NC}"
  echo
}

# ─────────────────────────────────────────────────────
# 개발용 로컬 제거
# ─────────────────────────────────────────────────────

uninstall_local() {
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Uninstalling ADB extensions kit (ak) from Local Development${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo
  
  # 권한 확인
  if [ ! -w "/usr/local/bin" ]; then
    echo -e "${RED}ERROR: Permission denied. Try running with 'sudo'.${NC}"
    exit 1
  fi
  
  # 제거할 항목 확인
  local items_to_remove=()
  local completion_file="/usr/local/share/zsh/site-functions/_ak"
  local bin_file="/usr/local/bin/ak"
  
  # /usr/local/lib/ak는 더 이상 설치하지 않음 (단일 바이너리 방식)
  # 하지만 기존 설치가 있을 수 있으므로 확인
  local lib_dir="/usr/local/lib/ak"
  
  if [ -f "$completion_file" ]; then
    items_to_remove+=("$completion_file")
  fi
  
  if [ -d "$lib_dir" ]; then
    items_to_remove+=("$lib_dir (legacy)")
  fi
  
  if [ -f "$bin_file" ]; then
    items_to_remove+=("$bin_file")
  fi
  
  # 제거할 항목이 없으면 종료
  if [ ${#items_to_remove[@]} -eq 0 ]; then
    echo -e "${YELLOW}No installation found. Nothing to uninstall.${NC}"
    echo
    return 0
  fi
  
  # 제거할 항목 표시
  echo -e "${YELLOW}The following items will be removed:${NC}"
  for item in "${items_to_remove[@]}"; do
    echo -e "  • $item"
  done
  echo
  
  # 사용자 확인
  read -p "Are you sure you want to uninstall? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Uninstallation cancelled.${NC}"
    echo
    exit 0
  fi
  
  echo
  
  # 1. zsh completion 제거
  if [ -f "$completion_file" ]; then
    echo -e "${CYAN}==> Removing zsh completion...${NC}"
    rm -f "$completion_file"
    echo -e "${GREEN}✓ Removed: $completion_file${NC}"
  fi
  
  # 2. 메인 바이너리 제거
  if [ -f "$bin_file" ]; then
    echo -e "${CYAN}==> Removing binary...${NC}"
    rm -f "$bin_file"
    echo -e "${GREEN}✓ Removed: $bin_file${NC}"
  fi
  
  # 3. 레거시 라이브러리 디렉토리 제거 (기존 설치용)
  if [ -d "$lib_dir" ]; then
    echo -e "${CYAN}==> Removing legacy library modules...${NC}"
    rm -rf "$lib_dir"
    echo -e "${GREEN}✓ Removed: $lib_dir${NC}"
  fi
  
  echo
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Uninstallation completed successfully!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo
  echo -e "${YELLOW}To refresh your shell:${NC}"
  echo -e "  Run: ${BOLD}exec zsh${NC}"
  echo
}

# ─────────────────────────────────────────────────────
# 권한 문제 처리 유틸리티
# ─────────────────────────────────────────────────────

# 디렉토리를 안전하게 삭제 (권한 문제 시 sudo 사용)
safe_remove_dir() {
  local dir="$1"
  local show_message="${2:-true}"  # 기본값: 메시지 표시
  
  if [ ! -d "$dir" ]; then
    return 0  # 디렉토리가 없으면 성공
  fi
  
  # 일반 삭제 시도 (권한 문제 시 에러 무시)
  if rm -rf "$dir" 2>/dev/null; then
    return 0  # 성공
  fi
  
  # 권한 문제 발생 시 sudo로 재시도
  if [ "$show_message" = "true" ]; then
    echo -e "${YELLOW}  Directory has permission issues (from previous sudo operation)${NC}"
    echo -e "${YELLOW}  Cleaning with sudo...${NC}"
  fi
  
  sudo rm -rf "$dir"
  return $?
}

# ─────────────────────────────────────────────────────
# 빌드 디렉토리 정리
# ─────────────────────────────────────────────────────

clean_build() {
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Cleaning Build Directory${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo
  
  if [ ! -d "${BUILD_DIR}" ]; then
    echo -e "${YELLOW}No build directory found. Nothing to clean.${NC}"
    echo
    return 0
  fi
  
  echo -e "${YELLOW}The following directory will be removed:${NC}"
  echo -e "  • ${BUILD_DIR}/"
  echo
  
  echo
  echo -e "${CYAN}==> Removing build directory...${NC}"
  
  # safe_remove_dir 유틸리티 사용
  if safe_remove_dir "${BUILD_DIR}"; then
    echo -e "${GREEN}✓ Removed: ${BUILD_DIR}/${NC}"
  else
    echo -e "${RED}✗ Failed to remove: ${BUILD_DIR}/${NC}"
    echo
    exit 1
  fi
  
  echo
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Clean completed successfully!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo
}

# ─────────────────────────────────────────────────────
# 빌드 프로세스
# ─────────────────────────────────────────────────────

# 헤더 추출 함수
# #@@HEADER_START ~ #@@HEADER_END 사이의 내용만 추출 (마커 제외)
extract_header() {
  local file="$1"
  sed -n '/^#@@HEADER_START$/,/^#@@HEADER_END$/p' "$file" | \
  grep -v '^#@@HEADER_START$' | \
  grep -v '^#@@HEADER_END$'
}

# 빌드 제외 블록 제거 함수
# shebang 라인과 모든 #@@BUILD_EXCLUDE_START ~ END 블록을 제거
# debug_log, debug_init 호출 라인은 : (no-op)로 대체하여 빈 블록 문법 오류 방지
# 한 파일 내에 여러 개의 BUILD_EXCLUDE 블록이 있어도 모두 제거됨
remove_build_excludes() {
  local file="$1"
  sed '
    # shebang 제거
    /^#!/d
    
    # BUILD_EXCLUDE 블록 제거 (debug_log 함수 정의 등 포함)
    /^#@@BUILD_EXCLUDE_START$/,/^#@@BUILD_EXCLUDE_END$/d
    
    # debug_log 호출 라인을 : (no-op)로 대체
    # 완전히 제거하면 빈 then/else 블록이 되어 문법 오류 발생 가능
    s/^[[:space:]]*debug_log .*$/    : # no-op/
  ' "$file"
}

# 빌드 디렉토리 준비
prepare_build_dir() {
  echo -e "${CYAN}==> Preparing build directory...${NC}"
  
  # safe_remove_dir 유틸리티 사용
  safe_remove_dir "${BUILD_DIR}"
  
  # 디렉토리 재생성
  mkdir -p "${BUILD_DIR}/completions"
}

# 모듈을 하나의 파일로 병합
merge_modules() {
  local output="${BUILD_DIR}/ak"
  
  echo -e "${CYAN}==> Merging modules into single file...${NC}"
  
  # 1. ak에서 헤더 추출 (HEADER 마커 사용)
  extract_header "${SRC_DIR}/ak" > "$output"
  
  # 2. VERSION 주입
  echo "" >> "$output"
  echo "VERSION=\"${VERSION}\"" >> "$output"
  echo "RELEASE_DATE=\"$(date +%Y-%m-%d)\"" >> "$output"
  echo "" >> "$output"
  
  # 3. lib/common.sh
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Common Utilities" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  remove_build_excludes "${SRC_DIR}/lib/common.sh" >> "$output"
  echo "" >> "$output"
  
  # 4. lib/filter.sh
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Filtering Functions" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  remove_build_excludes "${SRC_DIR}/lib/filter.sh" >> "$output"
  echo "" >> "$output"
  
  # 5. lib/ui.sh
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Interactive UI" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  remove_build_excludes "${SRC_DIR}/lib/ui.sh" >> "$output"
  echo "" >> "$output"
  
  # 6. lib/device.sh
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Device Management" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  remove_build_excludes "${SRC_DIR}/lib/device.sh" >> "$output"
  echo "" >> "$output"
  
  # 6. lib/commands/*.sh
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Commands" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  for cmd_file in "${SRC_DIR}/lib/commands"/*.sh; do
    cmd_name=$(basename "$cmd_file" .sh)
    echo "" >> "$output"
    echo "# ───────────────────── $cmd_name ─────────────────────" >> "$output"
    remove_build_excludes "$cmd_file" >> "$output"
  done
  echo "" >> "$output"
  
  # 8. 메인 스크립트 (ak)
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  echo "# Main Entry Point" >> "$output"
  echo "# ═══════════════════════════════════════════════════" >> "$output"
  remove_build_excludes "${SRC_DIR}/ak" >> "$output"
  
  chmod +x "$output"
  
  local line_count
  line_count=$(wc -l < "$output")
  echo -e "${GREEN}✓ Created: ${output} (${line_count} lines)${NC}"
}

# Completion 파일 동적 생성
generate_completion() {
  echo -e "${CYAN}==> Generating zsh completion from command code blocks...${NC}"
  
  local completion_file="${BUILD_DIR}/completions/_ak"
  
  # 1. 헤더 작성
  cat > "$completion_file" <<'EOF'
#compdef ak

_ak() {
  local -a commands
  commands=(
EOF
  
  # 2. 모든 커맨드 파일에서 AK_COMPLETION_DESC 블록 추출
  for cmd_file in "${SRC_DIR}/lib/commands"/*.sh; do
    [[ ! -f "$cmd_file" ]] && continue
    
    # AK_COMPLETION_DESC 블록 추출 (첫줄/마지막줄 제거)
    sed -n "/^: <<'AK_COMPLETION_DESC'$/,/^AK_COMPLETION_DESC$/p" "$cmd_file" 2>/dev/null | \
      sed '1d;$d' | \
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "    '$line'"
      done >> "$completion_file"
  done
  
  # 3. 중간 구조 작성
  cat >> "$completion_file" <<'EOF'
  )
  
  _arguments -C \
    '(- *)'{-h,--help}'[Show help message]' \
    '(- *)'{-v,--version}'[Show version]' \
    '1:command:->command' \
    '*::arg:->args' && return 0
  
  case $state in
    command)
      _describe 'ak commands' commands
      ;;
    args)
      case $words[1] in
EOF
  
  # 4. 모든 커맨드 파일에서 AK_COMPLETION 블록 추출
  for cmd_file in "${SRC_DIR}/lib/commands"/*.sh; do
    [[ ! -f "$cmd_file" ]] && continue
    
    # AK_COMPLETION 블록 추출 (첫줄/마지막줄 제거, 그대로 출력)
    sed -n "/^: <<'AK_COMPLETION'$/,/^AK_COMPLETION$/p" "$cmd_file" 2>/dev/null | \
      sed '1d;$d' >> "$completion_file"
  done
  
  # 5. 푸터 작성
  cat >> "$completion_file" <<'EOF'
        *)
          _arguments '(- *)'{-h,--help}'[Show help for this command]'
          ;;
      esac
      ;;
  esac
}

_ak "$@"
EOF
  
  echo -e "${GREEN}✓ Generated: ${completion_file}${NC}"
  echo -e "${DIM}  (자동 생성: heredoc 블록 추출 → 조립)${NC}"
}


# 빌드 검증
verify_build() {
  echo -e "${CYAN}==> Verifying build...${NC}"
  
  # 문법 체크
  if bash -n "${BUILD_DIR}/ak"; then
    echo -e "${GREEN}✓ Syntax check passed${NC}"
  else
    echo -e "${RED}✗ Syntax check failed${NC}"
    return 1
  fi
  
  # 버전 체크
  local version
  version=$(bash "${BUILD_DIR}/ak" --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1)
  if [ "$version" = "$VERSION" ]; then
    echo -e "${GREEN}✓ Version check passed: $VERSION${NC}"
  else
    echo -e "${RED}✗ Version mismatch: expected $VERSION, got $version${NC}"
    return 1
  fi
}

# 빌드 요약
show_summary() {
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Build Summary${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  
  if [ -f "${BUILD_DIR}/ak" ]; then
    local lines
    lines=$(wc -l < "${BUILD_DIR}/ak")
    local size
    size=$(du -h "${BUILD_DIR}/ak" | cut -f1)
    echo -e "  Shell Script: ${CYAN}${BUILD_DIR}/ak${NC} ($lines lines, $size)"
  fi
  
  if [ -f "${BUILD_DIR}/completions/_ak" ]; then
    echo -e "  Completion:   ${CYAN}${BUILD_DIR}/completions/_ak${NC}"
  fi
  
  echo
  echo -e "${GREEN}✓ Build completed successfully!${NC}"
  echo
  echo -e "${YELLOW}Next steps:${NC}"
  echo -e "  • Test: ${BUILD_DIR}/ak --version"
  echo -e "  • Test: ${BUILD_DIR}/ak --help"
  echo -e "  • Homebrew: Update ak.rb with new version and SHA256"
  echo
}

# ─────────────────────────────────────────────────────
# 메인 진입점
# ─────────────────────────────────────────────────────

main() {
  # --install 옵션 체크 (개발용 로컬 설치)
  if [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
    install_local
    exit 0
  fi
  
  # --uninstall 옵션 체크 (개발용 로컬 제거)
  if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    uninstall_local
    exit 0
  fi
  
  # --clean 옵션 체크 (빌드 디렉토리 정리)
  if [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
    clean_build
    exit 0
  fi
  
  # --help 옵션
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}ADB extensions kit (ak) - Build System${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}Usage:${NC} ./build.sh [options]"
    echo
    echo -e "${BOLD}Description:${NC}"
    echo -e "  Build system for ADB extensions kit. Merges modular source files"
    echo -e "  into a single distributable script or installs for local development."
    echo
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${GREEN}(none)${NC}              Build shell script (default)"
    echo -e "                      ${DIM}→ Creates build/ak${NC}"
    echo
    echo -e "  ${GREEN}--install, -i${NC}       Install built script (requires sudo)"
    echo -e "                      ${DIM}→ Uses existing build files from build/ directory${NC}"
    echo -e "                      ${DIM}→ Run './build.sh' first if not built yet${NC}"
    echo -e "                      ${DIM}→ Installs: /usr/local/bin/ak${NC}"
    echo -e "                      ${DIM}→ Same as Homebrew installation${NC}"
    echo
    echo -e "  ${GREEN}--uninstall, -u${NC}     Uninstall local installation (requires sudo)"
    echo -e "                      ${DIM}→ Removes: /usr/local/bin/ak${NC}"
    echo -e "                      ${DIM}→ Removes: /usr/local/share/zsh/site-functions/_ak${NC}"
    echo
    echo -e "  ${GREEN}--clean, -c${NC}         Clean build directory"
    echo -e "                      ${DIM}→ Removes: build/ directory${NC}"
    echo -e "                      ${DIM}→ Use before fresh build${NC}"
    echo
    echo -e "  ${GREEN}--help, -h${NC}          Show this help message"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${YELLOW}./build.sh${NC}                    # Build project"
    echo -e "  ${YELLOW}./build.sh --clean${NC}           # Clean build directory"
    echo -e "  ${YELLOW}sudo ./build.sh --install${NC}    # Install built binary"
    echo -e "  ${YELLOW}ak --version${NC}                 # Test installation"
    echo -e "  ${YELLOW}sudo ./build.sh --uninstall${NC}  # Uninstall"
    echo
    echo -e "${BOLD}Build Output:${NC}"
    echo -e "  ${CYAN}build/ak${NC}               Merged shell script"
    echo -e "  ${CYAN}build/completions/_ak${NC}   Zsh completion file"
    echo
    echo -e "${BOLD}Source Structure:${NC}"
    echo -e "  ${CYAN}src/ak${NC}                  Main entry point"
    echo -e "  ${CYAN}src/lib/common.sh${NC}       Common utilities"
    echo -e "  ${CYAN}src/lib/ui.sh${NC}           Interactive UI"
    echo -e "  ${CYAN}src/lib/device.sh${NC}       Device management"
    echo -e "  ${CYAN}src/lib/commands/*.sh${NC}   Command modules (including install)"
    echo
    echo -e "${BOLD}Development Workflow:${NC}"
    echo -e "  ${DIM}1.${NC} Edit source files in ${CYAN}src/${NC}"
    echo -e "  ${DIM}2.${NC} Test with ${YELLOW}./src/ak${NC} (no build needed)"
    echo -e "  ${DIM}3.${NC} Build with ${YELLOW}./build.sh${NC}"
    echo -e "  ${DIM}4.${NC} Test build with ${YELLOW}./build/ak${NC}"
    echo -e "  ${DIM}5.${NC} Install for testing ${YELLOW}sudo ./build.sh --install${NC}"
    echo -e "  ${DIM}6.${NC} Commit changes"
    echo
  echo -e "${BOLD}For more information:${NC}"
  echo -e "  Repository: ${CYAN}https://github.com/luminousvault/homebrew-adb-extensions${NC}"
  echo -e "  Version: ${GREEN}${VERSION}${NC}"
  echo
    exit 0
  fi
  
  # 유효하지 않은 옵션 체크
  if [ -n "$1" ]; then
    echo
    echo -e "${RED}ERROR: Invalid option: $1${NC}"
    echo -e "${YELLOW}Run './build.sh --help' to see available options.${NC}"
    echo
    exit 1
  fi
  
  # root로 빌드 시 경고
  if [ "$EUID" -eq 0 ]; then
    echo
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}WARNING: Running build as root${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${YELLOW}Building as root may cause permission issues with the build directory.${NC}"
    echo
    echo -e "${YELLOW}Recommended workflow:${NC}"
    echo -e "  ${GREEN}./build.sh${NC}                  (build as normal user)"
    echo -e "  ${GREEN}sudo ./build.sh --install${NC}   (install requires sudo)"
    echo
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Build cancelled.${NC}"
      exit 1
    fi
    echo
  fi
  
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Building ADB extensions kit (ak) v${VERSION}${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo
  
  prepare_build_dir
  merge_modules
  generate_completion
  # build_binary 제거 - 쉘 스크립트만 배포
  verify_build
  show_summary
}

main "$@"
