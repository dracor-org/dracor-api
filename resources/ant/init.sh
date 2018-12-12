#!/bin/#!/usr/bin/env bash

bash $2/bin/startup.sh &

while [ $(curl -I -s http://localhost:$1 | grep -c "200 OK") == 0 ];
do
  sleep 2s
done
bash $2/bin/shutdown.sh -u admin -p ""

exit 0
