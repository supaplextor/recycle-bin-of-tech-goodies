#!/usr/bin/env bash

set -eu

NIC_MODEL="${NIC_MODEL:-e1000}"
vfio_host="${VFIO_HOST:-0000:0a:00.0}"
guest_memory_mb="${GUEST_MEMORY_MB:-2048}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

memory_args=(-m "${guest_memory_mb}M" -mem-prealloc -mem-path /mnt/huge)
mem_path_candidates=()
selected_mem_path=""
mem_path_diagnostics=()
required_memlock_kb=$((guest_memory_mb * 1024))
current_memlock_kb=$(ulimit -S -l)
hugepage_size_kb=$(awk '/Hugepagesize:/ {print $2}' /proc/meminfo)
required_hugepages=$(((required_memlock_kb + hugepage_size_kb - 1) / hugepage_size_kb))

if [[ ${1:-} == --preflight ]]; then
	PREFLIGHT_ONLY=1
	shift
fi

if [[ -n ${QEMU_MEM_PATH:-} ]]; then
	mem_path_candidates+=("$QEMU_MEM_PATH")
fi

for default_mem_path in /mnt/huge /dev/hugepages; do
	if [[ ${QEMU_MEM_PATH:-} != "$default_mem_path" ]]; then
		mem_path_candidates+=("$default_mem_path")
	fi
done

for mem_path in "${mem_path_candidates[@]}"; do
	if [[ ! -d $mem_path ]]; then
		mem_path_diagnostics+=("${mem_path}:missing")
		continue
	fi

	fs_type=$(stat -f -c %T "$mem_path" 2>/dev/null || true)
	if [[ $fs_type != hugetlbfs ]]; then
		mem_path_diagnostics+=("${mem_path}:not-hugetlbfs(${fs_type:-unknown})")
		continue
	fi

	if [[ ! -w $mem_path ]]; then
		mem_path_diagnostics+=("${mem_path}:not-writable")
		continue
	fi

	memory_args=(-mem-path "$mem_path" -mem-prealloc -m "${guest_memory_mb}M")
	selected_mem_path="$mem_path"
	mem_path_diagnostics+=("${mem_path}:selected")
	break
done

vfio_sysfs=""
iommu_group=""

if [[ -n $vfio_host ]]; then
	vfio_sysfs="/sys/bus/pci/devices/${vfio_host}"
	if [[ -L ${vfio_sysfs}/iommu_group ]]; then
		iommu_group=$(basename "$(readlink "${vfio_sysfs}/iommu_group")")
	fi
fi

print_preflight() {
	printf 'preflight: guest_memory_mb=%s\n' "$guest_memory_mb"
	printf 'preflight: required_memlock_kb=%s\n' "$required_memlock_kb"
	printf 'preflight: current_memlock_kb=%s\n' "$current_memlock_kb"
	printf 'preflight: hugepage_size_kb=%s\n' "$hugepage_size_kb"
	printf 'preflight: required_hugepages=%s\n' "$required_hugepages"

	if [[ -n $selected_mem_path ]]; then
		printf 'preflight: memory_backend=hugetlbfs (%s)\n' "$selected_mem_path"
	else
		printf 'preflight: memory_backend=regular_ram\n'
	fi

	for item in "${mem_path_diagnostics[@]}"; do
		printf 'preflight: mem_path_candidate=%s\n' "$item"
	done

	if [[ -z $vfio_host ]]; then
		printf 'preflight: vfio=disabled\n'
		return
	fi

	if [[ -d $vfio_sysfs ]]; then
		printf 'preflight: vfio_device=%s present\n' "$vfio_host"
	else
		printf 'preflight: vfio_device=%s missing in sysfs\n' "$vfio_host"
	fi

	if [[ -n $iommu_group ]]; then
		printf 'preflight: iommu_group=%s\n' "$iommu_group"
	else
		printf 'preflight: iommu_group=unknown\n'
	fi
}

print_preflight

if [[ $PREFLIGHT_ONLY == 1 ]]; then
	exit 0
fi

if [[ ${memory_args[0]} != -mem-path ]]; then
	if [[ -n $vfio_host && $current_memlock_kb != unlimited ]] && (( current_memlock_kb < required_memlock_kb )); then
		# Try to raise memlock in-process before failing; this only works if hard limit/policy allows it.
		ulimit -S -l "$required_memlock_kb" 2>/dev/null || true
		current_memlock_kb=$(ulimit -S -l)

		if [[ $current_memlock_kb != unlimited ]] && (( current_memlock_kb < required_memlock_kb )); then
			ulimit -H -l "$required_memlock_kb" 2>/dev/null || true
			ulimit -S -l "$required_memlock_kb" 2>/dev/null || true
			current_memlock_kb=$(ulimit -S -l)
		fi

		if [[ $current_memlock_kb != unlimited ]] && (( current_memlock_kb < required_memlock_kb )); then
			printf 'error: vfio-pci host %s with %s MiB guest RAM needs at least %s KiB of locked memory, but the current limit is %s KiB\n' \
				"$vfio_host" "$guest_memory_mb" "$required_memlock_kb" "$current_memlock_kb" >&2
			printf 'hint: export QEMU_MEM_PATH=/dev/hugepages (or another writable hugetlbfs), lower GUEST_MEMORY_MB, or configure pam_limits/systemd LimitMEMLOCK and relogin\n' >&2
			exit 1
		fi

		printf 'info: raised memlock soft limit to %s KiB for this launch\n' "$current_memlock_kb" >&2
	fi

	printf 'warning: no writable hugetlbfs mount found; using regular guest RAM\n' >&2
fi

~/bin/qemu-caviar --vm-name ubuntu-test -- \
	-m 6G \
	-cdrom ubuntu-26.04-live-server-amd64.iso \
	-device "${NIC_MODEL}",netdev=net0 \
	-netdev bridge,id=net0,br=br0 \
	-smp 2,sockets=1,cores=2,threads=1 \
	-drive if=virtio,file=ubuntu.qcow2,format=qcow2,cache=writeback


#	${vfio_host:+-device vfio-pci,host="$vfio_host"} \
#	"${memory_args[@]}" \
#	-mem-prealloc -mem-path /mnt/huge \
