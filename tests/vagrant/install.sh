#!/bin/bash

set -e 

while [ "$1" != "" ]; do
	case $1 in

		-ds | --download-scripts )
                        if [ "$2" != "" ]; then
                                DOWNLOAD_SCRIPTS=$2
                                shift
                        fi
                ;;

                -arg | --arguments )
                        if [ "$2" != "" ]; then
                                ARGUMENTS=$2
                                shift
                        fi
                ;;


	        -pi | --production-install )
			if [ "$2" != "" ]; then
				PRODUCTION_INSTALL=$2
				shift
			fi
		;;

		-li | --local-install )
                        if [ "$2" != "" ]; then
                                LOCAL_INSTALL=$2
                                shift
                        fi
                ;;

		-lu | --local-update )
                        if [ "$2" != "" ]; then
                                LOCAL_UPDATE=$2
                                shift
                        fi
                ;;

	        -tr | --test-repo )
			if [ "$2" != "" ]; then
				TEST_REPO_ENABLE=$2
				shift
		        fi
		;;


        esac
	shift
done

export TERM=xterm-256color^M

SERVICES_SYSTEMD=(
	"monoserve.service"
	"monoserveApiSystem.service"
	"onlyofficeFilesTrashCleaner.service" 
	"onlyofficeBackup.service" 
	"onlyofficeControlPanel.service" 
	"onlyofficeFeed.service" 
	"onlyofficeIndex.service"                          
        "onlyofficeJabber.service"                         
        "onlyofficeMailAggregator.service"                 
        "onlyofficeMailCleaner.service"                    
        "onlyofficeMailImap.service"                       
        "onlyofficeMailWatchdog.service"                  
        "onlyofficeNotify.service"                   
        "onlyofficeRadicale.service"                       
        "onlyofficeSocketIO.service"                       
        "onlyofficeSsoAuth.service"                        
        "onlyofficeStorageEncryption.service"              
        "onlyofficeStorageMigrate.service"                
        "onlyofficeTelegram.service"                       
        "onlyofficeThumb.service"                        
        "onlyofficeThumbnailBuilder.service"               
        "onlyofficeUrlShortener.service"                   
        "onlyofficeWebDav.service"
        "ds-converter.service"
        "ds-docservice.service"
        "ds-metrics.service")      

function common::get_colors() {
    COLOR_BLUE=$'\e[34m'
    COLOR_GREEN=$'\e[32m'
    COLOR_RED=$'\e[31m'
    COLOR_RESET=$'\e[0m'
    COLOR_YELLOW=$'\e[33m'
    export COLOR_BLUE
    export COLOR_GREEN
    export COLOR_RED
    export COLOR_RESET
    export COLOR_YELLOW
}

#############################################################################################
# Checking available resources for a virtual machine
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
#############################################################################################
function check_hw() {
        local FREE_RAM=$(free -h)
	local FREE_CPU=$(nproc)
	echo "${COLOR_RED} ${FREE_RAM} ${COLOR_RESET}"
        echo "${COLOR_RED} ${FREE_CPU} ${COLOR_RESET}"
}


#############################################################################################
# Prepare vagrant boxes like: set hostname/remove postfix for DEB distributions
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   ☑ PREPAVE_VM: **<prepare_message>**
#############################################################################################
function prepare_vm() {
  # Определение дистрибутива
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DIST_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    DIST_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
    DIST_VER_ID=$VERSION_ID
    DIST_CODENAME=$(echo "$VERSION" | awk '{print tolower($NF)}' | tr -d '()')
  fi

  echo "${COLOR_YELLOW}☑ PREPARE_VM: Detected OS: $DIST_ID, Codename: $DIST_CODENAME, Version: $DIST_VER_ID${COLOR_RESET}"

  ############ Debian/Ubuntu логика ############
  if [[ "$DIST_ID" == "debian" || "$DIST_ID" == "ubuntu" ]]; then
    if [[ "$DIST_CODENAME" == "bookworm" || "$DIST_CODENAME" == "jammy" ]]; then
      apt-get update -y
      apt-get install -y curl gnupg
    fi

    # Удаление postfix
    if systemctl is-active --quiet postfix; then
      systemctl stop postfix
      systemctl disable postfix
      apt-get remove -y postfix
      echo "${COLOR_GREEN}☑ PREPARE_VM: Postfix was removed${COLOR_RESET}"
    fi

    # Добавление тестового репо
    if [ "${TEST_REPO_ENABLE}" == 'true' ]; then
      mkdir -p -m 700 /etc/apt/sources.list.d
      mkdir -p -m 700 $HOME/.gnupg
      echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] http://static.teamlab.info.s3.amazonaws.com/repo/4testing/debian stable main" \
        | tee /etc/apt/sources.list.d/onlyoffice4testing.list
      curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
        | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
      chmod 644 /usr/share/keyrings/onlyoffice.gpg
    fi
  fi

  ############ RHEL/CentOS логика ############
  if [[ "$DIST_ID" == "rhel" || "$DIST_ID" == "centos" ]]; then
    local REV=${DIST_VER_ID%%.*}

    # Поддержка GPG ключей SHA1 на RHEL9+
    if [[ "$REV" == "9" ]]; then
      update-crypto-policies --set LEGACY
      echo "${COLOR_GREEN}☑ PREPARE_VM: SHA1 GPG support enabled (RHEL9+)${COLOR_RESET}"
    fi

    # CentOS fallback patch (только если действительно CentOS)
    if grep -qi centos /etc/redhat-release 2>/dev/null; then
      echo "${COLOR_YELLOW}☑ PREPARE_VM: CentOS detected, applying repo fallback patch${COLOR_RESET}"
      sed -i 's|^mirrorlist=|#&|; s|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' /etc/yum.repos.d/CentOS-* || true
    fi

    # Добавление onlyoffice test repo
    if [ "${TEST_REPO_ENABLE}" == 'true' ]; then

      # CentOS Stream репозитории для RHEL 8/9
      if [[ "$REV" == "8" ]]; then
        cat <<EOF | sudo tee /etc/yum.repos.d/centos-stream-8.repo
[centos8s-baseos]
name=CentOS Stream 8 - BaseOS
baseurl=http://composes.stream.centos.org/production/latest-CentOS-Stream/compose/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos8s-appstream]
name=CentOS Stream 8 - AppStream
baseurl=http://composes.stream.centos.org/production/latest-CentOS-Stream/compose/AppStream/x86_64/os/
enabled=1
gpgcheck=0
EOF
      elif [[ "$REV" == "9" ]]; then
        cat <<EOF | sudo tee /etc/yum.repos.d/centos-stream-9.repo
[centos9s-baseos]
name=CentOS Stream 9 - BaseOS
baseurl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos9s-appstream]
name=CentOS Stream 9 - AppStream
baseurl=http://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/
enabled=1
gpgcheck=0
EOF
      fi

      # Репозиторий ONLYOFFICE
      cat > /etc/yum.repos.d/onlyoffice4testing.repo <<EOF
[onlyoffice4testing]
name=onlyoffice4testing repo
baseurl=http://static.teamlab.info.s3.amazonaws.com/repo/4testing/centos/main/noarch/
gpgcheck=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
enabled=1
EOF

      yum install -y centos-release || true
    fi
  fi

  ############ Общие действия ############
  rm -rf /home/vagrant/*
  if [ -d /tmp/workspace ]; then
    mv /tmp/workspace/* /home/vagrant
  fi

  echo '127.0.0.1 host4test' | tee -a /etc/hosts
  echo "${COLOR_GREEN}☑ PREPARE_VM: Hostname and workspace set up${COLOR_RESET}"
}


#############################################################################################
# Install workspace and then healthcheck
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Script log
#############################################################################################
function install_workspace() {
	if [ "${DOWNLOAD_SCRIPTS}" == 'true' ]; then
      curl -fLO https://download.onlyoffice.com/install/workspace-install.sh
  else
    sed 's/set -e/set -xe/' -i *.sh
  fi

	printf "N\nY\nY" | bash workspace-install.sh ${ARGUMENTS}

	if [[ $? != 0 ]]; then
	    echo "Exit code non-zero. Exit with 1."
	    exit 1
	else
	    echo "Exit code 0. Continue..."
	fi
}

#############################################################################################
# Healthcheck function for systemd services
# Globals:
#   SERVICES_SYSTEMD
# Arguments:
#   None
# Outputs:
#   Message about service status 
#############################################################################################
function healthcheck_systemd_services() {
  for service in ${SERVICES_SYSTEMD[@]} 
  do 
    if systemctl is-active --quiet ${service}; then
      echo "${COLOR_GREEN}☑ OK: Service ${service} is running${COLOR_RESET}"
    else 
      echo "${COLOR_RED}⚠ FAILED: Service ${service} is not running${COLOR_RESET}"
      SYSTEMD_SVC_FAILED="true"
    fi
  done
}

#############################################################################################
# Set output if some services failed
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   ⚠ ⚠  ATTENTION: Some sevices is not running ⚠ ⚠ 
# Returns
# 0 if all services is start correctly, non-zero if some failed
#############################################################################################
function healthcheck_general_status() {
  if [ ! -z "${SYSTEMD_SVC_FAILED}" ]; then
    echo "${COLOR_YELLOW}⚠ ⚠  ATTENTION: Some sevices is not running ⚠ ⚠ ${COLOR_RESET}"
    exit 1
  fi
}

#############################################################################################
# Get logs for all services
# Globals:
#   $SERVICES_SYSTEMD
# Arguments:
#   None
# Outputs:
#   Logs for systemd services
# Returns:
#   none
# Commentaries:
# This function succeeds even if the file for cat was not found. For that use ${SKIP_EXIT} variable
#############################################################################################
function services_logs() {
  for service in ${SERVICES_SYSTEMD[@]}; do
    echo -----------------------------------------
    echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}"
    echo -----------------------------------------
    EXIT_CODE=0
    journalctl -u $service || true
  done
  
  local MAIN_LOGS_DIR="/var/log/onlyoffice"
  local DOCS_LOGS_DIR="${MAIN_LOGS_DIR}/documentserver"
  local DOCSERVICE_LOGS_DIR="${DOCS_LOGS_DIR}/docservice"
  local CONVERTER_LOGS_DIR="${DOCS_LOGS_DIR}/converter"
  local METRICS_LOGS_DIR="${DOCS_LOGS_DIR}/metrics"
       
  ARRAY_MAIN_SERVICES_LOGS=($(ls ${MAIN_LOGS_DIR} | grep log | sed 's/web.sql.log//;s/web.api.log//;s/nginx.*//' ))
  ARRAY_DOCSERVICE_LOGS=($(ls ${DOCSERVICE_LOGS_DIR}))
  ARRAY_CONVERTER_LOGS=($(ls ${CONVERTER_LOGS_DIR}))
  ARRAY_METRICS_LOGS=($(ls ${METRICS_LOGS_DIR}))
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for main services ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_MAIN_SERVICES_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file: ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${MAIN_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for Docservice ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_DOCSERVICE_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file: ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${DOCSERVICE_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for Converter ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_CONVERTER_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${CONVERTER_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Start logs for Metrics ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_METRICS_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${METRICS_LOGS_DIR}/${file} || true
  done
}

function healthcheck_docker_installation() {
	exit 0
}

main() {
  common::get_colors
  prepare_vm
  check_hw
  install_workspace
  sleep 120
  services_logs
  healthcheck_systemd_services
  healthcheck_general_status
}

main
