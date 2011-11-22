#!/bin/bash

AMIFILE=$1
SELFNAME=`basename $0`

if [[ ! -f $AMIFILE ]]
then
  echo "USAGE:
  $SELFNAME ami-name.ami
  ami-name.ami should look like this:

DESC:ami description
DIST:debian
ARCH:i386
ROOTFS:ext3
ROOTFS_SIZE:1024
REPO_URL:ftp.us.debian.org/debian
REPO_PROTOCOL:ftp
LOCATION:TODO"
  exit 0
fi

function show_and_run {
  echo
  echo "$1"
  $1
}

function parse_cfg {
  result=`grep $1: $AMIFILE | awk -F: '{ print $2 }'`
  echo $result
}

# create ami image
AMINAME=`echo $AMIFILE | awk -F.ami '{ print $1 }'` # without .ami extension
ROOTFS_SIZE=`parse_cfg ROOTFS_SIZE`
AMIROOTFS=$AMINAME.image

[[ -f $AMIROOTFS ]] && show_and_run "rm -f $AMIROOTFS"
show_and_run "dd if=/dev/zero of=$AMIROOTFS bs=1M count=$ROOTFS_SIZE"

# creating filesystem
ROOTFS_TYPE=`parse_cfg ROOTFS`
show_and_run "mkfs.$ROOTFS_TYPE -F -j $AMIROOTFS"

# mounting filesystem
AMI_MOUNT_DIR=$AMINAME-rootfs-mnt
if [[ -d $AMI_MOUNT_DIR ]]
then
  show_and_run "sudo umount $AMI_MOUNT_DIR/proc"
  show_and_run "sudo umount $AMI_MOUNT_DIR"
  show_and_run "rm -rf $AMI_MOUNT_DIR"
fi
show_and_run "mkdir $AMI_MOUNT_DIR"
show_and_run "sudo mount -o loop $AMIROOTFS $AMI_MOUNT_DIR"

# prepare for the installation
AMIROOT=$PWD/$AMI_MOUNT_DIR
show_and_run "mkdir -p $AMIROOT/dev"
# aptitude install makedev
OLDPWD=$PWD
cd $AMIROOT/dev
show_and_run "sudo /sbin/MAKEDEV -v consoleonly"
show_and_run "sudo /sbin/MAKEDEV -v std"
cd $OLDPWD

# creating /etc/fstab
show_and_run "mkdir $AMIROOT/etc"
echo "# /etc/fstab: static file system information."                             >  $AMIROOT/etc/fstab
echo "#"                                                                         >> $AMIROOT/etc/fstab
echo "# <file system> <mount point>   <type>  <options>       <dump>  <pass>"    >> $AMIROOT/etc/fstab
echo "proc            /proc           proc    defaults        0       0"         >> $AMIROOT/etc/fstab
echo "# root filesystem"                                                         >> $AMIROOT/etc/fstab
echo "LABEL=uec-rootfs       /               $ROOTFS_TYPE    defaults        1       1" >> $AMIROOT/etc/fstab
#     TODO /\/\/\/\/\/\
cat $AMIROOT/etc/fstab

# mounting proc filesystem
show_and_run "mkdir $AMIROOT/proc"
show_and_run "sudo mount -t proc none $AMIROOT/proc"

# bootstrap (aptitude install debootstrap)
AMIARCH=`parse_cfg ARCH`
AMI_REPO_URL=`parse_cfg REPO_URL`
AMI_REPO_PROTOCOL=`parse_cfg REPO_PROTOCOL`
show_and_run "sudo debootstrap --arch $AMIARCH --include=ssh,curl,linux-image-xen-686 squeeze $AMIROOT $AMI_REPO_PROTOCOL://$AMI_REPO_URL"

# configuring network
echo "######################################################################" | sudo tee    $AMIROOT/etc/network/interfaces
echo "# /etc/network/interfaces -- configuration file for ifup(8), ifdown(8)" | sudo tee -a $AMIROOT/etc/network/interfaces
echo "# See the interfaces(5) manpage for information on what options are"    | sudo tee -a $AMIROOT/etc/network/interfaces
echo "# available."                                                           | sudo tee -a $AMIROOT/etc/network/interfaces
echo "######################################################################" | sudo tee -a $AMIROOT/etc/network/interfaces
echo "# loopback interface"                                                   | sudo tee -a $AMIROOT/etc/network/interfaces
echo "auto lo"                                                                | sudo tee -a $AMIROOT/etc/network/interfaces
echo "iface lo inet loopback"                                                 | sudo tee -a $AMIROOT/etc/network/interfaces
echo ""                                                                       | sudo tee -a $AMIROOT/etc/network/interfaces
echo "#"                                                                      | sudo tee -a $AMIROOT/etc/network/interfaces
echo "auto eth0"                                                              | sudo tee -a $AMIROOT/etc/network/interfaces
echo "iface eth0 inet dhcp"                                                   | sudo tee -a $AMIROOT/etc/network/interfaces

echo "new-ami" | sudo tee $AMIROOT/etc/hostname

# cpnfiguring apt
echo "deb-src http://ftp.us.debian.org/debian squeeze main"     | sudo tee    $AMIROOT/etc/apt/sources.list
echo ""                                                         | sudo tee -a $AMIROOT/etc/apt/sources.list
echo "deb http://security.debian.org/ squeeze/updates main"     | sudo tee -a $AMIROOT/etc/apt/sources.list
echo "deb-src http://security.debian.org/ squeeze/updates main" | sudo tee -a $AMIROOT/etc/apt/sources.list

# cleaning install
show_and_run "sudo chroot $AMIROOT aptitude clean"

# bootloader
sudo mkdir $AMIROOT/boot/grub
echo "default 0                                             " | sudo tee $AMIROOT/boot/grub/menu.lst
echo "timeout 1                                             " | sudo tee -a $AMIROOT/boot/grub/menu.lst
echo "                                                      " | sudo tee -a $AMIROOT/boot/grub/menu.lst
echo "title test                                            " | sudo tee -a $AMIROOT/boot/grub/menu.lst
echo "	root (hd0)                                          " | sudo tee -a $AMIROOT/boot/grub/menu.lst
echo "	kernel /boot/vmlinuz-2.6.32-5-xen-686 root=/dev/xvda1" | sudo tee -a $AMIROOT/boot/grub/menu.lst
echo "	initrd /boot/initrd.img-2.6.32-5-xen-686            " | sudo tee -a $AMIROOT/boot/grub/menu.lst

# configuring timezone
#show_and_run "sudo chroot $AMIROOT dpkg-reconfigure tzdata"

# ec2 setup
show_and_run "cp ec2-get-credentials $AMIROOT/etc/init.d/"
show_and_run "cp ec2-ssh-host-key-gen $AMIROOT/etc/init.d/"
show_and_run "sudo chroot $AMIROOT update-rc.d ec2-get-credentials  defaults"
show_and_run "sudo chroot $AMIROOT update-rc.d ec2-ssh-host-key-gen defaults"

# umount filesystem
sudo umount $AMIROOT/proc
sudo umount $AMIROOT
