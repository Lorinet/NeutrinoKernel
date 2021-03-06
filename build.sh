#!/bin/bash

if [ "$EUID" -ne 0 ]
then
    echo "Please run build script as root."
    exit
fi

echo "Linfinity Linux Build Tool"
echo "<========================>"

export BUILDDIR=$(pwd)
export LFS=$BUILDDIR/rootfs
export ARCH=i686
export SOURCEDIR=$BUILDDIR/sources
export TOOLSDIR=$BUILDDIR/tools
export LC_ALL=POSIX
export LFS_TGT=$ARCH-linux-gnu
export STD_TGT=linux-generic32
export CONFIG_SITE=$LFS/usr/share/config.site
export MAKEFLAGS='-j16 -s'
export PATH=$PATH:$TOOLSDIR/bin:$TOOLSDIR/$LFS_TGT

function downloadSources {
    mkdir $LFS
    mkdir $SOURCEDIR
    mkdir -pv $LFS/{bin,etc,lib,sbin,usr,var}
    case $ARCH in
      x86_64) mkdir -pv $LFS/lib64 ;;
    esac
    mkdir -pv $TOOLSDIR
    set +h
    umask 022
    chmod -v a+wt $SOURCEDIR
    echo "Downloading sources..."
    cat <<EOF > wget-list
http://ftp.osuosl.org/pub/clfs/conglomeration/clfs-embedded-bootscripts/clfs-embedded-bootscripts-1.0-pre5.tar.bz2
https://busybox.net/downloads/busybox-1.33.1.tar.bz2
http://ftp.gnu.org/gnu/binutils/binutils-2.36.1.tar.xz
http://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.xz
http://ftp.gnu.org/gnu/glibc/glibc-2.33.tar.xz
http://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz
https://github.com/Mic92/iana-etc/releases/download/20210202/iana-etc-20210202.tar.gz
https://ftp.gnu.org/gnu/inetutils/inetutils-2.1.tar.xz
https://www.kernel.org/pub/linux/kernel/v5.x/linux-5.10.17.tar.xz
https://ftp.gnu.org/gnu/mpc/mpc-1.2.1.tar.gz
http://www.mpfr.org/mpfr-4.1.0/mpfr-4.1.0.tar.xz
https://www.openssl.org/source/openssl-1.1.1j.tar.gz
http://www.linuxfromscratch.org/patches/lfs/10.1/glibc-2.33-fhs-1.patch
https://www.zlib.net/fossils/zlib-1.2.11.tar.gz
https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-8.9p1.tar.gz
EOF
    wget --input-file=$BUILDDIR/wget-list --continue --directory-prefix=$SOURCEDIR
}

function buildCrossToolchain {
    echo "Extracting binutils source..."
    tar -xf $SOURCEDIR/binutils-2.36.1.tar.xz -C $SOURCEDIR
    cd $SOURCEDIR/binutils-2.36.1
    mkdir -v build
    cd build
    echo "Configuring binutils..."
    ../configure --prefix=$TOOLSDIR --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --disable-werror > /dev/null
    echo "Building binutils..."
    make -j16 -s > /dev/null
    echo "Installing binutils..."
    make install > /dev/null
    echo "Extracting GCC source..."
    tar -xf $SOURCEDIR/gcc-10.2.0.tar.xz -C $SOURCEDIR
    tar -xf $SOURCEDIR/mpfr-4.1.0.tar.xz -C $SOURCEDIR/gcc-10.2.0
    tar -xf $SOURCEDIR/gmp-6.2.1.tar.xz -C $SOURCEDIR/gcc-10.2.0
    tar -xf $SOURCEDIR/mpc-1.2.1.tar.gz -C $SOURCEDIR/gcc-10.2.0
    cd $SOURCEDIR/gcc-10.2.0
    mv -v mpfr-4.1.0 mpfr
    mv -v gmp-6.2.1 gmp
    mv -v mpc-1.2.1 mpc
    case $ARCH in
        x86_64)
            sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
            ;;
    esac
    mkdir -v build
    cd build
    echo "Configuring GCC..."
    ../configure --target=$LFS_TGT --prefix=$TOOLSDIR --with-glibc-version=2.11 --with-sysroot=$LFS --with-newlib --without-headers --enable-initfini-array --disable-nls --disable-shared --disable-multilib --disable-decimal-float --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++ > /dev/null
    echo "Building GCC..."
    make -s > /dev/null
    echo "Installing GCC..."
    make install > /dev/null
    cd ..
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h
}

function buildKernelHeaders {
    echo "Extracting Linux source..."
    tar -xf $SOURCEDIR/linux-5.10.17.tar.xz -C $SOURCEDIR
    cd $SOURCEDIR/linux-5.10.17
    ARCHX=$ARCH
    case $ARCH in
        i686)
            ARCH=x86
            ;;
    esac
    echo "Cleaning Linux source..."
    make mrproper > /dev/null
    echo "Building Linux kernel headers..."
    make headers > /dev/null
    find usr/include -name '.*' -delete
    rm usr/include/Makefile
    cp -rv usr/include $LFS/usr
    ARCH=$ARCHX
}

function buildGLibC {
    echo "Extracting Glibc source..."
    tar -xf $SOURCEDIR/glibc-2.33.tar.xz -C $SOURCEDIR
    cd $SOURCEDIR/glibc-2.33
    case $ARCH in
        i?86)
            ln -sfv /lib/ld-linux.so.2 $LFS/lib/ld-lsb.so.3
        ;;
        x86_64)
            ln -sfv /lib/ld-2.33.so $LFS/lib64/ld-linux-x86-64.so.2
            ln -sfv /lib/ld-2.33.so $LFS/lib64/ld-lsb-x86-64.so.3
        ;;
    esac
    patch -Np1 -i $SOURCEDIR/glibc-2.33-fhs-1.patch
    mkdir -v build
    cd build
    echo "Configuring Glibc..."
    ../configure --prefix=/usr --host=$LFS_TGT --build=$($SOURCEDIR/glibc-2.33/scripts/config.guess) --enable-kernel=3.2 --with-headers=$LFS/usr/include libc_cv_slibdir=/lib > /dev/null
    echo "Building Glibc..."
    make -j16 > /dev/null
    echo "Installing Glibc..."
    make DESTDIR=$LFS install > /dev/null
    $TOOLSDIR/libexec/gcc/$LFS_TGT/10.2.0/install-tools/mkheaders > /dev/null
    cd $SOURCEDIR/glibc-2.33/nscd
    cp -v nscd.conf $LFS/etc/nscd.conf
}

function buildLibstdcpp {
    cd $SOURCEDIR/gcc-10.2.0/libstdc++-v3
    mkdir -v build
    cd build
    echo "Configuring libstdc++..."
    ../configure --host=$LFS_TGT --build=$($SOURCEDIR/gcc-10.2.0/config.guess) --prefix=/usr --disable-multilib --disable-nls --disable-libstdcxx-pch --with-gxx-include-dir=/usr/include/c++/10.2.0 > /dev/null
    echo "Building libstdc++..."
    make -j16 > /dev/null
    echo "Installing libstdc++..."
    make DESTDIR=$LFS install > /dev/null
}

function buildBusybox {
    echo "Extracting BusyBox source..."
    tar -xf $SOURCEDIR/busybox-1.33.1.tar.bz2 -C $SOURCEDIR
    cd $SOURCEDIR/busybox-1.33.1
    echo "Configuring BusyBox..."
    make CROSS_COMPILE="${LFS_TGT}-" defconfig > /dev/null
    echo "Building BusyBox..."
    make CROSS_COMPILE="${LFS_TGT}-" -j16 > /dev/null
    echo "Installing BusyBox..."
    make CROSS_COMPILE="${LFS_TGT}-" CONFIG_PREFIX="$LFS/" install > /dev/null
    cp -v examples/depmod.pl $TOOLSDIR/bin
    chmod 755 $TOOLSDIR/bin/depmod.pl
}

function buildIanaEtc {
    tar -xf $SOURCEDIR/iana-etc-20210202.tar.gz -C $SOURCEDIR
    cd $SOURCEDIR/iana-etc-20210202
    cp services protocols $LFS/etc
}

function buildInetutils {
    tar -xf $SOURCEDIR/inetutils-2.1.tar.xz -C $SOURCEDIR
    cd $SOURCEDIR/inetutils-2.1
    CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++" AR="${LFS_TGT}-ar" AS="${LFS_TGT}-as" RANLIB="${LFS_TGT}-ranlib" LD="${LFS_TGT}-ld" STRIP="${LFS_TGT}-strip" CFLAGS="-fPIE -march=${ARCH}" CXXFLAGS="-fPIE -march=${ARCH}" ./configure --host=$LFS_TGT --build=$($SOURCEDIR/binutils-2.36.1/config.guess) --prefix=/usr --localstatedir=/var --disable-logger --disable-whois --disable-rcp --disable-rexec --disable-rlogin --disable-rsh --disable-servers > /dev/null
    sed -i 's/PATH_PROCNET_DEV/"\/proc\/net\/dev"/g' ifconfig/system/linux.c
    make ARCH=$ARCH CROSS_COMPILE="${LFS_TGT}-" -j16 > /dev/null
    make ARCH=$ARCH CROSS_COMPILE="${LFS_TGT}-" DESTDIR=$LFS install > /dev/null
    mv -v $LFS/usr/bin/{hostname,ping,ping6,traceroute} $LFS/bin
    mv -v $LFS/usr/bin/ifconfig $LFS/sbin
}

function buildZlib {
    echo "Extracting Zlib source..."
    tar -xf $SOURCEDIR/zlib-1.2.11.tar.gz -C $SOURCEDIR
    cd $SOURCEDIR/zlib-1.2.11
    echo "Building Zlib..."
    CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++" AR="${LFS_TGT}-ar" AS="${LFS_TGT}-as" RANLIB="${LFS_TGT}-ranlib" LD="${LFS_TGT}-ld" STRIP="${LFS_TGT}-strip" CFLAGS="-fPIE -march=${ARCH}" CXXFLAGS="-fPIE -march=${ARCH}" ./configure --prefix=$LFS/usr > /dev/null
    make ARCH=$ARCH CROSS_COMPILE="${LFS_TGT}-" -j16 > /dev/null
    make ARCH=$ARCH CROSS_COMPILE="${LFS_TGT}-" install > /dev/null
    mv -v $LFS/usr/lib/libz.so.* $LFS/lib
    ln -sfv ../../lib/libz.so.1 $LFS/usr/lib/libz.so
}

function buildOpenSSL {
    echo "Extracting OpenSSL source..."
    tar -xf $SOURCEDIR/openssl-1.1.1j.tar.gz -C $SOURCEDIR
    cd $SOURCEDIR/openssl-1.1.1j
    echo "Building OpenSSL..."
    ./Configure --prefix=$LFS/usr --cross-compile-prefix="${LFS_TGT}-" --openssldir=$LFS/etc/ssl -I"${LFS}/usr/include" -L"${LFS}/usr/lib" --libdir=$LFS/lib shared zlib-dynamic -m32 $STD_TGT > /dev/null
    make clean > /dev/null
    make -j16 > /dev/null
    make install > /dev/null
}

function buildOpenSSH {
    echo "Extracting OpenSSH source..."
    tar -xf $SOURCEDIR/openssh-8.9p1.tar.gz -C $SOURCEDIR
    cd $SOURCEDIR/openssh-8.9p1
    echo "Building OpenSSH..."
    CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++" AR="${LFS_TGT}-ar" AS="${LFS_TGT}-as" RANLIB="${LFS_TGT}-ranlib" LD="${LFS_TGT}-ld" STRIP="${LFS_TGT}-strip" CFLAGS="-fPIE -march=${ARCH}" CXXFLAGS="-fPIE -march=${ARCH}" ./configure --host=$LFS_TGT --build=$($SOURCEDIR/binutils-2.36.1/config.guess) --prefix=/usr --sysconfdir=/etc/ssh --with-privsep-path=/var/lib/sshd --with-default-path=/usr/bin --with-superuser-path=/usr/sbin:/usr/bin --with-pid-dir=/run > /dev/null
    sed -i 's/PATH_PROCNET_DEV/"\/proc\/net\/dev"/g' ifconfig/system/linux.c
    make clean
    make ARCH=$ARCH CROSS_COMPILE="${LFS_TGT}-" -j16 > /dev/null
    make DESTDIR=$LFS install > /dev/null
}

function configureSystem {
    echo "Building file system layout..."
    mkdir -pv $LFS/{dev,proc,sys,run}
    mknod -m 600 $LFS/dev/console c 5 1
    mknod -m 666 $LFS/dev/null c 1 3
    chown -R root:root $LFS/{usr,lib,var,etc,bin,sbin,dev,proc,sys,run}
    case $(uname -m) in
        x86_64)
            chown -R root:root $LFS/lib64
            ;;
    esac
    echo "Mounting kernel file systems..."
    mount -v --bind /dev $LFS/dev > /dev/null
    mount -v --bind /dev/pts $LFS/dev/pts > /dev/null
    mount -vt proc proc $LFS/proc > /dev/null
    mount -vt sysfs sysfs $LFS/sys > /dev/null
    mount -vt tmpfs tmpfs $LFS/run > /dev/null
    if [ -h $LFS/dev/shm ]
    then
        mkdir -pv $LFS/$(readlink $LFS/dev/shm)
    fi
    cat > $LFS/setup2.sh << EOF
#!/bin/ash
echo "Linfinity Linux Setup"
echo "---------------------"
mkdir -pv /boot
mkdir -pv /etc/sysconfig
mkdir -pv /lib/firmware
mkdir -pv /media/cdrom
mkdir -pv /usr/local
mkdir -pv /usr/share
mkdir -pv /usr/bin
mkdir -pv /usr/lib
mkdir -pv /usr/sbin
mkdir -pv /usr/src
mkdir -pv /usr/local/share
mkdir -pv /usr/local/bin
mkdir -pv /usr/local/lib
mkdir -pv /usr/local/sbin
mkdir -pv /usr/local/src
mkdir -pv /usr/local/share/terminfo
mkdir -pv /usr/share/terminfo
mkdir -pv /var/cache
mkdir -pv /var/local
mkdir -pv /var/log
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp
ln -sv /proc/self/mounts /etc/mtab
echo "127.0.0.1 localhost linfinity" > /etc/hosts
cat > /etc/passwd << EOT
root::0:0:root:/root:/bin/ash
nobody::99:99:nobody:/dev/null:/bin/false
sshd::50:50:sshd PrivSep:/var/lib/sshd:/bin/false
EOT
cat > /etc/group << EOT
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tty:x:5:
daemon:x:6:
disk:x:8:
lp:x:9:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
sshd:x:50:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
nogroup:x:99:
users:x:999:
EOT
mkdir -pv /var/log
touch /var/log/btmp
touch /var/log/lastlog
touch /var/log/faillog
touch /var/log/wtmp
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp
touch /etc/ld.so.conf
mkdir -pv /var/cache/nscd
cat > /etc/network.conf << EOT
NETWORKING=yes
EOT
mkdir -pv /etc/network.d
cat > /etc/network.d/interface.eth0 << EOT
INTERFACE=eth0
DHCP=yes
EOT

cat > /etc/nsswitch.conf << EOT
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOT
cat > /etc/ld.so.conf << EOT
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOT
cat >> /etc/ld.so.conf << EOT
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOT
mkdir -pv /etc/ld.so.conf.d
cat > /etc/mdev.conf << EOT
# Devices:
# Syntax: %s %d:%d %s
# devices user:group mode

# null does already exist; therefore ownership has to
# be changed with command
null    root:root 0666  @chmod 666 $MDEV
zero    root:root 0666
grsec   root:root 0660
full    root:root 0666

random  root:root 0666
urandom root:root 0444
hwrandom root:root 0660

# console does already exist; therefore ownership has to
# be changed with command
console root:tty 0600 @mkdir -pm 755 fd && cd fd && for x in 0 1 2 3 ; do ln -sf /proc/self/fd/$x $x; done

kmem    root:root 0640
mem     root:root 0640
port    root:root 0640
ptmx    root:tty 0666

# ram.*
ram([0-9]*)     root:disk 0660 >rd/%1
loop([0-9]+)    root:disk 0660 >loop/%1
sd[a-z].*       root:disk 0660 */lib/mdev/usbdisk_link
hd[a-z][0-9]*   root:disk 0660 */lib/mdev/ide_links

tty             root:tty 0666
tty[0-9]        root:root 0600
tty[0-9][0-9]   root:tty 0660
ttyO[0-9]*      root:tty 0660
pty.*           root:tty 0660
vcs[0-9]*       root:tty 0660
vcsa[0-9]*      root:tty 0660

ttyLTM[0-9]     root:dialout 0660 @ln -sf $MDEV modem
ttySHSF[0-9]    root:dialout 0660 @ln -sf $MDEV modem
slamr           root:dialout 0660 @ln -sf $MDEV slamr0
slusb           root:dialout 0660 @ln -sf $MDEV slusb0
fuse            root:root  0666

# misc stuff
agpgart         root:root 0660  >misc/
psaux           root:root 0660  >misc/
rtc             root:root 0664  >misc/

# input stuff
event[0-9]+     root:root 0640 =input/
ts[0-9]         root:root 0600 =input/

# v4l stuff
vbi[0-9]        root:video 0660 >v4l/
video[0-9]      root:video 0660 >v4l/

# load drivers for usb devices
usbdev[0-9].[0-9]       root:root 0660 */lib/mdev/usbdev
usbdev[0-9].[0-9]_.*    root:root 0660
EOT

echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "linfinity" > /etc/HOSTNAME
cat > /etc/profile << EOT
export PATH=/bin:/usr/bin

if [ `id -u` -eq 0 ] ; then
        PATH=/bin:/sbin:/usr/bin:/usr/sbin
        unset HISTFILE
fi

# Set up some environment variables.
export USER=`id -un`
export LOGNAME=$USER
export HOSTNAME=`/bin/hostname`
export HISTSIZE=1000
export HISTFILESIZE=1000
export PAGER='/bin/more '
export EDITOR='/usr/bin/nano'
EOT
cat > /etc/fstab << EOT
# file system  mount-point  type   options          dump  fsck
#                                                         order

rootfs          /               auto    defaults        1      1
proc            /proc           proc    defaults        0      0
sysfs           /sys            sysfs   defaults        0      0
devpts          /dev/pts        devpts  gid=4,mode=620  0      0
tmpfs           /dev/shm        tmpfs   defaults        0      0
EOT
cat > /etc/issue << EOT
Linfinity Linux \r

EOT
cat > /etc/inittab << EOT
::sysinit:/etc/rc.d/startup

tty1::respawn:/sbin/getty 38400 tty1

::shutdown:/etc/rc.d/shutdown
::ctrlaltdel:/sbin/reboot
EOT
touch /var/run/utmp
chmod -v 664 /var/run/utmp
chmod -v 664 /var/log/lastlog

rm -rf /tmp/*
mkdir -pv /etc/rc.d
cat > /etc/rc.d/startup << EOT
#clear
EOT

cd /etc/sysconfig/
#cat > ifconfig.eth0 << EOT
#ONBOOT=yes
#IFACE=eth0
#GATEWAY=192.168.1.1
#PREFIX=24
#BROADCAST=192.168.1.255
#EOT
chmod 4755 /bin/busybox

install  -v -m700 -d /var/lib/sshd
chown -v root:sys /var/lib/sshd

cd /etc/ssh
ssh-keygen -A
EOF
    export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
    export HOME=/root
    export TMPDIR=/tmp
    echo "Entering chroot and launching setup environment..."
    chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/ash /setup2.sh
    umount -l $LFS/dev/pts > /dev/null
    umount -l $LFS/dev/shm > /dev/null 2> /dev/null
    umount -l $LFS/dev > /dev/null
    umount -l $LFS/proc > /dev/null
    umount -l $LFS/sys > /dev/null
    umount -l $LFS/run > /dev/null
    save_lib="ld-2.33.so libc-2.33.so libpthread-2.33.so libthread_db-1.0.so"
    cd $LFS/lib
    for LIB in $save_lib
    do
        strip --strip-unneeded $LIB
    done
    unset LIB save_lib save_usrlib
    find $LFS/usr/lib -type f -name \*.a -exec strip --strip-debug {} ';'
    find $LFS/lib $LFS/usr/lib -type f -name \*.so* ! -name \*dbg -exec strip --strip-unneeded {} ';'
    find $LFS/{bin,sbin} $LFS/usr/{bin,sbin,libexec} -type f -exec strip --strip-all {} ';'
    rm $LFS/setup2.sh
}

function buildKernel {
    rm -rf $SOURCEDIR/linux-5.10.17
    echo "Extracting Linux source..."
    tar -xf $SOURCEDIR/linux-5.10.17.tar.xz -C $SOURCEDIR
    cd $SOURCEDIR/linux-5.10.17
    ARCHX=$ARCH
    case $ARCH in
        i686)
            ARCH=x86
            ;;
    esac
    echo "Cleaning Linux source..."
    make mrproper > /dev/null
    echo "Configuring Linux kernel..."
    make ARCH=$ARCH CROSS_COMPILE=${LFS_TGT}- defconfig > /dev/null
    cp $BUILDDIR/kernelconfig $SOURCEDIR/linux-5.10.17/.config
    echo "Building Linux kernel..."
    make ARCH=$ARCH CROSS_COMPILE=${LFS_TGT}- -j16 > /dev/null
    make ARCH=$ARCH CROSS_COMPILE=${LFS_TGT}- INSTALL_MOD_PATH=$LFS modules_install > /dev/null
    find usr/include -name '.*' -delete
    rm usr/include/Makefile
    cp -rv usr/include $LFS/usr
    cp -v arch/x86/boot/bzImage $LFS/boot/vmlinuz-5.10.17
    cp -v System.map $LFS/boot/System.map-5.10.17
    cp -v .config $LFS/boot/config-5.10.17
    $TOOLSDIR/bin/depmod.pl -F $LFS/boot/System.map-5.10.17 -b $LFS/lib/modules/5.10.17 > /dev/null
    ARCH=$ARCHX
}

function installBootscripts {
    cd $BUILDDIR/bootscripts
    mkdir -pv $LFS/etc/rc.d/init.d
    mkdir -pv $LFS/etc/rc.d/start
    mkdir -pv $LFS/etc/rc.d/stop
    mkdir -pv $LFS/etc/init.d
    make DESTDIR=$LFS install-bootscripts > /dev/null
    ln -sv ../rc.d/startup $LFS/etc/init.d/rcS
}

function createDiskImage {
    mkdir -pv $BUILDDIR/imgroot
    cp -r $LFS/* $BUILDDIR/imgroot/
    rm -rf $BUILDDIR/imgroot/tools
    rm -rf $BUILDDIR/imgroot/usr/bin/man
    rm -rf $BUILDDIR/imgroot/usr/share/man
    rm -rf $BUILDDIR/imgroot/usr/local/share/man
    rm -rf $BUILDDIR/imgroot/usr/local/share/doc
    rm -rf $BUILDDIR/imgroot/usr/share/doc
    rm -rf $BUILDDIR/imgroot/usr/include
    rm -rf $BUILDDIR/imgroot/usr/local/share/locale
    rm -rf $BUILDDIR/imgroot/usr/share/i18n
    rm -rf $BUILDDIR/imgroot/usr/share/locale
    rm -rf $BUILDDIR/imgroot/usr/bin/locale
    rm -rf $BUILDDIR/imgroot/usr/bin/localedef
    rm -rf $BUILDDIR/imgroot/usr/bin/cc
    rm -rf $BUILDDIR/imgroot/usr/bin/gcc
    rm -rf $BUILDDIR/imgroot/usr/bin/c++
    rm -rf $BUILDDIR/imgroot/usr/bin/cpp
    rm -rf $BUILDDIR/imgroot/usr/bin/g++
    rm -rf $BUILDDIR/imgroot/usr/bin/gcc-*
    rm -rf $BUILDDIR/imgroot/usr/bin/gcov-*
    rm -rf $BUILDDIR/imgroot/usr/lib/*.a
    rm -rf $BUILDDIR/imgroot/usr/lib/*.la
    rm -rf $BUILDDIR/imgroot/usr/lib/gcc
    rm -rf $BUILDDIR/imgroot/usr/$LFS_TGT
    rm -rf $BUILDDIR/imgroot/usr/bin/${LFS_TGT}*
    rm -rf $BUILDDIR/imgroot/usr/libexec/gcc
    rm -rf $BUILDDIR/imgroot/lib/*.a
    rm -rf $BUILDDIR/imgroot/usr/lib/*.a
    cd $BUILDDIR
    echo "Creating disk image..."
    dd if=/dev/zero of=$BUILDDIR/linfinity.linux.img bs=1M count=96 > /dev/null
    echo "Mounting image..."
    lodev=$(losetup -f)
    losetup $lodev $BUILDDIR/linfinity.linux.img
    cat << EOF | fdisk $lodev
o
n
p
1
2048

a
p
w
q
EOF
    losetup -d $lodev
    lodev=$(losetup -f)
    losetup -P $lodev $BUILDDIR/linfinity.linux.img
    mkfs -t ext4 ${lodev}p1
    mkdir $BUILDDIR/imgdir
    mount ${lodev}p1 $BUILDDIR/imgdir
    echo "Creating bootloader congifuration..."
    mkdir -pv $LFS/boot/grub
    cat > $LFS/boot/grub/grub.cfg << EOF
set default=0
set timeout=2
set root=(hd0,msdos1)
menuentry "Linfinity Linux" {
    linux /boot/vmlinuz-5.10.17 root=/dev/sda1 ro quiet
}
EOF
    echo "Copying files..."
    cp -vr $BUILDDIR/imgroot/* $BUILDDIR/imgdir/
    echo "Installing bootloader..."
    grub_tgt=i386-pc
    grub-install --target=$grub_tgt --root-directory=$BUILDDIR/imgdir $lodev
    echo "Unmounting..."
    umount -l $BUILDDIR/imgdir
    losetup -d $lodev
    echo "Cleaning up..."
    rm -rf $BUILDDIR/imgdir
    rm -rf $BUILDDIR/imgroot
    echo "Linfinity Linux bootable image linfinity.linux.img created successfully! Have a nice day :)"
}

function createISO {
    mkdir iso
    cp -r rootfs/* iso/
    mkdir -pv iso/boot
    cp /usr/lib/ISOLINUX/isolinux.bin iso/boot/
    cp /lib/syslinux/modules/bios/ldlinux.c32 iso/
    cat > iso/isolinux.cfg <<EOF
default linux
label linux
  kernel /boot/vmlinuz-5.10.17
  append root=/dev/sda1 ro quiet
EOF
    genisoimage -r -V "Linfinity Linux" -cache-inodes -J -l -b boot/isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o linfinity.iso iso
}

function all {
    downloadSources
    start=`date +%s`
    buildCrossToolchain
    buildKernelHeaders
    buildGLibC
    buildLibstdcpp
    buildBusybox
    buildIanaEtc
    buildInetutils
    buildZlib
    buildOpenSSL
    buildOpenSSH
    configureSystem
    installBootscripts
    buildKernel
    createDiskImage
    end=`date +%s`
    runtime=$((end-start))
    echo "BUILD TIME: ${runtime}"
    #createISO
}

function run {
    qemu-system-i386 -hda linfinity.linux.img -netdev user,id=mynet0 -device e1000,netdev=mynet0
}

function nuclear {
    rm -rf sources
    rm -rf rootfs
    rm -rf tools
    rm -rf $BUILDDIR/imgroot
    rm -rf build
    rm -rf wget-list
    rm -rf linfinity.linux.img
}

if [ $# -eq 1 ]
then
    $1
fi

echo "Nothing left to do."
