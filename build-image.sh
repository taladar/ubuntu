#!/bin/bash -ex
### Build a docker image for ubuntu i386.

### settings
arch=i386
suite=${1:-trusty}
chroot_dir="/var/chroot/$suite"
apt_mirror='http://archive.ubuntu.com/ubuntu'
docker_image="32bit/ubuntu:${1:-14.04}"

### make sure that the required tools are installed
packages="debootstrap dchroot"
which docker || packages="$packages docker.io"
apt-get install -y $packages

### install a minbase system with debootstrap
export DEBIAN_FRONTEND=noninteractive
debootstrap --variant=minbase --arch=$arch $suite $chroot_dir $apt_mirror

### install ubuntu-minimal
cp /etc/resolv.conf $chroot_dir/etc/resolv.conf
mount -o bind /proc $chroot_dir/proc
mount -o bind /sys  $chroot_dir/sys

### update the list of package sources
cat <<EOF > $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite main restricted universe multiverse
deb $apt_mirror $suite-updates main restricted universe multiverse
deb $apt_mirror $suite-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
EOF
if [[ "${suite}" != "lucid" ]]; then
  cat <<EOF >> $chroot_dir/etc/apt/sources.list
deb http://extras.ubuntu.com/ubuntu $suite main
EOF
chroot $chroot_dir apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 16126D3A3E5C1192
fi


# stub for packages trying to communicate with upstart during installation/upgrade, e.g. procps
chroot $chroot_dir dpkg-divert --local --rename --add /sbin/initctl
if [[ "${suite}" == "lucid" ]]; then
  chroot $chroot_dir mv /sbin/initctl /sbin/initctl.distrib
fi
chroot $chroot_dir ln -s /bin/true /sbin/initctl

chroot $chroot_dir apt-get update
if [[ "${suite}" == "lucid" ]]; then
  chroot $chroot_dir apt-get -y --force-yes install gpgv
  chroot $chroot_dir apt-get update
fi
chroot $chroot_dir apt-get -y upgrade
chroot $chroot_dir apt-get -y install ubuntu-minimal

### cleanup
chroot $chroot_dir apt-get autoclean
chroot $chroot_dir apt-get clean
chroot $chroot_dir apt-get autoremove
rm $chroot_dir/etc/resolv.conf

### kill any processes that are running on chroot
chroot_pids=$(for p in /proc/*/root; do ls -l $p; done | grep $chroot_dir | cut -d'/' -f3)
test -z "$chroot_pids" || (kill -9 $chroot_pids; sleep 2)

### unmount /proc and /sys
umount $chroot_dir/sys
umount $chroot_dir/proc

### create a tar archive from the chroot directory
tar cfz ubuntu.tgz -C $chroot_dir .

### import this tar archive into a docker image:
cat ubuntu.tgz | docker import - $docker_image

# ### push image to Docker Hub
# docker push $docker_image

### cleanup
rm ubuntu.tgz
rm -rf $chroot_dir
