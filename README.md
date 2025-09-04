# SR - Smart Run

一个类似z.sh的命令历史记录和自动跳转工具，可以记录您执行的所有命令及其执行目录，并支持智能匹配跳转。

## 功能特性

1. **命令记录**: 自动记录所有命令及其执行目录
2. **智能匹配**: 基于frecent算法（频率+最近性）进行匹配
3. **模糊搜索**: 支持部分命令匹配
4. **自动跳转**: 快速跳转到最匹配的目录
5. **命令执行**: 支持跳转后自动执行匹配的命令
6. **调试模式**: 提供详细的调试日志和交互式命令确认
7. **安全过滤**: 自动过滤危险命令，支持自定义忽略列表

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
sr git         # 跳转到目录并执行匹配的命令（默认行为）
sr -j git      # 只跳转到目录，不执行命令
sr -p git      # 只打印目录和命令，不跳转也不执行
sr -l git      # 列出所有匹配项而不跳转
sr -r git      # 按频率排序跳转
sr -t git      # 按时间排序跳转
sr -d git      # 调试模式：执行前显示命令并等待确认
sr --debug-on  # 启用全局调试模式（持久化）
sr --debug-off # 禁用全局调试模式
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

# 忽略特定命令（空格分隔的命令列表）
export _SR_IGNORE_COMMANDS="vim nano emacs"

# 启用全局调试模式（持久化直到禁用）
export _SR_DEBUG=1

# 更改调试日志文件路径（默认${_SR_DATA}.debug）
export _SR_DEBUG_LOG="$HOME/.sr_debug.log"

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

### 基本跳转场景
假设您经常在不同项目目录中运行git命令：
- `/home/user/project1` - 运行了20次git命令
- `/home/user/project2` - 运行了5次git命令  
- `/home/user/docs` - 运行了2次git命令

当您运行`sr git`时，系统会自动跳转到`/home/user/project1`，因为这是您最频繁运行git命令的地方。

### 命令执行场景
```bash
# 跳转到最常用npm的目录并执行npm install（默认行为）
sr npm install

# 只跳转到目录，不执行命令
sr -j npm install

# 只打印目录和命令信息，不跳转也不执行
sr -p git commit

# 调试模式：显示将要执行的命令并等待确认
sr -d git commit
```

### 调试场景
```bash
# 启用调试模式查看详细过程
sr --debug-on
sr git  # 会在日志中记录搜索和跳转过程

# 查看调试日志了解匹配过程
cat ~/.sr.debug
```

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

4. 测试新功能：
   ```bash
   # 测试默认执行模式
   sr git status
   
   # 测试只跳转模式
   sr -j npm install
   
   # 测试只打印模式
   sr -p docker build
   
   # 启用调试模式
   sr --debug-on
   
   # 测试交互式调试
   sr -d git status
   
   # 查看调试日志
   cat ~/.sr.debug
   
   # 禁用调试模式
   sr --debug-off
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

sr.sh提供了强大的调试功能来帮助您了解工具的工作原理和排查问题：

#### 启用调试模式
```bash
# 启用全局调试模式（持久化）
sr --debug-on

# 禁用全局调试模式
sr --debug-off

# 临时调试模式（仅当次执行）
sr -d git
```

#### 调试日志内容
调试模式会记录以下信息到日志文件（默认`~/.sr.debug`）：
- **INIT**: 调试模式初始化
- **CMD_RECORD**: 命令记录过程
- **SEARCH**: 搜索匹配过程
- **JUMP**: 目录跳转操作
- **EXEC_PREP/EXEC_CONFIRM/EXEC_CANCEL/EXEC_AUTO/EXEC_DONE**: 命令执行过程
- **SEARCH_FAIL**: 搜索失败信息
- **DATA_SNAPSHOT**: 数据文件快照

#### 查看调试日志
```bash
# 查看调试日志
cat ~/.sr.debug

# 实时监控调试日志
tail -f ~/.sr.debug

# 查看最近的调试信息
tail -20 ~/.sr.debug
```

#### 手动调试命令
```bash
# 手动添加记录
_sr --add "git status" "/home/user/project"

# 查看匹配过程
sr -l git

# 调试模式执行命令
sr -d git commit

# 只打印命令信息
sr -p git commit
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
