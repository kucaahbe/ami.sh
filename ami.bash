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
ROOTFS:ext4
ROOTFS_SIZE:1024"
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
AMIROOTFS=$AMINAME.fs

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
echo "/dev/sda1       /               $ROOTFS_TYPE    defaults        1       1" >> $AMIROOT/etc/fstab
cat $AMIROOT/etc/fstab

# mounting proc filesystem
show_and_run "mkdir $AMIROOT/proc"
show_and_run "sudo mount -t proc none $AMIROOT/proc"
