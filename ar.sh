#!/bin/bash
# ar.sh - Auto Record and Jump to command history
# Copyright (c) 2024. Licensed under MIT license.

# maintains a jump-list of the commands you actually use with their directories
#
# INSTALL:
#     * put something like this in your .bashrc/.zshrc:
#         . /path/to/ar.sh
#     * run commands for a while to build up the db
#     * use: ar 'partial_command' to jump to the directory where you ran similar commands
#
# CONFIGURATION:
#     set $_AR_DATA in .bashrc/.zshrc to change the datafile (default ~/.ar).
#     set $_AR_MAX_SCORE lower to age entries out faster (default 9000).
#     set $_AR_NO_PROMPT_COMMAND if you're handling PROMPT_COMMAND yourself.
#     set $_AR_EXCLUDE_DIRS to an array of directories to exclude.
#     set $_AR_IGNORE_COMMANDS to a space-separated list of commands to ignore.
#     Note: Dangerous commands (rm, sudo, etc.) are automatically ignored for safety.
#
# USE:
#     * ar foo        # cd to most frecent dir where you ran commands matching foo
#     * ar -l foo     # list matches instead of cd
#     * ar -r foo     # cd to highest ranked dir matching foo
#     * ar -t foo     # cd to most recently accessed dir matching foo
#     * ar -h         # show help message

[ -d "${_AR_DATA:-$HOME/.ar}" ] && {
    echo "ERROR: ar.sh's datafile (${_AR_DATA:-$HOME/.ar}) is a directory."
}

_ar() {
    local datafile="${_AR_DATA:-$HOME/.ar}"
    
    # if symlink, dereference
    [ -h "$datafile" ] && datafile=$(readlink "$datafile")
    
    # bail if we don't own ~/.ar
    [ -f "$datafile" -a ! -O "$datafile" ] && return
    
    _ar_entries() {
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
        
        # skip empty commands or basic navigation
        [ -z "$cmd" ] && return
        case "$cmd" in
            cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
        esac
        
        # Default dangerous commands blacklist
        local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck ls ll cd z"
        
        # Check against dangerous commands (only check base command, not parameters)
        local cmd_base="$(echo "$cmd" | awk '{print $1}')"
        for dangerous in $dangerous_commands; do
            [ "$cmd_base" = "$dangerous" ] && return
        done
        
        # Check against user-defined ignored commands (only check base command)
        if [ -n "$_AR_IGNORE_COMMANDS" ]; then
            for ignore_cmd in $_AR_IGNORE_COMMANDS; do
                [ "$cmd_base" = "$ignore_cmd" ] && return
            done
        fi
        
        # don't track excluded directories
        if [ ${#_AR_EXCLUDE_DIRS[@]} -gt 0 ]; then
            local exclude
            for exclude in "${_AR_EXCLUDE_DIRS[@]}"; do
                case "$dir" in "$exclude"*) return;; esac
            done
        fi
        
        # maintain the data file
        local tempfile="$datafile.$RANDOM"
        local score=${_AR_MAX_SCORE:-9000}
        local key="$dir|$cmd"
        
        _ar_entries | \awk -v key="$key" -v now="$(\date +%s)" -v score=$score -F"|" '
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
        # search and jump
        local echo fnd last list opt typ path_filter execute_cmd
        execute_cmd=1
        # Parse arguments - handle options first, then search terms
        local parsing_options=1
        while [ "$1" ]; do 
            if [ "$parsing_options" = "1" ]; then
                case "$1" in
                    -h|--help) 
                        echo "ar [-hlrte] [command] [path]" >&2; 
                        echo "  -h: show help" >&2;
                        echo "  -l: list matches" >&2;
                        echo "  -r: rank by frequency" >&2;
                        echo "  -t: rank by recency" >&2;
                        echo "  -e: execute the matched command after jumping" >&2;
                        echo "Examples:" >&2;
                        echo "  ar vim           # jump to dir where vim was used" >&2;
                        echo "  ar -e vim main.py # jump to dir and execute vim main.py" >&2;
                        echo "  ar vim /tmp      # jump to dir under /tmp where vim was used" >&2;
                        echo "  ar -l git        # list all dirs where git was used" >&2;
                        return;;
                    -l) list=1;;
                    -r) typ="rank";;
                    -t) typ="recent";;
                    -j) execute_cmd=0;;
                    /*) path_filter="$1"; parsing_options=0;; # Path argument, stop parsing options
                    -*) ;; # Unknown option, ignore
                    *) fnd="$fnd${fnd:+ }$1"; parsing_options=0;; # Non-option argument, stop parsing options
                esac
            else
                # No longer parsing options, everything is a search term or path
                case "$1" in
                    /*) path_filter="$1";; # Path argument starting with /
                    *) fnd="$fnd${fnd:+ }$1";; # Search term
                esac
            fi
            shift
        done
        
        # no file yet
        [ -f "$datafile" ] || return
        
        local target_result
        target_result="$( < <( _ar_entries ) \awk -v t="$(\date +%s)" -v list="$list" -v typ="$typ" -v q="$fnd" -v path_filter="$path_filter" -v execute_cmd="$execute_cmd" -F"|" '
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
                            printf "%-10s %s\n", matches[x], x | cmd
                        }
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
                gsub(" ", ".*", q)
                hi_rank = ihi_rank = -9999999999
            }
            NF >= 4 {
                dir = $1
                cmd = $2
                
                # Apply path filter if specified
                if( path_filter && index(dir, path_filter) != 1 ) {
                    next
                }
                
                if( typ == "rank" ) {
                    rank = $3
                } else if( typ == "recent" ) {
                    rank = $4 - t
                } else rank = frecent($3, $4)
                
                # Match against command or full command line
                cmd_match = 0
                if( q == "" || cmd ~ q ) {
                    cmd_match = 1
                    # In execute mode, prefer non-ar commands
                    cmd_priority = (execute_cmd && cmd !~ /^ar /) ? rank * 2 : rank
                    if( !matches[dir] || matches[dir] < cmd_priority ) {
                        matches[dir] = cmd_priority
                        cmd_matches[dir] = cmd
                    }
                } else if( tolower(cmd) ~ tolower(q) ) {
                    cmd_match = 1
                    # In execute mode, prefer non-ar commands
                    cmd_priority = (execute_cmd && cmd !~ /^ar /) ? rank * 2 : rank
                    if( !imatches[dir] || imatches[dir] < cmd_priority ) {
                        imatches[dir] = cmd_priority
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
                    return
                else
                    # Parse result - could be "dir" or "dir|command"
                    local target_dir="${target_result%%|*}"
                    local target_cmd="${target_result#*|}"
                    
                    echo "Jumping to: $target_dir"
                    builtin cd "$target_dir"
                    
                    # Execute command if -e option was used and we have a command
                    if [ "$execute_cmd" = "1" ] && [ "$target_cmd" != "$target_dir" ]; then
                        echo "Executing: $target_cmd"
                        eval "$target_cmd"
                    fi
                fi
            fi
        else
            echo "No matching commands found." >&2
            return 1
        fi
    fi
}

# Hook function to record commands (for bash compatibility)
_ar_record_command() {
    local cmd="$(history | tail -2 | head -1 | sed 's/^[ ]*[0-9]*[ ]*//')"
    local dir="$PWD"
    
    # Skip if command is empty or just whitespace
    [ -z "$(echo "$cmd" | tr -d ' \t\n')" ] && return
    
    # Apply filtering logic before recording
    case "$cmd" in
        cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
    esac
    
    # Default dangerous commands blacklist
    local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck ar cd z ls ll"
    
    # Check against dangerous commands (only check base command, not parameters)
    local cmd_base="$(echo "$cmd" | awk '{print $1}')"
    for dangerous in $dangerous_commands; do
        [ "$cmd_base" = "$dangerous" ] && return
    done
    
    # Check against user-defined ignored commands (only check base command)
    if [ -n "$_AR_IGNORE_COMMANDS" ]; then
        for ignore_cmd in $_AR_IGNORE_COMMANDS; do
            [ "$cmd_base" = "$ignore_cmd" ] && return
        done
    fi
    
    # Record the command asynchronously
    (_ar --add "$cmd" "$dir" &)
}

# Create alias
alias ar='_ar 2>&1'

# Shell integration
if type compctl >/dev/null 2>&1; then
    # zsh
    [ "$_AR_NO_PROMPT_COMMAND" ] || {
        # Add to precmd functions
        _ar_precmd() {
            # Get the second-to-last command from history to avoid capturing the precmd function itself
            local cmd="$(fc -ln -2 | head -1 | sed 's/^[ \t]*//')"
            local dir="$PWD"
            
            # Skip if command is empty or just whitespace
            [ -z "$(echo "$cmd" | tr -d ' \t\n')" ] && return
            
            # Skip if this is the same as the last recorded command (avoid duplicates)
            [ "$cmd" = "$_AR_LAST_CMD" ] && return
            _AR_LAST_CMD="$cmd"
            
            # Apply filtering logic before recording
            case "$cmd" in
                cd|cd\ *|ls|ls\ *|pwd|clear|exit) return;;
            esac
            
            # Default dangerous commands blacklist
            local dangerous_commands="rm rmdir mv cp dd chmod chown sudo su killall pkill halt reboot shutdown init mount umount fdisk mkfs fsck"
            
            # Check against dangerous commands (only check base command, not parameters)
            local cmd_base="$(echo "$cmd" | awk '{print $1}')"
            for dangerous in $dangerous_commands; do
                [ "$cmd_base" = "$dangerous" ] && return
            done
            
            # Check against user-defined ignored commands (only check base command)
            if [ -n "$_AR_IGNORE_COMMANDS" ]; then
                for ignore_cmd in $_AR_IGNORE_COMMANDS; do
                    [ "$cmd_base" = "$ignore_cmd" ] && return
                done
            fi
            
            # Record the command asynchronously
            (_ar --add "$cmd" "$dir" &)
        }
        [[ -n "${precmd_functions[(r)_ar_precmd]}" ]] || {
            precmd_functions[$(($#precmd_functions+1))]=_ar_precmd
        }
    }
elif type complete >/dev/null 2>&1; then
    # bash
    [ "$_AR_NO_PROMPT_COMMAND" ] || {
        # Add to PROMPT_COMMAND
        grep "_ar_record_command" <<< "$PROMPT_COMMAND" >/dev/null || {
            PROMPT_COMMAND="$PROMPT_COMMAND"$'\n''_ar_record_command;'
        }
    }
fi