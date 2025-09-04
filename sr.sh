#!/bin/bash
# sr.sh - Auto Record and Jump to command history
# Copyright (c) 2024. Licensed under MIT license.

# maintains a jump-list of the commands you actually use with their directories
#
# INSTALL:
#     * put something like this in your .bashrc/.zshrc:
#         . /path/to/sr.sh
#     * run commands for a while to build up the db
#     * use: sr 'partial_command' to jump to the directory where you ran similar commands   
#
# CONFIGURATION:
#     set $_SR_DATA in .bashrc/.zshrc to change the datafile (default ~/.sr).
#     set $_SR_MAX_SCORE lower to age entries out faster (default 9000).
#     set $_SR_NO_PROMPT_COMMAND if you're handling PROMPT_COMMAND yourself.
#     set $_SR_EXCLUDE_DIRS to an array of directories to exclude.
#     set $_SR_IGNORE_COMMANDS to a space-separated list of commands to ignore.
#     set $_SR_DEBUG=1 to enable global debug mode (persistent until disabled).
#     set $_SR_DEBUG_LOG to change the debug log file path (default ${_SR_DATA}.debug).
#     Note: Dangerous commands (rm, sudo, etc.) are automatically ignored for safety.
#
# USE:
#     * sr foo        # cd to most frecent dir where you ran commands matching foo
#     * sr -l foo     # list matches instead of cd
#     * sr -r foo     # cd to highest ranked dir matching foo
#     * sr -t foo     # cd to most recently accessed dir matching foo
#     * sr -e foo     # cd to dir and execute the matched command
#     * sr -d -e foo  # debug mode: show command before execution and wait for confirmation
#     * sr --debug-on # enable global debug mode (persistent)
#     * sr --debug-off # disable global debug mode
#     * sr -h         # show help message

[ -d "${_SR_DATA:-$HOME/.sr}" ] && {
    echo "ERROR: sr.sh's datafile (${_SR_DATA:-$HOME/.sr}) is a directory."
}

# Debug logging function
_sr_debug_log() {
    # Only log if debug mode is enabled
    [ "$_SR_DEBUG" != "1" ] && return
    
    local debug_file="${_SR_DEBUG_LOG:-${_SR_DATA:-$HOME/.sr}.debug}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_type="$1"
    shift
    local message="$*"
    
    # Create debug log entry
    echo "[$timestamp] [$log_type] $message" >> "$debug_file"
    
    # If this is a data snapshot request, append current _SR_DATA content
    if [ "$log_type" = "DATA_SNAPSHOT" ]; then
        local datafile="${_SR_DATA:-$HOME/.sr}"
        echo "[$timestamp] [DATA_CONTENT] === Current _SR_DATA file content ===" >> "$debug_file"
        if [ -f "$datafile" ]; then
            cat "$datafile" >> "$debug_file"
        else
            echo "[$timestamp] [DATA_CONTENT] _SR_DATA file does not exist" >> "$debug_file"
        fi
        echo "[$timestamp] [DATA_CONTENT] === End of _SR_DATA content ===" >> "$debug_file"
    fi
}

_sr() {
    local datafile="${_SR_DATA:-$HOME/.sr}"
    
    # if symlink, dereference
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")
    
    # bail if we don't own ~/.ar
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
        
        # maintain the data file
        local tempfile="$datafile.$RANDOM"
        local score=${_SR_MAX_SCORE:-9000}
        local key="$dir|$cmd"
        
        _sr_entries | \awk -v key="$key" -v now="$(\date +%s)" -v score=$score -F"|" '
            BEGIN {
                rank[key] = 1
                time[key] = now
            }
            NF >= 4 {
                entry_key = $1 "|" $2
                if( entry_key == key ) {
                    rank[entry_key] = $3 + 1
                    time[entry_key] = now
                } else {
                    rank[entry_key] = $3
                    time[entry_key] = $4
                }
                count += $3
            }
            END {
                if( count > score ) {
                    # aging
                    for( x in rank ) {
                        split(x, parts, "|")
                        printf "%s|%s|%.2f|%s\n", parts[1], parts[2], 0.99*rank[x], time[x]
                    }
                } else {
                    for( x in rank ) {
                        split(x, parts, "|")
                        printf "%s|%s|%.2f|%s\n", parts[1], parts[2], rank[x], time[x]
                    }
                }
            }
        ' 2>/dev/null >| "$tempfile"
        
        # avoid clobbering the datafile in a race condition
        if [ $? -ne 0 -a -f "$datafile" ]; then
            \env rm -f "$tempfile"
        else
            \env mv -f "$tempfile" "$datafile" || \env rm -f "$tempfile"
        fi
        
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
        
        # search and jump
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
                    -p) print_only=1;;   # Print command only, don't jump or execute
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
        
        local target_result
        target_result="$( < <( _sr_entries ) \awk -v t="$(\date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -v path_filter="$path_filter" -v execute_cmd="$execute_cmd" -v debug_mode="$debug_mode" -v print_only="$print_only" -F"|" '
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
            BEGIN {
                # Store original query for exact matching
                q_exact = q
                # Create fuzzy pattern for fallback
                q_fuzzy = q
                gsub(" ", ".*", q_fuzzy)
                hi_rank = ihi_rank = -9999999999
            }
            NF >= 4 {
                dir = $1
                cmd = $2
                
                # Apply path filter if specified (substring matching)
                if( path_filter && index(dir, path_filter) == 0 ) {
                    next
                }
                
                if( typ == "rank" ) {
                    rank = $3
                } else if( typ == "recent" ) {
                    rank = $4 - t
                } else rank = frecent($3, $4)
                
                # Match against command or full command line
                cmd_match = 0
                
                # In execute mode, skip sr/_sr commands to prevent recursion
                if( execute_cmd && cmd ~ /^(_sr|sr) / ) {
                    next
                }
                
                # Smart matching: exact match first, then fuzzy match
                if( q == "" ) {
                    cmd_match = 1
                } else {
                    # Try exact match first (higher priority)
                    if( cmd == q_exact || index(cmd, q_exact) > 0 ) {
                        cmd_match = 1
                        rank = rank * 1.5  # Boost exact matches
                    }
                    # If no exact match, try fuzzy match
                    else if( cmd ~ q_fuzzy ) {
                        cmd_match = 1
                    }
                }
                
                if( cmd_match ) {
                    if( !matches[dir] || matches[dir] < rank ) {
                        matches[dir] = rank
                        cmd_matches[dir] = cmd
                    }
                } else if( tolower(cmd) ~ tolower(q) ) {
                    cmd_match = 1
                    if( !imatches[dir] || imatches[dir] < rank ) {
                        imatches[dir] = rank
                        icmd_matches[dir] = cmd
                    }
                }
                
                if( cmd_match ) {
                    if( matches[dir] && matches[dir] > hi_rank ) {
                        best_match = dir
                        best_cmd = cmd_matches[dir]
                        hi_rank = matches[dir]
                    } else if( imatches[dir] && imatches[dir] > ihi_rank ) {
                        ibest_match = dir
                        ibest_cmd = icmd_matches[dir]
                        ihi_rank = imatches[dir]
                    }
                }
            }
            END {
                # prefer case sensitive
                if( best_match ) {
                    output(matches, best_match, cmd_matches, best_cmd)
                    exit
                } else if( ibest_match ) {
                    output(imatches, ibest_match, icmd_matches, ibest_cmd)
                    exit
                }
                exit(1)
            }
        ')" 
        
        if [ "$?" -eq 0 ]; then
            if [ "$target_result" ]; then
                if [ "$list" ]; then
                    _sr_debug_log "SEARCH" "List mode: showing matches for query: '$fnd' path_filter: '$path_filter'"
                    return
                elif [ "$print_only" = "1" ]; then
                    # Handle print-only mode
                    if [[ "$target_result" == PRINT_ONLY* ]]; then
                        local result_without_prefix="${target_result#PRINT_ONLY|}"
                        local target_dir="${result_without_prefix%%|*}"
                        local target_cmd="${result_without_prefix#*|}"
                        
                        _sr_debug_log "PRINT_ONLY" "Print mode: directory: '$target_dir' command: '$target_cmd'"
                        
                        echo "\033[1;33m==> Directory:\033[0m \033[1;36m$target_dir\033[0m"
                        if [ "$target_cmd" != "NO_COMMAND" ] && [ "$target_cmd" != "$target_dir" ]; then
                            echo "\033[1;33m==> Command:\033[0m \033[1;35m$target_cmd\033[0m"
                        else
                            echo "\033[1;33m==> Command:\033[0m \033[1;31mNo specific command found\033[0m"
                        fi
                    fi
                    return
                else
                    # Parse result - could be "dir" or "dir|command"
                    local target_dir="${target_result%%|*}"
                    local target_cmd="${target_result#*|}"
                    
                    _sr_debug_log "JUMP" "Found match - jumping to: '$target_dir' with command: '$target_cmd'"
                    _sr_debug_log "DATA_SNAPSHOT" "State before jumping"
                    
                    echo "\033[1;32m==> Jumping to:\033[0m \033[1;36m$target_dir\033[0m"
                    builtin cd "$target_dir"
                    
                    # Execute command if -e option was used and we have a command
                    if [ "$execute_cmd" = "1" ] && [ "$target_cmd" != "$target_dir" ]; then
                        _sr_debug_log "EXEC_PREP" "Preparing to execute command: '$target_cmd' in directory: '$target_dir'"
                        if [ "$debug_mode" = "1" ]; then
                            echo "\033[1;33m==> Debug mode: Will execute command:\033[0m \033[1;35m$target_cmd\033[0m"
                            echo -n "Do you want to execute this command? [y/N]: "
                            read -r confirm
                            case "$confirm" in
                                [Yy]|[Yy][Ee][Ss])
                                    _sr_debug_log "EXEC_CONFIRM" "User confirmed execution of: '$target_cmd'"
                                    echo "\033[1;32m==> Executing:\033[0m \033[1;35m$target_cmd\033[0m"
                                    eval "$target_cmd"
                                    _sr_debug_log "EXEC_DONE" "Command executed: '$target_cmd' (exit code: $?)"
                                    # Manually increase the weight of the executed command
                                    _sr --add "$target_cmd" "$target_dir"
                                    ;;
                                *)
                                    _sr_debug_log "EXEC_CANCEL" "User cancelled execution of: '$target_cmd'"
                                    echo "Command execution cancelled."
                                    ;;
                            esac
                        else
                            _sr_debug_log "EXEC_AUTO" "Auto-executing command: '$target_cmd'"
                            echo "\033[1;32m==> Executing:\033[0m \033[1;35m$target_cmd\033[0m"
                            eval "$target_cmd"
                            _sr_debug_log "EXEC_DONE" "Command executed: '$target_cmd' (exit code: $?)"
                            # Manually increase the weight of the executed command
                            _sr --add "$target_cmd" "$target_dir"
                        fi
                    fi
                fi
            fi
        else
            _sr_debug_log "SEARCH_FAIL" "No matching commands found for query: '$fnd' path_filter: '$path_filter'"
            _sr_debug_log "DATA_SNAPSHOT" "Current state when search failed"
            echo "No matching commands found." >&2
            return 1
        fi
    fi
}

# Hook function to record commands (for bash compatibility)
_sr_record_command() {
    local cmd="$(history | tail -1 | head -1 | sed 's/^[ ]*[0-9]*[ ]*//')"
    local dir="$PWD"
    
    # Clean up command: remove newlines and extra spaces
    cmd="$(echo "$cmd" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
    
    # Skip if command is empty or just whitespace
    [ -z "$(echo "$cmd" | tr -d ' \t\n')" ] && return
    
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
    
    # Record the command asynchronously
    (_sr --add "$cmd" "$dir" &)
}

# Create alias
alias sr='_sr 2>&1'

# Shell integration
if type compctl >/dev/null 2>&1; then
    # zsh
    [ "$_SR_NO_PROMPT_COMMAND" ] || {
        # Add to precmd functions
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
            
            # Record the command asynchronously
            (_sr --add "$cmd" "$dir" &)
        }
        [[ -n "${precmd_functions[(r)_sr_precmd]}" ]] || {
            precmd_functions[$(($#precmd_functions+1))]=_sr_precmd
        }
    }
elif type complete >/dev/null 2>&1; then
    # bash
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
            
            # Record the command asynchronously
            (_sr --add "$cmd" "$dir" &)
        }
        
        # Add to PROMPT_COMMAND
        grep "_sr_record_command" <<< "$PROMPT_COMMAND" >/dev/null || {
            PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''_sr_record_command;'
        }
    }
fi
