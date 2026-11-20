#include <obs-module.h>
#include "ddp-source.h"

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("ddp-camera-source", "en-US")

bool obs_module_load(void)
{
    obs_register_source(&ddp_source_info);
    blog(LOG_INFO, "DDP Camera source plugin loaded (v1.0.0)");
    return true;
}

void obs_module_unload(void)
{
    blog(LOG_INFO, "DDP Camera source plugin unloaded");
}
