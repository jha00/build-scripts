#!/usr/bin/env bash
# © Copyright IBM Corporation 2023
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Ruby/3.2.2/build_ruby.sh
# Execute build script: bash build_ruby.sh    (provide -h for help)
#
set -e -o pipefail
PACKAGE_NAME="ruby"
PACKAGE_VERSION="3.2.2"
CURDIR="$PWD"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
trap cleanup 1 2 ERR
TESTS="false"
FORCE="false"
#Check if directory exsists
if [ ! -d "logs" ]; then
   mkdir -p "logs"
fi
if [ -f "/etc/os-release" ]; then
	source "/etc/os-release"
fi

function checkPrequisites()
{
  if command -v "sudo" > /dev/null ;
  then
    printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
  else
    printf -- 'Sudo : No \n' >> "$LOG_FILE"
    printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
  fi;

if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}
function cleanup()
{
  cd "${CURDIR}"
  rm -rf "${PACKAGE_NAME}"-"${PACKAGE_VERSION}".tar.gz
  printf -- 'Cleaned up the artifacts\n'
}
function runTest() {
if [[ "$TESTS" == "true" ]]; then
		printf -- 'Running tests \n\n'
		cd "${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}"
		make test
    printf -- 'Test Completed \n\n'
	fi
}
function configureAndInstall()
{
  printf -- 'Configuration and Installation started \n'
#Download the source code
  printf -- 'Downloading ruby \n'
  cd "${CURDIR}"
  wget http://cache.ruby-lang.org/pub/ruby/3.2/ruby-${PACKAGE_VERSION}.tar.gz
  tar zxf "${PACKAGE_NAME}"-"${PACKAGE_VERSION}".tar.gz
  cd "${CURDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}"
#Building ruby
  printf -- 'Building ruby \n'
  ./configure
  make
#Installation step
  sudo make install
export PATH="$PATH:/usr/local/bin"
#Run tests
  runTest
#Verify installation
  ruby -v
  gem env
#Clean up the downloaded zip
  cleanup
}
function logDetails()
{
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' > "$LOG_FILE";
if [ -f "/etc/os-release" ]; then
	    cat "/etc/os-release" >> "$LOG_FILE"
    fi
cat /proc/version >> "$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >> "$LOG_FILE";
printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}
# Print the usage message
function printHelp() {
  echo
  echo "Usage: "
  echo "bash build_ruby.sh [-d debug] [-t install-with-tests] [-y install-without-confirmation]"
  echo
}
while getopts "dthy?" opt; do
  case "$opt" in
  d)
    set -x
    ;;
  t)
    TESTS="true"
    ;;
  y)
    FORCE="true"
    ;;
  h | \?)
    printHelp
    exit 0
    ;;
  esac
done
function gettingStarted()
{
printf -- "\n\nUsage: \n"
  printf -- "  Ruby installed successfully \n"
  printf -- '  Run command export PATH="$PATH:/usr/local/bin" or add it to .bashrc file for permanant changes \n'
  printf -- "  More information can be found here : https://github.com/ruby/ruby \n"
  printf -- '\n'
}
###############################################################################################################
logDetails
checkPrequisites  #Check Prequisites
DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-22.10" | "ubuntu-23.04")
  printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
  sudo apt-get update > /dev/null
  sudo apt-get install -y gcc make wget tar bison flex openssl libssl-dev libdb-dev libgdbm-dev libreadline-dev libyaml-dev |& tee -a "${LOG_FILE}"
  configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable=rhel-7-server-for-system-z-rhscl-rpms || true
	sudo yum install -y devtoolset-7-gcc-c++ devtoolset-7-gcc bison flex openssl-devel readline-devel gdbm-devel make wget tar libyaml-devel |& tee -a "${LOG_FILE}"
	source /opt/rh/devtoolset-7/enable
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"rhel-8.6" | "rhel-8.7" | "rhel-8.8" | "rhel-9.0" | "rhel-9.1" | "rhel-9.2")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo yum install -y bison flex openssl-devel readline-devel gdbm-devel gcc make wget tar libyaml-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y bison flex libopenssl-devel readline-devel gdbm-devel gcc7 make wget tar gawk gzip libyaml-devel |& tee -a "${LOG_FILE}"
	sudo ln -sf /usr/bin/gcc-7 /usr/bin/gcc
	sudo ln -sf /usr/bin/gcc /usr/bin/cc
	configureAndInstall |& tee -a "${LOG_FILE}"
;;
"sles-15.4" | "sles-15.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	sudo zypper install -y bison flex libopenssl-devel readline-devel gdbm-devel gcc make wget tar gawk gzip libyaml-devel |& tee -a "${LOG_FILE}"
	configureAndInstall |& tee -a "${LOG_FILE}"
  ;;
*)
  printf -- "%s not supported \n" "$DISTRO"|& tee -a "$LOG_FILE"
  exit 1 ;;
esac
gettingStarted |& tee -a "${LOG_FILE}"
