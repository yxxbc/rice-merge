#!/usr/bin/env bash
# 10 - partition and mount (GPT: 1G ESP + btrfs @/@home)

ESP_PART=""
ROOT_PART=""

partition_names() {
    if [[ "$DISK" =~ [0-9]$ ]]; then
        ESP_PART="${DISK}p1"
        ROOT_PART="${DISK}p2"
    else
        ESP_PART="${DISK}1"
        ROOT_PART="${DISK}2"
    fi
}

verify_disk() {
    [[ -b "$DISK" ]] || die "Not a block device: $DISK"
    [[ "$DISK" != /dev/mapper/* ]] || die "Pass a whole disk, not an LVM volume"
    if lsblk -rno MOUNTPOINTS "$DISK" 2>/dev/null | grep -q .; then
        die "$DISK or one of its partitions is mounted; umount first"
    fi
    local size
    size="$(lsblk -bndo SIZE "$DISK" | head -1)"
    [[ -n "$size" ]] || die "Cannot read the size of $DISK"
    (( size >= 20 * 1024 * 1024 * 1024 )) || die "Disk is smaller than 20GiB"
}

confirm_wipe() {
    [[ "$ALLOW_WIPE" == "yes" ]] || die "This will erase $DISK; set ALLOW_WIPE=yes to proceed"
    [[ "$ASSUME_YES" == "1" ]] && return 0
    warn "ALL DATA on $DISK will be destroyed"
    lsblk -o NAME,SIZE,TYPE,MODEL "$DISK" 2>/dev/null || true
    local answer=""
    read -r -p "Type $DISK to confirm: " answer
    [[ "$answer" == "$DISK" ]] || die "Cancelled"
}

step_partition() {
    partition_names
    step "10 partition: $DISK -> $ESP_PART + $ROOT_PART"

    if [[ "$DRY_RUN" == "1" ]]; then
        run sgdisk --zap-all "$DISK"
        run sgdisk -n "1:0:+$ESP_SIZE" -t 1:ef00 -c 1:ESP "$DISK"
        run sgdisk -n 2:0:0 -t 2:8300 -c 2:ARCH "$DISK"
        run mkfs.fat -F 32 -n ESP "$ESP_PART"
        run mkfs.btrfs -f -L arch "$ROOT_PART"
        run mount "$ROOT_PART" "$MNT"
        run btrfs subvolume create "$MNT/@" "$MNT/@home"
        run mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_PART" "$MNT"
        return 0
    fi

    verify_disk
    confirm_wipe

    umount -R "$MNT" 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    run sgdisk --zap-all "$DISK" || die "Failed to zap the partition table"
    run sgdisk -n "1:0:+$ESP_SIZE" -t 1:ef00 -c 1:ESP "$DISK" || die "Failed to create ESP"
    run sgdisk -n 2:0:0 -t 2:8300 -c 2:ARCH "$DISK" || die "Failed to create root partition"
    run partprobe "$DISK"
    run udevadm settle

    run mkfs.fat -F 32 -n ESP "$ESP_PART" || die "Failed to format ESP"
    run mkfs.btrfs -f -L arch "$ROOT_PART" || die "Failed to format btrfs"

    run mount "$ROOT_PART" "$MNT" || die "Failed to mount root"
    run btrfs subvolume create "$MNT/@" "$MNT/@home" || die "Failed to create subvolumes"
    run umount "$MNT"
    run mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_PART" "$MNT" || die "Failed to mount @"
    run mkdir -p "$MNT/home" "$MNT/boot"
    run mount -o "$BTRFS_OPTS,subvol=@home" "$ROOT_PART" "$MNT/home" || die "Failed to mount @home"
    run mount "$ESP_PART" "$MNT/boot" || die "Failed to mount ESP"
}
