#pragma once
#include <obs-module.h>
#include <cstdint>

// Decodifica NAL units H.264 y entrega frames a OBS via obs_source_output_video
class H264Decoder {
public:
    explicit H264Decoder(obs_source_t *source);
    ~H264Decoder();

    void push_packet(const uint8_t *data, size_t size, uint64_t timestamp_us);

private:
    obs_source_t *m_source;

    // ffmpeg / libav contexto — se inicializa al primer SPS/PPS
    struct Impl;
    Impl *m_impl{nullptr};

    void init_decoder(const uint8_t *sps_pps, size_t size);
    void decode_frame(const uint8_t *data, size_t size, uint64_t timestamp_us);
};
