#!/bin/bash
####									####
#									   #
#    Q&D build script for OnePlus 6/6T kernel by ZaneZam		   #
#    based on infos from Nathan Chancellor (thx and credits!)		   #
#    Details: https://github.com/nathanchance/android-kernel-clang	   #
#									   #
#    Infos about 'ZZupreme Builds' for which this script was mainly	   #
#    made for: https://github.com/zanezam/FK-ZZupreme-Build		   #
#									   #
####									####

# version of this script
SCRIPTVER="1.3"

# franco kernel release (source-base of the build)
FKREL="22"

# version of zzupreme build
BUILDVERSION="2.3"

# keystore for zip signing (with jarsigner) leave empty or comment out to disable signing of anykernel zip
KEYSTORE="/path/to/keystore/zzupreme.keystore"

# project dir
PROJECTDIR="/path/to/project-root"

# sources dir
SOURCEDIR="$PROJECTDIR/sources/franco/enchilada"

# compile output dir (should be included in git ignore list in the local repo)
OUTDIR="out"

# anykernel template dir (included in this kernel repo)
ANYKERNEL="$SOURCEDIR/anykernel"

# force username for kernel string (if not set it will be the actual user which builds the kernel)
BUILDUSER=""
if [ -z "$BUILDUSER" ]; then
    BUILDUSER=$(whoami | sed 's/\\/\\\\/')
fi

# force hostname for kernel string (if not set it will be the hostname on which the kernel is build)
BUILDHOST=""
if [ -z "$BUILDHOST" ]; then
    BUILDHOST=`hostname`
fi

# name of the kernel (for zip package naming)
KERNAME="fk-r$FKREL-zzupreme"

# addendum to kernel version (for zip package naming)
VERSIONADD=""

# default config to use for compilation (eg. franco_defconfig for franco config, sdm845-perf_defconfig = default of unchanged sources)
KERNCONFIG="zzupreme_defconfig"

# name and location of build log file
BUILDLOG="$SOURCEDIR/$OUTDIR/zz_buildlog.log"

# release directory in which the ready anykernel zips land
RELEASEDIR="$PROJECTDIR/releases"

# this is a OP6 PIE compatible stock toolchain (for normal build with toolchain prefix)
TOOLCHAIN="/path/to/toolchain/aarch64-linux-android-4.9/bin/aarch64-linux-android-"

# this is the clang toolchain folder (only the dir of toolchain without a prefix)
CLANGTOOLCHAIN="/path/to/toolchain/clang/clang-4691093"

# this is the gcc toolchain folder for clang compilation (for linking etc. to fix odd issues)
GCCTOOLCHAIN="/path/to/toolchain/aarch64-linux-android-4.9" # this is the folder to the PIE compatible gcc toolchain

# set number of cpu cores to be used. leave empty for autodetection
NUM_CORES=

# get number of cpus for compile usage
if [ -z "$NUM_CORES" ]; then
    NUM_CORES=`nproc --all`
fi

# start time for compile counter
START=$(date +%s)

build="$1"

# compile time counter
endtime()
{
    END=$(date +%s)
    ELAPSED=$((END - START))
    E_MIN=$((ELAPSED / 60))
    E_SEC=$((ELAPSED - E_MIN * 60))
    echo -e $COLOR_ORANGE
    printf "Image Build time: "
    echo -e $COLOR_NEUTRAL
    [ $E_MIN != 0 ] && printf "%d min(s) " $E_MIN
    printf "%d sec(s)\n" $E_SEC
}

print_info()
{
    echo ""
    echo "Start $build building of $KERNAME-$BUILDVERSION$VERSIONADD with kernel string: $BUILDUSER@$BUILDHOST / $KBUILD_COMPILER_STRING"
    echo ""
    sleep 1
}

sign_image()
{
    echo "Signing zip..."
    jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore $KEYSTORE -tsa http://timestamp.digicert.com -storepass zzupreme $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.zip zzupreme 1> /dev/null 2>&1
    echo ""
    echo "Done!"
}

pack_image()
{
    # timestamp for filename
    STAMP=`date +%Y-%m-%d-%H%M%S`
    echo ""
    echo "Going to pack kernel image files into anykernel template now..."
    rm -f $OUTDIR/anykernel/kernel/placeholder
    rm -f $OUTDIR/anykernel/dtbs/placeholder
    cd  $OUTDIR/anykernel
    zip -r $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.zip .
    echo "Done!"
    echo ""
    if [ ! -z $KEYSTORE ]; then
	sign_image
    fi
    md5sum $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.zip > $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.md5
    mv -f $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.zip $RELEASEDIR
    mv -f $KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.md5 $RELEASEDIR
    echo ""
    echo "$KERNAME-$BUILDVERSION$VERSIONADD-$STAMP-anykernel.zip placed in $RELEASEDIR"
    echo ""
}

case "$1" in

gcc)
    export KBUILD_BUILD_VERSION=$FKREL
    export KBUILD_BUILD_USER=$BUILDUSER
    export KBUILD_BUILD_HOST=$BUILDHOST
    export KBUILD_COMPILER_STRING="$($GCCTOOLCHAIN/bin/aarch64-linux-android-gcc -v 2>&1 | grep ' version ' | sed 's/[[:space:]]*$//')"
    clear
    print_info
    cd $SOURCEDIR
    if [ -f arch/arm64/configs/$KERNCONFIG ]; then
	make O=$OUTDIR ARCH=arm64 $KERNCONFIG
    else
	echo "$KERNCONFIG config not found, be sure that it exists in $SOURCEDIR/arch/arm64/configs!!"
	exit 1
    fi
    ./scripts/config --file out/.config -e BUILD_ARM64_DT_OVERLAY
    make O=$OUTDIR ARCH=arm64 olddefconfig
    make O=$OUTDIR ARCH=arm64 CROSS_COMPILE=$TOOLCHAIN DTC_EXT=dtc -j$NUM_CORES 2>&1 | tee $BUILDLOG
    echo ""
    echo "Build done!"
    endtime && endtime >> $BUILDLOG
    if [ -f $SOURCEDIR/$OUTDIR/arch/arm64/boot/Image.gz ]; then
	cp -rf $ANYKERNEL $OUTDIR/anykernel
	cp -f $SOURCEDIR/$OUTDIR/arch/arm64/boot/Image.gz $OUTDIR/anykernel/kernel
	find . -name "*.dtb" -exec cp -f '{}' $OUTDIR/anykernel/dtbs \;
    else
	echo "No image file found! Something went wrong, check $BUILDLOG!!"
	exit 1
    fi
    pack_image
;;

clang)
    export KBUILD_BUILD_VERSION=$FKREL
    export KBUILD_BUILD_USER=$BUILDUSER
    export KBUILD_BUILD_HOST=$BUILDHOST
    export KBUILD_COMPILER_STRING="$($CLANGTOOLCHAIN/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
    clear
    print_info
    cd $SOURCEDIR
    if [ -f arch/arm64/configs/$KERNCONFIG ]; then
	make O=$OUTDIR ARCH=arm64 $KERNCONFIG
    else
	echo "$KERNCONFIG config not found, be sure that it exists in $SOURCEDIR/arch/arm64/configs!!"
    exit 1
    fi
    ./scripts/config --file out/.config -e BUILD_ARM64_DT_OVERLAY
    make O=$OUTDIR ARCH=arm64 olddefconfig
    PATH="$CLANGTOOLCHAIN/bin:$GCCTOOLCHAIN/bin:${PATH}" make -j$NUM_CORES O=$OUTDIR ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- DTC_EXT=dtc 2>&1 | tee $BUILDLOG
    echo ""
    echo "Build done!"
    endtime && endtime >> $BUILDLOG
    if [ -f $SOURCEDIR/$OUTDIR/arch/arm64/boot/Image.gz ]; then
	cp -rf $ANYKERNEL $OUTDIR/anykernel
	cp -f $SOURCEDIR/$OUTDIR/arch/arm64/boot/Image.gz $OUTDIR/anykernel/kernel
	find . -name "*.dtb" -exec cp -f '{}' $OUTDIR/anykernel/dtbs \;
    else
	echo "No image file found! Something went wrong, check $BUILDLOG!!"
	exit 1
    fi
    pack_image
;;

clean)
    rm -rf $SOURCEDIR/$OUTDIR
    echo ""
    cd $SOURCEDIR
    echo "Sources cleaned, checking status of repo..."
    echo ""
    git status
;;

*)
    echo ""
    echo "Build Script $SCRIPTVER for enchilada kernel by ZaneZam"
    echo ""
    echo "Usage: $0 gcc | clang | clean"
    echo ""
;;

esac
