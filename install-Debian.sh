#!/bin/bash

set -e

package_sysname="onlyoffice";
DS_COMMON_NAME="onlyoffice";
RES_APP_INSTALLED="is already installed";
RES_APP_CHECK_PORTS="uses ports"
RES_CHECK_PORTS="please, make sure that the ports are free.";
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE.";
RES_PROPOSAL="You can now configure your portal using the Control Panel";
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"

while [ "$1" != "" ]; do
	case $1 in

		-ls | --localscripts )
			if [ "$2" != "" ]; then
				LOCAL_SCRIPTS=$2
				shift
			fi
		;;

		-it | --installation_type )
			if [ "$2" != "" ]; then
				INSTALLATION_TYPE=$(echo "$2" | awk '{print toupper($0)}');
				shift
			fi
		;;

		-skiphc | --skiphardwarecheck )
			if [ "$2" != "" ]; then
				SKIP_HARDWARE_CHECK=$2
				shift
			fi
		;;

		-u | --update )
			if [ "$2" != "" ]; then
				UPDATE=$2
				shift
			fi
		;;

		-? | -h | --help )
			echo "  Usage $0 [PARAMETER] [[PARAMETER], ...]"
			echo "    Parameters:"
			echo "      -it, --installation_type          installation type (GROUPS|WORKSPACE|WORKSPACE_ENTERPRISE)"
			echo "      -u, --update                      use to update existing components (true|false)"
			echo "      -ls, --localscripts               use 'true' to run local scripts (true|false)"
			echo "      -skiphc, --skiphardwarecheck      use to skip hardware check (true|false)"
			echo "      -?, -h, --help                    this help"
			echo
			exit 0
		;;

	esac
	shift
done

if [ -z "${INSTALLATION_TYPE}" ]; then
   INSTALLATION_TYPE=${INSTALLATION_TYPE:-"WORKSPACE_ENTERPRISE"}
fi

if [ -z "${UPDATE}" ]; then
   UPDATE="false";
fi

if [ -z "${SKIP_HARDWARE_CHECK}" ]; then
   SKIP_HARDWARE_CHECK="false";
fi

# Switch to archived APT repos for EOL Debian 10
if grep -q buster /etc/os-release; then
    echo "deb http://archive.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian-security buster/updates main contrib non-free" >> /etc/apt/sources.list

    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -Ei \
        -e 's|http://deb\.debian\.org/debian/?|http://archive.debian.org/debian/|g' \
        -e 's|http://security\.debian\.org/debian-security/?|http://archive.debian.org/debian-security/|g' \
        -e 's|http://ftp\.uk\.debian\.org/debian/?|http://archive.debian.org/debian/|g' {} +
fi

apt-get update -y --allow-releaseinfo-change

if [ $(dpkg-query -W -f='${Status}' curl 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
  apt-get install -yq curl;
fi

export MYSQL_SERVER_HOST="127.0.0.1"
DOWNLOAD_URL_PREFIX="https://download.onlyoffice.com/install/install-Debian"

if [ "${LOCAL_SCRIPTS}" == "true" ]; then
	source install-Debian/bootstrap.sh
else
	source <(curl ${DOWNLOAD_URL_PREFIX}/bootstrap.sh)
fi

# add onlyoffice repo
mkdir -p -m 700 $HOME/.gnupg
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] http://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
chmod 644 /usr/share/keyrings/onlyoffice.gpg

declare -x LANG="en_US.UTF-8"
declare -x LANGUAGE="en_US:en"
declare -x LC_ALL="en_US.UTF-8"

if [ "${LOCAL_SCRIPTS}" == "true" ]; then
	source install-Debian/tools.sh
	source install-Debian/check-ports.sh
	source install-Debian/install-preq.sh
	source install-Debian/install-app.sh
else
	source <(curl ${DOWNLOAD_URL_PREFIX}/tools.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/check-ports.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-preq.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-app.sh)
fi
