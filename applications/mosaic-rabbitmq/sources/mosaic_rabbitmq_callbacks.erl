
-module (mosaic_rabbitmq_callbacks).

-behaviour (mosaic_component_callbacks).


-export ([configure/0, standalone/0]).
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
	{SocketIp, SocketPort, SocketFqdn} = Socket,
	Outcome = {ok, {struct, [
					{<<"transport">>, <<"tcp">>}, {<<"ip">>, SocketIp}, {<<"port">>, SocketPort}, {<<"fqdn">>, SocketFqdn},
					{<<"url">>, erlang:iolist_to_binary (["amqp://", SocketFqdn, ":", erlang:integer_to_list (SocketPort), "/"])}
				]}, <<>>},
	{reply, Outcome, State};
	
handle_call (<<"mosaic-rabbitmq:get-management-endpoint">>, null, <<>>, _Sender, State = #state{status = executing, management_socket = Socket}) ->
	{SocketIp, SocketPort, SocketFqdn} = Socket,
	Outcome = {ok, {struct, [
					{<<"ip">>, SocketIp}, {<<"port">>, SocketPort}, {<<"fqdn">>, SocketFqdn},
					{<<"url">>, erlang:iolist_to_binary (["http://", SocketFqdn, ":", erlang:integer_to_list (SocketPort), "/"])}
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
		ok = enforce_ok (setup_applications (Identifier, BrokerSocket, ManagementSocket)),
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


standalone () ->
	mosaic_application_tools:boot (fun standalone_1/0).

standalone_1 () ->
	try
		ok = enforce_ok (load_applications ()),
		ok = enforce_ok (mosaic_component_callbacks:configure ([{identifier, mosaic_rabbitmq}])),
		Identifier = enforce_ok_1 (mosaic_generic_coders:application_env_get (identifier, mosaic_rabbitmq,
					{decode, fun mosaic_component_coders:decode_component/1}, {error, missing_identifier})),
		BrokerSocket = {<<"127.0.0.1">>, 21688, <<"127.0.0.1">>},
		ManagementSocket = {<<"127.0.0.1">>, 29800, <<"127.0.0.1">>},
		ok = enforce_ok (setup_applications (Identifier, BrokerSocket, ManagementSocket)),
		ok = enforce_ok (start_applications ()),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


configure () ->
	try
		ok = enforce_ok (load_applications ()),
		ok = enforce_ok (mosaic_component_callbacks:configure ([
					{identifier, mosaic_rabbitmq},
					{group, mosaic_rabbitmq},
					harness])),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


resolve_applications () ->
	try
		ManagementEnabled = enforce_ok_1 (mosaic_generic_coders:application_env_get (management_enabled, mosaic_rabbitmq,
					{validate, {is_boolean, invalid_management_enabled}}, {error, missing_management_enabled})),
		MandatoryApplicationsStep1 = [sasl, os_mon, mnesia],
		MandatoryApplicationsStep2 = [rabbit, amqp_client],
		OptionalApplicationsStep1 = if ManagementEnabled -> [inets, crypto, mochiweb, webmachine, rabbit_mochiweb]; true -> [] end,
		OptionalApplicationsStep2 = if ManagementEnabled -> [rabbit_management_agent, rabbit_management]; true -> [] end,
		{ok, MandatoryApplicationsStep1 ++ OptionalApplicationsStep1, MandatoryApplicationsStep2 ++ OptionalApplicationsStep2}
	catch throw : Error = {error, _Reason} -> Error end.


load_applications () ->
	try
		ok = enforce_ok (mosaic_application_tools:load (mosaic_rabbitmq, without_dependencies)),
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:load (ApplicationsStep1, without_dependencies)),
		ok = enforce_ok (mosaic_application_tools:load (ApplicationsStep2, without_dependencies)),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


setup_applications (Identifier, BrokerSocket, ManagementSocket) ->
	try
		IdentifierString = enforce_ok_1 (mosaic_component_coders:encode_component (Identifier)),
		{BrokerSocketIp, BrokerSocketPort, BrokerSocketFqdn} = BrokerSocket,
		{ManagementSocketIp, ManagementSocketPort, ManagementSocketFqdn} = ManagementSocket,
		BrokerSocketIpString = erlang:binary_to_list (BrokerSocketIp),
		BrokerSocketFqdnString = erlang:binary_to_list (BrokerSocketFqdn),
		ManagementSocketIpString = erlang:binary_to_list (ManagementSocketIp),
		ManagementSocketFqdnString = erlang:binary_to_list (ManagementSocketFqdn),
		ok = enforce_ok (mosaic_component_callbacks:configure ([
					{env, rabbit, tcp_listeners, [{BrokerSocketIpString, BrokerSocketPort}]},
					{env, rabbit_mochiweb, port, ManagementSocketPort}])),
		ok = error_logger:info_report (["Configuring mOSAIC RabbitMq component...",
					{identifier, IdentifierString},
					{url, erlang:list_to_binary ("http://" ++ ManagementSocketFqdnString ++ ":" ++ erlang:integer_to_list (ManagementSocketPort) ++ "/")},
					{broker_endpoint, BrokerSocket}, {management_endpoint, ManagementSocket}]),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


start_applications () ->
	try
		{ApplicationsStep1, ApplicationsStep2} = enforce_ok_2 (resolve_applications ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep1, without_dependencies)),
		ok = enforce_ok (rabbit:prepare ()),
		ok = enforce_ok (mosaic_application_tools:start (ApplicationsStep2, without_dependencies)),
		ok
	catch throw : Error = {error, _Reason} -> Error end.


stop_applications () ->
	_ = rabbit:stop_and_halt ().


stop_applications_async () ->
	_ = erlang:spawn (
				fun () ->
					ok = timer:sleep (100),
					ok = stop_applications (),
					ok
				end),
	ok.
