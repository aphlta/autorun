#!/bin/bash

# SR 性能测试脚本
# 测试大数据量下的查询性能和内存使用

echo "=== SR 性能测试 ==="

# 测试环境设置
TEST_DIR="/tmp/sr_perf_test_$(date +%s)"
TEST_DATA="$TEST_DIR/.sr"

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

# 生成大量测试数据
echo "生成测试数据..."
generate_test_data() {
    local count=$1
    local file="$2"
    
    # 命令模板
    local commands=(
        "git status"
        "git commit -m 'update'"
        "git push origin main"
        "npm install"
        "npm run build"
        "npm test"
        "docker build -t app ."
        "docker run -p 3000:3000 app"
        "python manage.py runserver"
        "python -m pytest"
        "ls -la"
        "cd .."
        "make build"
        "make test"
        "cargo build"
        "cargo test"
        "go build"
        "go test"
        "mvn compile"
        "mvn test"
    )
    
    # 路径模板
    local paths=(
        "/home/project1"
        "/home/project2"
        "/home/backend"
        "/home/frontend"
        "/home/scripts"
        "/opt/app"
        "/var/www"
        "/usr/local/src"
        "/tmp/build"
        "/workspace/main"
    )
    
    > "$file"  # 清空文件
    
    for ((i=1; i<=count; i++)); do
        local cmd_idx=$((RANDOM % ${#commands[@]}))
        local path_idx=$((RANDOM % ${#paths[@]}))
        local rank=$((RANDOM % 20 + 1))
        local timestamp=$((1234567890 + RANDOM % 1000000))
        
        echo "${paths[$path_idx]}|${commands[$cmd_idx]}|$rank|$timestamp" >> "$file"
    done
}

# 性能测试函数
performance_test() {
    local data_size=$1
    local query="$2"
    local description="$3"
    
    echo "\n=== $description (数据量: $data_size) ==="
    
    # 生成测试数据
    echo "生成 $data_size 条记录..."
    local start_time=$(date +%s.%N)
    generate_test_data $data_size "$TEST_DATA"
    local gen_time=$(date +%s.%N)
    local gen_duration=$(echo "$gen_time - $start_time" | bc -l)
    echo "数据生成耗时: ${gen_duration}s"
    
    # 执行查询测试
    echo "执行查询: '$query'"
    local query_start=$(date +%s.%N)
    local result
    result=$(_SR_DATA="$TEST_DATA" bash -c "source /home/alex/autorun/sr.sh && _sr -p '$query'" 2>&1)
    local query_end=$(date +%s.%N)
    local query_duration=$(echo "$query_end - $query_start" | bc -l)
    
    echo "查询耗时: ${query_duration}s"
    echo "查询结果: $(echo "$result" | head -1)"
    
    # 内存使用情况
    local file_size=$(du -h "$TEST_DATA" | cut -f1)
    echo "数据文件大小: $file_size"
    
    # 性能评估
    local records_per_sec=$(echo "scale=2; $data_size / $query_duration" | bc -l)
    echo "查询性能: ${records_per_sec} 记录/秒"
}

# 检查依赖
if ! command -v bc &> /dev/null; then
    echo "警告: bc 命令未找到，无法计算精确时间"
    # 使用简化的时间计算
    performance_test() {
        local data_size=$1
        local query="$2"
        local description="$3"
        
        echo "\n=== $description (数据量: $data_size) ==="
        
        echo "生成 $data_size 条记录..."
        generate_test_data $data_size "$TEST_DATA"
        
        echo "执行查询: '$query'"
        local start_time=$(date +%s)
        local result
        result=$(_SR_DATA="$TEST_DATA" bash -c "source /home/alex/autorun/sr.sh && _sr -p '$query'" 2>&1)
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo "查询耗时: ${duration}s"
        echo "查询结果: $(echo "$result" | head -1)"
        
        local file_size=$(du -h "$TEST_DATA" | cut -f1)
        echo "数据文件大小: $file_size"
    }
fi

# 执行性能测试
echo "开始性能测试..."

# 小数据量测试
performance_test 100 "git status" "小数据量测试"

# 中等数据量测试
performance_test 1000 "git status" "中等数据量测试"

# 大数据量测试
performance_test 5000 "git status" "大数据量测试"

# 模糊匹配性能测试
performance_test 1000 "git statu" "模糊匹配性能测试"

# 复杂查询性能测试
performance_test 1000 "docker bild" "复杂模糊匹配性能测试"

echo "\n=== 性能测试完成 ==="
echo "\n性能建议:"
echo "- 小于1000条记录: 查询应在0.1秒内完成"
echo "- 1000-5000条记录: 查询应在0.5秒内完成"
echo "- 大于5000条记录: 考虑定期清理旧数据"
echo "- 模糊匹配比精确匹配稍慢，但应保持在可接受范围内"