#!/bin/bash
while true; do
  #~/metrics/get_metrics.sh  
  ~/metrics/get_metrics.sh  > /var/www/html/metrics.json
  sleep 5
done
