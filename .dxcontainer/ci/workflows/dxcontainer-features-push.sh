#!/usr/bin/env nix
#! nix develop ../../../. --ignore-env --keep-env-var TERM --keep-env-var HOME --keep-env-var OCI_REGISTRY --keep-env-var OCI_REGISTRY_USERNAME --keep-env-var OCI_REGISTRY_PASSWORD --keep-env-var OCI_ARTIFACT_REPOSITORY --command bash

# ─────────────────────────────────────────────────────────────
# Nix-Shebang Interpreter
# Docs:
# - https://nix.dev/manual/nix/2.29/command-ref/new-cli/nix.html#shebang-interpreter
# - https://nix.dev/manual/nix/2.29/command-ref/new-cli/nix3-env-shell.html#options-that-change-environment-variables

# ─────────────────────────────────────────────────────────────
# Utility Functions

oras_version() {
    log "info" "${FUNCNAME[0]}: Print 'oras' version"

    oras version
}

oras_login() {
    local oci_registry="$1"
    local oci_registry_username="$2"
    local oci_registry_password="$3"

    if echo "${oci_registry_password}" | oras login --username "${oci_registry_username}" --password-stdin "${oci_registry}"; then
        log "info" "${FUNCNAME[0]} '${oci_registry}' '${oci_registry_username}' '***': Login successful"
    else
        log "error" "${FUNCNAME[0]} '${oci_registry}' '${oci_registry_username}' '***': Login failed" && exit 1
    fi
}

oras_push() {
    local oci_registry="$1"
    local oci_artifact_name="$2"
    local oci_artifact_tags="$3"
    local oci_artifact_dir="$4"

    if (cd "${oci_artifact_dir}" && oras push "${oci_registry}/${oci_artifact_name}:${oci_artifact_tags}" .); then
        log "info" "${FUNCNAME[0]} '${oci_registry}/${oci_artifact_name}:${oci_artifact_tags}' '${oci_artifact_dir}': Push successful"
    else
        log "error" "${FUNCNAME[0]} '${oci_registry}/${oci_artifact_name}:${oci_artifact_tags}' '${oci_artifact_dir}': Push failed" && exit 1
    fi
}

oras_attach() {
    local oci_registry="$1"
    local oci_artifact_name="$2"
    local oci_artifact_tags="$3"
    local oci_artifact_dir="$4"
    local oci_artifact_file="$5"
    local oci_artifact_type="$6"

    IFS=',' read -ra oci_artifact_tags_iterator <<< "$oci_artifact_tags"

    for oci_artifact_tag in "${oci_artifact_tags_iterator[@]}"; do
        if (cd "${oci_artifact_dir}" && oras attach --artifact-type="${oci_artifact_type}" "${oci_registry}/${oci_artifact_name}:${oci_artifact_tag}" "${oci_artifact_file}:${oci_artifact_type}"); then
            log "info" "${FUNCNAME[0]} '${oci_registry}/${oci_artifact_name}:${oci_artifact_tag}' '${oci_artifact_dir}/${oci_artifact_file}:${oci_artifact_type}': Attach successful"
        else
            log "error" "${FUNCNAME[0]} '${oci_registry}/${oci_artifact_name}:${oci_artifact_tag}' '${oci_artifact_dir}/${oci_artifact_file}:${oci_artifact_type}': Attach failed" && exit 1
        fi
    done
}

oras_logout() {
    local oci_registry="$1"

    if oras logout "${oci_registry}"; then
        log "info" "${FUNCNAME[0]} '${oci_registry}': Logout successful"
    else
        log "error" "${FUNCNAME[0]} '${oci_registry}': Logout failed" && exit 1
    fi
}

semver_get() {
    local component="$1"
    local version="$2"

    if [[ "$(semver validate "$version")" == "invalid" ]]; then
        log "error" "${FUNCNAME[0]} '${version}': Invalid Semantic Version (SemVer), got '${version}', want f'MAJOR.MINOR.PATCH'" && exit 1
    fi

    semver get "${component}" "${version}"
}

# ─────────────────────────────────────────────────────────────
# DxContainer Feature Functions

dxcontainer_feature_get() {
    local dxcontainer_feature_key="$1"
    local dxcontainer_feature_dir="$2"

    local dxcontainer_feature_json="${dxcontainer_feature_dir}/dxcontainer-feature.json"

    local dxcontainer_feature_value
          dxcontainer_feature_value=$(jq --raw-output ".${dxcontainer_feature_key} // empty" "${dxcontainer_feature_json}")

    if [ -z "${dxcontainer_feature_value}" ]; then
        log "error" "${FUNCNAME[0]} '${dxcontainer_feature_dir}: Missing key '${dxcontainer_feature_key}' in '${dxcontainer_feature_json}'" && exit 1
    fi

    echo "${dxcontainer_feature_value}"
}

dxcontainer_feature_tags() {
    local dxcontainer_feature_dir="$1"

    local dxcontainer_feature_version
          dxcontainer_feature_version=$(dxcontainer_feature_get "version" "${dxcontainer_feature_dir}")

    local major
          major=$(semver_get "major" "${dxcontainer_feature_version}")
    
    local minor
          minor=$(semver_get "minor" "${dxcontainer_feature_version}")
          
    local patch
          patch=$(semver_get "patch" "${dxcontainer_feature_version}")
          
    local dxcontainer_feature_tags
          dxcontainer_feature_tags="latest,${major},${major}.${minor},${major}.${minor}.${patch}"

    echo "${dxcontainer_feature_tags}"
}

dxcontainer_feature_name() {
    local dxcontainer_feature_dir="$1"

    local dxcontainer_feature_id
          dxcontainer_feature_id="$(dxcontainer_feature_get "id" "${dxcontainer_feature_dir}")"

    echo "${dxcontainer_feature_id}"
}

dxcontainer_feature_push() {
    local dxcontainer_feature_registry="$1"
    local dxcontainer_feature_repository="$2"

    local dxcontainer_feature_dir="$3"
          
    local dxcontainer_feature_name
          dxcontainer_feature_name=$(dxcontainer_feature_name "${dxcontainer_feature_dir}")
          
    local dxcontainer_feature_tags
          dxcontainer_feature_tags=$(dxcontainer_feature_tags "${dxcontainer_feature_dir}")

    local dxcontainer_feature_root_dir
          dxcontainer_feature_root_dir="${dxcontainer_feature_dir}/root"

    local dxcontainer_feature_json
          dxcontainer_feature_json="dxcontainer-feature.json"

    local dxcontainer_feature_json_media_type
          dxcontainer_feature_json_media_type="application/vnd.org.dxcontainer.dxcontainerfeature.v1+json"

    if [[ ! -d "${dxcontainer_feature_root_dir}" ]]; then
        log "error" "${FUNCNAME[0]} '${dxcontainer_feature_dir}: Missing directory '${dxcontainer_feature_root_dir}'" && exit 1
    fi

    oras_push \
        "${dxcontainer_feature_registry}" \
        "${dxcontainer_feature_repository}/${dxcontainer_feature_name}" \
        "${dxcontainer_feature_tags}" \
        "${dxcontainer_feature_root_dir}"

    oras_attach \
        "${dxcontainer_feature_registry}" \
        "${dxcontainer_feature_repository}/${dxcontainer_feature_name}" \
        "${dxcontainer_feature_tags}" \
        "${dxcontainer_feature_dir}" \
        "${dxcontainer_feature_json}" \
        "${dxcontainer_feature_json_media_type}"
}

dxcontainer_feature_dirs() {
    find "." -type f -name "dxcontainer-feature.json" -exec dirname {} \; | sort -u
}

# ─────────────────────────────────────────────────────────────
# Main Function

main() {
    local oci_registry="${OCI_REGISTRY}"
    local oci_registry_username="${OCI_REGISTRY_USERNAME}"
    local oci_registry_password="${OCI_REGISTRY_PASSWORD}"
    local oci_artifact_repository="${OCI_ARTIFACT_REPOSITORY}"

    oras_version

    oras_login "${oci_registry}" "${oci_registry_username}" "${oci_registry_password}"

    readarray -t dxcontainer_feature_dirs_iterator < <(dxcontainer_feature_dirs)

    for dxcontainer_feature_dir in "${dxcontainer_feature_dirs_iterator[@]}"; do
        dxcontainer_feature_push \
            "${oci_registry}" \
            "${oci_artifact_repository}" \
            "${dxcontainer_feature_dir}"
    done

    oras_logout "${oci_registry}"
}

main