#!/usr/bin/env bash
set -e

# This script validates an IBM CRN based off the specification:
#     https://github.ibm.com/ibmcloud/builders-guide/blob/master/specifications/crn/CRN.md
#
# Usage: ${0} <crn>

function valid_guid
{
    local guid=${1}
    if [[ ${guid} =~ - ]]; then
        # validate formatted GUID # 8-4-4-4-12 # ex. c7a27f55-d35e-4153-b044-8ca9155fc467
        #[[ "${guid}" =~ ^\{?[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\}?$ ]] || return 1
        [[ "${guid}" =~ ^\{?[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\}?$ ]] || return 1
    else
        [[ "${guid}" =~ ^[a-f0-9]{32}$ ]] || return 1
    fi

    return 0

}

function valid_uri
{
    [[ "${1}" =~ ^[a-zA-Z0-9_\.\/%~-]+$ ]] && return 0 || return 1
}

function in_array
{
    local element=${1}
    shift
    local array=("${@}")
    for i in "${array[@]}"; do
        if [[ "${i}" == "${element}" ]]; then
            return 0
        fi
    done
    return 1

}

function valid_crn
{
    # crn:version:cname:ctype:service-name:location:scope:service-instance:resource-type:resource
    # https://github.ibm.com/ibmcloud/builders-guide/blob/master/specifications/crn/CRN.md
    local crn=${1}

    local valid_cnames=("bluemix" "internal" "staging") # can also be a customerID
    local valid_ctypes=("public" "dedicated" "local")
    local valid_geos=("us" "eu" "au" "jp" "cn")
    local valid_regions=("us-south" "us-east" "eu-gb" "eu-de" "au-syd" "jp-tok")
    local valid_zones=("AMS01" "AMS03" "CHE01" "DAL01" "DAL05" "DAL06" "DAL07" "DAL09" "DAL10" "DAL12" "DAL13" \
                       "FRA02" "FRA04" "FRA05" "HKG02" "HOU02" "LON02" "MEL01" "MEX01" "MIL01" "MON01" "OSL01" \
                       "PAR01" "SJC01" "SJC03" "SAO01" "SEA01" "SEO01" "SNG01" "SYD01" "TOK02" "TOR01" "WDC01" \
                       "WDC04" "WDC06" "WDC07")
    local valid_locations=("global" "${valid_geos[@]}" "${valid_regions[@]}" "${valid_zones[@]}")

    local errors=()

    # Split the CRN
    IFS=':' read -r -a crn_a <<< "${crn}"

    # Validate CRN - crn_a[0]
    if [[ "${crn_a[0]}" != "crn" ]]; then
        errors[0]="must start with 'crn'"
#        exit 1
    fi

    # Validate version - crn_a[1]
    #if ! in_array "${crn_a[1]}" "${valid_versions[@]}"; then
    if [[ ! "${crn_a[1]}" =~ ^v[1-9][0-9]*$ ]]; then
        errors[1]="version [${crn_a[1]}] - Must be in the form 'vX'"
#        exit 1
    fi

    # Validate ctype & cname - crn_a[3] & crn_a[2]
    if [[ "${crn_a[3]}" == "public" ]]; then
        # Check for valid cname
        if ! in_array "${crn_a[2]}" "${valid_cnames[@]}"; then
            errors[2]="cname [${crn_a[2]}] - Must be one of: ${valid_cnames[*]}"
#            exit 1
        fi
    elif [[ "${crn_a[3]}" == "dedicated" || "${crn_a[3]}" == "local" ]]; then
        # Check for valid customerID - SHOULD be alphanumeric with no spaces or special characters other than '-'
        if [[ "${crn_a[2]}" =~ \  ]]; then
            errors[2]="cname [${crn_a[2]}] - Can not contain any spaces."
#            exit 1
        elif [[ ! "${crn_a[2]}" =~ ^[a-zA-Z0-9-]+$ ]]; then
            errors[2]="cname [${crn_a[2]}] - Can not contain any special characters, only [a-z A-Z 0-9 -]"
#            exit 1
        fi
    else
        errors[3]="ctype [${crn_a[3]}] - Must be one of: ${valid_ctypes[*]}"
#        exit 1
    fi

    # Validate service-name - crn_a[4]
    # service-name MUST be unique globally and MUST be alphanumeric, lower case, no spaces or special characters other than '-'
    if [[ ! "${crn_a[4]}" =~ ^[a-z0-9-]+$ ]]; then
        errors[4]="service-name [${crn_a[4]}] - Must be lowercase and not contain any special characters except for '-'"
#        exit 1
    fi

    # Validate location - crn_a[5]
    if ! in_array "${crn_a[5]}" "${valid_locations[@]}"; then
        errors[5]="location [${crn_a[5]}] - Must be one of: ${valid_locations[*]}"
#        exit 1
    fi

    # Validate scope - crn_a[6]
    # scope segment can be empty or MUST be formatted as {scopePrefix}/{id}. scopePrefix represents the format used to identify the owner/containment.local
    local scope="${crn_a[6]}"
    if [[ ${scope} != '' ]]; then  # it can be empty
        if [[ ! "${scope}" =~ / ]]; then
            errors[6]="scope [${scope}] - Missing '/'"
#            exit 1
        else
            # split into {scope_prefix}/{scope_id}
            IFS='/' read -r -a scope_a <<< "${scope}"
            local scope_prefix="${scope_a[0]}"
            local scope_id="${scope_a[1]}"

            if [[ ! ${scope_prefix} =~ ^[aos] ]]; then
                errors[6]="scope [${scope_prefix}] - Invalid scope prefix, must be 'a' (Account), 'o' (Organization), or 's' (Space)"
    #            exit 1
            else
                # ID should be a GUID - w/o '-' if accountID (32 chars) otherwise 36 chars
                if ! valid_guid ${scope_id}; then
                    errors[6]="scope [${scope_id}] - Invalid scope ID; can only contain the characters [a-f, 0-9, -]. "
                    case "${scope_prefix}" in
                        "a") errors[6]+="Must be a valid account ID (ex. 1234567890abcdef1234567890abcdef). " ;;
                        "o") errors[6]+="Must be a valid organization GUID (ex. 12345678-90ab-cdef-1234-567890abcdef). " ;;
                        "s") errors[6]+="Must be a valid scope GUID (ex. 12345678-90ab-cdef-1234-567890abcdef). " ;;
                    esac
        #            exit 1
                fi
            fi
        fi
    fi

    # Validate service-instance - crn_a[7]
    # service-instance may be blank or MUST be a GUID or a string encoded according to the URI syntax
    local si="${crn_a[7]}"
    if [[ "${si}" != '' ]]; then  # it can be empty
        if [[ "${si}" =~ / ]]; then # it's a URI, the root should be a guid
            # validate the uri
#            valid_uri ${si} || { echo "ERROR: Invalid CRN; service-instance [${si}] has an invalid URI format"; exit 1; }
            valid_uri ${si} || errors[7]="service-instance [${si}] - Invalid URI format"
        else
            # Check for GUID
#            valid_guid ${si} || { echo "ERROR: Invalid CRN; service-instance [${si}] MUST contain a valid GUID"; exit 1; }
            valid_guid ${si} || errors[7]="service-instance [${si}] - MUST contain a valid GUID"
        fi
    fi

    # Validate resource-type - crn_a[8]
    # resource-type can be empty or MUST be alphanumeric, lower case, no spaces or special characters other than '-'
    local rt="${crn_a[8]}"
    if [[ ${rt} != '' ]]; then  # it can be empty
        if [[ ! "${rt}" =~ ^[a-z0-9-]+$ ]]; then
            errors[8]="resource-type [${rt}]. Must be lowercase and not contain any special characters except for '-'"
#            exit 1
        fi

    fi

    # Validate resource - crn_a[9]
    # resource MUST be a be a GUID or a string encoded according to the URI syntax
    local resource="${crn_a[9]}"
    if [[ ${resource} != '' ]]; then  # it can be empty
        if [[ "${resource}" =~ / ]]; then # it's a URI, the root should be a guid
            # validate the uri
#            valid_uri ${resource} || { echo "ERROR: Invalid CRN; resourece [${resource}] has an invalid URI format"; exit 1; }
            valid_uri ${resource} || errors[9]="resource [${resource}] - Invalid URI format"
        else
            # check for GUID
#            valid_guid ${resource} || { echo "ERROR: Invalid CRN; resource [${resource}] MUST contain a valid GUID"; exit 1; }
            valid_guid ${resource} || errors[9]="resource [${resource}] - MUST contain a valid GUID"
        fi
    fi

    if [[ ${#errors[*]} -eq 0 ]]; then
        return 0
    else
        echo "ERROR: Invalid CRN"
        echo "The CRN [${crn}] had the following errors:"
        for e in "${errors[@]}"; do
            echo "  * ${e}"
        done
        if [[ ${#crn_a[*]} -gt 10 ]]; then
            echo "  * CRN too long; Should only contain 10 elements:"
            echo "        crn:version:cname:ctype:service-name:location:scope:service-instance:resource-type:resource"
        fi
        return 1
    fi

}

# Main
crn="${1}"
if [[ "${crn}" == "" ]]; then
    echo "CRN required as a parameter."
    echo "CRN format: crn:version:cname:ctype:service-name:location:scope:service-instance:resource-type:resource"
    exit 1
fi
valid_crn ${crn} && echo "OK"
