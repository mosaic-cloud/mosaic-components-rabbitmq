
{application, mosaic_rabbitmq, [
	{description, "mOSAIC rabbitmq component"},
	{vsn, "1"},
	{applications, [kernel, stdlib]},
	{modules, [mosaic_rabbitmq_app, mosaic_rabbitmq_sup, mosaic_rabbitmq_component]},
	{registered, [mosaic_rabbitmq_sup, mosaic_rabbitmq_component]},
	{mod, {mosaic_rabbitmq_app, defaults}},
	{env, []}
]}.
