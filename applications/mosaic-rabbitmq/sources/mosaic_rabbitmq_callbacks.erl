
-module (mosaic_rabbitmq_callbacks).

-behaviour (mosaic_component_callbacks).


-export ([configure/0]).
-export ([init/0, terminate/2, handle_call/5, handle_cast/4, handle_info/2]).


-import (mosaic_enforcements, [enforce_ok/1, enforce_ok_1/1, enforce_ok_2/1]).


-record (state, {status}).


init () ->
	_ = erlang:send_after (100, erlang:self (), {mosaic_rabbitmq_callbacks_internals, trigger_initialize}),
	State = #state{status = initializing},
	{ok, State}.


terminate (_Reason, _State = #state{}) ->
	stop_applications ().


handle_call (<<"mosaic-rabbitmq:get-broker-endpoint">>, null, <<>>, _Sender, State = #state{status = executing}) ->
	try
		BrokerSocketIp = enforce_ok_1 (mosaic_generic_coders:application_env_get (broker_socket_ip, mosaic_rabbitmq, none, {error, invalid})),
		BrokerSocketPort = enforce_ok_1 (mosaic_generic_coders:application_env_get (broker_socket_port, mosaic_rabbitmq, none, {error, invalid})),
		Outcome = {ok, {struct, [
						{<<"type">>, <<"tcp">>}, {<<"ip">>, BrokerSocketIp}, {<<"port">>, BrokerSocketPort},
						{<<"url">>, erlang:iolist_to_binary (["amqp://", BrokerSocketIp, ":", erlang:integer_to_list (BrokerSocketPort), "/"])}
					]}, <<>>},
		{reply, Outcome, State}
	catch throw : Error = {error, _Reason} -> {reply, Error, State} end;
	
handle_call (<<"mosaic-rabbitmq:get-management-endpoint">>, null, <<>>, _Sender, State = #state{status = executing}) ->
	try
		ManagementSocketIp = enforce_ok_1 (mosaic_generic_coders:application_env_get (management_socket_ip, mosaic_rabbitmq, none, {error, invalid})),
		ManagementSocketPort = enforce_ok_1 (mosaic_generic_coders:application_env_get (management_socket_port, mosaic_rabbitmq, none, {error, invalid})),
		Outcome = {ok, {struct, [
						{<<"type">>, <<"http">>}, {<<"ip">>, ManagementSocketIp}, {<<"port">>, ManagementSocketPort},
						{<<"url">>, erlang:iolist_to_binary (["http://", ManagementSocketIp, ":", erlang:integer_to_list (ManagementSocketPort), "/"])}
					]}, <<>>},
		{reply, Outcome, State}
	catch throw : Error = {error, _Reason} -> {reply, Error, State} end;
	
handle_call (Operation, Inputs, _Data, _Sender, State = #state{}) ->
	ok = mosaic_transcript:trace_error ("received invalid call request; ignoring!", [{operation, Operation}, {inputs, Inputs}]),
	{reply, {error, {invalid_operation, Operation}}, State}.


handle_cast (Operation, Inputs, _Data, State = #state{}) ->
	ok = mosaic_transcript:trace_error ("received invalid cast request; ignoring!", [{operation, Operation}, {inputs, Inputs}]),
	{noreply, State}.


handle_info ({mosaic_rabbitmq_callbacks_internals, trigger_initialize}, OldState = #state{status = initializing}) ->
	try
		Identifier = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_identifier,
					{decode, fun mosaic_component_coders:decode_component/1}, {error, missing_identifier})),
		IdentifierString = erlang:binary_to_list (enforce_ok_1 (mosaic_component_coders:encode_component (Identifier))),
		AppEnvGroup = enforce_ok_1 (mosaic_generic_coders:application_env_get (group, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_group/1}, {default, undefined})),
		OsEnvGroup = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_group,
					{decode, fun mosaic_component_coders:decode_group/1}, {default, undefined})),
		Descriptors = enforce_ok_1 (mosaic_component_callbacks:acquire (
					[{<<"broker_socket">>, <<"socket:ipv4:tcp">>}, {<<"management_socket">>, <<"socket:ipv4:tcp">>}])),
		BrokerSocketDescriptor = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"broker_socket">>, Descriptors,
					none, {error, invalid_broker_socket_descriptor})),
		BrokerSocketIp = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"ip">>, BrokerSocketDescriptor,
					{validate, {is_binary, invalid_broker_socket_ip}}, {error, invalid_broker_socket_descriptor})),
		BrokerSocketPort = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"port">>, BrokerSocketDescriptor,
					{validate, {is_integer, invalid_broker_socket_port}}, {error, invalid_broker_socket_descriptor})),
		ManagementSocketDescriptor = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"management_socket">>, Descriptors,
					none, {error, invalid_management_socket_descriptor})),
		ManagementSocketIp = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"ip">>, ManagementSocketDescriptor,
					{validate, {is_binary, invalid_management_socket_ip}}, {error, invalid_management_socket_descriptor})),
		ManagementSocketPort = enforce_ok_1 (mosaic_generic_coders:proplist_get (<<"port">>, ManagementSocketDescriptor,
					{validate, {is_integer, invalid_management_socket_port}}, {error, invalid_management_socket_descriptor})),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, identifier, Identifier)),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, broker_socket_ip, BrokerSocketIp)),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, broker_socket_port, BrokerSocketPort)),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, management_socket_ip, ManagementSocketIp)),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, management_socket_port, ManagementSocketPort)),
		ok = enforce_ok (application:set_env (rabbit, tcp_listeners, [{erlang:binary_to_list (BrokerSocketIp), BrokerSocketPort}])),
		ok = enforce_ok (application:set_env (rabbit_mochiweb, port, ManagementSocketPort)),
		ok = enforce_ok (application:set_env (mnesia, dir, "/tmp/mosaic/components/rabbitmq/" ++ IdentifierString ++ "/mnesia")),
		ok = enforce_ok (application:set_env (mnesia, core_dir, "/tmp/mosaic/components/rabbitmq/" ++ IdentifierString ++ "/mnesia")),
		ok = enforce_ok (start_applications ()),
		ok = if
			(OsEnvGroup =/= undefined) ->
				ok = enforce_ok (mosaic_component_callbacks:register (OsEnvGroup)),
				ok;
			(AppEnvGroup =/= undefined) ->
				ok = enforce_ok (mosaic_component_callbacks:register (AppEnvGroup)),
				ok;
			(AppEnvGroup =:= undefined), (OsEnvGroup =:= undefined) ->
				ok
		end,
		{noreply, OldState#state{status = executing}}
	catch throw : {error, Reason} -> {stop, Reason, OldState} end;
	
handle_info (Message, State = #state{}) ->
	ok = mosaic_transcript:trace_error ("received invalid message; terminating!", [{message, Message}]),
	{stop, {error, {invalid_message, Message}}, State}.


configure () ->
	try
		ok = enforce_ok (load_applications ()),
		HarnessInputDescriptor = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_harness_input_descriptor,
					{decode, fun mosaic_generic_coders:decode_integer/1}, {error, missing_harness_input_descriptor})),
		HarnessOutputDescriptor = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_harness_output_descriptor,
					{decode, fun mosaic_generic_coders:decode_integer/1}, {error, missing_harness_output_descriptor})),
		ok = enforce_ok (application:set_env (mosaic_component, callbacks, mosaic_rabbitmq_callbacks)),
		ok = enforce_ok (application:set_env (mosaic_component, harness_input_descriptor, HarnessInputDescriptor)),
		ok = enforce_ok (application:set_env (mosaic_component, harness_output_descriptor, HarnessOutputDescriptor)),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


resolve_applications () ->
	ManagementEnabled = enforce_ok_1 (mosaic_generic_coders:application_env_get (management_enabled, mosaic_rabbitmq,
				{validate, {is_boolean, invalid_management_enabled}}, {error, missing_management_enabled})),
	MandatoryApplicationsStep1 = [sasl, os_mon, mnesia],
	MandatoryApplicationsStep2 = [rabbit, amqp_client],
	OptionalApplicationsStep1 = if ManagementEnabled -> [inets, crypto, mochiweb, webmachine, rabbit_mochiweb]; true -> [] end,
	OptionalApplicationsStep2 = if ManagementEnabled -> [rabbit_management_agent, rabbit_management]; true -> [] end,
	{ok, MandatoryApplicationsStep1 ++ OptionalApplicationsStep1, MandatoryApplicationsStep2 ++ OptionalApplicationsStep2}.


load_applications () ->
	try
		ok = enforce_ok (mosaic_application_tools:load (mosaic_rabbitmq, with_dependencies)),
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:load (ApplicationsStep1 ++ ApplicationsStep2, without_dependencies)),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


start_applications () ->
	try
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep1, without_dependencies)),
		ok = enforce_ok (rabbit:prepare ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep2, without_dependencies)),
		ok = enforce_ok (mosaic_application_tools:start (mosaic_rabbitmq, with_dependencies)),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


stop_applications () ->
	try
		ok = enforce_ok (rabbit:stop_and_halt ()),
		ok
	catch _ : Reason -> {error, Reason} end.
