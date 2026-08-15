#!/bin/bash
#
# VM Health Check Script for Ubuntu VMs
# Analyzes CPU, memory, and disk usage.
# A VM is "healthy" only if ALL three metrics are below 60%.
# If any metric is 60% or above, the VM is "not healthy".
#

THRESHOLD=60

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get CPU usage percentage
get_cpu_usage() {
    # Read two snapshots of /proc/stat 1 second apart and compute the delta.
    # This gives an accurate instantaneous CPU usage percentage.
    local cpu_a cpu_b
    cpu_a=$(head -1 /proc/stat)
    sleep 1
    cpu_b=$(head -1 /proc/stat)

    local idle_a total_a idle_b total_b
    idle_a=$(echo "$cpu_a" | awk '{print $5}')
    total_a=$(echo "$cpu_a" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    idle_b=$(echo "$cpu_b" | awk '{print $5}')
    total_b=$(echo "$cpu_b" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')

    local idle_diff total_diff
    idle_diff=$((idle_b - idle_a))
    total_diff=$((total_b - total_a))

    if [ "$total_diff" -le 0 ]; then
        echo 0
        return
    fi

    local idle_pct
    idle_pct=$(( (idle_diff * 100) / total_diff ))
    echo $((100 - idle_pct))
}

# Get memory usage percentage
get_memory_usage() {
    # Use /proc/meminfo for a dependency-free calculation.
    local mem_total mem_available mem_used
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))

    if [ "$mem_total" -le 0 ]; then
        echo 0
        return
    fi

    echo $(( (mem_used * 100) / mem_total ))
}

# Get disk usage percentage for the root filesystem
get_disk_usage() {
    # Use df to get the usage percentage of the root (/) filesystem.
    df / --output=pcent | tail -1 | tr -d ' ' | sed 's/%//'
}

# Print a colored status label
print_status() {
    local usage=$1
    if [ "$usage" -ge "$THRESHOLD" ]; then
        printf "${RED}NOT OK${NC} (${usage}%% >= ${THRESHOLD}%%)"
    else
        printf "${GREEN}OK${NC} (${usage}%% < ${THRESHOLD}%%)"
    fi
}

# Check a single VM (the local machine)
check_vm() {
    local vm_name="${1:-$(hostname)}"

    printf "\n${CYAN}========================================\n"
    printf "  VM Health Report: %s\n" "$vm_name"
    printf "  Threshold: %d%% for all metrics\n" "$THRESHOLD"
    printf "========================================${NC}\n\n"

    local cpu_usage mem_usage disk_usage
    cpu_usage=$(get_cpu_usage)
    mem_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)

    printf "  CPU Usage   : %s\n" "$(print_status "$cpu_usage")"
    printf "  Memory Usage: %s\n" "$(print_status "$mem_usage")"
    printf "  Disk Usage  : %s\n\n" "$(print_status "$disk_usage")"

    # Determine overall health
    if [ "$cpu_usage" -ge "$THRESHOLD" ] || [ "$mem_usage" -ge "$THRESHOLD" ] || [ "$disk_usage" -ge "$THRESHOLD" ]; then
        printf "  Overall Status: ${RED}NOT HEALTHY${NC}\n"
        printf "  Reason: "
        [ "$cpu_usage" -ge "$THRESHOLD" ] && printf "CPU=${cpu_usage}%% "
        [ "$mem_usage" -ge "$THRESHOLD" ] && printf "Memory=${mem_usage}%% "
        [ "$disk_usage" -ge "$THRESHOLD" ] && printf "Disk=${disk_usage}%% "
        printf "\n"
        return 1
    else
        printf "  Overall Status: ${GREEN}HEALTHY${NC}\n"
        printf "  All metrics are below the %d%% threshold.\n" "$THRESHOLD"
        return 0
    fi
}

# Explain what each metric means and why the VM is healthy or not
explain_vm() {
    local vm_name="${1:-$(hostname)}"

    printf "\n${CYAN}========================================\n"
    printf "  VM Health Explanation: %s\n" "$vm_name"
    printf "  Threshold: %d%% for all metrics\n" "$THRESHOLD"
    printf "========================================${NC}\n\n"

    local cpu_usage mem_usage disk_usage
    cpu_usage=$(get_cpu_usage)
    mem_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)

    # --- CPU ---
    printf "${YELLOW}CPU Usage: %d%%${NC}\n" "$cpu_usage"
    printf "  What it measures: The percentage of time the CPU spends running\n"
    printf "  processes versus sitting idle. A high value means the processor is\n"
    printf "  under heavy load and may struggle to keep up with demand.\n"
    if [ "$cpu_usage" -ge "$THRESHOLD" ]; then
        printf "  ${RED}Status: NOT OK — above the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  Impact: Applications may respond slowly, requests may queue up,\n"
        printf "  and the system can become unresponsive under sustained load.\n"
        printf "  Suggestions:\n"
        printf "    - Identify heavy processes: top -b -n1 | head -20\n"
        printf "    - Scale vertically (more cores) or distribute load across VMs.\n"
        printf "    - Check for runaway or stuck processes.\n"
    else
        printf "  ${GREEN}Status: OK — below the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  The CPU has enough headroom to handle current and near-future workloads.\n"
    fi
    printf "\n"

    # --- Memory ---
    printf "${YELLOW}Memory Usage: %d%%${NC}\n" "$mem_usage"
    printf "  What it measures: The percentage of RAM in use by the OS and\n"
    printf "  applications (total minus available/cached). High usage can lead\n"
    printf "  to swapping, which severely degrades performance.\n"
    if [ "$mem_usage" -ge "$THRESHOLD" ]; then
        printf "  ${RED}Status: NOT OK — above the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  Impact: The kernel may start swapping to disk, causing major\n"
    printf "  slowdowns. The OOM killer may terminate processes to free memory.\n"
        printf "  Suggestions:\n"
        printf "    - Find top memory consumers: ps aux --sort=-%mem | head -10\n"
    printf "    - Add more RAM or reduce the number of running services.\n"
        printf "    - Check for memory leaks in long-running applications.\n"
    else
        printf "  ${GREEN}Status: OK — below the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  There is sufficient free memory for current workloads and spikes.\n"
    fi
    printf "\n"

    # --- Disk ---
    printf "${YELLOW}Disk Usage: %d%%${NC}\n" "$disk_usage"
    printf "  What it measures: The percentage of the root filesystem (/) that\n"
    printf "  is filled with data. When a disk fills up, the system cannot write\n"
    printf "  logs, save files, or persist data — leading to failures.\n"
    if [ "$disk_usage" -ge "$THRESHOLD" ]; then
        printf "  ${RED}Status: NOT OK — above the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  Impact: Services may crash, logs may stop being written, and\n"
        printf "  database writes can fail. At 100%% the VM becomes nearly unusable.\n"
        printf "  Suggestions:\n"
        printf "    - Find large files:      du -ah / 2>/dev/null | sort -rh | head -20\n"
        printf "    - Clean old logs:        journalctl --vacuum-time=7d\n"
        printf "    - Remove unused packages: apt autoremove && apt clean\n"
        printf "    - Extend the disk volume or attach additional storage.\n"
    else
        printf "  ${GREEN}Status: OK — below the %d%% threshold.${NC}\n" "$THRESHOLD"
        printf "  There is enough free disk space for normal operations and growth.\n"
    fi
    printf "\n"

    # --- Overall verdict ---
    printf "${CYAN}--- Overall Verdict ---${NC}\n"
    if [ "$cpu_usage" -ge "$THRESHOLD" ] || [ "$mem_usage" -ge "$THRESHOLD" ] || [ "$disk_usage" -ge "$THRESHOLD" ]; then
        printf "  ${RED}NOT HEALTHY${NC}\n"
        printf "  One or more resources have crossed the %d%% threshold.\n" "$THRESHOLD"
        printf "  A VM is only considered healthy when ALL three metrics — CPU,\n"
        printf "  memory, and disk — stay below %d%%. Address the failing items\n" "$THRESHOLD"
        printf "  above to restore the VM to a healthy state.\n"
        return 1
    else
        printf "  ${GREEN}HEALTHY${NC}\n"
        printf "  All three resources (CPU, memory, disk) are below the %d%%\n" "$THRESHOLD"
        printf "  threshold, so the VM has sufficient capacity to operate normally.\n"
        return 0
    fi
}

# Check multiple remote VMs over SSH (optional)
# Usage: ./vm-health-check.sh --remote user@vm1 user@vm2 ...
check_remote_vms() {
    local overall_healthy=true

    for vm in "$@"; do
        printf "\n${YELLOW}--- Checking remote VM: %s ---${NC}\n" "$vm"

        # Copy this script to the remote VM and execute it
        if scp -q "$0" "$vm:/tmp/vm-health-check.sh" 2>/dev/null; then
            ssh -q "$vm" "chmod +x /tmp/vm-health-check.sh && bash /tmp/vm-health-check.sh --local '$vm'" || overall_healthy=false
            ssh -q "$vm" "rm -f /tmp/vm-health-check.sh" 2>/dev/null
        else
            printf "${RED}Failed to connect to %s. Make sure SSH access is configured.${NC}\n" "$vm"
            overall_healthy=false
        fi
    done

    if [ "$overall_healthy" = true ]; then
        return 0
    else
        return 1
    fi
}

usage() {
    printf "Usage: %s [OPTIONS]\n\n" "$0"
    printf "Options:\n"
    printf "  --local [NAME]     Check the local machine (optionally give it a custom name)\n"
    printf "  --remote VM ...    Check one or more remote VMs over SSH (e.g. user@vm1 user@vm2)\n"
    printf "  --explain-remote   Same as --remote but with detailed explanations per VM\n"
    printf "  --threshold N      Set the health threshold percentage (default: 60)\n"
    printf "  --explain [NAME]   Check the local machine AND print a detailed\n"
    printf "                     explanation of each metric and the verdict\n"
    printf "  --help             Show this help message\n\n"
    printf "Examples:\n"
    printf "  %s                          Check the local VM\n" "$0"
    printf "  %s --local web-server-01    Check local VM with a custom name\n" "$0"
    printf "  %s --remote ubuntu@10.0.0.1 ubuntu@10.0.0.2   Check two remote VMs\n" "$0"
    printf "  %s --threshold 75           Use 75%% as the threshold instead of 60%%\n" "$0"
    printf "  %s --explain                Check local VM with detailed explanations\n" "$0"
    printf "  %s --explain db-server-01    Check and explain with a custom name\n" "$0"
}

main() {
    # Default: check the local machine
    if [ $# -eq 0 ]; then
        check_vm "$(hostname)"
        return $?
    fi

    case "$1" in
        --help|-h)
            usage
            return 0
            ;;
        --local)
            local name="${2:-$(hostname)}"
            check_vm "$name"
            return $?
            ;;
        --remote)
            shift
            if [ $# -eq 0 ]; then
                printf "${RED}Error: --remote requires at least one VM address.${NC}\n" >&2
                usage
                return 1
            fi
            check_remote_vms "$@"
            return $?
            ;;
        --explain-remote)
            shift
            if [ $# -eq 0 ]; then
                printf "${RED}Error: --explain-remote requires at least one VM address.${NC}\n" >&2
                usage
                return 1
            fi
            local overall_healthy=true
            for vm in "$@"; do
                printf "\n${YELLOW}--- Explaining remote VM: %s ---${NC}\n" "$vm"
                if scp -q "$0" "$vm:/tmp/vm-health-check.sh" 2>/dev/null; then
                    ssh -q "$vm" "chmod +x /tmp/vm-health-check.sh && bash /tmp/vm-health-check.sh --explain '$vm'" || overall_healthy=false
                    ssh -q "$vm" "rm -f /tmp/vm-health-check.sh" 2>/dev/null
                else
                    printf "${RED}Failed to connect to %s. Make sure SSH access is configured.${NC}\n" "$vm"
                    overall_healthy=false
                fi
            done
            [ "$overall_healthy" = true ] && return 0 || return 1
            ;;
        --explain)
            local name="${2:-$(hostname)}"
            explain_vm "$name"
            return $?
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            # After setting threshold, process remaining args or default to local
            if [ $# -eq 0 ]; then
                check_vm "$(hostname)"
                return $?
            fi
            "$0" "$@"
            return $?
            ;;
        *)
            printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
            usage
            return 1
            ;;
    esac
}

main "$@"
