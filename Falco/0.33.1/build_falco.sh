#!/bin/bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/0.33.1/build_falco.sh
# Execute build script: bash build_falco.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="falco"
PACKAGE_VERSION="0.33.1"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Falco/${PACKAGE_VERSION}/patch"

export SOURCE_ROOT="$(pwd)"

TEST_USER="$(whoami)"
FORCE="false"
TESTS="false"
LOG_FILE="$SOURCE_ROOT/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$SOURCE_ROOT/logs/" ]; then
    mkdir -p "$SOURCE_ROOT/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

DISTRO="$ID-$VERSION_ID"

function error() { echo "Error: ${*}"; exit 1; }

function prepare()
{

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' | tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    if [[ "${DISTRO}" =~ ^rhel-7 ]]; then
        rm -rf "${SOURCE_ROOT}/cmake-3.22.5.tar.gz"
    fi
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo mv "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile"
    fi

    printf -- '\nCleaned up the artifacts\n'
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'

    #Installing dependencies
    printf -- 'User responded with Yes. \n'
    printf -- 'Building dependencies\n'

    cd "${SOURCE_ROOT}"
    if [[ "${ID}" == "ubuntu" ]] || [[ "${DISTRO}" == "sles-12.5" ]] || [[ "${DISTRO}" =~ ^rhel-[78] ]]; then
        printf -- 'Installing Go v1.18.8\n'
	    cd $SOURCE_ROOT
	    wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh
	    bash build_go.sh -y -v 1.18.8
	    export GOPATH=$SOURCE_ROOT
	    export PATH=$GOPATH/bin:$PATH
        export CC=$(which gcc)
        export CXX=$(which g++)
	    go version
	    printf -- 'Go installed successfully\n'
    fi
    
    cd "${SOURCE_ROOT}"
    if [[ "${DISTRO}" =~ ^rhel-7 ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
        printf -- 'Building cmake 3.22.5\n'
        cd $SOURCE_ROOT
        wget https://github.com/Kitware/CMake/releases/download/v3.22.5/cmake-3.22.5.tar.gz
        tar -xf cmake-3.22.5.tar.gz
        cd cmake-3.22.5
        ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release
        make
        sudo make install
        sudo ln -sf /usr/local/bin/cmake /usr/bin/cmake
        printf -- 'cmake installed successfully\n'
    fi

    printf -- '\nDownloading Falco source. \n'
	
    cd $SOURCE_ROOT
    git clone https://github.com/falcosecurity/falco.git
    cd falco
    git checkout ${PACKAGE_VERSION}

    # Apply patch to plugins.cmake file
    curl -sSL ${PATCH_URL}/plugins.cmake.patch | git apply - || error "plugins.cmake patch"

    printf -- '\nStarting Falco cmake setup. \n'
    mkdir -p $SOURCE_ROOT/falco/build
    cd $SOURCE_ROOT/falco/build
    if [[ "${DISTRO}" == "sles-12.5" ]]; then
        sudo cp "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile" "/usr/src/linux-$SLES_KERNEL_VERSION/Makefile.back"
        sudo sed -i 's/-fdump-ipa-clones//g' /usr/src/linux-"$SLES_KERNEL_VERSION"/Makefile
    fi

    if [[ "${DISTRO}" == "ubuntu-18.04" ]] || [[ "${DISTRO}" == "sles-12.5" ]]; then
        CMAKE_FLAGS="-DUSE_BUNDLED_DEPS=ON -DUSE_BUNDLED_CURL=OFF"
    elif [[ "${DISTRO}" =~ ^rhel-7 ]]; then
        CMAKE_FLAGS="-DUSE_BUNDLED_DEPS=ON"
    else
        CMAKE_FLAGS="-DFALCO_ETC_DIR=/etc/falco -DUSE_BUNDLED_OPENSSL=On -DUSE_BUNDLED_DEPS=On -DCMAKE_BUILD_TYPE=Release"
    fi
    cmake $CMAKE_FLAGS ../
    
    printf -- '\nPatching Falco cmake files. \n'
    cd $SOURCE_ROOT/falco/build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs/cmake/modules
    
    # Upgrade curl version
    if [[ "${DISTRO}" =~ ^rhel-[789] ]] || [[ "${DISTRO}" =~ ^sles-15 ]] || [[ "${DISTRO}" == "ubuntu-20.04" ]] || [[ "${DISTRO}" =~ ^ubuntu-22 ]]; then
        sed -i 's+https://github.com/curl/curl/releases/download/curl-7_84_0/curl-7.84.0.tar.bz2+https://github.com/curl/curl/releases/download/curl-7_85_0/curl-7.85.0.tar.bz2+g' curl.cmake
        sed -i 's/702fb26e73190a3bd77071aa146f507b9817cc4dfce218d2ab87f00cd3bc059d/21a7e83628ee96164ac2b36ff6bf99d467c7b0b621c1f7e317d8f0d96011539c/g' curl.cmake
    fi

    # Move the 'libabsl_random_internal_platform.a' lib later in the linker list
    sed -i '135{h;d};136G' grpc.cmake

    # Patch the kernel module to fix the socketcall syscall.
    # The kernel module source exists in several dirs so make sure they are all in sync.
    printf -- '\nPatching Falco kernel module. \n'
    cd $SOURCE_ROOT/falco/
    curl -sSL ${PATCH_URL}/libs-driver-socketcall.patch | git apply -v --directory=build/falcosecurity-libs-repo/falcosecurity-libs-prefix/src/falcosecurity-libs - || error "build/falcosecurity-libs-repo libs-driver-socketcall patch"
    curl -sSL ${PATCH_URL}/libs-driver-socketcall.patch | git apply -v --directory=build/driver-repo/driver-prefix/src - || error "build/driver-repo libs-driver-socketcall patch"
    curl -sSL ${PATCH_URL}/libs-driver-socketcall.patch | git apply -v --directory=build/driver/src -p2 - || error "build/driver libs-driver-socketcall patch"

    printf -- '\nStarting Falco build. \n'
    cd $SOURCE_ROOT/falco/build/
    make

    if [[ "${ID}" == "rhel" ]] || [[ "${ID}" == "ubuntu" ]]; then
        printf -- '\nStarting Falco package. \n'
        make package
    fi

    printf -- '\nStarting Falco install. \n'
    sudo make install
    printf -- '\nFalco build completed successfully. \n'

    printf -- '\nInserting Falco kernel module. \n'
    sudo rmmod falco || true

    cd $SOURCE_ROOT/falco/build
    sudo insmod driver/falco.ko
    printf -- '\nInserted Falco kernel module successfully. \n'

    # Run Tests
    runTest
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
       cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" | tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "  bash build_falco.sh  [-d debug] [-y install-without-confirmation] [-t run-tests-after-build] "
    echo
}

function runTest() {
    set +e

    if [[ "$TESTS" == "true" ]]; then
        cd $SOURCE_ROOT/falco/build
        make tests
    fi

    set -e
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    y)
        FORCE="true"
        ;;
    t)
        if command -v "$PACKAGE_NAME" >/dev/null; then
            printf -- "%s is detected in the system. Skipping build and running tests .\n" "$PACKAGE_NAME" | tee -a "$LOG_FILE"
            TESTS="true"
            runTest
            exit 0
        else
            TESTS="true"
        fi

        ;;
    esac
done

function printSummary() {

    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\nRun falco --help to see all available options to run falco.'
    printf -- '\nSee https://github.com/falcosecurity/event-generator for information on testing falco.'
    printf -- '\nFor more information on Falco please visit https://falco.org/docs/ \n\n'
    printf -- '**********************************************************************************************************\n'
}

logDetails
prepare

case "$DISTRO" in

"ubuntu-18.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo apt-get update
    sudo apt-get install -y curl kmod git cmake build-essential pkg-config autoconf libtool libelf-dev libcurl4-openssl-dev patch wget rpm linux-headers-$(uname -r) gcc

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"
  
    sudo apt-get update
    sudo apt-get install -y git cmake build-essential pkg-config autoconf wget curl patch libtool libelf-dev gcc rpm linux-headers-$(uname -r) kmod

    configureAndInstall | tee -a "$LOG_FILE"
    ;;
	
"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y devtoolset-7-gcc devtoolset-7-gcc-c++ devtoolset-7-toolchain devtoolset-7-libstdc++-devel glibc-static openssl-devel autoconf automake libtool createrepo expect git which rpm-build git libarchive wget bzip2 perl-FindBin make autoconf automake pkg-config patch elfutils-libelf-devel diffutils kernel-devel-$(uname -r) kmod
	source /opt/rh/devtoolset-7/enable
    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-8.4" | "rhel-8.6" | "rhel-8.7")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install -y gcc gcc-c++ git make cmake autoconf automake pkg-config patch libtool elfutils-libelf-devel diffutils which createrepo libarchive wget curl rpm-build kmod kernel-devel-$(uname -r)

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"rhel-9.0" | "rhel-9.1")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    sudo yum install --allowerasing -y gcc gcc-c++ git make cmake autoconf automake pkg-config patch perl-FindBin libtool elfutils-libelf-devel diffutils which createrepo libarchive wget curl rpm-build kmod kernel-devel-$(uname -r) go
    go version

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//')
    SLES_KERNEL_PKG_VERSION=$(sudo zypper se -s 'kernel-default-devel' | grep ${SLES_KERNEL_VERSION} | cut -d "|" -f 4 - | tr -d '[:space:]')

	sudo zypper install -y --force-resolution gcc9 gcc9-c++ git-core patch which automake autoconf libtool libopenssl-devel libcurl-devel libelf-devel "kernel-default-devel=${SLES_KERNEL_PKG_VERSION}" tar curl

    sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 50
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 20
    sudo update-alternatives --skip-auto --config gcc
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 50
    export CC=$(which gcc)
    export CXX=$(which g++)

    configureAndInstall | tee -a "$LOG_FILE"
    ;;

"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- '\nInstalling dependencies \n' | tee -a "$LOG_FILE"

    SLES_KERNEL_VERSION=$(uname -r | sed 's/-default//')
    SLES_KERNEL_VERSION=$(sudo zypper se -s 'kernel-default-devel' | grep ${SLES_KERNEL_VERSION} | cut -d "|" -f 4 - | tr -d '[:space:]')
    sudo zypper install -y gcc gcc-c++ git-core cmake patch which automake autoconf libtool libelf-devel tar curl vim wget pkg-config glibc-devel-static go1.18 "kernel-default-devel=${SLES_KERNEL_VERSION}" kmod
    go version
	
    configureAndInstall | tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" | tee -a "$LOG_FILE"
    exit 1
    ;;
esac

printSummary | tee -a "$LOG_FILE"
