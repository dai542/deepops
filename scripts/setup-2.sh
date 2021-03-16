#!/usr/bin/env bash

# Can be run standalone with: curl -sL git.io/deepops | bash
# or: curl -sL git.io/deepops | bash -s -- 19.07

ANSIBLE_VERSION="2.9.5"                         # Ansible version to install
ANSIBLE_OK="2.7.8"                              # Oldest allowed Ansible version
CONFIG_DIR=${CONFIG_DIR:-./config}              # Default configuration directory location
DEEPOPS_TAG="${1:-master}"                      # DeepOps branch to setup
JINJA2_VERSION="${JINJA2_VERSION:-2.11.1}"      # Jinja2 required version
PIP="${PIP:-pip3}"                              # Pip binary to use
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"    # Python3 path
VENV_DIR="${VENV_DIR:-/opt/deepops/env}"        # Path to python virtual environment

###

. /etc/os-release

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.." || echo "Could not cd to repository root"

DEPS_DEB=(git virtualenv python3-virtualenv sshpass wget)
DEPS_EL7=(git python-virtualenv python3-virtualenv sshpass wget)
DEPS_EL8=(git python3-virtualenv sshpass wget)
EPEL_VERSION="$(echo ${VERSION_ID} | sed  's/^[^0-9]*//;s/[^0-9].*$//')"
EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EPEL_VERSION}.noarch.rpm"
PROXY_USE=`grep -v ^# ${SCRIPT_DIR}/deepops/proxy.sh 2>/dev/null | grep -v ^$ | wc -l`

# No interactive prompts from Apt during this process
export DEBIAN_FRONTEND=noninteractive

# Exit if run as root
if [ $(id -u) -eq 0 ] ; then
    echo "Please run as a regular user"
    exit
fi

# Proxy wrapper
as_sudo(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="sudo -H bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="sudo bash -c '$@'"
    fi
    eval $cmd
}

# Proxy wrapper
as_user(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="bash -c '$@'"
    fi
    eval $cmd
}

# Install software dependencies
case "$ID" in
    rhel*|centos*)
        as_sudo "yum -y -q install ${EPEL_URL} |& grep -v 'Nothing to do'"       # Enable EPEL (required for sshpass package)
        case "$EPEL_VERSION" in
            7)
                as_sudo "yum -y -q install ${DEPS_EL7[@]}"
                ;;
            8)
                as_sudo "yum -y -q install ${DEPS_EL8[@]}"
                ;;
            esac
        ;;
    ubuntu*)
        as_sudo "apt-get -q update"
        as_sudo "apt -yq install ${DEPS_DEB[@]}"
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install ${DEPS_RPM[@]} manually"
        ;;
esac

# Create virtual environment and install python dependencies
if command -v virtualenv &> /dev/null ; then
    sudo mkdir -p "${VENV_DIR}"
    sudo chown -R $(id -u):$(id -g) "${VENV_DIR}"
    deactivate nondestructive &> /dev/null
    virtualenv -q --python="${PYTHON_BIN}" "${VENV_DIR}"
    . "${VENV_DIR}/bin/activate"
    as_user "${PIP} install -q --upgrade pip"
    as_user "${PIP} install -q --upgrade \
        ansible==${ANSIBLE_VERSION} \
        Jinja2==${JINJA2_VERSION} \
        netaddr \
        ruamel.yaml \
        PyMySQL"
else
    echo "ERROR: Unable to create Python virtual environment, 'virtualenv' command not found"
fi

# Clone DeepOps git repo if running standalone
if ! grep -i deepops README.md >/dev/null 2>&1 ; then
    if command -v git &> /dev/null ; then
        cd "${SCRIPT_DIR}"
        if ! test -d deepops ; then
            as_user git clone --branch ${DEEPOPS_TAG} https://github.com/NVIDIA/deepops.git
        fi
        cd deepops
    else
        echo "ERROR: Unable to check out DeepOps git repo, 'git' command not found"
        exit
    fi
fi

# Install Ansible Galaxy roles
if command -v ansible-galaxy &> /dev/null ; then
    echo "Updating Ansible Galaxy roles..."
    as_user ansible-galaxy collection install --force -r roles/requirements.yml >/dev/null
    as_user ansible-galaxy role install --force -r roles/requirements.yml >/dev/null
else
    echo "ERROR: Unable to install Ansible Galaxy roles, 'ansible-galaxy' command not found"
fi

# Update submodules
if command -v git &> /dev/null ; then
    as_user git submodule update --init
else
    echo "ERROR: Unable to update Git submodules, 'git' command not found"
fi

# Copy default configuration
if grep -i deepops README.md >/dev/null 2>&1 ; then
    if [ ! -d "${CONFIG_DIR}" ] ; then
        cp -rfp ./config.example "${CONFIG_DIR}"
        echo "Copied default configuration to ${CONFIG_DIR}"
    else
        echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
    fi
fi

echo
echo "*** Setup complete ***"
echo "To use Ansible, run: source ${VENV_DIR}/bin/activate"
echo
