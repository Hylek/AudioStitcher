#!/bin/bash

# Exit on error
set -e

# Function to cleanup temporary files on exit
cleanup() {
    if [ -d "$temp_dir" ]; then
        echo -e "\n --- Cleaning up temporary files ---"
        rm -rf "$temp_dir"
    fi
}

# Function to show spinner
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c] Processing... " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf " \r"
}

# Function to handle script exit
handle_exit() {
    echo -e "\nScript interrupted. Cleaning up..."
    cleanup
    exit 1
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is required but not installed."
        echo "Please install $1 and try again."
        exit 1
    fi
}

# Function to validate input directory
check_input_dir() {
    if [ ! -d "$input_dir" ]; then
        echo "Error: Input directory '$input_dir' not found."
        echo "Please create the directory and add your audio files."
        exit 1
    fi
}

# Function to get user input with timeout
get_user_input() {
    local prompt="$1"
    local default="$2"
    local response

    read -p "$prompt" response || true

    if [ -z "$response" ]; then
        echo "$default"
    else
        echo "$response"
    fi
}

# Function to format duration
format_duration() {
    local total_seconds=$1
    local minutes=$(( ${total_seconds%.*}/60 ))
    local seconds=$(printf "%.0f" $(echo "$total_seconds - ($minutes * 60)" | bc))

    # Pad seconds with a leading zero if less than 10
    if [ $seconds -lt 10 ]; then
        seconds="0$seconds"
    fi
    echo "${minutes}:${seconds}"
}

# Function for natural sorting of files that works across Bash versions
get_sorted_files() {
    local dir="$1"
    local IFS=$'\n'
    # Use find to get files and sort them naturally
    # The 2>/dev/null suppresses errors if no mp3 files are found
    find "$dir" -maxdepth 1 -name "*.mp3" -type f 2>/dev/null | sort -V
}

# Configuration
background_file="background.mp3"
input_dir="./input"
output_dir="./output"
final_output="final_output.mp3"
temp_dir="$output_dir/temp"

# Handle the interrupt signals to handle a graceful exit if user hits CTRL+C
trap handle_exit SIGINT SIGTERM

# Check for required commands
echo "--- Checking Prerequisites ---"
check_command "ffmpeg"
check_command "bc"

# Validate input directory
check_input_dir

# Create output and temp directories if they don't exist
mkdir -p "$temp_dir"

echo -e "\n--- Inside Out Audio Meditation Helper ---"
echo "Press Ctrl+C at any time to exit the script"
echo -e "Input directory: $input_dir\nOutput directory: $output_dir\n"

# Ask about background music
while true; do
    use_background=$(get_user_input "Do you want to include background music? (y/n) [n]: " "n")
    use_background=$(echo "$use_background" | tr '[:upper:]' '[:lower:]')
    if [[ "$use_background" =~ ^[yn]$ ]]; then
        break
    else
        echo "Please enter 'y' or 'n'"
    fi
done

# Only ask for background volume if user wants background music
if [[ "$use_background" == "y" ]]; then
    if [ ! -f "$background_file" ]; then
        echo "Error: Background music file '$background_file' not found."
        handle_exit
    fi

    while true; do
        bg_volume_percent=$(get_user_input "Enter the desired volume level for background music (1-100) [30]: " "30")
        if [[ "$bg_volume_percent" =~ ^[0-9]+$ ]] && [ "$bg_volume_percent" -ge 1 ] && [ "$bg_volume_percent" -le 100 ]; then
            bg_volume=$(echo "scale=2; $bg_volume_percent/100" | bc)
            break
        else
            echo "Please enter a number between 1 and 100"
        fi
    done
fi

# Initialize an empty array and read the sorted files
input_files=()
while IFS= read -r file; do
    input_files+=("$file")
done < <(get_sorted_files "$input_dir")

# Get file count
file_count=${#input_files[@]}

if [ $file_count -eq 0 ]; then
    echo "Error: No MP3 files found in '$input_dir'"
    exit 1
fi

echo -e "\nFound $file_count audio files in input directory (sorted numerically):"
for ((i=0; i<$file_count; i++)); do
    echo "$(($i+1)). $(basename "${input_files[$i]}")"
done

# Create an array to store delays
declare -a delays

# Collect delay times for each transition
echo -e "\n--- Setting Delays Between Clips ---"
echo "Enter delay in seconds between clips (or press Enter for default 2 seconds)"
for ((i=1; i<$file_count; i++)); do
    current_file=$(basename "${input_files[$i-1]}")
    next_file=$(basename "${input_files[$i]}")

    while true; do
        delay=$(get_user_input "Delay between '$current_file' and '$next_file' [2.0]: " "2.0")
        if [[ "$delay" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            delays[$i-1]=$delay
            break
        else
            echo "Please enter a valid number"
        fi
    done
done

# Calculate total duration for background music
echo -e "\n--- Calculating Durations ---"
total_duration=0
# Add duration of each audio file
for input_file in "${input_files[@]}"; do
    duration=$(ffprobe -i "$input_file" -show_entries format=duration -v quiet -of csv="p=0")
    total_duration=$(echo "$total_duration + $duration" | bc)
    echo "$(basename "$input_file"): ${duration}s"
done
# Add duration of all delays
for delay in "${delays[@]}"; do
    total_duration=$(echo "$total_duration + $delay" | bc)
done

echo "Total duration with delays: ${total_duration}s"

echo -e "\n--- Normalising Voice Files ---"
for input_file in "${input_files[@]}"; do
    filename=$(basename "$input_file")
    echo "Processing: $filename"

    # Audio volume normalisation
    if ! ffmpeg -i "$input_file" \
        -filter:a "compand=attacks=0.05:decays=0.1:points=-60/-80|-40/-40|-30/-30|-20/-20|0/-8|20/-6,
                  loudnorm=I=-16:TP=-1:LRA=7:print_format=json,
                  alimiter=level_in=1:level_out=1:limit=1:attack=5:release=50" \
        "$temp_dir/normalised_$filename" -y 2>/dev/null; then
        echo "Error: Failed to process $filename"
        handle_exit
    fi
done

# Create concatenation list with custom delays
echo -e "\n--- Creating Concatenation List ---"
concat_list="$temp_dir/concat_list.txt"
rm -f "$concat_list"

# Add first file
echo "file 'normalised_$(basename "${input_files[0]}")'" >> "$concat_list"

# Add remaining files with custom delay between each
for ((i=1; i<$file_count; i++)); do
    # Create delay of specified length
    if ! ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t ${delays[$i-1]} "$temp_dir/delay_${i}.mp3" -y 2>/dev/null; then
        echo "Error: Failed to create delay file"
        handle_exit
    fi

    # Add delay and next file to concat list
    echo "file 'delay_${i}.mp3'" >> "$concat_list"
    echo "file 'normalised_$(basename "${input_files[$i]}")'" >> "$concat_list"
done

# First concatenate all clips with delay
echo -e "\n--- Creating Base Audio Track ---"

# Change to temp directory before concatenation
cd "$temp_dir"

ffmpeg -f concat -safe 0 -i concat_list.txt -c:a libmp3lame -q:a 0 base_track.mp3 2>/dev/null &
show_spinner $!

# Check if the concatenation was successful
if ! wait $!; then
    echo "Error: Failed to concatenate audio files"
    cd - > /dev/null
    handle_exit
fi
cd - > /dev/null  # Return to original directory

if [[ "$use_background" == "y" ]]; then
    # Prepare background music
    echo -e "\n--- Preparing Background Music ---"

    # First get background music duration
    bg_duration=$(ffprobe -i "$background_file" -show_entries format=duration -v quiet -of csv="p=0")

    if (( $(echo "$bg_duration < $total_duration" | bc -l) )); then
        # If background music is shorter, we need to loop it
        repeats=$(echo "scale=0; $total_duration/$bg_duration + 1" | bc)
        ffmpeg -stream_loop $repeats -i "$background_file" -t $total_duration \
            -filter:a "volume=$bg_volume" "$temp_dir/background_prepared.mp3" 2>/dev/null &

        show_spinner $!

        # Check if the preparation was successful
        if ! wait $!; then
            echo "Error: Failed to prepare background music"
            handle_exit
        fi
    else
        # If background music is longer, just trim it
        ffmpeg -i "$background_file" -t $total_duration \
            -filter:a "volume=$bg_volume" "$temp_dir/background_prepared.mp3" 2>/dev/null &

        show_spinner $!

        # Check if the preparation was successful
        if ! wait $!; then
            echo "Error: Failed to prepare background music"
            handle_exit
        fi
    fi

    # Mix the base track with background music
    echo -e "\n--- Mixing Final Audio ---"
    # Remove existing output file if it exists
    if [ -f "$output_dir/$final_output" ]; then
        rm "$output_dir/$final_output"
    fi

    ffmpeg -i "$temp_dir/base_track.mp3" -i "$temp_dir/background_prepared.mp3" \
        -filter_complex amix=inputs=2:duration=first:weights=1.0.$bg_volume \
        "$output_dir/$final_output" 2>/dev/null &

    show_spinner $!

    # Check if the mixing was successful
    if ! wait $!; then
        echo "Error: Failed to mix final audio"
        handle_exit
    fi
else
    # If no background music, just move base track to final output
    if [ -f "$output_dir/$final_output" ]; then
        rm "$output_dir/$final_output"
    fi
    mv "$temp_dir/base_track.mp3" "$output_dir/$final_output"
fi

# Clean up all temporary files and directory
cleanup

echo -e "\n--- Process Complete! ---"
echo "Final output file: $output_dir/$final_output"

# Get exact duration from final output file
final_duration=$(ffprobe -i "$output_dir/$final_output" -show_entries format=duration -v quiet -of csv="p=0")
formatted_duration=$(format_duration $final_duration)
echo "Meditation Duration: ${formatted_duration}"
