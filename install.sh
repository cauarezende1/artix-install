#!/bin/bash
set -e

# ===== CONFIG =====

USERNAME="user"
PASSWORD="1234"
HOSTNAME="artix"
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"

# ===== AUTO DETECT DISK =====

DISK=$(lsblk -dpno NAME | grep -E "/dev/sd|/dev/nvme" | head -n1)

echo "Usando disco: $DISK"
sleep 2

# ===== PARTIÇÃO =====

parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 513MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart ROOT btrfs 513MiB 100%

mkfs.fat -F32 ${DISK}1
mkfs.btrfs -f ${DISK}2

mount ${DISK}2 /mnt

# ===== SUBVOLUMES =====

btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots

umount /mnt

mount -o noatime,compress=zstd,subvol=@ ${DISK}2 /mnt
mkdir -p /mnt/{boot,home,.snapshots}

mount -o noatime,compress=zstd,subvol=@home ${DISK}2 /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots ${DISK}2 /mnt/.snapshots
mount ${DISK}1 /mnt/boot

# ===== BASE =====

basestrap /mnt base base-devel dinit elogind-dinit linux linux-firmware 
sudo nano vim git 
networkmanager networkmanager-dinit 
pipewire pipewire-pulse wireplumber 
mesa wayland xorg-xwayland 
hyprland kitty wofi thunar firefox 
snapper btrfs-progs grub-btrfs 
greetd greetd-tuigreet

fstabgen -U /mnt >> /mnt/etc/fstab

# ===== CHROOT =====

artix-chroot /mnt /bin/bash <<EOF

echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "root:$PASSWORD" | chpasswd

useradd -m -G wheel,video,audio -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ===== INITRAMFS =====

mkinitcpio -P

# ===== EFISTUB =====

pacman -S --noconfirm efibootmgr

ROOT_UUID=$(blkid -s UUID -o value ${DISK}2)

efibootmgr --create 
--disk $DISK 
--part 1 
--label "Artix Linux" 
--loader /vmlinuz-linux 
--unicode "root=UUID=$ROOT_UUID rootflags=subvol=@ rw quiet loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 initrd=\initramfs-linux.img" 
--verbose

# ===== DINIT SERVICES =====

ln -s /etc/dinit.d/NetworkManager /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/greetd /etc/dinit.d/boot.d/

# ===== GREETD AUTOLOGIN =====

cat > /etc/greetd/config.toml <<EOL
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "$USERNAME"
EOL

# ===== SNAPPER =====

snapper -c root create-config /

# ===== HYPR CONFIG =====

mkdir -p /home/$USERNAME/.config/hypr

cat > /home/$USERNAME/.config/hypr/hyprland.conf <<EOL
monitor=,preferred,auto,1

exec-once = nm-applet --indicator

input {
kb_layout = br
}

bind = SUPER, RETURN, exec, kitty
bind = SUPER, D, exec, wofi --show drun
bind = SUPER, Q, killactive
EOL

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

EOF

echo "INSTALAÇÃO COMPLETA ESTILO DISTRO FINALIZADA"
echo "Reboot e pronto."
