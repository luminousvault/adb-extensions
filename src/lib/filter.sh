#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# Filtering Functions
# 필터링 및 하이라이팅 함수
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# 순차 매칭 함수: 입력 문자열의 각 문자가 대상 문자열에 순서대로 존재하는지 확인 (Bash 3.2 호환)
matches_sequential() {
  local text_lower="$1"      # 소문자 변환된 항목 텍스트
  local filter_lower="$2"    # 소문자 변환된 필터 텍스트
  
  # 공백 제거 (텍스트와 필터 모두)
  text_lower="${text_lower// /}"
  filter_lower="${filter_lower// /}"
  
  local text_len=${#text_lower}
  local filter_len=${#filter_lower}
  local text_pos=0
  local filter_pos=0
  
  # 필터의 각 문자를 순차적으로 찾음
  while [ $filter_pos -lt $filter_len ] && [ $text_pos -lt $text_len ]; do
    local filter_char="${filter_lower:$filter_pos:1}"
    local text_char="${text_lower:$text_pos:1}"
    
    if [ "$filter_char" = "$text_char" ]; then
      ((filter_pos++))
    fi
    ((text_pos++))
  done
  
  # 모든 필터 문자를 찾았으면 매칭 성공
  [ $filter_pos -eq $filter_len ]
}

# 하이라이트 계산 함수: 순차 매칭된 문자들을 하이라이팅 (Bash 3.2 호환, fzf 스타일)
# 공백 무시: 텍스트와 필터의 공백을 무시하고 매칭
compute_highlight() {
  local text="$1"
  local text_lower="$2"    # 이미 소문자 변환된 텍스트 (성능 최적화)
  local filter_lower="$3"  # 이미 소문자 변환된 필터 텍스트
  
  # 필터가 비어있으면 원본 반환
  if [ -z "$filter_lower" ]; then
    echo "$text"
    return
  fi
  
  # tr 호출 제거 - 이미 변환된 text_lower 사용
  local text_len=${#text}
  local filter_len=${#filter_lower}
  local filter_pos=0
  local result=""
  local in_highlight=0
  
  # 단일 패스로 매칭 및 하이라이트
  for ((i=0; i<text_len; i++)); do
    local text_char="${text_lower:$i:1}"
    local orig_char="${text:$i:1}"
    
    # 공백 처리: 무시하고 원본 출력
    if [ "$text_char" = " " ]; then
      if [ $in_highlight -eq 1 ]; then
        result+=$'\033[0m'
        in_highlight=0
      fi
      result+="$orig_char"
      continue
    fi
    
    # 필터 문자가 남아있으면 매칭 시도
    if [ $filter_pos -lt $filter_len ]; then
      local filter_char="${filter_lower:$filter_pos:1}"
      
      # 필터 공백 건너뛰기
      while [ "$filter_char" = " " ] && [ $filter_pos -lt $filter_len ]; do
        ((filter_pos++))
        if [ $filter_pos -lt $filter_len ]; then
          filter_char="${filter_lower:$filter_pos:1}"
        fi
      done
      
      # 필터 문자와 매칭되는지 확인
      if [ $filter_pos -lt $filter_len ] && [ "$text_char" = "$filter_char" ]; then
        # 매칭: 하이라이트 시작
        if [ $in_highlight -eq 0 ]; then
          result+=$'\033[43m\033[30m'
          in_highlight=1
        fi
        result+="$orig_char"
        ((filter_pos++))
      else
        # 미매칭: 하이라이트 종료하고 원본 출력
        if [ $in_highlight -eq 1 ]; then
          result+=$'\033[0m'
          in_highlight=0
        fi
        result+="$orig_char"
      fi
    else
      # 필터 매칭 완료: 나머지 텍스트는 원본 출력
      if [ $in_highlight -eq 1 ]; then
        result+=$'\033[0m'
        in_highlight=0
      fi
      result+="$orig_char"
    fi
  done
  
  # 마지막 하이라이트 종료
  if [ $in_highlight -eq 1 ]; then
    result+=$'\033[0m'
  fi
  
  echo "$result"
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

