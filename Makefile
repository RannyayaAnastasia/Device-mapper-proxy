MODULE_NAME := dmp

obj-m += $(MODULE_NAME).o

KDIR := /lib/modules/$(shell uname -r)/build

PWD := $(shell pwd)

GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
NC     := \033[0m

.PHONY: all
all:
	@echo -e "$(GREEN)[BUILD]$(NC) Compiling module $(MODULE_NAME).ko for kernel $(shell uname -r)..."
	$(MAKE) -C $(KDIR) M=$(PWD) modules
	@echo -e "$(GREEN)[BUILD]$(NC) Module successfully built: $(MODULE_NAME).ko"

.PHONY: clean
clean:
	@echo -e "$(YELLOW)[CLEAN]$(NC) Cleaning build artifacts..."
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	@rm -f *.o *.ko *.mod *.mod.c .*.cmd modules.order Module.symvers 2>/dev/null || true
	@echo -e "$(GREEN)[CLEAN]$(NC) Cleanup complete."

.PHONY: load
load: all
	@echo -e "$(GREEN)[LOAD]$(NC) Loading module $(MODULE_NAME) into the kernel..."
	@sudo insmod $(MODULE_NAME).ko
	@echo -e "$(GREEN)[LOAD]$(NC) Module loaded."
	@lsmod | grep $(MODULE_NAME) || true

.PHONY: unload
unload:
	@echo -e "$(YELLOW)[UNLOAD]$(NC) Unloading module $(MODULE_NAME)..."
	@sudo rmmod $(MODULE_NAME) 2>/dev/null || true
	@echo -e "$(GREEN)[UNLOAD]$(NC) Module unloaded."

.PHONY: reload
reload: unload load

.PHONY: test
test: all
	@echo -e "$(GREEN)[TEST]$(NC) Running test script..."
	@sudo bash test.sh

.PHONY: install
install: all
	@echo -e "$(GREEN)[INSTALL]$(NC) Installing module to /lib/modules/$(shell uname -r)/extra/..."
	@sudo install -m 644 -D $(MODULE_NAME).ko /lib/modules/$(shell uname -r)/extra/$(MODULE_NAME).ko
	@sudo depmod -a
	@echo -e "$(GREEN)[INSTALL]$(NC) Module installed. It can now be loaded via modprobe $(MODULE_NAME)."

