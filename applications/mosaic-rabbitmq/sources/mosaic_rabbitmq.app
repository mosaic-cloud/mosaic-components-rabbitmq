
{application, mosaic_rabbitmq, [
	{description, "mOSAIC rabbitmq component"},
	{vsn, "1"},
	{applications, [kernel, stdlib, mosaic_component]},
	{modules, []},
	{registered, []},
	{mod, {mosaic_dummy_app, defaults}},
	{env, []}
]}.
