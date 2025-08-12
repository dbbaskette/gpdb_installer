#!/bin/bash

# PostGIS installer library for Greenplum Installer
# - Finds PostGIS RPMs in files/
# - Installs required GEOS/Proj/GDAL dependencies if present in files/ or repos
# - Enables postgis extension in target DB

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

readonly POSTGIS_RPM_PATTERNS=(
  "postgis*gp7*.rpm"
  "postgis-gp7-*.rpm"
  "postgis-*.rpm"
)

should_install_postgis() {
  local v="${INSTALL_POSTGIS}"
  local v_lc=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
  if [ "$v_lc" = "true" ]; then
    return 0
  fi
  if find_postgis_installer "$INSTALL_FILES_DIR" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

find_postgis_installer() {
  local install_files_dir="${1:-files}"
  local found=""
  for pattern in "${POSTGIS_RPM_PATTERNS[@]}"; do
    found=$(find "$install_files_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n1)
    [ -n "$found" ] && { echo "$found"; return 0; }
  done
  return 1
}

distribute_postgis_installer() {
  local installer_file="$1"
  local hosts=("${@:2}")
  log_info "Distributing PostGIS installer to hosts..."
  for host in "${hosts[@]}"; do
    if ! ssh_copy_file "$installer_file" "$host" "/tmp/"; then
      log_error "Failed to copy PostGIS installer to $host"
      return 1
    fi
  done
  log_success "PostGIS installer distributed"
}

install_postgis_single() {
  local host="$1"
  local installer_file="$2"
  local sudo_password="$3"
  log_info_with_timestamp "Installing PostGIS on $host..."
  local remote_installer_path="/tmp/$(basename "$installer_file")"
  local remote_script="
    set -e
    echo 'Installing PostGIS dependencies and package...'
    # Try to install typical deps from repos if not bundled
    echo '$sudo_password' | sudo -S yum install -y geos geos-devel proj proj-devel gdal gdal-devel || \
      echo '$sudo_password' | sudo -S dnf install -y geos geos-devel proj proj-devel gdal gdal-devel || true
    # Install RPM
    echo '$sudo_password' | sudo -S yum install -y $remote_installer_path || echo '$sudo_password' | sudo -S dnf install -y $remote_installer_path
    rm -f $remote_installer_path
  "
  if ssh_execute "$host" "$remote_script"; then
    log_success_with_timestamp "PostGIS installed on $host"
  else
    log_error_with_timestamp "PostGIS installation failed on $host"
    return 1
  fi
}

install_postgis_binaries() {
  local args=("$@")
  local last_index=$((${#args[@]}-1))
  local installer_file="${args[$last_index]}"
  unset 'args[$last_index]'
  local hosts=("${args[@]}")
  log_info "Installing PostGIS on all Greenplum hosts..."
  local failed=()
  for host in "${hosts[@]}"; do
    if ! install_postgis_single "$host" "$installer_file" "$SUDO_PASSWORD"; then
      failed+=("$host")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    log_error "PostGIS installation failed on: ${failed[*]}"
    return 1
  fi
  log_success "PostGIS installed on all hosts"
}

enable_postgis_extension() {
  local coordinator_host="$1"
  local database_name="${2:-tdi}"
  log_info "Creating PostGIS extensions in '$database_name'..."
  local sql_script="
    set -e
    source ~/.bashrc
    psql -d $database_name -v ON_ERROR_STOP=1 -c \"CREATE EXTENSION IF NOT EXISTS postgis;\"
    psql -d $database_name -v ON_ERROR_STOP=1 -c \"CREATE EXTENSION IF NOT EXISTS postgis_topology;\" || true
    psql -d $database_name -c \"SELECT extname, extversion FROM pg_extension WHERE extname like 'postgis%';\"
  "
  if ssh_execute "$coordinator_host" "$sql_script" "" "false" "gpadmin"; then
    log_success "PostGIS extensions enabled in '$database_name'"
    return 0
  else
    log_warn "Failed to enable PostGIS extensions in '$database_name'"
    return 0
  fi
}

install_postgis_full() {
  read -r -a all_hosts <<< "$(get_all_hosts)"
  local installer_file
  if ! installer_file=$(find_postgis_installer "$INSTALL_FILES_DIR"); then
    log_error "PostGIS installer not found in '$INSTALL_FILES_DIR'"
    return 1
  fi
  distribute_postgis_installer "$installer_file" "${all_hosts[@]}"
  install_postgis_binaries "${all_hosts[@]}" "$installer_file"
  enable_postgis_extension "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
}

# Verify PostGIS installation by checking extensions and running a basic function
verify_postgis_installation() {
  local coordinator_host="$1"
  local database_name="${2:-tdi}"
  log_info "Verifying PostGIS installation in '$database_name'..."
  local verify_script="
    set -e
    source ~/.bashrc
    echo 'Checking postgis extensions...'
    psql -d $database_name -c \"SELECT extname, extversion FROM pg_extension WHERE extname LIKE 'postgis%';\"
    echo 'Running ST_AsText on a simple point...'
    psql -d $database_name -t -c \"SELECT ST_AsText(ST_GeomFromText('POINT(0 0)'));\" 2>/dev/null | xargs || true
  "
  if ssh_execute "$coordinator_host" "$verify_script" "" "false" "gpadmin"; then
    log_success "PostGIS verification executed (check output above)."
  else
    log_warn "PostGIS verification failed to execute."
  fi
}


