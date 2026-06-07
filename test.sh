#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

IMG_FILE="/tmp/dmp_test.img"
LOOP_DEV=""
DM_NAME="dmp_test"
MODULE_NAME="dmp"

cleanup() {
    log_info "Cleaning up test environment..."
    dmsetup remove $DM_NAME 2>/dev/null || true
    dmsetup remove ${DM_NAME}_2 2>/dev/null || true
    dmsetup remove ${DM_NAME}_off 2>/dev/null || true
    if [ -n "$LOOP_DEV" ]; then
        losetup -d $LOOP_DEV 2>/dev/null || true
    fi
    rmmod $MODULE_NAME 2>/dev/null || true
    rm -f $IMG_FILE
}
trap cleanup EXIT

if [ "$EUID" -ne 0 ]; then
    log_error "Script requires root privileges. Please run via sudo."
    exit 1
fi

if [ ! -f "dmp.ko" ]; then
    log_error "Module dmp.ko not found. Run 'make' first in this directory."
    exit 1
fi

log_info "=== Starting dmp module testing ==="

modprobe dm-mod
modprobe loop

log_info "Loading dmp module into kernel..."
insmod $MODULE_NAME.ko
if ! lsmod | grep -q "^$MODULE_NAME "; then
    log_error "Failed to load module. Check dmesg output."
    exit 1
fi

log_info "Creating test image and loop device..."
dd if=/dev/zero of=$IMG_FILE bs=1M count=100 status=none
LOOP_DEV=$(losetup --find --show $IMG_FILE)
log_info "Loop device created: $LOOP_DEV"

SIZE=$(blockdev --getsz $LOOP_DEV)

log_info "Test 1: Basic I/O and sysfs verification (no offset)"
dmsetup create $DM_NAME --table "0 $SIZE dmp $LOOP_DEV"

dd if=/dev/zero of=/dev/mapper/$DM_NAME bs=4k count=10 oflag=direct status=none
dd if=/dev/mapper/$DM_NAME of=/dev/null bs=4k count=20 iflag=direct status=none

STATS=$(cat /sys/module/$MODULE_NAME/stat/volumes)
echo "$STATS"

W_REQS=$(echo "$STATS" | grep "write: reqs" | awk '{print $3}')
W_REQS=${W_REQS:-0}
R_REQS=$(echo "$STATS" | grep "read: reqs" | awk '{print $3}')
R_REQS=${R_REQS:-0}
W_AVG=$(echo "$STATS" | grep "write: reqs" | awk '{print $6}')
W_AVG=${W_AVG:-0}
R_AVG=$(echo "$STATS" | grep "read: reqs" | awk '{print $6}')
R_AVG=${R_AVG:-0}

if [ "$W_REQS" -ge 10 ] && [ "$R_REQS" -ge 20 ] && [ "$W_AVG" -eq 4096 ] && [ "$R_AVG" -eq 4096 ]; then
    log_info "Test 1 PASSED: Statistics collected correctly."
else
    log_error "Test 1 FAILED: Expected >=10 writes and >=20 reads with avg size 4096."
    log_error "Got -> Write: reqs=$W_REQS avg=$W_AVG | Read: reqs=$R_REQS avg=$R_AVG"
    exit 1
fi

log_info "Test 2: Global statistics accumulation (creating second device)"
DM_NAME_2="${DM_NAME}_2"
dmsetup create $DM_NAME_2 --table "0 $SIZE dmp $LOOP_DEV"

dd if=/dev/zero of=/dev/mapper/$DM_NAME_2 bs=4k count=5 oflag=direct status=none

STATS2=$(cat /sys/module/$MODULE_NAME/stat/volumes)
W_REQS2=$(echo "$STATS2" | grep "write: reqs" | awk '{print $3}')
W_REQS2=${W_REQS2:-0}

if [ "$W_REQS2" -ge 15 ]; then
    log_info "Test 2 PASSED: Global statistics correctly accumulate data."
else
    log_error "Test 2 FAILED: Expected >=15 total writes, got $W_REQS2."
    exit 1
fi

log_info "Test 3: Creating device with physical offset"
DM_NAME_OFF="${DM_NAME}_off"
dmsetup create $DM_NAME_OFF --table "0 1024 dmp $LOOP_DEV 1024"

dd if=/dev/zero of=/dev/mapper/$DM_NAME_OFF bs=4k count=2 oflag=direct status=none
log_info "Test 3 PASSED: Device with offset created, I/O works."
dmsetup remove $DM_NAME_OFF

log_info "Test 4: Handling invalid arguments (non-existent disk)"
if dmsetup create bad_dmp --table "0 100 dmp /dev/nonexistent_device_xyz" 2>/dev/null; then
    log_error "Test 4 FAILED: dmsetup should have rejected non-existent device."
    exit 1
else
    log_info "Test 4 PASSED: Non-existent device correctly rejected."
fi

log_info "Test 5: Handling invalid arguments (missing device path)"
if dmsetup create bad_args --table "0 100 dmp" 2>/dev/null; then
    log_error "Test 5 FAILED: Should have rejected creation without device path."
    exit 1
else
    log_info "Test 5 PASSED: Invalid argument count correctly rejected."
fi

log_info "=== All tests passed successfully! ==="
