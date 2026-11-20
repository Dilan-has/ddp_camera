#include "udp-receiver.h"
#include <obs-module.h>
#include <cstring>
#include <numeric>

#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
   typedef SOCKET sock_t;
#  define INVALID_SOCK INVALID_SOCKET
#  define CLOSE_SOCK(s) closesocket(s)
#else
#  include <sys/socket.h>
#  include <netinet/in.h>
#  include <unistd.h>
   typedef int sock_t;
#  define INVALID_SOCK (-1)
#  define CLOSE_SOCK(s) close(s)
#endif

UdpReceiver::UdpReceiver(uint16_t port, FrameCallback callback)
    : m_port(port), m_callback(std::move(callback))
{
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
}

UdpReceiver::~UdpReceiver()
{
    stop();
}

void UdpReceiver::set_port(uint16_t port)
{
    m_port = port;
}

void UdpReceiver::start()
{
    if (m_running) return;

    sock_t s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCK) {
        blog(LOG_ERROR, "[DDP] Failed to create UDP socket");
        return;
    }

    // Permitir reutilizar puerto
    int opt = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));

    // Buffer de recepcion grande para frames de alta calidad
    int buf_size = 4 * 1024 * 1024;  // 4 MB
    setsockopt(s, SOL_SOCKET, SO_RCVBUF, (const char*)&buf_size, sizeof(buf_size));

    struct sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(m_port);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        blog(LOG_ERROR, "[DDP] Failed to bind UDP socket to port %d", m_port);
        CLOSE_SOCK(s);
        return;
    }

#ifdef _WIN32
    m_sock = (uintptr_t)s;
#else
    m_sock = s;
#endif

    m_running = true;
    m_thread  = std::thread(&UdpReceiver::receive_loop, this);
    blog(LOG_INFO, "[DDP] UDP receiver started on port %d", m_port);
}

void UdpReceiver::stop()
{
    if (!m_running) return;
    m_running = false;

#ifdef _WIN32
    if (m_sock != (uintptr_t)-1) {
        CLOSE_SOCK((sock_t)m_sock);
        m_sock = (uintptr_t)-1;
    }
#else
    if (m_sock >= 0) {
        CLOSE_SOCK(m_sock);
        m_sock = -1;
    }
#endif

    if (m_thread.joinable()) m_thread.join();
    m_frames.clear();
}

void UdpReceiver::receive_loop()
{
    static const size_t BUF_SIZE = sizeof(ddp_video_packet_t) + DDP_MAX_PAYLOAD_SIZE;
    std::vector<uint8_t> buf(BUF_SIZE);

    while (m_running) {
        int received = recv((sock_t)m_sock, (char*)buf.data(), (int)BUF_SIZE, 0);
        if (received <= 0) break;

        if ((size_t)received < sizeof(ddp_header_t)) continue;

        const ddp_header_t *header = reinterpret_cast<const ddp_header_t*>(buf.data());
        if (header->version != DDP_PROTOCOL_VERSION) continue;

        if (header->packet_type == DDP_PKT_VIDEO) {
            handle_video_packet(buf.data(), received);
        }
    }
}

void UdpReceiver::handle_video_packet(const uint8_t *buf, size_t len)
{
    if (len < sizeof(ddp_video_packet_t)) return;

    const ddp_video_packet_t *pkt = reinterpret_cast<const ddp_video_packet_t*>(buf);
    const uint8_t *payload        = buf + sizeof(ddp_video_packet_t);
    size_t payload_size           = pkt->payload_size;

    if (len < sizeof(ddp_video_packet_t) + payload_size) return;

    auto &frame = m_frames[pkt->frame_id];

    // Inicializar buffer en el primer fragmento
    if (frame.total_fragments == 0) {
        frame.total_fragments = pkt->fragment_count;
        frame.fragments.resize(pkt->fragment_count);
        frame.timestamp_us = pkt->header.timestamp_us;
    }

    // Almacenar fragmento si no habia llegado aun
    if (frame.fragments[pkt->fragment_index].empty()) {
        frame.fragments[pkt->fragment_index].assign(payload, payload + payload_size);
        frame.received++;
    }

    // Frame completo — ensamblar y entregar
    if (frame.received == frame.total_fragments) {
        size_t total = 0;
        for (auto &f : frame.fragments) total += f.size();

        std::vector<uint8_t> assembled(total);
        size_t offset = 0;
        for (auto &f : frame.fragments) {
            memcpy(assembled.data() + offset, f.data(), f.size());
            offset += f.size();
        }

        m_callback(assembled.data(), assembled.size(), frame.timestamp_us);
        m_frames.erase(pkt->frame_id);

        // Limpiar frames viejos para evitar acumulacion de memoria
        if (m_frames.size() > 10) {
            uint32_t oldest = pkt->frame_id - 10;
            m_frames.erase(oldest);
        }
    }
}
