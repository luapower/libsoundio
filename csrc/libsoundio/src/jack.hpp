/*
 * Copyright (c) 2015 Andrew Kelley
 *
 * This file is part of libsoundio, which is MIT licensed.
 * See http://opensource.org/licenses/MIT
 */

#ifndef SOUNDIO_JACK_HPP
#define SOUNDIO_JACK_HPP

#include "soundio_private.h"
#include "os.h"
#include "atomics.hpp"

#include <jack/jack.h>

int soundio_jack_init(struct SoundIoPrivate *si);

struct SoundIoDeviceJackPort {
    char *full_name;
    int full_name_len;
    SoundIoChannelId channel_id;
    jack_latency_range_t latency_range;
};

struct SoundIoDeviceJack {
    int port_count;
    SoundIoDeviceJackPort *ports;
};

struct SoundIoJack {
    jack_client_t *client;
    SoundIoOsMutex *mutex;
    SoundIoOsCond *cond;
    atomic_flag refresh_devices_flag;
    int sample_rate;
    int period_size;
    bool is_shutdown;
    bool emitted_shutdown_cb;
};

struct SoundIoOutStreamJackPort {
    jack_port_t *source_port;
    const char *dest_port_name;
    int dest_port_name_len;
};

struct SoundIoOutStreamJack {
    jack_client_t *client;
    int period_size;
    int frames_left;
    bool is_paused;
    double hardware_latency;
    SoundIoOutStreamJackPort ports[SOUNDIO_MAX_CHANNELS];
    SoundIoChannelArea areas[SOUNDIO_MAX_CHANNELS];
};

struct SoundIoInStreamJackPort {
    jack_port_t *dest_port;
    const char *source_port_name;
    int source_port_name_len;
};

struct SoundIoInStreamJack {
    jack_client_t *client;
    int period_size;
    int frames_left;
    double hardware_latency;
    SoundIoInStreamJackPort ports[SOUNDIO_MAX_CHANNELS];
    SoundIoChannelArea areas[SOUNDIO_MAX_CHANNELS];
    char *buf_ptrs[SOUNDIO_MAX_CHANNELS];
};

#endif
