#!/bin/bash
set -eu
cd ${LOCAL_WORKER_REPO}/deno-run-worker
[ -f cli.ts ]
ref=`openssl rand 6 -base64`
echo "ref=${ref}" 
deno run -A ./cli.ts xadd-req ${ref} && 
  redis-cli rpop res:${ref} 4
