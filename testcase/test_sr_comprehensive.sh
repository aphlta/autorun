#!/bin/bash

# SR 综合功能测试脚本
# 测试所有核心功能：基本匹配、模糊匹配、各种选项、边界情况

echo "=== SR 综合功能测试 ==="

# 测试环境设置
TEST_DIR="/tmp/sr_test_$(date +%s)"
TEST_DATA="$TEST_DIR/.sr"
TEST_LOG="$TEST_DIR/test.log"

# 清理函数
cleanup() {
    rm -rf "$TEST_DIR"
}

# 错误处理
set -e
trap cleanup EXIT

# 创建测试环境
mkdir -p "$TEST_DIR"
echo "测试目录: $TEST_DIR"

# 创建测试目录
mkdir -p "$TEST_DIR/project1" "$TEST_DIR/project2" "$TEST_DIR/backend" "$TEST_DIR/frontend" "$TEST_DIR/scripts"

# 创建测试数据（使用实际存在的目录）
cat > "$TEST_DATA" << EOF
$TEST_DIR/project1|git status|10|1234567890
$TEST_DIR/project1|git commit -m "fix bug"|8|1234567891
$TEST_DIR/project1|git push origin main|5|1234567892
$TEST_DIR/project2|npm install|12|1234567893
$TEST_DIR/project2|npm run build|7|1234567894
$TEST_DIR/project2|npm test|4|1234567895
$TEST_DIR/backend|docker build -t api .|6|1234567896
$TEST_DIR/backend|docker run -p 8080:8080 api|3|1234567897
$TEST_DIR/frontend|python manage.py runserver|9|1234567898
$TEST_DIR/frontend|python -m pytest tests/|5|1234567899
$TEST_DIR/scripts|ls -la|2|1234567900
$TEST_DIR/scripts|cd ..|1|1234567901
EOF

echo "✓ 测试数据已创建"
echo ""

# 测试计数器
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# 测试函数
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_pattern="$3"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "测试 $TEST_COUNT: $test_name"
    echo "命令: $command"
    
    # 执行命令并捕获输出
    local output
    if output=$(eval "$command" 2>&1); then
        if echo "$output" | grep -q "$expected_pattern"; then
            echo "✓ 通过"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "✗ 失败 - 输出不匹配期望模式: $expected_pattern"
            echo "实际输出: $output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "✗ 失败 - 命令执行错误"
        echo "错误输出: $output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
}

# 1. 基本功能测试
echo "=== 1. 基本功能测试 ==="

# 精确匹配
run_test "精确匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git status\"'" \
    "git status"

# 部分匹配
run_test "部分匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git\"'" \
    "git status"

# 不同命令匹配
run_test "NPM命令匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"npm\"'" \
    "npm install"

# 2. 模糊匹配测试
echo "=== 2. 模糊匹配测试 ==="

# 拼写错误
run_test "拼写错误容错" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git statu\"'" \
    "git status"

# 缺少字母
run_test "缺少字母匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git stat\"'" \
    "git status"

# 多余字母
run_test "多余字母匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git statuss\"'" \
    "git status"

# 复杂模糊匹配
run_test "复杂模糊匹配" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"docker bild\"'" \
    "docker build"

# 3. 选项测试
echo "=== 3. 选项测试 ==="

# 列表模式
run_test "列表模式(-l)" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -l \"git\"'" \
    "git status"

# 频率排序
run_test "频率排序(-r)" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -r -p \"git\"'" \
    "git status"

# 时间排序
run_test "时间排序(-t)" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -t -p \"git\"'" \
    "git"

# 4. 边界情况测试
echo "=== 4. 边界情况测试 ==="

# 空查询（应该返回最频繁的命令）
run_test "空查询处理" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"\"'" \
    "npm install"

# 不存在的命令（应该返回最频繁的命令）
run_test "不存在命令" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"nonexistent\"'" \
    "npm install"

# 特殊字符
run_test "特殊字符处理" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"python\"'" \
    "python"

# 5. 路径过滤测试
echo "=== 5. 路径过滤测试 ==="

# 绝对路径过滤
run_test "绝对路径过滤" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"git\" \"$TEST_DIR/project1\"'" \
    "git status"

# 相对路径过滤
run_test "路径子串过滤" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"npm\" \"project2\"'" \
    "npm install"

# 6. 帮助和调试测试
echo "=== 6. 帮助和调试测试 ==="

# 帮助信息
run_test "帮助信息" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -h'" \
    "show help"

# 调试模式
run_test "调试模式" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -d -p \"git\"'" \
    "git"

# 测试结果统计
echo "=== 测试结果统计 ==="
echo "总测试数: $TEST_COUNT"
echo "通过: $PASS_COUNT"
echo "失败: $FAIL_COUNT"
echo "成功率: $(( PASS_COUNT * 100 / TEST_COUNT ))%"

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 所有测试通过！"
    exit 0
else
    echo "❌ 有 $FAIL_COUNT 个测试失败"
    exit 1
fi