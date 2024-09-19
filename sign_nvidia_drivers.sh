#!/usr/bin/env bash

set -e

install_packages() {
    local -n packages="${1}"
    local missing_packages=()

    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  ${package}\b"; then
            missing_packages+=("${package}")
        fi
    done

    if [ "${#missing_packages[@]}" -gt 0 ]; then
        echo "Required packages missing: ${missing_packages[@]}"
        echo "Do you want to install them? (y/n) "
        while true; do
            read response
            if [[ "${response}" =~ ^[yY]$ ]]; then
                echo "Installing."
                apt install -y "${missing_packages[*]}"
                break
            elif [[ "${response}" =~ ^[nN]$ ]]; then
                echo "Program cannot run without required dependencies. Terminating."
                exit 0
            else
                echo "Invalid input. Please enter 'y' or 'n'."
            fi
        done
    fi
}

generate_keys() {
    local mok_dir="${1}"

    if [[ ! -d "${mok_dir}" ]]; then
        mkdir "${mok_dir}"
    fi

    if [[ -f "${mok_dir}/MOK.priv" ]] && [[ -f "${mok_dir}/MOK.der" ]]; then
        echo "Found existing MOK keys. Do you want to use them instead of generating new ones?"
        while true; do
            read response
            if [[ "${response}" =~ ^[yY]$ ]]; then
                local gen_keys="true"
                break
            elif [[ "${response}" =~ ^[nN]$ ]]; then
                local gen_keys="false"
                break
            else
                echo "Invalid input. Please enter 'y' or 'n'."
            fi
        done
    else
        gen_keys="true"
    fi

    if [[ "${gen_keys}" == "true" ]]; then
        openssl req -new -x509 \
                -newkey rsa:2048 \
                -keyout "${mok_dir}/MOK.priv" \
                -outform DER \
                -out "${mok_dir}/MOK.der" \
                -nodes \
                -days 36500 \
                -subj "/CN=${USER}/" > /dev/null 2>&1
    fi

    sudo mokutil --import "${mok_dir}/MOK.der"
}

sign_drivers() {
    local mok_dir="${1}"

    for module in $(ls /lib/modules/$(uname -r)/updates/dkms/); do
        echo "Signing ${module}."
        sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 ${mok_dir}/MOK.priv ${mok_dir}/MOK.der /lib/modules/$(uname -r)/updates/dkms/${module}
    done
}

main() {
    required_packages=(
        "mokutil"
        "openssl"
        "nvidia-driver"
    )

    mok_dir="${HOME}/.mok_files"

    install_packages required_packages
    generate_keys "${mok_dir}"
    sign_drivers "${mok_dir}"

    echo -e "\nDriver signing complete. Restart your computer and enroll the new keys."

}

main "${@}"

