#include "ddp-source.h"
#include "udp-receiver.h"
#include "h264-decoder.h"
#include <obs-module.h>
#include <memory>

struct ddp_source {
    obs_source_t       *source;
    std::unique_ptr<UdpReceiver>  receiver;
    std::unique_ptr<H264Decoder>  decoder;
    uint16_t            port;
    bool                active;
};

static const char *ddp_source_get_name(void *)
{
    return "DDP Camera Source";
}

static void *ddp_source_create(obs_data_t *settings, obs_source_t *source)
{
    auto ctx = new ddp_source();
    ctx->source = source;
    ctx->active = false;
    ctx->port   = (uint16_t)obs_data_get_int(settings, "port");

    ctx->decoder  = std::make_unique<H264Decoder>(source);
    ctx->receiver = std::make_unique<UdpReceiver>(
        ctx->port,
        [ctx](const uint8_t *data, size_t size, uint64_t timestamp_us) {
            ctx->decoder->push_packet(data, size, timestamp_us);
        }
    );

    ctx->receiver->start();
    ctx->active = true;

    blog(LOG_INFO, "[DDP] Source created, listening on port %d", ctx->port);
    return ctx;
}

static void ddp_source_destroy(void *data)
{
    auto ctx = static_cast<ddp_source *>(data);
    if (ctx->receiver) ctx->receiver->stop();
    delete ctx;
}

static void ddp_source_get_defaults(obs_data_t *settings)
{
    obs_data_set_default_int(settings, "port", 5151);
}

static obs_properties_t *ddp_source_get_properties(void *)
{
    obs_properties_t *props = obs_properties_create();
    obs_properties_add_int(props, "port", "UDP Port", 1024, 65535, 1);
    return props;
}

static void ddp_source_update(void *data, obs_data_t *settings)
{
    auto ctx = static_cast<ddp_source *>(data);
    uint16_t new_port = (uint16_t)obs_data_get_int(settings, "port");

    if (new_port != ctx->port) {
        ctx->receiver->stop();
        ctx->port = new_port;
        ctx->receiver->set_port(new_port);
        ctx->receiver->start();
    }
}

struct obs_source_info ddp_source_info = {
    .id             = "ddp_camera_source",
    .type           = OBS_SOURCE_TYPE_INPUT,
    .output_flags   = OBS_SOURCE_ASYNC_VIDEO,
    .get_name       = ddp_source_get_name,
    .create         = ddp_source_create,
    .destroy        = ddp_source_destroy,
    .get_defaults   = ddp_source_get_defaults,
    .get_properties = ddp_source_get_properties,
    .update         = ddp_source_update,
};
