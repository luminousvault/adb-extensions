#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# Filtering Functions
# 필터링 및 하이라이팅 함수
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# 부분 문자열 매칭 함수: 필터 문자열이 대상 문자열에 연속으로 존재하는지 확인
matches_sequential() {
  local text_lower="$1"      # 소문자 변환된 항목 텍스트
  local filter_lower="$2"    # 소문자 변환된 필터 텍스트
  [[ "$text_lower" == *"$filter_lower"* ]]
}

# 하이라이트 계산 함수: 매칭된 부분 문자열 블록을 하이라이팅
compute_highlight() {
  local text="$1"
  local text_lower="$2"    # 이미 소문자 변환된 텍스트 (성능 최적화)
  local filter_lower="$3"  # 이미 소문자 변환된 필터 텍스트

  if [ -z "$filter_lower" ]; then
    echo "$text"
    return
  fi

  if [[ "$text_lower" != *"$filter_lower"* ]]; then
    echo "$text"
    return
  fi

  # %% 확장으로 첫 번째 매칭 위치(prefix 길이) 계산
  local prefix="${text_lower%%"$filter_lower"*}"
  local start=${#prefix}
  local filter_len=${#filter_lower}

  echo "${text:0:$start}"$'\033[43m\033[30m'"${text:$start:$filter_len}"$'\033[0m'"${text:$((start + filter_len))}"
}

# 필터링 함수: filter_text 기반으로 항목 필터링 (Bash 3.2 호환)
# Note: Uses variables from parent scope (item_count, items, mode, selection_status, items_lower, etc.)
# shellcheck disable=SC2154  # Variables from parent scope
apply_filter() {
  debug_log "apply_filter START: filter_text='$filter_text'"
  
  # 입력값이 없으면 필터링을 건너뛰고 전체 항목을 그대로 반환
  if [ -z "$filter_text" ]; then
    filtered_indices=()
    display_items=()
    highlighted_items=()
    filter_text_lower=""
    
    for ((i=0; i<item_count; i++)); do
      filtered_indices+=("$i")
      display_items+=("${items[$i]}")
      highlighted_items+=("${items[$i]%%$'\t'*}")  # 탭 이후(폴더 레이블) 제거
    done
    debug_log "apply_filter: no filter, returning all $item_count items"
    return
  fi
  
  # 필터링 로직 (입력값이 있는 경우에만 실행)
  filtered_indices=()
  display_items=()
  highlighted_items=()
  
  # 필터 텍스트를 소문자로 변환 (한 번만)
  filter_text_lower=$(printf '%s' "$filter_text" | tr '[:upper:]' '[:lower:]')
  
  # 중복 체크용 배열 (Bash 3.2 호환)
  declare -a added_flags=()
  for ((i=0; i<item_count; i++)); do
    added_flags[$i]=0
  done
  
  # 1단계: 멀티 모드일 때, 선택됨 + 미매칭 항목을 최상단에 배치
  if [ "$mode" = "multi" ]; then
    for ((i=0; i<item_count; i++)); do
      if [ ${selection_status[$i]} -eq 1 ]; then
        local item_lower="${items_lower[$i]}"
        # 선택됨 + 필터 미매칭 → 최상단 추가
        if ! matches_sequential "$item_lower" "$filter_text_lower"; then
          filtered_indices+=("$i")
          display_items+=("${items[$i]}")
          local _item_name="${items[$i]%%$'\t'*}"
          highlighted_items+=("$(compute_highlight "$_item_name" "${items_lower[$i]}" "$filter_text_lower")")
          added_flags[$i]=1
        fi
      fi
    done
  fi
  
  # 2단계: 필터 조건에 맞는 모든 항목 추가 (선택 여부 무관, 원래 순서 유지)
  for ((i=0; i<item_count; i++)); do
    if [ ${added_flags[$i]} -eq 0 ]; then
      local item_lower="${items_lower[$i]}"
      
      if matches_sequential "$item_lower" "$filter_text_lower"; then
        filtered_indices+=("$i")
        display_items+=("${items[$i]}")
        # 하이라이트 사전 계산 (서브셸 1회만)
        local _item_name="${items[$i]%%$'\t'*}"
        highlighted_items+=("$(compute_highlight "$_item_name" "${items_lower[$i]}" "$filter_text_lower")")
        added_flags[$i]=1
      fi
    fi
  done
  
  # 포커스가 필터 범위를 벗어나면 첫 번째 항목으로 리셋
  if [ ${#filtered_indices[@]} -gt 0 ]; then
    if [ $focused -ge ${#filtered_indices[@]} ]; then
      focused=0
    fi
  else
    focused=0
  fi
  
  debug_log "apply_filter END: filtered ${#filtered_indices[@]} items from $item_count"
}

