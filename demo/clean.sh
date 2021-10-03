#!/bin/bash
set -eu

echo "WORKER_TYPE: ${WORKER_TYPE:=demo-worker}"

for workerId in `
  redis-cli lrange ${WORKER_TYPE}:started:q 0 9
`
do
  echo "Clean started worker: ${workerId}" reply:`
    redis-cli del ${WORKER_TYPE}:${workerId}:h
  `
done

for workerId in 1 2 3 4 
do
  echo "Clean worker: ${workerId}" reply:`
    redis-cli del ${WORKER_TYPE}:${workerId}:h
  `
done

sleep 2

for key in \
  ${WORKER_TYPE}:h \
  ${WORKER_TYPE}:start:q \
  ${WORKER_TYPE}:started:q \
  ${WORKER_TYPE}:req:x \
  ${WORKER_TYPE}:res:x
do
  echo "del ${key}" reply:`
    redis-cli del "${key}"
  `
done

