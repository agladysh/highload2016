#!/bin/bash

set -e

ROOT="${BASH_SOURCE[0]}";
if([ -h "${ROOT}" ]) then
  while([ -h "${ROOT}" ]) do ROOT=`readlink "${ROOT}"`; done
fi
ROOT=$(cd `dirname "${ROOT}"` && pwd)

cd ${ROOT}

echo "--> Rebuilding dockers" >&2
docker-compose up -d --build --remove-orphans

echo "--> DONE"
