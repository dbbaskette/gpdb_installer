# PXF Installation Guide and Troubleshooting

This document provides a comprehensive guide to installing, configuring, and troubleshooting the Greenplum Platform Extension Framework (PXF).

## 1. PXF Architecture and Key Changes (PXF 7+)

- **No SystemD Services**: PXF is managed via the `pxf` command-line tool, not `systemctl`.
- **Installation Location**: `/usr/local/pxf-gp7/`
- **Configuration**: Managed through Greenplum cluster operations.

## 2. Installation and Initialization Workflow

The installer follows a specific workflow to ensure a reliable PXF setup.

### Phase 1: Root-Level Operations

1.  **Install PXF Binaries**: The PXF RPM is installed on all hosts.
2.  **Setup Java Environment**:
    *   **Problem**: PXF requires Java, but it might not be installed or configured.
    *   **Solution**: The installer automatically installs `java-11-openjdk-devel` and configures `JAVA_HOME` on all hosts in `/etc/environment`, `/home/gpadmin/.bashrc`, and `/home/gpadmin/.bash_profile`. This ensures the Java environment is available for all users and services.
3.  **Fix Directory Ownership**: Sets the correct ownership (`gpadmin:gpadmin`) for the PXF installation directory.

### Phase 2: gpadmin-Level Operations

This phase is executed as the `gpadmin` user.

1.  **Check for Existing PXF Installation**:
    *   **Problem**: Re-running the installer on a system with a partial or complete PXF installation would fail.
    *   **Solution**: The installer now checks if PXF is already running. If so, it skips initialization. If a cluster directory exists but PXF is not running, it attempts to start it. If that fails, it resets the cluster to ensure a clean installation.
2.  **Initialize the PXF Cluster**: This involves a sequence of `pxf cluster` commands:
    1.  `pxf cluster prepare`: Creates the configuration directories.
    2.  `pxf cluster init`: Initializes the cluster.
    3.  `pxf cluster register`: **(Critical Step)** Registers the PXF extension with Greenplum by copying the necessary files (`pxf.control`, `pxf--*.sql`) to the Greenplum extension directory. This was a common point of failure.
    4.  `pxf cluster sync`: Distributes the PXF configuration to all segment hosts.
    5.  `pxf cluster start`: Starts the PXF cluster.
3.  **Enable PXF Extension**: Runs `CREATE EXTENSION IF NOT EXISTS pxf;` in the specified database.
4.  **Test PXF Installation**: Verifies that the PXF service is running and accessible.

## 3. Common Issues and Solutions

### Issue: `pxf command not found`

-   **Cause**: The PXF binary directory (`/usr/local/pxf-gp7/bin`) is not in the `gpadmin` user's `PATH`.
-   **Solution**: The installer now adds the PXF binary directory to the `gpadmin` user's `.bashrc` and `.bash_profile`.

### Issue: `ERROR: $JAVA_HOME=... is invalid`

-   **Cause**: `JAVA_HOME` was not correctly set on all hosts in the cluster.
-   **Solution**: The installer now includes a dedicated function (`setup_java_environment`) that runs on all hosts to detect the Java installation, set `JAVA_HOME` in multiple environment files, and install Java if it's missing.

### Issue: `ERROR: could not open extension control file ... pxf.control: No such file or directory`

-   **Cause**: The `pxf cluster register` command was not being run, so the extension files were not copied to the Greenplum directory.
-   **Solution**: The `pxf cluster register` command is now a standard part of the initialization sequence.

### Issue: `ERROR: The cluster directory ... is not empty. Did you already run 'pxf prepare'?`

-   **Cause**: Re-running the installer after a partial installation.
-   **Solution**: The installer now has logic to detect an existing cluster, try to start it, or reset it if necessary.

### Issue: Excessive Password Prompts

-   **Cause**: Frequent switching between `root` and `gpadmin` user contexts, and short SSH connection timeouts.
-   **Solution**:
    *   Operations are now grouped by user context (all `root` tasks, then all `gpadmin` tasks) to minimize context switching.
    *   The SSH connection timeout has been increased from 10 to 30 minutes.
    *   A connection refresh mechanism has been added to re-establish lost SSH connections.

### Issue: `Permission denied` errors related to `/root` directory

-   **Cause**: Running commands as `root` and then using `sudo -u gpadmin`, which caused confusion about the user context and home directory.
-   **Solution**: All `gpadmin`-level commands are now executed by connecting directly as the `gpadmin` user, ensuring a clean user context.

## 4. Standalone PXF Installer

The project includes a standalone PXF installer (`pxf_installer.sh`). A bug was fixed where a necessary function (`setup_java_environment`) was not available, causing the installer to fail. The function was copied into the standalone installer to make it self-contained.

## 5. Manual Troubleshooting

-   **Check PXF Status**: `ssh <coordinator-host> -l gpadmin 'pxf cluster status'`
-   **Verify Java Home**: `ssh <any-host> -l gpadmin 'echo $JAVA_HOME'`
-   **Check Extension Files**: `ssh <coordinator-host> -l gpadmin 'ls -la $GPHOME/share/postgresql/extension/pxf*'`
-   **Verify Extension in DB**: `ssh <coordinator-host> -l gpadmin 'psql -d <your-db> -c "\dx pxf"'`
