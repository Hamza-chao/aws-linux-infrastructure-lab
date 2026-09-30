#!/bin/bash

result=0

if systemctl is-active --quiet nginx; then
  echo "Pass: Nginx is running"
else
  echo "Fail: Nginx is stopped"
  result=1
fi

if curl --fail --silent --show-error --max-time 5 --output /dev/null http://localhost; then
  echo "Pass: HTTP request succeeded"
else
  echo "Fail: HTTP request failed"
  result=1
fi

echo "Root filesystem disk usage:"
df -h /

exit "$result"
