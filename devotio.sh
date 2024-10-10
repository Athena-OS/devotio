#!/bin/sh

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

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
    dev="$(echo 'H4sIAAAAAAAAAzVQQW4DIQz8ih+wyiOqXCK1lar2uBfCehNLCybG8P4ObHvADB7GHvsWMi90a6WIsy30EaxSCRN/NTEBveY3Pg7NYaH3YFwXukoX+tTOucpxJuiWN3mw47XmwS/0amotEVenoiA8VMpa3Wb6CSQtvRpPAW40z6NYV1gwjmqEDozvywASEhV2pR2pU9ZcKMlTiJ02OIkulRIjdEk40dWmzLQWNh706MsV+jV38cD4j4CB0YdpV0uyYWpKas7DVdh2iRKgvaz5W2JzuLE7SuWWYythzIpKowuKDS8nCnTwQ3Ru8A/V/7FBR8Tr8Iqx5d4q/WDLzeYmNu7Yrl5+ASRQMy6fAQAA' | base64 -d | gzip -d)"
else
    dev="$(echo 'H4sIAAAAAAAAA02QS27DMAxE9zkFD2DkDi3aRYKmRffeMDZtEZVFg5Lt+vYlFQfoTvzocWa+AlwxLbmB6zJzIW1gwBJI4YZq3e+FlX3epleKURI28IFKNnrjleFTVkqZIzdwST2PVNhWR+kzbEEg4Eowy2Y8W1RYMmDqQRYFSjQxOfiGyXkXmBV3KAK7LF7eaXw+Mf/4s03+2xdl4kww7ZniAKYXRsWO2lQCFt+EjWM0K6so3uPu41QOJc5YuSui9dpEtTPtEE2jiUtVlffu5n0ES0XFg1EeQ6nLPVlI/tlPH05Ahgrhgc5tesmms9qn39nyyiaipy5adr3RL5CxUx64I8NYbB75xgZ9eDInD3gNp948Gu+oJRhhEH369+mjhEgjS2o8CDqKKuyfzvPpdPoDh1Ym7vcBAAA=' | base64 -d | gzip -d)"
fi

clear
echo
echo
echo "              DEVOTIO"
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
    if [[ "$disk_name" == sr* ]]; then
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
    mkfs.ext4 -F "$device"
    shred -n 3 -z -v "$device"
    dd if=/dev/zero of="$device" bs=1M status=progress
    printf '\377' | dd of="$device" bs=1M status=progress conv=notrunc
    dd if=/dev/urandom of="$device" bs=1M status=progress conv=notrunc
    wipe "$device"
    cryptsetup luksErase "$device"
}

secure_erase_ssd() {
    local device=$1
    echo "Erasing SSD $device..."
    mkfs.ext4 -F "$device"
    blkdiscard "$device"
    entropy=$(openssl rand -base64 32)
    hdparm --user-master u --security-set-pass "$entropy" "$device"
    hdparm --user-master u --security-erase "$entropy" "$device"
    cryptsetup luksErase "$device"
}

secure_erase_luks() {
    local device=$1
    echo "Erasing crypto LUKS $device..."
    dd if=/dev/urandom of="$device" bs=1M status=progress
    shred -n 3 -z -v "$device"
    cryptsetup luksErase "$device"
}

secure_erase_flash() {
    local device=$1
    echo "Erasing Flash Drive $device..."
    mkfs.ext4 -F "$device"
    shred -n 3 -z -v "$device"
    dd if=/dev/zero of="$device" bs=1M status=progress
    printf '\377' | dd of="$device" bs=1M status=progress conv=notrunc
    dd if=/dev/urandom of="$device" bs=1M status=progress conv=notrunc
    cryptsetup luksErase "$device"
}

secure_erase_zram() {
    local device=$1
    echo "Erasing zram device $device..."
    swapoff "$device"
    dd if=/dev/urandom of="$device" bs=1M status=progress
    zramctl --reset "$device"
}

secure_erase_swap() {
    local device=$1
    echo "Erasing swap space $device..."
    swapoff "$device"
    dd if=/dev/zero of="$device" bs=1M
    mkswap "$device"
    swapon "$device"
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
