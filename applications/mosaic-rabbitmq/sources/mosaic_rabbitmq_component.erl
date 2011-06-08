
-module (mosaic_rabbitmq_component).


-export ([start_link/0, init/0]).


start_link () ->
	proc_lib:start_link (mosaic_rabbitmq_component, init, []).


-record (state, {identifier, port, status, correlation}).


handle_init (State = #state{status = initialized}) ->
	{ok, Correlation} = correlation (),
	case trigger_acquire (Correlation, [{<<"broker_socket">>, <<"socket:ipv4:tcp">>}, {<<"management_socket">>, <<"socket:ipv4:tcp">>}],  State) of
		ok ->
			{ok, State#state{status = acquiring, correlation = Correlation}};
		Error = {error, _Reason} ->
			{stop, Error, State}
	end.


handle_terminate (State) ->
	{stop, normal, State}.


handle_call (Correlation, [{<<"operation">>, <<"get-broker-endpoint">>}], <<>>, State = #state{status = executing}) ->
	{ok, Ip} = application:get_env (mosaic_rabbitmq, broker_socket_ip),
	{ok, Port} = application:get_env (mosaic_rabbitmq, broker_socket_port),
	ok = trigger_call_return (Correlation, [{<<"type">>, <<"tcp">>}, {<<"ip">>, Ip}, {<<"port">>, Port}], <<>>, State),
	{ok, State};
	
handle_call (_Correlation, _MetaData, _Data, State = #state{}) ->
	{stop, {error, unexpected_call}, State}.


handle_cast (_MetaData, _Data, State = #state{}) ->
	{stop, {error, unexpected_cast}, State}.


handle_call_return (_Correlation, _MetaData, _Data, State = #state{}) ->
	{stop, {error, unexpected_call_return}, State}.


handle_register_return (Correlation, Outcome, OldState = #state{status = registering, correlation = Correlation}) ->
	case Outcome of
		ok ->
			case mosaic_rabbitmq_app:boot (mosaic_rabbitmq_rabbit, start) of
				ok ->
					{ok, OldState#state{status = executing, correlation = none}};
				Error = {error, _Reason} ->
					{stop, Error, OldState}
			end;
		{error, Reason} ->
			{stop, {error, {register_failed, Reason}}, OldState}
	end;
	
handle_register_return (_Correlation, _Outcome, State = #state{}) ->
	{stop, {error, unexpected_register_return}, State}.


handle_resources_return (Correlation, Outcome, OldState = #state{identifier = Identifier, status = acquiring, correlation = Correlation}) ->
	case Outcome of
		{ok, Resources} ->
			case lists:sort (Resources) of
				[{<<"broker_socket">>, {struct, BrokerSocket}}, {<<"management_socket">>, {struct, ManagementSocket}}] ->
					try
						{ok, BrokerSocketIp, BrokerSocketPort} = case lists:sort (BrokerSocket) of
							[{<<"ip">>, BrokerSocketIp_}, {<<"port">>, BrokerSocketPort_}]
									when is_binary (BrokerSocketIp_), is_integer (BrokerSocketPort_), (BrokerSocketPort_ >= 1), (BrokerSocketPort_ =< 65535) ->
								{ok, BrokerSocketIp_, BrokerSocketPort_};
							_ ->
								throw ({error, {invalid_resources, Resources}})
						end,
						{ok, _ManagementSocketIp, ManagementSocketPort} = case lists:sort (ManagementSocket) of
							[{<<"ip">>, ManagementSocketIp_}, {<<"port">>, ManagementSocketPort_}]
									when is_binary (ManagementSocketIp_), is_integer (ManagementSocketPort_), (ManagementSocketPort_ >= 1), (ManagementSocketPort_ =< 65535) ->
								{ok, ManagementSocketIp_, ManagementSocketPort_};
							_ ->
								throw ({error, {invalid_resources, Resources}})
						end,
						ok = case mosaic_rabbitmq_app:boot (mosaic_rabbitmq_rabbit, load) of
							ok ->
								ok;
							Error1 = {error, _Reason1} ->
								throw (Error1)
						end,
						ok = application:set_env (mosaic_rabbitmq, broker_socket_ip, BrokerSocketIp),
						ok = application:set_env (mosaic_rabbitmq, broker_socket_port, BrokerSocketPort),
						ok = application:set_env (rabbit, tcp_listeners, [{erlang:binary_to_list (BrokerSocketIp), BrokerSocketPort}]),
						ok = application:set_env (rabbit_mochiweb, port, ManagementSocketPort),
						ok = application:set_env (mnesia, dir, "/tmp/mosaic/components/rabbitmq/" ++ erlang:binary_to_list (Identifier) ++ "/mnesia"),
						ok = application:set_env (mnesia, core_dir, "/tmp/mosaic/components/rabbitmq/" ++ erlang:binary_to_list (Identifier) ++ "/mnesia"),
						{ok, Group} = application:get_env (mosaic_rabbitmq, group),
						{ok, NewCorrelation} = correlation (),
						ok = trigger_register (NewCorrelation, erlang:list_to_binary (Group), OldState),
						{ok, OldState#state{status = registering, correlation = NewCorrelation}}
					catch
						throw : Error = {error, _Reason} ->
							{stop, Error, OldState}
					end;
				_ ->
					{stop, {invalid_resources, Resources}, OldState}
			end;
		{error, Reason} ->
			{stop, {error, {denied_resources, Reason}}, OldState}
	end;
	
handle_resources_return (_Correlation, _Outcome, State = #state{}) ->
	{stop, {error, {unexpected_resources_return}}, State}.


abort (normal) ->
	ok = error_logger:error_report (["stopping..."]),
	_ = (catch rabbit:stop_and_halt ()),
	ok = timer:sleep (60 * 1000),
	erlang:halt ();
	
abort ({error, Reason}) ->
	ok = error_logger:error_report (["aborting...", {reason, Reason}]),
	_ = (catch rabbit:stop_and_halt ()),
	ok = timer:sleep (60 * 1000),
	erlang:halt ().


init () ->
	true = erlang:register (mosaic_rabbitmq_component, erlang:self ()),
	ok = proc_lib:init_ack ({ok, erlang:self ()}),
	false = erlang:process_flag (trap_exit, true),
	{ok, Identifier} = case os:getenv ("mosaic_component_identifier") of
		Identifier_ when is_list (Identifier_), (length (Identifier_) =:= 40) ->
			try
				{ok, erlang:list_to_binary (Identifier_)}
			catch
				error : badarg ->
					abort ({error, {invalid_configuration, {invalid_identifier, Identifier_}}})
			end;
		Identifier_ ->
			abort ({error, {invalid_configuration, {invalid_identifier, Identifier_}}})
	end,
	{ok, InputDescriptor} = case os:getenv ("mosaic_component_input_descriptor") of
		InputDescriptor_ when is_list (InputDescriptor_) ->
			try
				{ok, erlang:list_to_integer (InputDescriptor_)}
			catch
				error : badarg ->
					abort ({error, {invalid_configuration, {invalid_input_descriptor, InputDescriptor_}}})
			end;
		InputDescriptor_ ->
			abort ({error, {invalid_configuration, {invalid_input_descriptor, InputDescriptor_}}})
	end,
	{ok, OutputDescriptor} = case os:getenv ("mosaic_component_output_descriptor") of
		OutputDescriptor_ when is_list (OutputDescriptor_) ->
			try
				{ok, erlang:list_to_integer (OutputDescriptor_)}
			catch
				error : badarg ->
					abort ({error, {invalid_configuration, {invalid_output_descriptor, OutputDescriptor_}}})
			end;
		OutputDescriptor_ ->
			abort ({error, {invalid_configuration, {invalid_output_descriptor, OutputDescriptor_}}})
	end,
	Port = erlang:open_port ({fd, InputDescriptor, OutputDescriptor}, [{packet, 4}, binary, eof]),
	true = erlang:link (Port),
	State = #state{identifier = Identifier, port = Port, status = initialized},
	case handle_init (State) of
		{ok, NewState} ->
			try
				loop (NewState),
				abort (assertion)
			catch
				throw : Caught ->
					abort ({error, {error, Caught, erlang:get_stacktrace ()}});
				error : Caught ->
					abort ({error, {error, Caught, erlang:get_stacktrace ()}});
				exit : Caught ->
					abort ({error, {error, Caught, erlang:get_stacktrace ()}})
			end;
		{stop, Reason, NewState} ->
			terminate (Reason, NewState)
	end.


terminate (normal, _State = #state{}) ->
	abort (normal);
	
terminate (Error = {error, _Reason}, _State = #state{}) ->
	abort (Error);
	
terminate (Reason, _State = #state{}) ->
	abort ({error, Reason}).


loop (OldState = #state{port = Port}) ->
	case
		receive
			{Port, {data, Packet}} when is_binary (Packet) ->
				handle_packet (Packet, OldState);
			{Port, eof} ->
				handle_terminate (OldState);
			Message ->
				ok = error_logger:error_report (["received invalid message; ignoring!", {message, Message}]),
				{ok, OldState}
		end
	of
		{ok, NewState} ->
			loop (NewState);
		{stop, Reason, NewState} ->
			terminate (Reason, NewState)
	end.


handle_packet (Packet, State) ->
	case decode_packet (Packet) of
		{ok, json, {PacketMetaData, PacketData}} ->
			case lists:sort (PacketMetaData) of
				[{<<"__type__">>, <<"exchange">>} | RemainingMetaData] ->
					handle_exchange (RemainingMetaData, PacketData, State);
				[{<<"__type__">>, <<"resources">>} | RemainingMetaData] ->
					handle_resources (RemainingMetaData, PacketData, State);
				_ ->
					{stop, {error, {invalid_packet, PacketMetaData, PacketData}}, State}
			end;
		Error = {error, _Reason} ->
			{stop, Error, State}
	end.


handle_exchange (MetaData, Data, State = #state{}) ->
	case MetaData of
		[{<<"action">>, <<"call">>}, {<<"correlation">>, Correlation}, {<<"meta-data">>, {struct, RequestMetaData}}] when is_binary (Correlation) ->
			handle_call (Correlation, RequestMetaData, Data, State);
		[{<<"action">>, <<"cast">>}, {<<"meta-data">>, {struct, RequestMetaData}}] ->
			handle_cast (RequestMetaData, Data, State);
		[{<<"action">>, <<"return">>}, {<<"correlation">>, Correlation}, {<<"meta-data">>, {struct, RequestMetaData}}] when is_binary (Correlation) ->
			handle_call_return (Correlation, RequestMetaData, Data, State);
		[{<<"action">>, <<"register-return">>}, {<<"correlation">>, Correlation}, {<<"ok">>, true}] when is_binary (Correlation), (Data =:= <<>>) ->
			handle_register_return (Correlation, ok, State);
		[{<<"action">>, <<"register-return">>}, {<<"correlation">>, Correlation}, {<<"error">>, Reason}, {<<"ok">>, false}] when is_binary (Correlation), (Data =:= <<>>) ->
			handle_register_return (Correlation, {error, Reason}, State);
		_ ->
			{stop, {error, {invalid_exchange_packet, MetaData, Data}}, State}
	end.


handle_resources (MetaData, Data, State = #state{}) ->
	case MetaData of
		[{<<"action">>, <<"return">>}, {<<"correlation">>, Correlation}, {<<"ok">>, true}, {<<"resources">>, {struct, Resources}}]
				when is_binary (Correlation) ->
			handle_resources_return (Correlation, {ok, Resources}, State);
		[{<<"action">>, <<"return">>}, {<<"correlation">>, Correlation}, {<<"ok">>, false}, {<<"error">>, Reason}]
				when is_binary (Correlation) ->
			if
				(Data =:= <<>>) ->
					handle_resources_return (Correlation, {error, Reason}, State);
				true ->
					{stop, {error, {invalid_resources_packet, MetaData, Data}}, State}
			end;
		_ ->
			{stop, {error, {invalid_resources_packet, MetaData, Data}}, State}
	end.


trigger_call (Component, Correlation, RequestMetaData, RequestData, State = #state{})
		when is_binary (Component), is_binary (Correlation), is_list (RequestMetaData), is_binary (RequestData) ->
	trigger_packet (
			[
				{<<"__type__">>, <<"exchange">>}, {<<"action">>, <<"call">>},
				{<<"component">>, Component}, {<<"correlation">>, Correlation}, {<<"meta-data">>, RequestMetaData}],
			RequestData, State).


trigger_cast (Component, RequestMetaData, RequestData, State = #state{})
		when is_binary (Component), is_list (RequestMetaData), is_binary (RequestData) ->
	trigger_packet (
			[
				{<<"__type__">>, <<"exchange">>}, {<<"action">>, <<"cast">>},
				{<<"component">>, Component}, {<<"meta-data">>, RequestMetaData}],
			RequestData, State).


trigger_call_return (Correlation, ReplyMetaData, ReplyData, State = #state{})
		when is_binary (Correlation), is_list (ReplyMetaData), is_binary (ReplyData) ->
	trigger_packet (
			[
				{<<"__type__">>, <<"exchange">>}, {<<"action">>, <<"return">>},
				{<<"correlation">>, Correlation}, {<<"meta-data">>, ReplyMetaData}],
			ReplyData, State).


trigger_register (Correlation, Group, State = #state{})
		when is_binary (Correlation), is_binary (Group) ->
	trigger_packet (
			[
				{<<"__type__">>, <<"exchange">>}, {<<"action">>, <<"register">>},
				{<<"correlation">>, Correlation}, {<<"group">>, Group}],
			<<>>, State).


trigger_acquire (Correlation, Resources, State = #state{})
		when is_binary (Correlation), is_list (Resources) ->
	trigger_packet (
			[
				{<<"__type__">>, <<"resources">>}, {<<"action">>, <<"acquire">>},
				{<<"correlation">>, Correlation}, {<<"resources">>, {struct, Resources}}],
			<<>>, State).


trigger_packet (PacketMetaData, PacketData, _State = #state{port = Port})
		when is_list (PacketMetaData), is_binary (PacketData) ->
	case encode_packet (json, {PacketMetaData, PacketData}) of
		{ok, Packet} ->
			true = erlang:port_command (Port, Packet),
			ok;
		Error = {error, _Reason} ->
			Error
	end.


encode_packet (json, {PacketMetaData, PacketData})
		when is_list (PacketMetaData), is_binary (PacketData) ->
	try
		PacketMetaDataBinary = erlang:iolist_to_binary (mochijson2:encode ({struct, PacketMetaData})),
		PacketPayload = <<PacketMetaDataBinary / binary, 0 : 8, PacketData / binary>>,
		{ok, PacketPayload}
	catch
		throw : Reason ->
			{error, {invalid_packet, Reason}};
		error : Reason ->
			{error, {invalid_packet, Reason}};
		exit : Reason ->
			{error, {invalid_packet, Reason}}
	end.


decode_packet (PacketPayload)
		when is_binary (PacketPayload) ->
	case binary:split (PacketPayload, <<0:8>>) of
		[PacketMetaDataBinary, PacketData] ->
			try
				case mochijson2:decode (PacketMetaDataBinary) of
					{struct, PacketMetaData} ->
						{ok, json, {PacketMetaData, PacketData}};
					PacketMetaData ->
						{error, {invalid_meta_data, PacketMetaData}}
				end
			catch
				throw : Reason ->
					{error, {invalid_packet, Reason}};
				error : Reason ->
					{error, {invalid_packet, Reason}};
				exit : Reason ->
					{error, {invalid_packet, Reason}}
			end;
		_ ->
			{error, invalid_packet_framing}
	end.


correlation () ->
	String = erlang:binary_to_list (crypto:rand_bytes (160 div 8)),
	{ok, erlang:iolist_to_binary (lists:flatten ([io_lib:format ("~2.16.0b", [Byte]) || Byte <- String]))}.
