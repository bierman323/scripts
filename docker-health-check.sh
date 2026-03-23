#!/bin/bash
#
# Docker Health Check Script
# Checks if Docker system prune is needed and reports on stopped containers
# Designed to run via cron with dual output to log file and stdout
#

set -euo pipefail

# =============================================================================
# Configuration (override via environment variables)
# =============================================================================

# Thresholds
RECLAIMABLE_THRESHOLD_GB="${RECLAIMABLE_THRESHOLD_GB:-5}"
DANGLING_IMAGE_THRESHOLD="${DANGLING_IMAGE_THRESHOLD:-10}"
DANGLING_VOLUME_THRESHOLD="${DANGLING_VOLUME_THRESHOLD:-5}"
DANGLING_NETWORK_THRESHOLD="${DANGLING_NETWORK_THRESHOLD:-10}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/docker-health-check.log}"

# Uptime Kuma Push URL (leave empty to disable)
UPTIME_KUMA_PUSH_URL="${UPTIME_KUMA_PUSH_URL:-}"

# Docker binary path (for cron compatibility)
DOCKER="${DOCKER:-/usr/bin/docker}"

# =============================================================================
# Global State
# =============================================================================

PRUNE_RECOMMENDED=false
STOPPED_CONTAINERS_FOUND=false
STOPPED_CONTAINER_COUNT=0
TOTAL_RECLAIMABLE_GB=0
ALERT_MESSAGES=()

# =============================================================================
# Functions
# =============================================================================

log_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Output to stdout (for cron email)
    echo "$message"

    # Append to log file (create directory if needed)
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ -w "$log_dir" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

log_section() {
    log_message ""
    log_message "$1"
}

check_docker_available() {
    if ! command -v "$DOCKER" &> /dev/null; then
        # Try common paths
        for path in /usr/local/bin/docker /opt/homebrew/bin/docker /usr/bin/docker; do
            if [[ -x "$path" ]]; then
                DOCKER="$path"
                break
            fi
        done
    fi

    if ! command -v "$DOCKER" &> /dev/null; then
        log_message "ERROR: Docker command not found"
        return 1
    fi

    if ! "$DOCKER" info &> /dev/null; then
        log_message "ERROR: Docker daemon is not running or not accessible"
        return 1
    fi

    return 0
}

bytes_to_gb() {
    local bytes="$1"
    echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc
}

parse_size_to_bytes() {
    local size="$1"
    local num unit

    # Extract number and unit (e.g., "12.5GB" -> "12.5" "GB")
    num=$(echo "$size" | sed 's/[^0-9.]//g')
    unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')

    case "$unit" in
        B)   echo "$num" | awk '{printf "%.0f", $1}' ;;
        KB)  echo "$num" | awk '{printf "%.0f", $1 * 1024}' ;;
        MB)  echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024}' ;;
        GB)  echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}' ;;
        TB)  echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024}' ;;
        *)   echo "0" ;;
    esac
}

check_disk_usage() {
    log_section "--- Disk Usage ---"

    local total_reclaimable_bytes=0

    # Get docker system df output in raw format for parsing
    local df_output
    df_output=$("$DOCKER" system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}')

    while IFS=$'\t' read -r type size reclaimable; do
        # Extract just the size part from reclaimable (e.g., "3.2GB (25%)" -> "3.2GB")
        local reclaim_size
        reclaim_size=$(echo "$reclaimable" | sed 's/ *(.*//')

        local reclaim_bytes
        reclaim_bytes=$(parse_size_to_bytes "$reclaim_size")
        total_reclaimable_bytes=$((total_reclaimable_bytes + reclaim_bytes))

        # Format output
        printf -v line "%-12s %s (%s reclaimable)" "$type:" "$size" "$reclaim_size"
        log_message "$line"
    done <<< "$df_output"

    # Calculate total reclaimable in GB
    TOTAL_RECLAIMABLE_GB=$(bytes_to_gb "$total_reclaimable_bytes")

    local threshold_exceeded
    threshold_exceeded=$(echo "$TOTAL_RECLAIMABLE_GB > $RECLAIMABLE_THRESHOLD_GB" | bc)

    if [[ "$threshold_exceeded" -eq 1 ]]; then
        log_message "Total Reclaimable: ${TOTAL_RECLAIMABLE_GB} GB ⚠️ PRUNE RECOMMENDED"
        PRUNE_RECOMMENDED=true
        ALERT_MESSAGES+=("${TOTAL_RECLAIMABLE_GB}GB reclaimable")
    else
        log_message "Total Reclaimable: ${TOTAL_RECLAIMABLE_GB} GB ✓"
    fi
}

check_dangling_resources() {
    log_section "--- Dangling Resources ---"

    # Count dangling images
    local dangling_images
    dangling_images=$("$DOCKER" images -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$dangling_images" -gt "$DANGLING_IMAGE_THRESHOLD" ]]; then
        log_message "Dangling Images:  $dangling_images ⚠️"
        PRUNE_RECOMMENDED=true
        ALERT_MESSAGES+=("$dangling_images dangling images")
    else
        log_message "Dangling Images:  $dangling_images ✓"
    fi

    # Count dangling volumes
    local dangling_volumes
    dangling_volumes=$("$DOCKER" volume ls -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$dangling_volumes" -gt "$DANGLING_VOLUME_THRESHOLD" ]]; then
        log_message "Dangling Volumes: $dangling_volumes ⚠️"
        PRUNE_RECOMMENDED=true
        ALERT_MESSAGES+=("$dangling_volumes dangling volumes")
    else
        log_message "Dangling Volumes: $dangling_volumes ✓"
    fi

    # Count unused networks (excluding default networks)
    local unused_networks
    unused_networks=$("$DOCKER" network ls -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$unused_networks" -gt "$DANGLING_NETWORK_THRESHOLD" ]]; then
        log_message "Unused Networks:  $unused_networks ⚠️"
        PRUNE_RECOMMENDED=true
        ALERT_MESSAGES+=("$unused_networks unused networks")
    else
        log_message "Unused Networks:  $unused_networks ✓"
    fi
}

check_stopped_containers() {
    log_section "--- Stopped Containers ---"

    # Get containers that are not running (exited, created, dead, restarting)
    local stopped_containers
    stopped_containers=$("$DOCKER" ps -a --filter "status=exited" \
                                         --filter "status=created" \
                                         --filter "status=dead" \
                                         --filter "status=restarting" \
                                         --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Label "com.docker.compose.project"}}' 2>/dev/null)

    if [[ -z "$stopped_containers" ]]; then
        log_message "All containers are running ✓"
        return
    fi

    STOPPED_CONTAINER_COUNT=$(echo "$stopped_containers" | wc -l | tr -d ' ')
    STOPPED_CONTAINERS_FOUND=true

    log_message "⚠️ WARNING: $STOPPED_CONTAINER_COUNT container(s) are not running:"
    log_message ""

    # Print header
    printf -v header "%-20s %-25s %-25s %-10s" "NAME" "IMAGE" "STATUS" "PROJECT"
    log_message "$header"
    log_message "$(printf '%.0s-' {1..80})"

    # Print each stopped container
    while IFS=$'\t' read -r name image status project; do
        [[ -z "$name" ]] && continue

        # Truncate long values
        [[ ${#name} -gt 20 ]] && name="${name:0:17}..."
        [[ ${#image} -gt 25 ]] && image="${image:0:22}..."
        [[ ${#status} -gt 25 ]] && status="${status:0:22}..."
        [[ -z "$project" ]] && project="-"

        printf -v line "%-20s %-25s %-25s %-10s" "$name" "$image" "$status" "$project"
        log_message "$line"
    done <<< "$stopped_containers"
}

generate_report() {
    log_section "--- Recommendation ---"

    if [[ "$STOPPED_CONTAINERS_FOUND" == true ]] && [[ "$PRUNE_RECOMMENDED" == true ]]; then
        log_message "⚠️ Prune is recommended, BUT review stopped containers first!"
        log_message "Some containers may need to be restarted before pruning."
        log_message ""
        log_message "To restart all stopped containers:"
        log_message "  docker start \$(docker ps -aq -f status=exited)"
        log_message ""
        log_message "To prune (after reviewing stopped containers):"
        log_message "  docker system prune -a --volumes"
    elif [[ "$STOPPED_CONTAINERS_FOUND" == true ]]; then
        log_message "⚠️ Review stopped containers - some may need attention"
        log_message ""
        log_message "To view logs for a stopped container:"
        log_message "  docker logs <container_name>"
    elif [[ "$PRUNE_RECOMMENDED" == true ]]; then
        log_message "✓ No stopped containers. Safe to prune."
        log_message ""
        log_message "Run: docker system prune -a --volumes"
    else
        log_message "✓ Docker system is healthy. No action needed."
    fi
}

push_to_uptime_kuma() {
    [[ -z "$UPTIME_KUMA_PUSH_URL" ]] && return

    local status="up"
    local msg="OK"

    if [[ "$STOPPED_CONTAINERS_FOUND" == true ]]; then
        status="down"
        msg="ALERT - $STOPPED_CONTAINER_COUNT containers stopped"
    elif [[ "$PRUNE_RECOMMENDED" == true ]]; then
        status="up"
        msg="PRUNE_RECOMMENDED - ${TOTAL_RECLAIMABLE_GB}GB reclaimable"
    else
        msg="OK - No issues found"
    fi

    # URL encode the message
    local encoded_msg
    encoded_msg=$(printf '%s' "$msg" | sed 's/ /%20/g; s/\./%2E/g')

    # Push to Uptime Kuma (silent, with timeout)
    local push_url="${UPTIME_KUMA_PUSH_URL}?status=${status}&msg=${encoded_msg}"

    if command -v curl &> /dev/null; then
        curl -fsS -m 10 "$push_url" > /dev/null 2>&1 || true
    elif command -v wget &> /dev/null; then
        wget -q -T 10 -O /dev/null "$push_url" 2>/dev/null || true
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_message "=== Docker Health Check Report ==="
    log_message "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "Host: $(hostname)"

    # Verify Docker is available
    if ! check_docker_available; then
        push_to_uptime_kuma
        exit 1
    fi

    # Run all checks
    check_disk_usage
    check_dangling_resources
    check_stopped_containers
    generate_report

    log_message ""
    log_message "=== End Report ==="

    # Push status to Uptime Kuma
    push_to_uptime_kuma

    # Exit with appropriate code for monitoring
    if [[ "$STOPPED_CONTAINERS_FOUND" == true ]]; then
        exit 2  # Warning: stopped containers
    elif [[ "$PRUNE_RECOMMENDED" == true ]]; then
        exit 0  # Info: prune recommended but not critical
    else
        exit 0  # Healthy
    fi
}

main "$@"
