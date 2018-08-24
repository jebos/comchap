#!/usr/bin/env bash

ldPath=${LD_LIBRARY_PATH}
unset LD_LIBRARY_PATH

exitcode=0

ffmpegPath="ffmpeg"
ffprobePath="avprobe"

if [[ $# -lt 1 ]]; then

  exename=$(basename "$0")

  echo "Converts ts or mkv to mp4 keeping subtitles and all audio, audio is converted (mp2->acc, ac3 -> acc)"
  echo ""
  echo "Usage: $exename infile"
  echo "Output: infile.mp4"
  exit 1
fi
dryrun=false
startframe=0
endframe=0

while [[ $# -gt 1 ]]
do
key="$1"
case $key in
    --dry-run)
    dryrun=true
    shift
    ;;
    --start-frame=*)
    startframe="${key#*=}"
    shift
    ;;
    --end-frame=*)
    endframe="${key#*=}"
    shift
    ;;
    --start-time=*)
    startframe=$(echo "${key#*=}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
    shift
    ;;
    --stop-time=*)
    endframe=$(echo "${key#*=}" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
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
  echo "STREAM CODEC: $streamCodec"

  if [ "$streamCodec" == "ac3" ] || [ "$streamCodec" == "mp2" ]; then
    audio="$audio -acodec aac -strict experimental -map a:$internalASNB"
  fi
done

for subtitleStream in $(seq 1 $numberOfSubtitleStreams)
do
  internalSubtitleStream=$(($subtitleStream-1))
  streamCodec=`$ffprobePath -v error -select_streams s:$internalSubtitleStream -show_entries stream=codec_name -of json=c=0 "$filename" | jq -r '.streams[] | "\(.codec_name)"'`
  echo "$ffprobePath -v error -select_streams s:$internalSubtitleStream -show_entries stream=codec_name -of json=c=0 \"$filename\" | jq -r '.streams[] | \"\(.codec_name)\"\'"
  echo "$steamCodec"

  if [ "$streamCodec" == "srt" ]; then
    subtitle="$subtitle -scodec mov_text -map s:$internalSubtitleStream"
  else
    subtitle="$subtitle -scodec dvdsub -map s:$internalSubtitleStream -s $resolution"
  fi
done

duration=`echo "$endframe" "$startframe" | awk  '{printf "%f", $1 - $2}'`

startEnd=""
if [ $(echo "$duration > 0"|bc) -eq 1 ]; then
  startEnd="-ss $startframe -t $duration"
fi
echo "avconv -i \"$filename\" -f ffmetadata -y \"$filename.txt\""
echo "avconv -canvas_size $resolution -threads auto -i \"$filename\" -i \"$filename.txt\" -map_metadata 1 $startEnd -vcodec libx264 -map v:0 -preset slow -tune film -profile:v high -level 41 $audio $subtitle -y \"$filename.mp4\""
if ! $dryrun; then
  avconv -i "$filename" -f ffmetadata -y "$filename.txt"
  avconv -canvas_size $resolution -threads auto -i "$filename" -i "$filename.txt" -map_metadata 1 $startEnd -vcodec libx264 -map v:0 -preset slow -tune film -profile:v high -level 41 $audio $subtitle -y "$filename.mp4"
fi

echo "------------"
echo ""
