#!/bin/bash
set -eu

echo "WORKER_CLASS: ${WORKER_CLASS:=deno-date-iso}"

for workerId in `
  redis-cli lrange ${WORKER_CLASS}:started:q 0 9
`
do
  echo "Clean started worker: ${workerId}" reply:`
    redis-cli del ${WORKER_CLASS}:${workerId}:h
  `
done

for workerId in 1 2 3 4 
do
  echo "Clean worker: ${workerId}" reply:`
    redis-cli del ${WORKER_CLASS}:${workerId}:h
  `
done

sleep 2

for key in \
  ${WORKER_CLASS}:h \
  ${WORKER_CLASS}:start:q \
  ${WORKER_CLASS}:started:q \
  ${WORKER_CLASS}:req:x \
  ${WORKER_CLASS}:res:x
do
  echo "del ${key}" reply:`
    redis-cli del "${key}"
  `
done

