#!/dev/null

if ! test "${#}" -le 1 ; then
	echo "[ee] invalid arguments; aborting!" >&2
	exit 1
fi

_identifier="${1:-0000000000000000000000000000000000000000}"

if test "${_identifier}" != 0000000000000000000000000000000000000000 ; then
	_erl_argv=(
		"${_erl}"
			"${_erl_args[@]}"
			-noinput -noshell
			-sname "mosaic-rabbitmq-${_identifier}@${_erl_host}" -setcookie "${_erl_cookie}"
			-boot start_sasl
			-config "${_outputs}/erlang/applications/mosaic_rabbitmq/priv/mosaic_rabbitmq.config"
			-run mosaic_component_app boot
	)
	_erl_env=(
		mosaic_component_identifier="${_identifier}"
		mosaic_component_harness_input_descriptor=3
		mosaic_component_harness_output_descriptor=4
		ERL_EPMD_PORT="${_erl_epmd_port}"
	)
	exec  3<&0- 4>&1- </dev/null >&2
else
	_erl_argv=(
		"${_erl}"
			"${_erl_args[@]}"
			-noinput -noshell
			-sname "mosaic-rabbitmq-${_identifier}@${_erl_host}" -setcookie "${_erl_cookie}"
			-boot start_sasl
			-config "${_outputs}/erlang/applications/mosaic_rabbitmq/priv/mosaic_rabbitmq.config"
			-run mosaic_rabbitmq_callbacks standalone
	)
	_erl_env=(
		ERL_EPMD_PORT="${_erl_epmd_port}"
	)
fi

exec env "${_erl_env[@]}" "${_erl_argv[@]}"
