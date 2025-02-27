# -----------------------------------------------------------------------------
#
# Package	: Calico
# Version	: v3.26.1
# Source repo	: https://github.com/projectcalico/calico
# Tested on	: rh7.8, rh7.9, rh8.6, rh8.8, rh9.0, rh9.2, sl12.5, sl15.4, sl15.5, ub20.04, ub22.04, ub23.04
# Language      : Go
# Travis-Check  : False
# Script License: Apache License, Version 2 or later
# Maintainer	: Yasir Ashfaq <Yasir.Ashfaq@ibm.com>
#
# Run as:	  docker run -it --network host -v /var/run/docker.sock:/var/run/docker.sock registry.access.redhat.com/ubi8
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------
#!/bin/bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

################################################################################################################################################################
#Script     :   build_calico.sh
#Description:   The script builds Calico version v3.26.1 on Linux on IBM Z for RHEL (7.8, 7.9, 8.6, 8.8, 9.0, 9.2), Ubuntu (20.04, 22.04, 23.04) and SLES (12 SP5, 15 SP4, 15 SP5).
#Maintainer :   LoZ Open Source Ecosystem (https://www.ibm.com/community/z/usergroups/opensource)
#Info/Notes :   Please refer to the instructions first for Building Calico mentioned in wiki( https://github.com/linux-on-ibm-z/docs/wiki/Building-Calico-3.x ).
#               Build and Test logs can be found in $CURDIR/logs/.
#               By Default, system tests are turned off. To run system tests for Calico, pass argument "-t" to shell script.
#
#Download build script :   wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.26.1/build_calico.sh
#Run build script      :   bash build_calico.sh       #(To only build Calico, provide -h for help)
#                          bash build_calico.sh -t    #(To build Calico and run system tests)
#
################################################################################################################################################################

USER_IN_GROUP_DOCKER=$(id -nGz $USER | tr '\0' '\n' | grep '^docker$' | wc -l)
set -e
set -o pipefail

PACKAGE_NAME="calico"
PACKAGE_VERSION="v3.26.1"
ETCD_VERSION="v3.5.1"
GOLANG_VERSION="go1.20.5.linux-s390x.tar.gz"
BIRD_VERSION="v0.3.3-202-g7a77fb7"
GOBUILD_VERSION="v0.85"
FORCE="false"
TESTS="false"
CURDIR="$(pwd)"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Calico/3.26.1/patch"
GO_INSTALL_URL="https://golang.org/dl/${GOLANG_VERSION}"
GO_DEFAULT="$CURDIR/go"
GO_FLAG="DEFAULT"
LOGDIR="$CURDIR/logs"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
fi

function prepare() {

    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$USER_IN_GROUP_DOCKER" == "1" ]]; then
        printf "User $USER belongs to group docker\n" |& tee -a "${LOG_FILE}"
    else
        printf "Please ensure User $USER belongs to group docker\n"
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        printf -- 'As part of the installation, dependencies would be installed/upgraded.\n'

        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)

                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide Correct input to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    rm -rf "${CURDIR}/${GOLANG_VERSION}" "${CURDIR}/etcd-v3.5.1-linux-s390x" "${CURDIR}/etcd-v3.5.1-linux-s390x.tar.gz"
    printf -- '\nCleaned up the artifacts.\n' >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- '\nConfiguration and Installation started \n'
    # Install go
    cd "$CURDIR"
    export LOG_FILE="$LOGDIR/configuration-$(date +"%F-%T").log"
    printf -- "\nInstalling Go ... \n" | tee -a "$LOG_FILE"
    wget $GO_INSTALL_URL
    sudo tar -C /usr/local -xzf ${GOLANG_VERSION}

    if [[ "${ID}" != "ubuntu" ]]; then
        sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
        printf -- 'Symlink done for gcc \n'
    fi

    # Set GOPATH if not already set
    if [[ -z "${GOPATH}" ]]; then
        printf -- "\nSetting default value for GOPATH \n"
        # Check if go directory exists
        if [ ! -d "$CURDIR/go" ]; then
            mkdir "$CURDIR/go"
        fi
        export GOPATH="${GO_DEFAULT}"
    else
        printf -- "\nGOPATH already set : Value : %s \n" "$GOPATH"
        if [ ! -d "$GOPATH" ]; then
            mkdir -p "$GOPATH"
        fi
        export GO_FLAG="CUSTOM"
    fi

    export PATH=/usr/local/go/bin:$PATH
    export PATH=$PATH:/usr/local/bin

    # Download `etcd ${ETCD_VERSION}`.
    cd "$CURDIR"
    wget --no-check-certificate https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-s390x.tar.gz
    tar xvf etcd-${ETCD_VERSION}-linux-s390x.tar.gz
    sudo cp -f etcd-${ETCD_VERSION}-linux-s390x/etcd /usr/local/bin

    printenv >>"$LOG_FILE"

    # Exporting Calico ENV to $CURDIR/setenv.sh for later use
    cd $CURDIR
    cat <<EOF >setenv.sh
#CALICO ENV
export GOPATH=$GOPATH
export PATH=$PATH
export LOGDIR=$LOGDIR
EOF

    # Start docker service
    printf -- "Starting docker service\n"
    sudo service docker start
    sleep 20s

    # Build `bpftool`
    export BPFTOOL_LOG="${LOGDIR}/bpftool-$(date +"%F-%T").log"
    touch $BPFTOOL_LOG
    printf -- "\nBuilding bpftool ... \n" | tee -a "$BPFTOOL_LOG"

    rm -rf $GOPATH/src/github.com/projectcalico/bpftool
    git clone https://github.com/projectcalico/bpftool $GOPATH/src/github.com/projectcalico/bpftool 2>&1 | tee -a "$BPFTOOL_LOG"
    cd $GOPATH/src/github.com/projectcalico/bpftool
    sed -i 's,buster-slim,bullseye-slim,g' Dockerfile.s390x
    sed -i 's,libgcc-8-dev,libgcc-10-dev,g' Dockerfile.s390x
    ARCH=s390x VERSION=v5.3 make image 2>&1 | tee -a "$BPFTOOL_LOG"

    # Build go-build v0.85
    export GOBUILD_LOG="${LOGDIR}/go-build-$(date +"%F-%T").log"
    touch $GOBUILD_LOG
    printf -- "\nBuilding go-build ${GOBUILD_VERSION} ... \n" | tee -a "$GOBUILD_LOG"

    rm -rf $GOPATH/src/github.com/projectcalico/go-build
    git clone -b v0.85 https://github.com/projectcalico/go-build $GOPATH/src/github.com/projectcalico/go-build 2>&1 | tee -a "$GOBUILD_LOG"
    cd $GOPATH/src/github.com/projectcalico/go-build
    printf -- "\nApplying patch for go-build Makefile ... \n" | tee -a "$GOBUILD_LOG"
    curl -s $PATCH_URL/go-build.patch | patch -p1
    ARCH=s390x VERSION=v0.85 ARCHIMAGE='$(DEFAULTIMAGE)' make image | tee -a "$GOBUILD_LOG"
    docker tag calico/go-build:v0.85 calico/go-build:v0.85-s390x | tee -a "$GOBUILD_LOG"
    if [ $(docker images 'calico/go-build:v0.85' | wc -l) == 2 ]; then
        echo "Successfully built calico/go-build:v0.85" | tee -a "$GOBUILD_LOG"
    else
        echo "go-build FAILED, Stopping further build !!! Check logs at $GOBUILD_LOG" | tee -a "$GOBUILD_LOG"
        exit 1
    fi

    # Build BIRD
    export BIRD_LOG="${LOGDIR}/bird-$(date +"%F-%T").log"
    touch $BIRD_LOG
    printf -- "\nBuilding BIRD ${BIRD_VERSION} ... \n" | tee -a "$BIRD_LOG"

    cd "$CURDIR"
    wget -O bird.tar.gz https://github.com/projectcalico/bird/tarball/${BIRD_VERSION} 2>&1 | tee -a "$BIRD_LOG"
    tar xvfz bird.tar.gz 2>&1 | tee -a "$BIRD_LOG"
    cd projectcalico-bird-7a77fb7/
    ./build.sh 2>&1 | tee -a "$BIRD_LOG"
    make image -f Makefile.calico 2>&1 | tee -a "$BIRD_LOG"
    docker tag calico/bird:latest-s390x calico/bird:v0.3.3-202-g7a77fb73-s390x
    cd "$CURDIR"
    sudo rm -rf bird.tar.gz projectcalico-bird-7a77fb7 2>&1 | tee -a "$BIRD_LOG"

    # Clone the Calico repo and apply patches where applicable
    rm -rf $GOPATH/src/github.com/projectcalico
    export CALICO_LOG="${LOGDIR}/calico-$(date +"%F-%T").log"
    touch $CALICO_LOG
    printf -- "\nBuilding calico ... \n" | tee -a "$CALICO_LOG"
    git clone -b $PACKAGE_VERSION https://github.com/projectcalico/calico $GOPATH/src/github.com/projectcalico/calico
    cd $GOPATH/src/github.com/projectcalico/calico
    printf -- "\Applying patch for calico ... \n" | tee -a "$CALICO_LOG"
    curl -s $PATCH_URL/calico.patch | patch -p1 2>&1 | tee -a "$CALICO_LOG"

    # Build Calico images
    ARCH=s390x make image 2>&1 | tee -a "$CALICO_LOG"
    ARCH=s390x make -C felix image 2>&1 | tee -a "$CALICO_LOG"

    # Build Calico binaries
    ARCH=s390x make -C api build 2>&1 | tee -a "$CALICO_LOG"
    ARCH=s390x make bin/helm 2>&1 | tee -a "$CALICO_LOG"

    # Tag docker images
    printf -- "\nTagging images ... \n" | tee -a "$CALICO_LOG"
    docker tag calico/node:latest-s390x calico/node:${PACKAGE_VERSION}
    docker tag calico/felix:latest-s390x calico/felix:${PACKAGE_VERSION}
    docker tag calico/typha:latest-s390x calico/typha:master-s390x
    docker tag calico/typha:latest-s390x calico/typha:${PACKAGE_VERSION}
    docker tag calico/ctl:latest-s390x calico/ctl:${PACKAGE_VERSION}
    docker tag calico/cni:latest-s390x calico/cni:${PACKAGE_VERSION}
    docker tag calico/apiserver:latest-s390x docker.io/calico/apiserver:${PACKAGE_VERSION}
    docker tag calico/pod2daemon-flexvol:latest-s390x calico/pod2daemon:latest-s390x
    docker tag calico/pod2daemon:latest-s390x calico/pod2daemon:${PACKAGE_VERSION}
    docker tag calico/pod2daemon-flexvol:latest-s390x calico/pod2daemon-flexvol:${PACKAGE_VERSION}
    docker tag calico/kube-controllers:latest-s390x calico/kube-controllers:${PACKAGE_VERSION}
    docker tag calico/dikastes:latest-s390x calico/dikastes:${PACKAGE_VERSION}
    docker tag calico/flannel-migration-controller:latest-s390x calico/flannel-migration-controller:${PACKAGE_VERSION}
}

function runTest() {
    export DIND_LOG="${LOGDIR}/dind-$(date +"%F-%T").log"
    touch $DIND_LOG
    source "${CURDIR}/setenv.sh" || true
    printf -- "\nBuilding dind Image for s390x ... \n" | tee -a "$DIND_LOG"
    rm -rf $GOPATH/src/github.com/projectcalico/dind
    git clone https://github.com/projectcalico/dind $GOPATH/src/github.com/projectcalico/dind 2>&1 | tee -a "$DIND_LOG"
    cd $GOPATH/src/github.com/projectcalico/dind
    # Build the dind
    docker build -t calico/dind -f Dockerfile-s390x . 2>&1 | tee -a "$DIND_LOG"

    if [ $(docker images 'calico/dind:latest' | wc -l) == 2 ]; then
        echo "Successfully built calico/dind" | tee -a "$DIND_LOG"
    else
        echo "calico/dind Build FAILED, Stopping further build !!! Check logs at $DIND_LOG" | tee -a "$DIND_LOG"
        exit 1
    fi

    export TEST_LOG="${LOGDIR}/testLog-$(date +"%F-%T").log"
    touch $TEST_LOG

    # Copy ETCD artifact to `calico_test`
    cd $GOPATH/src/github.com/projectcalico/calico/node
    mkdir -p calico_test/pkg
    cp $CURDIR/etcd-${ETCD_VERSION}-linux-s390x.tar.gz calico_test/pkg

    # Verifying if all images are built/tagged
    export VERIFY_LOG="${LOGDIR}/verify-images-$(date +"%F-%T").log"
    touch $VERIFY_LOG
    printf -- "export VERIFY_LOG=$VERIFY_LOG\n" >>"$CURDIR/setenv.sh"
    printf -- "\nVerifying if all needed images are successfully built/downloaded ? ... \n" | tee -a "$VERIFY_LOG"
    cd $CURDIR
    echo "Required Docker Images: " >>$VERIFY_LOG
    rm -rf docker_images_expected.txt
    rm -rf docker_images.txt

    cat <<EOF >docker_images_expected.txt
calico/dind:latest
calico/node:latest-s390x
calico/node:${PACKAGE_VERSION}
calico/cni:latest-s390x
calico/cni:${PACKAGE_VERSION}
calico/felix:latest-s390x
calico/felix:${PACKAGE_VERSION}
calico/typha:latest-s390x
calico/typha:${PACKAGE_VERSION}
calico/ctl:latest-s390x
calico/ctl:${PACKAGE_VERSION}
calico/pod2daemon:latest-s390x
calico/pod2daemon:${PACKAGE_VERSION}
calico/apiserver:latest-s390x
calico/apiserver:${PACKAGE_VERSION}
calico/kube-controllers:latest-s390x
calico/kube-controllers:${PACKAGE_VERSION}
calico/dikastes:latest-s390x
calico/dikastes:${PACKAGE_VERSION}
calico/flannel-migration-controller:latest-s390x
calico/flannel-migration-controller:${PACKAGE_VERSION}
calico/go-build:v0.85
EOF

    cat docker_images_expected.txt >>$VERIFY_LOG
    docker images --format "{{.Repository}}:{{.Tag}}" >docker_images.txt
    echo "" >>$VERIFY_LOG
    echo "" >>$VERIFY_LOG
    echo "Images present: " >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    echo "########################################################################" >>$VERIFY_LOG
    cat docker_images.txt >>$VERIFY_LOG
    count=0
    while read image; do
        if ! grep -q $image docker_images.txt; then
            echo ""
            echo "$image" | tee -a "$VERIFY_LOG"
            count=$(expr $count + 1)
        fi
    done <docker_images_expected.txt
    if [ "$count" != "0" ]; then
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "Above $count images need to be present. Check $VERIFY_LOG and the logs of above images/modules in $LOGDIR" | tee -a "$VERIFY_LOG"
        echo "CALICO NODE & TESTS BUILD FAILED !!" | tee -a "$VERIFY_LOG"
        exit 1
    else
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "" | tee -a "$VERIFY_LOG"
        echo "###################-----------------------------------------------------------------------------------------------###################" | tee -a "$VERIFY_LOG"
        echo "                                      All docker images are created as expected." | tee -a "$VERIFY_LOG"
        echo ""
        echo "                                  CALICO NODE & TESTS BUILD COMPLETED SUCCESSFULLY !!" | tee -a "$VERIFY_LOG"
        echo "###################-----------------------------------------------------------------------------------------------###################" | tee -a "$VERIFY_LOG"
    fi
    rm -rf docker_images_expected.txt docker_images.txt

    # Execute test cases
    export TEST_FELIX_LOG="${LOGDIR}/testFelixLog-$(date +"%F-%T").log"
    export TEST_KC_LOG="${LOGDIR}/testKCLog-$(date +"%F-%T").log"
    export TEST_CTL_LOG="${LOGDIR}/testCTLLog-$(date +"%F-%T").log"
    export TEST_CNI_LOG="${LOGDIR}/testCNILog-$(date +"%F-%T").log"
    export TEST_CONFD_LOG="${LOGDIR}/testConfdLog-$(date +"%F-%T").log"
    export TEST_APP_LOG="${LOGDIR}/testAppLog-$(date +"%F-%T").log"
    export TEST_NODE_LOG="${LOGDIR}/testNodeLog-$(date +"%F-%T").log"
    export TEST_APISERVER_LOG="${LOGDIR}/testApiserverLog-$(date +"%F-%T").log"
    export TEST_API_LOG="${LOGDIR}/testApiLog-$(date +"%F-%T").log"
    export TEST_TYPHA_LOG="${LOGDIR}/testTyphaLog-$(date +"%F-%T").log"
    export TEST_POD2DAEMON_LOG="${LOGDIR}/testPod2DaemonLog-$(date +"%F-%T").log"
    export TEST_LIBCALGO_LOG="${LOGDIR}/testLibCalGoLog-$(date +"%F-%T").log"

    touch $TEST_FELIX_LOG
    touch $TEST_KC_LOG
    touch $TEST_CTL_LOG
    touch $TEST_CNI_LOG
    touch $TEST_CONFD_LOG
    touch $TEST_APP_LOG
    touch $TEST_NODE_LOG
    touch $TEST_LOG
    touch $TEST_APISERVER_LOG
    touch $TEST_TYPHA_LOG
    touch $TEST_API_LOG
    touch $TEST_POD2DAEMON_LOG
    touch $TEST_LIBCALGO_LOG

    set +e

    cd $GOPATH/src/github.com/projectcalico/calico/node
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make test_image 2>&1 | tee -a "$TEST_NODE_LOG"
    docker tag calico/test:latest-s390x calico/test:latest
    ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make st 2>&1 | tee -a "$TEST_NODE_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/felix
    ARCH=s390x make ut 2>&1 | tee "$TEST_FELIX_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/kube-controllers
    ARCH=s390x make test 2>&1 | tee -a "$TEST_KC_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/calicoctl
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CTL_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/cni-plugin
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CNI_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/confd
    ARCH=s390x make test 2>&1 | tee -a "$TEST_CONFD_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/app-policy
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_APP_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/apiserver
    ARCH=s390x make test 2>&1 | tee -a "$TEST_APISERVER_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/api
    ARCH=s390x make test 2>&1 | tee -a "$TEST_API_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/typha
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_TYPHA_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/pod2daemon
    ARCH=s390x make test 2>&1 | tee -a "$TEST_POD2DAEMON_LOG" || true

    cd $GOPATH/src/github.com/projectcalico/calico/libcalico-go
    ARCH=s390x make ut 2>&1 | tee -a "$TEST_LIBCALGO_LOG" || true

    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n"
    printf -- "\n Please review results of individual test components."
    printf -- "\n Test results for individual components can be found in their respective repository under report folder."
    printf -- "\n Tests for individual components can be run as follows - for example, node component:"
    printf -- "\n source \$CURDIR/setenv.sh"
    printf -- "\n cd \$GOPATH/src/github.com/projectcalico/calico/node"
    printf -- "\n ARCH=s390x CALICOCTL_VER=latest CNI_VER=latest-s390x make st 2>&1 | tee -a \$LOGDIR/testLog-\$(date +"%%F-%%T").log \n"
    printf -- "\n------------------------------------------------------------------------------------------------------------------- \n"

    set -e
}

function logDetails() {
    printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- "\nDetected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo "bash  build_calico.sh  [-y install-without-confirmation] [-t install-with-tests]"
    echo
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
        if grep SUCCESSFULLY "$VERIFY_LOG" >/dev/null; then
            TESTS="true"
            printf -- "%s is detected with version %s .\n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
            runTest |& tee -a "$LOG_FILE"
            exit 0

        else
            TESTS="true"
        fi
        ;;
    esac
done

function printSummary() {
    printf -- '\n***********************************************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- '\n\nFor information on Getting started with Calico visit: \nhttps://github.com/projectcalico/calico \n\n'
    printf -- '***********************************************************************************************************************************\n'
}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y patch git curl tar gcc wget make docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin clang 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-7.8" | "rhel-7.9")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo yum-config-manager --enable docker-ce-stable
    sudo yum install -y curl git wget tar gcc glibc-static.s390x docker-ce make which patch 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"rhel-8.6" | "rhel-8.8" | "rhel-9.0" | "rhel-9.2")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo yum remove -y podman buildah
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo yum install -y curl git wget tar gcc glibc-static.s390x docker-ce docker-ce-cli containerd.io make which patch 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-12.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch docker libnghttp2-devel 2>&1 | tee -a "$LOG_FILE"
    wget --no-check-certificate https://github.com/docker/buildx/releases/download/v0.6.1/buildx-v0.6.1.linux-s390x
    mkdir -p ~/.docker/cli-plugins
    mv buildx-v0.6.1.linux-s390x ~/.docker/cli-plugins/docker-buildx
    chmod a+x ~/.docker/cli-plugins/docker-buildx
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
    
"sles-15.4")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    opensuse_repo="https://download.opensuse.org/repositories/security:SELinux/15.4/security:SELinux.repo"
    sudo zypper addrepo $opensuse_repo
    sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
    sudo zypper --gpg-auto-import-keys ref
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

"sles-15.5")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" | tee -a "$LOG_FILE"
    printf -- "Installing dependencies ... it may take some time.\n"
    sudo zypper install -y curl git wget tar gcc glibc-devel-static make which patch docker containerd docker-buildx 2>&1 | tee -a "$LOG_FILE"
    sudo wget -O /usr/local/bin/yq.v2 https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_s390x
    sudo chmod 755 /usr/local/bin/yq.v2
    export CC=gcc
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

# Run tests
if [[ "$TESTS" == "true" ]]; then
    runTest |& tee -a "$LOG_FILE"
fi

cleanup
printSummary |& tee -a "$LOG_FILE"
