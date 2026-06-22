#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# Install Command
# APK 설치 커맨드 (ai.sh의 핵심 기능)
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# Completion definition: command name and description
: <<'AK_COMPLETION_DESC'
install:Install APK files
AK_COMPLETION_DESC

# Completion handler: zsh completion code for install command
: <<'AK_COMPLETION'
        install)
          local -a apk_files
          apk_files=(*.apk(N-.))
          _arguments -C \
            '(- *)'{-h,--help}'[Show help for this command]' \
            '(-a -f)-l[Install latest APK]' \
            '(-l -f)-a[Install all APKs]' \
            '(-l -a)-f[Filter APKs by filter]:filter' \
            '-m[Install on all devices]' \
            '-r[Replace existing app]' \
            '-t[Allow test APKs]' \
            '-d[Allow version downgrade]' \
            '*:APK files or directories:_files -g "*.apk(-.)" -/'
          ;;
AK_COMPLETION

# install 커맨드 도움말
show_help_install() {
  echo -e "${BOLD}Usage:${NC} ak install [options] [apk_files...]"
  echo "Install APK files on a selected Android device using adb."
  echo
  echo -e "${BOLD}General Options:${NC}"
  echo -e "  -h\t\tShow this help message and exit."
  echo
  echo -e "${BOLD}APK Selection Options (mutually exclusive):${NC}"
  echo -e "  (none)\tSelect APK files interactively from the current directory (default)."
  echo -e "  <directories>\tSelect APK files interactively from the specified directories."
  echo -e "  <apk files>\tDirectly specify APK files to install."
  echo -e "  -l\t\tInstall the latest APK file (from current directory or specified directory)."
  echo -e "  -a\t\tInstall all APK files (from current directory or specified directory)."
  echo -e "  -f <filter>\tFilter and select APK files matching the filter interactively."
  echo -e "\t\t\tFilter is REQUIRED. Can be used with directory."
  echo -e "\t\t\tExamples:"
  echo -e "\t\t\t  -f debug\t\t\tFind APKs containing 'debug' in current dir"
  echo -e "\t\t\t  -f \"myapp release\"\t\tFind APKs containing both 'myapp' and 'release'"
  echo -e "\t\t\t  -f debug /path/to/folder\tFind APKs in specified folder"
  echo
  echo -e "${BOLD}Device Options:${NC}"
  echo -e "  -m\t\tInstall APK files on all connected devices."
  echo
  echo -e "${BOLD}ADB Install Options:${NC}"
  echo -e "  -r\t\tReplace an existing application without removing its data (default)."
  echo -e "  -t\t\tAllow test APKs to be installed."
  echo -e "  -d\t\tAllow version code downgrade (requires 'pm' permission)."
  echo
  echo -e "${BOLD}Compatibility Notes:${NC}"
  echo -e "  If a '.idsig' file is present for the APK, the '--no-incremental' option is added to"
  echo -e "  the install command to ensure compatibility."
}

# 변수 초기화
initialize_install_variables() {
  install_opt="-r"
  opt_l_used=0
  opt_a_used=0
  opt_m_used=0
  opt_f_used=0
  filter=""
  install_positional_args=()
  USER_SPECIFIED_DIRECTORIES=()
  USER_SPECIFIED_INVALID_PATHS=()
}

# 옵션 파싱 (수동 파싱으로 옵션과 위치 인자를 구조적으로 분리)
process_install_options() {
  local i=1
  install_positional_args=()
  
  while [ $i -le $# ]; do
    local arg="${!i}"
    
    case "$arg" in
      -h|--help)
        show_help_install
        exit 0
        ;;
      -f)
        opt_f_used=1
        ((i++))
        # 다음 인자는 무조건 필터 문자열로 처리
        if [ $i -gt $# ]; then
          echo -e "${ERROR} Option -f requires a filter argument."
          echo
          echo -e "${BOLD}Usage:${NC} ak install -f <filter> [directory]"
          echo -e "${BOLD}Example:${NC}"
          echo -e "  ak install -f debug"
          echo -e "  ak install -f \"myapp release\""
          echo -e "  ak install -f debug /path/to/folder"
          echo -e "  ak install /path/to/folder -f debug"
          echo
          echo "For interactive selection of all APKs, use: ak install"
          exit 1
        fi
        filter="${!i}"
        ;;
      -l)
        opt_l_used=1
        ;;
      -a)
        opt_a_used=1
        ;;
      -m)
        opt_m_used=1
        ;;
      -t)
        install_opt+=" -t"
        ;;
      -d)
        install_opt+=" -d"
        ;;
      -r)
        # '-r' 옵션은 이미 기본값으로 설정되어 있으므로 무시
        ;;
      --*)
        # 긴 옵션 형태는 지원하지 않음 (--help는 위에서 처리됨)
        echo -e "${ERROR} Invalid option: $arg" 1>&2
        echo "Try 'ak install --help' for more information."
        exit 1
        ;;
      -*)
        # 알 수 없는 짧은 옵션
        echo -e "${ERROR} Invalid option: $arg" 1>&2
        echo "Try 'ak install --help' for more information."
        exit 1
        ;;
      *)
        # 옵션이 아닌 인자는 위치 인자로 수집
        install_positional_args+=("$arg")
        ;;
    esac
    ((i++))
  done
}

# 옵션 조합 검증
handle_option_combinations() {
  # '-l', '-a', '-f' 옵션 사용 여부 확인
  if [ $opt_l_used -eq 1 ] && [ $opt_a_used -eq 1 ] && [ $opt_f_used -eq 1 ]; then
    echo -e "${ERROR} Options -l, -a, and -f cannot be used together."
    exit 1
  fi

  if [ $opt_l_used -eq 1 ] && [ $opt_a_used -eq 1 ]; then
    echo -e "${ERROR} Options -l and -a cannot be used together."
    exit 1
  fi

  if [ $opt_l_used -eq 1 ] && [ $opt_f_used -eq 1 ]; then
    echo -e "${ERROR} Options -l and -f cannot be used together."
    exit 1
  fi

  if [ $opt_a_used -eq 1 ] && [ $opt_f_used -eq 1 ]; then
    echo -e "${ERROR} Options -a and -f cannot be used together."
    exit 1
  fi

  validate_install_apk_files "$@"
}

# APK 파일이 아닌지, APK 파일인데 다른 옵션과 같이 사용되었는지 판단
validate_install_apk_files() {
  for arg in "$@"; do
    # 파일 존재 여부
    if [ -f "$arg" ]; then
      extension="${arg##*.}"  # 확장자 추출
      
      if [[ "$extension" != "apk" ]]; then
        # 확장자가 APK 파일이 아닌 경우
        echo -e "${ERROR} Invalid file detected: '$arg'. Only APK files are allowed."
        exit 1
      elif [ $opt_l_used -eq 1 ] || [ $opt_a_used -eq 1 ] || [ $opt_f_used -eq 1 ]; then
        # '-l', '-a', '-f' 옵션 사용 시 APK 파일 인자를 허용하지 않음
        echo -e "${ERROR} Options -l, -a, or -f cannot be used with APK file arguments: '$arg'."
        exit 1
      fi
    fi
  done
}

# 옵션에 따라 APK 파일을 선택
select_apk_files() {
  apk_files=()

  # '-f' 옵션 사용 시: 인자가 있으면 `validate_and_collect_apk_files`에서 처리 (디렉토리 지원)
  # 인자가 없으면 select_apk_interactively 호출 (현재 디렉토리)
  if [ $opt_f_used -eq 1 ]; then
    if [ $# -eq 0 ]; then
      select_apk_interactively
      apk_files=("${selected_apks[@]}")
    fi
    # 인자가 있으면 아래에서 validate_and_collect_apk_files로 처리됨
  fi

  # '-l', '-a' 옵션 공통 처리
  if [ $opt_l_used -eq 1 ] || [ $opt_a_used -eq 1 ]; then
    local target_dir="."  # 기본값: 현재 디렉토리
    
    # 위치 인자에서 디렉토리 찾기 (첫 번째 디렉토리만 사용)
    for arg in "$@"; do
      if [ -d "$arg" ]; then
        target_dir="$arg"
        # 사용자 지정 디렉토리 추적
        USER_SPECIFIED_DIRECTORIES=("$target_dir")
        break
      fi
    done
    
    # APK 목록 가져오기 (한 번만 호출)
    get_apk_list "$target_dir" "time-newest"
    
    if [ ${#APK_LIST[@]} -gt 0 ]; then
      if [ $opt_l_used -eq 1 ]; then
        # -l: 첫 번째만
        apk_files+=("${APK_LIST[0]}")
      elif [ $opt_a_used -eq 1 ]; then
        # -a: 모두
        apk_files+=("${APK_LIST[@]}")
      fi
    fi
  fi

  # 옵션 없음 또는 -f 옵션 + 인자 있음 → APK 파일 또는 디렉토리 인자 확인
  if [ ${#apk_files[@]} -eq 0 ]; then
    validate_and_collect_apk_files "$@"
  fi

  # 여전히 APK 없음 AND 인자 없음 → 인터랙티브 선택 (기본 동작)
  if [ ${#apk_files[@]} -eq 0 ] && [ $# -eq 0 ]; then
    select_apk_interactively
    apk_files=("${selected_apks[@]}")
  fi

  # 여전히 APK 없음 → 에러 메시지 출력 후 종료
  if [ ${#apk_files[@]} -eq 0 ]; then
    echo -e "${ERROR} No APK files found."
    exit 1
  fi
}

# 인자로 APK 파일이 있는지 확인
validate_and_collect_apk_files() {
  local has_directories=false
  local has_apk_files=false
  local apk_list=()
  local apk_sources=()

  # 전역 변수 초기화
  USER_SPECIFIED_DIRECTORIES=()
  USER_SPECIFIED_INVALID_PATHS=()

  # 1단계: 모든 인자를 검사하여 디렉토리와 APK 파일을 분류
  for arg in "$@"; do
    # 존재하지 않는 경로 체크
    if [ ! -e "$arg" ]; then
      # 존재하지 않는 경로 - 경고 메시지 표시하되 계속 진행
      USER_SPECIFIED_INVALID_PATHS+=("$arg")
      continue
    fi

    # 파일인 경우
    if [ -f "$arg" ]; then
      # APK 파일인지 확인
      if [[ "$arg" == *.apk ]]; then
        # APK 파일 발견
        has_apk_files=true
        apk_list+=("$arg")
        local _src_dir
        _src_dir=$(cd "$(dirname "$arg")" 2>/dev/null && pwd)
        [[ "$_src_dir" == "$HOME"* ]] && _src_dir="${_src_dir/#$HOME/~}"
        apk_sources+=("$_src_dir")
      else
        # APK가 아닌 파일 - 에러 메시지 표시 후 종료
        echo -e "${ERROR} Invalid file detected: '$arg'. Only APK files are allowed."
        exit 1
      fi
    # 디렉토리인 경우
    elif [ -d "$arg" ]; then
      # 디렉토리 발견 - 해당 디렉토리의 APK 수집
      has_directories=true
      USER_SPECIFIED_DIRECTORIES+=("$arg")

      get_apk_list "$arg" "time-newest"
      local _src_dir="$arg"
      [[ "$_src_dir" != /* ]] && _src_dir=$(cd "$_src_dir" 2>/dev/null && pwd)
      [[ "$_src_dir" == "$HOME"* ]] && _src_dir="${_src_dir/#$HOME/~}"
      for _apk in "${APK_LIST[@]}"; do
        apk_list+=("$_apk")
        apk_sources+=("$_src_dir")
      done
    fi
  done

  # 2단계: 디렉토리나 APK가 있으면 처리
  if [ "$has_directories" = true ] || [ "$has_apk_files" = true ]; then
    # APK가 없으면 에러
    if [ ${#apk_list[@]} -eq 0 ]; then
      echo -e "${ERROR} No APK files found in the specified directories."
      exit 1
    fi

    # APK가 1개만 있으면 자동 선택
    if [ ${#apk_list[@]} -eq 1 ]; then
      apk_files=("${apk_list[0]}")
      echo -e "${BARROW} Only one APK file found: ${YELLOW}$(basename "${apk_list[0]}")${NC}"
      return 0
    fi

    # 여러 APK가 있으면 인터랙티브 선택
    # 필터링이 있으면 적용
    if [ -n "$filter" ]; then
      local filtered_apks=()
      local filtered_sources=()
      for i in "${!apk_list[@]}"; do
        local all_filters_match=true
        IFS=' ' read -ra filters <<< "$filter"
        for filter_item in "${filters[@]}"; do
          if ! echo "${apk_list[$i]}" | grep -i -q "$filter_item"; then
            all_filters_match=false
            break
          fi
        done
        if [ "$all_filters_match" = true ]; then
          filtered_apks+=("${apk_list[$i]}")
          filtered_sources+=("${apk_sources[$i]}")
        fi
      done
      apk_list=("${filtered_apks[@]}")
      apk_sources=("${filtered_sources[@]}")

      if [ ${#apk_list[@]} -eq 0 ]; then
        echo -e "${ERROR} No APK files found matching all filters: ${filter}"
        exit 1
      fi

      # 필터링 후 APK가 1개만 남으면 자동 선택
      if [ ${#apk_list[@]} -eq 1 ]; then
        apk_files=("${apk_list[0]}")
        echo -e "${BARROW} Only one APK file found: ${YELLOW}$(basename "${apk_list[0]}")${NC}"
        return 0
      fi
    fi

    # select_interactive 멀티 모드 호출
    # 출처가 2개 이상인지 판단
    local _multi_source=false
    local _distinct=()
    for _src in "${apk_sources[@]}"; do
      local _dup=false
      for _e in "${_distinct[@]}"; do
        [[ "$_src" == "$_e" ]] && { _dup=true; break; }
      done
      [ "$_dup" = "false" ] && _distinct+=("$_src")
    done
    [ ${#_distinct[@]} -gt 1 ] && _multi_source=true

    # 표시용 배열 생성 (출처 2개 이상이면 파일명\t(폴더명) 형식)
    local display_list=()
    for i in "${!apk_list[@]}"; do
      local _base
      _base=$(basename "${apk_list[$i]}")
      if [ "$_multi_source" = "true" ]; then
        local _label
        _label=$(basename "${apk_sources[$i]}")
        display_list+=("${_base}"$'\t'"(${_label})")
      else
        display_list+=("$_base")
      fi
    done
    
    # 경로 정보 추출 - 사용자 지정 디렉토리 목록 사용
    local location_param=""
    local formatted_dirs=()
    
    # 존재하는 디렉토리 처리
    for dir in "${USER_SPECIFIED_DIRECTORIES[@]}"; do
      local formatted_dir="$dir"
      
      # 절대 경로로 변환
      if [[ "$formatted_dir" != /* ]]; then
        # 상대 경로인 경우 절대 경로로 변환
        local abs_dir
        abs_dir=$(cd "$formatted_dir" 2>/dev/null && pwd)
        if [ -n "$abs_dir" ]; then
          formatted_dir="$abs_dir"
        fi
      fi
      
      # 홈 디렉토리 축약
      if [[ "$formatted_dir" == "$HOME"* ]]; then
        formatted_dir="${formatted_dir/#$HOME/~}"
      fi
      
      # 해당 디렉토리의 APK 개수 확인
      get_apk_list "$dir" "time-newest"
      local apk_count=${#APK_LIST[@]}
      
      # APK가 없는 경우 "(empty)" 표시 추가
      if [ $apk_count -eq 0 ]; then
        formatted_dir="${formatted_dir} (empty)"
      fi
      
      formatted_dirs+=("$formatted_dir")
    done
    
    # 존재하지 않는 경로 처리
    for invalid_path in "${USER_SPECIFIED_INVALID_PATHS[@]}"; do
      local formatted_path="$invalid_path"
      
      # ~로 시작하는 경로를 홈 디렉토리로 확장
      if [[ "$formatted_path" == ~/* ]] || [[ "$formatted_path" == ~ ]]; then
        formatted_path="${formatted_path/#\~/$HOME}"
      fi
      
      # 절대 경로로 변환 시도
      if [[ "$formatted_path" != /* ]]; then
        # 상대 경로인 경우 절대 경로로 변환 시도
        local abs_path
        abs_path=$(cd "$(dirname "$formatted_path")" 2>/dev/null && pwd)/$(basename "$formatted_path")
        if [ -n "$abs_path" ] && [[ "$abs_path" == /* ]]; then
          formatted_path="$abs_path"
        fi
      fi
      
      # 홈 디렉토리 축약
      if [[ "$formatted_path" == "$HOME"* ]]; then
        formatted_path="${formatted_path/#$HOME/~}"
      fi
      
      formatted_path="${formatted_path} (not found)"
      formatted_dirs+=("$formatted_path")
    done
    
    # location 파라미터 생성
    if [ ${#formatted_dirs[@]} -gt 0 ]; then
      IFS='|'
      location_param="location:${formatted_dirs[*]}"
      unset IFS
    fi
    
    echo -e "${BARROW} ${BOLD}Select APK files to install${NC}\n"
    if [ -n "$location_param" ]; then
      select_interactive "multi" "Select APK files" "$location_param" "${display_list[@]}"
    else
      select_interactive "multi" "Select APK files" "${display_list[@]}"
    fi
    
    # 선택된 인덱스를 사용하여 원본 경로 매핑
    apk_files=()
    for idx in "${SELECTED_INDICES[@]}"; do
      apk_files+=("${apk_list[$idx]}")
    done
  fi
}

# APK 인터랙티브 선택
select_apk_interactively() {
  echo -e "${BARROW} ${BOLD}Scanning APK files in the current directory...${NC}"
  get_apk_list "." "time-newest"
  local apk_list=("${APK_LIST[@]}")

  # 현재 폴더에 APK 파일이 없는 경우 에러 출력 후 종료
  if [ ${#apk_list[@]} -eq 0 ]; then
    echo -e "${ERROR} No APK files found in the current directory."
    exit 1
  fi

  # 필터가 있는 경우 필터링
  if [ -n "$filter" ]; then
    filtered_apks=()
    for apk in "${apk_list[@]}"; do
      # 필터를 공백으로 분리하여 각각의 필터를 검색
      all_filters_match=true
      IFS=' ' read -ra filters <<< "$filter"
      for filter_item in "${filters[@]}"; do
        if ! echo "$apk" | grep -i -q "$filter_item"; then
          all_filters_match=false
          break
        fi
      done
      if [ "$all_filters_match" = true ]; then
        filtered_apks+=("$apk")
      fi
    done
    apk_list=("${filtered_apks[@]}")

    if [ ${#apk_list[@]} -eq 0 ]; then
      echo -e "${ERROR} No APK files found matching all filters: '$filter'"
      exit 1
    fi
  fi

  # 현재 폴더에 APK 파일이 1개인 경우 자동으로 선택
  if [ ${#apk_list[@]} -eq 1 ]; then
    selected_apks=("${apk_list[0]}")
    echo -e "${BARROW} Only one APK file found: ${YELLOW}$(basename "${apk_list[0]}")${NC}"
    return 0
  fi

  # 인터랙티브 선택 실행
  # 표시용 basename 배열 생성
  local display_list=()
  for apk in "${apk_list[@]}"; do
    display_list+=("$(basename "$apk")")
  done
  
  # 현재 디렉토리 경로 정보 추출
  local current_dir
  current_dir=$(pwd)
  # 홈 디렉토리 축약
  if [[ "$current_dir" == "$HOME"* ]]; then
    current_dir="${current_dir/#$HOME/~}"
  fi
  local location_param="location:${current_dir}"
  
  select_interactive "multi" "Select APK files to install" "$location_param" "${display_list[@]}"

  # 선택된 인덱스를 사용하여 원본 경로 매핑
  selected_apks=()
  for idx in "${SELECTED_INDICES[@]}"; do
    selected_apks+=("${apk_list[$idx]}")
  done

  # 유효한 선택이 없으면 종료
  if [ ${#selected_apks[@]} -eq 0 ]; then
    echo -e "${ERROR} No valid APK files selected."
    exit 1
  fi
}

# APK 파일 목록 출력
pretty_print_apk_files() {
  echo -e "${BARROW} ${BOLD}The APK files to install.${NC}"
  local i=1
  for apk_file in "${apk_files[@]}"; do
    echo "${i}. $(basename "$apk_file")"
    ((i++))
  done
}

# APK 설치 실행
execute_installation() {
  # 먼저 디바이스 정보를 시각화하여 출력
  if [ ${#selected_device[@]} -gt 1 ]; then
    echo
    pretty_print_selected_devices
  fi

  # 설치할 APK 파일들 출력
  echo
  pretty_print_apk_files

  # 설치 프로세스 시작 안내 메시지 출력
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${PURPLE}    🚀 Starting the install process for the selected devices... 🚀${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"

  for d in "${selected_device[@]}"; do
    echo
    echo -e "${BARROW} ${BOLD}Selected device: ${CYAN}$(pretty_device $d)${NC}"  

    for apk_file in "${apk_files[@]}"; do
      local inner_opt=$install_opt

      # APK 파일에 .idsig 파일이 있는 경우 '--no-incremental' 옵션 추가
      if [ -f "${apk_file}.idsig" ]; then
        echo
        echo -e "${GARROW} Detected an .idsig file associated with ${YELLOW}'$(basename "$apk_file")'${NC}."
        echo -e "    Applying the ${CYAN}${BOLD}'--no-incremental'${NC} option for compatibility.${NC}"
        inner_opt+=" --no-incremental"
      fi

      # 각 APK 파일에 대한 설치 명령 실행
      execute_install_command "-s $d" "$inner_opt" "$apk_file"
    done
  done
}

# 각 APK 파일에 대한 설치 명령 실행
execute_install_command() {
  local device_opt=$1
  local install_opt=$2
  local apk_file=$3

  echo
  echo -e "${BARROW} Install command: ${BOLD}adb install ${install_opt} $(basename "$apk_file")${NC}"
  local result
  result=$(start_adb_install "$device_opt" "$install_opt" "$apk_file")

  case "$result" in
    # 테스트 전용 설치 실패 시 처리
    *INSTALL_FAILED_TEST_ONLY*)
      retry_install "INSTALL_FAILED_TEST_ONLY" "-t" "${device_opt}" "${install_opt}" "${apk_file}"
      ;;
    # 버전 다운그레이드 설치 실패 시 처리
    *INSTALL_FAILED_VERSION_DOWNGRADE*)
      if [[ "$install_opt" == *"-d"* ]]; then
        resolve_downgrade "${device_opt}" "${install_opt}" "${apk_file}"
      else
        retry_install "INSTALL_FAILED_VERSION_DOWNGRADE" "-d" "${device_opt}" "${install_opt}" "${apk_file}"
      fi
      ;;
    # 설치 불가능한 기존 앱과 충돌 발생 시 처리
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      resolve_conflict "${device_opt}" "${install_opt}" "${apk_file}" "${result}"
      ;;
    *) echo "$result" ;;
  esac
}

# 설치 실패 시 다시 시도
retry_install() {
  local failure_reason=$1
  local retry_option=$2
  local device_opt=$3
  local install_opt=$4
  local apk_file=$5

  local inner_opt="${install_opt} ${retry_option}"
  
  echo
  echo -e "${GARROW} Installation failed due to ${YELLOW}'${failure_reason}'${NC}. Retrying with ${CYAN}${BOLD}'${retry_option}'${NC} option."
  echo
  echo -e "${BARROW} Install command: ${BOLD}adb install ${inner_opt} $(basename "$apk_file")${NC}"

  # 옵션을 추가하여 재설치
  local result
  result=$(start_adb_install "$device_opt" "$inner_opt" "$apk_file")

   case "$result" in
    # 버전 다운그레이드 설치 실패 시 처리
    *INSTALL_FAILED_VERSION_DOWNGRADE*)
      resolve_downgrade "${device_opt}" "${install_opt}" "${apk_file}"
      ;;
    *) echo "$result" ;;
  esac
}

# 다운그레이드 실패 처리
resolve_downgrade() {
  local device_opt=$1
  local install_opt=$2
  local apk_file=$3

  echo
  echo -e "${RED}${BOLD}Application Installation Failed${NC}"
  echo
  echo -e "The adb install -d option is not supported on newer Android OS versions."
  echo -e "You need to uninstall the existing application before reinstalling it."
  echo
  echo -e "${YELLOW}${BOLD}WARNING:${NC} Uninstalling will remove all application data!"
  echo
  echo -n "Do you want to uninstall and reinstall the application? [Y/n]: "
  read -rsn1 choice
  echo "$choice"
  
  # 엔터키나 y/Y면 진행, n/N이면 중단
  if [[ -z "$choice" ]] || [[ "$choice" == "y" ]] || [[ "$choice" == "Y" ]]; then
    # aapt 도구 찾기
    local aapt=$(find_aapt)
    if [ -z "$aapt" ]; then
      echo
      echo -e "${ERROR} aapt not found."
      echo
      echo -e "${YELLOW}aapt is included in Android SDK build-tools.${NC}"
      echo
      echo -e "${BOLD}Solutions:${NC}"
      echo -e "  1. Install Android Studio and add build-tools via SDK Manager"
      echo -e "  2. Set ANDROID_HOME environment variable:"
      echo -e "     ${DIM}export ANDROID_HOME=\$HOME/Library/Android/sdk  # macOS${NC}"
      echo -e "     ${DIM}export ANDROID_HOME=\$HOME/Android/Sdk          # Linux${NC}"
      echo
      return 1
    fi
    
    # 패키지 이름 추출
    local package_name
    package_name=$("$aapt" dump badging "${apk_file}" | grep package:\ name | awk -F"'" '{print $2}')

    echo
    echo -e "${BARROW} Uninstalling package: ${BOLD}${package_name}${NC}"
    adb ${device_opt} uninstall "${package_name}" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
      echo -e "${GARROW} Uninstallation successful."
      echo
      echo -e "${BARROW} Install command: ${BOLD}adb install ${install_opt} $(basename "$apk_file")${NC}"
      start_adb_install "$device_opt" "$install_opt" "$apk_file"
    else
      echo -e "${ERROR} Failed to uninstall the existing application."
    fi
  else
    echo -e "${GARROW} Installation aborted by user."
  fi
}

# INSTALL_FAILED_UPDATE_INCOMPATIBLE 오류 처리
resolve_conflict() {
  local device_opt=$1
  local install_opt=$2
  local apk_file=$3
  local result=$4
  
  echo
  echo -e "${RED}${BOLD}Application Installation Failed${NC}"
  echo
  echo -e "The device already has an application with the same package but a different signature."
  echo -e "In order to proceed, you will have to uninstall the existing application."
  echo
  echo -e "${YELLOW}${BOLD}WARNING:${NC} Uninstalling will remove the application data!"
  echo
  echo -n "Do you want to uninstall the existing application? [Y/n]: "
  read -rsn1 choice
  echo "$choice"

  # 엔터키나 y/Y면 진행, n/N이면 중단
  if [[ -z "$choice" ]] || [[ "$choice" == "y" ]] || [[ "$choice" == "Y" ]]; then
    # 패키지 이름 추출
    local package_name
    package_name=$(echo "$result" | sed -n 's/.*package \([^ ]*\).*/\1/p')

    echo
    echo -e "${BARROW} Uninstalling package: ${BOLD}${package_name}${NC}"
    adb ${device_opt} uninstall "${package_name}" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
      echo -e "${GARROW} Uninstallation successful."
      echo
      echo -e "${BARROW} Install command: ${BOLD}adb install ${install_opt} $(basename "$apk_file")${NC}"
      start_adb_install "$device_opt" "$install_opt" "$apk_file"
    else
      echo -e "${ERROR} Failed to uninstall the existing application."
    fi
  else
    echo -e "${GARROW} Installation aborted by user."
  fi
}

# adb install 실행
start_adb_install() {
  local device_opt=$1
  local install_opt=$2
  local apk_file=$3
  # adb install 실행 결과를 반환
  adb ${device_opt} install ${install_opt} "${apk_file}" 2>&1
}

# ─────────────────────────────────────────────────────
# install 커맨드 메인 진입점
# ─────────────────────────────────────────────────────

cmd_install() {
  # 변수 초기화
  initialize_install_variables
  
  # 옵션 파싱 (옵션과 위치 인자를 구조적으로 분리)
  process_install_options "$@"
  
  # 옵션 조합 검증 (위치 인자 배열 사용)
  handle_option_combinations "${install_positional_args[@]}"
  
  # APK 파일 선택 (위치 인자 배열 사용)
  select_apk_files "${install_positional_args[@]}"
  
  # 설치할 디바이스 선택 (멀티 디바이스 지원)
  find_and_select_devices_multi $opt_m_used
  
  # APK 설치 실행
  execute_installation
}
