//
//  BTRDV3KPacket.h
//
//  Copyright (c) 2015 - Jeremy C. McDermond (NH6Z)

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

#ifndef Buster_BTRDV3KPacket_h
#define Buster_BTRDV3KPacket_h

#define DV3K_TYPE_CONTROL 0x00
#define DV3K_TYPE_AMBE 0x01
#define DV3K_TYPE_AUDIO 0x02

static const unsigned char DV3K_START_BYTE   = 0x61;

static const unsigned char DV3K_CONTROL_RATEP  = 0x0A;
static const unsigned char DV3K_CONTROL_PRODID = 0x30;
static const unsigned char DV3K_CONTROL_VERSTRING = 0x31;
static const unsigned char DV3K_CONTROL_RESET = 0x33;
static const unsigned char DV3K_CONTROL_READY = 0x39;
static const unsigned char DV3K_CONTROL_CHANFMT = 0x15;

static const unsigned char DV3K_AMBE_FIELD_CMODE = 0x02;
static const unsigned char DV3K_AMBE_FIELD_TONE = 0x08;
static const unsigned char DV3K_AMBE_FIELD_CHAND = 0x01;

static const unsigned char DV3K_AUDIO_FIELD_SPEECHD = 0x00;

static const char ratep_values[12] = { 0x01, 0x30, 0x07, 0x63, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48 };

//  The size of a dv3k header is the start byte, plus header size plus the payload length
#define dv3k_packet_size(a) (1 + sizeof((a).header) + ntohs((a).header.payload_length))

#pragma pack(push, 1)
struct dv3k_packet {
    unsigned char start_byte;
    struct {
        unsigned short payload_length;
        unsigned char packet_type;
    } header;
    union {
        struct {
            unsigned char field_id;
            union {
                char prodid[16];
                char ratep[12];
                char version[48];
                short chanfmt;
            } data;
        } ctrl;
        struct {
            unsigned char field_id;
            unsigned char num_samples;
            short samples[160];
            unsigned char cmode_field_id;
            short cmode_value;
        } audio;
        struct {
            struct {
                unsigned char field_id;
                unsigned char num_bits;
                unsigned char data[9];
            } data;
            struct {
                unsigned char field_id;
                unsigned short value;
            } cmode;
            struct {
                unsigned char field_id;
                unsigned char tone;
                unsigned char amplitude;
            } tone;
        } ambe;
    } payload;
};
#pragma pack(pop)

#endif
