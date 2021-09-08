#!/bin/bash
if [ $# -lt 1 ]; then
    echo "usage: batch.sh INPUT [AUTO_EDITOR_ARGS ...]"
    exit 1
fi

# generate uuid for this run
UUID=$(cat /dev/random | tr -dc "[:alnum:]" | head -c 10)
# make temp dir
# TODO: make arg for temp dir location
TEMPDIR=/tmp/auto-editor-temp-$UUID
mkdir $TEMPDIR

LENGTH=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1")

# get video extension
NAME=$(basename -- "$1")
EXT="${NAME##*.}"
NAME="${NAME%.*}"
echo $EXT
echo $NAME

JOBS=$(nproc)
# JOBS=6
SLICES=$(nproc)

echo "Cutting input video into slices"

ffmpeg -v error -v error -i "$1" -c copy -map 0 -segment_time $(bc <<< "$LENGTH / $SLICES") -f segment -reset_timestamps 1 $TEMPDIR/slice_%05d.$EXT


echo "made $(ls -l $TEMPDIR/* | wc -l ) slices"
# ls $TEMPDIR
echo "starting $JOBS jobs"


# for CPU encoding
ls $TEMPDIR/slice_*.$EXT | parallel -j $JOBS python3 -m auto_editor {} --no-open --video_codec libx264 --has_vfr no

# for GPU encoding
# TODO: cli flag to enable switching between these
# ls $TEMPDIR/slice_*.$EXT | parallel -j $JOBS python3 -m auto_editor {} --no-open --video_codec h264_nvenc --has_vfr no

echo "jobs done"
# ls $TEMPDIR
for f in $TEMPDIR/*_ALTERED.$EXT; do echo "file '$f'" >> $TEMPDIR/cat_list.txt; done
cat $TEMPDIR/cat_list.txt
ffmpeg -f concat -safe 0 -i $TEMPDIR/cat_list.txt -c copy $(dirname "$1")/"$NAME"_ALTERED.mp4
 

# clean up temp dir
# TODO: flag arg for this, potentially useful for testing purposes
rm -rf $TEMPDIR

