#!/bin/bash

# Bash script to seamlessly rescale static backgrounds in OoT, specifically SoH.
# Images aren't simply rescaled as they are, they are first stripped of their 
# padding and formed into a panoramic montage before being scaled by an AI model.
# The panorama is then sliced up into constituent parts and padding reapplied. 
# Scaling this way gives the model more context and avoids visible seams in game.

# The difference with this script over the non-2px variant is that this one mirrors 
# an additional 2px at the padded borders and then scales down to the correct size.
# This 'should' provide a more seamless experience in game, but YMMV - try it out.

# Check dependancies. You can get a portable release of realesrgan from GitHub:
# https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan
type mogrify >/dev/null || { echo "Please install ImageMagick to use this script."; exit 1; }
type realesrgan-ncnn-vulkan >/dev/null || { echo "realesrgan-ncnn-vulkan not in PATH"; exit 1; }

# We need a directory to process (can be '.' but I don't assume here).
[[ ! -d "$1" ]]  && echo "No directory provided." && exit 1
[[ "$#" -ne 1 ]] && echo "Please, one at a time." && exit 1

# Create temporary dirs & vars. I make an effort to clean these up as we go.
tmpdir='/tmp/ncnn'
scaled="$tmpdir"/scaled
mkdir -p "$scaled"

ncnn(){
	# With realesrgan in PATH, we just need to provide an image ($2) and a model ($1).
	# Good models are 'ultrasharp', 'ultramix_balanced', 'remacri' & 'ealesrgan-x4plus-anime'. 
	# Find them at: https://github.com/upscayl/upscayl/tree/main/resources/models
	# Check the model database for more info: https://upscale.wiki/wiki/Model_Database
	
	# Work on a duplicate file in case of error. Copy back after checking log.
	cp "$2" "$scaled"
	file="${scaled}/${2##*/}"
	realesrgan-ncnn-vulkan -i "$file" -o "$file" -n "$1" 2>&1 | tee "$tmpdir"/.log
	# And because it ploughs through errors and provides no exit status...	
	failed=$(cat "$tmpdir"/.log | grep failed)
	[[ -n $failed ]] && ncnn "$1" "$2" || { cp "$file" "$2" && rm "$file"; }
}

msg(){
	# Simple cleanup & message handler
	rm -r "$tmpdir"
	[[ $1 -eq 0 ]] && echo "All done." && exit 0
	[[ $1 -eq 1 ]] && echo "Montage Failed. Process halted." && exit 1
	[[ $1 -eq 2 ]] && echo "Slicing Failed. Process halted." && exit 1
}

# Recursive list of directories. There has to be at least one.
readarray -d '' dirs < <(find "$1" -type d -print0)
# Enter each directory in turn.
for dir in "${dirs[@]}"
do
	# Generate a list of files to process within this directory.
	readarray -d '' fnd < <(find "$dir" -maxdepth 1 -name '*.png' -print0)

	# Some directories may not have any pngs. Only proceed if they do.
	if (( ${#fnd[@]} )); then
		# As the first png wont be numbered, it will be found last. To put them in order, 
		# create a new array starting with the last png before removing it from the first array.
		pngs=("${fnd[-1]}") && unset fnd[-1]
		# And add the remaining pngs.
		for f in "${fnd[@]}"; do pngs+=("$f"); done
		
		# Remove the margins/padding 
		for png in "${pngs[@]}"; do mogrify -crop 253x249+0+0 "$png"; done
		# Create panoramic montage for seamless upscale.
		montage "${pngs[@]}" -tile "${#pngs[@]}"x1 -geometry +0+0 "$tmpdir"/pan.png
		
		# Check prior success & upscale with chosen model.
		[[ $? -eq 0 ]] && ncnn 'ultrasharp' "$tmpdir"/pan.png || msg 1
		
		# Determine the size of each slice. Offset is used to keep track of where we are.
		panw=$(identify -format %w "$tmpdir"/pan.png)
		width=$((panw/${#pngs[@]}))
		height=$(identify -format %h "$tmpdir"/pan.png)
		offset=0
		
		# Mirror the panorama along the horizontal plane & crop as to only include an extra 2px.
		convert ${tmpdir}/pan.png -background transparent -extent ${panw}x$((height*2)) \
				\( +clone -flip \) -composite -crop ${panw}x$((height+2))+0+0 ${tmpdir}/pan.png
		
		# Take a slice for each image & overwrite original		
		for png in "${pngs[@]}"
		do
			# Mirror each slice along the vertical plane & crop as to only include an extra 2px.
			# Finally, scale down to pre-mirrored size, i.e -2px in each dimension & add padding.
			convert ${tmpdir}/pan.png -crop ${width}x$((height+2))+${offset}+0 +repage - | 
			convert - -filter sinc -background transparent -extent $((width*2))x$((height+2)) \
					\( +clone -flop \) -composite -crop $((width+2))x$((height+2))+0+0 \
					-resize ${width}x${height}! -background black -extent 1024x1024 "$png"
			
			# Check that it worked. If so, increment the offset and continue.
			[[ $? -eq 0 ]] && offset=$((offset+width)) || msg 2
		done
	fi
	
	# JPGs are much easier to process as there is only one jpg per scene. 
	# Therefore, seams are irrelevant and we can go straight to scaling.
	readarray -d '' jpgs < <(find "$dir" -maxdepth 1 -name '*.jpg' -print0)
	[[ ${#jpgs[@]} -gt 0 ]] && for jpg in "${jpgs[@]}"; do ncnn 'ultrasharp' "$jpg"; done 
	
done

msg 0
