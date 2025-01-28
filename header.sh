#!/bin/bash

# Constants
VALID_LANGUAGES=("fr" "en" "de" "es" "it")
VALID_COMMENTS=("#" "//" ";" "/")
VALID_SHEBANGS=("sh" "py" "pl" "rb" "php" "go")
VALID_TEMPLATES=("default" "single")

# Variables
current_dir_path=${PWD##*/}
current_dir_path=${current_dir_path:-/}
user_name=$(whoami)
user_name=${user_name:-"unknown"}
version="1.0.0"

# Options Variables
lang="en"
language="bash"
shebang="none"
template="default"

dest_file=${@: -1}

if [[ -f ".header_config" ]]; then
    IFS='='
    while read -r var value || [ -n "$var" ]; do
        case "$var" in
            Author) user_name="$value" ;;
            Language) lang="$value" ;;
            Shebang) shebang="$value" ;;
            Template) template="$value" ;;
        esac
    done < .header_config
fi

# Translations
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

# Single-string approach: "Language|Shebang|Comment"
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

# Utils Functions

join_by() {
  local separator="$1"
  shift
  local first="$1"
  shift
  printf "%s" "$first" "${@/#/$separator}"
}

detect_language() {
    local extension="${1##*.}"
    case "$extension" in
        sh) echo "bash" ;;
        py) echo "python" ;;
        pl) echo "perl" ;;
        rb) echo "ruby" ;;
        php) echo "php" ;;
        java) echo "java" ;;
        js|ts|tsx|jsx|mjs) echo "javascript" ;;
        c|h) echo "c" ;;
        cpp|cc|cxx|hpp) echo "cpp" ;;
        go) echo "go" ;;
        rs) echo "rust" ;;
        *) echo "bash" ;;
    esac
}

# Print N copies of the comment character
print_lines() {
    local comment_char="$1"
    local file_path="$2"
    printf -- "$comment_char%.0s" {1..15} >> "$file_path"
    echo "" >> "$file_path"
}

get_translation() {
    local key="$1"
    local slang="$2"
    echo "${translations["${key}_${slang}"]}"
}

contains() {
    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ $element == "$seeking" ]]; then
            in=0
            break
        fi
    done
    return $in
}

# Headers Functions
default_header() {
    local file="$1"
    local slang="$2"

    # Multi-line metadata
    print_lines "$comment_character" "$file"
    echo "$comment_character    $(get_translation "Author" "$slang"): $user_name" >> "$file"
    echo "$comment_character    $(get_translation "Creation Date" "$slang"): $(date)" >> "$file"
    echo "$comment_character    $(get_translation "Description" "$slang"): " >> "$file"
    print_lines "$comment_character" "$file"
    echo "$comment_character    $(get_translation "Version" "$slang"): 1.0" >> "$file"
    echo "$comment_character    $(get_translation "Last edited by" "$slang"): $user_name" >> "$file"
    echo "$comment_character    $(get_translation "Last edited on" "$slang"): $(date)" >> "$file"
    print_lines "$comment_character" "$file"
    echo "" >> "$file"
}

custom_header() {
    local file="$1"
    local slang="$2"

    # Single-line metadata
    # Example: # [Author: Michel] [Date: Mon Jan 21 ...] [Version: 1.0]
    echo "${comment_character} [$(get_translation "Author" "$slang"): $user_name]" >> "$file"
    echo "${comment_character} [$(get_translation "Creation Date" "$slang"): $(date)]" >> "$file"
    echo "${comment_character} [$(get_translation "Description" "$slang"): ]" >> "$file"
    echo "${comment_character} [$(get_translation "Version" "$slang"): 1.0]" >> "$file"
    echo "${comment_character} [$(get_translation "Last edited by" "$slang"): $user_name]" >> "$file"
    echo "${comment_character} [$(get_translation "Last edited on" "$slang"): $(date)]" >> "$file"
}

# Main Functions

Help() {
    cat << EOF
Usage: $(basename $0) [options] <file>
Description:
    This script adds a header to the specified file depending on its extension.

Options:
    -h, --help      Display this help message.
    -v, --version   Display the version of this script.
    -a, --author    Set the author name.
    -l, --language  Set the language of the file ($(join_by ", " ${VALID_LANGUAGES[*]})). Default is based on your system language ("$lang" here).
    -c, --comment   Set the comment character ($(join_by ", " ${VALID_COMMENTS[*]})). Default is based on the file extension.
    -s, --shebang   Set the shebang language ($(join_by ", " ${VALID_SHEBANGS[*]})).
    -t, --template  Set the template to use ($(join_by ", " ${VALID_TEMPLATES[*]})).

Config FIle:
    You can create a .header_config file in the same directory to set default values.
    Example:
        Author=John Doe
        Language=en
        Shebang=sh
        Template=default

Examples:
    local file="$1"
    local slang="${lang:-en}"

    $0 file.sh
EOF
}

append_header() {
    local file="$1"
    local extension="${file##*.}"
    local temp_header=$(mktemp --suffix=".$extension")
    write_header "$temp_header"

    # Insert the header at the top
    { cat "$temp_header"; cat "$file"; } > "${file}.new"
    mv "${file}.new" "$file"
    rm -f "$temp_header"
}

update_header() {
    local version="$1"
    local dest_file="$2"
    local slang="${lang:-en}"

    # Update version number
    sed -i "s/\($(get_translation "Version" "$slang"): \).*/\1$version/" "$dest_file"

    # Update last edited by
    sed -i "s/\($(get_translation "Last edited by" "$slang"): \).*/\1$user_name/" "$dest_file"

    # Update last edited on
    sed -i "s/\($(get_translation "Last edited on" "$slang"): \).*/\1$(date)/" "$dest_file"
}

write_header() {
    local file="$1"
    local slang="${lang:-en}"

    local detected_lang="$(detect_language "$file")"
    local config="${language_configs[$detected_lang]}"
    IFS='|' read -r config_shebang config_comment <<< "$config"

    # Optional shebang line
    if [[ -n "$shebang" && "$shebang" != "none" ]]; then
        echo "$config_shebang" > "$file"
    fi

    # Use the language’s default comment if user didn’t override
    if [[ -z "$comment_character" ]]; then
        comment_character="$config_comment"
    fi

    case "$template" in
        default) default_header "$file" "$slang" ;;
        single)  custom_header "$file" "$slang";;
    esac
}


OPTIONS=hva:l:c:s:t:u:
LONGOPTS=help,version,author:,language:,comment:,shebang:,template:,update:

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    exit 2
fi

eval set -- "$PARSED"

while true; do
    case "$1" in
        -h|--help)
            Help
            exit;;
        -v|--version)
            echo "Version $version"
            exit;;
        -a|--author)
            user_name="$2"
            shift 2;;
        -l|--language)
            if contains VALID_LANGUAGES "$2"; then
                lang="$2"
            else
                echo "Error: Invalid language. Valid options are: ${VALID_LANGUAGES[*]}"
                exit 1
            fi
            shift 2;;
        -c|--comment)
            if contains VALID_COMMENTS "$2"; then
                comment_character="$2"
            else
                echo "Error: Invalid comment character. Valid options are: ${VALID_COMMENTS[*]}"
                exit 1
            fi
            shift 2;;
        -s|--shebang)
            if contains VALID_SHEBANGS "$2"; then
                shebang="$2"
            else
                echo "Error: Invalid shebang. Valid options are: ${VALID_SHEBANGS[*]}"
                exit 1
            fi
            shift 2;;
        -t|--template)
            if contains VALID_TEMPLATES "$2"; then
                template="$2"
            else
                echo "Error: Invalid template. Valid options are: ${VALID_TEMPLATES[*]}"
                exit 1
            fi
            shift 2;;
        -u|--update)
            update_header "$2" "$dest_file"
            exit;;
        --)
            shift
            break;;
        *)
            echo "Error: Invalid option"
            exit 1;;
    esac
done

if [[ -z "$lang" ]]; then
    lang=${LANG:0:2}
fi

# Final argument after options should be the filename
if [[ -n "$1" && ! "$1" =~ ^- ]]; then
    dest_file="$1"
    # If file already exists, prepend the header
    if [[ -f "$dest_file" ]]; then
        append_header "$dest_file"
        exit 0;
    fi
    write_header "$dest_file"
else
    echo "Error: No file specified."
    Help
    exit 1
fi
