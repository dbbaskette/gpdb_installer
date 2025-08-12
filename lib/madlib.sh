#!/bin/bash

# MADlib installer library for Greenplum Installer
# - Finds MADlib RPM in files/
# - Distributes and installs on all GP hosts
# - Enables MADlib extension in the target database

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

readonly MADLIB_RPM_PATTERNS=(
  "madlib*gp7*.rpm"
  "madlib-oss-gp7-*.rpm"
  "madlib-*.rpm"
)

# Return 0 if we should attempt MADlib install
should_install_madlib() {
  local v="${INSTALL_MADLIB}"
  local v_lc=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
  if [ "$v_lc" = "true" ]; then
    return 0
  fi
  # Auto-detect based on artifact presence
  if find_madlib_installer "$INSTALL_FILES_DIR" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

find_madlib_installer() {
  local install_files_dir="${1:-files}"
  local found=""
  for pattern in "${MADLIB_RPM_PATTERNS[@]}"; do
    found=$(find "$install_files_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n1)
    [ -n "$found" ] && { echo "$found"; return 0; }
  done
  return 1
}

distribute_madlib_installer() {
  local installer_file="$1"
  local hosts=("${@:2}")
  log_info "Distributing MADlib installer to hosts..."
  for host in "${hosts[@]}"; do
    log_info "Copying MADlib installer to $host..."
    if ! ssh_copy_file "$installer_file" "$host" "/tmp/"; then
      log_error "Failed to copy MADlib installer to $host"
      return 1
    fi
  done
  log_success "MADlib installer distributed"
}

install_madlib_single() {
  local host="$1"
  local installer_file="$2"
  local sudo_password="$3"
  log_info_with_timestamp "Installing MADlib on $host..."
  local remote_installer_path="/tmp/$(basename "$installer_file")"
  local remote_script="
    set -e
    echo 'Installing MADlib...'
    if echo '$sudo_password' | sudo -S rpm -qa | grep -qi '^madlib'; then
      echo 'MADlib already installed on $host'
      exit 0
    fi
    echo '$sudo_password' | sudo -S yum install -y $remote_installer_path || echo '$sudo_password' | sudo -S dnf install -y $remote_installer_path
    rm -f $remote_installer_path
  "
  if ssh_execute "$host" "$remote_script"; then
    log_success_with_timestamp "MADlib installed on $host"
  else
    log_error_with_timestamp "MADlib installation failed on $host"
    return 1
  fi
}

install_madlib_binaries() {
  local args=("$@")
  local last_index=$((${#args[@]}-1))
  local installer_file="${args[$last_index]}"
  unset 'args[$last_index]'
  local hosts=("${args[@]}")
  log_info "Installing MADlib on all Greenplum hosts..."
  local failed=()
  for host in "${hosts[@]}"; do
    if ! install_madlib_single "$host" "$installer_file" "$SUDO_PASSWORD"; then
      failed+=("$host")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    log_error "MADlib installation failed on: ${failed[*]}"
    return 1
  fi
  log_success "MADlib installed on all hosts"
}

enable_madlib_extension() {
  local coordinator_host="$1"
  local database_name="${2:-tdi}"
  log_info "Creating MADlib extension in database '$database_name'..."
  local sql_script="
    set -e
    source ~/.bashrc
    psql -d $database_name -c \"CREATE EXTENSION IF NOT EXISTS madlib;\"
    psql -d $database_name -c \"SELECT extname, extversion FROM pg_extension WHERE extname='madlib';\"
  "
  if ssh_execute "$coordinator_host" "$sql_script" "" "false" "gpadmin"; then
    log_success "MADlib extension enabled in '$database_name'"
    return 0
  else
    log_warn "Failed to enable MADlib extension in '$database_name'"
    return 0
  fi
}

install_madlib_full() {
  local all_hosts=("$(get_all_hosts)")
  read -r -a all_hosts <<< "$(get_all_hosts)"
  local installer_file
  if ! installer_file=$(find_madlib_installer "$INSTALL_FILES_DIR"); then
    log_error "MADlib installer not found in '$INSTALL_FILES_DIR'"
    return 1
  fi
  distribute_madlib_installer "$installer_file" "${all_hosts[@]}"
  install_madlib_binaries "${all_hosts[@]}" "$installer_file"
  enable_madlib_extension "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
}

# Verify MADlib installation by checking extension and calling version()
verify_madlib_installation() {
  local coordinator_host="$1"
  local database_name="${2:-tdi}"
  log_info "Verifying MADlib installation in '$database_name'..."
  local verify_script="
    set -e
    source ~/.bashrc
    echo 'Checking madlib extension...'
    psql -d $database_name -t -c \"SELECT extversion FROM pg_extension WHERE extname='madlib';\" | xargs
    echo 'Attempting madlib.version() call...'
    psql -d $database_name -t -c \"SELECT madlib.version();\" 2>/dev/null | xargs || true
  "
  if ssh_execute "$coordinator_host" "$verify_script" "" "false" "gpadmin"; then
    log_success "MADlib verification executed (check output above for version)."
  else
    log_warn "MADlib verification failed to execute."
  fi
}


