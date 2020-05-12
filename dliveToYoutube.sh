#!/bin/bash
#Channel Info
dliveChannel='https://dlive.tv/owenbenjamincomedy'
description='Check out https://dlive.tv/owenbenjamincomedy. Support Owen with a kind letter or supplies at PO Box 727 Gig Harbor WA 98335. Support Owen by signing up to https://unauthorized.tv for more content & access to Social Galactic. Bear forum at https://bearsaloon.com and meetup site at https://bearvibe.com Clips shown with fair use.'

#YouTube APIKey
apiKey='39(?)charsHere'

#Refreshing access token
client_id='46(?)charsHere.apps.googleusercontent.com'
client_secret='24(?)charsHere'
refresh_token='103(?)charsHere'


while true
do
livestreaming=""
while [ -z $livestreaming ]
do
    sleep 1
    livestreaming=$( curl $dliveChannel | grep "<img src=\"/img/live.4729dfd6.svg" )
    echo "Sleeping 15s"
    sleep 14
done
echo "Owen is live!"
livestreaming=""
title=$( youtube-dl $dliveChannel --get-title | tr -d '"' | tr -d \')
title=${title::-17}
title=${title:0:82}
title="$title "$(date '+%F %T');
title=${title::-2}
echo "$title is the title"
streamEncoding=`youtube-dl $dliveChannel -g`
echo $streamEncoding
echo ".m3u8 url streamEncoding found via youtube-dl"

#refresh access token
refreshaccesstokenresponse=$( curl \
--request POST \
--data "client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token&grant_type=refresh_token" \
https://accounts.google.com/o/oauth2/token )
accessToken=$( jq -r '.access_token' <<< $refreshaccesstokenresponse )
echo 'Access token is '$accessToken
echo 'Refreshed access token'

sleep 3

#insertbroadcast
currentTime=`date -Is`
insertbroadcastresponse=$( curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet%2Cstatus%2CcontentDetails&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data "{\"snippet\":{\"title\":\"$title\",\"scheduledStartTime\":\"$currentTime\",\"description\":\"$description\"},\"status\":{\"privacyStatus\":\"public\",\"selfDeclaredMadeForKids\":false},\"contentDetails\":{\"enableClosedCaptions\":true,\"enableContentEncryption\":true,\"enableDvr\":true,\"recordFromStart\":true,\"startWithSlate\":false}}" \
  --compressed )
echo $insertbroadcastresponse
broadcastId=$( jq -r '.id' <<< $insertbroadcastresponse )
echo 'broadcastId is '$broadcastId
echo 'Broadcast inserted'

sleep 3

#insertlivestream
insertlivestreamresponse=$( curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveStreams?part=snippet%2Ccdn%2CcontentDetails&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data "{\"snippet\":{\"title\":\"$title\",\"description\":\"$description\"},\"cdn\":{\"frameRate\":\"30fps\",\"ingestionType\":\"rtmp\",\"resolution\":\"720p\"},\"contentDetails\":{\"isReusable\":true}}" \
  --compressed )
echo $insertlivestreamresponse
ingestionAddress=$( jq -r '.cdn.ingestionInfo.ingestionAddress' <<< $insertlivestreamresponse )
streamName=$( jq -r '.cdn.ingestionInfo.streamName' <<< $insertlivestreamresponse )
streamId=$( jq -r '.id' <<< $insertlivestreamresponse )
echo 'ingestionAddress is '$ingestionAddress
echo 'streamName is '$streamName
echo 'streamId is '$streamId
echo 'Livestream inserted'

sleep 25
echo 'sleeping 25s after binding stream'

#bindstream
curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveBroadcasts/bind?id=$broadcastId&part=snippet&streamId=$streamId&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --compressed

echo 'Stream bound to broadcast'
youtubeDestinationUrl=$ingestionAddress'/'$streamName
echo 'destinationUrl is '$youtubeDestinationUrl

#start stream to youtube
ffmpeg -re -i $streamEncoding \
 -c:v copy -c:a aac -ar 44100 -ab 128k -ac 2 \
 -strict -2 -flags +global_header -bsf:a aac_adtstoasc \
 -bufsize 3000k -f flv \
 -preset slow $youtubeDestinationUrl &
youtube_ffmpeg_pid=$!
echo "Started streaming to secondary platform!"

echo 'sleeping 25s to prepare for transition to testing'
sleep 25

#youtube transition to testing
curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveBroadcasts/transition?broadcastStatus=testing&id=$broadcastId&part=snippet%2Cstatus&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --compressed

#youtube transition to live
sleep 25
echo 'sleeping 25s to prepare for transition to live'
curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveBroadcasts/transition?broadcastStatus=live&id=$broadcastId&part=snippet%2Cstatus&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --compressed

wait $youtube_ffmpeg_pid
echo "Finished streaming to youtube!"

#refresh the youtube access token again in case it's expired before transitioning to complete
refreshaccesstokenresponse=$( curl \
--request POST \
--data "client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token&grant_type=refresh_token" \
https://accounts.google.com/o/oauth2/token )
accessToken=$( jq -r '.access_token' <<< $refreshaccesstokenresponse )
echo 'Access token is '$accessToken
echo 'Refreshed access token'

#youtube transition to complete
curl --request POST \
  "https://www.googleapis.com/youtube/v3/liveBroadcasts/transition?broadcastStatus=complete&id=$broadcastId&part=snippet%2Cstatus&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --compressed

sleep 10

#youtube check stream status just for fun
curl \
  "https://www.googleapis.com/youtube/v3/liveStreams?part=snippet%2Ccdn%2CcontentDetails%2Cstatus&id=$streamId&key=$apiKey" \
  --header "Authorization: Bearer $accessToken" \
  --header 'Accept: application/json' \
  --compressed

done
