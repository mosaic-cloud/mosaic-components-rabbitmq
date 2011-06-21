#!/dev/null

if ! test "${#}" -le 1 ; then
	echo "[ee] invalid arguments; aborting!" >&2
	exit 1
fi

_identifier="${1:-000000001e12528cc806cba37318f48295d688db}"

_erl_args+=(
		-noinput -noshell
		-sname "mosaic-rabbitmq-${_identifier}@${_erl_host}" -setcookie "${_erl_cookie}"
		-boot start_sasl
		-config "${_outputs}/erlang/applications/mosaic_rabbitmq/priv/mosaic_rabbitmq.config"
)
_erl_env+=(
		mosaic_component_identifier="${_identifier}"
)

if test "${_identifier}" != 000000001e12528cc806cba37318f48295d688db ; then
	_erl_args+=(
			-run mosaic_component_app boot
	)
	_erl_env+=(
			mosaic_component_harness_input_descriptor=3
			mosaic_component_harness_output_descriptor=4
	)
	exec  3<&0- 4>&1- </dev/null >&2
else
	_erl_args+=(
			-run mosaic_rabbitmq_callbacks standalone
	)
fi

mkdir -p "/tmp/mosaic/components/${_identifier}"
cd "/tmp/mosaic/components/${_identifier}"

exec env "${_erl_env[@]}" "${_erl}" "${_erl_args[@]}"
