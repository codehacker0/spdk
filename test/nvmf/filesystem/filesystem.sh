#!/usr/bin/env bash

testdir=$(readlink -f $(dirname $0))
rootdir=$(readlink -f $testdir/../../..)
source $rootdir/scripts/autotest_common.sh
source $rootdir/test/nvmf/common.sh

set -e

if ! rdma_nic_available; then
	echo "no NIC for nvmf test"
	exit 0
fi

timing_enter fs_test

# Start up the NVMf target in another process
$rootdir/app/nvmf_tgt/nvmf_tgt -c $testdir/../nvmf.conf &
nvmfpid=$!

trap "killprocess $nvmfpid; exit 1" SIGINT SIGTERM EXIT

waitforlisten $nvmfpid ${RPC_PORT}

modprobe -v nvme-rdma

if [ -e "/dev/nvme-fabrics" ]; then
	chmod a+rw /dev/nvme-fabrics
fi

nvme connect -t rdma -n "nqn.2016-06.io.spdk:cnode1" -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
nvme connect -t rdma -n "nqn.2016-06.io.spdk:cnode2" -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"

mkdir -p /mnt/device

devs=`lsblk -l -o NAME | grep nvme`

for dev in $devs; do
	timing_enter parted
	parted -s /dev/$dev mklabel msdos  mkpart primary '0%' '100%'
	timing_exit parted
	sleep 1

	for fstype in "ext4" "btrfs" "xfs"; do
		timing_enter $fstype
		if [ $fstype = ext4 ]; then
			force=-F
		else
			force=-f
		fi

		mkfs.${fstype} $force /dev/${dev}p1

		mount /dev/${dev}p1 /mnt/device
		touch /mnt/device/aaa
		sync
		rm /mnt/device/aaa
		sync
		umount /mnt/device
		timing_exit $fstype
	done

	parted -s /dev/$dev rm 1
done

sync
nvme disconnect -n "nqn.2016-06.io.spdk:cnode1"
nvme disconnect -n "nqn.2016-06.io.spdk:cnode2"

trap - SIGINT SIGTERM EXIT

nvmfcleanup
killprocess $nvmfpid
timing_exit fs_test
