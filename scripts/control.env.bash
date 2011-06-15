#!/dev/null

_erl_path=''

_erl_run_argv=(
	+Bd +Ww
	-env ERL_CRASH_DUMP /dev/null
	-env ERL_LIBS "${_deployment_erlang_path:-./erlang}/lib"
	-env LANG C
	-noshell -noinput
	-sname -sname mosaic-rabbitmq-0000000000000000000000000000000000000000@localhost
	-boot start_sasl
	-config "${_deployment_erlang_path:-./erlang}/lib/mosaic_rabbitmq/priv/mosaic_rabbitmq.config"
	-run mosaic_rabbitmq_callbacks standalone
)

_ez_bundle_names=(
	amqp_client
	mochiweb
	mosaic_component
	mosaic_harness
	mosaic_rabbitmq
	mosaic_tools
	rabbit_common
	rabbit
	rabbit_management_agent
	rabbit_management
	rabbit_mochiweb
	webmachine
)

_bundles_token=236e3b5e58cb84645499d4e181e5a86b
_bundles_base_url="http://data.volution.ro/ciprian/${_bundles_token}"
_bundles_base_path="/afs/olympus.volution.ro/people/ciprian/web/data/${_bundles_token}"
