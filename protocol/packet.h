#pragma once
#include <stdint.h>

// DDP Camera Protocol v1
// Transport: UDP
// Video: H.264 All-Intra (no B-frames, GOP=1)
// Audio: none

#define DDP_PROTOCOL_VERSION  1
#define DDP_MAX_PAYLOAD_SIZE  65000   // bytes per UDP packet
#define DDP_DEFAULT_PORT      5151

// Packet types
#define DDP_PKT_VIDEO         0x01
#define DDP_PKT_HANDSHAKE     0x02
#define DDP_PKT_KEEPALIVE     0x03

#pragma pack(push, 1)

// Header presente en todos los paquetes (12 bytes)
typedef struct {
    uint8_t  version;        // DDP_PROTOCOL_VERSION
    uint8_t  packet_type;    // DDP_PKT_*
    uint16_t sequence;       // numero de paquete, wraps around
    uint64_t timestamp_us;   // microsegundos desde inicio del stream
} ddp_header_t;

// Paquete de video (header + payload)
// Un frame H.264 puede fragmentarse en multiples paquetes UDP.
// frame_id identifica el frame, fragment_index/fragment_count indican la posicion.
typedef struct {
    ddp_header_t header;

    uint32_t frame_id;          // ID unico del frame (incrementa por frame)
    uint16_t fragment_index;    // indice de este fragmento (0-based)
    uint16_t fragment_count;    // total de fragmentos para este frame
    uint16_t width;             // resolucion del frame
    uint16_t height;
    uint32_t payload_size;      // bytes de datos H.264 en este paquete
    // seguido de payload_size bytes de datos H.264
} ddp_video_packet_t;

// Paquete de handshake (enviado por la app al conectar)
typedef struct {
    ddp_header_t header;
    uint16_t width;
    uint16_t height;
    uint8_t  fps;
    uint32_t bitrate_kbps;
} ddp_handshake_packet_t;

#pragma pack(pop)
