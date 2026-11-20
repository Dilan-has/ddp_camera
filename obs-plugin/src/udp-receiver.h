#pragma once
#include <cstdint>
#include <functional>
#include <thread>
#include <atomic>
#include <unordered_map>
#include <vector>
#include "../../../../protocol/packet.h"

// Callback: datos H.264 completos de un frame, timestamp en microsegundos
using FrameCallback = std::function<void(const uint8_t*, size_t, uint64_t)>;

class UdpReceiver {
public:
    UdpReceiver(uint16_t port, FrameCallback callback);
    ~UdpReceiver();

    void start();
    void stop();
    void set_port(uint16_t port);

private:
    void receive_loop();
    void handle_video_packet(const uint8_t *buf, size_t len);

    uint16_t      m_port;
    FrameCallback m_callback;
    std::thread   m_thread;
    std::atomic<bool> m_running{false};

#ifdef _WIN32
    uintptr_t m_sock{(uintptr_t)-1};  // SOCKET
#else
    int m_sock{-1};
#endif

    // Ensamblado de frames fragmentados
    struct FrameBuffer {
        std::vector<std::vector<uint8_t>> fragments;
        uint16_t total_fragments{0};
        uint16_t received{0};
        uint64_t timestamp_us{0};
    };
    std::unordered_map<uint32_t, FrameBuffer> m_frames;
};
