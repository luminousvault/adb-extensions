#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# Interactive UI
# 인터랙티브 사용자 선택 UI 함수
# ═══════════════════════════════════════════════════

# 디버그 초기화
debug_init
#@@BUILD_EXCLUDE_END


# 통합 인터랙티브 선택 함수: 단일/멀티 선택 지원
# 사용법: 
#   select_interactive "single" "프롬프트" "${array[@]}"  # 단일 선택
#   select_interactive "multi" "프롬프트" "${array[@]}"   # 멀티 선택
#   select_interactive "multi" "프롬프트" "location" "${array[@]}"  # location 정보 포함
# 
# 결과:
#   Single - SELECTED_ITEM, SELECTED_INDEX
#   Multi - SELECTED_ITEMS[], SELECTED_INDICES[]
select_interactive() {  
  # Bracketed Paste Mode 활성화 (붙여넣기 감지용)
  printf '\e[?2004h'
  
  # 디버그 로그 시작
  debug_log "=== select_interactive START ==="
  debug_log "mode_arg=$1, prompt=$2, item_count=${#}"
  
  # 입력 에코 차단 및 SIGINT(Ctrl+C) 비활성화 (직접 처리)
  local old_stty
  old_stty=$(stty -g)
  stty -echo intr undef
  
  # 화면 갱신: 깔끔한 선택 UI를 위해 이전 내용 지우기
  clear
  # 스크롤백 버퍼 지우기 (ANSI escape sequence - macOS/Linux 호환)
  printf '\033[3J'

  local mode_arg="$1"
  local prompt="$2"
  shift 2
  
  # location 파라미터 확인 (옵션)
  local location_info=""
  if [ $# -gt 0 ] && [[ "$1" == "location:"* ]]; then
    location_info="${1#location:}"
    shift
  fi
  
  local items=("$@")
  local item_count=${#items[@]}
  local focused=0
  local key=""
  
  # 모드와 필터 옵션 파싱
  local mode="${mode_arg%%:*}"        # single 또는 multi
  local enable_filter=1               # 기본값: 활성화
  local enable_sort=1                 # 기본값: 활성화 (filter와 연동)
  if [[ "$mode_arg" == *":nofilter"* ]]; then
    enable_filter=0
    enable_sort=0  # 필터 비활성화 시 sort도 비활성화
  fi
  
  # nocasematch 설정 저장 및 활성화 (필터링 성능 최적화)
  local old_nocasematch
  old_nocasematch=$(shopt -p nocasematch 2>/dev/null || echo "shopt -u nocasematch")
  shopt -s nocasematch
  
  # 숫자 표시를 위한 자리수 계산
  local max_digits=${#item_count}
  
  # 멀티 선택 모드용 상태 추적
  declare -a selection_status=()
  declare -a selection_order=()
  if [ "$mode" = "multi" ]; then
    for ((i=0; i<item_count; i++)); do
      selection_status[$i]=0
    done
  fi
  
  # 필터 모드 관련 변수
  local filter_mode=0          # 0: 일반 모드, 1: 필터 입력 모드
  local filter_text=""         # 현재 필터 문자열
  # shellcheck disable=SC2034  # Used in filtering logic
  local filter_text_lower=""   # 소문자 변환된 필터 텍스트 (캐시)
  local filter_cursor=0        # 필터 텍스트 내 커서 위치
  declare -a filtered_indices=()  # 필터된 항목의 원본 인덱스
  # shellcheck disable=SC2034  # Used in filtering logic
  declare -a display_items=()     # 화면에 표시할 항목 (필터 적용)
  declare -a highlighted_items=() # 하이라이트 적용된 항목 (사전 계산)
  
  # 소문자 변환 사전 계산 (성능 최적화: 1회만 변환)
  # 탭 이후(폴더 레이블)는 제거하고 소문자 변환 — 필터링이 파일명으로만 매칭되도록
  declare -a items_lower=()
  for item in "${items[@]}"; do
    local _item_name="${item%%$'\t'*}"
    items_lower+=("$(printf '%s' "$_item_name" | tr '[:upper:]' '[:lower:]')")
  done
  
  # Sort 모드 관련 변수
  local sort_mode=1            # 0: none(원본), 1: time-newest, 2: name (기본: 최신순)
  declare -a original_order=() # 원본 순서 저장 (인덱스 매핑용)
  declare -a initial_items=()        # 초기 원본 저장
  declare -a initial_items_lower=()  # 초기 원본 (소문자)
  
  # 초기 원본 복사 (items_lower 생성 후에 해야 함)
  for ((i=0; i<item_count; i++)); do
    original_order+=("$i")
    initial_items+=("${items[$i]}")
    initial_items_lower+=("${items_lower[$i]}")
  done
  
  # 터미널 크기 변경 감지용 플래그
  TERM_RESIZED=0
  trap 'TERM_RESIZED=1' WINCH
  
  # 마지막 렌더링 라인 추적 (종료 시 커서 위치 조정용)
  local last_render_line=0
  local help_msg_line=0      # 도움말 메시지 라인 위치
  local fixed_list_height=0  # 필터 모드 시 리스트 영역 높이 고정용
  
  # 안전한 종료를 위한 함수들
  # 정상 종료 (선택 완료): UI 내용 유지하고 다음 출력 준비
  restore_terminal() {
    trap - WINCH TERM
    # 커서를 마지막 렌더링 위치로 이동 (모든 UI 내용 보존)
    if [ $last_render_line -gt 0 ]; then
      tput cup $((last_render_line + 1)) 0
    fi
    # 다음 줄로 이동하여 다음 출력과 구분 (tput cup으로 이미 이동했으므로 개행 제거)
    tput cnorm
    stty "$old_stty"
    printf '\e[?2004l'  # Bracketed Paste Mode 비활성화
  }
  
  # 중단 (SIGTERM): UI 내용 유지하고 프로그램 종료
  # SIGINT(Ctrl+C)는 read 루프에서 직접 처리
  interrupt_handler() {
    trap - WINCH TERM
    # 커서를 마지막 렌더링 위치로 이동 (모든 UI 내용 보존)
    if [ $last_render_line -gt 0 ]; then
      tput cup $((last_render_line + 1)) 0
    fi
    tput cnorm
    stty "$old_stty"
    printf '\e[?2004l'  # Bracketed Paste Mode 비활성화
    # printf '\n'  # 프롬프트와 구분 (tput cup으로 이미 이동했으므로 제거)
    exit 130  # Ctrl+C 표준 exit code
  }
  
  # SIGTERM만 trap (SIGINT는 stty로 비활성화 후 키 입력으로 처리)
  trap interrupt_handler TERM

  tput civis # 커서 숨김
  
  # Location 정보 라인 수 계산 (항상 1줄로 표시)
  local location_lines=0
  if [ -n "$location_info" ]; then
    location_lines=1  # "Location: ~/path • ~/path2" 1줄
  fi
  
  # UI 레이아웃 상수 정의 (라인 계산용)
  # HEADER_LINES = 프롬프트(1) + Location라인(1) + 빈줄(1) = 3
  # Location이 없으면: 프롬프트(1) + 빈줄(1) = 2
  if [ $location_lines -eq 0 ]; then
    local HEADER_LINES=2
  else
    local HEADER_LINES=3
  fi
  local COUNTER_LINES=1       # 카운터 정보
  local HELP_LINES=1          # 도움말 (1줄)
  local FILTER_BOX_LINES=3    # 필터박스 (상단선 + 입력줄 + 하단선)
  local ITEM_SPACING_LINES=1  # 항목과 헬퍼 사이 빈줄
  
  # ═══════════════════════════════════════════════════
  # Sort 함수
  # ═══════════════════════════════════════════════════
  
  # 정렬 함수: sort_mode에 따라 items 배열 재정렬
  apply_sort() {
    debug_log "apply_sort START: sort_mode=$sort_mode"
    
    if [ $sort_mode -eq 0 ]; then
      # none: 초기 원본으로 복원
      debug_log "Sort mode: none (restoring initial order)"
      items=("${initial_items[@]}")
      items_lower=("${initial_items_lower[@]}")
      # original_order는 [0,1,2,...] 그대로 유지
      for ((i=0; i<item_count; i++)); do
        original_order[$i]=$i
      done
      # selection_status는 초기 원본 인덱스 기준이므로 변경하지 않음
      return 0
      
    elif [ $sort_mode -eq 1 ]; then
      # time-newest: 초기 원본이 이미 time-newest라고 가정하고 복원
      # (install.sh에서 time-newest로 가져옴)
      debug_log "Sort mode: time-newest (restoring initial order)"
      items=("${initial_items[@]}")
      items_lower=("${initial_items_lower[@]}")
      # original_order는 [0,1,2,...] 그대로 유지
      for ((i=0; i<item_count; i++)); do
        original_order[$i]=$i
      done
      # selection_status는 초기 원본 인덱스 기준이므로 변경하지 않음
      return 0
      
    elif [ $sort_mode -eq 2 ]; then
      # name: 초기 원본에서 이름순 정렬
      debug_log "Sort mode: name (sorting alphabetically)"
      
      # 초기 원본에서 정렬
      declare -a temp_items=()
      for ((i=0; i<item_count; i++)); do
        temp_items+=("$i|${initial_items[$i]}")
      done
      
      local sorted_array
      IFS=$'\n' read -r -d '' -a sorted_array < <(printf '%s\n' "${temp_items[@]}" | sort -t'|' -k2 && printf '\0')
      unset IFS
      
      # 정렬된 순서로 재구성
      declare -a new_items=()
      declare -a new_items_lower=()
      declare -a new_original_order=()
      
      for entry in "${sorted_array[@]}"; do
        local idx="${entry%%|*}"
        new_items+=("${initial_items[$idx]}")
        new_items_lower+=("${initial_items_lower[$idx]}")
        new_original_order+=("$idx")  # 원본 인덱스 추적
      done
      
      items=("${new_items[@]}")
      items_lower=("${new_items_lower[@]}")
      original_order=("${new_original_order[@]}")
      
      # selection_status는 초기 원본 인덱스 기준이므로 변경하지 않음
    fi
    
    debug_log "apply_sort END"
  }
  
  # 초기 필터 적용 (전체 항목)
  apply_filter
  
  # #region agent log H2
  debug_log "AGENT_LOG H2: After apply_filter - filtered_indices count=${#filtered_indices[@]}, item_count=$item_count"
  # #endregion
  

  
  # 렌더링 상태 추적 변수
  local prev_focused=-1          # 이전 포커스 위치
  local prev_filter_mode=-1      # 이전 필터 모드 상태
  local prev_window_start=-1     # 이전 윈도우 시작 위치
  local need_full_render=1       # 전체 렌더링 필요 플래그
  
  # ═══════════════════════════════════════════════════
  # 렌더링 함수들
  # ═══════════════════════════════════════════════════
  
  # 헤더 렌더링 함수
  render_header() {
    tput cup 0 0
    echo -e "\033[K${BLUE}==> ${BOLD}${prompt}${NC}"
    
    # Location 정보가 있으면 표시
    if [ -n "$location_info" ]; then
      # "location:" 접두사 제거
      local dirs_str="${location_info#location:}"
      # location_info를 |로 분리하여 배열로 변환
      IFS='|' read -ra dirs <<< "$dirs_str"
      unset IFS
      
      # 한 줄에 구분자로 표시
      local location_line=""
      if [ ${#dirs[@]} -eq 1 ]; then
        # 단일 디렉토리
        location_line="${dirs[0]}"
      elif [ ${#dirs[@]} -gt 1 ]; then
        # 여러 디렉토리 - 불릿(•)으로 구분
        local first=true
        for dir in "${dirs[@]}"; do
          if [ "$first" = true ]; then
            location_line="$dir"
            first=false
          else
            location_line="${location_line} • ${dir}"
          fi
        done
      fi

      tput cup 1 0
      echo -e "\033[K    ${DIM}Location: ${location_line}${NC}"
      tput cup 2 0
      echo -e "\033[K"
      
    else
      tput cup 1 0
      echo -e "\033[K"
    fi
  }
  
  # 필터 박스 렌더링 함수
  render_filter_box() {
    if [ $filter_mode -eq 1 ]; then
      local terminal_width
      terminal_width=$(tput cols)
      local line_width=$((terminal_width - 1))
      
      # 상단 라인
      local top_line
      top_line=$(printf '─%.0s' $(seq 1 $line_width))
      echo -e "\033[K${DIM}${top_line}${NC}"
      
      # 텍스트 내용 준비
      local before_cursor="${filter_text:0:$filter_cursor}"
      local at_cursor="${filter_text:$filter_cursor:1}"
      local after_cursor="${filter_text:$((filter_cursor + 1))}"
      
      # 커서 표시가 포함된 텍스트 (블록 커서 + 색상 반전)
      local display_text=""
      if [ -z "$at_cursor" ]; then
        display_text="${before_cursor}"$'\033[7m'" "$'\033[0m'
      else
        display_text="${before_cursor}"$'\033[7m'"${at_cursor}"$'\033[0m'"${after_cursor}"
      fi
      
      echo -e "\033[K> ${display_text}"
      
      # 하단 라인
      local bottom_line
      bottom_line=$(printf '─%.0s' $(seq 1 $line_width))
      echo -e "\033[K${DIM}${bottom_line}${NC}"
    fi
  }
  
  # 필터 박스만 부분 업데이트 (커서 이동 시, 고정 라인 위치)
  render_filter_box_only() {
    if [ $filter_mode -eq 1 ]; then
      local filtered_count=${#filtered_indices[@]}
      local visible_count=$((window_end - window_start))
      
      # 필터박스 위치: 헤더 + 카운터 + 아이템영역(고정높이) + 아이템과 헬퍼 사이 빈줄 + 헬퍼
      local filter_line=$((HEADER_LINES + COUNTER_LINES + fixed_list_height + ITEM_SPACING_LINES + HELP_LINES))
      
      tput cup $filter_line 0
      local terminal_width
      terminal_width=$(tput cols)
      local line_width=$((terminal_width - 1))

      # 텍스트 내용 준비
      local before_cursor="${filter_text:0:$filter_cursor}"
      local at_cursor="${filter_text:$filter_cursor:1}"
      local after_cursor="${filter_text:$((filter_cursor + 1))}"
      
      # 커서 표시가 포함된 텍스트 (블록 커서 + 색상 반전)
      local display_text=""
      if [ -z "$at_cursor" ]; then
        display_text="${before_cursor}"$'\033[7m'" "$'\033[0m'
      else
        display_text="${before_cursor}"$'\033[7m'"${at_cursor}"$'\033[0m'"${after_cursor}"
      fi
      
      echo -e "\033[K> ${display_text}"
      # Move cursor back to the input position for correct subsequent input
      tput cup $filter_line $((2 + filter_cursor)) # 2 for "> "
    fi
  }
  
  # 도움말 렌더링 함수
  render_help() {
    local pipe="${DIM}│${NC}"
    
    if [ $filter_mode -eq 1 ]; then
      # 필터 모드: 1줄만 표시
      if [ "$mode" = "multi" ]; then
        echo -e "\033[K${DIM}${CYAN}↑↓${NC}: Move ${pipe} ${CYAN}Enter${NC}: Confirm ${pipe} ${CYAN}Space${NC}: Toggle ${pipe} ${CYAN}/${NC}: Exit filter ${pipe} ${CYAN}^C${NC}: Exit${NC}"
      else
        echo -e "\033[K${DIM}${CYAN}↑↓${NC}: Move ${pipe} ${CYAN}Enter${NC}: Select ${pipe} ${CYAN}/${NC}: Exit filter ${pipe} ${CYAN}^C${NC}: Exit${NC}"
      fi
    else
      # 일반 모드: 1줄 표시
      local help_text="${DIM}${CYAN}↑↓${NC}: Move ${pipe} "
      
      if [ "$mode" = "multi" ]; then
        help_text+="${CYAN}Enter${NC}: Confirm ${pipe} ${CYAN}Space${NC}: Toggle ${pipe} ${CYAN}A${NC}: All ${pipe} "
      else
        help_text+="${CYAN}Enter${NC}: Select ${pipe} "
      fi
      
      if [ $enable_sort -eq 1 ]; then
        if [ $sort_mode -eq 0 ]; then
          help_text+="${CYAN}S${NC}: Sort ${pipe} "
        elif [ $sort_mode -eq 1 ]; then
          help_text+="${CYAN}S${NC}: Time↓ ${pipe} "
        else
          help_text+="${CYAN}S${NC}: Name↑ ${pipe} "
        fi
      fi
      
      if [ $enable_filter -eq 1 ]; then
        help_text+="${CYAN}/${NC}: Filter ${pipe} "
      fi
      
      help_text+="${CYAN}^C${NC}: Exit${NC}"
      
      echo -e "\033[K${help_text}"
    fi
  }

  # 도움말만 부분 업데이트 함수
  render_help_only() {
    tput cup $help_msg_line 0
    render_help
  }
  
  # 카운터 정보 렌더링 함수
  render_counter() {
    local filtered_count=${#filtered_indices[@]}
    local selected_count=0
    
    if [ "$mode" = "multi" ]; then
      for status in "${selection_status[@]}"; do
        if [ $status -eq 1 ]; then
          ((selected_count++))
        fi
      done
    fi
    
    if [ $filtered_count -gt $max_visible_items ]; then
      if [ "$mode" = "multi" ]; then
        if [ -n "$filter_text" ]; then
          echo -e "\033[K${DIM}Showing $((window_start + 1))-${window_end} / ${filtered_count} (filtered from ${item_count}) | ${GREEN}${selected_count} selected${NC}"
        else
          echo -e "\033[K${DIM}Showing $((window_start + 1))-${window_end} / ${filtered_count} | ${GREEN}${selected_count} selected${NC}"
        fi
      else
        if [ -n "$filter_text" ]; then
          echo -e "\033[K${DIM}Showing $((window_start + 1))-${window_end} / ${filtered_count} (filtered from ${item_count})${NC}"
        else
          echo -e "\033[K${DIM}Showing $((window_start + 1))-${window_end} / ${filtered_count}${NC}"
        fi
      fi
    else
      if [ "$mode" = "multi" ]; then
        if [ -n "$filter_text" ]; then
          echo -e "\033[K${DIM}${filtered_count} item(s) (filtered from ${item_count}) | ${GREEN}${selected_count} selected${NC}"
        else
          echo -e "\033[K${DIM}${filtered_count} item(s) | ${GREEN}${selected_count} selected${NC}"
        fi
      else
        if [ -n "$filter_text" ]; then
          echo -e "\033[K${DIM}${filtered_count} item(s) (filtered from ${item_count})${NC}"
        else
          echo -e "\033[K${DIM}${filtered_count} item(s)${NC}"
        fi
      fi
    fi
  }
  
  # 단일 항목 렌더링 함수
  render_single_item() {
    local display_idx=$1
    local items_idx=${filtered_indices[$display_idx]}
    local original_idx=${original_order[$items_idx]}  # 초기 원본 인덱스로 변환
    
    local number=$((display_idx + 1))  # 화면 표시 번호는 현재 표시 순서
    local checkbox=""
    
    if [ "$mode" = "multi" ]; then
      if [ ${selection_status[$original_idx]} -eq 1 ]; then
        checkbox="[✓] "
      else
        checkbox="[ ] "
      fi
    fi
    
    local number_prefix
    number_prefix=$(printf "%${max_digits}d. " "$number")
    local highlighted_item="${highlighted_items[$display_idx]}"

    local raw_item="${items[$items_idx]}"
    local folder_suffix=""
    if [[ "$raw_item" == *$'\t'* ]]; then
      folder_suffix="${DIM}  ${raw_item#*$'\t'}${NC}"
    fi

    if [ $display_idx -eq $focused ]; then
      echo -e "\033[K${CYAN}➤ ${checkbox}${BOLD}${number_prefix}${highlighted_item}${NC}${folder_suffix}"
    else
      if [ "$mode" = "multi" ] && [ ${selection_status[$original_idx]} -eq 1 ]; then
        echo -e "\033[K  ${GREEN}${checkbox}${NC}${number_prefix}${highlighted_item}${folder_suffix}"
      else
        echo -e "\033[K  ${checkbox}${number_prefix}${highlighted_item}${folder_suffix}"
      fi
    fi
  }
  
  # 모든 항목 렌더링 함수
  render_items() {
    local filtered_count=${#filtered_indices[@]}
    for ((display_idx=window_start; display_idx<window_end && display_idx<filtered_count; display_idx++)); do
      render_single_item "$display_idx"
    done
  }

  # 패딩 렌더링 함수 (필터 모드 시 높이 고정용)
  render_padding() {
    if [ $filter_mode -eq 1 ]; then
      local visible_count=$((window_end - window_start))
      if [ $visible_count -lt $fixed_list_height ]; then
        local padding=$((fixed_list_height - visible_count))
        for ((i=0; i<padding; i++)); do
          echo -e "\033[K"
        done
      fi
    fi
  }
  

  
  # 전체 화면 렌더링 함수
  render_full() {
    debug_log "=== render_full START ==="
    tput cup 0 0
    render_header        # 2줄 (헤더 + 빈줄)
    render_counter       # 1줄
    render_items         # 가변 (실제 표시 항목)
    render_padding       # 패딩 추가
    echo -e "\033[K"     # 항목과 헬퍼 사이 빈줄 (ITEM_SPACING_LINES)
    render_help          # 1줄
    if [ $filter_mode -eq 1 ]; then
      render_filter_box  # 3줄
    fi
    printf '\033[J'  # 화면 아래 잔여 내용 지우기
    
    # 마지막 렌더링 라인 계산 (종료 시 커서 위치 조정용)
    # 헤더(2) + 카운터(1) + 항목(visible_count) + 빈줄(1) + 헬퍼(1)
    local visible_count=$((window_end - window_start))
    
    # 필터 모드일 때는 패딩을 포함한 높이(fixed_list_height)를 사용
    local content_height=$visible_count
    if [ $filter_mode -eq 1 ]; then
        content_height=$fixed_list_height
    fi
    
    # 도움말 출력 라인 계산 (헤더 + 카운터 + 콘텐츠 + 빈줄)
    help_msg_line=$((HEADER_LINES + COUNTER_LINES + content_height + ITEM_SPACING_LINES))

    last_render_line=$((HEADER_LINES + COUNTER_LINES + content_height + ITEM_SPACING_LINES + HELP_LINES))
    
    if [ $filter_mode -eq 1 ]; then
      # 필터박스 3줄 추가 (상단선 + 입력줄 + 하단선)
      last_render_line=$((last_render_line + FILTER_BOX_LINES))
    fi
    debug_log "last_render_line calculated: $last_render_line (visible=$visible_count, content_height=$content_height, filter_mode=$filter_mode)"
    debug_log "=== render_full END ==="
  }
  
  # 카운터만 부분 업데이트 함수
  render_counter_only() {
    tput cup $((HEADER_LINES)) 0  # 헤더 다음
    render_counter
  }
  
  # 포커스 변경 부분 렌더링 함수 (이전 포커스와 새 포커스만 업데이트)
  render_focus_change() {
    local old_focus=$1
    local new_focus=$2
    
    # 항목 시작 라인 계산 (필터 모드와 관계없이 통일)
    # 헤더 + 카운터
    local items_start_line=$((HEADER_LINES + COUNTER_LINES))
    debug_log "render_focus_change: old=$old_focus, new=$new_focus, items_start_line=$items_start_line"
    
    local filtered_count=${#filtered_indices[@]}
    
    # window 내에서만 렌더링
    # 이전 포커스 라인 업데이트 (일반 항목으로)
    if [ $old_focus -ge $window_start ] && [ $old_focus -lt $window_end ] && [ $old_focus -lt $filtered_count ]; then
      local old_line=$((items_start_line + old_focus - window_start))
      tput cup $old_line 0
      render_single_item "$old_focus"
    fi
    
    # 새 포커스 라인 업데이트 (포커스된 항목으로)
    if [ $new_focus -ge $window_start ] && [ $new_focus -lt $window_end ] && [ $new_focus -lt $filtered_count ]; then
      local new_line=$((items_start_line + new_focus - window_start))
      tput cup $new_line 0
      render_single_item "$new_focus"
    fi
  }

  while true; do
    # 터미널 크기 변경 플래그 확인
    local is_resized=$TERM_RESIZED
    if [ $is_resized -eq 1 ]; then
      TERM_RESIZED=0
      debug_log "Terminal resized - triggering full render"
      clear
      printf '\033[3J'
      need_full_render=1

    fi
    
    # 매 루프마다 터미널 높이 재측정
    local terminal_height
    terminal_height=$(tput lines)
    
    # reserved_lines는 항상 필터 모드 기준 (최대값)으로 고정
    # 이렇게 해야 모드 전환 시 아이템 공간이 일정하고 하단 요소만 변경됨
    local reserved_lines=$((HEADER_LINES + COUNTER_LINES + HELP_LINES + ITEM_SPACING_LINES + FILTER_BOX_LINES))
    # = 2 + 1 + 1 + 1 + 4 = 10
    
    # #region agent log H4
    debug_log "AGENT_LOG H4: terminal_height=$terminal_height, reserved_lines=$reserved_lines, filter_mode=$filter_mode"
    # #endregion
    
    debug_log "terminal_height=$terminal_height, filter_mode=$filter_mode, reserved_lines=$reserved_lines(fixed)"
    
    local max_visible_items=$((terminal_height - reserved_lines - 1))
    
    if [ $max_visible_items -lt 1 ]; then
      max_visible_items=1
    fi
    
    # fixed_list_height 업데이트 로직
    # 필터 모드가 아니거나 리사이즈 되었을 때만 높이 갱신 (즉, 필터링 중에는 높이 고정)
    if [ $filter_mode -eq 0 ] || [ $is_resized -eq 1 ]; then
        local current_content_height=$max_visible_items
        # 전체 아이템이 화면보다 작으면 아이템 수만큼만 높이 차지
        if [ $item_count -lt $current_content_height ]; then
            current_content_height=$item_count
        fi
        fixed_list_height=$current_content_height
    fi
    

    
    # #region agent log H4
    debug_log "AGENT_LOG H4: max_visible_items calculated as $max_visible_items"
    # #endregion
    
    debug_log "max_visible_items=$max_visible_items"
    
    local filtered_count=${#filtered_indices[@]}
    
    # 필터 모드: 실제 항목 수에 맞춰 제한 (불필요한 패딩 방지)
    if [ $filter_mode -eq 1 ] && [ $filtered_count -lt $max_visible_items ]; then
      max_visible_items=$filtered_count
      debug_log "Filter mode: max_visible_items adjusted to $max_visible_items (filtered_count)"
    fi
    
    # 스크롤 윈도우 범위 계산
    local window_start=0
    local window_end=$filtered_count
    
    if [ $filtered_count -gt $max_visible_items ]; then
      window_start=$((focused - max_visible_items / 2))
      
      if [ $window_start -lt 0 ]; then
        window_start=0
      fi
      
      window_end=$((window_start + max_visible_items))
      
      if [ $window_end -gt $filtered_count ]; then
        window_end=$filtered_count
        window_start=$((filtered_count - max_visible_items))
        if [ $window_start -lt 0 ]; then
          window_start=0
        fi
      fi
    fi
    
    # #region agent log H3
    debug_log "AGENT_LOG H3: Window calculation - filtered_count=$filtered_count, max_visible_items=$max_visible_items, window_start=$window_start, window_end=$window_end, focused=$focused"
    # #endregion
    
    debug_log "Window: start=$window_start, end=$window_end, filtered_count=$filtered_count, focused=$focused"

    # 렌더링 결정: 전체 렌더링이 필요한가?
    if [ $need_full_render -eq 1 ] || [ $prev_filter_mode -ne $filter_mode ] || [ $prev_window_start -ne $window_start ]; then
      debug_log "Full render: need_full=$need_full_render, filter_mode_changed=$([[ $prev_filter_mode -ne $filter_mode ]] && echo 1 || echo 0), window_changed=$([[ $prev_window_start -ne $window_start ]] && echo 1 || echo 0)"
      render_full
      need_full_render=0
      prev_filter_mode=$filter_mode
      prev_window_start=$window_start
      prev_focused=$focused
    elif [ $prev_focused -ne $focused ]; then
      # 포커스만 변경: 부분 렌더링
      debug_log "Partial render: focus change only"
      render_focus_change "$prev_focused" "$focused"
      prev_focused=$focused
    fi
    # 아무 변경 없으면 렌더링하지 않음

    # 버퍼에 쌓인 이전 키 입력 제거 (방향키 반응 속도 개선)
    while IFS= read -rsn1 -t 0; do :; done
    
    # 키 입력 대기
    IFS= read -rsn1 key

    # Ctrl+C (ASCII 3, 0x03) 처리 - 즉시 종료
    if [[ $key == $'\x03' ]]; then
        restore_terminal
        exit 130
    fi

    # 필터 모드와 일반 모드에 따라 키 처리 분기
    if [ $filter_mode -eq 1 ]; then
      # ===== 필터 입력 모드 =====
      
      # ESC 시퀀스 처리 (시퀀스 vs 단독 ESC)
      if [[ $key == $'\x1b' ]]; then
        # 다음 문자를 1초 타임아웃으로 읽기 (Bash 3.2 호환)
        # read -t 0은 일부 환경에서 동작하지 않으므로 실제 읽기를 시도함
        if IFS= read -rsn1 -t 1 next_char; then
          # 문자가 읽혔다면 시퀀스로 간주 (예: [)
          # 나머지 1문자를 더 읽어서 2글자 시퀀스 완성 (예: A)
          IFS= read -rsn1 last_char
          seq="${next_char}${last_char}"
          
          if [[ $seq == "[A" ]]; then # 위쪽 화살표
            if [ $filtered_count -gt 0 ]; then
              ((focused--))
              if [ $focused -lt 0 ]; then focused=$((filtered_count - 1)); fi
            fi
          elif [[ $seq == "[B" ]]; then # 아래쪽 화살표
            if [ $filtered_count -gt 0 ]; then
              ((focused++))
              if [ $focused -ge $filtered_count ]; then focused=0; fi
            fi
          elif [[ $seq == "[C" ]]; then # 오른쪽 화살표
            if [ $filter_cursor -lt ${#filter_text} ]; then
              ((filter_cursor++))
              render_filter_box_only
            fi
          elif [[ $seq == "[D" ]]; then # 왼쪽 화살표
            if [ $filter_cursor -gt 0 ]; then
              ((filter_cursor--))
              render_filter_box_only
            fi
          elif [[ $seq == "[H" ]]; then # Home 키
            filter_cursor=0
            render_filter_box_only
          elif [[ $seq == "[F" ]]; then # End 키
            filter_cursor=${#filter_text}
            render_filter_box_only
          elif [[ $seq == "[2" ]]; then # Bracketed Paste 시퀀스 시작 가능성
            # [200~ 인지 확인
            IFS= read -rsn3 paste_check
            if [[ $paste_check == "00~" ]]; then
              # Bracketed Paste Mode: 붙여넣기 시작
              debug_log "Paste mode detected, reading until \\e[201~"
              local pasted_text=""
              local paste_buffer=""
              
              # [201~ 시퀀스가 나올 때까지 모든 문자 읽기
              while true; do
                IFS= read -rsn1 char
                paste_buffer+="$char"
                
                # 버퍼의 마지막 5글자가 [201~ 인지 확인
                local buffer_len=${#paste_buffer}
                if [ $buffer_len -ge 5 ]; then
                  local last_five="${paste_buffer:$((buffer_len - 5)):5}"
                  if [[ $last_five == "[201~" ]]; then
                    # 종료 시퀀스 발견: 앞의 \e 제거하고 [201~ 제거
                    pasted_text="${paste_buffer:0:$((buffer_len - 6))}"
                    break
                  fi
                fi
              done
              
              debug_log "Pasted text length: ${#pasted_text}"
              # 커서 위치에 붙여넣은 텍스트 삽입
              filter_text="${filter_text:0:$filter_cursor}${pasted_text}${filter_text:$filter_cursor}"
              filter_cursor=$((filter_cursor + ${#pasted_text}))
              # 한 번만 필터링 수행
              apply_filter
              need_full_render=1
            else
              # [2 다음이 00~가 아니면 무시 (알 수 없는 시퀀스)
              debug_log "Unknown sequence: ESC[2${paste_check}"
            fi
          elif [[ $seq == "[3" ]]; then # Delete 키 시퀀스 시작
            IFS= read -rsn1 # ~ 읽기
            if [ $filter_cursor -lt ${#filter_text} ]; then
              filter_text="${filter_text:0:$filter_cursor}${filter_text:$((filter_cursor + 1))}"
              apply_filter
              need_full_render=1
            fi
          fi
        else
          # 단독 ESC: 무시 (화살표 키 시퀀스가 아닌 경우)
          :
        fi
      elif [[ $key == $'\x7f' ]] || [[ $key == $'\x08' ]]; then
        # Backspace
        if [ $filter_cursor -gt 0 ]; then
          filter_text="${filter_text:0:$((filter_cursor - 1))}${filter_text:$filter_cursor}"
          ((filter_cursor--))
          apply_filter
          need_full_render=1
        fi
      elif [[ $key == $'\x01' ]]; then
        # Ctrl+A: 커서를 맨 앞으로
        filter_cursor=0
        render_filter_box_only
      elif [[ $key == $'\x05' ]]; then
        # Ctrl+E: 커서를 맨 뒤로
        filter_cursor=${#filter_text}
        render_filter_box_only
      elif [[ $key == "" ]]; then
        # Enter: 필터링된 결과로 확정
        if [ $filtered_count -eq 0 ]; then
          # 필터링 결과가 없으면 아무것도 하지 않음
          continue
        fi
        
        if [ "$mode" = "multi" ]; then
          # 멀티 모드: 선택된 항목 수 확인
          local selected_count=0
          for status in "${selection_status[@]}"; do
            if [ $status -eq 1 ]; then
              ((selected_count++))
            fi
          done

          # 아무것도 선택하지 않았으면 현재 포커스된 항목 선택
          if [ $selected_count -eq 0 ]; then
            local items_idx=${filtered_indices[$focused]}
            local original_idx=${original_order[$items_idx]}  # 초기 원본 인덱스로 변환
            selection_status[$original_idx]=1
            selection_order+=("$original_idx")
          fi
        fi
        break
      elif [[ $key == " " ]]; then
        # Space 키 - 선택/해제 토글 (멀티 모드만, 필터 모드에서)
        if [ "$mode" = "multi" ] && [ $filtered_count -gt 0 ]; then
          local items_idx=${filtered_indices[$focused]}
          local original_idx=${original_order[$items_idx]}  # 초기 원본 인덱스로 변환
          if [ ${selection_status[$original_idx]} -eq 0 ]; then
            # 선택 (Toggle ON)
            selection_status[$original_idx]=1
            selection_order+=("$original_idx")
            # 부분 렌더링: 카운터 + 현재 항목만
            render_counter_only
            # 항목 위치 계산
            local items_start_line=$((HEADER_LINES + COUNTER_LINES))
            local item_line=$((items_start_line + focused - window_start))
            tput cup $item_line 0
            render_single_item "$focused"
          else
            # 해제 (Toggle OFF)
            selection_status[$original_idx]=0
            # selection_order에서 제거
            local new_order=()
            for idx in "${selection_order[@]}"; do
              if [ "$idx" -ne "$original_idx" ]; then
                new_order+=("$idx")
              fi
            done
            selection_order=("${new_order[@]}")
            apply_filter  # 해제 시에만 호출 → 필터 매칭 체크 (선택됨+미매칭 항목 재정렬)
            need_full_render=1
          fi
        fi
      elif [[ $key == "/" ]]; then
        # '/' 키: 필터 모드 종료 및 필터 초기화
        debug_log "Exiting filter mode (/)"
        filter_text=""
        filter_cursor=0
        filter_mode=0
        apply_filter  # 전체 리스트로 복원
        need_full_render=1
      else
        # 일반 문자/숫자/특수문자 입력 (Space는 토글로 사용)
        # 출력 가능한 문자만 허용 (ASCII 33-126)
        local char_code
        char_code=$(printf '%d' "'$key")
        if [ $char_code -ge 33 ] && [ $char_code -le 126 ]; then
          filter_text="${filter_text:0:$filter_cursor}${key}${filter_text:$filter_cursor}"
          ((filter_cursor++))
          apply_filter
          need_full_render=1
        fi
      fi
      
    else
      # ===== 일반 선택 모드 =====
      
      # ESC 시퀀스 처리 (시퀀스 vs 단독 ESC)
      if [[ $key == $'\x1b' ]]; then
        # 다음 문자를 1초 타임아웃으로 읽기 (Bash 3.2 호환)
        if IFS= read -rsn1 -t 1 next_char; then
          # 문자가 읽혔다면 시퀀스로 간주
          IFS= read -rsn1 last_char
          seq="${next_char}${last_char}"
          
          if [[ $seq == "[A" ]]; then # 위쪽 화살표
            ((focused--))
            if [ $focused -lt 0 ]; then focused=$((filtered_count - 1)); fi
          elif [[ $seq == "[B" ]]; then # 아래쪽 화살표
            ((focused++))
            if [ $focused -ge $filtered_count ]; then focused=0; fi
          fi
        else
          # 단독 ESC: 일반 모드에서는 무시
          :
        fi
      fi

      # 키 동작 처리
      case "$key" in
        "") # Enter 키
          if [ $filtered_count -eq 0 ]; then
            # 필터링 결과가 없으면 아무것도 하지 않음
            continue
          fi
          
          if [ "$mode" = "multi" ]; then
            # 멀티 모드: 선택된 항목 수 확인
            local selected_count=0
            for status in "${selection_status[@]}"; do
              if [ $status -eq 1 ]; then
                ((selected_count++))
              fi
            done

            # 아무것도 선택하지 않았으면 현재 포커스된 항목 선택
            if [ $selected_count -eq 0 ]; then
              local items_idx=${filtered_indices[$focused]}
              local original_idx=${original_order[$items_idx]}  # 초기 원본 인덱스로 변환
              selection_status[$original_idx]=1
              selection_order+=("$original_idx")
            fi
          fi
          break
          ;;
        "/") # 필터 모드 진입 (enable_filter가 1일 때만)
          if [ $enable_filter -eq 1 ]; then
            debug_log "Entering filter mode"
            filter_mode=1
            need_full_render=1
          fi
          ;;
        "a"|"A") # A/a 키 - 전체 선택/해제 토글 (멀티 모드만)
          if [ "$mode" = "multi" ]; then
            # 모든 항목이 선택되어 있는지 확인
            local all_selected=1
            for status in "${selection_status[@]}"; do
              if [ $status -eq 0 ]; then
                all_selected=0
                break
              fi
            done

            if [ $all_selected -eq 1 ]; then
              # 모두 해제
              for ((i=0; i<item_count; i++)); do
                selection_status[$i]=0
              done
              selection_order=()
            else
              # 모두 선택 (순서대로)
              for ((i=0; i<item_count; i++)); do
                selection_status[$i]=1
                selection_order+=("$i")
              done
            fi
            need_full_render=1
          fi
          ;;
        "s"|"S") # Sort 토글 (APK 선택 시에만, 대소문자 구분 없음)
          if [ $enable_sort -eq 1 ]; then
            # 2-way 토글: time(1) ↔ name(2)
            if [ $sort_mode -eq 1 ]; then
              sort_mode=2  # time → name
            else
              sort_mode=1  # name → time
            fi
            apply_sort
            apply_filter  # 정렬 후 필터 재적용
            need_full_render=1
          fi
          ;;
        " ") # Space 키 - 선택/해제 토글 (멀티 모드만)
          if [ "$mode" = "multi" ] && [ $filtered_count -gt 0 ]; then
            local items_idx=${filtered_indices[$focused]}
            local original_idx=${original_order[$items_idx]}  # 초기 원본 인덱스로 변환
            
            if [ ${selection_status[$original_idx]} -eq 0 ]; then
              selection_status[$original_idx]=1
              selection_order+=("$original_idx")
            else
              selection_status[$original_idx]=0
              # selection_order에서 제거
              local new_order=()
              for idx in "${selection_order[@]}"; do
                if [ "$idx" -ne "$original_idx" ]; then
                  new_order+=("$idx")
                fi
              done
              selection_order=("${new_order[@]}")
            fi
            # 현재 포커스 항목과 카운터만 업데이트 (부분 렌더링)
            render_counter_only
            # 항목 위치로 이동 후 렌더링
            local items_start_line=$((HEADER_LINES + COUNTER_LINES))
            local item_line=$((items_start_line + focused - window_start))
            tput cup $item_line 0
            render_single_item "$focused"
          fi
          ;;
        [1-9]) # 숫자 키 1-9
          local selected_num=$((key))
          # 유효한 범위인지 확인
          if [ $selected_num -le $item_count ]; then
            if [ "$mode" = "multi" ]; then
              # 멀티 모드: 9개 이하일 때만 해당 항목만 선택하고 확정
              if [ $item_count -le 9 ]; then
                local selected_idx=$((selected_num - 1))
                # 해당 항목만 선택 상태로 변경
                for ((i=0; i<item_count; i++)); do
                  selection_status[$i]=0
                done
                selection_status[$selected_idx]=1
                selection_order=("$selected_idx")
                break
              fi
            else
              # 단일 모드: 9개 이하일 때만 즉시 선택하고 확정
              if [ $item_count -le 9 ]; then
                focused=$((selected_num - 1))
                break
              fi
            fi
          fi
          ;;
      esac
    fi
  done

  # 정상 종료 시 터미널 복원
  restore_terminal
  
  # nocasematch 원래 설정 복원 (안전한 방법)
  if [ -n "$old_nocasematch" ]; then
    eval "$old_nocasematch"
  fi

  # 선택된 항목을 전역 변수에 저장
  if [ "$mode" = "multi" ]; then
    # 멀티 선택: 배열로 저장
    SELECTED_ITEMS=()
    SELECTED_INDICES=()
    for idx in "${selection_order[@]}"; do
      # idx는 현재 items 배열의 인덱스
      # original_order[idx]가 실제 원본 인덱스
      local orig_idx="${original_order[$idx]}"
      SELECTED_ITEMS+=("${items[$idx]}")
      SELECTED_INDICES+=("$orig_idx")
    done
  else
    # 단일 선택: 단일 값으로 저장
    # focused는 필터링된 배열의 인덱스이므로 원본 인덱스로 변환
    if [ ${#filtered_indices[@]} -gt 0 ]; then
      local display_idx=${filtered_indices[$focused]}
      local original_idx=${original_order[$display_idx]}
      SELECTED_ITEM="${items[$display_idx]}"
      SELECTED_INDEX=$original_idx
    else
      # 필터링 결과가 없는 경우 (에러 케이스)
      # shellcheck disable=SC2034  # Used by caller
      SELECTED_ITEM=""
      # shellcheck disable=SC2034  # Used by caller
      SELECTED_INDEX=-1
    fi
  fi
}
