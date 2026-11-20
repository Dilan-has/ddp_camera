cmake_minimum_required(VERSION 3.16)
project(ddp-camera-source VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# OBS Studio path - ajustar segun instalacion local
if(NOT DEFINED OBS_SOURCE_DIR)
    set(OBS_SOURCE_DIR "C:/obs-studio" CACHE PATH "OBS Studio source directory")
endif()

find_package(libobs REQUIRED
    HINTS "${OBS_SOURCE_DIR}/build" "${OBS_SOURCE_DIR}/cmake"
)

set(SOURCES
    src/plugin-main.cpp
    src/ddp-source.cpp
    src/udp-receiver.cpp
    src/h264-decoder.cpp
)

set(HEADERS
    src/ddp-source.h
    src/udp-receiver.h
    src/h264-decoder.h
    ${CMAKE_SOURCE_DIR}/../protocol/packet.h
)

add_library(ddp-camera-source MODULE ${SOURCES} ${HEADERS})

target_include_directories(ddp-camera-source PRIVATE
    src/
    ${CMAKE_SOURCE_DIR}/../protocol/
)

target_link_libraries(ddp-camera-source
    OBS::libobs
)

# Windows: linkear Winsock para UDP
if(WIN32)
    target_link_libraries(ddp-camera-source ws2_32)
endif()

install(TARGETS ddp-camera-source
    LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}/obs-plugins/64bit"
)
