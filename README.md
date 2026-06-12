---
# Device Mapper Proxy (dmp) — Kernel Module

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Platform: Linux Kernel](https://img.shields.io/badge/Kernel-6.18.13-blue)](https://www.kernel.org)

A Linux kernel module implementing a Device Mapper target called **dmp** (device mapper proxy). The module creates virtual block devices on top of existing physical block devices and transparently proxies all I/O requests, while simultaneously collecting **global** I/O operation statistics (aggregated across all active `dmp` devices).

---

## 📊 Supported Statistics

**Global** statistics (aggregated across all active `dmp` devices) are available in real time via the `sysfs` interface:

| Metric | Description |
|--------|-------------|
| `read: reqs` | Total number of read requests (all devices) |
| `read: avg size` | Average read block size in bytes (all devices) |
| `write: reqs` | Total number of write requests (all devices) |
| `write: avg size` | Average write block size in bytes (all devices) |
| `total: reqs` | Total number of requests (all devices) |
| `total: avg size` | Average block size for all operations (all devices) |

Example output:
```bash
$ cat /sys/module/dmp/stat/volumes
read: reqs: 500 avg size: 4096
write: reqs: 100 avg size: 4096
total: reqs: 600 avg size: 4096
```

---

## Requirements

- Linux kernel **6.18.13** (with Device Mapper support)
- Kernel header files (`linux-headers`)
- Utilities: `dmsetup`, `insmod`, `rmmod`
- Superuser privileges (root)

---

## Building the Module

### 1. Clone the Repository
```bash
git clone https://github.com/<your-username>/Device-mapper-proxy.git
cd Device-mapper-proxy
```

### 2. Build
```bash
make
```

Result: `dmp.ko` — compiled kernel module.

### 3. Load the Module
```bash
sudo insmod dmp.ko
```

Verify loading:
```bash
lsmod | grep dmp
dmesg | tail -20
```

---

## Testing and Usage

### Step 1: Prepare a Physical Block Device
Use any real block device (disk, partition, or loop device):

```bash
# Example using a loop device
sudo dd if=/dev/zero of=/tmp/test.img bs=1M count=1024
sudo losetup /dev/loop0 /tmp/test.img
```

### Step 2: Create a dmp Device
Create a dmp device on top of the physical block device:

```bash
# Get device size in sectors (512 bytes)
SIZE=$(sudo blockdev --getsz /dev/loop0)

# Create the dmp device
sudo dmsetup create dmp1 --table "0 $SIZE dmp /dev/loop0"

# Verify
ls -l /dev/mapper/dmp1
```

> `dmp` works directly with physical block devices — not on top of other DM targets.

### Step 3: Generate Workload
```bash
# Write
sudo dd if=/dev/random of=/dev/mapper/dmp1 bs=4k count=100 conv=fsync

# Read
sudo dd if=/dev/mapper/dmp1 of=/dev/null bs=4k count=100
```

### Step 4: View Global Statistics
```bash
cat /sys/module/dmp/stat/volumes
```

Expected output:
```
read: reqs: 100 avg size: 4096
write: reqs: 100 avg size: 4096
total: reqs: 200 avg size: 4096
```

---

## Architecture

`dmp` is a **standalone** Device Mapper target:
- Registers via `dm_register_target()`
- Handles I/O by forwarding bios directly to the underlying physical device
- Collects atomic, thread-safe **global** statistics in the bio mapping path
- Exports aggregated metrics via `sysfs` (`/sys/module/dmp/stat/volumes`)

---

## Project Structure

```
Device-mapper-proxy/
├── Makefile
├── dmp.c                    # Kernel module source code
├── dmp.h                    # Header file
├── README.md
├── test.sh
└── docs/
    └── dmp.rst
```

---

## Limitations

- Statistics are **global** and reset entirely on module reload
- Currently supports a single volume mapping per device (extendable)
- No persistent storage of metrics

---

## License

**GPL v2**, in accordance with Linux kernel licensing policy.
