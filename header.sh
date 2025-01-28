#!/bin/bash
# --------------------------------------------------------------------------
# header.sh
#
# A Bash script that automatically creates and updates file headers with
# author, version, and other metadata. It can:
#    - Detect a file's programming language by extension
#    - Insert a configurable header at the top of a new or existing file
#    - Update version numbers in the file header (major, minor, patch, or direct)
#    - Translate header fields based on a chosen language (en, fr, es, etc.)
#
# You can also set default values in a local .header_config file, and
# provide command-line flags to override them as needed.
#
# Usage example:
#   ./header.sh file.sh
#   ./header.sh --update major file.py
# --------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# --------------------------
# 1) CONSTANTS & VALID VALUES
# --------------------------

# Supported languages for translations
VALID_LANGUAGES=("fr" "en" "de" "es" "it")

# Supported comment style characters
VALID_COMMENTS=("#" "//" ";" "/")

# Supported shebang shortcuts
VALID_SHEBANGS=("sh" "py" "pl" "rb" "php" "go")

# Supported templates for the header
VALID_TEMPLATES=("default" "single")

# Supported update types or version regex
VALID_UPDATE=("major" "minor" "patch" '^[0-9]+\.[0-9]+(\.[0-9]+)?$')

# --------------------------
# 2) GLOBAL VARIABLES
# --------------------------

# The current directory name, used for reference if needed
current_dir_path=${PWD##*/}
current_dir_path=${current_dir_path:-/}

# The current user's name and email, or the system username if not in a git repo
if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) ]]; then
    user_name="$(git config user.name 2>/dev/null || echo 'unknown')"
    user_email="$(git config user.email 2>/dev/null || echo 'unknown')"
    user_name="$user_name <$user_email>"
else
    user_name=$(whoami)
    user_name=${user_name:-"unknown"}
fi

# Script's own version identifier (not the file’s version)
version="1.0.0"

# Default values for command-line options
lang="en"            # Language for translations
language="bash"      # Programming language
shebang="none"       # Shebang type
template="default"   # Header template style
comment_character="" # Comment prefix (e.g. #, //)
description=""       # Description of the file
verbose=false        # Verbose mode

# Final parameter from the command line is typically the file to process
dest_file=${@: -1}


# -------------------------------------------------------
# 3) TRANSLATIONS (used to localize header field keywords)
# -------------------------------------------------------
# We store them in an associative array so we can pick
# the correct term for the user's chosen language.

declare -A translations=(
    ["Author_en"]="Author"
    ["Author_fr"]="Auteur"
    ["Author_de"]="Autor"
    ["Author_es"]="Autor"
    ["Author_it"]="Autore"

    ["Creation Date_en"]="Creation Date"
    ["Creation Date_fr"]="Date de Création"
    ["Creation Date_de"]="Erstellungsdatum"
    ["Creation Date_es"]="Fecha de Creación"
    ["Creation Date_it"]="Data di Creazione"

    ["Description_en"]="Description"
    ["Description_fr"]="Description"
    ["Description_de"]="Beschreibung"
    ["Description_es"]="Descripción"
    ["Description_it"]="Descrizione"

    ["Version_en"]="Version"
    ["Version_fr"]="Version"
    ["Version_de"]="Version"
    ["Version_es"]="Versión"
    ["Version_it"]="Versione"

    ["Last edited by_en"]="Last edited by"
    ["Last edited by_fr"]="Dernière modification par"
    ["Last edited by_de"]="Zuletzt bearbeitet von"
    ["Last edited by_es"]="Última edición por"
    ["Last edited by_it"]="Ultima modifica di"

    ["Last edited on_en"]="Last edited on"
    ["Last edited on_fr"]="Dernière modification le"
    ["Last edited on_de"]="Zuletzt bearbeitet am"
    ["Last edited on_es"]="Última edición el"
    ["Last edited on_it"]="Ultima modifica il"
)

# ----------------------------------------------------
# 4) LANGUAGE CONFIGS (SHEBANG|COMMENT) PER EXTENSION
# ----------------------------------------------------
# Each key is a programming language, with a string
# containing "shebang|comment_char". For example,
# 'bash' => "#!/bin/bash|#"

declare -A language_configs=(
  [bash]="#!/bin/bash|#"
  [python]="#!/usr/bin/env python|#"
  [perl]="#!/usr/bin/env perl|#"
  [ruby]="#!/usr/bin/env ruby|#"
  [php]="#!/usr/bin/env php|#"
  [java]="|//"
  [javascript]="|//"
  [c]="|//"
  [cpp]="|//"
  [go]="#!/usr/bin/env go|//"
  [rust]="|//"
)

# --------------------------
# 5) UTILITY FUNCTIONS
# --------------------------

# join_by - Joins an array of strings with a chosen separator.
join_by() {
  local separator="$1"
  shift
  local first="$1"
  shift
  printf "%s" "$first" "${@/#/$separator}"
}

# update_version - Increments version based on update type (major/minor/patch)
# or accepts a direct version string like 2.3.4
update_version() {
    local version="$1"
    local update="$2"
    local major minor patch

    # Split the current version into major/minor/patch
    IFS='.' read -r major minor patch <<< "$version"

    case "$update" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "$update"; return 0 ;;  # direct version string
    esac

    # Return the new version string
    echo "$major.$minor.$patch"
}

# detect_language - Detects a programming language by file extension
detect_language() {
    local extension=$1
    local result

    case "$extension" in
        sh) result="bash" ;;
        py) result="python" ;;
        pl) result="perl" ;;
        rb) result="ruby" ;;
        php) result="php" ;;
        java) result="java" ;;
        js|ts|tsx|jsx|mjs) result="javascript" ;;
        c|h) result="c" ;;
        cpp|cc|cxx|hpp) result="cpp" ;;
        go) result="go" ;;
        rs) result="rust" ;;
        *) result="bash" ;;  # Default to bash if unknown
    esac

    log_info "Detected extension '$extension', using language: $result"
    echo "$result"
}

# print_lines - Prints 15 copies of the comment character for a visual separator
print_lines() {
    local comment_char="$1"
    local file_path="$2"
    printf -- "$comment_char%.0s" {1..15} >> "$file_path"
    echo "" >> "$file_path"
}

# get_translation - Retrieves the correct translation for a given key & language
get_translation() {
    local key="$1"
    local slang="$2"
    echo "${translations["${key}_${slang}"]}"
}

# contains - Checks if "seeking" is in array_name, matching either exact string
# or, if the array element starts with ^, interpret it as a regex.
contains() {
    local array_name="$1[@]"
    local seeking="$2"
    local ret=1

    for element in "${!array_name}"; do
        if [[ "$element" =~ ^\^ ]]; then
            # If element is a regex, test for pattern match
            if [[ "$seeking" =~ $element ]]; then
                ret=0
                break
            fi
        else
            # Otherwise test for exact match
            if [[ "$element" == "$seeking" ]]; then
                ret=0
                break
            fi
        fi
    done
    
    return $ret
}

# log_info - Logs a message if verbose mode is enabled
log_info() {
    local msg="$1"
    if [[ "$verbose" == true ]]; then
        echo "[INFO]: $msg" >&2
    fi
}

# -----------------------------
# 6) HEADER GENERATION FUNCTIONS
# -----------------------------

# default_header - Creates a multi-line header with distinct lines
default_header() {
    local file="$1"
    local slang="$2"
    local now=$(date)

    # Print a separator of 15 comment chars
    print_lines "$comment_character" "$file"

    # Author, creation date, description fields
    echo "$comment_character    $(get_translation "Author" "$slang"): $user_name" >> "$file"
    echo "$comment_character    $(get_translation "Creation Date" "$slang"): $now" >> "$file"
    echo "$comment_character    $(get_translation "Description" "$slang"): $description" >> "$file"

    print_lines "$comment_character" "$file"

    # Version, last edited by, last edited on fields
    echo "$comment_character    $(get_translation "Version" "$slang"): 1.0.0" >> "$file"
    echo "$comment_character    $(get_translation "Last edited by" "$slang"): $user_name" >> "$file"
    echo "$comment_character    $(get_translation "Last edited on" "$slang"): $now" >> "$file"

    print_lines "$comment_character" "$file"
    echo "" >> "$file"
}

# custom_header - Creates a single-line header style for each metadata field
custom_header() {
    local file="$1"
    local slang="$2"
    local now=$(date)

    echo "${comment_character} [$(get_translation "Author" "$slang"): $user_name]" >> "$file"
    echo "${comment_character} [$(get_translation "Creation Date" "$slang"): $now]" >> "$file"
    echo "${comment_character} [$(get_translation "Description" "$slang"): $description]" >> "$file"
    echo "${comment_character} [$(get_translation "Version" "$slang"): 1.0.0]" >> "$file"
    echo "${comment_character} [$(get_translation "Last edited by" "$slang"): $user_name]" >> "$file"
    echo "${comment_character} [$(get_translation "Last edited on" "$slang"): $now]" >> "$file"
}

# -----------------------------
# 7) MAIN (PRIMARY) FUNCTIONS
# -----------------------------

# Help - Prints usage instructions
Help() {
    cat << EOF
Usage: $(basename $0) [options] <file>
Description:
    This script adds a header to the specified file depending on its extension.

Options:
    -h, --help      Display this help message.
    -v, --version   Display the version of this script.
    -a, --author    Set the author name.
    -l, --language  Set the language of the file ($(join_by ", " ${VALID_LANGUAGES[*]})).
                    Default is based on your system language ("$lang" here).
    -c, --comment   Set the comment character ($(join_by ", " ${VALID_COMMENTS[*]})).
                    Default is based on the file extension.
    -s, --shebang   Set the shebang language ($(join_by ", " ${VALID_SHEBANGS[*]})).
    -t, --template  Set the template to use ($(join_by ", " ${VALID_TEMPLATES[*]})).
    -u, --update    Update the header with the specified version
                    ($(join_by ", " ${VALID_UPDATE[*]::${#VALID_UPDATE[*]}-1})) or
                    with a version number (eg. 2.1.7).
    -d, --description  Add a description to the file.
    
Config File:
    You can create a .header_config file in the same directory to set default values.
    Example:
        Author=John Doe
        Language=en
        Template=default

Examples:
    $(basename $0) file.sh
EOF
}

# append_header - If a file already exists, build a header in a temp file,
# and prepend it to the existing file content.
append_header() {
    local file="$1"
    local extension="${file##*.}"

    # Create a temporary file for the header
    local temp_header
    temp_header=$(mktemp --suffix=".$extension")

    # Write a new header to the temp file
    write_header "$temp_header"

    # Prepend the newly generated header to the original file
    {
        cat "$temp_header"
        cat "$file"
    } > "${file}.new"

    mv "${file}.new" "$file"
    rm -f "$temp_header"
}

# update_header - Updates version, last edited by, and last edited on fields
# in an existing file's header.
update_header() {
    local update_type="$1"
    local dest_file="$2"
    local slang="${lang:-en}"

    log_info "Updating header in $dest_file with version $update_type..."

    # Extract the current version by searching for the "Version: X.Y.Z" line
    local current_version
    current_version=$(grep -oP "(?<=$(get_translation "Version" "$slang"): )\d+\.\d+(\.\d+)?" "$dest_file")
    
    if [[ -z "$current_version" ]]; then
        echo "Could not find a current version in $dest_file!"
        exit 1
    fi

    # Calculate the new version based on user request (major/minor/patch or direct)
    local new_version
    new_version=$(update_version "$current_version" "$update_type")
    
    # Update the fields in place with sed, using a pipe delimiter
    sed -i "s|\($(get_translation "Version" "$slang"): \).*|\1$new_version|" "$dest_file"
    sed -i "s|\($(get_translation "Last edited by" "$slang"): \).*|\1$user_name|" "$dest_file"
    sed -i "s|\($(get_translation "Last edited on" "$slang"): \).*|\1$(date)|" "$dest_file"
}

# write_header - Decides which comment char, template, etc., then writes a new header
write_header() {
    local file="$1"
    local slang="${lang:-en}"

    # Ensure the file exists, even if empty
    if [[ ! -f "$file" ]]; then
       : > "$file"
    fi

    # Detect language by file extension
    local detected_lang
    if [[ "$shebang" != "none" ]]; then
        detected_lang="$(detect_language "$shebang")"
    else
        detected_lang="$(detect_language ${file##*.})"
    fi

    # Retrieve associated config (shebang|comment)
    local config
    if [[ -n "${language_configs[$detected_lang]:-}" ]]; then
       config="${language_configs[$detected_lang]}"
    else
       # fallback if no config found
       config="|#"
    fi
    IFS='|' read -r config_shebang config_comment <<< "$config"

    echo $config_shebang

    # If no comment override was given, use the detected language's comment
    if [[ -z "$comment_character" ]]; then
        comment_character="$config_comment"
    fi

    # If shebang is not empty, write it only if no existing #! line
    if [[ -n "$shebang" ]]; then
        if ! head -1 "$file" 2>/dev/null | grep -q '^#!'; then
            echo "$config_shebang" > "$file"
        fi
    fi

    # Call the appropriate header function based on chosen template
    case "$template" in
        default) default_header "$file" "$slang" ;;
        single)  custom_header "$file" "$slang" ;;
    esac
}


# --------------------------------------
# 8) PRE-PROCESSING & ARGUMENT HANDLING
# --------------------------------------
# Before we start processing the file, we check for verbose mode and load config.

for arg in "$@"; do
    if [[ "$arg" == "-x" || "$arg" == "--verbose" ]]; then
        verbose=true
        break
    fi
done

# ----------------------------------------
# 9) LOAD CONFIG (.header_config if exists)
# ----------------------------------------
# If a local .header_config file is present, read defaults from it.
# Each line is "Key=Value", e.g. "Author=John Doe"
# This is optional and can be overridden by CLI flags.

if [[ -f ".header_config" ]]; then
    log_info "Loading default values from .header_config file..."
    while IFS='=' read -r key value; do
        # Skip empty or commented lines
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        
        # Trim whitespace around key/value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Assign config values to appropriate variables
        case "$key" in
            Author)    user_name="$value" ;;
            Language)  lang="$value" ;;
            Template)  template="$value" ;;
        esac
    done < .header_config
else
    log_info "No .header_config file found, using default values."
fi

# --------------------------------------
# 10) CLI ARGUMENT PARSING VIA GETOPT
# --------------------------------------
# We use getopt to parse short/long options and set variables accordingly.

OPTIONS=hva:l:c:s:t:u:d
LONGOPTS=help,version,author:,language:,comment:,shebang:,template:,update:,description

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    exit 2
fi

eval set -- "$PARSED"

while true; do
    case "$1" in
        -h|--help)
            Help
            exit
            ;;
        -v|--version)
            echo "Version $version"
            exit
            ;;
        -a|--author)
            user_name="$2"
            shift 2
            ;;
        -l|--language)
            # Validate language against VALID_LANGUAGES array
            if contains VALID_LANGUAGES "$2"; then
                lang="$2"
            else
                echo "Error: Invalid language. Valid options are: ${VALID_LANGUAGES[*]}"
                exit 1
            fi
            shift 2
            ;;
        -c|--comment)
            # Validate comment char
            if contains VALID_COMMENTS "$2"; then
                comment_character="$2"
            else
                echo "Error: Invalid comment character. Valid options are: ${VALID_COMMENTS[*]}"
                exit 1
            fi
            shift 2
            ;;
        -s|--shebang)
            # Validate shebang choice
            if contains VALID_SHEBANGS "$2"; then
                shebang="$2"
            else
                echo "Error: Invalid shebang. Valid options are: ${VALID_SHEBANGS[*]}"
                exit 1
            fi
            shift 2
            ;;
        -t|--template)
            # Validate template choice
            if contains VALID_TEMPLATES "$2"; then
                template="$2"
            else
                echo "Error: Invalid template. Valid options are: ${VALID_TEMPLATES[*]}"
                exit 1
            fi
            shift 2
            ;;
        -u|--update)
            # This option updates the header version
            if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
                echo "Error: --update requires a version argument"
                exit 1
            fi
            if [[ ! -f "$dest_file" ]]; then
                echo "Error: Cannot update a non-existent file ($dest_file)."
                exit 1
            fi

            # Check if the provided version/update type is valid (major/minor/patch or matches the regex)
            if ! contains VALID_UPDATE "$2"; then
                echo "Error: Invalid version update. Valid options are: ${VALID_UPDATE[*]}"
                exit 1
            fi

            # Perform the update, then exit
            update_header "$2" "$dest_file"
            exit
            ;;
        -d|--description)
            read -r -p "Enter a description for the file: " description
            shift
            ;;
        --)
            # End of options
            shift
            break
            ;;
        *)
            echo "Error: Invalid option"
            exit 1
            ;;
    esac
done

# --------------------------------------
# 10) FINAL FILE PROCESSING
# --------------------------------------
# If no language was set by config or CLI, fall back to system default or 'en'.
if [[ -z "$lang" ]]; then
    lang=${LANG:0:2}
fi

# The last argument after the parsed options is the file to operate on
if [[ -n "${1:-}" && ! "${1:-}" =~ ^- ]]; then
    dest_file="$1"

    # If the file already exists, we prepend a header (append_header).
    # If it doesn't, we create a new file with a header (write_header).
    if [[ -f "$dest_file" ]]; then
        append_header "$dest_file"
        exit 0
    fi
    write_header "$dest_file"
else
    echo "Error: No file specified."
    Help
    exit 1
fi
