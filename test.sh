set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

IMG_FILE="/tmp/dmp_test.img"
LOOP_DEV=""
DM_NAME="dmp_test"
BS=4096
COUNT=10

echo -e "${YELLOW}=== Starting dmp module testing ===${NC}"
echo -e "\n${YELLOW}[1/6] Cleaning up previous states...${NC}"

for dev in $(sudo dmsetup ls 2>/dev/null | grep -i dmp | awk '{print $1}'); do
    echo "    -> Removing DM device: $dev"
    sudo dmsetup remove "$dev" 2>/dev/null || true
done

sudo losetup -l | grep "$IMG_FILE" | awk '{print $1}' | xargs -r sudo losetup -d 2>/dev/null || true

if lsmod | grep -q "^dmp "; then
    echo "    -> Unloading dmp module from kernel..."
    sudo rmmod dmp 2>/dev/null || true
    sleep 1
fi

rm -f "$IMG_FILE"

echo -e "\n${YELLOW}[2/6] Building and loading the module...${NC}"
make -s
sudo insmod dmp.ko
if ! lsmod | grep -q "^dmp "; then
    echo -e "${RED}Error: dmp module failed to load!${NC}"
    exit 1
fi
echo -e "${GREEN}Module loaded successfully.${NC}"

echo -e "\n${YELLOW}[3/6] Creating test block device (10 MB)...${NC}"
dd if=/dev/zero of="$IMG_FILE" bs=1M count=10 status=none
LOOP_DEV=$(sudo losetup -f --show "$IMG_FILE")
TOTAL_SIZE=$(sudo blockdev --getsz "$LOOP_DEV") # Размер в 512-байтных секторах

echo -e "\n${YELLOW}[4/6] Running test scenarios...${NC}"

echo "  -> Test A: Basic write/read (with conv=fsync to generate flush)"
sudo dmsetup create "$DM_NAME" --table "0 $TOTAL_SIZE dmp $LOOP_DEV"
sudo dd if=/dev/urandom of="/dev/mapper/$DM_NAME" bs=$BS count=$COUNT conv=fsync status=none
sudo dd if="/dev/mapper/$DM_NAME" of=/dev/null bs=$BS count=$COUNT status=none
echo -e "${GREEN}[PASS]${NC} Basic test completed."

echo "  -> Test B: Offset operations (seek=2048 sectors) on the same volume"
OFFSET_SECTORS=2048
sudo dd if=/dev/urandom of="/dev/mapper/$DM_NAME" bs=512 seek=$OFFSET_SECTORS count=$COUNT conv=fsync status=none
sudo dd if="/dev/mapper/$DM_NAME" bs=512 skip=$OFFSET_SECTORS count=$COUNT of=/dev/null status=none
echo -e "${GREEN}[PASS]${NC} Offset test completed."

echo "  -> Test C: Verifying rejection of invalid arguments"
if sudo dmsetup create dmp_fail1 --table "0 100 dmp" 2>/dev/null; then
    echo -e "${RED}[FAIL]${NC} Module accepted a table without a device!"
    sudo dmsetup remove dmp_fail1 2>/dev/null || true
else
    echo -e "${GREEN}[PASS]${NC} Module correctly rejected a table with no arguments."
fi

echo "  -> Test D: Checking final statistics"
echo "    Contents of /sys/module/dmp/stat/volumes:"
cat /sys/module/dmp/stat/volumes | sed 's/^/    /'
echo -e "${GREEN}[PASS]${NC} Statistics read successfully."

echo -e "\n${YELLOW}[5/6] Final cleanup and module unload...${NC}"

for dev in $(sudo dmsetup ls 2>/dev/null | grep -i dmp | awk '{print $1}'); do
    sudo dmsetup remove "$dev" 2>/dev/null || true
done

sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
rm -f "$IMG_FILE"

sudo rmmod dmp 2>/dev/null || true

if lsmod | grep -q "^dmp "; then
    echo -e "${RED}[FAIL]${NC} Failed to unload dmp module (device may still be in use).${NC}"
else
    echo -e "${GREEN}[PASS]${NC} dmp module successfully unloaded from kernel.${NC}"
fi

echo -e "\n${GREEN}=== Testing completed successfully ===${NC}"
```
