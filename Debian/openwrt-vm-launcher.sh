#!/usr/bin/env bash

guest_memory_mb=${GUEST_MEMORY_MB:-128}
vfio_host=${VFIO_HOST:-0000:0a:00.0}
memory_args=(-m "$guest_memory_mb")

mem_path_candidates=()

if [[ -n ${QEMU_MEM_PATH:-} ]]; then
	mem_path_candidates+=("$QEMU_MEM_PATH")
fi

mem_path_candidates+=(/mnt/huge /dev/hugepages)

for mem_path in "${mem_path_candidates[@]}"; do
	if [[ -d $mem_path && -w $mem_path ]]; then
		memory_args=(-mem-path "$mem_path" -mem-prealloc -m "$guest_memory_mb")
		break
	fi
done

if [[ ${memory_args[0]} != -mem-path ]]; then
	required_memlock_kb=$((guest_memory_mb * 1024))
	current_memlock_kb=$(ulimit -S -l)

	if [[ -n $vfio_host && $current_memlock_kb != unlimited ]] && (( current_memlock_kb < required_memlock_kb )); then
		printf 'error: vfio-pci host %s with %s MiB guest RAM needs at least %s KiB of locked memory, but the current limit is %s KiB\n' \
			"$vfio_host" "$guest_memory_mb" "$required_memlock_kb" "$current_memlock_kb" >&2
		printf 'hint: make a writable hugetlbfs mount available and set QEMU_MEM_PATH to it, or raise the memlock limit before starting QEMU\n' >&2
		exit 1
	fi

	printf 'warning: no writable hugetlbfs mount found; using regular guest RAM\n' >&2
fi

~/bin/qemu-caviar --vm-name openwrt2 -- \
	-smp 2,sockets=1,cores=2,threads=1 \
	"${memory_args[@]}" \
	-drive if=virtio,file=openwrt-vm.qcow2,format=qcow2,cache=writeback \
	-device virtio-net-pci,netdev=net0 \
	-netdev bridge,id=net0,br=br0 \
	${vfio_host:+-device vfio-pci,host="$vfio_host"}
