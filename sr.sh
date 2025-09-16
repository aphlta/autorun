#!/bin/bash
# sr.sh - 智能命令历史记录与目录跳转工具
# Copyright (c) 2024. Licensed under MIT license.
# 使用原子更新机制防止并发冲突的优化版本

# 功能说明：
# 自动记录你实际使用的命令及其执行目录，建立智能跳转列表
# 支持模糊匹配快速跳转到最常用的工作目录
#
# 安装方法：
#     在 .bashrc/.zshrc 中添加：
#         source /path/to/sr.sh
#     使用一段时间后数据库会自动建立
#     然后可以使用：sr 'partial_command' 跳转到相关目录
#
# 配置选项：
#     _SR_DATA_FILE     - 数据文件路径 (默认 ~/.sr_history)
#     _SR_MAX_SCORE     - 最大评分，越小条目老化越快 (默认 9000)
#     _SR_MAX_ENTRIES   - 最大条目数 (默认 1000)
#     _SR_EXCLUDE_DIRS  - 排除目录数组
#     _SR_IGNORE_COMMANDS - 忽略命令列表 (空格分隔)
#     _SR_DEBUG         - 调试模式开关 (设为1启用)
#     _SR_DEBUG_LOG     - 调试日志文件路径
#     注意：危险命令 (rm, sudo等) 会自动忽略以确保安全
#
# 使用方法：
#     sr foo        # 跳转到运行过包含foo的命令的最常用目录
#     sr -l foo     # 列出匹配项而不跳转
#     sr -r foo     # 跳转到评分最高的匹配目录
#     sr -t foo     # 跳转到最近访问的匹配目录
#     sr -e foo     # 跳转并执行匹配的命令
#     sr -d -e foo  # 调试模式：显示命令并等待确认
#     sr --debug-on # 启用全局调试模式
#     sr --debug-off # 关闭全局调试模式
#     sr -h         # 显示帮助信息

# 配置变量初始化
_SR_DATA_FILE="${_SR_DATA:-$HOME/.sr_history}"    # 数据文件路径
_SR_MAX_SCORE="${_SR_MAX_SCORE:-9000}"            # 最大评分阈值
_SR_MAX_ENTRIES="${_SR_MAX_ENTRIES:-1000}"        # 最大条目数限制
_SR_DEBUG_LOG="${_SR_DEBUG_LOG:-${_SR_DATA_FILE}.debug}"  # 调试日志文件路径

[ -d "${_SR_DATA:-$HOME/.sr}" ] && {
    echo "ERROR: sr.sh's datafile (${_SR_DATA:-$HOME/.sr}) is a directory."
}

# 原子文件更新函数 - 防止并发写入冲突
# 参数: $1=目标文件路径, $2=新内容
# 返回: 0=成功, 1=失败
_sr_atomic_update() {
    local datafile="$1"
    local new_content="$2"
    local tempfile="$datafile.$RANDOM"
    
    _sr_debug_log "ATOMIC" "Starting atomic update with tempfile: $tempfile"
    
    # Write new content to temporary file
    echo -e "$new_content" > "$tempfile" 2>/dev/null
    
    # Atomic move to replace original file
    if [ $? -eq 0 ]; then
        if \env mv "$tempfile" "$datafile" 2>/dev/null; then
            _sr_debug_log "ATOMIC" "Successfully updated $datafile"
            return 0
        else
            _sr_debug_log "ATOMIC" "Failed to move tempfile to $datafile"
            \env rm -f "$tempfile" 2>/dev/null
            return 1
        fi
    else
        _sr_debug_log "ATOMIC" "Failed to write to tempfile: $tempfile"
        \env rm -f "$tempfile" 2>/dev/null
        return 1
    fi
}

# 清理过期条目函数 - 保持数据文件大小合理
# 当条目数超过最大限制时，保留最近的75%条目
_sr_cleanup_old_entries() {
    [ ! -f "$_SR_DATA_FILE" ] && return 0
    
    local max_entries="${_SR_MAX_ENTRIES:-1000}"
    local current_count=$(wc -l < "$_SR_DATA_FILE" 2>/dev/null || echo 0)
    
    if [ "$current_count" -le "$max_entries" ]; then
        return 0
    fi
    
    _sr_debug_log "CLEANUP" "Starting cleanup: $current_count entries, max: $max_entries"
    
    # Keep only the most recent entries
    local keep_count=$((max_entries * 3 / 4))  # Keep 75% of max
    local new_data=$(tail -n "$keep_count" "$_SR_DATA_FILE" 2>/dev/null)
    
    if [ -n "$new_data" ]; then
        if _sr_atomic_update "$_SR_DATA_FILE" "$new_data"; then
            local new_count=$(echo "$new_data" | wc -l 2>/dev/null || echo 0)
            _sr_debug_log "CLEANUP" "Cleanup completed: $new_count entries remaining"
            return 0
        else
            _sr_debug_log "CLEANUP" "Failed to update data file during cleanup"
            return 1
        fi
    else
        _sr_debug_log "CLEANUP" "No data to keep after cleanup"
        return 1
    fi
}

# 添加命令记录函数 - 记录命令执行信息到数据文件
# 参数: $1=命令, $2=执行目录
# 数据格式: 目录|命令|评分|时间
# 使用原子更新确保数据一致性
_sr_add_command() {
    local cmd="$1"
    local dir="$2"
    
    [ -z "$cmd" ] || [ -z "$dir" ] && return 1
    
    # Create data directory if it doesn't exist
    mkdir -p "$(dirname "$_SR_DATA_FILE")"
    
    # Use the same logic as the main _sr function for consistency
    local datafile="${_SR_DATA:-$HOME/.sr}"
    local tempfile="$datafile.$RANDOM"
    local score=${_SR_MAX_SCORE:-9000}
    local key="$dir|$cmd"
    local now=$(date +%s)
    
    _sr_debug_log "ADD" "Adding command: '$cmd' in directory: '$dir'"
    
    # Process existing data and update scores
    {
        if [ -f "$datafile" ]; then
            while IFS='|' read -r entry_dir entry_cmd entry_score entry_time; do
                [ -d "$entry_dir" ] || continue  # Skip non-existent directories
                local entry_key="$entry_dir|$entry_cmd"
                if [ "$entry_key" = "$key" ]; then
                    # Increment score for existing entry
                    local new_score=$(awk "BEGIN {printf \"%.2f\", $entry_score + 1}")
                    echo "$entry_dir|$entry_cmd|$new_score|$now"
                else
                    # Keep existing entry
                    echo "$entry_dir|$entry_cmd|$entry_score|$entry_time"
                fi
            done < "$datafile"
        fi
        
        # Add new entry if it doesn't exist
        if [ -f "$datafile" ]; then
            if ! grep -q "^$dir|$cmd|" "$datafile" 2>/dev/null; then
                echo "$dir|$cmd|1|$now"
            fi
        else
            echo "$dir|$cmd|1|$now"
        fi
    } > "$tempfile"
    
    # Atomic move to replace original file
    if mv "$tempfile" "$datafile" 2>/dev/null; then
        _sr_debug_log "ADD" "Successfully added command: '$cmd' in directory: '$dir'"
        return 0
    else
        _sr_debug_log "ADD" "Failed to update data file atomically"
        rm -f "$tempfile" 2>/dev/null
        return 1
    fi
}

# 调试日志函数 - 记录调试信息到日志文件
# 参数: $1=日志类型, $2+=日志消息
# 只有在调试模式启用时才记录日志
_sr_debug_log() {
    # Only log if debug mode is enabled
    [ "$_SR_DEBUG" != "1" ] && return
    
    local debug_file="${_SR_DEBUG_LOG:-${_SR_DATA:-$HOME/.sr}.debug}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_type="$1"
    shift
    local message="$*"
    
    # Create debug log entry (with basic locking to prevent log corruption)
    local log_lock="${debug_file}.lock"
    local log_waited=0
    while [ $log_waited -lt 10 ]; do
        if (set -C; echo $$ > "$log_lock") 2>/dev/null; then
            echo "[$timestamp] [$log_type] [PID:$$] $message" >> "$debug_file"
            rm -f "$log_lock"
            break
        fi
        sleep 0.01
        log_waited=$((log_waited + 1))
    done
    
    # If this is a data snapshot request, append current _SR_DATA content
    if [ "$log_type" = "DATA_SNAPSHOT" ]; then
        local datafile="${_SR_DATA:-$HOME/.sr}"
        echo "[$timestamp] [DATA_CONTENT] [PID:$$] === Current _SR_DATA file content ===" >> "$debug_file"
        if [ -f "$datafile" ]; then
            cat "$datafile" >> "$debug_file"
        else
            echo "[$timestamp] [DATA_CONTENT] [PID:$$] _SR_DATA file does not exist" >> "$debug_file"
        fi
        echo "[$timestamp] [DATA_CONTENT] [PID:$$] === End of _SR_DATA content ===" >> "$debug_file"
    fi
}

_sr() {
    local datafile="${_SR_DATA:-$HOME/.sr}"
    
    # if symlink, dereference
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")
    
    # bail if we don't own ~/.sr
    [ -f "$datafile" -a ! -O "$datafile" ] && return
    
    _sr_entries() {
        [ -f "$datafile" ] || return
        
        local line
        while read line; do
            # only count existing directories
            local dir="${line%%|*}"
            [ -d "$dir" ] && echo "$line"
        done < "$datafile"
        return 0
    }
    
    # add entries
    if [ "$1" = "--add" ]; then
        shift
        local cmd="$1"
        local dir="$2"
        
        # Clean up command: remove newlines and extra spaces
        cmd="$(echo "$cmd" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
        
        # skip empty commands or basic navigation
        [ -z "$cmd" ] && return
        case "$cmd" in
            ll|ll\ *|z|z\ *|cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
        esac
        
        # Default dangerous commands blacklist
        local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck df du"
        
        # Check against dangerous commands (only check base command, not parameters)
        local cmd_base="$(echo "$cmd" | awk '{print $1}')"
        for dangerous in $dangerous_commands; do
            [ "$cmd_base" = "$dangerous" ] && return
        done
        
        # Check against user-defined ignored commands (only check base command)
        if [ -n "$_SR_IGNORE_COMMANDS" ]; then
            for ignore_cmd in $_SR_IGNORE_COMMANDS; do
                [ "$cmd_base" = "$ignore_cmd" ] && return
            done
        fi
        
        # don't track excluded directories
        if [ ${#_SR_EXCLUDE_DIRS[@]} -gt 0 ]; then
            local exclude
            for exclude in "${_SR_EXCLUDE_DIRS[@]}"; do
                case "$dir" in "$exclude"*) return;; esac
            done
        fi
        
        # Use the dedicated add command function
        _sr_add_command "$cmd" "$dir"
        
    else
        # Handle global debug mode commands first
        case "$1" in
            --debug-on)
                export _SR_DEBUG=1
                # Initialize debug log file
                local debug_file="${_SR_DEBUG_LOG:-${_SR_DATA:-$HOME/.sr}.debug}"
                echo "=== SR Debug Session Started at $(date) ===" > "$debug_file"
                _sr_debug_log "INIT" "Debug mode enabled, logging to: $debug_file"
                _sr_debug_log "DATA_SNAPSHOT" "Initial state when debug mode enabled"
                echo "Global debug mode enabled. Use 'sr --debug-off' to disable."
                echo "Debug log file: $debug_file"
                return;;
            --debug-off)
                unset _SR_DEBUG
                echo "Global debug mode disabled."
                return;;
        esac
        
        # search and jump (rest of the original sr function remains the same)
        local echo fnd last list opt typ path_filter execute_cmd debug_mode print_only
        execute_cmd=1  # Default to execute mode
        print_only=0   # Default to not print-only mode
        on_keyword_found=0  # Track if 'on' keyword is found
        # Check for global debug mode or local debug flag
        debug_mode=${_SR_DEBUG:-0}
        
        # Parse arguments - handle options first, then search terms
        local parsing_options=1
        while [ "$1" ]; do 
            if [ "$parsing_options" = "1" ]; then
                case "$1" in
                    -h|--help) 
                        echo "sr [-hlrtjpd] [command] [path]" >&2;
                        echo "  -h: show help" >&2;
                        echo "  -l: list matches (show directories and commands)" >&2;
                        echo "  -r: rank by frequency" >&2;
                        echo "  -t: rank by recency" >&2;
                        echo "  -j: jump only (don't execute command)" >&2;
                        echo "  -p: print command only (don't jump or execute)" >&2;
                        echo "  -d: debug mode - show command before execution and wait for confirmation" >&2;
                        echo "  --debug-on: enable global debug mode (persistent)" >&2;
                        echo "  --debug-off: disable global debug mode" >&2;
                        echo "Examples:" >&2;
                        echo "  sr vim           # jump to dir and execute vim command (default)" >&2;
                        echo "  sr -j vim        # jump to dir only, don't execute" >&2;
                        echo "  sr -p vim        # print command only, don't jump or execute" >&2;
                        echo "  sr -d vim        # debug mode: show command before execution" >&2;
                        echo "  sr --debug-on    # enable global debug mode" >&2;
                        echo "  sr --debug-off   # disable global debug mode" >&2;
                        echo "  sr vim /tmp      # jump to dir under /tmp where vim was used" >&2;
                        echo "  sr git work-dir  # jump to dir containing 'work-dir' where git was used" >&2;
                        echo "  sr git on work   # jump to dir containing 'work' where git was used (explicit syntax)" >&2;
                        echo "  sr 'git diff'    # jump to dir where 'git diff' command was used (exact match)" >&2;
                        echo "  sr -l git        # list all dirs and commands where git was used" >&2;
                        if [ "$_SR_DEBUG" = "1" ]; then
                            echo "" >&2;
                            echo "Global debug mode is currently ENABLED." >&2;
                        else
                            echo "" >&2;
                            echo "Global debug mode is currently DISABLED." >&2;
                        fi
                        return;;
                    -l) list=1;;
                    -r) typ="rank";;
                    -t) typ="recent";;
                    -j) execute_cmd=0;;  # Jump only, don't execute
                    -p|--print) print_only=1;;   # Print command only, don't jump or execute
                    -d) debug_mode=1;;   # Local debug mode override
                    /*) path_filter="$1"; parsing_options=0;; # Path argument, stop parsing options
                    -*) ;; # Unknown option, ignore
                    *) fnd="$fnd${fnd:+ }$1"; parsing_options=0;; # Non-option argument, stop parsing options
                esac
            else
                # No longer parsing options, everything is a search term or path
                case "$1" in
                    /*) path_filter="$1";; # Absolute path argument
                    on) 
                        # 'on' keyword: everything before 'on' is command, everything after is path
                        on_keyword_found=1
                        ;;
                    *) 
                        if [ "$on_keyword_found" = "1" ]; then
                            # After 'on' keyword, treat as path filter
                            path_filter="$1"
                        elif [ -n "$fnd" ] && [ "$on_keyword_found" != "1" ]; then
                            # Smart detection: check if this looks like a command subcommand
                            case "$1" in
                                # Common git subcommands
                                add|commit|push|pull|diff|status|log|branch|checkout|merge|rebase|clone|fetch|reset|tag|stash|show|config|remote|init)
                                    fnd="$fnd $1"  # Treat as part of command
                                    ;;
                                # Common other subcommands
                                install|update|upgrade|remove|list|search|info|help|version|start|stop|restart|enable|disable|build|test|run|deploy)
                                    fnd="$fnd $1"  # Treat as part of command
                                    ;;
                                # If it contains path-like characters, treat as path
                                */*|*-*|*_*)
                                    path_filter="$1"
                                    ;;
                                # Otherwise, treat as path filter for backward compatibility
                                *)
                                    path_filter="$1"
                                    ;;
                            esac
                        else
                            # Build command search term
                            fnd="$fnd${fnd:+ }$1"
                        fi
                        ;;
                esac
            fi
            shift
        done
        
        # no file yet
        [ -f "$datafile" ] || return
        
        # No locking needed for read operations with atomic updates
        
        local target_result
        target_result="$( < <( _sr_entries ) awk -v t="$(date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -v path_filter="$path_filter" -v execute_cmd="$execute_cmd" -v debug_mode="$debug_mode" -v print_only="$print_only" -F"|" '
            # ... (rest of the awk script remains the same as original)
            function frecent(rank, time) {
                # relate frequency and time
                dx = t - time
                return int(10000 * rank * (3.75/((0.0001 * dx + 1) + 0.25)))
            }
            function output(matches, best_match, cmd_matches, best_cmd) {
                if( list ) {
                    cmd = "sort -nr >&2"
                    for( x in matches ) {
                        if( matches[x] ) {
                            printf "%-10s %s -> %s\n", matches[x], x, (cmd_matches[x] ? cmd_matches[x] : "NO_COMMAND") | cmd
                        }
                    }
                } else if( print_only ) {
                    if( best_cmd ) {
                        print "PRINT_ONLY|" best_match "|" best_cmd
                    } else {
                        print "PRINT_ONLY|" best_match "|NO_COMMAND"
                    }
                } else {
                    if( execute_cmd && best_cmd ) {
                        print best_match "|" best_cmd
                    } else {
                        print best_match
                    }
                }
            }
            function enhanced_match(cmd, query) {
                cmd_lower = tolower(cmd)
                query_lower = tolower(query)
                
                # Exact match (highest priority)
                if (cmd == query || cmd_lower == query_lower) return 2.0
                
                # Exact substring match
                if (index(cmd, query) > 0) return 1.9
                
                # Case-insensitive substring match
                if (index(cmd_lower, query_lower) > 0) return 1.8
                
                return 0  # No match
            }
            BEGIN {
                # Initialize variables
                best_match = ""
                best_cmd = ""
                best_score = 0
            }
            NF >= 4 {
                dir = $1
                cmd = $2
                rank = $3
                time = $4
                
                # Apply path filter if specified
                if (path_filter && index(dir, path_filter) == 0) next
                
                # Calculate match score
                match_score = enhanced_match(cmd, q)
                if (match_score == 0) next
                
                # Calculate final score
                if (typ == "rank") {
                    score = rank * match_score
                } else if (typ == "recent") {
                    score = time * match_score
                } else {
                    score = frecent(rank, time) * match_score
                }
                
                matches[dir] = score
                cmd_matches[dir] = cmd
                
                if (score > best_score) {
                    best_score = score
                    best_match = dir
                    best_cmd = cmd
                }
            }
            END {
                output(matches, best_match, cmd_matches, best_cmd)
            }
        ' )"
        
        # No lock release needed with atomic updates
        
        if [ -n "$target_result" ]; then
            if [ "$print_only" = "1" ]; then
                # Parse print-only result
                local target_dir="${target_result#PRINT_ONLY|}"
                target_dir="${target_dir%%|*}"
                local target_cmd="${target_result##*|}"
                
                if [ "$target_cmd" = "NO_COMMAND" ]; then
                    echo "Directory: $target_dir"
                    echo "Command: No specific command found"
                else
                    echo "Directory: $target_dir"
                    echo "Command: $target_cmd"
                fi
                return
            else
                # Parse result - could be "dir" or "dir|command"
                local target_dir="${target_result%%|*}"
                local target_cmd="${target_result#*|}"
                
                _sr_debug_log "JUMP" "Found match - jumping to: '$target_dir' with command: '$target_cmd'"
                
                echo "\033[1;32m==> Jumping to:\033[0m \033[1;36m$target_dir\033[0m"
                builtin cd "$target_dir"
                
                # Execute command if requested and we have a command
                if [ "$execute_cmd" = "1" ] && [ "$target_cmd" != "$target_dir" ]; then
                    if [ "$debug_mode" = "1" ]; then
                        echo "\033[1;33m==> About to execute:\033[0m \033[1;35m$target_cmd\033[0m"
                        echo -n "Execute this command? [y/N] "
                        read -r response
                        case "$response" in
                            [yY]|[yY][eE][sS])
                                echo "\033[1;32m==> Executing:\033[0m \033[1;35m$target_cmd\033[0m"
                                eval "$target_cmd"
                                ;;
                            *)
                                echo "\033[1;31m==> Execution cancelled\033[0m"
                                ;;
                        esac
                    else
                        echo "\033[1;32m==> Executing:\033[0m \033[1;35m$target_cmd\033[0m"
                        eval "$target_cmd"
                    fi
                    
                    # Manually increase the weight of the executed command
                    _sr --add "$target_cmd" "$target_dir"
                fi
            fi
        else
            _sr_debug_log "SEARCH_FAIL" "No matching commands found for query: '$fnd' path_filter: '$path_filter'"
            echo "No matching commands found." >&2
            return 1
        fi
    fi
}

# Create alias
alias sr='_sr 2>&1'

# Shell集成部分
if type compctl >/dev/null 2>&1; then
    # zsh
    [ "$_SR_NO_PROMPT_COMMAND" ] || {
        # ZSH集成 - 添加到precmd函数列表
        # 在每个命令执行后自动记录命令历史
        _sr_precmd() {
            # Get the second-to-last command from history to avoid capturing the precmd function itself
            local cmd="$(fc -ln -2 | head -1 | sed 's/^[ \t]*//')"
            local dir="$PWD"
            
            # Clean up command: remove newlines and extra spaces
            cmd="$(echo "$cmd" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
            
            # Skip if command is empty or just whitespace
            [ -z "$(echo "$cmd" | tr -d ' \t\n')" ] && return
            
            # Skip if this is the same as the last recorded command (avoid duplicates)
            [ "$cmd" = "$_SR_LAST_CMD" ] && return
            _SR_LAST_CMD="$cmd"
            
            # Apply filtering logic before recording
            case "$cmd" in
                cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
            esac
            
            # Default dangerous commands blacklist
            local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck sr cd z ls ll"
            
            # Check against dangerous commands (only check base command, not parameters)
            local cmd_base="$(echo "$cmd" | awk '{print $1}')"
            for dangerous in $dangerous_commands; do
                [ "$cmd_base" = "$dangerous" ] && return
            done
            
            # Also check if command contains sr command (for compound commands)
            case "$cmd" in
                sr\ *|*\ sr\ *|*"&&"\ sr\ *|*"|"\ sr\ *|*";sr"\ *|*";sr"|*"&&sr"\ *|*"|sr"\ *) return;;
            esac
            
            # Check against user-defined ignored commands (only check base command)
            if [ -n "$_SR_IGNORE_COMMANDS" ]; then
                for ignore_cmd in $_SR_IGNORE_COMMANDS; do
                    [ "$cmd_base" = "$ignore_cmd" ] && return
                done
            fi
            
            # Log command recording in debug mode
            _sr_debug_log "CMD_RECORD" "Recording command: '$cmd' in directory: '$dir'"
            
            # Record the command with improved error handling
            (_sr --add "$cmd" "$dir" || { echo "[DEBUG] Failed to record command: '$cmd' in directory: '$dir'" >&2; _sr_debug_log "CMD_RECORD_FAIL" "Failed to record: '$cmd' in '$dir'"; }) &
        }
        [[ -n "${precmd_functions[(r)_sr_precmd]}" ]] || {
            precmd_functions[$(($#precmd_functions+1))]=_sr_precmd
        }
    }
elif type complete >/dev/null 2>&1; then
    # BASH集成 - 通过PROMPT_COMMAND实现
    # 在每个命令执行后自动记录命令历史
    [ "$_SR_NO_PROMPT_COMMAND" ] || {
        _sr_record_command() {
            # Get the last command from history
            local cmd="$(history 1 | sed 's/^[ ]*[0-9]*[ ]*//')"
            local dir="$PWD"
            
            # Clean up command: remove newlines and extra spaces
            cmd="$(echo "$cmd" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
            
            # Skip if command is empty or just whitespace
            [ -z "$(echo "$cmd" | tr -d ' \t\n')" ] && return
            
            # Skip if this is the same as the last recorded command (avoid duplicates)
            [ "$cmd" = "$_SR_LAST_CMD" ] && return
            _SR_LAST_CMD="$cmd"
            
            # Apply filtering logic before recording
            case "$cmd" in
                cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
            esac
            
            # Default dangerous commands blacklist
            local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck sr cd z ls ll"
            
            # Check against dangerous commands (only check base command, not parameters)
            local cmd_base="$(echo "$cmd" | awk '{print $1}')"
            for dangerous in $dangerous_commands; do
                [ "$cmd_base" = "$dangerous" ] && return
            done
            
            # Also check if command contains sr command (for compound commands)
            case "$cmd" in
                sr\ *|*\ sr\ *|*"&&"\ sr\ *|*"|"\ sr\ *|*";sr"\ *|*";sr"|*"&&sr"\ *|*"|sr"\ *) return;;
            esac
            
            # Check against user-defined ignored commands (only check base command)
            if [ -n "$_SR_IGNORE_COMMANDS" ]; then
                for ignore_cmd in $_SR_IGNORE_COMMANDS; do
                    [ "$cmd_base" = "$ignore_cmd" ] && return
                done
            fi
            
            # Log command recording in debug mode
            _sr_debug_log "CMD_RECORD" "Recording command: '$cmd' in directory: '$dir'"
            
            # Record the command with improved error handling
            (_sr --add "$cmd" "$dir" || { echo "[DEBUG] Failed to record command: '$cmd' in directory: '$dir'" >&2; _sr_debug_log "CMD_RECORD_FAIL" "Failed to record: '$cmd' in '$dir'"; }) &
        }
        
        # Add to PROMPT_COMMAND
        grep "_sr_record_command" <<< "$PROMPT_COMMAND" >/dev/null || {
            PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''_sr_record_command;'
        }
    }
fi
