#!/usr/bin/env bash

set -euo pipefail

# Run as systemd service
#
# See also:
#   - https://www.linode.com/docs/quick-answers/linux/start-service-at-boot/
#   - https://gist.github.com/awseward/100cec20c2523b0c5c5bc083dd114ae8/20da7082070affdb259013b00abbdba7d4352ddc
#   - https://web.archive.org/web/20200628142802/https://ma.ttias.be/auto-restart-crashed-service-systemd/
#

readonly api_url='https://call-status.herokuapp.com/api/people'
readonly topic_people='call-status/people'
readonly topic_heartbeat='call-status/heartbeat/latest'

echo "Started at $(date --iso-8601=s)" | systemd-cat -t call_status_poll -p info

while true; do
  now_s="$(date +%s)"
  heartbeat="$(mosquitto_sub -t "${topic_heartbeat}" -C 1 -W 1)"

  systemd-cat -t call_status_poll -p info <<< "heartbeat: ${heartbeat}"

  if [ "${heartbeat}" == '' ]; then
    systemd-cat -t call_status_poll -p info <<< 'no heartbeat; doing nothing…'
  else
    systemd-cat -t call_status_poll -p info <<< "now_s: ${now_s}"
    heartbeat_s="$(date -d "${heartbeat}" +%s)"
    systemd-cat -t call_status_poll -p info <<< "heartbeat_s: ${heartbeat_s}"
    diff_s="$(( now_s - heartbeat_s ))"
    systemd-cat -t call_status_poll -p info <<< "diff_s: ${diff_s}"

    if [ $diff_s -gt 10 ]; then
      systemd-cat -t call_status_poll -p info <<< 'more than 10s since last heartbeat; doing nothing…'
    else
      systemd-cat -t call_status_poll -p info <<< "polling: ${api_url} >> ${topic_people}"
      echo "${api_url}" \
        | xargs -t curl -s \
        | mosquitto_pub -h localhost -t "${topic_people}" -r -s
    fi
  fi

  sleep 5
done