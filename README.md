# SR - Smart Run

一个类似z.sh的命令历史记录和自动跳转工具，可以记录您执行的所有命令及其执行目录，并支持智能匹配跳转。

## 功能特性

1. **命令记录**: 自动记录所有命令及其执行目录
2. **智能匹配**: 基于frecent算法（频率+最近性）进行匹配
3. **模糊搜索**: 支持部分命令匹配
4. **自动跳转**: 快速跳转到最匹配的目录

## 安装

1. 将sr.sh放到合适的位置（如~/sr.sh）
2. 在您的.bashrc或.zshrc中添加：
   ```bash
   source ~/sr.sh
   ```
3. 重新加载shell配置或重启终端

## 使用方法

### 基本用法
```bash
# 跳转到最常运行包含'git'命令的目录
sr git

# 跳转到最常运行包含'npm install'命令的目录  
sr npm install

# 部分匹配也可以
sr npm
sr docker
sr make
```

### 选项
```bash
sr -l git      # 列出所有匹配项而不跳转
sr -r git      # 按频率排序跳转
sr -t git      # 按时间排序跳转
sr -h          # 显示帮助
```

## 配置选项

在.bashrc/.zshrc中设置以下变量来自定义行为：

```bash
# 更改数据文件位置（默认~/.sr）
export _SR_DATA="$HOME/.command_history"

# 更改最大分数以更快老化条目（默认9000）
export _SR_MAX_SCORE=5000

# 排除某些目录
export _SR_EXCLUDE_DIRS=("/tmp" "/var")

# 禁用自动命令记录（如果您要手动处理）
export _SR_NO_PROMPT_COMMAND=1
```

## 工作原理

1. **记录阶段**: 每次执行命令后，sr会记录命令内容和当前目录
2. **匹配阶段**: 使用frecent算法计算每个目录的分数（频率×时间衰减）
3. **跳转阶段**: 自动cd到分数最高的目录

## 数据格式

数据存储在~/.sr文件中，格式为：
```
目录|命令|频率分数|时间戳
/home/user/project|git commit|5.2|1640995200
/home/user/docs|vim README.md|3.1|1640995100
```

## 示例场景

假设您经常在不同项目目录中运行git命令：
- `/home/user/project1` - 运行了20次git命令
- `/home/user/project2` - 运行了5次git命令  
- `/home/user/docs` - 运行了2次git命令

当您运行`sr git`时，系统会自动跳转到`/home/user/project1`，因为这是您最频繁运行git命令的地方。

## 测试和验证

安装完成后，您可以通过以下步骤测试功能：

1. 在不同目录中运行一些命令：
   ```bash
   cd ~/project1
   git status
   git log
   
   cd ~/project2  
   npm install
   npm test
   
   cd ~/docs
   vim README.md
   ```

2. 查看记录的数据：
   ```bash
   cat ~/.sr
   ```

3. 测试跳转功能：
   ```bash
   sr git     # 应该跳转到最常用git的目录
   sr npm     # 应该跳转到最常用npm的目录
   sr -l vim  # 列出所有使用vim的目录
   ```

## 故障排除

### 常见问题

1. **命令没有被记录**
   - 检查是否正确source了sr.sh
   - 确认`_SR_NO_PROMPT_COMMAND`没有被设置
   - 重启终端或重新source配置文件

2. **跳转不工作**
   - 确认目标目录仍然存在
   - 检查~/.sr文件是否有正确的权限
   - 使用`sr -l`查看匹配结果

3. **性能问题**
   - 如果数据文件过大，可以降低`_SR_MAX_SCORE`值
   - 定期清理不存在的目录记录

### 调试模式

如果需要调试，可以手动运行命令查看详细信息：
```bash
# 手动添加记录
_sr --add "git status" "/home/user/project"

# 查看匹配过程
sr -l git
```

## 与其他工具的比较

| 特性 | sr.sh | z.sh | autojump |
|------|-------|------|----------|
| 基于命令匹配 | ✅ | ❌ | ❌ |
| 基于目录访问 | ❌ | ✅ | ✅ |
| frecent算法 | ✅ | ✅ | ✅ |
| 模糊匹配 | ✅ | ✅ | ✅ |
| 命令历史记录 | ✅ | ❌ | ❌ |

## 许可证

MIT License - 您可以自由使用、修改和分发此工具。

## 贡献

欢迎提交bug报告、功能请求或代码贡献！
