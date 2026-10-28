#!/bin/bash

# Project NOMAD Raspberry Pi 5 Edition
# Manual application updates are disabled until a safe
# backup, upgrade, and rollback procedure is implemented.

echo
echo "Project NOMAD Raspberry Pi 5 Edition"
echo "===================================="
echo
echo "Automatic application upgrades are not supported in this release."
echo "This safeguard protects customized source files and containers."
echo
echo "No changes have been made to your installation."
echo
exit 1


# Project N.O.M.A.D. Update Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Update Script
# Version               | 1.0.1
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m' # Same as GRAY_R for terminals with white background.
GRAY_R='\033[39m'
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.
NOMAD_DIR="/opt/project-nomad"
INSTALL_METADATA_FILE="${NOMAD_DIR}/install-metadata.env"
PREPARE_RTLSDR_SCRIPT_PATH="${NOMAD_DIR}/prepare_rtlsdr.sh"

github_repo_owner=''
github_repo_name=''
github_repo_branch=''
source_repo_dir=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_has_sudo() {
  if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
  else
    echo "User does not have sudo permissions"
    header_red
    echo -e "${RED}#${RESET} This script requires sudo permissions to run. Please run the script with sudo.\\n"
    echo -e "${RED}#${RESET} For example: sudo bash $(basename "$0")"
    exit 1
  fi
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_is_debian_based() {
  if [[ ! -f /etc/debian_version ]]; then
    header_red
    echo -e "${RED}#${RESET} This script is designed to run on Debian-based systems only.\\n"
    echo -e "${RED}#${RESET} Please run this script on a Debian-based system and try again."
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running on a Debian-based system.\\n"
}

load_install_metadata() {
  if [[ -f "${INSTALL_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${INSTALL_METADATA_FILE}"
    github_repo_owner="${GITHUB_REPO_OWNER:-}"
    github_repo_name="${GITHUB_REPO_NAME:-}"
    github_repo_branch="${GITHUB_REPO_BRANCH:-}"
    source_repo_dir="${SOURCE_REPO_DIR:-}"
  fi
}

get_update_confirmation(){
  read -p "This script will update Project N.O.M.A.D. and its dependencies on your machine. No data loss is expected, but you should always back up your data before proceeding. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the update."
      ;;
    n|N )
      echo -e "${RED}#${RESET} User chose not to continue with the update."
      exit 0
      ;;
    * )
      echo "Invalid Response"
      echo "User chose not to continue with the update."
      exit 0
      ;;
  esac
}

ensure_docker_installed_and_running() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed. This is unexpected, as Project N.O.M.A.D. requires Docker to run. Did you mean to use the install script instead of the update script?"
    exit 1
  fi

  if ! systemctl is-active --quiet docker; then
    echo -e "${RED}#${RESET} Docker is not running. Attempting to start Docker..."
    sudo systemctl start docker
    if ! systemctl is-active --quiet docker; then
      echo -e "${RED}#${RESET} Failed to start Docker. Please start Docker and try again."
      exit 1
    fi
  fi
}

ensure_docker_compose_file_exists() {
  if [ ! -f "${NOMAD_DIR}/compose.yml" ]; then
    echo -e "${RED}#${RESET} compose.yml file not found. Please ensure it exists at ${NOMAD_DIR}/compose.yml."
    exit 1
  fi
}

refresh_local_source_checkout() {
  if [[ -z "${source_repo_dir}" || -z "${github_repo_owner}" || -z "${github_repo_name}" || -z "${github_repo_branch}" ]]; then
    return 0
  fi

  local source_root="${NOMAD_DIR}/source"
  local archive_url="https://codeload.github.com/${github_repo_owner}/${github_repo_name}/tar.gz/refs/heads/${github_repo_branch}"

  echo -e "${YELLOW}#${RESET} Refreshing local source checkout from GitHub for arm64 rebuilds..."
  rm -rf "${source_root:?}/"*
  mkdir -p "${source_root}"
  if ! curl -fsSL "${archive_url}" | tar -xzf - -C "${source_root}"; then
    echo -e "${RED}#${RESET} Failed to refresh source checkout from ${archive_url}."
    exit 1
  fi

  source_repo_dir="$(find "${source_root}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "${source_repo_dir}" || ! -d "${source_repo_dir}" ]]; then
    echo -e "${RED}#${RESET} Refreshed source checkout is missing or invalid."
    exit 1
  fi
}

refresh_helper_scripts() {
  if [[ -n "${source_repo_dir}" && -f "${source_repo_dir}/install/prepare_rtlsdr.sh" ]]; then
    cp "${source_repo_dir}/install/prepare_rtlsdr.sh" "${PREPARE_RTLSDR_SCRIPT_PATH}"
    chmod +x "${PREPARE_RTLSDR_SCRIPT_PATH}"
  fi
}

force_recreate() {
  local compose_file="${NOMAD_DIR}/compose.yml"

  if grep -qE '^\s+build:' "${compose_file}"; then
    refresh_local_source_checkout
    echo -e "${YELLOW}#${RESET} Pulling registry-backed dependencies and rebuilding local images..."
    if ! docker compose -p project-nomad -f "${compose_file}" pull --ignore-buildable; then
      echo -e "${RED}#${RESET} Failed to pull dependency images. Please check your network connection and registry access."
      exit 1
    fi

    echo -e "${YELLOW}#${RESET} Rebuilding and recreating Project N.O.M.A.D containers..."
    if ! docker compose -p project-nomad -f "${compose_file}" up -d --build --force-recreate; then
      echo -e "${RED}#${RESET} Failed to rebuild/recreate containers. Please check Docker logs for more details."
      exit 1
    fi
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Pulling the latest Docker images..."
  if ! docker compose -p project-nomad -f "${compose_file}" pull; then
    echo -e "${RED}#${RESET} Failed to pull the latest Docker images. Please check your network connection and the Docker registry status, then try again."
    exit 1
  fi
  
  echo -e "${YELLOW}#${RESET} Forcing recreation of containers..."
  if ! docker compose -p project-nomad -f "${compose_file}" up -d --force-recreate; then
    echo -e "${RED}#${RESET} Failed to recreate containers. Please check the Docker logs for more details."
    exit 1
  fi
}

get_local_ip() {
  local_ip_address=$(hostname -I | awk '{print $1}')
  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    # Don't exit if we can't determine the local IP address, it's not critical for the installation
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\n"
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D's Command Center should automatically start whenever your device reboots. However, if you need to start it manually, you can always do so by running: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_is_debian_based
check_is_bash
check_has_sudo
load_install_metadata

# Main update
get_update_confirmation
ensure_docker_installed_and_running
ensure_docker_compose_file_exists
force_recreate
refresh_helper_scripts
get_local_ip
success_message
