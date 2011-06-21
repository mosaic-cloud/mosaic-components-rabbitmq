#!/dev/null

_identifier="${mosaic_component_identifier:-000000001e12528cc806cba37318f48295d688db}"

_erl_args+=(
	-noshell -noinput
	-sname "mosaic-rabbitmq-${_identifier}@localhost"
	-env mosaic_component_identifier "${_identifier}"
	-boot start_sasl
	-config "${_deployment_erlang_path}/lib/mosaic_rabbitmq/priv/mosaic_rabbitmq.config"
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
