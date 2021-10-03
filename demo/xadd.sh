#!/bin/bash
set -eu
redish() { 
  deno run -A ../deno-redish/main.ts "${@}" 
}
[ -f cli.ts ]
ref=`openssl rand 6 -hex`
echo "ref=${ref}" 
deno run -A ./cli.ts xadd-req ${ref} &&
  redis-cli rpop res:${ref} 4 |
  jq '.'
redish ${ref}
