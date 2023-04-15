#!/usr/bin/env bash

. /tmp/files/vars.sh

CONFIG_SCRIPT_SHORT=`basename "$CONFIG_SCRIPT"`
tee "${ROOT_DIR}${CONFIG_SCRIPT}" &>/dev/null << EOF
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring hostname, timezone, and keymap.."
  echo "${FQDN}" | tee /etc/hostname
  /usr/bin/ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  /usr/bin/hwclock --systohc
  echo "KEYMAP=${KEYMAP}" | tee /etc/vconsole.conf
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring locale.."
  /usr/bin/sed -i "s/#${LANGUAGE}/${LANGUAGE}/" /etc/locale.gen
  /usr/bin/locale-gen
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Creating initramfs.."
  /usr/bin/mkinitcpio -p linux
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Setting root pasword.."
  /usr/bin/usermod --password ${PASSWORD} root
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring network.."
  # Disable systemd Predictable Network Interface Names and revert to traditional interface names
  # https://wiki.archlinux.org/index.php/Network_configuration#Revert_to_traditional_interface_names
  /usr/bin/ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
  /usr/bin/systemctl enable dhcpcd@eth0.service
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring sshd.."
  /usr/bin/sed -i "s/#UseDNS yes/UseDNS no/" /etc/ssh/sshd_config
  /usr/bin/systemctl enable sshd.service
  # Workaround for https://bugs.archlinux.org/task/58355 which prevents sshd to accept connections after reboot
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Adding workaround for sshd connection issue after reboot.."
  /usr/bin/pacman -S --noconfirm rng-tools
  /usr/bin/systemctl enable rngd
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Enable time synching.."
  /usr/bin/pacman -S --noconfirm ntp
  /usr/bin/systemctl enable ntpd 
  # Vagrant-specific configuration
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Creating ${USER} user.."
  /usr/bin/rm -rf /home/${USER}
  /usr/bin/useradd --password ${TEMP_PASSWORD} --comment "${USER} User" --create-home --user-group ${USER}
  /usr/bin/echo -e "${PASSWORD}\n${PASSWORD}" | /usr/bin/passwd ${USER}
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring sudo.."
  echo "Defaults env_keep += \"SSH_AUTH_SOCK\"" | tee /etc/sudoers.d/10_${USER}
  echo "${USER} ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers.d/10_${USER}
  /usr/bin/chmod 0440 /etc/sudoers.d/10_${USER}
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Creating .ssh directory.."
  /usr/bin/install --directory --owner=${USER} --group=${GROUP} --mode=0700 /home/${USER}/.ssh
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Installing ${FQDN} non-AUR dependencies.."
  /usr/bin/pacman -S --noconfirm base-devel
  /usr/bin/pacman -S --noconfirm wget git parted 
  /usr/bin/pacman -S --noconfirm dialog dosfstools f2fs-tools polkit qemu-user-static-binfmt
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Installing ${FQDN} AUR dependencies.."
  /usr/bin/runuser - ${USER} -c '(cd /tmp && /usr/bin/git clone https://aur.archlinux.org/yay-bin.git)'
  /usr/bin/runuser - ${USER} -c '(cd /tmp/yay-bin && /usr/bin/makepkg --install --syncdeps --noconfirm)'
  /usr/bin/runuser - ${USER} -c '/usr/bin/yay -S --noconfirm grub-efi-arm64'
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Installing ${FQDN}.."
  /usr/bin/runuser - ${USER} -c 'cd /tmp && /usr/bin/git clone https://gitlab.manjaro.org/scarf/applications/${FQDN}.git/'
  /usr/bin/install -m 755 -o root /tmp/${FQDN}/${FQDN} /usr/bin
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Autostarting ${FQDN} at login.."
  /usr/bin/echo "sudo /bin/bash ${FQDN}" | tee -a /home/${USER}/.bashrc
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Cleaning up.."
  /usr/bin/pacman -Rcns --noconfirm gptfdisk git
  # Vagrant-specific configuration
EOF

echo ">>>> setup.sh: Entering chroot and configuring system.."
/usr/bin/arch-chroot ${ROOT_DIR} ${CONFIG_SCRIPT}
/usr/bin/rm "${ROOT_DIR}${CONFIG_SCRIPT}"

echo ">>>> setup.sh: Copying authorized_keys from iso to box"
/usr/bin/cp ${A_KEYS} ${ROOT_DIR}${A_KEYS}

echo ">>>> setup.sh: Adding custom language yr.."
/usr/bin/gzip -k /tmp/files/yr-af.map
/usr/bin/install --mode=0644 /tmp/files/yr-af.map.gz "${ROOT_DIR}/usr/share/kbd/keymaps/i386/dvorak"


echo ">>>> setup.sh: Completing installation.."
/usr/bin/sleep 3
/usr/bin/umount ${BOOT_DIR}
/usr/bin/umount ${ROOT_DIR}

/usr/bin/rm ${A_KEYS}

# Turning network interfaces down to make sure SSH session was dropped on host.
# More info at: https://www.packer.io/docs/provisioners/shell.html#handling-reboots
for i in $(/usr/bin/ip -o link show | /usr/bin/awk -F': ' '{print $2}'); do /usr/bin/ip link set ${i} down; done
/usr/bin/systemctl reboot
echo ">>>> setup.sh: Installation complete!"