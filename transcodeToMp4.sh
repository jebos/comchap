#!/usr/bin/env bash

ldPath=${LD_LIBRARY_PATH}
unset LD_LIBRARY_PATH

exitcode=0

ffmpegPath="ffmpeg"
ffprobePath="avprobe"

command -v $ffmpegPath >/dev/null 2>&1 || { echo >&2 "I require $ffmpegPath but it's not installed.  Aborting."; exit 1; }
command -v $ffprobePath >/dev/null 2>&1 || { echo >&2 "I require $ffprobePath but it's not installed.  Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "I require foo bujq but's not installed.  Aborting."; exit 1; }
command -v bc >/dev/null 2>&1 || { echo >&2 "I require bc but it's not installed.  Aborting."; exit 1; }

if [[ $# -lt 1 ]]; then

  exename=$(basename "$0")

  echo "Converts ts or mkv to mp4 keeping subtitles and all audio, audio is converted (mp2->acc, ac3 -> acc)"
  echo ""
  echo "Usage: $exename infile"
  echo "Options:"
  echo " --dry-run       Do not convert, only print command"
  echo " --start-second  Provide start point in seconds"
  echo " --end-second    Povide end point in seconds (NOT duration, seconds from start of original source)"
  echo " --start-time    Time in format 00:00:00"
  echo " --end-time      Time in format 00:00:00"
  echo " --h264Preset    Change preset from 'ultrafast' to something you like"
  echo "Output: infile.mp4"
  exit 1
fi
dryrun=false
startsecond=0
endfsecond=0
h264Preset=medium

while [[ $# -gt 1 ]]
do
key="$1"
case $key in
    --dry-run)
    dryrun=true
    shift
    ;;
    --start-second=*)
    startsecond="${key#*=}"
    shift
    ;;
    --end-second=*)
    endsecond="${key#*=}"
    shift
    ;;
    --start-time=*)
    startsecond=$(echo "${key#*=}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
    shift
    ;;
    --end-time=*)
    endsecond=$(echo "${key#*=}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
    shift
    ;;
    --h264Preset=*)
    h264Preset="${key#*=}"
    shift
    ;;
    *)
    break
    ;;
esac

done

filename=$1

resolution=`$ffprobePath -v error -select_streams v:0 -show_entries stream=width,height -of json=c=0 "$filename" | jq -r '.streams[] | "\(.width)x\(.height)"'`
numberOfAudioStreams=`$ffprobePath  -v error -select_streams a -show_entries stream=index -of json=c=0 "$filename"  | jq -r '.streams | length'`
numberOfSubtitleStreams=`$ffprobePath -v error -select_streams s -show_entries stream=index -of json=c=0 "$filename"  | jq -r '.streams | length'`

audio=""
subtitle=""

for audioStream in $(seq 1 $numberOfAudioStreams)
do
  internalASNB=$(($audioStream-1))
  streamCodec=`$ffprobePath -v error -select_streams a:$internalASNB -show_entries stream=codec_name -of json=c=0 "$filename" | jq -r '.streams[] | "\(.codec_name)"'`
  
  if [ "$streamCodec" == "ac3" ] || [ "$streamCodec" == "mp2" ]; then
    audio="$audio -acodec aac -strict experimental -map a:$internalASNB"
  fi
done

for subtitleStream in $(seq 1 $numberOfSubtitleStreams)
do
  internalSubtitleStream=$(($subtitleStream-1))
  streamCodec=`$ffprobePath -v error -select_streams s:$internalSubtitleStream -show_entries stream=codec_name -of json=c=0 "$filename" | jq -r '.streams[] | "\(.codec_name)"'`
  echo "$ffprobePath -v error -select_streams s:$internalSubtitleStream -show_entries stream=codec_name -of json=c=0 \"$filename\" | jq -r '.streams[] | \"\(.codec_name)\"'"
  echo "$streamCodec"

  if [ "$streamCodec" == "srt" ]; then
    subtitle="$subtitle -scodec mov_text -map s:$internalSubtitleStream"
  elif [ "$streamCodec" == "dvbsub" ]; then
    subtitle="$subtitle -scodec dvdsub -map s:$internalSubtitleStream -s $resolution"
  fi
  echo "$subtitle"
done

duration=`echo "$endsecond" "$startsecond" | awk  '{printf "%f", $1 - $2}'`

startEnd=""
if [ $(echo "$duration > 0"|bc) -eq 1 ]; then
  startEnd="-ss $startsecond -t $duration"
fi
echo "avconv -i \"$filename\" -f ffmetadata -y \"$filename.txt\""
echo "avconv -canvas_size $resolution -threads auto $startEnd -i \"$filename\" -i \"$filename.txt\" -map_metadata 1 -vcodec libx264 -map v:0 -preset $h264Preset -tune film -profile:v high -level 41 $audio $subtitle -y \"$filename.mp4\""
if ! $dryrun; then
  avconv -i "$filename" -f ffmetadata -y "$filename.txt"
  avconv -canvas_size $resolution -threads auto $startEnd -i "$filename" -i "$filename.txt" -map_metadata 1 -vcodec libx264 -map v:0 -preset $h264Preset -tune film -profile:v high -level 41 $audio $subtitle -y "$filename.mp4"
fi

echo "------------"
echo ""
