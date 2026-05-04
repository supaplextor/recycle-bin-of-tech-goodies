GUEST_MEMORY_MB ?= 3072
QEMU_MEM_PATH ?= /dev/hugepages
HUGEPAGE_SIZE_KB := $(shell awk '/Hugepagesize:/ {print $$2}' /proc/meminfo)
REQUIRED_HUGEPAGES := $(shell echo $$(( ($(GUEST_MEMORY_MB) * 1024 + $(HUGEPAGE_SIZE_KB) - 1) / $(HUGEPAGE_SIZE_KB) )))
REQUIRED_MEMLOCK_KB := $(shell echo $$(( $(GUEST_MEMORY_MB) * 1024 )))

disk:
	test -s openwrt.qcow2 || qemu-img create -f qcow2 openwrt.qcow2 64G

preflight:
	./kvm.openwrt.bash --preflight

hugepages-info:
	@echo "guest memory (MiB): $(GUEST_MEMORY_MB)"
	@echo "hugepage size (KiB): $(HUGEPAGE_SIZE_KB)"
	@echo "required hugepages: $(REQUIRED_HUGEPAGES)"
	@grep -E 'HugePages_Total|HugePages_Free|Hugepagesize' /proc/meminfo
	@mount | grep -i hugetlbfs || true

hugepages-setup:
	@echo "Configuring hugetlbfs for $(GUEST_MEMORY_MB) MiB guest RAM"
	sudo sysctl -w vm.nr_hugepages=$(REQUIRED_HUGEPAGES)
	sudo mkdir -p $(QEMU_MEM_PATH)
	sudo mountpoint -q $(QEMU_MEM_PATH) || sudo mount -t hugetlbfs nodev $(QEMU_MEM_PATH)
	sudo chgrp "$$(id -gn)" $(QEMU_MEM_PATH)
	sudo chmod 1770 $(QEMU_MEM_PATH)
	@echo "Done. Use: QEMU_MEM_PATH=$(QEMU_MEM_PATH) ./kvm.openwrt.bash --preflight"

run-hugepages:
	QEMU_MEM_PATH=$(QEMU_MEM_PATH) GUEST_MEMORY_MB=$(GUEST_MEMORY_MB) ./kvm.openwrt.bash

memlock-setup:
	@echo "Configuring memlock for user '$$(id -un)' to $(REQUIRED_MEMLOCK_KB) KiB"
	@echo "$$(id -un) soft memlock $(REQUIRED_MEMLOCK_KB)" | sudo tee /etc/security/limits.d/99-vfio-memlock.conf >/dev/null
	@echo "$$(id -un) hard memlock $(REQUIRED_MEMLOCK_KB)" | sudo tee -a /etc/security/limits.d/99-vfio-memlock.conf >/dev/null
	sudo mkdir -p /etc/systemd/system/user@.service.d
	@printf "[Service]\nLimitMEMLOCK=%sK\n" "$(REQUIRED_MEMLOCK_KB)" | sudo tee /etc/systemd/system/user@.service.d/99-memlock.conf >/dev/null
	sudo systemctl daemon-reload
	@echo "Done. Log out and log back in, then run: make memlock-check"

memlock-check:
	@echo "required memlock (KiB): $(REQUIRED_MEMLOCK_KB)"
	@echo "hard memlock (KiB): $$(ulimit -H -l)"
	@echo "soft memlock (KiB): $$(ulimit -S -l)"
	@soft="$$(ulimit -S -l)"; \
	if [ "$$soft" = "unlimited" ]; then \
		echo "status: OK (unlimited)"; \
	elif [ "$$soft" -ge "$(REQUIRED_MEMLOCK_KB)" ]; then \
		echo "status: OK"; \
	else \
		echo "status: NOT OK (relogin likely still needed)"; \
	fi
