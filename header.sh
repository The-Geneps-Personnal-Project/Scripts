#!/bin/bash

# Constants
VALID_LANGUAGES=("fr" "en" "de" "es" "it")
VALID_COMMENTS=("#" "//" ";" "/")
VALID_SHEBANGS=("bash" "python" "perl" "ruby" "php")
VALID_TEMPLATES=("default" "custom")

# Variables
current_dir_path=${PWD##*/}
current_dir_path=${current_dir_path:-/}
user_name=$(whoami)
user_name=${user_name:-"unknown"}
version="1.0.0"

# Options Variables
character="#"
lang="en"
language="bash"
comment_character="#"
shebang="none"
template="default"

dest_file=${@: -1}

# Translations
declare -A translations
translations=(
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
)

declare -A language_configs
language_configs["bash"]=("Bash" "#!/bin/bash" "#")
language_configs["python"]=("Python" "#!/usr/bin/env python" "#")
language_configs["perl"]=("Perl" "#!/usr/bin/env perl" "#")
language_configs["ruby"]=("Ruby" "#!/usr/bin/env ruby" "#")
language_configs["php"]=("PHP" "#!/usr/bin/env php" "#")
language_configs["java"]=("Java" "" "//")
language_configs["javascript"]=("JavaScript" "" "//")
language_configs["c"]=("C" "" "//")
language_configs["cpp"]=("C++" "" "//")
language_configs["go"]=("Go" "#!/usr/bin/env go" "//")
language_configs["rust"]=("Rust" "" "//")

Help() {
    cat << EOF
Usage: $0 [options] <file>

Description:
    This script adds a header to the specified file depending on its extension.

Options:
    -h, --help      Display this help message.
    -v, --version   Display the version of this script.
    -a, --author    Set the author name.
    -l, --language  Set the language of the file.
    -c, --comment   Set the comment character.
    -s, --shebang   Set the shebang.
    -t, --template  Set the template to use.

Examples:
    $0 file.py
    $0 file.sh
EOF
}

detect_language() {
    local extension="${dest_file##*.}"
    case $extension in
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

print_lines() {
    printf -- "$1%.0s" {1..15} >> "$2"
    echo "" >> "$2"
}

default_header() {
    local slang=${lang:-en}

    if [[ -n "$shenamg" ]]; then
        echo "${language_configs[$(detect_language "$file")][1]}" > "$dest_file"
    fi
    print_lines "$comment_character" 15 "$dest_file"
    echo "$comment_character    $(get_translation "Author" "$slang"): $user_name" >> "$dest_file"
    echo "$comment_character    $(get_translation "Creation Date" "$slang"): $(date)" >> "$dest_file"
    echo "$comment_character    $(get_translation "Description" "$slang"): " >> "$dest_file"
    print_lines "$comment_character" 15 "$dest_file"
    echo "$comment_character    $(get_translation "Version" "$slang"): 1.0" >> "$dest_file"
    echo "$comment_character    $(get_translation "Last edited by" "$slang"): " >> "$dest_file"
    print_lines "$comment_character" 15 "$dest_file"
}

write_header() {
    local file=$1
    case $template in
        default) default_header "$file" ;;
        custom) custom_header "$file" ;;
    esac
}

contains() {
    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ $element == $seeking ]]; then
            in=0
            break
        fi
    done
    return $in
}

OPTIONS=hv:a:l:c:s:t:u:
LONGOPTS=help,version,author:,language:,comment:,shebang:,template:,update

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
            echo $version
            exit;;
        -a|--author)
            username="$2"
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
                comment="$2"
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
        --)
            shift
            break;;
        *)
            echo "Error: Invalid option"
            exit 1;;
    esac
done

if [[ -n "$1" && ! "$1" =~ ^- ]]; then
    dest_file="$1"
    if [[ -f "$dest_file"]]; then
        temp_header=$(mktemp)
        write_header "$temp_header"
        sed -i "1e cat $temp_header" "$dest_file"
        rm "$temp_header"
        exit 0
    fi
    write_header "$dest_file"
else
    echo "Error: No file specified."
    Help
    exit 1
fi