
-module (mosaic_rabbitmq_sup).

-behaviour (supervisor).


-export ([start_link/0]).
-export ([init/1]).


start_link () ->
	supervisor:start_link (mosaic_rabbitmq_sup, [defaults]).


init ([defaults]) ->
	{ok, {{one_for_all, 1, 60},
			[{mosaic_rabbitmq_component, {mosaic_rabbitmq_component, start_link, []}, permanent, 60, worker, dynamic}]}}.
