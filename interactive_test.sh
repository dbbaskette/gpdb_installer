#!/bin/bash

# Interactive Test Script for Greenplum Installer
# This script allows you to test the installer interactively

echo "=========================================="
echo "Greenplum Installer Interactive Test"
echo "=========================================="
echo ""
echo "This script will help you test the installer interactively."
echo "You can choose to:"
echo "1. Test with default values (single-node)"
echo "2. Test with custom values"
echo "3. Test help and error handling"
echo "4. Exit"
echo ""

read -p "Choose an option (1-4): " choice

case $choice in
    1)
        echo ""
        echo "Testing with default values (single-node setup)..."
        echo "This will use your current hostname as coordinator and segment."
        echo ""
        read -p "Press Enter to continue..."
        
        # Remove existing config to force new configuration
        rm -f gpdb_config.conf
        
        # Create mock installer file
        mkdir -p files
        echo "# Mock Greenplum installer for testing" > files/greenplum-db-7.0.0-el7-x86_64.rpm
        
        echo ""
        echo "Running installer with dry-run mode..."
        echo "You will be prompted for configuration values."
        echo "Suggested responses:"
        echo "- Coordinator hostname: Press Enter for default"
        echo "- Segment hosts: Press Enter for default (single-node)"
        echo "- Standby coordinator: n (no)"
        echo "- Install directory: Press Enter for default"
        echo "- Data directory: Press Enter for default"
        echo ""
        read -p "Press Enter to start the installer..."
        
        ./gpdb_installer.sh --dry-run
        ;;
        
    2)
        echo ""
        echo "Testing with custom values..."
        echo "You can enter custom hostnames and paths."
        echo ""
        read -p "Press Enter to continue..."
        
        # Remove existing config
        rm -f gpdb_config.conf
        
        # Create mock installer file
        mkdir -p files
        echo "# Mock Greenplum installer for testing" > files/greenplum-db-7.0.0-el7-x86_64.rpm
        
        echo ""
        echo "Running installer with dry-run mode..."
        echo "You can enter custom values when prompted."
        echo ""
        read -p "Press Enter to start the installer..."
        
        ./gpdb_installer.sh --dry-run
        ;;
        
    3)
        echo ""
        echo "Testing help and error handling..."
        echo ""
        
        echo "1. Testing help function:"
        ./gpdb_installer.sh --help
        echo ""
        
        echo "2. Testing invalid option:"
        ./gpdb_installer.sh --invalid-option
        echo ""
        
        echo "3. Testing without installer file:"
        rm -f files/greenplum-db-7.0.0-el7-x86_64.rpm
        ./gpdb_installer.sh --dry-run
        echo ""
        
        echo "Help and error handling tests complete."
        ;;
        
    4)
        echo "Exiting..."
        exit 0
        ;;
        
    *)
        echo "Invalid option. Please choose 1-4."
        exit 1
        ;;
esac

echo ""
echo "Test completed!"
echo "Check the output above for any issues."
echo "The installer should have run in dry-run mode without making actual changes." 