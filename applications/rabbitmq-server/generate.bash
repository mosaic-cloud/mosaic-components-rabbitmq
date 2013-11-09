#!/bin/bash

set -e -E -u -o pipefail -o noclobber -o noglob -o braceexpand || exit 1
trap 'printf "[ee] failed: %s\n" "${BASH_COMMAND}" >&2' ERR || exit 1

test "${#}" -eq 0

cd -- "$( dirname -- "$( readlink -e -- "${0}" )" )"
test -d ./.generated

VERSION=2.3.1

PYTHONPATH=./repositories/rabbitmq-codegen \
python2 ./repositories/rabbitmq-server/codegen.py \
		header --ignore-conflicts \
		./repositories/rabbitmq-codegen/amqp-rabbitmq-0.9.1.json \
		./repositories/rabbitmq-codegen/amqp-rabbitmq-0.8.json \
		./.generated/rabbit_framing.hrl

PYTHONPATH=./repositories/rabbitmq-codegen \
python2 ./repositories/rabbitmq-server/codegen.py \
		body \
		./repositories/rabbitmq-codegen/amqp-rabbitmq-0.9.1.json \
		./.generated/rabbit_framing_amqp_0_9_1.erl

PYTHONPATH=./repositories/rabbitmq-codegen \
python2 ./repositories/rabbitmq-server/codegen.py \
		body \
		./repositories/rabbitmq-codegen/amqp-rabbitmq-0.8.json \
		./.generated/rabbit_framing_amqp_0_8.erl

find ./repositories/rabbitmq-server/src -name '*.erl' -printf '%f\n' \
| sed -r -e 's!^([a-z]([a-z0-9_]+[a-z0-9])?)(\.erl)$!\1!g' \
	>./.generated/rabbit_modules.txt

erl +Bd -mode minimal -noinput -noshell \
		-eval '
	{ok,[{_,_,[_,_,{modules, Mods},_,_,_]}]} = file:consult("./repositories/rabbitmq-erlang-client/rabbit_common.app.in"),
	[io:format("~p\n",[M]) || M <- Mods],
	init:stop ().
' >./.generated/rabbit_common_modules.txt

cp -T ./repositories/rabbitmq-server/ebin/rabbit_app.in ./.generated/rabbit.app
cp -T ./repositories/rabbitmq-erlang-client/rabbit_common.app.in ./.generated/rabbit_common.app
cp -T ./repositories/rabbitmq-erlang-client/ebin/amqp_client.app.in ./.generated/amqp_client.app

sed -r -e 's!%%VSN%%!'"${VERSION}"'!g' -i ./.generated/rabbit.app
sed -r -e 's!%%VSN%%!'"${VERSION}"'!g' -i ./.generated/amqp_client.app
sed -r -e 's!%%VSN%%!'"${VERSION}"'!g' -i ./.generated/rabbit_common.app

sed -r \
		-e 's!(\{modules, \[)(\]\})!\1'"$( tr '\n' ',' <./.generated/rabbit_modules.txt )"'\2!g' \
		-e 's!(\{modules, \[)(([a-z]([a-z0-9_]+[a-z0-9])?,)*)([a-z]([a-z0-9_]+[a-z0-9])?),(\]\})!\1\2\5\7!g' \
		-i ./.generated/rabbit.app

exit 0
