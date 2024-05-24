#!/bin/bash

api=:8080/exist/restxq/v1
secret='qwerty'
path=$(dirname $0)
payload_file=$path/webhook.4.json

signature=$(node $path/sign.js $secret $payload_file)

echo $signature

http -a admin: POST $api/webhook/github \
  user-agent:GitHub-Hookshot/ \
  x-github-event:push \
  x-github-delivery:xyz-$RANDOM \
  x-hub-signature:$signature \
  < $payload_file
