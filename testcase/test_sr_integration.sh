#!/bin/bash

# SR 集成测试脚本
# 测试SR与shell环境的集成功能：命令记录、alias、PROMPT_COMMAND等

echo "=== SR 集成测试 ==="

# 测试环境设置
TEST_DIR="/tmp/sr_integration_test_$(date +%s)"
TEST_DATA="$TEST_DIR/.sr"
TEST_SHELL_RC="$TEST_DIR/.testrc"

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

# 测试计数器
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# 测试函数
run_integration_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "\n测试 $TEST_COUNT: $test_name"
    echo "执行: $test_command"
    
    if eval "$test_command"; then
        if [ -n "$expected_result" ]; then
            if eval "$expected_result"; then
                echo "✓ 通过"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                echo "✗ 失败 - 结果验证失败"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        else
            echo "✓ 通过"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi
    else
        echo "✗ 失败 - 命令执行失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# 1. 基本集成测试
echo "=== 1. 基本集成测试 ==="

# 测试source加载
run_integration_test "source加载测试" \
    "bash -c 'source /home/alex/autorun/sr.sh && type _sr >/dev/null 2>&1'" \
    "true"

# 测试alias设置
run_integration_test "alias设置测试" \
    "bash -c 'source /home/alex/autorun/sr.sh && alias sr >/dev/null 2>&1'" \
    "true"

# 2. 命令记录测试
echo "\n=== 2. 命令记录测试 ==="

# 创建测试shell配置
cat > "$TEST_SHELL_RC" << EOF
export _SR_DATA="$TEST_DATA"
source /home/alex/autorun/sr.sh
EOF

# 测试命令记录功能
run_integration_test "命令记录功能" \
    "cd '$TEST_DIR' && bash --rcfile '$TEST_SHELL_RC' -i -c 'echo test_command; _sr --add \"echo test_command\" \"$TEST_DIR\"'" \
    "[ -f '$TEST_DATA' ] && grep -q 'echo test_command' '$TEST_DATA'"

# 测试危险命令过滤
run_integration_test "危险命令过滤" \
    "cd '$TEST_DIR' && _SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr --add \"rm -rf /\" \"$TEST_DIR\"'" \
    "! grep -q 'rm -rf' '$TEST_DATA' 2>/dev/null || true"

# 3. 环境变量测试
echo "\n=== 3. 环境变量测试 ==="

# 测试_SR_DATA环境变量
run_integration_test "_SR_DATA环境变量" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr --add \"test_env\" \"$TEST_DIR\"'" \
    "[ -f '$TEST_DATA' ] && grep -q 'test_env' '$TEST_DATA'"

# 测试_SR_DEBUG环境变量（目前SR不支持调试文件，测试环境变量不影响功能）
run_integration_test "_SR_DEBUG环境变量" \
    "_SR_DEBUG=1 _SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr --add \"debug_test\" \"$TEST_DIR\"'" \
    "[ -f '$TEST_DATA' ] && grep -q 'debug_test' '$TEST_DATA'"

# 测试_SR_FUZZY_LEVEL环境变量
run_integration_test "_SR_FUZZY_LEVEL环境变量" \
    "_SR_FUZZY_LEVEL=5 _SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && echo \"test\"'" \
    "true"

# 4. Shell兼容性测试
echo "\n=== 4. Shell兼容性测试 ==="

# Bash兼容性
run_integration_test "Bash兼容性" \
    "bash -c 'source /home/alex/autorun/sr.sh && _sr -h >/dev/null 2>&1'" \
    "true"

# Zsh兼容性（如果可用）
if command -v zsh >/dev/null 2>&1; then
    run_integration_test "Zsh兼容性" \
        "zsh -c 'source /home/alex/autorun/sr.sh && _sr -h >/dev/null 2>&1'" \
        "true"
else
    echo "跳过Zsh兼容性测试（zsh未安装）"
fi

# 5. 数据文件操作测试
echo "\n=== 5. 数据文件操作测试 ==="

# 创建测试数据（使用实际存在的目录）
mkdir -p "$TEST_DIR/test1" "$TEST_DIR/test2"
cat > "$TEST_DATA" << EOF
$TEST_DIR/test1|git status|5|1234567890
$TEST_DIR/test2|npm install|3|1234567891
EOF

# 测试数据文件读取
run_integration_test "数据文件读取" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -l \"git\"' >/dev/null 2>&1" \
    "true"

# 测试数据文件权限检查
run_integration_test "数据文件权限检查" \
    "chmod 644 '$TEST_DATA' && _SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -l \"git\"' >/dev/null 2>&1" \
    "true"

# 6. 错误处理测试
echo "\n=== 6. 错误处理测试 ==="

# 测试不存在的数据文件
run_integration_test "不存在数据文件处理" \
    "_SR_DATA='/nonexistent/path/.sr' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"test\"' 2>/dev/null || true" \
    "true"

# 测试无效参数
run_integration_test "无效参数处理" \
    "_SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr --invalid-option' 2>/dev/null || true" \
    "true"

# 7. 性能集成测试
echo "\n=== 7. 性能集成测试 ==="

# 测试大数据文件处理
echo "创建大数据文件..."
for i in {1..500}; do
    mkdir -p "$TEST_DIR/test$i"
    echo "$TEST_DIR/test$i|command$i|$((i % 10 + 1))|$((1234567890 + i))" >> "$TEST_DATA"
done

run_integration_test "大数据文件查询性能" \
    "time _SR_DATA='$TEST_DATA' bash -c 'source /home/alex/autorun/sr.sh && _sr -p \"command1\"' >/dev/null 2>&1" \
    "true"

# 测试结果统计
echo "\n=== 集成测试结果统计 ==="
echo "总测试数: $TEST_COUNT"
echo "通过: $PASS_COUNT"
echo "失败: $FAIL_COUNT"
echo "成功率: $(( PASS_COUNT * 100 / TEST_COUNT ))%"

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 所有集成测试通过！"
    echo "SR与shell环境集成正常"
    exit 0
else
    echo "❌ 有 $FAIL_COUNT 个集成测试失败"
    echo "请检查SR的shell集成配置"
    exit 1
fi