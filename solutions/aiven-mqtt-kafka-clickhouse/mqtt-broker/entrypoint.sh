#!/bin/sh
# Generate the Mosquitto password file from env vars at startup so the
# credentials never live in the image and no bind mount is needed.
set -eu

: "${MQTT_USERNAME:?MQTT_USERNAME must be set}"
: "${MQTT_PASSWORD:?MQTT_PASSWORD must be set}"

touch /mosquitto/config/passwd
mosquitto_passwd -b /mosquitto/config/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
chown mosquitto:mosquitto /mosquitto/config/passwd
chmod 600 /mosquitto/config/passwd

exec mosquitto -c /mosquitto/config/mosquitto.conf
