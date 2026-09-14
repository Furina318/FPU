#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM_DIR="$SCRIPT_DIR/software/asm-test"
CPU_DIR="$SCRIPT_DIR/cpu"
BUILD_DIR="$CPU_DIR/build"
LOG_DIR="$BUILD_DIR/test-logs"
RESULT_FILE=""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认选项
PARALLEL=1
KEEP_GOING=true
VERBOSE=false

# 显示帮助
show_help() {
    echo "FPU asm-test 全量运行脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -j N    并行运行 N 个测试 (默认 1)"
    echo "  -k      遇到失败时继续运行 (默认开启)"
    echo "  -K      遇到失败时立即停止"
    echo "  -v      显示每个测试的详细输出"
    echo "  -o FILE 将结果输出到文件"
    echo "  -h      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                  # 顺序运行所有测试"
    echo "  $0 -j 4             # 4 路并行运行"
    echo "  $0 -v -o result.txt # 详细输出并保存到文件"
}

# 收集所有测试名称
collect_tests() {
    local f name
    # 顶层 .S 文件
    for f in "$ASM_DIR"/*.S; do
        [ -f "$f" ] || continue
        name="$(basename "$f" .S)"
        echo "$name"
    done
    # 子目录中的 .S 文件 (如 fmadd_b15/fmadd_b15-001.S)
    for f in "$ASM_DIR"/*/*.S; do
        [ -f "$f" ] || continue
        name="$(basename "$f" .S)"
        echo "$name"
    done
}

# 根据测试名获取指令类型
get_instr_type() {
    echo "$1" | sed 's/_b[0-9].*$//'
}

# 计算百分比 (避免依赖 bc)
calc_pct() {
    local p=$1 n=$2
    if [ "$n" -eq 0 ]; then
        echo "0.0"
    else
        awk "BEGIN { printf \"%.1f\", $p * 100 / $n }"
    fi
}

# 运行单个测试
# 返回行格式: 测试名 退出码 耗时(ms)
run_test() {
    local test_name="$1"
    local log_file="${LOG_DIR}/${test_name}.log"
    local start_ms end_ms duration ret

    mkdir -p "$LOG_DIR"

    start_ms=$(date +%s%3N)

    set +e
    make -C "$CPU_DIR" run OBJ_DIR=build diff=1 FRAME=pipeline-FPU \
        ARGS="-b --log=build/test-logs/${test_name}.npc-log.txt" \
        IMG="$SCRIPT_DIR/software/build/asm-test/${test_name}.bin" \
        > "$log_file" 2>&1
    ret=$?
    set -e

    end_ms=$(date +%s%3N)
    duration=$((end_ms - start_ms))

    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[运行]${NC} $test_name" >&2
        tail -20 "$log_file" >&2
    fi

    echo "$test_name $ret $duration"
}

# 打印进度条
print_progress() {
    local current=$1 total=$2
    local pct=$((current * 100 / total))
    local filled=$((current * 40 / total))
    local empty=$((40 - filled))
    local i
    printf "\r${BLUE}[PROG]${NC} ["
    for ((i = 0; i < filled; i++)); do printf '█'; done
    for ((i = 0; i < empty; i++)); do printf '░'; done
    printf "] %3d%% (%d/%d)" "$pct" "$current" "$total"
}

# 主函数
main() {
    # 解析参数
    while getopts "j:kKvho:" opt; do
        case $opt in
            j) PARALLEL=$OPTARG ;;
            k) KEEP_GOING=true ;;
            K) KEEP_GOING=false ;;
            v) VERBOSE=true ;;
            o) RESULT_FILE="$OPTARG" ;;
            h) show_help; exit 0 ;;
            *) echo "无效选项: -$opt"; show_help; exit 1 ;;
        esac
    done
    [ "$PARALLEL" -lt 1 ] && PARALLEL=1

    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}      FPU asm-test 全量测试运行器${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    echo -e "${CYAN}[INFO]${NC} 测试源目录: $ASM_DIR"
    echo -e "${CYAN}[INFO]${NC} 并行数: $PARALLEL"
    echo -e "${CYAN}[INFO]${NC} 失败时继续: $KEEP_GOING"
    echo ""

    # 读取测试列表 (排序并去重)
    mapfile -t ALL_TESTS < <(collect_tests | sort -u)
    local total=${#ALL_TESTS[@]}

    echo -e "${CYAN}[INFO]${NC} 共发现 ${GREEN}$total${NC} 个 asm-test"
    echo ""

    if [ "$total" -eq 0 ]; then
        echo -e "${RED}[FAIL]${NC} 未发现任何测试!"
        exit 1
    fi

    echo -e "${YELLOW}[BUILD]${NC} 正在构建全部软件镜像..."
    set +e
    make -C "$SCRIPT_DIR/software" asm > "$BUILD_DIR/test-logs-software-build.log" 2>&1
    local sw_ret=$?
    set -e
    if [ "$sw_ret" -ne 0 ]; then
        echo -e "${RED}[FAIL]${NC} 软件镜像构建失败, 详情: $BUILD_DIR/test-logs-software-build.log"
        exit 1
    fi
    echo -e "${GREEN}[DONE]${NC} 软件镜像构建完成"
    echo ""

    # 创建结果临时文件
    local tmp_results
    tmp_results=$(mktemp)
    trap "rm -f '$tmp_results'" EXIT

    local start_time
    start_time=$(date +%s)

    if [ "$PARALLEL" -gt 1 ]; then
        # 并行模式
        echo -e "${YELLOW}[提示]${NC} 并行运行时建议使用 -v 查看实时输出"
        echo ""

        local running=0 idx=0
        for test_name in "${ALL_TESTS[@]}"; do
            # 等待空闲槽位
            while [ "$running" -ge "$PARALLEL" ]; do
                wait -n 2>/dev/null || true
                running=$((running - 1))
            done

            (
                run_test "$test_name" >> "$tmp_results"
            ) &
            running=$((running + 1))
            idx=$((idx + 1))
            printf "\r${BLUE}[PROG]${NC} 已启动 %d/%d 个测试..." "$idx" "$total"
        done

        wait
        printf "\r${BLUE}[PROG]${NC} 全部 %d 个测试已完成!%*s\n" "$total" 25 ""
    else
        # 顺序模式
        local idx=0 result ret
        for test_name in "${ALL_TESTS[@]}"; do
            idx=$((idx + 1))

            result=$(run_test "$test_name")
            echo "$result" >> "$tmp_results"

            ret=$(echo "$result" | awk '{print $2}')
            print_progress "$idx" "$total"

            if [ "$KEEP_GOING" = false ] && [ "$ret" -ne 0 ]; then
                echo ""
                echo -e "${RED}[停止]${NC} 测试 $test_name 失败, 且设置了 -K 选项, 停止运行"
                break
            fi
        done
        echo ""
    fi

    # 统计结果 (从临时文件, 反映实际运行的测试数)
    local passed=0 failed=0 tested=0
    local failed_tests=()
    while IFS=' ' read -r name ret _duration; do
        tested=$((tested + 1))
        if [ "$ret" -eq 0 ]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            failed_tests+=("$name")
        fi
    done < "$tmp_results"

    local end_time elapsed minutes seconds pass_rate
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    pass_rate=$(calc_pct "$passed" "$tested")

    echo ""
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}            测试结果汇总${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    echo -e "  测试总数:   ${CYAN}$total${NC}"
    echo -e "  已运行:     ${CYAN}$tested${NC}"
    if [ "$tested" -lt "$total" ]; then
        echo -e "  未运行:     ${YELLOW}$((total - tested)) (提前停止)${NC}"
    fi
    echo -e "  ${GREEN}通过:       $passed${NC}"
    echo -e "  ${RED}失败:       $failed${NC}"
    echo -e "  通过率:     ${pass_rate}%"
    echo -e "  运行时间:   ${minutes}分${seconds}秒"
    echo ""

    # 按指令类型统计
    echo -e "${BLUE}--- 按指令类型统计 ---${NC}"
    local instr
    declare -A type_total type_passed type_failed
    while IFS=' ' read -r name ret _duration; do
        instr=$(get_instr_type "$name")
        type_total[$instr]=$(( ${type_total[$instr]:-0} + 1 ))
        if [ "$ret" -eq 0 ]; then
            type_passed[$instr]=$(( ${type_passed[$instr]:-0} + 1 ))
        else
            type_failed[$instr]=$(( ${type_failed[$instr]:-0} + 1 ))
        fi
    done < "$tmp_results"

    for instr in $(printf '%s\n' "${!type_total[@]}" | sort); do
        local t=${type_total[$instr]}
        local p=${type_passed[$instr]:-0}
        local f=${type_failed[$instr]:-0}
        local tpct
        tpct=$(calc_pct "$p" "$t")
        if [ "$f" -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} $instr: $p/$t 通过 ($tpct%)"
        else
            echo -e "  ${RED}✗${NC} $instr: $p/$t 通过 ($tpct%) ${RED}($f 失败)${NC}"
        fi
    done

    echo ""

    # 失败测试列表
    if [ ${#failed_tests[@]} -gt 0 ]; then
        echo -e "${RED}--- 失败的测试 ---${NC}"
        local t
        for t in "${failed_tests[@]}"; do
            echo -e "  ${RED}✗${NC} $t"
            if [ -f "$LOG_DIR/$t.log" ]; then
                echo -e "    日志: $LOG_DIR/$t.log"
            fi
        done
        echo ""
    fi

    # 保存结果到文件
    if [ -n "$RESULT_FILE" ]; then
        {
            echo "FPU asm-test 测试结果报告"
            echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "========================"
            echo ""
            echo "测试总数: $total"
            echo "已运行: $tested"
            echo "通过: $passed"
            echo "失败: $failed"
            echo "通过率: ${pass_rate}%"
            echo "运行时间: ${minutes}分${seconds}秒"
            echo ""
            echo "--- 失败的测试 ---"
            for t in "${failed_tests[@]}"; do
                echo "  $t"
            done
            echo ""
            echo "--- 详细结果 ---"
            echo "测试名称 | 结果 | 耗时(ms)"
            while IFS=' ' read -r name ret duration; do
                if [ "$ret" -eq 0 ]; then
                    echo "$name | 通过 | $duration"
                else
                    echo "$name | 失败 | $duration"
                fi
            done < "$tmp_results"
        } > "$RESULT_FILE"
        echo -e "${CYAN}[INFO]${NC} 结果已保存到: $RESULT_FILE"
    fi

    echo -e "${BLUE}================================================${NC}"

    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"