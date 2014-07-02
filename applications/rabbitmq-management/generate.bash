#!/bin/bash

set -e -E -u -o pipefail -o noclobber -o noglob -o braceexpand || exit 1
trap 'printf "[ee] failed: %s\n" "${BASH_COMMAND}" >&2' ERR || exit 1

test "${#}" -eq 0

cd -- "$( dirname -- "$( readlink -e -- "${0}" )" )"
test -d "${_generate_outputs}"

VERSION=2.3.1

cp -T ./repositories/rabbitmq-management/ebin/rabbit_management.app.in "${_generate_outputs}/rabbit_management.app"

sed -r -e 's!%%VSN%%!'"${VERSION}"'!g' -i "${_generate_outputs}/rabbit_management.app"

exit 0
