#!/bin/bash

# Function to get next letter sequence
get_next_letter_sequence() {
    local current="$1"
    if [ -z "$current" ]; then
        echo "a"
        return
    fi

    # Convert to next sequence
    local length=${#current}
    local last_char="${current: -1}"
    local prefix="${current:0:$((length-1))}"

    if [ "$last_char" = "z" ]; then
        if [ -z "$prefix" ]; then
            echo "aa"
        else
            local next_prefix=$(get_next_letter_sequence "$prefix")
            echo "${next_prefix}a"
        fi
    else
        local next_char=$(echo "$last_char" | tr "a-y" "b-z")
        echo "$prefix$next_char"
    fi
}

# Function to display script usage
show_usage() {
    echo "Usage: $0 [options] <directory>"
    echo "Options:"
    echo "  -b, --base TEXT     Set base name for files (replaces original filename)"
    echo "  -p, --prefix TEXT   Add prefix to filenames"
    echo "  -s, --suffix TEXT   Add suffix to filenames (before extension)"
    echo "  -r, --replace OLD NEW    Replace OLD text with NEW in filenames"
    echo "  -n, --number START  Add sequential numbers starting from START"
    echo "  -a, --alpha        Use alphabetic sequence instead of numbers (a,b,c...aa,ab,ac...)"
    echo "  -l, --lowercase     Convert filenames to lowercase"
    echo "  -u, --uppercase     Convert filenames to uppercase"
    echo "  -d, --dry-run      Show what would be done without actually renaming"
    echo "  -h, --help         Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -p 'vacation_' -n 1 ./photos"
    echo "  $0 -r 'IMG' 'photo' ./pictures"
    echo "  $0 -b 'clip' -p 'stress_' -a ./input"
    exit 1
}

# Initialize variables
BASE_NAME=""
PREFIX=""
SUFFIX=""
REPLACE_OLD=""
REPLACE_NEW=""
START_NUMBER=""
USE_ALPHA=false
LOWERCASE=false
UPPERCASE=false
DRY_RUN=false
DIRECTORY=""
CURRENT_LETTER=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -b|--base)
            BASE_NAME="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        -r|--replace)
            REPLACE_OLD="$2"
            REPLACE_NEW="$3"
            shift 3
            ;;
        -n|--number)
            START_NUMBER="$2"
            shift 2
            ;;
        -a|--alpha)
            USE_ALPHA=true
            shift
            ;;
        -l|--lowercase)
            LOWERCASE=true
            shift
            ;;
        -u|--uppercase)
            UPPERCASE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            DIRECTORY="$1"
            shift
            ;;
    esac
done

# Check if directory is provided
if [ -z "$DIRECTORY" ]; then
    echo "Error: Directory not specified"
    show_usage
fi

# Check if directory exists
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' does not exist"
    exit 1
fi

# Counter for sequential numbering
counter=$START_NUMBER

# Create an array of files in alphabetical order
files=()
while IFS= read -r -d $'\0' file; do
    files+=("$file")
done < <(find "$DIRECTORY" -maxdepth 1 -type f -print0 | sort -z)

# Process files in sorted order
for file in "${files[@]}"; do
    # Get the directory, filename, and extension
    dir=$(dirname "$file")
    filename=$(basename "$file")
    extension="${filename##*.}"
    basename="${filename%.*}"

    # Initialize new filename
    if [ ! -z "$BASE_NAME" ]; then
        new_basename="$BASE_NAME"
    else
        new_basename="$basename"
    fi

    # Apply replacements if specified and BASE_NAME is not set
    if [ -z "$BASE_NAME" ] && [ ! -z "$REPLACE_OLD" ]; then
        new_basename="${new_basename//$REPLACE_OLD/$REPLACE_NEW}"
    fi

    # Apply case conversion
    if [ "$LOWERCASE" = true ]; then
        new_basename=$(echo "$new_basename" | tr '[:upper:]' '[:lower:]')
    elif [ "$UPPERCASE" = true ]; then
        new_basename=$(echo "$new_basename" | tr '[:lower:]' '[:upper:]')
    fi

    # Add prefix if specified
    if [ ! -z "$PREFIX" ]; then
        new_basename="${PREFIX}${new_basename}"
    fi

    # Add suffix if specified
    if [ ! -z "$SUFFIX" ]; then
        new_basename="${new_basename}${SUFFIX}"
    fi

    # Add sequence (number or letter)
    if [ ! -z "$START_NUMBER" ]; then
        new_basename="${new_basename}${counter}"
        ((counter++))
    elif [ "$USE_ALPHA" = true ]; then
        CURRENT_LETTER=$(get_next_letter_sequence "$CURRENT_LETTER")
        new_basename="${new_basename}${CURRENT_LETTER}"
    fi

    # Construct new filename with extension
    new_filename="${new_basename}.${extension}"
    new_filepath="${dir}/${new_filename}"

    # Perform or simulate the rename
    if [ "$DRY_RUN" = true ]; then
        echo "Would rename: $filename -> $new_filename"
    else
        if [ "$filename" != "$new_filename" ]; then
            mv -- "$file" "$new_filepath"
            echo "Renamed: $filename -> $new_filename"
        fi
    fi
done

echo "File renaming completed!"
