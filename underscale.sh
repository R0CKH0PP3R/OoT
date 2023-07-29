#!/bin/bash

# Simple script to scale the Reloaded texture pack proportionally to the original textures.
# Some texture replacements are too big and cause stutter. A 4x scale is sufficient at 1080p.
# The script takes the source dir as the first argument and the Reloaded dir the second.
# Each PNG found in the source dir is compared against its counterpart and scaled accordingly.

# Basic checks
type mogrify >/dev/null || { echo "ImageMagick is required to use this script."; exit 1; }
[[ "$#" -ne 2 ]]  && echo "Provide source (original) and target folders respectively." && exit 1

# Scale Factor. Choose 4 or 8.
sf=4
# Output here
dir='XXXX'

underscale(){
	# Take array as first argument, target dir as second.
	local -n array="$1"
	for file in "${array[@]}"
	do
		# Store the parent folder name for later comparison 
		srcpdir="$(basename "$(dirname "$file")")"
		readarray -d '' target < <(find "$2" -name "${file##*/}" -print0)
		# There may be a number of hits. Let's find the one with the same parent:
		for hit in "${target[@]}"	
		do
			hitpdir="$(basename "$(dirname "$hit")")"
			if [[ "$hitpdir" == "$srcpdir" ]]; then
				# We have the right file. 
				# Create a save dir for it.
				mkdir -p "${dir}/${file%/*}"
				# Get widths
				srcw=$(identify -format %w "$file")
				hitw=$(identify -format %w "${hit}")
				# Scale 
				if (( hitw > srcw*sf )); then
					echo "Scaling ${hit}"
					# Preserve the colormap while scaling to avoid the unexpected.
					convert "${hit}" -scale "$((srcw*sf))" -define png:preserve-colormap=true \
							"${dir}/${file}"
				else 
					# We still want a copy of the replacement texture
					echo "Copying ${hit}"
					cp "${hit}" "${dir}/${file}"
				fi
				break
			fi
		done
	done
}

# Recursive list of files
# Just considering PNGs here - JPGs are dealt with in my 'supersharp' script.
readarray -d '' src < <(find "$1" -name '*.png' -print0)
# This is a big list. Determine number of cores to split the processing over.
cores=$(grep '^core id' /proc/cpuinfo | sort -u | wc -l)
# Add 1 below to simply account for rounding errors.
count=$((${#src[@]}/cores+1))
offset=0
# Slice the array process each slice in parallel.
for core in $(seq 1 $cores); do 
	slice=("${src[@]:$offset:$count}")
	((offset+=count))	
	underscale slice "$2" &
done
# Wait for the background tasks to complete, else the script will not exit.
wait
echo "All done." && exit 0
