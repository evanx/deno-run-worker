#!/bin/bash
set -eu
cd ${WORKER_REPO}/dm
[ -f cli.ts ]
ref=`openssl rand 6 -base64`
echo "ref=${ref}" 
deno run -A ./cli.ts xadd-req ${ref} && 
  redis-cli rpop res:${ref} 4
