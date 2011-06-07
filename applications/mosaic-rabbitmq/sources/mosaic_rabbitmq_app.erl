
-module (mosaic_rabbitmq_app).

-behaviour (application).


-export ([start/2, stop/1, boot/0, boot/2]).


start (normal, defaults) ->
	try
		{ok, Supervisor} = start_supervisor (),
		{ok, Supervisor, void}
	catch
		throw : Error = {error, _Reason} ->
			Error
	end;
	
start (normal, Configuration) ->
	{error, {invalid_configuration, Configuration}};
	
start (Disposition, _Configuration) ->
	{error, {invalid_disposition, Disposition}}.


stop (void) ->
	ok.


start_supervisor () ->
	case mosaic_rabbitmq_sup:start_link () of
		Outcome = {ok, _Supervisor} ->
			Outcome;
		Error = {error, _Reason} ->
			throw (Error)
	end.


boot () ->
	boot (mosaic_rabbitmq, start).


boot (mosaic_rabbitmq, load) ->
	case application:load (mosaic_rabbitmq) of
		ok ->
			ok;
		{error, {already_loaded, mosaic_rabbitmq}} ->
			ok;
		Error = {error, _Reason} ->
			Error
	end;
	
boot (mosaic_rabbitmq, start) ->
	case boot (mosaic_rabbitmq, load) of
		ok ->
			case application:start (mosaic_rabbitmq) of
				ok ->
					ok;
				{error, {already_started, mosaic_rabbitmq}} ->
					ok;
				Error = {error, _Reason} ->
					throw (Error)
			end;
		Error = {error, _Reason} ->
			Error
	end;
	
boot (mosaic_rabbitmq_rabbit, load) ->
	MandatoryApplicationsStep1 = [sasl, os_mon, mnesia],
	MandatoryApplicationsStep2 = [rabbit, amqp_client],
	try
		{ok, OptionalApplicationsStep1, OptionalApplicationsStep2} = case application:get_env (mosaic_rabbitmq, management_enabled) of
			{ok, true} ->
				{ok,
						[inets, crypto, mochiweb, webmachine, rabbit_mochiweb],
						[rabbit_management_agent, rabbit_management]};
			{ok, false} ->
				{ok, [], []};
			{ok, Enabled} ->
				throw ({error, {invalid_configuration, {management_enabled, Enabled}}});
			undefined ->
				throw ({error, {invalid_configuration, {management_enabled, undefined}}})
		end,
		ok = lists:foreach (
				fun (Application) ->
					ok = case boot (Application, load) of
						ok ->
							ok;
						Error = {error, _Reason} ->
							throw (Error)
					end
				end,
				MandatoryApplicationsStep1 ++ OptionalApplicationsStep1 ++ MandatoryApplicationsStep2 ++ OptionalApplicationsStep2),
		ok
	catch
		throw : Error = {error, _Reason} ->
			Error
	end;
	
boot (mosaic_rabbitmq_rabbit, start) ->
	case boot (mosaic_rabbitmq_rabbit, load) of
		ok ->
			MandatoryApplicationsStep1 = [sasl, os_mon, mnesia],
			MandatoryApplicationsStep2 = [rabbit, amqp_client],
			try
				{ok, OptionalApplicationsStep1, OptionalApplicationsStep2} = case application:get_env (mosaic_rabbitmq, management_enabled) of
					{ok, true} ->
						{ok,
								[inets, crypto, mochiweb, webmachine, rabbit_mochiweb],
								[rabbit_management_agent, rabbit_management]};
					{ok, false} ->
						{ok, [], []};
					{ok, Enabled} ->
						throw ({error, {invalid_configuration, {management_enabled, Enabled}}});
					undefined ->
						throw ({error, {invalid_configuration, {management_enabled, undefined}}})
				end,
				ok = lists:foreach (
						fun (Application) ->
							ok = case boot (Application, start) of
								ok ->
									ok;
								Error = {error, _Reason} ->
									throw (Error)
							end
						end,
						MandatoryApplicationsStep1 ++ OptionalApplicationsStep1),
				ok = rabbit:prepare (),
				ok = lists:foreach (
						fun (Application) ->
							ok = case boot (Application, start) of
								ok ->
									ok;
								Error = {error, _Reason} ->
									throw (Error)
							end
						end,
						MandatoryApplicationsStep2 ++ OptionalApplicationsStep2),
				ok
			catch
				throw : Error = {error, _Reason} ->
					Error
			end;
		Error = {error, _Reason} ->
			Error
	end;
	
boot (Application, load)
		when is_atom (Application) ->
	case application:load (Application) of
		ok ->
			ok;
		{error, {already_loaded, Application}} ->
			ok;
		Error = {error, _Reason} ->
			throw (Error)
	end;
	
boot (Application, start)
		when is_atom (Application) ->
	case application:start (Application) of
		ok ->
			ok;
		{error, {already_started, Application}} ->
			ok;
		Error = {error, _Reason} ->
			throw (Error)
	end.
