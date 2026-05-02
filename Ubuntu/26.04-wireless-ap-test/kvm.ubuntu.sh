#!/usr/bin/env bash

set -eu

DISK_IMAGE="${DISK_IMAGE:-ubuntu.dd}"
NIC_MODEL="${NIC_MODEL:-e1000}"
vfio_host="${VFIO_HOST:-0000:0a:00.0}"

~/bin/qemu-caviar --vm-name wtfopenwrt -- -m 3G \
	-drive file="${DISK_IMAGE}",if=ide,format=raw \
	-cdrom ubuntu-26.04-live-server-amd64.iso \
	-device "${NIC_MODEL}",netdev=net0 \
	-netdev bridge,id=net0,br=br0 \
	-smp 2,sockets=1,cores=2,threads=1 \
	-drive if=virtio,file=/home/supaplex/usr/src/github-by-user/supaplextor/recycle-bin-of-tech-goodies/OpenWRT/openwrt-vm.qcow2,format=qcow2,cache=writeback \
	${vfio_host:+-device vfio-pci,host="$vfio_host"}
