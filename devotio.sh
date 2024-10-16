#!/bin/sh

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

start_time=$(date +%s)

############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options
while getopts ":l" option; do
   case "${option}" in
      l) 
         lat=true
         ;;
      : )
        echo "Missing option argument for -$OPTARG" >&2; exit 0;;
      \?) # Invalid option
         echo "Error: Invalid option" >&2
         ;;
   esac
done

if [ "$lat" ]; then
    dev="$(echo 'H4sIAAAAAAAAAz1QQW4DIQz8yjxglUdUuURqK1XtsRfCOomlBRMD+/4MpOkBa7CZ8TAATiHLglMvRZv4go/gFSVM/NXVlePfDOBNts1yWPAeXOqCo+6KT9slV92eDZzyqldpvE3KeLLg3s17gtSGYpy1UJGtNp/tG5H2dO/y4hDSRR6Su9GLSzQH9wgZywAaEoo0w4Wtf2ZviqQ3hTSstBSbViRh2TXxxGY+mW61iMsYj+1SKTEVdm1BSGHh/7lNcDFPujIEJPMmw1tYLxo1kH6YrG+NvdGWnymYe469hPFvio1d1BuOnihgk6vaK9O/S32lwBeR9ThMMwI994of5t59prLKzrzt8ACO2WhFtwEAAA==' | base64 -d | gzip -d)"
else
    dev="$(echo 'H4sIAAAAAAAAA02RQW6EMAxFr/IPgHqHVu1iRp1W3XfjAQNWQ4ycAOX2dQIjdRfbn+/vB4DPEVeKS2pwXWbJbA16yiMbbmTe/VrEpMy/I4AXDkEjNXgnY5++yir40JVjkiANLrGTgbMc6kG7hG1UjLQyZt3c1bWGJYFiB10MHHkSPu1vFIvrBbPRjqzYdSnlnYfHk9JPeVZ58ShanSQxpj1x6OHZMRi1XCV5pFz02CQEv2xVo3vYiyLmM1KxWaXNanXnxLUz7Qge1lPGR7zSvjuNAc7JtKAyGcZcBx07tvJ9CXBeBe2rj/T8VB2ekweuNPh3doLJo3TcBqfZHTsuSNSa9NKymznL8is2cevjvuOqY0vFVZefjTeyPB4+vdqDSBEcJQIPorE50fBZ15z/Yj/9AQy/jy8YAgAA' | base64 -d | gzip -d)"
fi

clear
echo
echo
echo "                  DEVOTIO"
echo
echo
echo -e "$dev"
sleep 2
echo
echo
echo
echo "Collecting disk devices and their types..."
echo

declare -A device_list

boot_device=$(grep -oP 'root=/dev/\K[^ ]+' /proc/cmdline)
swap_devices=$(awk 'NR>1 {print $1}' /proc/swaps)

for disk in /sys/block/*; do
    disk_name=$(basename "$disk")
    
    # Skip sr* devices (optical drives)
    if [[ "$disk_name" == sr* ]] || [[ "$disk_name" == loop* ]]; then
        continue
    fi

    # Skip the Live Environment boot device
    if [[ "$disk_name" == "$boot_device" ]]; then
        echo "Skipping boot device: /dev/$disk_name"
        continue
    fi

    device_info=$(lsblk -dn -o NAME,TYPE,MODEL,SIZE,MOUNTPOINT "/dev/$disk_name" 2>/dev/null)

    if blkid "/dev/$disk_name" | grep -q 'TYPE="crypto_LUKS"'; then
        disk_type="LUKS Encrypted"
    elif [[ "$disk_name" == zram* ]]; then
        if echo "$swap_devices" | grep -q "/dev/$disk_name"; then
            disk_type="RAM Disk (Swap)"
        else
            disk_type="RAM Disk (zram)"
        fi
    elif [ -e "/sys/block/$disk_name/queue/rotational" ]; then
        if [ "$(cat "/sys/block/$disk_name/queue/rotational")" -eq 0 ] && \
           [[ "$(readlink -f /sys/block/$disk_name/subsystem)" =~ "block" ]]; then
            disk_type="SSD"
        elif [ "$(cat "/sys/block/$disk_name/queue/rotational")" -eq 1 ]; then
            disk_type="HDD"
        else
            disk_type="Other"
        fi
    elif echo "$swap_devices" | grep -q "/dev/$disk_name"; then
        disk_type="Swap Device"
    else
        disk_type="Other"
    fi

    # Separated because must check first if USB HDD or SSD
    if [[ "$(readlink -f /sys/block/$disk_name/device)" =~ "usb" ]]; then
        if [ "$disk_type" = "HDD" ]; then
            disk_type="USB HDD"
        elif [ "$disk_type" = "SSD" ]; then
            disk_type="USB SSD"
        elif [ "$disk_type" = "Other" ]; then
            disk_type="USB Flash Drive"  # Assume flash drive for "Other" if connected over USB
        else
            disk_type="USB $disk_type"
        fi
    fi

    device_list["/dev/$disk_name"]=$disk_type

    echo "$device_info | Type: $disk_type"
done
echo
echo
echo "Do you want to securely erase a specific device or everything?"
echo
echo "1) Specific device"
echo "2) Everything"
echo
read -rp "Select an option: " choice

if [ "$choice" -eq 2 ]; then
    echo "Clearing RAM..."
    sync; echo 3 > /proc/sys/vm/drop_caches
fi

secure_erase_hdd() {
    local device=$1
    echo "Erasing HDD $device..."
    echo
    echo "Formatting file system..."
    mkfs.ext4 -F "$device"
    echo
    echo "Running shred by 3 passes of overwriting..."
    shred -n 3 -z -v "$device"
    echo
    echo "Running dd by writing zeroes..."
    dd if=/dev/zero of="$device" bs=1M status=progress
    echo
    echo "Running dd by writing ones..."
    printf '\377' | dd of="$device" bs=1M status=progress conv=notrunc
    echo
    echo "Running dd by writing random data..."
    dd if=/dev/urandom of="$device" bs=1M status=progress conv=notrunc
    echo
    echo "Running wipe for multiple-pass overwriting..."
    wipe "$device"
    echo
    initialize_luks_encryption "$device"
    echo
    wipe_luks_header "$device"
}

secure_erase_ssd() {
    local device=$1
    echo "Erasing SSD $device..."
    echo
    echo "Formatting file system..."
    mkfs.ext4 -F "$device"
    echo
    echo "Issuing TRIM commands..."
    blkdiscard "$device"
    local entropy=$(openssl rand -base64 32)
    echo
    echo "Running ATA Secure Erase..."
    hdparm --user-master u --security-set-pass "$entropy" "$device"
    hdparm --user-master u --security-erase "$entropy" "$device"
    echo
    initialize_luks_encryption "$device"
    echo
    wipe_luks_header "$device"
}

secure_erase_luks() {
    local device=$1
    echo "Erasing crypto LUKS $device..."
    echo
    echo "Running dd by writing random data..."
    dd if=/dev/urandom of="$device" bs=1M status=progress
    echo
    echo "Running shred by 3 passes of overwriting..."
    shred -n 3 -z -v "$device"
    echo
    initialize_luks_encryption "$device"
    echo
    wipe_luks_header "$device"
}

secure_erase_flash() {
    local device=$1
    echo "Erasing Flash Drive $device..."
    echo
    echo "Formatting file system..."
    mkfs.ext4 -F "$device"
    echo
    echo "Running shred by 3 passes of overwriting..."
    shred -n 3 -z -v "$device"
    echo
    echo "Running dd by writing zeroes..."
    dd if=/dev/zero of="$device" bs=1M status=progress
    echo
    echo "Running dd by writing ones..."
    printf '\377' | dd of="$device" bs=1M status=progress conv=notrunc
    echo
    echo "Running dd by writing random data..."
    dd if=/dev/urandom of="$device" bs=1M status=progress conv=notrunc
    echo
    initialize_luks_encryption "$device"
    echo
    wipe_luks_header "$device"
}

secure_erase_zram() {
    local device=$1
    echo "Erasing zram device $device..."
    echo
    echo "Turning off zram device..."
    swapoff "$device"
    echo
    echo "Running dd by writing random data..."
    dd if=/dev/urandom of="$device" bs=1M status=progress
    echo
    echo "Resetting zram device..."
    zramctl --reset "$device"
}

secure_erase_swap() {
    local device=$1
    echo "Erasing swap space $device..."
    echo
    echo "Turning off swap device..."
    swapoff "$device"
    echo
    echo "Running dd by writing zeroes..."
    dd if=/dev/zero of="$device" bs=1M
}

initialize_luks_encryption() {
    local device=$1
    local entropy=$(openssl rand -base64 32)
    echo "Initializing LUKS encryption on $device..."

    # Warning: This will overwrite all data on the device
    echo "$entropy" | cryptsetup luksFormat "$device" --batch-mode --key-file -
    echo "LUKS encryption initialized on $device."
}

wipe_luks_header() {
    local device=$1

    # Check if the device is already a LUKS-encrypted volume
    if cryptsetup isLuks "$device"; then
        echo "Wiping LUKS header on $device..."
        cryptsetup luksErase "$device" --batch-mode
        echo "LUKS header wiped from $device."
    else
        echo "$device is not a LUKS-encrypted device; skipping luksErase."
    fi
}

perform_erase() {
    local device=$1
    local type=$2
    case $type in
        "HDD") secure_erase_hdd "$device" ;;
        "USB HDD") secure_erase_hdd "$device" ;;
        "SSD") secure_erase_ssd "$device" ;;
        "USB SSD") secure_erase_ssd "$device" ;;
        "LUKS Encrypted") secure_erase_luks "$device" ;;
        "USB Flash Drive") secure_erase_flash "$device" ;;
        "RAM Disk (zram)"|"RAM Disk (Swap)") secure_erase_zram "$device" ;;
        "Swap Device") secure_erase_swap "$device" ;;
        *) echo "Unsupported device type for secure erasure." ;;
    esac
}

if [ "$choice" -eq 1 ]; then
    echo "Available devices for secure erasure:"
    select device in "${!device_list[@]}"; do
        if [ -n "$device" ]; then
            perform_erase "$device" "${device_list[$device]}"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
elif [ "$choice" -eq 2 ]; then
    for device in "${!device_list[@]}"; do
        perform_erase "$device" "${device_list[$device]}"
        echo "Reboot to clear any data in volatile memories."
    done
else
    echo "Invalid choice. Exiting."
    exit 1
fi

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
echo "Script completed in $((elapsed_time / 60)) minutes and $((elapsed_time % 60)) seconds."
