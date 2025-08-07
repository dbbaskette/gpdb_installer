# PXF 7 Installation Notes

## Architecture Changes in PXF 7

### **No SystemD Services**
Unlike previous versions, PXF 7 does **NOT** use systemd services:
- ❌ No `pxf-gp7.service` 
- ❌ No `systemctl enable/start/stop pxf-gp7`
- ✅ Managed entirely via `pxf` command line tool

### **Installation Location**
- **Binary Location**: `/usr/local/pxf-gp7/`
- **Command**: `pxf` (should be in PATH after installation)
- **Configuration**: Managed through Greenplum cluster operations

### **Management Commands**

#### **Initialize PXF Cluster** (run as gpadmin on coordinator)
```bash
pxf cluster prepare    # Creates configuration directories and files
pxf cluster init       # Initialize the cluster
```

#### **Start/Stop PXF Cluster**
```bash
pxf cluster start
pxf cluster stop
```

#### **Check PXF Status**
```bash
pxf cluster status
```

#### **Individual Host Management**
```bash
pxf init        # Initialize PXF on single host
pxf start       # Start PXF on single host  
pxf stop        # Stop PXF on single host
pxf status      # Check PXF status on single host
```

## Installation Process

### **1. Install RPM on All Hosts**
```bash
sudo yum install pxf-gp7-7.0.0-2.el9.x86_64.rpm
```

### **2. Initialize Cluster** (gpadmin on coordinator)
```bash
pxf cluster prepare    # Create configuration directories
pxf cluster init       # Initialize cluster 
pxf cluster start      # Start cluster
```

### **3. Enable Extension** (in Greenplum database)
```sql
CREATE EXTENSION IF NOT EXISTS pxf;
```

## Installer Implementation

### **What the Installer Does:**
1. ✅ Installs PXF RPM on all hosts
2. ✅ Verifies installation directories exist
3. ✅ Sets proper ownership (`chown gpadmin:gpadmin /usr/local/pxf-gp7`)
4. ✅ Runs `pxf cluster prepare`, `pxf cluster init`, and `pxf cluster start`
5. ✅ Creates PXF extension in database
6. ✅ Tests installation

### **What Changed from Old Versions:**
- **Removed**: systemctl service management
- **Added**: PXF command-line cluster management
- **Simplified**: No manual service configuration needed

## Troubleshooting

### **Check Installation**
```bash
# On any host
ls -la /usr/local/pxf-gp7/
command -v pxf
```

### **Check PXF Status**
```bash  
# On coordinator as gpadmin
ssh coordinator-host -l gpadmin 'pxf cluster status'
```

### **Manual Start/Stop**
```bash
# As gpadmin on coordinator
pxf cluster stop
pxf cluster start

# If cluster not initialized, run full sequence:
pxf cluster prepare
pxf cluster init  
pxf cluster start
```

### **Check Database Extension**
```sql
\dx pxf
SELECT extname, extversion FROM pg_extension WHERE extname = 'pxf';
```

## Common Issues

### **"Unit file pxf-gp7.service does not exist"**
- **Cause**: Trying to use systemctl with PXF 7
- **Solution**: Use `pxf cluster` commands instead

### **"pxf command not found"**
- **Cause**: PXF binary not in PATH
- **Solution**: Check if `/usr/local/pxf-gp7/bin` is in gpadmin's PATH

### **"could not read configuration file cluster.txt"**
- **Cause**: PXF cluster not prepared before initialization
- **Solution**: Run the full initialization sequence:
  ```bash
  pxf cluster prepare    # Creates config directories and files
  pxf cluster init       # Then initialize  
  pxf cluster start      # Then start
  ```

### **"Permission denied" during pxf cluster prepare**
- **Cause**: `/usr/local/pxf-gp7` directory owned by root, not gpadmin
- **Solution**: Fix ownership before initialization:
  ```bash
  sudo chown -R gpadmin:gpadmin /usr/local/pxf-gp7
  ```

### **PXF Not Starting**
- **Check**: Greenplum cluster is running first
- **Check**: All hosts have PXF installed
- **Try**: `pxf cluster reset && pxf cluster prepare && pxf cluster init && pxf cluster start`

This architecture change makes PXF more tightly integrated with Greenplum and eliminates the need for separate service management.