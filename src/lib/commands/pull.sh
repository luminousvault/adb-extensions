#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# PULL Command
# 디바이스 최근 파일 가져오기
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# 최근 파일 조회 개수 상한 (쿼리와 help 문구에서 공용)
AK_PULL_RECENT_LIMIT=300

# Completion definition: command name and description
: <<'AK_COMPLETION_DESC'
pull:Pull recent files from device
AK_COMPLETION_DESC

# Completion handler: zsh completion code for pull command
: <<'AK_COMPLETION'
        pull)
          _arguments \
            '(- *)'{-h,--help}'[Show help for this command]' \
            '1:destination directory:_files -/'
          ;;
AK_COMPLETION

show_help_pull() {
    echo -e "${CYAN}${BOLD}Usage:${NC} ak pull [-h|--help] [directory]"
    echo
    echo "Description: Lists recently modified files on the device (like the Files app"
    echo "'Recents' tab, via MediaStore), lets you pick one or more interactively,"
    echo "then pulls them with adb. Files are saved with their original names."
    echo
    echo -e "${CYAN}${BOLD}Examples:${NC}"
    echo "  ak pull                  # Pull selected files into the current directory"
    echo "  ak pull /path/to/folder  # Pull into the given directory (created if needed)"
    echo
    echo "Notes:"
    echo "  - Shows the ${AK_PULL_RECENT_LIMIT} most recently modified files (newest first)."
    echo "  - Existing local files with the same name are overwritten."
    echo "  - Selected files sharing the same name are saved with a ' (N)' suffix."
    echo
    echo "Options:"
    echo "  -h, --help  Show this help message"
    echo
    exit 1
}

# 피커 suffix 라벨용 메타 정보 계산 (상대 폴더, 사람이 읽기 쉬운 크기)
# 결과는 G_FILE_META에 저장 (행마다 호출되므로 서브셸 fork 방지)
format_file_meta() {
    local path="$1" size="$2" dir rel human
    dir="${path%/*}"
    rel="${dir#/storage/emulated/0/}"
    [ "$rel" = "/storage/emulated/0" ] && rel="sdcard"
    case "$size" in
        ''|*[!0-9]*)
            human="?"
            ;;
        *)
            if [ "$size" -lt 1024 ]; then
                human="${size} B"
            elif [ "$size" -lt 1048576 ]; then
                human="$(( (size + 512) / 1024 )) KB"
            elif [ "$size" -lt 1073741824 ]; then
                local tenths=$(( (size * 10 + 524288) / 1048576 ))
                human="$((tenths / 10)).$((tenths % 10)) MB"
            else
                local tenths=$(( (size * 10 + 536870912) / 1073741824 ))
                human="$((tenths / 10)).$((tenths % 10)) GB"
            fi
            ;;
    esac
    G_FILE_META="${rel}, ${human}"
}

cmd_pull() {
    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help_pull
                ;;
            -*)
                echo -e "${ERROR} Invalid option: $1"
                echo "Try 'ak pull --help' for more information."
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [ $# -gt 1 ]; then
        echo -e "${ERROR} Too many arguments"
        echo "Try 'ak pull --help' for more information."
        exit 1
    fi

    # 저장 디렉터리 결정 (디바이스 선택·파일 선택 전에 조기 검증)
    local dest="${1:-.}"
    if [ ! -d "$dest" ]; then
        echo -e "${YELLOW}Directory does not exist:${NC} $dest"
        printf "Create it? [y/N] "
        local reply
        IFS= read -r reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *)
                echo "Aborted."
                exit 1
                ;;
        esac
        if ! mkdir -p "$dest"; then
            echo -e "${ERROR} Cannot create directory: $dest"
            exit 1
        fi
    fi

    # 디바이스 선택
    find_and_select_device

    # MediaStore에서 최근 수정 파일 조회 (파일앱 '최근 파일' 탭과 동일한 소스)
    # format이 NULL인 행도 포함해야 하므로 NULL-safe 비교 사용
    local raw
    raw=$(adb -s "$G_SELECTED_DEVICE" shell \
        "content query --uri content://media/external/file \
         --projection _data:date_modified:_size \
         --where \"(format IS NULL OR format != 12289) AND _size > 0 AND _data NOT LIKE '%/Android/%' AND _data NOT LIKE '%/.%'\" \
         --sort 'date_modified DESC' 2>&1 | head -n $AK_PULL_RECENT_LIMIT" | tr -d '\r')

    # 행 파싱: Row: 0 _data=<path>, date_modified=<ts>, _size=<bytes>
    # 행마다 실행되므로 외부 명령 없이 bash 파라미터 확장만 사용
    local remote_paths=() display_list=() line path size
    while IFS= read -r line; do
        case "$line" in
            Row:*) ;;
            *) continue ;;
        esac
        path="${line#* _data=}"
        path="${path%%, date_modified=*}"
        size="${line##*, _size=}"
        [ -z "$path" ] && continue
        format_file_meta "$path" "$size"
        remote_paths+=("$path")
        display_list+=("${path##*/}"$'\t'"(${G_FILE_META})")
    done <<< "$raw"

    if [ ${#remote_paths[@]} -eq 0 ]; then
        # 빈 결과와 쿼리 실패 구분 (content query는 빈 결과 시 "No result found" 출력)
        if [ -z "$raw" ] || [[ "$raw" == *"No result found"* ]]; then
            echo -e "${ERROR} No recent files found on device."
        else
            echo -e "${ERROR} Failed to query recent files from device:"
            printf '%s\n' "$raw" | head -n 5
        fi
        exit 1
    fi

    # 파일 선택 (MediaStore가 이미 최신순으로 반환)
    select_interactive "multi" "Select files to pull" "location:Recent files (newest first)" "${display_list[@]}"

    local selected_remotes=() idx
    for idx in "${SELECTED_INDICES[@]}"; do
        selected_remotes+=("${remote_paths[$idx]}")
    done

    if [ ${#selected_remotes[@]} -eq 0 ]; then
        echo -e "${YELLOW}No files selected.${NC}"
        exit 0
    fi

    # 선택 파일 pull (개별 실패 시에도 계속 진행)
    # 같은 이름의 파일이 여러 개 선택되면 " (N)" 접미사로 구분해 저장
    local remote base name ext n ok=0 fail=0
    local used_names=()
    for remote in "${selected_remotes[@]}"; do
        echo
        base="${remote##*/}"
        if contains "$base" "${used_names[@]}"; then
            if [[ "$base" == *.* ]]; then
                name="${base%.*}"
                ext=".${base##*.}"
            else
                name="$base"
                ext=""
            fi
            n=1
            while contains "${name} (${n})${ext}" "${used_names[@]}"; do
                n=$((n+1))
            done
            base="${name} (${n})${ext}"
            echo -e "${YELLOW}WARNING: Duplicate file name, saving as:${NC} $base"
        fi
        used_names+=("$base")
        echo -e "${YELLOW}==> Pulling:${NC} ${remote##*/}"
        adb -s "$G_SELECTED_DEVICE" pull "$remote" "${dest%/}/${base}"
        if [ $? -eq 0 ]; then
            ok=$((ok+1))
        else
            fail=$((fail+1))
            echo -e "${RED}ERROR: Failed to pull:${NC} $remote"
        fi
    done

    echo
    if [ "$fail" -gt 0 ]; then
        echo -e "${GREEN}Done:${NC} $ok pulled, ${RED}$fail failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}Done:${NC} $ok file(s) pulled to $dest"
}
