#!/bin/bash

set -E -o pipefail

# Project N.O.M.A.D. Installation Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Installation Script
# Version               | 1.0.0
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

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

WHIPTAIL_TITLE="Project N.O.M.A.D Installation"
NOMAD_DIR="/opt/project-nomad"
NOMAD_EXTERNAL_MOUNT_DEFAULT="/mnt/nomad-data"
NOMAD_EXTERNAL_LABEL_DEFAULT="nomad-data"
GITHUB_REPO_OWNER="${GITHUB_REPO_OWNER:-broy55}"
GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-project-nomad-rpi5}"
GITHUB_REPO_BRANCH="${GITHUB_REPO_BRANCH:-main}"
GITHUB_RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/refs/heads/${GITHUB_REPO_BRANCH}"
GITHUB_ARCHIVE_URL="https://codeload.github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/tar.gz/refs/heads/${GITHUB_REPO_BRANCH}"
MANAGEMENT_COMPOSE_FILE_URL="${GITHUB_RAW_BASE_URL}/install/management_compose.yaml"
ENTRYPOINT_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/entrypoint.sh"
SIDECAR_UPDATER_DOCKERFILE_URL="${GITHUB_RAW_BASE_URL}/install/sidecar-updater/Dockerfile"
SIDECAR_UPDATER_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/sidecar-updater/update-watcher.sh"
START_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/start_nomad.sh"
STOP_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/stop_nomad.sh"
UPDATE_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/update_nomad.sh"
PREPARE_RTLSDR_SCRIPT_URL="${GITHUB_RAW_BASE_URL}/install/prepare_rtlsdr.sh"
WAIT_FOR_IT_SCRIPT_URL="https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh"
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-580.95.05}"
NVIDIA_DRIVER_RUNFILE_URL="${NVIDIA_DRIVER_RUNFILE_URL:-https://download.nvidia.com/XFree86/Linux-aarch64/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-aarch64-${NVIDIA_DRIVER_VERSION}.run}"
NVIDIA_CUDA_VERSION="${NVIDIA_CUDA_VERSION:-13.0.2}"
NVIDIA_CUDA_RUNFILE_URL="${NVIDIA_CUDA_RUNFILE_URL:-https://developer.download.nvidia.com/compute/cuda/${NVIDIA_CUDA_VERSION}/local_installers/cuda_${NVIDIA_CUDA_VERSION}_${NVIDIA_DRIVER_VERSION}_linux_sbsa.run}"
NVIDIA_OPEN_MODULES_REPO_URL="${NVIDIA_OPEN_MODULES_REPO_URL:-https://github.com/mariobalanica/open-gpu-kernel-modules.git}"
NVIDIA_OPEN_MODULES_BRANCH="${NVIDIA_OPEN_MODULES_BRANCH:-non-coherent-arm-fixes}"
NVIDIA_OPEN_MODULES_COMMIT="${NVIDIA_OPEN_MODULES_COMMIT:-10072734b2f88f3580cdb036778ec27d2b4f2fb9}"
DEFAULT_NVIDIA_RUNTIME_CACHE_DIR="${NVIDIA_RUNTIME_CACHE_DIR:-/var/cache/project-nomad/nvidia}"
NVIDIA_RUNTIME_CACHE_DIR="${DEFAULT_NVIDIA_RUNTIME_CACHE_DIR}"
NVIDIA_STATE_DIR="${NVIDIA_STATE_DIR:-/var/lib/project-nomad-runtime}"
NVIDIA_APT_PIN_FILE="${NVIDIA_APT_PIN_FILE:-/etc/apt/preferences.d/nvidia-block}"
CUDA_ENV_FILE="${CUDA_ENV_FILE:-/etc/profile.d/cuda.sh}"
INSTALL_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INSTALL_LOG_DIR="${HOME}/project-nomad-install-logs"
INSTALL_LOG_FILE="${INSTALL_LOG_DIR}/install-${INSTALL_TIMESTAMP}.log"
warnings_detected=0
preflight_failures=0
boot_order_update_applied='false'

script_option_debug='true'
accepted_terms='false'
local_ip_address=''
target_architecture="$(dpkg --print-architecture 2>/dev/null || uname -m)"
target_platform='generic'
preinstall_only='false'
preflight_only='false'
storage_only='false'
skip_storage_preflight='false'
assume_yes='false'
format_external_disk='false'
force_format_existing_nomad_data='false'
reset_existing_mysql='false'
external_device=''
external_mount="${NOMAD_EXTERNAL_MOUNT_DEFAULT}"
external_label="${NOMAD_EXTERNAL_LABEL_DEFAULT}"
use_external_storage='auto'
swap_device=''
swap_mount='/mnt/usb-swap'
swap_label='nomad-swap'
swap_file_path=''
swap_size_gib="${NOMAD_SWAP_SIZE_GIB:-16}"
use_external_swap='auto'
enable_ai_runtime='auto'
ai_runtime_requested='auto'
nomad_data_root=''
source_repo_dir=''
install_secrets_file=''
app_key=''
db_root_password=''
db_user_password=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

setup_logging() {
  if [[ -t 0 ]]; then
    exec 3<&0
  fi
  if [[ -t 1 ]]; then
    exec 4>&1
  fi
  if [[ -t 2 ]]; then
    exec 5>&2
  fi

  mkdir -p "${INSTALL_LOG_DIR}"
  touch "${INSTALL_LOG_FILE}"
  exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1

  echo "================================================================="
  echo "Project N.O.M.A.D installer log"
  echo "Started: $(date --iso-8601=seconds)"
  echo "Log file: ${INSTALL_LOG_FILE}"
  echo "Repository source: ${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}@${GITHUB_REPO_BRANCH}"
  echo "Host: $(hostname)"
  echo "User: $(whoami)"
  echo "================================================================="
}

record_warning() {
  warnings_detected=$((warnings_detected + 1))
  echo -e "${YELLOW}#${RESET} Warning: $1"
}

record_preflight_failure() {
  preflight_failures=$((preflight_failures + 1))
  echo -e "${RED}#${RESET} Preflight failure: $1"
}

log_error_context() {
  local exit_code="$1"
  local line_number="$2"
  local command_text="$3"

  echo -e "${RED}#${RESET} Installer command failed with exit code ${WHITE_R}${exit_code}${RESET} at line ${WHITE_R}${line_number}${RESET}."
  echo -e "${RED}#${RESET} Last command: ${WHITE_R}${command_text}${RESET}"
  echo -e "${YELLOW}#${RESET} Review the installer log at ${WHITE_R}${INSTALL_LOG_FILE}${RESET} for the surrounding output."
  echo -e "${YELLOW}#${RESET} Common causes: missing network access, package repository issues, insufficient sudo rights, or a stale/custom runtime configuration."
}

print_log_location() {
  echo -e "${YELLOW}#${RESET} Installer log: ${WHITE_R}${INSTALL_LOG_FILE}${RESET}\\n"
}

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

ensure_dependencies_installed() {
  local missing_deps=()

  # Check for curl
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if ! command -v whiptail &> /dev/null; then
    missing_deps+=("whiptail")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_deps[*]}...\\n"
    sudo apt-get update
    sudo apt-get install -y "${missing_deps[@]}"

    # Verify installation
    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $dep. Please install it manually and try again."
        exit 1
      fi
    done
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

installer_tui_available() {
  [[ "${assume_yes}" != 'true' ]] \
    && [[ -t 3 && -t 4 ]] \
    && [[ -n "${TERM:-}" ]] \
    && [[ "${TERM:-dumb}" != 'dumb' ]] \
    && command -v whiptail >/dev/null 2>&1
}

nomad_backtitle() {
  echo "Project N.O.M.A.D. | Offline-first install wizard"
}

show_nomad_msgbox() {
  local title="$1"
  local message="$2"

  if installer_tui_available; then
    whiptail --backtitle "$(nomad_backtitle)" --title "${title}" --msgbox "${message}" 18 78 <&3 >&4 2>&5
    return $?
  fi

  echo
  header
  echo -e "${GREEN}${title}${RESET}"
  echo
  printf "%b\n" "${message}"
  echo
}

show_nomad_yesno() {
  local title="$1"
  local message="$2"
  local yes_label="${3:-Yes}"
  local no_label="${4:-No}"

  if installer_tui_available; then
    whiptail \
      --backtitle "$(nomad_backtitle)" \
      --title "${title}" \
      --yes-button "${yes_label}" \
      --no-button "${no_label}" \
      --yesno "${message}" 18 78 <&3 >&4 2>&5
    return $?
  fi

  echo
  header
  echo -e "${GREEN}${title}${RESET}"
  echo
  printf "%b\n\n" "${message}"
  echo "  1) ${yes_label}"
  echo "  2) ${no_label}"
  echo
  local choice=''
  read -r -p "Choose [1/2]: " choice
  case "${choice}" in
    1|'')
      return 0
      ;;
    2)
      return 1
      ;;
    y|Y|yes|YES)
      return 0
      ;;
    n|N|no|NO)
      return 1
      ;;
    [Cc][Oo][Nn][Tt][Ii][Nn][Uu][Ee])
      return 0
      ;;
    [Ee][Xx][Ii][Tt]|[Cc][Aa][Nn][Cc][Ee][Ll]|[Dd][Ee][Cc][Ll][Ii][Nn][Ee])
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

show_nomad_radiolist() {
  local title="$1"
  local message="$2"
  shift 2

  if installer_tui_available; then
    whiptail \
      --backtitle "$(nomad_backtitle)" \
      --title "${title}" \
      --radiolist "${message}" 22 100 12 "$@" 6>&1 1>&4 2>&6 <&3
    return $?
  fi

  echo
  header
  echo -e "${GREEN}${title}${RESET}"
  echo
  printf "%b\n\n" "${message}"
  local tags=()
  local index=1
  while [[ $# -gt 0 ]]; do
    printf "  %s) %s\n" "${index}" "$2"
    tags+=("$1")
    shift 3
    index=$((index + 1))
  done

  local selection=''
  read -r -p "Enter selection [1]: " selection
  selection="${selection:-1}"
  if [[ "${selection}" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#tags[@]} )); then
    echo "${tags[$((selection - 1))]}"
    return 0
  fi

  return 1
}

detect_target_platform() {
  if [[ -f /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
    target_platform='raspberry-pi'
  elif grep -qi "raspberry pi" /sys/firmware/devicetree/base/model 2>/dev/null; then
    target_platform='raspberry-pi'
  else
    target_platform='generic'
  fi

  echo -e "${GREEN}#${RESET} Detected platform: ${WHITE_R}${target_platform}${RESET} (${WHITE_R}${target_architecture}${RESET})\\n"
}

is_raspberry_pi_5() {
  [[ "${target_platform}" == 'raspberry-pi' ]] && grep -qi "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null
}

get_pi5_kernel_override() {
  if [[ ! -f /boot/firmware/config.txt ]]; then
    return 0
  fi

  awk '/\[pi5\]/{f=1;next} /^\[/{f=0} f && /^kernel=/{print $0}' /boot/firmware/config.txt | tail -n1
}

stage_pi5_4k_kernel_override() {
  local config_path='/boot/firmware/config.txt'
  local temp_file=''
  temp_file="$(mktemp)"

  sudo cp "${config_path}" "${temp_file}"

  if grep -q '^\[pi5\]' "${temp_file}"; then
    if awk '/\[pi5\]/{f=1;next} /^\[/{f=0} f && /^kernel=kernel8\.img$/{found=1} END{exit(found?0:1)}' "${temp_file}"; then
      rm -f "${temp_file}"
      return 0
    fi

    if awk '/\[pi5\]/{f=1;next} /^\[/{f=0} f && /^kernel=/{found=1} END{exit(found?0:1)}' "${temp_file}"; then
      sudo sed -i '/^\[pi5\]/,/^\[/{s/^kernel=.*/kernel=kernel8.img/}' "${temp_file}"
    else
      sudo sed -i '/^\[pi5\]/a kernel=kernel8.img' "${temp_file}"
    fi
  else
    cat <<'EOF' | sudo tee -a "${temp_file}" >/dev/null

[pi5]
kernel=kernel8.img
EOF
  fi

  sudo cp "${temp_file}" "${config_path}"
  rm -f "${temp_file}"
}

has_nvidia_pci_device() {
  command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -iq 'nvidia'
}

ensure_project_runtime_state_dirs() {
  sudo mkdir -p "${NVIDIA_RUNTIME_CACHE_DIR}" "${NVIDIA_STATE_DIR}"
}

ensure_custom_nvidia_apt_pin() {
  if [[ "${target_platform}" != 'raspberry-pi' ]] || ! has_nvidia_pci_device; then
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Ensuring custom NVIDIA APT pin protects the Pi host driver stack...\\n"
  cat <<'EOF' | sudo tee "${NVIDIA_APT_PIN_FILE}" >/dev/null
Package: nvidia-*
Pin: release *
Pin-Priority: -1

Package: libnvidia-*
Pin: release *
Pin-Priority: -1

Package: libcuda1
Pin: release *
Pin-Priority: -1

Package: nvidia-smi
Pin: release *
Pin-Priority: -1

Package: firmware-nvidia-gsp
Pin: release *
Pin-Priority: -1
EOF
}

ensure_cuda_environment_file() {
  echo -e "${YELLOW}#${RESET} Ensuring CUDA environment variables are exported globally...\\n"
  cat <<'EOF' | sudo tee "${CUDA_ENV_FILE}" >/dev/null
export PATH="${PATH}:/usr/local/cuda-13.0/bin"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/cuda-13.0/lib64"
EOF
}

cuda_nvcc_path() {
  if command -v nvcc >/dev/null 2>&1; then
    command -v nvcc
    return 0
  fi

  if [[ -x "/usr/local/cuda-13.0/bin/nvcc" ]]; then
    echo "/usr/local/cuda-13.0/bin/nvcc"
    return 0
  fi

  return 1
}

cuda_toolkit_looks_ready() {
  local nvcc_path=''
  nvcc_path="$(cuda_nvcc_path)" || return 1
  "${nvcc_path}" --version 2>/dev/null | grep -q "release 13.0"
}

download_with_resume() {
  local url="$1"
  local destination_path="$2"
  local description="$3"

  if [[ -f "${destination_path}" && -s "${destination_path}" ]]; then
    echo -e "${GREEN}#${RESET} Reusing existing ${description} download at ${WHITE_R}${destination_path}${RESET}.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Downloading ${description}...\\n"
  if ! sudo curl -fL --retry 3 --continue-at - "${url}" -o "${destination_path}"; then
    echo -e "${RED}#${RESET} Failed to download ${description} from ${WHITE_R}${url}${RESET}."
    exit 1
  fi
}

ensure_raspberry_pi_nvidia_build_dependencies() {
  if [[ "${target_platform}" != 'raspberry-pi' ]] || ! has_nvidia_pci_device; then
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Installing Raspberry Pi NVIDIA build dependencies...\\n"
  sudo apt-get update
  sudo apt-get install -y build-essential dkms "linux-headers-$(uname -r)" git
}

install_raspberry_pi_nvidia_driver_stack() {
  if [[ "${target_platform}" != 'raspberry-pi' ]] || ! has_nvidia_pci_device; then
    return 0
  fi

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | grep -q "${NVIDIA_DRIVER_VERSION}"; then
    echo -e "${GREEN}#${RESET} NVIDIA host driver ${WHITE_R}${NVIDIA_DRIVER_VERSION}${RESET} is already active.\\n"
    return 0
  fi

  ensure_project_runtime_state_dirs
  ensure_custom_nvidia_apt_pin
  ensure_raspberry_pi_nvidia_build_dependencies
  sudo apt-get install -y pkg-config libvulkan1 >/dev/null 2>&1 || true

  local driver_runfile="${NVIDIA_RUNTIME_CACHE_DIR}/NVIDIA-Linux-aarch64-${NVIDIA_DRIVER_VERSION}.run"
  local module_clone_dir="${NVIDIA_RUNTIME_CACHE_DIR}/open-gpu-kernel-modules"
  local driver_marker="${NVIDIA_STATE_DIR}/nvidia-driver-${NVIDIA_DRIVER_VERSION}.installed"

  download_with_resume "${NVIDIA_DRIVER_RUNFILE_URL}" "${driver_runfile}" "NVIDIA aarch64 driver ${NVIDIA_DRIVER_VERSION}"
  sudo chmod +x "${driver_runfile}"

  if [[ ! -f "${driver_marker}" ]]; then
    echo -e "${YELLOW}#${RESET} Installing NVIDIA userland from runfile ${WHITE_R}${NVIDIA_DRIVER_VERSION}${RESET}...\\n"
    if ! sudo sh "${driver_runfile}" --silent --no-kernel-modules --install-libglvnd; then
      echo -e "${RED}#${RESET} NVIDIA userland install failed."
      exit 1
    fi
    sudo touch "${driver_marker}"
  else
    echo -e "${GREEN}#${RESET} NVIDIA userland marker present for ${WHITE_R}${NVIDIA_DRIVER_VERSION}${RESET}; skipping rerun.\\n"
  fi

  echo -e "${YELLOW}#${RESET} Preparing patched NVIDIA open kernel modules checkout...\\n"
  if [[ -d "${module_clone_dir}/.git" ]]; then
    sudo git -C "${module_clone_dir}" fetch --tags origin "${NVIDIA_OPEN_MODULES_BRANCH}"
  else
    sudo rm -rf "${module_clone_dir}"
    sudo git clone --branch "${NVIDIA_OPEN_MODULES_BRANCH}" "${NVIDIA_OPEN_MODULES_REPO_URL}" "${module_clone_dir}"
  fi
  sudo git -C "${module_clone_dir}" checkout "${NVIDIA_OPEN_MODULES_COMMIT}"

  local current_module_version=''
  current_module_version="$(modinfo -F version nvidia 2>/dev/null || true)"
  if [[ "${current_module_version}" != "${NVIDIA_DRIVER_VERSION}" ]]; then
    echo -e "${YELLOW}#${RESET} Building patched NVIDIA kernel modules...\\n"
    sudo make -C "${module_clone_dir}" modules -j"$(nproc)"
    echo -e "${YELLOW}#${RESET} Installing patched NVIDIA kernel modules...\\n"
    sudo make -C "${module_clone_dir}" modules_install -j"$(nproc)"
    sudo depmod -a

    echo -e "${YELLOW}#${RESET} Attempting to load NVIDIA kernel modules immediately...\\n"
    sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    sudo modprobe nvidia || true
    sudo modprobe nvidia_uvm || true
  else
    echo -e "${GREEN}#${RESET} NVIDIA kernel modules already report version ${WHITE_R}${current_module_version}${RESET}.\\n"
  fi

  if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} NVIDIA driver stack is installed but not yet active in the current boot."
    echo -e "${YELLOW}#${RESET} Reboot the Pi, then rerun the installer so GPU validation can continue.\\n"
    exit 0
  fi

  echo -e "${GREEN}#${RESET} NVIDIA host driver stack is active.\\n"
}

install_raspberry_pi_cuda_toolkit() {
  if [[ "${target_platform}" != 'raspberry-pi' ]] || ! has_nvidia_pci_device; then
    return 0
  fi

  if cuda_toolkit_looks_ready; then
    echo -e "${GREEN}#${RESET} CUDA toolkit ${WHITE_R}${NVIDIA_CUDA_VERSION}${RESET} is already installed.\\n"
    ensure_cuda_environment_file
    return 0
  fi

  ensure_project_runtime_state_dirs
  local cuda_runfile="${NVIDIA_RUNTIME_CACHE_DIR}/cuda_${NVIDIA_CUDA_VERSION}_${NVIDIA_DRIVER_VERSION}_linux_sbsa.run"
  local cuda_tmpdir="${NVIDIA_RUNTIME_CACHE_DIR}/tmp"

  download_with_resume "${NVIDIA_CUDA_RUNFILE_URL}" "${cuda_runfile}" "CUDA toolkit ${NVIDIA_CUDA_VERSION} SBSA runfile"
  sudo chmod +x "${cuda_runfile}"
  sudo mkdir -p "${cuda_tmpdir}"

  echo -e "${YELLOW}#${RESET} Installing CUDA toolkit ${WHITE_R}${NVIDIA_CUDA_VERSION}${RESET} without replacing the custom NVIDIA driver...\\n"
  if ! sudo env TMPDIR="${cuda_tmpdir}" sh "${cuda_runfile}" --silent --toolkit --override; then
    echo -e "${RED}#${RESET} CUDA toolkit install failed."
    exit 1
  fi

  ensure_cuda_environment_file

  if ! cuda_nvcc_path >/dev/null 2>&1; then
    export PATH="${PATH}:/usr/local/cuda-13.0/bin"
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/cuda-13.0/lib64"
  fi

  if ! cuda_toolkit_looks_ready; then
    echo -e "${RED}#${RESET} CUDA toolkit install did not expose a usable ${WHITE_R}nvcc${RESET}."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} CUDA toolkit ${WHITE_R}${NVIDIA_CUDA_VERSION}${RESET} installed successfully.\\n"
}

ensure_raspberry_pi_4k_kernel_prerequisites() {
  if ! is_raspberry_pi_5; then
    return 0
  fi

  local page_size
  page_size="$(getconf PAGESIZE 2>/dev/null || true)"
  local kernel_override=''
  kernel_override="$(get_pi5_kernel_override)"

  if [[ "${page_size}" == "4096" ]]; then
    echo -e "${GREEN}#${RESET} Raspberry Pi 5 is already running with 4K pages.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Raspberry Pi 5 detected with PAGE_SIZE=${WHITE_R}${page_size}${RESET}."
  echo -e "${YELLOW}#${RESET} Current Project N.O.M.A.D arm64 AI path requires the 4K kernel on Pi 5."
  echo -e "${YELLOW}#${RESET} This avoids the current Qdrant page-size crash on 16K-page kernels and is also required for the known-good NVIDIA eGPU path."

  if [[ "${kernel_override}" == "kernel=kernel8.img" ]]; then
    echo -e "${YELLOW}#${RESET} The boot config already stages ${WHITE_R}kernel=kernel8.img${RESET} under [pi5], but the system has not rebooted into it yet."
    echo -e "${YELLOW}#${RESET} Reboot the Pi, then rerun the installer.\\n"
    exit 0
  fi

  if ! confirm_action "Stage the Pi 5 4K kernel override now and stop so you can reboot before continuing?"; then
    echo -e "${RED}#${RESET} Cannot continue safely on the current 16K-page Pi 5 kernel."
    echo -e "${RED}#${RESET} Re-run the installer after setting ${WHITE_R}[pi5] kernel=kernel8.img${RESET} and rebooting."
    exit 1
  fi

  stage_pi5_4k_kernel_override
  echo -e "${GREEN}#${RESET} Staged ${WHITE_R}kernel=kernel8.img${RESET} under [pi5] in /boot/firmware/config.txt."
  echo -e "${YELLOW}#${RESET} Reboot the Pi now, then rerun the installer so the 4K kernel is active.\\n"
  exit 0
}

nvidia_cuda_stack_looks_ready() {
  command -v nvidia-smi >/dev/null 2>&1 \
    && nvidia-smi >/dev/null 2>&1 \
    && cuda_toolkit_looks_ready
}

nvidia_cuda_host_stack_passes_quick_test() {
  nvidia_cuda_stack_looks_ready \
    && command -v nvidia-ctk >/dev/null 2>&1
}

nvidia_cuda_stack_passes_quick_test() {
  if ! nvidia_cuda_host_stack_passes_quick_test; then
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} Docker is not installed yet. Deferring the container GPU smoke test until after Docker setup."
    return 0
  fi

  if ! systemctl is-active --quiet docker; then
    echo -e "${YELLOW}#${RESET} Docker is not active yet. Deferring the container GPU smoke test until after Docker setup."
    return 0
  fi

  if ! docker_runtime_is_configured; then
    echo -e "${YELLOW}#${RESET} Docker is present but the NVIDIA runtime is not configured yet. Deferring the container GPU smoke test until after runtime setup."
    return 0
  fi

  sudo docker run --rm --runtime=nvidia --gpus all \
    nvidia/cuda:12.4.1-base-ubuntu22.04 \
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader >/dev/null 2>&1
}

prompt_ai_runtime_selection() {
  if [[ "${target_platform}" != 'raspberry-pi' ]]; then
    return 0
  fi

  if [[ "${enable_ai_runtime}" != 'auto' ]]; then
    if [[ "${enable_ai_runtime}" == 'true' ]]; then
      ai_runtime_requested='true'
    elif [[ "${enable_ai_runtime}" == 'false' ]]; then
      ai_runtime_requested='false'
    fi
    return 0
  fi

  if show_nomad_yesno \
    "AI Assistant Setup" \
    "Project N.O.M.A.D. can install the AI Assistant on this Raspberry Pi.\n\nOn a Pi without GPU acceleration, inference is limited to smaller Pi-appropriate models and will be slower than an eGPU-backed setup.\n\nContinue with AI Assistant installation?" \
    "Install AI Assistant" \
    "Skip AI Assistant"; then
    ai_runtime_requested='true'
  else
    enable_ai_runtime='false'
    ai_runtime_requested='false'
    return 0
  fi

  if ! has_nvidia_pci_device; then
    if show_nomad_yesno \
      "CPU-only AI Assistant" \
      "No NVIDIA GPU was detected on this Raspberry Pi.\n\nProject N.O.M.A.D. can still install the AI Assistant in CPU-only mode, but you will be limited to smaller Pi-specific models and slower local inference.\n\nInstall the AI Assistant anyway?" \
      "Install CPU-only AI" \
      "Cancel AI Assistant"; then
      enable_ai_runtime='false'
      return 0
    fi

    enable_ai_runtime='false'
    ai_runtime_requested='false'
    return 0
  fi

  if show_nomad_yesno \
    "GPU Acceleration Setup" \
    "An NVIDIA GPU was detected on this Raspberry Pi.\n\nProject N.O.M.A.D. can install the optional CUDA/NVIDIA toolstack for GPU-accelerated Ollama inference.\n\nChoose GPU acceleration if you want faster local inference. You can skip it and still keep the AI Assistant in CPU-only mode." \
    "Enable GPU Acceleration" \
    "Use CPU-only AI"; then
    enable_ai_runtime='true'
  else
    enable_ai_runtime='false'
  fi
}

ensure_raspberry_pi_nvidia_prerequisites() {
  if [[ "${target_platform}" != 'raspberry-pi' ]]; then
    return 0
  fi

  prompt_ai_runtime_selection

  # Never modify the Pi kernel or install NVIDIA drivers
  # when no NVIDIA PCI device is present.
  if ! has_nvidia_pci_device; then
    if [[ "${enable_ai_runtime}" == 'true' ]]; then
      echo -e "${YELLOW}#${RESET} No NVIDIA GPU detected."
      echo -e "${YELLOW}#${RESET} Using CPU-only AI mode."
    fi

    enable_ai_runtime='false'
    return 0
  fi

  if [[ "${enable_ai_runtime}" == 'false' ]]; then
    echo -e "${YELLOW}#${RESET} Skipping optional NVIDIA/CUDA runtime setup for this install.\\n"
    return 0
  fi

  if has_nvidia_pci_device && nvidia_cuda_stack_looks_ready; then
    echo -e "${YELLOW}#${RESET} NVIDIA/CUDA toolkit files were detected. Running a quick sanity check before deciding whether a reinstall is needed...\\n"

    if nvidia_cuda_stack_passes_quick_test; then
      if show_nomad_yesno \
        "AI Runtime Already Working" \
        "A quick sanity check confirmed that the existing NVIDIA/CUDA runtime is working on this Pi.\n\nReusing it will save time. Only choose reinstall if you specifically want to refresh the host GPU stack." \
        "Reuse Existing" \
        "Force Reinstall"; then
        echo -e "${GREEN}#${RESET} Reusing the existing NVIDIA/CUDA host runtime."
        return 0
      fi
    else
      echo -e "${YELLOW}#${RESET} NVIDIA/CUDA components were found, but the quick sanity check did not pass."
      echo -e "${YELLOW}#${RESET} Project N.O.M.A.D will continue with a reinstall of the AI runtime stack.\\n"
    fi
  fi

  ensure_raspberry_pi_4k_kernel_prerequisites
  ensure_project_runtime_state_dirs
  ensure_custom_nvidia_apt_pin

  local kernel_override=''
  kernel_override="$(get_pi5_kernel_override)"

  if command -v nvidia-smi >/dev/null 2>&1 && [[ "$kernel_override" != "kernel=kernel8.img" ]]; then
    echo -e "${YELLOW}#${RESET} Warning: NVIDIA is present, but /boot/firmware/config.txt does not explicitly set ${WHITE_R}kernel=kernel8.img${RESET} under [pi5]."
    echo -e "${YELLOW}#${RESET} Current detected override: ${WHITE_R}${kernel_override:-<none>}${RESET}\\n"
  fi

  if has_nvidia_pci_device; then
    install_raspberry_pi_nvidia_driver_stack
    install_raspberry_pi_cuda_toolkit
  fi
}

ensure_runtime_prerequisites_installed() {
  local missing_deps=()
  local runtime_deps=("ca-certificates" "curl" "gnupg" "jq" "lsb-release" "pciutils")

  for dep in "${runtime_deps[@]}"; do
    if ! dpkg -s "$dep" >/dev/null 2>&1; then
      missing_deps+=("$dep")
    fi
  done

  if [[ ${#missing_deps[@]} -eq 0 ]]; then
    echo -e "${GREEN}#${RESET} Runtime prerequisites are already installed.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Installing runtime prerequisites: ${missing_deps[*]}...\\n"
  sudo apt-get update
  sudo apt-get install -y "${missing_deps[@]}"
  echo -e "${GREEN}#${RESET} Runtime prerequisites installed successfully.\\n"
}

check_is_debug_mode(){
  # Check if the script is being run in debug mode
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local length="${1:-32}"  # Default to 32
  local password

  # Temporarily disable pipefail so head terminating the upstream tr process
  # doesn't turn password generation into a false error.
  set +o pipefail
  password="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")"
  set -o pipefail

  echo "$password"
}

ensure_docker_installed() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker not found. Installing Docker...\\n"

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings

    local docker_os=''
    local docker_codename=''

    docker_os="$(. /etc/os-release && echo "${ID}")"
    docker_codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

    if [[ "$docker_os" != "ubuntu" && "$docker_os" != "debian" ]]; then
      echo "Unsupported Docker repository distribution: $docker_os"
      exit 1
    fi

    sudo curl -fsSL \
      "https://download.docker.com/linux/${docker_os}/gpg" \
      -o /etc/apt/keyrings/docker.asc

    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_os} ${docker_codename} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Check if Docker was installed successfully
    if ! command -v docker &> /dev/null; then
      echo -e "${RED}#${RESET} Docker installation failed. Please check the logs and try again."
      exit 1
    fi
    
    echo -e "${GREEN}#${RESET} Docker installation completed.\\n"
    ensure_docker_group_access
  else
    echo -e "${GREEN}#${RESET} Docker is already installed.\\n"
    
    # Check if Docker service is running
    if ! systemctl is-active --quiet docker; then
      echo -e "${YELLOW}#${RESET} Docker is installed but not running. Attempting to start Docker...\\n"
      sudo systemctl start docker
      if ! systemctl is-active --quiet docker; then
        echo -e "${RED}#${RESET} Failed to start Docker. Please check the Docker service status and try again."
        exit 1
      else
        echo -e "${GREEN}#${RESET} Docker service started successfully.\\n"
      fi
    else
      echo -e "${GREEN}#${RESET} Docker service is already running.\\n"
    fi

    ensure_docker_group_access
  fi
}

ensure_docker_compose_available() {
  if docker compose version >/dev/null 2>&1; then
    echo -e "${GREEN}#${RESET} Docker Compose plugin is already available.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Docker Compose plugin not detected. Attempting to install it...\\n"
  sudo apt-get update
  if ! sudo apt-get install -y docker-compose-plugin; then
    echo -e "${RED}#${RESET} Failed to install docker-compose-plugin. Docker is present but compose is unavailable."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}#${RESET} Docker Compose plugin is still unavailable after installation."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Docker Compose plugin installed successfully.\\n"
}

ensure_docker_group_access() {
  if ! getent group docker >/dev/null 2>&1; then
    return 0
  fi

  if id -nG "$(whoami)" | grep -qw docker; then
    echo -e "${GREEN}#${RESET} User ${WHITE_R}$(whoami)${RESET} is already in the docker group.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Adding ${WHITE_R}$(whoami)${RESET} to the docker group for future non-sudo Docker access...\\n"
  sudo usermod -aG docker "$(whoami)"
  echo -e "${YELLOW}#${RESET} Docker group membership will apply to new login sessions. This installer will continue using sudo-backed Docker checks for now.\\n"
}

docker_runtime_is_configured() {
  sudo docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'
}

get_parent_block_device() {
  local device_path="$1"
  local parent_name=''
  parent_name="$(lsblk -no PKNAME "${device_path}" 2>/dev/null | head -n1)"
  if [[ -n "${parent_name}" ]]; then
    echo "/dev/${parent_name}"
  fi
}

get_root_block_device() {
  local root_source=''
  root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  if [[ "${root_source}" == /dev/* ]]; then
    local root_parent=''
    root_parent="$(get_parent_block_device "${root_source}")"
    echo "${root_parent:-${root_source}}"
  fi
}

device_is_system_disk() {
  local device_path="$1"
  local root_device=''
  local candidate_parent=''
  root_device="$(get_root_block_device)"
  candidate_parent="$(get_parent_block_device "${device_path}")"
  [[ -n "${root_device}" && "${root_device}" == "${candidate_parent:-${device_path}}" ]]
}

device_mountpoint() {
  local device_path="$1"
  findmnt -nr -S "${device_path}" -o TARGET 2>/dev/null | head -n1 || true
}

device_label() {
  local device_path="$1"
  sudo blkid -s LABEL -o value "${device_path}" 2>/dev/null || true
}

device_filesystem_type() {
  local device_path="$1"
  sudo blkid -s TYPE -o value "${device_path}" 2>/dev/null || true
}

list_external_partition_candidates() {
  python3 - <<'PY'
import json
import subprocess

result = subprocess.run(
    ['lsblk', '-J', '-o', 'PATH,TYPE,FSTYPE,LABEL,MOUNTPOINT,SIZE,RM,TRAN'],
    check=True,
    capture_output=True,
    text=True,
)
data = json.loads(result.stdout)

def walk(nodes):
    for node in nodes:
        yield node
        for child in walk(node.get('children', []) or []):
            yield child

for node in walk(data.get('blockdevices', [])):
    if node.get('type') != 'part':
        continue
    print(
        f"{node.get('path','')}|{node.get('fstype') or ''}|{node.get('label') or ''}|"
        f"{node.get('mountpoint') or ''}|{node.get('size') or ''}|{int(bool(node.get('rm')))}|{node.get('tran') or ''}"
    )
PY
}

list_swap_device_candidates() {
  python3 - <<'PY'
import json
import subprocess

result = subprocess.run(
    ['lsblk', '-J', '-o', 'PATH,TYPE,FSTYPE,LABEL,MOUNTPOINT,SIZE,RM,TRAN'],
    check=True,
    capture_output=True,
    text=True,
)
data = json.loads(result.stdout)

def walk(nodes):
    for node in nodes:
        yield node
        for child in walk(node.get('children', []) or []):
            yield child

for node in walk(data.get('blockdevices', [])):
    node_type = node.get('type')
    removable = int(bool(node.get('rm')))
    transport = node.get('tran') or ''
    if node_type == 'part' or (node_type == 'disk' and (transport == 'usb' or removable == 1)):
        print(
            f"{node.get('path','')}|{node_type or ''}|{node.get('fstype') or ''}|{node.get('label') or ''}|"
            f"{node.get('mountpoint') or ''}|{node.get('size') or ''}|{removable}|{transport}"
        )
PY
}

device_contains_zim_files() {
  local device_path="$1"
  local fstype=''
  fstype="$(device_filesystem_type "${device_path}")"
  [[ "${fstype}" == 'ext4' ]] || return 1

  local mountpoint=''
  mountpoint="$(device_mountpoint "${device_path}")"
  local temp_mount=''
  local mounted_here='false'

  if [[ -z "${mountpoint}" ]]; then
    temp_mount="$(mktemp -d)"
    if sudo mount -o ro "${device_path}" "${temp_mount}" >/dev/null 2>&1; then
      mountpoint="${temp_mount}"
      mounted_here='true'
    else
      rmdir "${temp_mount}" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  local found='false'
  if find "${mountpoint}" -path '*/project-nomad/storage/zim/*.zim' -o -path '*/project-nomad/storage/zim/content/*.zim' 2>/dev/null | read -r _; then
    found='true'
  fi

  if [[ "${mounted_here}" == 'true' ]]; then
    sudo umount "${temp_mount}" >/dev/null 2>&1 || true
    rmdir "${temp_mount}" >/dev/null 2>&1 || true
  fi

  [[ "${found}" == 'true' ]]
}

device_looks_like_nomad_data() {
  local device_path="$1"
  local detected_label=''
  detected_label="$(device_label "${device_path}")"
  if [[ "${detected_label}" == "${external_label}" ]]; then
    return 0
  fi

  local fstype=''
  fstype="$(device_filesystem_type "${device_path}")"
  if [[ "${fstype}" != 'ext4' ]]; then
    return 1
  fi

  local mountpoint=''
  mountpoint="$(device_mountpoint "${device_path}")"
  local temp_mount=''
  local mounted_here='false'

  if [[ -z "${mountpoint}" ]]; then
    temp_mount="$(mktemp -d)"
    if sudo mount -o ro "${device_path}" "${temp_mount}" >/dev/null 2>&1; then
      mountpoint="${temp_mount}"
      mounted_here='true'
    else
      rmdir "${temp_mount}" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  local looks_like_nomad='false'
  if [[ -d "${mountpoint}/project-nomad" || -d "${mountpoint}/project-nomad/storage" || -f "${mountpoint}/project-nomad/install-metadata.env" ]]; then
    looks_like_nomad='true'
  fi

  if [[ "${mounted_here}" == 'true' ]]; then
    sudo umount "${temp_mount}" >/dev/null 2>&1 || true
    rmdir "${temp_mount}" >/dev/null 2>&1 || true
  fi

  [[ "${looks_like_nomad}" == 'true' ]]
}

device_hosts_active_swap() {
  local device_path="$1"
  local mountpoint=''
  mountpoint="$(device_mountpoint "${device_path}")"

  while read -r swap_name; do
    [[ -z "${swap_name}" ]] && continue
    if [[ "${swap_name}" == "${device_path}" ]]; then
      return 0
    fi
    if [[ -n "${mountpoint}" && "${swap_name}" == "${mountpoint}/"* ]]; then
      return 0
    fi
  done < <(swapon --noheadings --raw --show=NAME 2>/dev/null || true)

  return 1
}

safe_sd_boot_order_value() {
  if [[ "${target_platform}" == 'raspberry-pi' ]] && grep -qi "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
    echo "0xf461"
  else
    echo "0xf41"
  fi
}

current_boot_order_value() {
  sudo rpi-eeprom-config 2>/dev/null | awk -F= '/^BOOT_ORDER=/{print $2; exit}'
}

apply_safe_boot_order() {
  local desired_boot_order=''
  desired_boot_order="$(safe_sd_boot_order_value)"
  local temp_file=''
  temp_file="$(mktemp)"

  if ! sudo sh -c "rpi-eeprom-config > '${temp_file}'" >/dev/null 2>&1; then
    rm -f "${temp_file}"
    echo -e "${YELLOW}#${RESET} Warning: unable to read current Raspberry Pi EEPROM configuration."
    return 1
  fi

  if grep -q '^BOOT_ORDER=' "${temp_file}"; then
    sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=${desired_boot_order}/" "${temp_file}"
  else
    printf "\n[all]\nBOOT_ORDER=%s\n" "${desired_boot_order}" >> "${temp_file}"
  fi

  if ! sudo rpi-eeprom-update -d -f "${temp_file}" >/dev/null 2>&1; then
    rm -f "${temp_file}"
    echo -e "${YELLOW}#${RESET} Warning: failed to stage Raspberry Pi bootloader EEPROM update."
    return 1
  fi

  rm -f "${temp_file}"
  boot_order_update_applied='true'
  echo -e "${GREEN}#${RESET} Raspberry Pi bootloader update staged with BOOT_ORDER=${WHITE_R}${desired_boot_order}${RESET}."
  echo -e "${YELLOW}#${RESET} Reboot is required before the new boot order takes effect.\\n"
  return 0
}

ensure_safe_boot_order() {
  if [[ "${target_platform}" != 'raspberry-pi' ]]; then
    return 0
  fi

  if ! command -v rpi-eeprom-config >/dev/null 2>&1 || ! command -v rpi-eeprom-update >/dev/null 2>&1; then
    record_warning "Raspberry Pi EEPROM tools are unavailable. Boot-order safety was not checked."
    return 0
  fi

  local desired_boot_order=''
  local current_boot_order=''
  desired_boot_order="$(safe_sd_boot_order_value)"
  current_boot_order="$(current_boot_order_value || true)"

  if [[ -z "${current_boot_order}" ]]; then
    record_warning "Could not determine current Raspberry Pi boot order."
    return 0
  fi

  if [[ "${current_boot_order}" == "${desired_boot_order}" ]]; then
    echo -e "${GREEN}#${RESET} Raspberry Pi boot order already prefers SD before USB/NVMe: ${WHITE_R}${current_boot_order}${RESET}.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Current Raspberry Pi boot order is ${WHITE_R}${current_boot_order}${RESET}; recommended safe order is ${WHITE_R}${desired_boot_order}${RESET}."
  if confirm_action "Stage a bootloader update so the Pi prefers SD boot before USB/NVMe?"; then
    apply_safe_boot_order || true
  else
    record_warning "Skipped Raspberry Pi boot-order update. USB-attached boot media may still interfere with startup."
  fi
}

refresh_nomad_data_root() {
  if [[ "${use_external_storage}" == 'false' ]]; then
    nomad_data_root="${NOMAD_DIR}"
    NVIDIA_RUNTIME_CACHE_DIR="${DEFAULT_NVIDIA_RUNTIME_CACHE_DIR}"
  else
    nomad_data_root="${external_mount}/project-nomad"
    NVIDIA_RUNTIME_CACHE_DIR="${nomad_data_root}/runtime-cache/nvidia"
  fi
  install_secrets_file="${nomad_data_root}/install-secrets.env"
  swap_file_path="${swap_mount}/swapfile"
}

directory_has_files() {
  local directory_path="$1"
  [[ -d "${directory_path}" ]] && find "${directory_path}" -mindepth 1 -maxdepth 1 | read -r _
}

mysql_data_present() {
  directory_has_files "${nomad_data_root}/mysql"
}

redis_data_present() {
  directory_has_files "${nomad_data_root}/redis"
}

backup_and_reset_mysql_data_if_requested() {
  if [[ "${reset_existing_mysql}" != 'true' ]]; then
    return 0
  fi

  if ! mysql_data_present; then
    return 0
  fi

  local mysql_backup_dir="${nomad_data_root}/mysql-recovery-backup-${INSTALL_TIMESTAMP}"
  echo -e "${YELLOW}#${RESET} Backing up existing MySQL data directory to ${WHITE_R}${mysql_backup_dir}${RESET} before initializing a fresh Nomad metadata database."
  sudo mv "${nomad_data_root}/mysql" "${mysql_backup_dir}"
  sudo mkdir -p "${nomad_data_root}/mysql"
  sudo chown -R "$(whoami):$(whoami)" "${nomad_data_root}/mysql"
}

backup_and_reset_redis_data_if_requested() {
  if [[ "${reset_existing_mysql}" != 'true' ]]; then
    return 0
  fi

  if ! redis_data_present; then
    return 0
  fi

  local redis_backup_dir="${nomad_data_root}/redis-recovery-backup-${INSTALL_TIMESTAMP}"
  echo -e "${YELLOW}#${RESET} Backing up existing Redis data directory to ${WHITE_R}${redis_backup_dir}${RESET} before clearing stale BullMQ queue state."
  sudo mv "${nomad_data_root}/redis" "${redis_backup_dir}"
  sudo mkdir -p "${nomad_data_root}/redis"
  sudo chown -R "$(whoami):$(whoami)" "${nomad_data_root}/redis"
}

repair_nomad_storage_permissions() {
  refresh_nomad_data_root

  sudo mkdir -p \
    "${nomad_data_root}/storage/logs" \
    "${nomad_data_root}/storage/nodered" \
    "${nomad_data_root}/mysql" \
    "${nomad_data_root}/redis"
  sudo touch "${nomad_data_root}/storage/logs/admin.log"

  sudo chown -R "$(whoami):$(whoami)" "${nomad_data_root}/storage"
  sudo chmod -R u+rwX,go+rX "${nomad_data_root}/storage"

  # Node-RED writes its initial settings into /data on first boot and runs as
  # uid/gid 1000 in the upstream image. Without this, a root-owned recovered
  # bind mount will make the container crash-loop with EACCES.
  sudo chown -R 1000:1000 "${nomad_data_root}/storage/nodered"
  sudo find "${nomad_data_root}/storage/nodered" -type d -exec chmod 775 {} \;
  sudo find "${nomad_data_root}/storage/nodered" -type f -exec chmod 664 {} \;

  # MySQL runs as uid/gid 999 in the upstream mysql:8.0 image. Reused external
  # data can easily keep the wrong owner after recovery-style installs.
  sudo chown -R 999:999 "${nomad_data_root}/mysql"
  sudo find "${nomad_data_root}/mysql" -type d -exec chmod 750 {} \;
  sudo find "${nomad_data_root}/mysql" -type f -exec chmod 640 {} \;

  # Redis also writes persistent state inside its data dir and benefits from
  # being normalized during recovery imports.
  sudo chown -R 999:999 "${nomad_data_root}/redis"
  sudo find "${nomad_data_root}/redis" -type d -exec chmod 750 {} \;
  sudo find "${nomad_data_root}/redis" -type f -exec chmod 640 {} \;

  echo -e "${GREEN}#${RESET} Normalized permissions under ${WHITE_R}${nomad_data_root}${RESET} for storage, Node-RED, Vikunja, MySQL, and Redis."
}

load_or_generate_install_secrets() {
  refresh_nomad_data_root

  if [[ -f "${install_secrets_file}" ]]; then
    # shellcheck disable=SC1090
    source "${install_secrets_file}"
    if [[ -n "${app_key}" && -n "${db_root_password}" && -n "${db_user_password}" ]]; then
      echo -e "${GREEN}#${RESET} Reusing persisted install secrets from ${WHITE_R}${install_secrets_file}${RESET}."
      return 0
    fi
    echo -e "${RED}#${RESET} Install secrets file ${WHITE_R}${install_secrets_file}${RESET} is present but incomplete."
    exit 1
  fi

  if mysql_data_present && [[ "${reset_existing_mysql}" != 'true' ]]; then
    echo -e "${RED}#${RESET} Existing MySQL recovery data was detected under ${WHITE_R}${nomad_data_root}/mysql${RESET}, but no persisted install secrets were found."
    echo -e "${YELLOW}#${RESET} Recovery cannot safely continue because the old database volume will reject newly generated credentials."
    echo -e "${YELLOW}#${RESET} Options:"
    echo -e "${YELLOW}#${RESET}  1. restore/preserve the previous ${WHITE_R}install-secrets.env${RESET}, or"
    echo -e "${YELLOW}#${RESET}  2. re-run with ${WHITE_R}--reset-existing-mysql${RESET} to keep storage content but initialize a fresh Nomad metadata database."
    exit 1
  fi

  app_key="$(generateRandomPass)"
  db_root_password="$(generateRandomPass)"
  db_user_password="$(generateRandomPass)"

  cat > "${install_secrets_file}" <<EOF
app_key='${app_key}'
db_root_password='${db_root_password}'
db_user_password='${db_user_password}'
EOF
  chmod 600 "${install_secrets_file}"
  echo -e "${GREEN}#${RESET} Persisted install secrets to ${WHITE_R}${install_secrets_file}${RESET} for future recovery installs."
}

source_install_enabled() {
  [[ -n "${source_repo_dir}" ]]
}

copy_or_download_file() {
  local source_path="$1"
  local url="$2"
  local destination_path="$3"
  local description="$4"

  if source_install_enabled && [[ -n "${source_path}" ]]; then
    if [[ ! -f "${source_path}" ]]; then
      echo -e "${RED}#${RESET} Expected local source file for ${description} was not found: ${WHITE_R}${source_path}${RESET}"
      exit 1
    fi

    if ! cp "${source_path}" "${destination_path}"; then
      echo -e "${RED}#${RESET} Failed to copy ${description} from local source checkout."
      exit 1
    fi

    return 0
  fi

  if ! curl -fsSL "${url}" -o "${destination_path}"; then
    echo -e "${RED}#${RESET} Failed to download ${description}. Please check the URL and try again."
    exit 1
  fi
}

prepare_local_build_source_checkout() {
  if source_install_enabled; then
    return 0
  fi

  if [[ "${target_architecture}" != 'arm64' && "${target_architecture}" != 'aarch64' ]]; then
    return 0
  fi

  local source_root="${NOMAD_DIR}/source"
  local extracted_root="${source_root}/${GITHUB_REPO_NAME}-${GITHUB_REPO_BRANCH}"

  echo -e "${YELLOW}#${RESET} Preparing local source checkout for arm64 image builds...\\n"
  sudo mkdir -p "${source_root}"
  sudo chown -R "$(whoami):$(whoami)" "${source_root}"

  rm -rf "${source_root:?}/"*
  mkdir -p "${source_root}"
  if ! curl -fsSL "${GITHUB_ARCHIVE_URL}" | tar -xzf - -C "${source_root}"; then
    echo -e "${RED}#${RESET} Failed to extract source archive for local arm64 builds."
    exit 1
  fi

  if [[ -d "${extracted_root}" ]]; then
    source_repo_dir="${extracted_root}"
  else
    source_repo_dir="$(find "${source_root}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  fi

  if [[ -z "${source_repo_dir}" || ! -d "${source_repo_dir}" ]]; then
    echo -e "${RED}#${RESET} Unable to locate extracted source checkout under ${WHITE_R}${source_root}${RESET}."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Local source checkout prepared at ${WHITE_R}${source_repo_dir}${RESET}.\\n"
}

write_install_metadata() {
  local metadata_path="${NOMAD_DIR}/install-metadata.env"
  cat > "${metadata_path}" <<EOF
GITHUB_REPO_OWNER='${GITHUB_REPO_OWNER}'
GITHUB_REPO_NAME='${GITHUB_REPO_NAME}'
GITHUB_REPO_BRANCH='${GITHUB_REPO_BRANCH}'
SOURCE_REPO_DIR='${source_repo_dir}'
TARGET_PLATFORM='${target_platform}'
TARGET_ARCHITECTURE='${target_architecture}'
EXTERNAL_MOUNT='${external_mount}'
EOF
  chmod 600 "${metadata_path}"
}

confirm_action() {
  local prompt="$1"

  if [[ "${assume_yes}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Auto-confirm enabled: ${WHITE_R}${prompt}${RESET}"
    return 0
  fi

  show_nomad_yesno "Project N.O.M.A.D." "${prompt}" "Continue" "Cancel"
}

select_external_device_interactively() {
  local candidates=()
  local candidate_output=''
  local root_device=''
  local recommended_selection=''
  root_device="$(get_root_block_device)"

  candidate_output="$(list_external_partition_candidates)"

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local candidate_device=''
    candidate_device="$(echo "${line}" | cut -d'|' -f1)"
    if device_is_system_disk "${candidate_device}"; then
      continue
    fi
    candidates+=("${line}")
  done <<< "${candidate_output}"

  if [[ ${#candidates[@]} -eq 0 ]]; then
    if show_nomad_yesno \
      "Storage Setup" \
      "No external data partition was detected.\n\nProject N.O.M.A.D. can continue using the local system disk, but large ZIM libraries and AI models will live on the TF/SD card.\n\nContinue with local storage only?" \
      "Use Local" \
      "Cancel"; then
      use_external_storage='false'
      external_device=''
      return 0
    fi

    echo -e "${RED}#${RESET} No external partition candidates were detected."
    echo -e "${YELLOW}#${RESET} Connect and partition the target USB disk first, or pass ${WHITE_R}--external-device /dev/sdX1${RESET}."
    exit 1
  fi

  local options=(
    "LOCAL" "Use only local TF/SD storage for Nomad data" "OFF"
  )
  local entry=''
  for entry in "${candidates[@]}"; do
    IFS='|' read -r dev fstype label mountpoint size rm_flag transport <<< "${entry}"
    local notes=()
    local recommendation='false'
    if device_hosts_active_swap "${dev}"; then
      notes+=("active-swap")
    fi
    if [[ -n "${mountpoint}" ]]; then
      notes+=("mounted")
    fi
    if [[ "${label}" == "${external_label}" ]]; then
      notes+=("nomad-label")
      recommendation='true'
    fi
    if device_looks_like_nomad_data "${dev}"; then
      notes+=("existing-nomad-data")
      recommendation='true'
    fi
    if device_contains_zim_files "${dev}"; then
      notes+=("zim-files")
      recommendation='true'
    fi
    if [[ "${rm_flag}" == '1' ]]; then
      notes+=("removable")
    fi
    if [[ -n "${transport}" ]]; then
      notes+=("${transport}")
    fi
    local notes_csv=''
    if [[ ${#notes[@]} -gt 0 ]]; then
      notes_csv="$(IFS=,; echo "${notes[*]}")"
    fi
    local description=''
    description="$(format_storage_choice_description "${size:-<unknown>}" "${fstype:-<none>}" "${label:-<none>}" "${mountpoint:-<none>}" "${notes_csv}")"
    local state='OFF'
    if [[ -z "${recommended_selection}" && "${recommendation}" == 'true' && ! " ${notes[*]} " =~ " active-swap " ]]; then
      recommended_selection="${dev}"
      state='ON'
    fi
    options+=("${dev}" "${description}" "${state}")
  done

  if [[ -z "${recommended_selection}" ]]; then
    options[2]='ON'
  fi

  local selection=''
  selection="$(show_nomad_radiolist \
    "Storage Setup" \
    "Choose where Project N.O.M.A.D should store its large data.\n\nUse arrow keys and Space to select. Existing Nomad data and ZIM libraries are marked when detected.\n\nSystem disk: ${root_device:-<unknown>}" \
    "${options[@]}")" || exit 1

  if [[ "${selection}" == 'LOCAL' ]]; then
    use_external_storage='false'
    external_device=''
    echo -e "${YELLOW}#${RESET} User chose local-only storage. Large datasets and models will stay on the system disk."
    return 0
  fi

  use_external_storage='true'
  external_device="${selection}"
  echo -e "${GREEN}#${RESET} Selected external device: ${WHITE_R}${external_device}${RESET}\\n"
}

configure_local_storage() {
  use_external_storage='false'
  refresh_nomad_data_root
  backup_and_reset_mysql_data_if_requested
  backup_and_reset_redis_data_if_requested
  repair_nomad_storage_permissions
  echo -e "${YELLOW}#${RESET} Project N.O.M.A.D will use local storage under ${WHITE_R}${NOMAD_DIR}${RESET}."
  echo -e "${YELLOW}#${RESET} This is simpler, but large ZIM collections and Ollama models will use TF/SD storage.\\n"
}

select_swap_device_interactively() {
  if [[ "${ai_runtime_requested}" != 'true' && "${enable_ai_runtime}" != 'true' ]]; then
    use_external_swap='false'
    return 0
  fi

  local candidates=()
  local candidate_output=''
  candidate_output="$(list_swap_device_candidates)"

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local candidate_device=''
    candidate_device="$(echo "${line}" | cut -d'|' -f1)"
    if device_is_system_disk "${candidate_device}"; then
      continue
    fi
    if [[ -n "${external_device}" && "${candidate_device}" == "${external_device}" ]]; then
      continue
    fi
    candidates+=("${line}")
  done <<< "${candidate_output}"

  if [[ ${#candidates[@]} -eq 0 ]]; then
    use_external_swap='false'
    return 0
  fi

  if ! show_nomad_yesno \
    "Swap Setup" \
    "AI Assistant support was enabled for this install.\n\nA dedicated USB stick can be used for supplemental swap.\n\nFor larger local models, inference can generate heavy memory pressure and bursty I/O. Using a separate USB swap device is usually kinder to the TF/SD card and can help the system recover more gracefully under load.\n\nDo you want Project N.O.M.A.D. to configure supplemental USB-backed swap for AI workloads?" \
    "Choose Device" \
    "Keep System Swap"; then
    use_external_swap='false'
    return 0
  fi

  local options=(
    "SYSTEM" "Keep the current OS swap layout only" "OFF"
  )
  local recommended='SYSTEM'
  local entry=''
  for entry in "${candidates[@]}"; do
    IFS='|' read -r dev device_type fstype label mountpoint size rm_flag transport <<< "${entry}"
    local notes=()
    if device_hosts_active_swap "${dev}"; then
      notes+=("active-swap")
    fi
    if [[ "${device_type}" == 'disk' ]]; then
      notes+=("whole-disk")
    fi
    if [[ "${rm_flag}" == '1' ]]; then
      notes+=("removable")
    fi
    if [[ -n "${transport}" ]]; then
      notes+=("${transport}")
    fi
    local state='OFF'
    if [[ "${recommended}" == 'SYSTEM' && "${rm_flag}" == '1' ]]; then
      recommended="${dev}"
      state='ON'
    fi
    local notes_csv=''
    if [[ ${#notes[@]} -gt 0 ]]; then
      notes_csv="$(IFS=,; echo "${notes[*]}")"
    fi
    local description=''
    description="$(format_storage_choice_description "${size:-<unknown>}" "${fstype:-<none>}" "${label:-<none>}" "${mountpoint:-<none>}" "${notes_csv}")"
    options+=("${dev}" "${description}" "${state}")
  done
  if [[ "${recommended}" == 'SYSTEM' ]]; then
    options[2]='ON'
  fi

  local selection=''
  selection="$(show_nomad_radiolist \
    "Swap Setup" \
    "Choose the device for supplemental swap.\n\nUse a dedicated USB stick if available. Do not use the Nomad data disk for swap." \
    "${options[@]}")" || exit 1

  if [[ "${selection}" == 'SYSTEM' ]]; then
    use_external_swap='false'
    return 0
  fi

  use_external_swap='true'
  swap_device="${selection}"
}

configure_optional_swap_device() {
  if [[ "${ai_runtime_requested}" != 'true' && "${enable_ai_runtime}" != 'true' ]]; then
    use_external_swap='false'
    echo -e "${YELLOW}#${RESET} AI runtime was not requested, so Project N.O.M.A.D will keep the current OS swap layout."
    return 0
  fi

  if [[ "${use_external_swap}" == 'auto' ]]; then
    select_swap_device_interactively
  fi

  if [[ "${use_external_swap}" != 'true' || -z "${swap_device}" ]]; then
    echo -e "${YELLOW}#${RESET} Keeping the current OS swap layout."
    return 0
  fi

  if [[ ! -b "${swap_device}" ]]; then
    echo -e "${RED}#${RESET} Swap device ${WHITE_R}${swap_device}${RESET} was not found."
    exit 1
  fi

  local current_fstype=''
  current_fstype="$(device_filesystem_type "${swap_device}")"
  if [[ "${current_fstype}" != 'ext4' ]]; then
    if ! confirm_action "Format ${swap_device} as ext4 for supplemental swap? Existing data on that partition will be lost"; then
      echo -e "${YELLOW}#${RESET} Supplemental swap was skipped."
      use_external_swap='false'
      return 0
    fi
    sudo mkfs.ext4 -F -L "${swap_label}" "${swap_device}"
  fi

  local swap_uuid=''
  swap_uuid="$(sudo blkid -s UUID -o value "${swap_device}")"
  [[ -n "${swap_uuid}" ]] || { echo -e "${RED}#${RESET} Unable to determine UUID for ${swap_device}."; exit 1; }

  sudo mkdir -p "${swap_mount}"
  if grep -qsE "[[:space:]]${swap_mount//\//\\/}[[:space:]]" /etc/fstab; then
    sudo cp /etc/fstab "/etc/fstab.project-nomad-rpi.swap.bak"
    sudo awk -v mountpoint="${swap_mount}" '$2 != mountpoint { print }' /etc/fstab | sudo tee /etc/fstab >/dev/null
  fi
  echo "UUID=${swap_uuid} ${swap_mount} ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab >/dev/null
  sudo mount "${swap_mount}" 2>/dev/null || sudo mount -a

  refresh_nomad_data_root
  if [[ ! -f "${swap_file_path}" ]]; then
    sudo fallocate -l "${swap_size_gib}G" "${swap_file_path}" 2>/dev/null || sudo dd if=/dev/zero of="${swap_file_path}" bs=1M count="$((swap_size_gib * 1024))" status=progress
    sudo chmod 600 "${swap_file_path}"
    sudo mkswap "${swap_file_path}" >/dev/null
  fi

  if ! grep -qsF "${swap_file_path}" /etc/fstab; then
    echo "${swap_file_path} none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi

  sudo swapon "${swap_file_path}" 2>/dev/null || true
  echo -e "${GREEN}#${RESET} Supplemental swap is configured at ${WHITE_R}${swap_file_path}${RESET}.\\n"
}

configure_external_storage() {
  refresh_nomad_data_root

  if [[ -z "${external_device}" ]]; then
    select_external_device_interactively
  fi

  if [[ "${use_external_storage}" == 'false' ]]; then
    configure_local_storage
    return 0
  fi

  if [[ ! -b "${external_device}" ]]; then
    echo -e "${RED}#${RESET} External device ${WHITE_R}${external_device}${RESET} was not found."
    exit 1
  fi

  if device_is_system_disk "${external_device}"; then
    echo -e "${RED}#${RESET} Refusing to use ${WHITE_R}${external_device}${RESET} because it is on the current system boot/root device."
    exit 1
  fi

  if device_hosts_active_swap "${external_device}"; then
    echo -e "${RED}#${RESET} Refusing to use ${WHITE_R}${external_device}${RESET} because it currently hosts active swap."
    echo -e "${YELLOW}#${RESET} Keep swap on its own device/path and choose a different partition for Nomad data."
    exit 1
  fi

  ensure_safe_boot_order

  local current_fstype=''
  current_fstype="$(sudo blkid -s TYPE -o value "${external_device}" 2>/dev/null || true)"
  local device_contains_nomad_data='false'
  if device_looks_like_nomad_data "${external_device}"; then
    device_contains_nomad_data='true'
  fi

  if [[ "${format_external_disk}" != 'true' && "${current_fstype}" != 'ext4' ]]; then
    if confirm_action "External storage ${external_device} is ${current_fstype:-unknown}. Format it as ext4 for Nomad data now?"; then
      format_external_disk='true'
    fi
  fi

  if [[ "${format_external_disk}" == 'true' ]]; then
    if [[ "${device_contains_nomad_data}" == 'true' && "${force_format_existing_nomad_data}" != 'true' ]]; then
      if show_nomad_yesno \
        "Recovery Data Detected" \
        "The selected drive appears to contain existing Project N.O.M.A.D. recovery data, and possibly ZIM libraries or prior service state.\n\nFormatting it will destroy that data.\n\nDo you really want to wipe it?" \
        "Wipe It" \
        "Keep Data"; then
        force_format_existing_nomad_data='true'
      else
        echo -e "${YELLOW}#${RESET} Preserving existing Project N.O.M.A.D. recovery data on ${WHITE_R}${external_device}${RESET}."
        format_external_disk='false'
      fi
    fi
    if [[ "${format_external_disk}" == 'true' ]] && ! confirm_action "Format ${external_device} as ext4 and mount it at ${external_mount}? Existing data on that partition will be lost"; then
      echo -e "${RED}#${RESET} External storage formatting was cancelled."
      exit 1
    fi
  elif [[ "${current_fstype}" != 'ext4' ]]; then
    echo -e "${RED}#${RESET} External device ${WHITE_R}${external_device}${RESET} is not ext4 (detected: ${WHITE_R}${current_fstype:-unknown}${RESET})."
    echo -e "${YELLOW}#${RESET} Native Linux ext4 storage is required for reliable Project N.O.M.A.D data mounts."
    exit 1
  else
    echo -e "${YELLOW}#${RESET} Reusing existing ext4 filesystem on ${WHITE_R}${external_device}${RESET} without formatting."
    if [[ "${device_contains_nomad_data}" == 'true' ]]; then
      echo -e "${GREEN}#${RESET} Existing Project N.O.M.A.D data was detected on ${WHITE_R}${external_device}${RESET}; recovery-safe reuse is enabled."
    fi
  fi

  if [[ "${format_external_disk}" != 'true' && "${current_fstype}" != 'ext4' ]]; then
    echo -e "${RED}#${RESET} Cannot continue with ${WHITE_R}${external_device}${RESET} without formatting it to ext4."
    exit 1
  fi

  echo -e "${YELLOW}#${RESET} Preparing external storage device ${WHITE_R}${external_device}${RESET} for Project N.O.M.A.D data...\\n"

  local existing_mountpoint=''
  existing_mountpoint="$(device_mountpoint "${external_device}")"
  if [[ -n "${existing_mountpoint}" ]]; then
    sudo umount "${external_device}" 2>/dev/null || true
  fi

  if [[ "${format_external_disk}" == 'true' ]]; then
    sudo mkfs.ext4 -F -L "${external_label}" "${external_device}"
  fi

  local external_uuid=''
  external_uuid="$(sudo blkid -s UUID -o value "${external_device}")"
  if [[ -z "${external_uuid}" ]]; then
    echo -e "${RED}#${RESET} Unable to determine UUID for ${WHITE_R}${external_device}${RESET} after formatting."
    exit 1
  fi

  sudo mkdir -p "${external_mount}"

  local fstab_entry="UUID=${external_uuid} ${external_mount} ext4 defaults,noatime 0 2"
  if grep -qsE "[[:space:]]${external_mount//\//\\/}[[:space:]]" /etc/fstab; then
    sudo cp /etc/fstab "/etc/fstab.project-nomad-rpi.bak"
    sudo awk -v mountpoint="${external_mount}" '$2 != mountpoint { print }' /etc/fstab | sudo tee /etc/fstab >/dev/null
  fi
  echo "${fstab_entry}" | sudo tee -a /etc/fstab >/dev/null

  sudo mount "${external_mount}"
  refresh_nomad_data_root
  backup_and_reset_mysql_data_if_requested
  backup_and_reset_redis_data_if_requested
  repair_nomad_storage_permissions

  echo -e "${YELLOW}#${RESET} Installer note: Project N.O.M.A.D stores data on ${WHITE_R}${external_device}${RESET} but does not configure USB boot."
  echo -e "${YELLOW}#${RESET} If your Pi firmware ever prefers USB mass storage over the SD card, set Raspberry Pi boot order to prefer SD before USB."
  echo -e "${GREEN}#${RESET} External storage mounted at ${WHITE_R}${external_mount}${RESET} with data root ${WHITE_R}${nomad_data_root}${RESET}.\\n"
}

human_readable_kib() {
  local kib="$1"
  awk -v kib="$kib" 'BEGIN {
    split("KiB MiB GiB TiB", units, " ")
    value = kib + 0
    unit = 1
    while (value >= 1024 && unit < 4) {
      value /= 1024
      unit++
    }
    printf "%.1f %s", value, units[unit]
  }'
}

crop_dialog_text() {
  local text="$1"
  local max_len="${2:-68}"

  if (( ${#text} <= max_len )); then
    printf '%s' "${text}"
    return 0
  fi

  if (( max_len <= 3 )); then
    printf '%.*s' "${max_len}" "${text}"
    return 0
  fi

  printf '%s...' "${text:0:max_len-3}"
}

format_storage_choice_description() {
  local size="$1"
  local fstype="$2"
  local label="$3"
  local mountpoint="$4"
  local notes_csv="$5"

  local short_label="${label:-none}"
  local short_mount="${mountpoint:-none}"
  local short_fs="${fstype:-none}"

  short_label="$(crop_dialog_text "${short_label}" 14)"
  short_mount="$(crop_dialog_text "${short_mount}" 16)"

  local desc="${size:-?} fs=${short_fs} lbl=${short_label} mnt=${short_mount}"
  if [[ -n "${notes_csv}" ]]; then
    desc="${desc} ${notes_csv}"
  fi

  crop_dialog_text "${desc}" 72
}

print_runtime_preflight_report() {
  refresh_nomad_data_root
  local root_available_kib
  root_available_kib="$(df -Pk / | awk 'NR==2{print $4}')"
  local root_available_hr
  root_available_hr="$(human_readable_kib "${root_available_kib:-0}")"
  local docker_service_state
  docker_service_state="$(systemctl is-active docker 2>/dev/null || true)"
  local docker_compose_version='missing'
  if sudo docker compose version >/dev/null 2>&1; then
    docker_compose_version="$(sudo docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -n1)"
  fi

  echo -e "\\n${YELLOW}#${RESET} Runtime Preflight Check\\n"
  echo -e "${YELLOW}===========================================${RESET}"
  echo "Platform: ${target_platform} (${target_architecture})"
  echo "Repo source: ${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}@${GITHUB_REPO_BRANCH}"
  echo "Root free space: ${root_available_hr}"
  echo "Docker service: ${docker_service_state:-unknown}"
  echo "Docker compose: ${docker_compose_version}"
  echo "AI runtime requested: ${enable_ai_runtime}"

  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU host check: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | paste -sd '; ' -)"
  else
    echo "GPU host check: nvidia-smi unavailable"
  fi

  if command -v nvidia-ctk >/dev/null 2>&1; then
    echo "NVIDIA toolkit: $(nvidia-ctk --version 2>/dev/null | head -n1)"
  else
    echo "NVIDIA toolkit: missing"
  fi

  if docker_runtime_is_configured; then
    echo "Docker runtime: nvidia available"
  else
  echo "Docker runtime: nvidia missing"
  fi

  echo "External storage: ${use_external_storage}"
  if [[ "${use_external_storage}" == 'true' ]]; then
    echo "External data device: ${external_device:-<unset>}"
    echo "External data mount: ${external_mount}"
  else
    echo "External data mount: local-only"
  fi
  echo "Nomad data root: ${nomad_data_root}"
  echo "Supplemental swap: ${use_external_swap}"
  if [[ "${use_external_swap}" == 'true' ]]; then
    echo "Swap device: ${swap_device:-<unset>}"
    echo "Swap path: ${swap_file_path:-<unset>}"
  fi

  if [[ "${use_external_storage}" == 'true' ]] && findmnt -rn "${external_mount}" >/dev/null 2>&1; then
    echo "Nomad data disk free: $(df -Ph "${external_mount}" | awk 'NR==2{print $4 " of " $2}')"
  fi

  echo -e "${YELLOW}===========================================${RESET}\\n"
}

run_runtime_preflight_checks() {
  preflight_failures=0
  refresh_nomad_data_root

  print_runtime_preflight_report

  local root_available_kib
  root_available_kib="$(df -Pk / | awk 'NR==2{print $4}')"
  if [[ -z "${root_available_kib}" || "${root_available_kib}" -lt 8388608 ]]; then
    record_preflight_failure "Less than 8 GiB free on /. Free additional space before continuing."
  fi

  if ! command -v docker >/dev/null 2>&1; then
    record_preflight_failure "Docker is not installed. The preinstall stage did not complete successfully."
  fi

  if ! systemctl is-active --quiet docker; then
    record_preflight_failure "Docker service is not active. Check 'sudo systemctl status docker' and the installer log."
  fi

  if ! sudo docker compose version >/dev/null 2>&1; then
    record_preflight_failure "Docker Compose plugin is unavailable. Re-run preinstall and inspect package installation output."
  fi

  if is_raspberry_pi_5; then
    local page_size
    page_size="$(getconf PAGESIZE 2>/dev/null || true)"
    if [[ "${page_size}" != '4096' ]]; then
      record_preflight_failure "Raspberry Pi 5 is not running with 4K pages. Expected 4096, got ${page_size}. Current arm64 AI services require the 4K kernel."
    fi
  fi

  if [[ "${target_platform}" == 'raspberry-pi' ]] && has_nvidia_pci_device && [[ "${enable_ai_runtime}" == 'true' ]]; then
    if ! command -v nvidia-smi >/dev/null 2>&1; then
      record_preflight_failure "NVIDIA GPU hardware is present, but nvidia-smi is unavailable. The Pi host driver stack did not install correctly."
    elif ! nvidia-smi >/dev/null 2>&1; then
      record_preflight_failure "NVIDIA GPU hardware is present, but nvidia-smi cannot talk to the driver. Reboot after the host driver/module install and rerun the installer."
    fi

    if ! cuda_nvcc_path >/dev/null 2>&1; then
      record_preflight_failure "NVIDIA GPU hardware is present, but the CUDA toolkit is missing. The Pi host CUDA install did not complete."
    fi

    if ! command -v nvidia-ctk >/dev/null 2>&1; then
      record_preflight_failure "NVIDIA container toolkit is missing. Docker GPU passthrough will not work."
    fi

    if ! docker_runtime_is_configured; then
      record_preflight_failure "Docker does not report an nvidia runtime. Check /etc/docker/daemon.json and restart docker."
    fi

    local gpu_smoke_output=''
    if ! gpu_smoke_output="$(sudo docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1)"; then
      record_preflight_failure "Container GPU smoke test failed. Likely causes: broken nvidia-container-runtime wiring, incompatible driver/toolkit state, or Docker runtime regression."
      echo "${gpu_smoke_output}"
    else
      echo -e "${GREEN}#${RESET} Container GPU smoke test passed: ${WHITE_R}${gpu_smoke_output}${RESET}"
    fi
  elif [[ "${target_platform}" == 'raspberry-pi' ]] && has_nvidia_pci_device && [[ "${enable_ai_runtime}" == 'false' ]]; then
    echo -e "${YELLOW}#${RESET} AI runtime was skipped by user choice; NVIDIA/CUDA host validation is being skipped."
  fi

  if [[ "${skip_storage_preflight}" != 'true' ]]; then
    if [[ "${use_external_storage}" == 'true' ]]; then
      if ! findmnt -rn "${external_mount}" >/dev/null 2>&1; then
        record_preflight_failure "External data mount ${external_mount} is not mounted. Select and prepare the external drive before continuing."
      else
        local nomad_data_available_kib
        nomad_data_available_kib="$(df -Pk "${external_mount}" | awk 'NR==2{print $4}')"
        if [[ -n "${nomad_data_available_kib}" && "${nomad_data_available_kib}" -lt 52428800 ]]; then
          record_warning "Less than 50 GiB free on ${external_mount}. Large knowledgebase ingestion may stall later."
        fi
      fi
    fi

    if [[ ! -d "${nomad_data_root}/storage" || ! -d "${nomad_data_root}/mysql" || ! -d "${nomad_data_root}/redis" ]]; then
      record_preflight_failure "Nomad data directories are missing under ${nomad_data_root}. Storage preparation did not complete."
    fi

    if [[ "${use_external_swap}" == 'true' ]]; then
      if [[ ! -f "${swap_file_path}" ]]; then
        record_preflight_failure "Supplemental swap was requested, but ${swap_file_path} does not exist."
      elif ! swapon --noheadings --show=NAME 2>/dev/null | grep -qx "${swap_file_path}"; then
        record_warning "Supplemental swap file ${swap_file_path} exists but is not currently active."
      fi
    fi
  fi

  if [[ ${preflight_failures} -gt 0 ]]; then
    echo -e "${RED}#${RESET} Runtime preflight failed with ${WHITE_R}${preflight_failures}${RESET} blocking issue(s)."
    echo -e "${RED}#${RESET} Nomad will not be started until these are fixed."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Runtime preflight passed. Proceeding with Nomad installation.\\n"
}

prepare_nvidia_container_toolkit_apt_preferences() {
  local pref_file="/etc/apt/preferences.d/nomad-nvidia-container-toolkit"

  echo -e "${YELLOW}#${RESET} Ensuring APT preferences allow NVIDIA container toolkit packages...\\n"

  cat <<'EOF' | sudo tee "$pref_file" >/dev/null
Package: nvidia-container-toolkit nvidia-container-toolkit-base nvidia-container-runtime libnvidia-container* libnvidia-container-tools
Pin: release *
Pin-Priority: 1001
EOF

  echo -e "${GREEN}#${RESET} NVIDIA container toolkit APT preference override written to ${WHITE_R}${pref_file}${RESET}.\\n"
}

configure_nvidia_container_runtime() {
  echo -e "${YELLOW}#${RESET} Configuring Docker to use NVIDIA runtime...\\n"

  if ! command -v nvidia-ctk &> /dev/null; then
    echo -e "${YELLOW}#${RESET} nvidia-ctk not found. Skipping Docker NVIDIA runtime configuration.\\n"
    return 0
  fi

  if ! sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} nvidia-ctk configure failed, attempting manual configuration...\\n"

    local daemon_json="/etc/docker/daemon.json"
    local config_success=false

    if [[ -f "$daemon_json" ]]; then
      sudo cp "$daemon_json" "${daemon_json}.backup" 2>/dev/null || true

      if ! grep -q '"nvidia"' "$daemon_json" 2>/dev/null; then
        if command -v jq &> /dev/null; then
          if sudo jq '. + {"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}' "$daemon_json" > /tmp/daemon.json.tmp 2>/dev/null; then
            if sudo mv /tmp/daemon.json.tmp "$daemon_json" 2>/dev/null; then
              config_success=true
            fi
          fi
          sudo rm -f /tmp/daemon.json.tmp 2>/dev/null || true
        else
          echo -e "${YELLOW}#${RESET} jq not available, skipping manual daemon.json configuration...\\n"
        fi
      else
        config_success=true
      fi
    else
      if echo '{"runtimes":{"nvidia":{"path":"nvidia-container-runtime","runtimeArgs":[]}}}' | sudo tee "$daemon_json" > /dev/null 2>&1; then
        config_success=true
      fi
    fi

    if ! $config_success; then
      echo -e "${YELLOW}#${RESET} Manual daemon.json configuration unsuccessful. GPU support may require manual setup.\\n"
    fi
  fi

  echo -e "${YELLOW}#${RESET} Restarting Docker service...\\n"
  if ! sudo systemctl restart docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to restart Docker service. You may need to restart it manually.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Verifying NVIDIA runtime configuration...\\n"
  sleep 2

  if docker_runtime_is_configured; then
    echo -e "${GREEN}#${RESET} NVIDIA runtime successfully configured and verified.\\n"
  else
    echo -e "${YELLOW}#${RESET} Warning: NVIDIA runtime not detected in Docker info. GPU acceleration may not work.\\n"
    echo -e "${YELLOW}#${RESET} You may need to manually configure /etc/docker/daemon.json and restart Docker.\\n"
  fi

  echo -e "${GREEN}#${RESET} NVIDIA container runtime configuration completed.\\n"
}

setup_nvidia_container_toolkit() {
  # This function attempts to set up NVIDIA GPU support but is non-blocking
  # Any failures will result in warnings but will NOT stop the installation process

  if [[ "${enable_ai_runtime}" == 'false' ]]; then
    echo -e "${YELLOW}#${RESET} Skipping NVIDIA container toolkit setup because AI runtime was not requested.\\n"
    return 0
  fi
  
  echo -e "${YELLOW}#${RESET} Checking for NVIDIA GPU...\\n"
  
  # Safely detect NVIDIA GPU
  local has_nvidia_gpu=false
  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected.\\n"
    fi
  fi
  
  # Also check for nvidia-smi
  if ! $has_nvidia_gpu && command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected via nvidia-smi.\\n"
    fi
  fi
  
  if ! $has_nvidia_gpu; then
    echo -e "${YELLOW}#${RESET} No NVIDIA GPU detected. Skipping NVIDIA container toolkit installation.\\n"
    return 0
  fi
  
  # Check if nvidia-container-toolkit is already installed
  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}#${RESET} NVIDIA container toolkit is already installed.\\n"
    configure_nvidia_container_runtime
    return 0
  fi
  
  echo -e "${YELLOW}#${RESET} Installing NVIDIA container toolkit...\\n"
  prepare_nvidia_container_toolkit_apt_preferences
  
  # Install dependencies per https://docs.ollama.com/docker - wrapped in error handling
  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit GPG key. Continuing anyway...\\n"
    return 0
  fi
  
  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit repository. Continuing anyway...\\n"
    return 0
  fi
  
  if ! sudo apt-get update 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to update package list. Continuing anyway...\\n"
    return 0
  fi
  
  if ! sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to install NVIDIA container toolkit. Continuing anyway...\\n"
    return 0
  fi
  
  echo -e "${GREEN}#${RESET} NVIDIA container toolkit installed successfully.\\n"
  
  configure_nvidia_container_runtime
}

run_platform_runtime_preinstall() {
  detect_target_platform
  ensure_runtime_prerequisites_installed
  ensure_raspberry_pi_nvidia_prerequisites

  if [[ "${target_platform}" == 'raspberry-pi' ]]; then
    echo -e "${YELLOW}#${RESET} Raspberry Pi detected. Running platform-specific runtime preparation before Nomad installation...\\n"
  else
    echo -e "${YELLOW}#${RESET} Running generic container runtime preparation before Nomad installation...\\n"
  fi

  ensure_docker_installed
  ensure_docker_compose_available
  setup_nvidia_container_toolkit
}

get_install_confirmation(){
  if [[ "${assume_yes}" == 'true' ]]; then
    accepted_terms='true'
    echo -e "${YELLOW}#${RESET} Auto-confirm enabled: proceeding with Project N.O.M.A.D installation."
    return 0
  fi

  if show_nomad_yesno \
    "Project N.O.M.A.D. Installer" \
    "This installer will prepare Docker, storage, and optional AI runtime support for Project N.O.M.A.D.\n\nProject N.O.M.A.D. is licensed under the Apache License 2.0.\n\nBy continuing, you confirm that you have read and accept the license terms for this software and the bundled installer flow.\n\nYou will be asked for consent before any disk format or recovery-impacting step.\n\nContinue?" \
    "Accept & Continue" \
    "Exit"; then
    accepted_terms='true'
    echo -e "${GREEN}#${RESET} User chose to continue with the installation."
    return 0
  fi

  echo "User chose not to continue with the installation."
  exit 0
}

accept_terms() {
  if [[ "${accepted_terms}" == 'true' ]]; then
    return 0
  fi

  if [[ "${assume_yes}" == 'true' ]]; then
    accepted_terms='true'
    echo -e "${YELLOW}#${RESET} Auto-confirm enabled: accepting License Agreement & Terms of Use."
    return 0
  fi

  if show_nomad_yesno \
    "License Agreement & Terms" \
    "Project N.O.M.A.D. is licensed under the Apache License 2.0.\n\nBy continuing, you confirm that you have read and accept the license terms for this software and the bundled installer flow." \
    "Accept" \
    "Decline"; then
    accepted_terms='true'
    return 0
  fi

  echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
  exit 1
}

create_nomad_directory(){
  # Ensure the main installation directory exists
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    sudo mkdir -p "$NOMAD_DIR"
    sudo chown "$(whoami):$(whoami)" "$NOMAD_DIR"

    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  # Also ensure the directory has a /storage/logs/ subdirectory
  sudo mkdir -p "${NOMAD_DIR}/storage/logs"

  # Create a admin.log file in the logs directory
  sudo touch "${NOMAD_DIR}/storage/logs/admin.log"
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"
  refresh_nomad_data_root
  load_or_generate_install_secrets

  echo -e "${YELLOW}#${RESET} Downloading docker-compose file for management...\\n"
  local compose_source_path=''
  local compose_url="${MANAGEMENT_COMPOSE_FILE_URL}"
  if source_install_enabled; then
    compose_source_path="${source_repo_dir}/install/management_compose.local-build.yaml"
    compose_url=''
  fi
  copy_or_download_file "${compose_source_path}" "${compose_url}" "${compose_file_path}" "the docker compose file"
  echo -e "${GREEN}#${RESET} Docker compose file downloaded successfully to $compose_file_path.\\n"

  # Inject dynamic env values into the compose file
  echo -e "${YELLOW}#${RESET} Configuring docker-compose file env variables...\\n"
  sed -i "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
  sed -i "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"
  
  sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
  sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
  sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"
  sed -i "s|/opt/project-nomad/storage|${nomad_data_root}/storage|g" "$compose_file_path"
  sed -i "s|/opt/project-nomad/mysql|${nomad_data_root}/mysql|g" "$compose_file_path"
  sed -i "s|/opt/project-nomad/redis|${nomad_data_root}/redis|g" "$compose_file_path"
  sed -i "s|__NOMAD_SOURCE_DIR__|${source_repo_dir}|g" "$compose_file_path"
  sed -i "s|\\./entrypoint\\.sh:/usr/local/bin/entrypoint\\.sh|${NOMAD_DIR}/entrypoint.sh:/usr/local/bin/entrypoint.sh|g" "$compose_file_path"
  sed -i "s|\\./wait-for-it\\.sh:/usr/local/bin/wait-for-it\\.sh|${NOMAD_DIR}/wait-for-it.sh:/usr/local/bin/wait-for-it.sh|g" "$compose_file_path"
  sed -i 's|test: \["CMD", "mysqladmin", "ping", "-h", "localhost"\]|test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 --protocol=tcp -uroot -p\\"$$MYSQL_ROOT_PASSWORD\\""]|g' "$compose_file_path"
  if grep -q 'mysqladmin ping -h 127.0.0.1 --protocol=tcp -uroot -p\\"$$MYSQL_ROOT_PASSWORD\\"' "$compose_file_path"; then
    python3 - "$compose_file_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
if 'start_period: 180s' not in text:
    text = text.replace(
        '      interval: 30s\n      timeout: 10s\n      retries: 3\n',
        '      start_period: 180s\n      interval: 30s\n      timeout: 10s\n      retries: 10\n',
    )
path.write_text(text)
PY
  fi

  if grep -q 'replaceme' "$compose_file_path"; then
    echo -e "${RED}#${RESET} Compose templating left unresolved placeholder values in ${WHITE_R}${compose_file_path}${RESET}."
    exit 1
  fi

  if ! grep -q "${NOMAD_DIR}/entrypoint.sh:/usr/local/bin/entrypoint.sh" "$compose_file_path"; then
    echo -e "${RED}#${RESET} Management compose file was not wired to the installed entrypoint script under ${WHITE_R}${NOMAD_DIR}${RESET}."
    exit 1
  fi

  if ! grep -q "${NOMAD_DIR}/wait-for-it.sh:/usr/local/bin/wait-for-it.sh" "$compose_file_path"; then
    echo -e "${RED}#${RESET} Management compose file was not wired to the installed wait-for-it script under ${WHITE_R}${NOMAD_DIR}${RESET}."
    exit 1
  fi

  if ! grep -q 'mysqladmin ping -h 127.0.0.1 --protocol=tcp -uroot -p\\"$$MYSQL_ROOT_PASSWORD\\"' "$compose_file_path"; then
    echo -e "${RED}#${RESET} Management compose file MySQL healthcheck was not templated correctly."
    exit 1
  fi

  if ! grep -q 'start_period: 180s' "$compose_file_path"; then
    echo -e "${RED}#${RESET} Management compose file MySQL healthcheck start period was not templated correctly."
    exit 1
  fi
  
  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_wait_for_it_script() {
  local wait_for_it_script_path="${NOMAD_DIR}/wait-for-it.sh"

  echo -e "${YELLOW}#${RESET} Downloading wait-for-it script...\\n"
  copy_or_download_file '' "$WAIT_FOR_IT_SCRIPT_URL" "$wait_for_it_script_path" "the wait-for-it script"
  chmod +x "$wait_for_it_script_path"
  echo -e "${GREEN}#${RESET} wait-for-it script downloaded successfully to $wait_for_it_script_path.\\n"
}

download_entrypoint_script() {
  local entrypoint_script_path="${NOMAD_DIR}/entrypoint.sh"

  echo -e "${YELLOW}#${RESET} Downloading entrypoint script...\\n"
  local entrypoint_source_path=''
  local entrypoint_url="${ENTRYPOINT_SCRIPT_URL}"
  if source_install_enabled; then
    entrypoint_source_path="${source_repo_dir}/install/entrypoint.sh"
    entrypoint_url=''
  fi
  copy_or_download_file "${entrypoint_source_path}" "${entrypoint_url}" "${entrypoint_script_path}" "the entrypoint script"
  chmod +x "$entrypoint_script_path"
  echo -e "${GREEN}#${RESET} entrypoint script downloaded successfully to $entrypoint_script_path.\\n"
}

download_sidecar_files() {
  # Create sidecar-updater directory if it doesn't exist
  if [[ ! -d "${NOMAD_DIR}/sidecar-updater" ]]; then
    sudo mkdir -p "${NOMAD_DIR}/sidecar-updater"
    sudo chown "$(whoami):$(whoami)" "${NOMAD_DIR}/sidecar-updater"
  fi

  local sidecar_dockerfile_path="${NOMAD_DIR}/sidecar-updater/Dockerfile"
  local sidecar_script_path="${NOMAD_DIR}/sidecar-updater/update-watcher.sh"
  local sidecar_dockerfile_source_path=''
  local sidecar_script_source_path=''
  local sidecar_dockerfile_url="${SIDECAR_UPDATER_DOCKERFILE_URL}"
  local sidecar_script_url="${SIDECAR_UPDATER_SCRIPT_URL}"

  if source_install_enabled; then
    sidecar_dockerfile_source_path="${source_repo_dir}/install/sidecar-updater/Dockerfile"
    sidecar_script_source_path="${source_repo_dir}/install/sidecar-updater/update-watcher.sh"
    sidecar_dockerfile_url=''
    sidecar_script_url=''
  fi

  echo -e "${YELLOW}#${RESET} Downloading sidecar updater Dockerfile...\\n"
  copy_or_download_file "${sidecar_dockerfile_source_path}" "${sidecar_dockerfile_url}" "${sidecar_dockerfile_path}" "the sidecar updater Dockerfile"
  echo -e "${GREEN}#${RESET} Sidecar updater Dockerfile downloaded successfully to $sidecar_dockerfile_path.\\n"

  echo -e "${YELLOW}#${RESET} Downloading sidecar updater script...\\n"
  copy_or_download_file "${sidecar_script_source_path}" "${sidecar_script_url}" "${sidecar_script_path}" "the sidecar updater script"
  chmod +x "$sidecar_script_path"
  echo -e "${GREEN}#${RESET} Sidecar updater script downloaded successfully to $sidecar_script_path.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"
  local prepare_rtlsdr_script_path="${NOMAD_DIR}/prepare_rtlsdr.sh"
  local start_script_source_path=''
  local stop_script_source_path=''
  local update_script_source_path=''
  local prepare_rtlsdr_script_source_path=''
  local start_script_url="${START_SCRIPT_URL}"
  local stop_script_url="${STOP_SCRIPT_URL}"
  local update_script_url="${UPDATE_SCRIPT_URL}"
  local prepare_rtlsdr_script_url="${PREPARE_RTLSDR_SCRIPT_URL}"

  if source_install_enabled; then
    start_script_source_path="${source_repo_dir}/install/start_nomad.sh"
    stop_script_source_path="${source_repo_dir}/install/stop_nomad.sh"
    update_script_source_path="${source_repo_dir}/install/update_nomad.sh"
    prepare_rtlsdr_script_source_path="${source_repo_dir}/install/prepare_rtlsdr.sh"
    start_script_url=''
    stop_script_url=''
    update_script_url=''
    prepare_rtlsdr_script_url=''
  fi

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"
  copy_or_download_file "${start_script_source_path}" "${start_script_url}" "${start_script_path}" "the start script"
  chmod +x "$start_script_path"

  copy_or_download_file "${stop_script_source_path}" "${stop_script_url}" "${stop_script_path}" "the stop script"
  chmod +x "$stop_script_path"

  copy_or_download_file "${update_script_source_path}" "${update_script_url}" "${update_script_path}" "the update script"
  chmod +x "$update_script_path"

  copy_or_download_file "${prepare_rtlsdr_script_source_path}" "${prepare_rtlsdr_script_url}" "${prepare_rtlsdr_script_path}" "the RTL-SDR preparation script"
  chmod +x "$prepare_rtlsdr_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded successfully to $start_script_path, $stop_script_path, $update_script_path, and $prepare_rtlsdr_script_path.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"
  if source_install_enabled; then
    echo -e "${YELLOW}#${RESET} Building local Nomad images explicitly before compose startup...\\n"

    if ! sudo docker build --provenance=false --sbom=false -t project-nomad-local:latest -f "${source_repo_dir}/Dockerfile" "${source_repo_dir}"; then
      echo -e "${RED}#${RESET} Failed to build the local Nomad admin image."
      exit 1
    fi

    if ! sudo docker build --provenance=false --sbom=false -t project-nomad-updater:latest -f "${NOMAD_DIR}/sidecar-updater/Dockerfile" "${NOMAD_DIR}/sidecar-updater"; then
      echo -e "${RED}#${RESET} Failed to build the local updater image."
      exit 1
    fi

    if ! sudo docker build --provenance=false --sbom=false -t project-nomad-disk-collector-local:latest -f "${source_repo_dir}/install/sidecar-disk-collector/Dockerfile" "${source_repo_dir}/install/sidecar-disk-collector"; then
      echo -e "${RED}#${RESET} Failed to build the local disk collector image."
      exit 1
    fi

    if ! sudo docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d --no-build; then
      echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
      exit 1
    fi
  elif ! sudo docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

wait_for_management_interface_ready() {
  local health_url='http://127.0.0.1:8080/api/health'
  local max_attempts=120
  local sleep_seconds=5
  local attempt=1
  local response=''

  echo -e "${YELLOW}#${RESET} Waiting for the Project N.O.M.A.D management interface to finish booting...\\n"

  while (( attempt <= max_attempts )); do
    response="$(curl -fsS "${health_url}" 2>/dev/null || true)"
    if [[ "${response}" == *'"status":"ok"'* ]]; then
      echo -e "${GREEN}#${RESET} Management interface is healthy and ready at ${WHITE_R}${health_url}${RESET}.\\n"
      return 0
    fi

    if (( attempt % 6 == 1 )); then
      echo -e "${YELLOW}#${RESET} Still waiting for the web interface to become ready (${attempt}/${max_attempts})..."
    fi

    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done

  echo -e "${RED}#${RESET} The management interface did not become healthy in time."
  echo -e "${RED}#${RESET} Check ${WHITE_R}sudo docker logs nomad_admin${RESET} and the installer log at ${WHITE_R}${INSTALL_LOG_FILE}${RESET}."
  exit 1
}

get_local_ip() {
  local_ip_address=$(hostname -I | awk '{print $1}')
  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    exit 1
  fi
}
verify_gpu_setup() {
  # This function only displays GPU setup status and is completely non-blocking
  # It never exits or returns error codes - purely informational
  
  echo -e "\\n${YELLOW}#${RESET} GPU Setup Verification\\n"
  echo -e "${YELLOW}===========================================${RESET}\\n"
  
  # Check if NVIDIA GPU is present
  if is_raspberry_pi_5; then
    local page_size=''
    page_size="$(getconf PAGESIZE 2>/dev/null || true)"
    if [[ "${page_size}" == '4096' ]]; then
      echo -e "${GREEN}✓${RESET} Raspberry Pi 5 kernel page size: ${WHITE_R}${page_size}${RESET} (4K kernel active)\\n"
    else
      echo -e "${YELLOW}○${RESET} Raspberry Pi 5 kernel page size: ${WHITE_R}${page_size:-unknown}${RESET} (16K/default path still active; AI services may fail)\\n"
    fi
  fi

  if command -v nvidia-smi &> /dev/null; then
    local gpu_inventory=''
    if gpu_inventory="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null)"; then
      echo -e "${GREEN}✓${RESET} NVIDIA GPU detected:"
      while IFS= read -r line; do
        [[ -n "${line}" ]] && echo -e "  ${WHITE_R}$line${RESET}"
      done <<< "${gpu_inventory}"
      echo ""
    else
      echo -e "${YELLOW}○${RESET} NVIDIA CLI is present but did not report an attached GPU in this session\\n"
    fi
  else
    echo -e "${YELLOW}○${RESET} No NVIDIA GPU detected (nvidia-smi not available)\\n"
  fi
  
  # Check if NVIDIA Container Toolkit is installed
  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}✓${RESET} NVIDIA Container Toolkit installed: $(nvidia-ctk --version 2>/dev/null | head -n1)\\n"
  else
    echo -e "${YELLOW}○${RESET} NVIDIA Container Toolkit not installed\\n"
  fi
  
  # Check if Docker has NVIDIA runtime
  if docker_runtime_is_configured; then
    echo -e "${GREEN}✓${RESET} Docker NVIDIA runtime configured\\n"
  else
    echo -e "${YELLOW}○${RESET} Docker NVIDIA runtime not detected\\n"
  fi
  
  # Check for AMD GPU
  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -iE "amd|radeon" &> /dev/null; then
      echo -e "${YELLOW}○${RESET} AMD GPU detected (ROCm support not currently available)\\n"
    fi
  fi
  
  echo -e "${YELLOW}===========================================${RESET}\\n"
  
  # Summary
  if command -v nvidia-smi &> /dev/null && docker_runtime_is_configured; then
    echo -e "${GREEN}#${RESET} GPU acceleration is properly configured! The AI Assistant will use your GPU.\\n"
  else
    echo -e "${YELLOW}#${RESET} GPU acceleration not detected. The AI Assistant will run in CPU-only mode.\\n"
    if command -v nvidia-smi &> /dev/null && ! docker_runtime_is_configured; then
      echo -e "${YELLOW}#${RESET} Tip: Your GPU is detected but Docker runtime is not configured.\\n"
      echo -e "${YELLOW}#${RESET} Try restarting Docker: ${WHITE_R}sudo systemctl restart docker${RESET}\\n"
    fi
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at /opt/project-nomad\\n\n"
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D's Command Center should automatically start whenever your device reboots. However, if you need to start it manually, you can always do so by running: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  if [[ "${boot_order_update_applied}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} A Raspberry Pi EEPROM boot-order update was staged. Reboot the Pi before relying on the new SD-first boot preference.\\n"
  fi
  echo -e "${GREEN}#${RESET} Full installer log: ${WHITE_R}${INSTALL_LOG_FILE}${RESET}\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

parse_script_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --preinstall-only)
        preinstall_only='true'
        shift
        ;;
      --preflight-only)
        preflight_only='true'
        shift
        ;;
      --storage-only)
        storage_only='true'
        shift
        ;;
      --debug)
        script_option_debug='true'
        shift
        ;;
      --assume-yes)
        assume_yes='true'
        shift
        ;;
      --format-external-disk)
        format_external_disk='true'
        shift
        ;;
      --force-format-existing-nomad-data)
        force_format_existing_nomad_data='true'
        shift
        ;;
      --reset-existing-mysql)
        reset_existing_mysql='true'
        shift
        ;;
      --external-device)
        external_device="$2"
        use_external_storage='true'
        shift 2
        ;;
      --use-local-storage)
        use_external_storage='false'
        shift
        ;;
      --external-mount)
        external_mount="$2"
        shift 2
        ;;
      --external-label)
        external_label="$2"
        shift 2
        ;;
      --swap-device)
        swap_device="$2"
        use_external_swap='true'
        shift 2
        ;;
      --keep-system-swap)
        use_external_swap='false'
        shift
        ;;
      --enable-ai-runtime)
        enable_ai_runtime='true'
        shift
        ;;
      --skip-ai-runtime)
        enable_ai_runtime='false'
        shift
        ;;
      --source-dir)
        source_repo_dir="$2"
        shift 2
        ;;
      *)
        echo -e "${YELLOW}#${RESET} Ignoring unknown option: ${WHITE_R}$1${RESET}\\n"
        shift
        ;;
    esac
  done

  if source_install_enabled && [[ ! -d "${source_repo_dir}" ]]; then
    echo -e "${RED}#${RESET} Local source directory not found: ${WHITE_R}${source_repo_dir}${RESET}"
    exit 1
  fi
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

parse_script_args "$@"

# Protect existing Project NOMAD installations.
# This installer is intended for fresh installations only.
if [[ -f "${NOMAD_DIR}/compose.yml" ]]; then
  echo
  echo "ERROR: An existing Project NOMAD installation was detected."
  echo "Location: ${NOMAD_DIR}"
  echo
  echo "This installer will not overwrite an existing installation."
  echo "Use a documented upgrade procedure instead."
  echo
  exit 1
fi

setup_logging
trap 'exit_code=$?; log_error_context "$exit_code" ${LINENO} "${BASH_COMMAND}"; exit "$exit_code"' ERR
print_log_location

# Pre-flight checks
check_is_debian_based
check_is_bash
check_has_sudo
ensure_dependencies_installed
check_is_debug_mode

if [[ "${preinstall_only}" == 'true' ]]; then
  skip_storage_preflight='true'
  run_platform_runtime_preinstall
  run_runtime_preflight_checks
  verify_gpu_setup
  exit 0
fi

if [[ "${preflight_only}" == 'true' ]]; then
  detect_target_platform
  run_runtime_preflight_checks
  verify_gpu_setup
  exit 0
fi

if [[ "${storage_only}" == 'true' ]]; then
  detect_target_platform
  prompt_ai_runtime_selection
  configure_external_storage
  configure_optional_swap_device
  run_runtime_preflight_checks
  exit 0
fi

# Main install
get_install_confirmation
accept_terms
detect_target_platform
prompt_ai_runtime_selection
configure_external_storage
configure_optional_swap_device
run_platform_runtime_preinstall
run_runtime_preflight_checks
get_local_ip
create_nomad_directory
prepare_local_build_source_checkout
write_install_metadata
download_wait_for_it_script
download_entrypoint_script
download_sidecar_files
download_helper_scripts
download_management_compose_file
start_management_containers
wait_for_management_interface_ready
verify_gpu_setup
success_message

# free_space_check() {
#   if [[ "$(df -B1 / | awk 'NR==2{print $4}')" -le '5368709120' ]]; then
#     header_red
#     echo -e "${YELLOW}#${RESET} You only have $(df -B1 / | awk 'NR==2{print $4}' | awk '{ split( "B KB MB GB TB PB EB ZB YB" , v ); s=1; while( $1>1024 && s<9 ){ $1/=1024; s++ } printf "%.1f %s", $1, v[s] }') of disk space available on \"/\"... \\n"
#     while true; do
#       read -rp $'\033[39m#\033[0m Do you want to proceed with running the script? (y/N) ' yes_no
#       case "$yes_no" in
#          [Nn]*|"")
#             free_space_check_response="Cancel script"
#             free_space_check_date="$(date +%s)"
#             echo -e "${YELLOW}#${RESET} OK... Please free up disk space before running the script again..."
#             cancel_script
#             break;;
#          [Yy]*)
#             free_space_check_response="Proceed at own risk"
#             free_space_check_date="$(date +%s)"
#             echo -e "${YELLOW}#${RESET} OK... Proceeding with the script.. please note that failures may occur due to not enough disk space... \\n"; sleep 10
#             break;;
#          *) echo -e "\\n${RED}#${RESET} Invalid input, please answer Yes or No (y/n)...\\n"; sleep 3;;
#       esac
#     done
#     if [[ -n "$(command -v jq)" ]]; then
#       if [[ "$(dpkg-query --showformat='${version}' --show jq 2> /dev/null | sed -e 's/.*://' -e 's/-.*//g' -e 's/[^0-9.]//g' -e 's/\.//g' | sort -V | tail -n1)" -ge "16" && -e "${eus_dir}/db/db.json" ]]; then
#         jq '.scripts."'"${script_name}"'" += {"warnings": {"low-free-disk-space": {"response": "'"${free_space_check_response}"'", "detected-date": "'"${free_space_check_date}"'"}}}' "${eus_dir}/db/db.json" > "${eus_dir}/db/db.json.tmp" 2>> "${eus_dir}/logs/eus-database-management.log"
#       else
#         jq '.scripts."'"${script_name}"'" = (.scripts."'"${script_name}"'" | . + {"warnings": {"low-free-disk-space": {"response": "'"${free_space_check_response}"'", "detected-date": "'"${free_space_check_date}"'"}}})' "${eus_dir}/db/db.json" > "${eus_dir}/db/db.json.tmp" 2>> "${eus_dir}/logs/eus-database-management.log"
#       fi
#       eus_database_move
#     fi
#   fi
# }
