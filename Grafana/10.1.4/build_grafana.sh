# -----------------------------------------------------------------------------
#
# Package	: Grafana
# Version	: v10.1.4
# Source repo	: https://github.com/grafana/grafana
# Tested on	: Ub20.04
# Language      : Typescript
# Travis-Check  : False
# Script License: Apache License, Version 2 or later
# Maintainer	: Prashant Jagtap <Prashant.Jagtap@ibm.com>
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
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/10.1.4/build_grafana.sh
# Execute build script: bash build_grafana.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="grafana"
PACKAGE_VERSION="10.1.4"
CURDIR="$(pwd)"
export PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Grafana/${PACKAGE_VERSION}/patch"


GO_VERSION="1.21.1"
NODE_JS_VERSION="18.18.0"

GO_DEFAULT="$HOME/go"

FORCE="false"
TESTS="false"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

# Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\n\nAs part of the installation , Go "${GO_VERSION}", NodeJS "${NODE_JS_VERSION}" will be installed, \n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' |& tee -a "$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	if [ -f $CURDIR/node-v${NODE_JS_VERSION}-linux-s390x/bin/yarn ]; then
		rm $CURDIR/node-v${NODE_JS_VERSION}-linux-s390x/bin/yarn
	fi

	if [ -f "$CURDIR/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz" ]; then
		rm "$CURDIR/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz"
	fi

	if [ -f "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz" ]; then
		rm "$CURDIR/go${GO_VERSION}.linux-s390x.tar.gz"
	fi

	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function buildGCC() {
    cd "${SOURCE_ROOT}"
    installer=yum
    if [[ "$DISTRO" == sles-12.5 ]]; then
    	installer=zypper
    fi
    sudo ${installer} install -y tar zip gcc-c++ unzip python3 cmake curl wget gcc vim patch binutils-devel tcl gettext bzip2 make
    GCC_VERSION=9.2.0
    wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz
    tar -xf gcc-${GCC_VERSION}.tar.gz
    cd gcc-${GCC_VERSION}
    ./contrib/download_prerequisites
    mkdir objdir
    cd objdir
    ../configure --prefix=/opt/gcc --enable-languages=c,c++ --with-arch=zEC12 --with-long-double-128 \
         --build=s390x-linux-gnu --host=s390x-linux-gnu --target=s390x-linux-gnu                  \
         --enable-threads=posix --with-system-zlib --disable-multilib
    make -j $(nproc)
    sudo make install
    sudo ln -sf /opt/gcc/bin/gcc /usr/bin/gcc
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/g++
    sudo ln -sf /opt/gcc/bin/g++ /usr/bin/c++
    export PATH=/opt/gcc/bin:"$PATH"
    export LD_LIBRARY_PATH=/opt/gcc/lib64:"$LD_LIBRARY_PATH"
    export C_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/${GCC_VERSION}/include
    export CPLUS_INCLUDE_PATH=/opt/gcc/lib/gcc/s390x-linux-gnu/${GCC_VERSION}/include
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

	# Install grafana
	printf -- "\nInstalling %s..... \n" "$PACKAGE_NAME"

	# Grafana installation

	#Build GCC for Rhel 7.x and/or Sles 12.5
    	if [[ "$DISTRO" == rhel-7* ]] || [[ "$DISTRO" == sles-12.5 ]]; then
        	buildGCC
    	fi

	# Install NodeJS
	
	# Rhel 7.x and Sles 12.5 dont support NodeJS 18
	if [[ "$DISTRO" == rhel-7* ]] || [[ "$DISTRO" == sles-12.5 ]]; then
		NODE_JS_VERSION=17.9.1
		printf -- "Rhel 7.x and Sles 12.5 dont support NodeJS 18, hence using NodeJS 17.9.1\n"
	fi
	
	cd "$CURDIR"
	wget https://nodejs.org/dist/v${NODE_JS_VERSION}/node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	chmod ugo+r node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	sudo tar -C /usr/local -xf node-v${NODE_JS_VERSION}-linux-s390x.tar.xz
	export PATH=$PATH:/usr/local/node-v${NODE_JS_VERSION}-linux-s390x/bin

	printf -- 'Install NodeJS success \n'

	cd "${CURDIR}"

	# Install go
	printf -- "Installing Go... \n"
	wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/1.18.4/build_go.sh
	bash build_go.sh -y -v ${GO_VERSION}
	go version
	printf -- 'Extracted the tar in /usr/local and created symlink\n'

	  if [[ "${ID}" != "ubuntu" ]]; then
		  sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
		  printf -- 'Symlink done for gcc \n'
	  fi
	  # Set GOPATH if not already set
	  if [[ -z "${GOPATH}" ]]; then
		  printf -- "Setting default value for GOPATH \n"

		  #Check if go directory exists
		  if [ ! -d "$HOME/go" ]; then
			  mkdir "$HOME/go"
		  fi
		  export GOPATH="${GO_DEFAULT}"
	  else
		  printf -- "GOPATH already set : Value : %s \n" "$GOPATH"
	  fi
	printenv >>"$LOG_FILE"

  	# Install yarn
	sudo chmod ugo+w -R /usr/local/node-v${NODE_JS_VERSION}-linux-s390x/
	npm install -g yarn
	yarn set version 4.0.0-rc.45
	yarn --version

	printf -- 'yarn install success \n'

	# Build Grafana
	printf -- "Building Grafana... \n"

	cd "$GOPATH"
	if [ -d "$GOPATH/grafana" ]; then
		rm -rf "$GOPATH/grafana"
		printf -- "Removing Existing Grafana Directory at GOPATH \n"
	fi

	git clone https://github.com/grafana/grafana.git
	cd grafana
	git checkout -f v"${PACKAGE_VERSION}"
	wget -O yarnrc.patch $PATCH_URL/yarnrc.patch
	git apply yarnrc.patch

	printf -- "Created grafana Directory at 1 \n"
	make gen-go
	make deps-go
	make build-go
	printf -- 'Build Grafana success \n'

	#Add grafana to /usr/bin
	sudo cp "$GOPATH/grafana/bin/linux-s390x/grafana" /usr/bin/
	sudo cp "$GOPATH/grafana/bin/linux-s390x/grafana-server" /usr/bin/
	sudo cp "$GOPATH/grafana/bin/linux-s390x/grafana-cli" /usr/bin/

	printf -- 'Add grafana to /usr/bin success \n'

	# Build Grafana frontend assets
	yarn install
	mkdir plugins-bundled/external
	export NODE_OPTIONS="--max-old-space-size=8192"
	make build-js

	printf -- 'Grafana frontend assets build success \n'

	cd "${CURDIR}"

	# Move build artifacts to default directory
	if [ ! -d "/usr/local/share/grafana" ]; then
		printf -- "Created grafana Directory at /usr/local/share \n"
		sudo mkdir /usr/local/share/grafana
	fi

	sudo cp -r "$GOPATH/grafana"/* /usr/local/share/grafana
	#Give permission to user
	sudo chown -R "$USER" /usr/local/share/grafana/
	printf -- 'Move build artifacts success \n'

	#Add grafana config
	if [ ! -d "/etc/grafana" ]; then
		printf -- "Created grafana config Directory at /etc \n"
		sudo mkdir /etc/grafana/
	fi

	#Add backend rendering in config
	sudo cp /usr/local/share/grafana/conf/defaults.ini /etc/grafana/grafana.ini
	printf -- 'Add grafana config success \n'

	#Create alias
	echo "alias grafana-server='sudo grafana-server -homepath /usr/local/share/grafana -config /etc/grafana/grafana.ini'" >> ~/.bashrc

	# Run Tests
	runTest

	#Cleanup
	cleanup

	#Verify grafana installation
	if command -v "$PACKAGE_NAME-server" >/dev/null; then
		printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
	else
		printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
		exit 127
	fi
}

function runTest() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"

		cd "$GOPATH/grafana"
		# Test backend
		make test-go

		# Test frontend
		echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
		yarn test --watchAll=false
		printf -- "Tests completed. \n"

	fi
	set -e
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo " bash build_grafana.sh  [-d debug] [-y install-without-confirmation] [-t install-with-tests]"
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
		TESTS="true"
		;;
	esac
done

function gettingStarted() {
	printf -- '\n***************************************************************************************\n'
	printf -- "Getting Started: \n"
	printf -- "To run grafana , run the following command : \n"
	printf -- "    source ~/.bashrc  \n"
	printf -- "    grafana-server  &   (Run in background)  \n"
	printf -- "\nAccess grafana UI using the below link : "
	printf -- "http://<host-ip>:<port>/    [Default port = 3000] \n"
	printf -- "\n Default homepath: /usr/local/share/grafana \n"
	printf -- "\n Default config:  /etc/grafana/grafana.ini \n"
	printf -- '***************************************************************************************\n'
	printf -- '\n'
}

###############################################################################################################

logDetails
prepare # Check Prequisites

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo apt-get update
	sudo apt-get install -y gcc g++ tar wget git make xz-utils patch curl python3 |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.6" | "rhel-8.8" | "rhel-9.0" | "rhel-9.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y make gcc gcc-c++ tar wget git git-core patch xz curl python3 |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5" | "sles-15.4" | "sles-15.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y make gcc gcc-c++ wget tar git xz gzip curl patch python3 libnghttp2-devel |& tee -a "$LOG_FILE"
	if [[ "$DISTRO" == sles-12.5 ]]; then
		# Get updated python
    		wget -q https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Python3/3.11.4/build_python3.sh
		bash build_python3.sh -y
    	fi
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
