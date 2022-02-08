FROM alpine:3.15

RUN apk add --no-cache curl jq bash
ADD node_monitor.sh /usr/local/bin

ENTRYPOINT node_monitor.sh
