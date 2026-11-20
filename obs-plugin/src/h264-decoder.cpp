#include "h264-decoder.h"
#include <obs-module.h>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

struct H264Decoder::Impl {
    const AVCodec    *codec{nullptr};
    AVCodecContext   *ctx{nullptr};
    AVFrame          *frame{nullptr};
    AVPacket         *packet{nullptr};
    SwsContext       *sws{nullptr};
    bool              initialized{false};
};

H264Decoder::H264Decoder(obs_source_t *source)
    : m_source(source), m_impl(new Impl())
{
    m_impl->codec  = avcodec_find_decoder(AV_CODEC_ID_H264);
    m_impl->packet = av_packet_alloc();
    m_impl->frame  = av_frame_alloc();
}

H264Decoder::~H264Decoder()
{
    if (m_impl) {
        if (m_impl->ctx)    avcodec_free_context(&m_impl->ctx);
        if (m_impl->frame)  av_frame_free(&m_impl->frame);
        if (m_impl->packet) av_packet_free(&m_impl->packet);
        if (m_impl->sws)    sws_freeContext(m_impl->sws);
        delete m_impl;
    }
}

void H264Decoder::init_decoder(const uint8_t *extradata, size_t size)
{
    if (m_impl->initialized) return;

    m_impl->ctx = avcodec_alloc_context3(m_impl->codec);

    // Modo low-delay: sin buffering de frames B
    m_impl->ctx->flags  |= AV_CODEC_FLAG_LOW_DELAY;
    m_impl->ctx->flags2 |= AV_CODEC_FLAG2_FAST;
    m_impl->ctx->thread_count = 1;  // single-thread = menor latencia

    if (size > 0) {
        m_impl->ctx->extradata = (uint8_t*)av_mallocz(size + AV_INPUT_BUFFER_PADDING_SIZE);
        memcpy(m_impl->ctx->extradata, extradata, size);
        m_impl->ctx->extradata_size = (int)size;
    }

    if (avcodec_open2(m_impl->ctx, m_impl->codec, nullptr) < 0) {
        blog(LOG_ERROR, "[DDP] Failed to open H264 decoder");
        return;
    }

    m_impl->initialized = true;
    blog(LOG_INFO, "[DDP] H264 decoder initialized");
}

void H264Decoder::push_packet(const uint8_t *data, size_t size, uint64_t timestamp_us)
{
    if (!data || size == 0) return;

    if (!m_impl->initialized) {
        init_decoder(nullptr, 0);
        if (!m_impl->initialized) return;
    }

    decode_frame(data, size, timestamp_us);
}

void H264Decoder::decode_frame(const uint8_t *data, size_t size, uint64_t timestamp_us)
{
    AVPacket *pkt = m_impl->packet;
    av_packet_unref(pkt);

    pkt->data = const_cast<uint8_t*>(data);
    pkt->size = (int)size;
    pkt->pts  = (int64_t)timestamp_us;

    int ret = avcodec_send_packet(m_impl->ctx, pkt);
    if (ret < 0) return;

    while (avcodec_receive_frame(m_impl->ctx, m_impl->frame) == 0) {
        AVFrame *f = m_impl->frame;

        // Convertir YUV420P a I420 para OBS
        m_impl->sws = sws_getCachedContext(
            m_impl->sws,
            f->width, f->height, (AVPixelFormat)f->format,
            f->width, f->height, AV_PIX_FMT_YUV420P,
            SWS_POINT, nullptr, nullptr, nullptr
        );

        // Preparar frame OBS
        obs_source_frame obs_frame{};
        obs_frame.width      = f->width;
        obs_frame.height     = f->height;
        obs_frame.format     = VIDEO_FORMAT_I420;
        obs_frame.timestamp  = timestamp_us * 1000;  // nanosegundos para OBS

        // Planos I420: Y, U, V
        uint32_t y_size  = f->width * f->height;
        uint32_t uv_size = y_size / 4;
        std::vector<uint8_t> buf(y_size + 2 * uv_size);

        uint8_t *dst[4]    = { buf.data(), buf.data() + y_size, buf.data() + y_size + uv_size, nullptr };
        int dst_stride[4]  = { f->width, f->width / 2, f->width / 2, 0 };

        sws_scale(m_impl->sws, f->data, f->linesize, 0, f->height, dst, dst_stride);

        obs_frame.data[0]     = dst[0];
        obs_frame.data[1]     = dst[1];
        obs_frame.data[2]     = dst[2];
        obs_frame.linesize[0] = f->width;
        obs_frame.linesize[1] = f->width / 2;
        obs_frame.linesize[2] = f->width / 2;

        obs_source_output_video(m_source, &obs_frame);
    }
}
