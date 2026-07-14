#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# EXTRACT Command
# APK 파일 추출
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# Completion definition: command name and description
: <<'AK_COMPLETION_DESC'
extract:Extract APK file from device
AK_COMPLETION_DESC

# Completion handler: zsh completion code for extract command
: <<'AK_COMPLETION'
        extract)
          _arguments \
            '(- *)'{-h,--help}'[Show help for this command]' \
            '1:package name or file name:_message "package name or save file name"' \
            '2:save file name or package name:_files'
          ;;
AK_COMPLETION

show_help_extract() {
    echo -e "${CYAN}${BOLD}Usage:${NC} ak extract [-h|--help] [packageName|saveApkFileName] [saveApkFileName|packageName]"
    echo
    echo "Description: Extract the APK file of the specified package to local storage."
    echo "The order of arguments is flexible - the script automatically detects which is the package name and which is the file name."
    echo
    echo -e "${CYAN}${BOLD}Examples:${NC}"
    echo "  ak extract                          # Auto-detect current app, save as <packageName>.apk"
    echo "  ak extract myapp.apk                # Auto-detect current app, save as myapp.apk"
    echo "  ak extract com.example.app          # Specific package, save as com.example.app.apk"
    echo "  ak extract com.example.app out.apk  # Specific package, save as out.apk"
    echo "  ak extract out.apk com.example.app  # Same as above (order flexible)"
    echo
    echo "Options:"
    echo "  -h, --help  Show this help message"
    echo
    exit 1
}

cmd_extract() {
    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help_extract
                ;;
            -*)
                echo -e "${ERROR} Invalid option: $1"
                echo "Try 'ak extract --help' for more information."
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 디바이스 선택
    find_and_select_device
    
    # 스마트 아규먼트 파싱: 순서에 상관없이 파일명과 패키지명 감지
    local package_name=""
    local save_apk_file_name=""
    
    case $# in
        0)
            # 아규먼트 없음: 자동 감지 + 기본 파일명
            package_name=""
            save_apk_file_name=""
            ;;
        1)
            # 1개 인자: 파일명 패턴인지 패키지명인지 판단
            if [[ "$1" == *.apk ]] || [[ "$1" == */* ]]; then
                # .apk 확장자 또는 경로 구분자 포함 → 파일명
                package_name=""
                save_apk_file_name="$1"
            else
                # 패키지명 (com.example.app 형태)
                package_name="$1"
                save_apk_file_name=""
            fi
            ;;
        2)
            # 2개 인자: 순서 판단
            if [[ "$1" == *.apk ]] || [[ "$1" == */* ]]; then
                # 첫번째가 파일명 → 역순
                save_apk_file_name="$1"
                package_name="$2"
            else
                # 첫번째가 패키지명 → 정순 (기존)
                package_name="$1"
                save_apk_file_name="$2"
            fi
            ;;
        *)
            echo -e "${ERROR} Too many arguments"
            echo "Try 'ak extract --help' for more information."
            exit 1
            ;;
    esac

    echo    
    if [ -z "$package_name" ]; then
        package_name=$(detect_foreground_package)
        echo -e "${YELLOW}Auto-detected package:${NC} $package_name"
    else
        echo -e "${BLUE}Using specified package:${NC} $package_name"
    fi
    
    echo
    validate_package_or_exit "$package_name"
    
    # save_apk_file_name이 null이거나 빈 문자열인 경우 기본 파일명 설정
    if [ -z "$save_apk_file_name" ]; then
        save_apk_file_name="${package_name}.apk"
    # save_apk_file_name이 주어졌지만 확장자가 .apk가 아닌 경우 확장자 추가
    elif [[ "$save_apk_file_name" != *.apk ]]; then
        save_apk_file_name="${save_apk_file_name}.apk"
    fi

    # 패키지 경로 찾기
    local apk_path
    apk_path=$(get_apk_path_for_package "$package_name") || exit 1
    
    # APK 파일 가져오기
    adb -s "$G_SELECTED_DEVICE" pull "$apk_path" "$save_apk_file_name"
    if [ $? -ne 0 ]; then
        echo
        echo -e "${RED}ERROR: Failed to pull APK from device. Check device connection and permissions.${NC}"
        exit 1
    fi

    echo -e "${GREEN}APK file saved as:${NC} $save_apk_file_name"
}
