
-module (mosaic_rabbitmq_callbacks).

-behaviour (mosaic_component_callbacks).


-export ([configure/0]).
-export ([init/0, terminate/2, handle_call/5, handle_cast/4, handle_info/2]).


-import (mosaic_enforcements, [enforce_ok/1, enforce_ok_1/1, enforce_ok_2/1]).


-record (state, {status, identifier, group, broker_socket, management_socket}).


init () ->
	try
		State = #state{
					status = waiting_initialize,
					identifier = none, group = none,
					broker_socket = none, management_socket = none},
		erlang:self () ! {mosaic_rabbitmq_callbacks_internals, trigger_initialize},
		{ok, State}
	catch throw : {error, Reason} -> {stop, Reason} end.


terminate (_Reason, _State = #state{}) ->
	ok = stop_applications_async (),
	ok.


handle_call (<<"mosaic-rabbitmq:get-broker-endpoint">>, null, <<>>, _Sender, State = #state{status = executing, broker_socket = Socket}) ->
	{SocketIp, SocketPort} = Socket,
	Outcome = {ok, {struct, [
					{<<"transport">>, <<"tcp">>}, {<<"ip">>, SocketIp}, {<<"port">>, SocketPort},
					{<<"url">>, erlang:iolist_to_binary (["amqp://", SocketIp, ":", erlang:integer_to_list (SocketPort), "/"])}
				]}, <<>>},
	{reply, Outcome, State};
	
handle_call (<<"mosaic-rabbitmq:get-management-endpoint">>, null, <<>>, _Sender, State = #state{status = executing, management_socket = Socket}) ->
	{SocketIp, SocketPort} = Socket,
	Outcome = {ok, {struct, [
					{<<"ip">>, SocketIp}, {<<"port">>, SocketPort},
					{<<"url">>, erlang:iolist_to_binary (["http://", SocketIp, ":", erlang:integer_to_list (SocketPort), "/"])}
				]}, <<>>},
	{reply, Outcome, State};
	
handle_call (<<"mosaic-rabbitmq:get-node-identifier">>, null, <<>>, _Sender, State) ->
	Outcome = {ok, erlang:atom_to_binary (erlang:node (), utf8), <<>>},
	{reply, Outcome, State};
	
handle_call (Operation, Inputs, _Data, _Sender, State = #state{status = executing}) ->
	ok = mosaic_transcript:trace_error ("received invalid call request; ignoring!", [{operation, Operation}, {inputs, Inputs}]),
	{reply, {error, {invalid_operation, Operation}}, State};
	
handle_call (Operation, Inputs, _Data, _Sender, State = #state{status = Status})
		when (Status =/= executing) ->
	ok = mosaic_transcript:trace_error ("received invalid call request; ignoring!", [{operation, Operation}, {inputs, Inputs}, {status, Status}]),
	{reply, {error, {invalid_status, Status}}, State}.


handle_cast (Operation, Inputs, _Data, State = #state{status = executing}) ->
	ok = mosaic_transcript:trace_error ("received invalid cast request; ignoring!", [{operation, Operation}, {inputs, Inputs}]),
	{noreply, State};
	
handle_cast (Operation, Inputs, _Data, State = #state{status = Status})
		when (Status =/= executing) ->
	ok = mosaic_transcript:trace_error ("received invalid cast request; ignoring!", [{operation, Operation}, {inputs, Inputs}, {status, Status}]),
	{noreply, State}.


handle_info ({mosaic_rabbitmq_callbacks_internals, trigger_initialize}, OldState = #state{status = waiting_initialize}) ->
	try
		Identifier = enforce_ok_1 (mosaic_generic_coders:application_env_get (identifier, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_component/1}, {error, missing_identifier})),
		Group = enforce_ok_1 (mosaic_generic_coders:application_env_get (group, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_group/1}, {error, missing_group})),
		ok = enforce_ok (mosaic_component_callbacks:acquire_async (
					[{<<"broker_socket">>, <<"socket:ipv4:tcp">>}, {<<"management_socket">>, <<"socket:ipv4:tcp">>}],
					{mosaic_rabbitmq_callbacks_internals, acquire_return})),
		NewState = OldState#state{status = waiting_acquire_return, identifier = Identifier, group = Group},
		{noreply, NewState}
	catch throw : Error = {error, _Reason} -> {stop, Error, OldState} end;
	
handle_info ({{mosaic_rabbitmq_callbacks_internals, acquire_return}, Outcome}, OldState = #state{status = waiting_acquire_return, identifier = Identifier, group = Group}) ->
	try
		Descriptors = enforce_ok_1 (Outcome),
		[BrokerSocket, ManagementSocket] = enforce_ok_1 (mosaic_component_coders:decode_socket_ipv4_tcp_descriptors (
					[<<"broker_socket">>, <<"management_socket">>], Descriptors)),
		{BrokerSocketIp, BrokerSocketPort} = BrokerSocket,
		{ManagementSocketIp, ManagementSocketPort} = ManagementSocket,
		IdentifierString = erlang:binary_to_list (enforce_ok_1 (mosaic_component_coders:encode_component (Identifier))),
		BrokerSocketIpString = erlang:binary_to_list (BrokerSocketIp),
		ManagementSocketIpString = erlang:binary_to_list (ManagementSocketIp),
		ok = enforce_ok (application:set_env (rabbit, tcp_listeners, [{BrokerSocketIpString, BrokerSocketPort}])),
		ok = enforce_ok (application:set_env (rabbit_mochiweb, port, ManagementSocketPort)),
		ok = enforce_ok (application:set_env (mnesia, dir, "/tmp/mosaic/components/rabbitmq/" ++ IdentifierString ++ "/mnesia")),
		ok = enforce_ok (application:set_env (mnesia, core_dir, "/tmp/mosaic/components/rabbitmq/" ++ IdentifierString ++ "/mnesia")),
		ok = enforce_ok (start_applications ()),
		ok = enforce_ok (mosaic_component_callbacks:register_async (Group, {mosaic_rabbitmq_callbacks_internals, register_return})),
		NewState = OldState#state{status = waiting_register_return, broker_socket = BrokerSocket, management_socket = ManagementSocket},
		{noreply, NewState}
	catch throw : Error = {error, _Reason} -> {stop, Error, OldState} end;
	
handle_info ({{mosaic_rabbitmq_callbacks_internals, register_return}, Outcome}, OldState = #state{status = waiting_register_return}) ->
	try
		ok = enforce_ok (Outcome),
		NewState = OldState#state{status = executing},
		{noreply, NewState}
	catch throw : Error = {error, _Reason} -> {stop, Error, OldState} end;
	
handle_info (Message, State = #state{status = Status}) ->
	ok = mosaic_transcript:trace_error ("received invalid message; terminating!", [{message, Message}, {status, Status}]),
	{stop, {error, {invalid_message, Message}}, State}.


configure () ->
	try
		ok = enforce_ok (load_applications ()),
		AppEnvIdentifier = enforce_ok_1 (mosaic_generic_coders:application_env_get (identifier, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_component/1}, {default, undefined})),
		OsEnvIdentifier = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_identifier,
					{decode, fun mosaic_component_coders:decode_component/1}, {default, undefined})),
		AppEnvGroup = enforce_ok_1 (mosaic_generic_coders:application_env_get (group, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_group/1}, {default, undefined})),
		OsEnvGroup = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_group,
					{decode, fun mosaic_component_coders:decode_group/1}, {default, undefined})),
		HarnessInputDescriptor = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_harness_input_descriptor,
					{decode, fun mosaic_generic_coders:decode_integer/1}, {error, missing_harness_input_descriptor})),
		HarnessOutputDescriptor = enforce_ok_1 (mosaic_generic_coders:os_env_get (mosaic_component_harness_output_descriptor,
					{decode, fun mosaic_generic_coders:decode_integer/1}, {error, missing_harness_output_descriptor})),
		Identifier = if
			(OsEnvIdentifier =/= undefined) -> OsEnvIdentifier;
			(AppEnvIdentifier =/= undefined) -> AppEnvIdentifier;
			true -> throw ({error, missing_identifier})
		end,
		Group = if
			(OsEnvGroup =/= undefined) -> OsEnvGroup;
			(AppEnvGroup =/= undefined) -> AppEnvGroup;
			true -> throw ({error, missing_group})
		end,
		IdentifierString = erlang:binary_to_list (enforce_ok_1 (mosaic_component_coders:encode_component (Identifier))),
		GroupString = erlang:binary_to_list (enforce_ok_1 (mosaic_component_coders:encode_group (Group))),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, identifier, IdentifierString)),
		ok = enforce_ok (application:set_env (mosaic_rabbitmq, group, GroupString)),
		ok = enforce_ok (application:set_env (mosaic_component, harness_input_descriptor, HarnessInputDescriptor)),
		ok = enforce_ok (application:set_env (mosaic_component, harness_output_descriptor, HarnessOutputDescriptor)),
		ok
	catch throw : {error, Reason} -> {error, {failed_configuring, Reason}} end.


resolve_applications () ->
	try
		ManagementEnabled = enforce_ok_1 (mosaic_generic_coders:application_env_get (management_enabled, mosaic_rabbitmq,
					{validate, {is_boolean, invalid_management_enabled}}, {error, missing_management_enabled})),
		MandatoryApplicationsStep1 = [sasl, os_mon, mnesia],
		MandatoryApplicationsStep2 = [rabbit, amqp_client],
		OptionalApplicationsStep1 = if ManagementEnabled -> [inets, crypto, mochiweb, webmachine, rabbit_mochiweb]; true -> [] end,
		OptionalApplicationsStep2 = if ManagementEnabled -> [rabbit_management_agent, rabbit_management]; true -> [] end,
		{ok, MandatoryApplicationsStep1 ++ OptionalApplicationsStep1, MandatoryApplicationsStep2 ++ OptionalApplicationsStep2}
	catch throw : {error, Reason} -> {error, {failed_resolving_applications, Reason}} end.


load_applications () ->
	try
		ok = enforce_ok (mosaic_application_tools:load (mosaic_rabbitmq, with_dependencies)),
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:load (ApplicationsStep1 ++ ApplicationsStep2, without_dependencies)),
		ok
	catch throw : {error, Reason} -> {error, {failed_loading_applications, Reason}} end.


start_applications () ->
	try
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep1, without_dependencies)),
		ok = enforce_ok (rabbit:prepare ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep2, without_dependencies)),
		ok = enforce_ok (mosaic_application_tools:start (mosaic_rabbitmq, with_dependencies)),
		ok
	catch throw : {error, Reason} -> {error, {failed_starting_applications, Reason}} end.


stop_applications () ->
	try
		ok = enforce_ok (rabbit:stop_and_halt ())
	catch _ : Reason -> {error, {failed_stopping_applications, Reason}} end.

stop_applications_async () ->
	_ = erlang:spawn (
				fun () ->
					ok = timer:sleep (100),
					ok = stop_applications (),
					ok
				end),
	ok.
