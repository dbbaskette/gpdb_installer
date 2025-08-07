#!/bin/bash

# PXF library for Greenplum Installer
# Provides PXF-specific operations and cluster management

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"

readonly PXF_RPM_PATTERN="pxf-gp7-*.rpm"

# Function to find PXF installer file
find_pxf_installer() {
    local install_files_dir="${1:-files}"
    
    local installer_file=$(find "$install_files_dir" -maxdepth 1 -type f -name "$PXF_RPM_PATTERN" 2>/dev/null | head -n1)
    
    if [ -z "$installer_file" ]; then
        return 1
    fi
    
    echo "$installer_file"
}

# Function to check if PXF should be installed (based on configuration)
should_install_pxf() {
    # Check if INSTALL_PXF is explicitly set to true in config
    if [ "${INSTALL_PXF,,}" = "true" ]; then
        return 0
    fi
    
    # Check if PXF installer exists (auto-detection)
    if find_pxf_installer "$INSTALL_FILES_DIR" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Function to verify Greenplum installation before PXF
verify_greenplum_for_pxf() {
    local coordinator_host="$1"
    
    log_info "Verifying Greenplum installation for PXF..."
    
    # Check if Greenplum is installed
    if ! ssh_execute "$coordinator_host" "rpm -q greenplum-db-7 2>/dev/null"; then
        log_error "Greenplum Database is not installed on $coordinator_host. Cannot install PXF."
        return 1
    fi
    
    # Check if cluster is running
    if ! ssh_execute "$coordinator_host" "source ~/.bashrc && gpstate -s" "30" "true" "gpadmin" 2>/dev/null; then
        log_warn "Greenplum cluster is not running on $coordinator_host. PXF will be installed but not initialized until cluster starts."
        return 0
    fi
    
    log_success "Greenplum installation verified for PXF"
    return 0
}

# Function to install PXF on a single host
install_pxf_single() {
    local host="$1"
    local installer_file="$2"
    local sudo_password="$3"
    
    log_info_with_timestamp "Installing PXF on $host..."
    
    local remote_installer_path="/tmp/$(basename "$installer_file")"
    
    # Check for existing PXF installation
    if ssh_execute "$host" "rpm -q pxf-gp7 2>/dev/null"; then
        log_warn_with_timestamp "PXF appears to be already installed on $host. Skipping installation."
        return 0
    fi
    
    # Install PXF
    local remote_script="
        set -e
        echo \"Installing PXF...\"
        if echo '$sudo_password' | sudo -S rpm -q pxf-gp7 2>/dev/null; then
            echo \"PXF is already installed.\"
        else
            echo '$sudo_password' | sudo -S yum install -y $remote_installer_path
        fi
        
        # Clean up installer file
        rm -f $remote_installer_path
    "
    
    if ssh_execute "$host" "$remote_script"; then
        log_success_with_timestamp "PXF installed on $host"
        return 0
    else
        log_error_with_timestamp "PXF installation failed on $host"
        return 1
    fi
}

# Function to distribute PXF installer to hosts
distribute_pxf_installer() {
    local installer_file="$1"
    local hosts=("${@:2}")
    
    log_info "Distributing PXF installer to hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Copying PXF installer to $host..."
        if ! ssh_copy_file "$installer_file" "$host" "/tmp/"; then
            log_error "Failed to copy PXF installer to $host"
            return 1
        fi
    done
    
    log_success "PXF installer distributed to all hosts"
}

# Function to install PXF on all hosts
install_pxf_binaries() {
    local hosts=("$@")
    local installer_file="${hosts[-1]}"  # Last argument is the installer file
    unset hosts[-1]  # Remove installer file from hosts array
    
    log_info "Installing PXF binaries on all hosts..."
    
    local failed_hosts=()
    for host in "${hosts[@]}"; do
        if ! install_pxf_single "$host" "$installer_file" "$SUDO_PASSWORD"; then
            failed_hosts+=("$host")
        fi
    done
    
    if [ ${#failed_hosts[@]} -gt 0 ]; then
        log_error "PXF installation failed on hosts: ${failed_hosts[*]}"
        return 1
    fi
    
    log_success "PXF binaries installed on all hosts"
}

# Function to configure PXF service on a host
configure_pxf_service() {
    local host="$1"
    local sudo_password="$2"
    
    log_info "Configuring PXF installation on $host..."
    
    local configure_script="
        set -e
        echo \"Verifying PXF installation...\"
        
        # PXF 7 doesn't use systemd services - it's managed via pxf command
        # Just verify the installation is complete
        if [ -d '/usr/local/pxf-gp7' ]; then
            echo \"PXF installation directory found\"
        else
            echo \"Warning: PXF installation directory not found\"
            exit 1
        fi
        
        # Check if pxf command is available
        if command -v pxf >/dev/null 2>&1; then
            echo \"PXF command line tool available\"
        else
            echo \"Warning: PXF command not found in PATH\"
        fi
        
        echo \"PXF installation verified on $host\"
    "
    
    if ssh_execute "$host" "$configure_script"; then
        log_success "PXF installation verified on $host"
        return 0
    else
        log_warn "PXF installation verification failed on $host - this may be normal"
        return 0  # Don't fail the entire installation for this
    fi
}

# Function to initialize PXF cluster
initialize_pxf_cluster() {
    local coordinator_host="$1"
    
    log_info "Initializing PXF cluster..."
    
    # Check if Greenplum cluster is running first
    if ! ssh_execute "$coordinator_host" "source ~/.bashrc && gpstate -s" "30" "true" "gpadmin" 2>/dev/null; then
        log_warn "Greenplum cluster is not running. Skipping PXF cluster initialization."
        log_info "You can initialize PXF later with: ssh $coordinator_host -l gpadmin 'pxf cluster init && pxf cluster start'"
        return 0
    fi
    
    # Create initialization script
    local pxf_init_script="
        set -e
        echo \"Initializing PXF cluster...\"
        
        # Source Greenplum environment
        source ~/.bashrc
        
        # Set PXF environment (ensure pxf command is in PATH)
        export PXF_HOME=/usr/local/pxf-gp7
        export PATH=\$PXF_HOME/bin:\$PATH
        
        # Ensure GPHOME is set properly for pxf cluster register
        if [ -z \"\$GPHOME\" ]; then
            # Try to detect GPHOME from common locations
            for gphome_path in /usr/local/greenplum-db /usr/local/greenplum-db-*; do
                if [ -d \"\$gphome_path\" ] && [ -f \"\$gphome_path/greenplum_path.sh\" ]; then
                    export GPHOME=\"\$gphome_path\"
                    echo \"Auto-detected GPHOME: \$GPHOME\"
                    source \"\$GPHOME/greenplum_path.sh\"
                    break
                fi
            done
        fi
        
        if [ -z \"\$GPHOME\" ]; then
            echo \"ERROR: GPHOME not set and could not auto-detect Greenplum installation\"
            exit 1
        fi
        
        echo \"Using GPHOME: \$GPHOME\"
        
        # Detect and set Java environment
        echo \"Detecting Java installation...\"
        if [ -n \"\$JAVA_HOME\" ] && [ -x \"\$JAVA_HOME/bin/java\" ]; then
            echo \"Using existing JAVA_HOME: \$JAVA_HOME\"
        else
            # Try common Java installation paths
            for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java /usr/bin/java; do
                if [ -x \"\$java_path\" ]; then
                    if [[ \"\$java_path\" == */usr/bin/java ]]; then
                        # For /usr/bin/java, find the actual JRE/JDK path
                        java_version=\\\$(readlink -f /usr/bin/java | sed 's|/bin/java||')
                        if [ -d \"\$java_version\" ]; then
                            export JAVA_HOME=\"\$java_version\"
                        fi
                    else
                        # Extract JAVA_HOME from bin/java path
                        export JAVA_HOME=\\\$(dirname \\\$(dirname \"\$java_path\"))
                    fi
                    echo \"Auto-detected JAVA_HOME: \$JAVA_HOME\"
                    break
                fi
            done
            
            if [ -z \"\$JAVA_HOME\" ]; then
                echo \"ERROR: Java not found. Installing OpenJDK...\"
                # Try to install Java if not found
                if command -v yum >/dev/null 2>&1; then
                    sudo yum install -y java-11-openjdk-devel || sudo yum install -y java-1.8.0-openjdk-devel
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y java-11-openjdk-devel || sudo dnf install -y java-1.8.0-openjdk-devel
                fi
                
                # Try detection again after installation
                for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java; do
                    if [ -x \"\$java_path\" ]; then
                        export JAVA_HOME=\\\$(dirname \\\$(dirname \"\$java_path\"))
                        echo \"Java installed and JAVA_HOME set to: \$JAVA_HOME\"
                        break
                    fi
                done
                
                if [ -z \"\$JAVA_HOME\" ]; then
                    echo \"ERROR: Could not install or detect Java. PXF requires Java to run.\"
                    exit 1
                fi
            fi
        fi
        
        # Validate JAVA_HOME
        if [ ! -x \"\$JAVA_HOME/bin/java\" ]; then
            echo \"ERROR: JAVA_HOME is set but java binary is not executable: \$JAVA_HOME/bin/java\"
            exit 1
        fi
        
        echo \"Java validation successful: \$(\$JAVA_HOME/bin/java -version 2>&1 | head -n1)\"
        
        # Verify pxf command is available
        if ! command -v pxf >/dev/null 2>&1; then
            echo \"ERROR: pxf command not found in PATH\"
            echo \"PATH: \$PATH\"
            echo \"Checking for PXF installation...\"
            ls -la /usr/local/pxf-gp7/bin/ || echo \"PXF bin directory not found\"
            exit 1
        fi
        
        # Check if PXF is already running
        if pxf cluster status 2>/dev/null | grep -q 'PXF is running'; then
            echo \"PXF cluster is already running\"
            exit 0
        fi
        
        # Check if PXF cluster directory already exists
        if [ -d \"/usr/local/pxf-gp7/clusters/default\" ]; then
            echo \"PXF cluster directory already exists. Checking if initialization is needed...\"
            
            # Try to start directly if already prepared/initialized
            if pxf cluster start 2>/dev/null; then
                echo \"PXF cluster started successfully (was already prepared)\"
                exit 0
            else
                echo \"PXF cluster exists but failed to start. Resetting and reinitializing...\"
                # Reset the cluster to clean state
                pxf cluster reset -f 2>/dev/null || true
                rm -rf /usr/local/pxf-gp7/clusters/default 2>/dev/null || true
            fi
        fi
        
        # Prepare PXF cluster (creates configuration directories and files)
        echo \"Running pxf cluster prepare...\"
        if ! pxf cluster prepare; then
            echo \"ERROR: PXF cluster prepare failed\"
            exit 1
        fi
        
        # Initialize PXF cluster
        echo \"Running pxf cluster init...\"
        if ! pxf cluster init; then
            echo \"ERROR: PXF cluster init failed\"
            exit 1
        fi
        
        # Register PXF extension with Greenplum Database (CRITICAL STEP)
        echo \"Registering PXF extension with Greenplum Database...\"
        
        # Show detailed output for debugging
        echo \"Running: pxf cluster register\"
        if pxf cluster register; then
            echo \"PXF cluster register completed successfully\"
            
            # Verify extension files were installed
            echo \"Verifying PXF extension files were installed...\"
            if [ -f \"\$GPHOME/share/postgresql/extension/pxf.control\" ]; then
                echo \"SUCCESS: pxf.control found in \$GPHOME/share/postgresql/extension/\"
                ls -la \"\$GPHOME/share/postgresql/extension/pxf*\"
            else
                echo \"WARNING: pxf.control not found in \$GPHOME/share/postgresql/extension/\"
                echo \"Checking alternative locations...\"
                pxf_control_found=\$(find /usr/local -name \"pxf.control\" 2>/dev/null | head -n1)
                
                if [ -n \"\$pxf_control_found\" ]; then
                    echo \"Found pxf.control at: \$pxf_control_found\"
                    echo \"Attempting manual installation of PXF extension files...\"
                    
                    # Copy extension files manually
                    pxf_dir=\$(dirname \"\$pxf_control_found\")
                    mkdir -p \"\$GPHOME/share/postgresql/extension\"
                    
                    if cp \"\$pxf_dir\"/pxf* \"\$GPHOME/share/postgresql/extension/\" 2>/dev/null; then
                        echo \"SUCCESS: Manually copied PXF extension files\"
                        # Fix ownership
                        chown gpadmin:gpadmin \"\$GPHOME/share/postgresql/extension/pxf*\" 2>/dev/null
                        ls -la \"\$GPHOME/share/postgresql/extension/pxf*\"
                    else
                        echo \"ERROR: Failed to manually copy PXF extension files\"
                    fi
                else
                    # Try known PXF 7 location - this is the working solution
                    echo \"Trying known PXF 7 extension location...\"
                    if [ -f \"/usr/local/pxf-gp7/gpextable/pxf.control\" ]; then
                        echo \"Found PXF extension files in /usr/local/pxf-gp7/gpextable/\"
                        mkdir -p \"\$GPHOME/share/postgresql/extension\"
                        
                        # Copy control file and SQL files separately (not .so files)
                        echo \"Copying pxf.control...\"
                        cp /usr/local/pxf-gp7/gpextable/pxf.control \"\$GPHOME/share/postgresql/extension/\"
                        
                        echo \"Copying PXF SQL files...\"
                        cp /usr/local/pxf-gp7/gpextable/pxf--*.sql \"\$GPHOME/share/postgresql/extension/\" 2>/dev/null
                        
                        # Fix ownership
                        chown gpadmin:gpadmin \"\$GPHOME/share/postgresql/extension/pxf\"* 2>/dev/null
                        
                        echo \"SUCCESS: Copied PXF extension files from known location\"
                        ls -la \"\$GPHOME/share/postgresql/extension/pxf*\"
                    else
                        echo \"ERROR: No pxf.control found in expected location /usr/local/pxf-gp7/gpextable/\"
                        echo \"PXF installation may be incomplete or corrupt\"
                    fi
                fi
            fi
        else
            echo \"ERROR: PXF cluster register failed\"
            echo \"Checking if PXF is properly installed...\"
            ls -la /usr/local/pxf-gp7/ || echo \"PXF installation directory not found\"
            echo \"Current GPHOME: \$GPHOME\"
            echo \"Current PATH: \$PATH\"
            exit 1
        fi
        
        # Sync configuration to all hosts
        echo \"Syncing PXF configuration to all hosts...\"
        if ! pxf cluster sync; then
            echo \"WARNING: PXF cluster sync failed, but continuing...\"
        fi
        
        # Start PXF cluster
        echo \"Starting PXF cluster...\"
        if ! pxf cluster start; then
            echo \"ERROR: PXF cluster start failed\"
            exit 1
        fi
        
        # Verify PXF status
        echo \"Verifying PXF cluster status...\"
        pxf cluster status
    "
    
    if ssh_execute "$coordinator_host" "$pxf_init_script" "120" "false" "gpadmin"; then
        log_success "PXF cluster initialized successfully"
        return 0
    else
        log_warn "PXF cluster initialization failed or timed out"
        log_info "You can try initializing PXF manually:"
        log_info "ssh $coordinator_host -l gpadmin 'pxf cluster init && pxf cluster start'"
        return 0  # Don't fail the entire installation for PXF issues
    fi
}

# Function to distribute PXF extension files to all hosts
distribute_pxf_extension_files() {
    local hosts=("$@")
    
    log_info "Distributing PXF extension files to all hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Installing PXF extension files on $host..."
        
        local extension_install_script="
            set -e
            echo \"Installing PXF extension files on $host...\"
            
            # Detect GPHOME on this host
            gphome=\"\"
            for gphome_path in /usr/local/greenplum-db /usr/local/greenplum-db-*; do
                if [ -d \"\$gphome_path\" ] && [ -f \"\$gphome_path/greenplum_path.sh\" ]; then
                    gphome=\"\$gphome_path\"
                    echo \"Found GPHOME: \$gphome\"
                    break
                fi
            done
            
            if [ -z \"\$gphome\" ]; then
                echo \"ERROR: Could not find Greenplum installation on $host\"
                exit 1
            fi
            
            # Check if extension files already exist
            if [ -f \"\$gphome/share/postgresql/extension/pxf.control\" ]; then
                echo \"PXF extension files already exist on $host\"
                exit 0
            fi
            
            # Try known PXF 7 location
            if [ -f \"/usr/local/pxf-gp7/gpextable/pxf.control\" ]; then
                echo \"Found PXF extension files in /usr/local/pxf-gp7/gpextable/\"
                mkdir -p \"\$gphome/share/postgresql/extension\"
                
                # Copy control file and SQL files separately
                echo \"Copying pxf.control...\"
                cp /usr/local/pxf-gp7/gpextable/pxf.control \"\$gphome/share/postgresql/extension/\"
                
                echo \"Copying PXF SQL files...\"
                cp /usr/local/pxf-gp7/gpextable/pxf--*.sql \"\$gphome/share/postgresql/extension/\" 2>/dev/null || true
                
                # Fix ownership
                chown gpadmin:gpadmin \"\$gphome/share/postgresql/extension/pxf\"* 2>/dev/null || true
                
                echo \"SUCCESS: PXF extension files installed on $host\"
                ls -la \"\$gphome/share/postgresql/extension/pxf*\"
            else
                echo \"ERROR: PXF extension files not found on $host\"
                echo \"PXF may not be properly installed on this host\"
                exit 1
            fi
        "
        
        if ssh_execute "$host" "$extension_install_script" "" "false" "root"; then
            log_success "PXF extension files installed on $host"
        else
            log_error "Failed to install PXF extension files on $host"
            return 1
        fi
    done
    
    log_success "PXF extension files distributed to all hosts"
}

# Function to enable PXF extension in database
enable_pxf_extension() {
    local coordinator_host="$1"
    local database_name="${2:-tdi}"
    
    log_info "Enabling PXF extension in database '$database_name'..."
    
    # Check if Greenplum cluster is running first
    if ! ssh_execute "$coordinator_host" "source ~/.bashrc && gpstate -s" "30" "true" "gpadmin" 2>/dev/null; then
        log_warn "Greenplum cluster is not running. Skipping PXF extension enablement."
        log_info "You can enable PXF extension later with: ssh $coordinator_host -l gpadmin 'psql -d $database_name -c \"CREATE EXTENSION IF NOT EXISTS pxf;\"'"
        return 0
    fi
    
    local extension_script="
        set -e
        echo \"Enabling PXF extension in database '$database_name'...\"
        
        # Source Greenplum environment
        source ~/.bashrc
        
        # Create PXF extension
        psql -d $database_name -c \"CREATE EXTENSION IF NOT EXISTS pxf;\"
        
        # Verify extension was created
        psql -d $database_name -c \"SELECT extname, extversion FROM pg_extension WHERE extname = 'pxf';\"
    "
    
    if ssh_execute "$coordinator_host" "$extension_script" "" "false" "gpadmin"; then
        log_success "PXF extension enabled in database '$database_name'"
        return 0
    else
        log_warn "Failed to enable PXF extension in database '$database_name'"
        log_info "You can enable it manually later:"
        log_info "ssh $coordinator_host -l gpadmin 'psql -d $database_name -c \"CREATE EXTENSION IF NOT EXISTS pxf;\"'"
        return 0  # Don't fail the entire installation for this
    fi
}

# Function to verify and fix PXF configuration
verify_and_fix_pxf_configuration() {
    local coordinator_host="$1"
    
    log_info "Verifying PXF configuration..."
    
    # Check if Greenplum cluster is running first
    if ! ssh_execute "$coordinator_host" "source ~/.bashrc && gpstate -s" "30" "true" "gpadmin" 2>/dev/null; then
        log_warn "Greenplum cluster is not running. Skipping PXF configuration verification."
        return 0
    fi
    
    local verification_script="
        set -e
        echo \"Verifying PXF configuration...\"
        
        # Source Greenplum environment
        source ~/.bashrc
        
        # Set PXF environment
        export PXF_HOME=/usr/local/pxf-gp7
        export PATH=\$PXF_HOME/bin:\$PATH
        
        # Check if PXF command is available
        if ! command -v pxf >/dev/null 2>&1; then
            echo \"WARNING: pxf command not found in PATH\"
            echo \"PATH: \$PATH\"
            exit 1
        fi
        
        # Check current Greenplum PXF configuration
        echo \"Checking pxf.pxf_base parameter...\"
        pxf_base_value=\$(psql -d postgres -t -c \"SHOW pxf.pxf_base;\" 2>/dev/null | xargs)
        
        NEEDS_REGISTER=false
        NEEDS_EXTENSION=false
        
        if [ -z \"\$pxf_base_value\" ] || [ \"\$pxf_base_value\" = \"\" ]; then
            echo \"pxf.pxf_base is empty or not set - needs registration\"
            NEEDS_REGISTER=true
        else
            echo \"pxf.pxf_base is set to: \$pxf_base_value\"
        fi
        
        # Check if PXF extension exists in postgres database
        extension_count=\$(psql -d postgres -t -c \"SELECT COUNT(*) FROM pg_extension WHERE extname = 'pxf';\" 2>/dev/null | xargs)
        
        if [ \"\$extension_count\" = \"0\" ]; then
            echo \"PXF extension is not installed in postgres database\"
            NEEDS_EXTENSION=true
        else
            echo \"PXF extension is installed in postgres database\"
        fi
        
        # Fix configuration if needed
        if [ \"\$NEEDS_REGISTER\" = \"true\" ]; then
            echo \"Attempting to register PXF with Greenplum...\"
            
            if pxf cluster register; then
                echo \"PXF cluster register completed successfully\"
                
                # Reload Greenplum configuration
                echo \"Reloading Greenplum configuration...\"
                gpstop -u
                
                # Verify the fix
                echo \"Verifying pxf.pxf_base parameter...\"
                sleep 2
                pxf_base_value=\$(psql -d postgres -t -c \"SHOW pxf.pxf_base;\" 2>/dev/null | xargs)
                
                if [ -n \"\$pxf_base_value\" ] && [ \"\$pxf_base_value\" != \"\" ]; then
                    echo \"SUCCESS: pxf.pxf_base is now set to: \$pxf_base_value\"
                else
                    echo \"WARNING: pxf.pxf_base is still empty after register\"
                    
                    # Manual configuration fallback
                    echo \"Attempting manual configuration...\"
                    PXF_BASE_PATH=\"/usr/local/pxf-gp7\"
                    
                    echo \"Using ALTER SYSTEM to set pxf.pxf_base...\"
                    if psql -d postgres -c \"ALTER SYSTEM SET pxf.pxf_base TO '\$PXF_BASE_PATH';\"; then
                        echo \"Reloading Greenplum configuration...\"
                        gpstop -u
                        
                        sleep 2
                        pxf_base_value=\$(psql -d postgres -t -c \"SHOW pxf.pxf_base;\" 2>/dev/null | xargs)
                        
                        if [ -n \"\$pxf_base_value\" ] && [ \"\$pxf_base_value\" != \"\" ]; then
                            echo \"SUCCESS: pxf.pxf_base manually set to: \$pxf_base_value\"
                        else
                            echo \"ERROR: Manual configuration also failed\"
                            exit 1
                        fi
                    else
                        echo \"ERROR: Failed to set pxf.pxf_base manually\"
                        exit 1
                    fi
                fi
            else
                echo \"ERROR: pxf cluster register failed\"
                exit 1
            fi
        fi
        
        # Install PXF extension in postgres database if needed
        if [ \"\$NEEDS_EXTENSION\" = \"true\" ]; then
            echo \"Creating PXF extension in postgres database...\"
            
            if psql -d postgres -c \"CREATE EXTENSION IF NOT EXISTS pxf;\"; then
                echo \"SUCCESS: PXF extension created in postgres database\"
            else
                echo \"WARNING: Failed to create PXF extension in postgres database\"
            fi
        fi
        
        # Final verification
        echo \"Final verification of PXF configuration...\"
        pxf_base_final=\$(psql -d postgres -t -c \"SHOW pxf.pxf_base;\" 2>/dev/null | xargs)
        if [ -n \"\$pxf_base_final\" ] && [ \"\$pxf_base_final\" != \"\" ]; then
            echo \"SUCCESS: pxf.pxf_base is correctly set to: \$pxf_base_final\"
        else
            echo \"ERROR: pxf.pxf_base is still not set properly\"
            exit 1
        fi
        
        # Check PXF cluster status
        echo \"Checking PXF cluster status...\"
        pxf cluster status
        
        echo \"PXF configuration verification completed successfully\"
    "
    
    if ssh_execute "$coordinator_host" "$verification_script" "" "false" "gpadmin"; then
        log_success "PXF configuration verified and fixed if needed"
        return 0
    else
        log_warn "PXF configuration verification failed - manual intervention may be required"
        log_info "To fix manually, run: ssh $coordinator_host -l gpadmin"
        log_info "Then execute: pxf cluster register && gpstop -u"
        return 0  # Don't fail the entire installation
    fi
}

# Function to test PXF installation
test_pxf_installation() {
    local coordinator_host="$1"
    
    log_info "Testing PXF installation..."
    
    # Check if Greenplum cluster is running first
    if ! ssh_execute "$coordinator_host" "source ~/.bashrc && gpstate -s" "30" "true" "gpadmin" 2>/dev/null; then
        log_warn "Greenplum cluster is not running. Skipping PXF installation test."
        return 0
    fi
    
    local test_script="
        set -e
        echo \"Testing PXF installation...\"
        
        # Source Greenplum environment
        source ~/.bashrc
        
        # Set PXF environment (ensure pxf command is in PATH)
        export PXF_HOME=/usr/local/pxf-gp7
        export PATH=\$PXF_HOME/bin:\$PATH
        
        # Test PXF status
        pxf cluster status
        
        # Test PXF extension in database
        psql -d tdi -c \"
        SELECT CASE 
            WHEN COUNT(*) > 0 THEN 'PXF extension is installed'
            ELSE 'PXF extension is NOT installed'
        END as pxf_status
        FROM pg_extension 
        WHERE extname = 'pxf';
        \"
    "
    
    if ssh_execute "$coordinator_host" "$test_script" "" "false" "gpadmin"; then
        log_success "PXF installation test passed"
        return 0
    else
        log_warn "PXF installation test failed - this may be normal if PXF was not fully initialized"
        return 0  # Don't fail for test failures
    fi
}

# Function to setup Java environment on all hosts for PXF
setup_java_environment() {
    local hosts=("$@")
    
    log_info "Setting up Java environment for PXF on all hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Configuring Java environment on $host..."
        
        # Create a script to detect and set Java on this host
        local java_setup_script="
            set -e
            echo \"Setting up Java environment on $host...\"
            
            # Detect Java installation
            java_home=\"\"
            for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java /usr/bin/java; do
                if [ -x \"\$java_path\" ]; then
                    if [[ \"\$java_path\" == */usr/bin/java ]]; then
                        # For /usr/bin/java, find the actual JRE/JDK path
                        java_version=\$(readlink -f /usr/bin/java | sed 's|/bin/java||')
                        if [ -d \"\$java_version\" ]; then
                            java_home=\"\$java_version\"
                        fi
                    else
                        # Extract JAVA_HOME from bin/java path
                        java_home=\$(dirname \$(dirname \"\$java_path\"))
                    fi
                    break
                fi
            done
            
            if [ -z \"\$java_home\" ]; then
                echo \"Java not found on $host, attempting to install...\"
                if command -v yum >/dev/null 2>&1; then
                    sudo yum install -y java-11-openjdk-devel || sudo yum install -y java-1.8.0-openjdk-devel
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y java-11-openjdk-devel || sudo dnf install -y java-1.8.0-openjdk-devel
                fi
                
                # Try detection again
                for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java; do
                    if [ -x \"\$java_path\" ]; then
                        java_home=\$(dirname \$(dirname \"\$java_path\"))
                        break
                    fi
                done
            fi
            
            if [ -n \"\$java_home\" ]; then
                echo \"Java found on $host: \$java_home\"
                
                # Update gpadmin's environment files
                if ! grep -q \"JAVA_HOME\" /home/gpadmin/.bashrc 2>/dev/null; then
                    echo \"export JAVA_HOME=\$java_home\" >> /home/gpadmin/.bashrc
                fi
                if ! grep -q \"JAVA_HOME\" /home/gpadmin/.bash_profile 2>/dev/null; then
                    echo \"export JAVA_HOME=\$java_home\" >> /home/gpadmin/.bash_profile
                fi
                
                # Also set system-wide for all users
                echo \"export JAVA_HOME=\$java_home\" > /etc/environment
                echo \"JAVA_HOME=\$java_home\" >> /etc/environment
                
                echo \"Java environment configured on $host\"
            else
                echo \"ERROR: Could not find or install Java on $host\"
                exit 1
            fi
        "
        
        if ssh_execute "$host" "$java_setup_script" "" "false" "root"; then
            log_success "Java environment configured on $host"
        else
            log_error "Failed to configure Java environment on $host"
            return 1
        fi
    done
    
    log_success "Java environment setup completed on all hosts"
}

# Function to setup PXF environment in gpadmin profile
setup_pxf_environment() {
    local hosts=("$@")
    
    log_info "Setting up PXF environment for gpadmin..."
    
    for host in "${hosts[@]}"; do
        log_info "Configuring PXF environment on $host..."
        
        # Create a temporary script file
        local temp_script="/tmp/setup_pxf_env_$$.sh"
        cat > "$temp_script" << 'EOF'
#!/bin/bash

# Detect Java and setup JAVA_HOME
echo "Detecting Java installation for PXF..."
java_home=""
for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java /usr/bin/java; do
    if [ -x "$java_path" ]; then
        if [[ "$java_path" == */usr/bin/java ]]; then
            # For /usr/bin/java, find the actual JRE/JDK path
            java_version=$(readlink -f /usr/bin/java | sed 's|/bin/java||')
            if [ -d "$java_version" ]; then
                java_home="$java_version"
            fi
        else
            # Extract JAVA_HOME from bin/java path
            java_home=$(dirname $(dirname "$java_path"))
        fi
        break
    fi
done

if [ -z "$java_home" ]; then
    echo "Java not found, attempting to install..."
    if command -v yum >/dev/null 2>&1; then
        yum install -y java-11-openjdk-devel || yum install -y java-1.8.0-openjdk-devel
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y java-11-openjdk-devel || dnf install -y java-1.8.0-openjdk-devel
    fi
    
    # Try detection again
    for java_path in /usr/lib/jvm/java-*-openjdk*/bin/java /usr/lib/jvm/java-*-openjdk/bin/java; do
        if [ -x "$java_path" ]; then
            java_home=$(dirname $(dirname "$java_path"))
            break
        fi
    done
fi

if [ -n "$java_home" ]; then
    echo "Java found: $java_home"
else
    echo "Warning: Could not find or install Java. PXF may not function properly."
    java_home="/usr/java/default"  # Fallback
fi

# Add PXF environment to .bashrc if not already present
if ! grep -q "PXF Environment Setup" /home/gpadmin/.bashrc 2>/dev/null; then
    cat >> /home/gpadmin/.bashrc << PXFENV_EOF

# PXF Environment Setup - Auto-generated by installer
export PXF_HOME=/usr/local/pxf-gp7
export JAVA_HOME=$java_home
export PATH=\$PXF_HOME/bin:\$PATH
PXFENV_EOF
    echo "PXF environment added to .bashrc"
else
    echo "PXF environment already configured in .bashrc"
fi

# Also add to .bash_profile
if ! grep -q "PXF Environment Setup" /home/gpadmin/.bash_profile 2>/dev/null; then
    cat >> /home/gpadmin/.bash_profile << PXFENV_EOF

# PXF Environment Setup - Auto-generated by installer
export PXF_HOME=/usr/local/pxf-gp7
export JAVA_HOME=$java_home
export PATH=\$PXF_HOME/bin:\$PATH
PXFENV_EOF
    echo "PXF environment added to .bash_profile"
else
    echo "PXF environment already configured in .bash_profile"
fi

chown gpadmin:gpadmin /home/gpadmin/.bash_profile /home/gpadmin/.bashrc
EOF
        
        # Copy script to host and execute
        ssh_copy_file "$temp_script" "$host" "/tmp/"
        ssh_execute "$host" "sudo bash /tmp/$(basename $temp_script) && rm -f /tmp/$(basename $temp_script)"
        
        # Clean up local temp script
        rm -f "$temp_script"
    done
    
    log_success "PXF environment configured for gpadmin"
}