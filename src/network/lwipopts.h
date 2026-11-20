#pragma once
// IPv4/DHCP connectivity only. No sockets, TCP services or IPv6.
#define NO_SYS 1
#define LWIP_SOCKET 0
#define LWIP_NETCONN 0
#define LWIP_IPV4 1
#define LWIP_IPV6 0
#define LWIP_DHCP 1
#define LWIP_DNS 1
#define LWIP_TCP 0
#define LWIP_UDP 1
#define LWIP_ICMP 1
#define LWIP_AUTOIP 0
#define MEM_ALIGNMENT 4
#define MEM_SIZE 4000
#define MEM_LIBC_MALLOC 0
#define PBUF_POOL_SIZE 8
#define MEMP_NUM_SYS_TIMEOUT 8
#define LWIP_NETIF_HOSTNAME 1
#define LWIP_STATS 0
#define LWIP_DEBUG 0
#define LWIP_CHKSUM_ALGORITHM 3

// Raw NTP timestamps retain fraction/era information for Swift validation.
#include <stdint.h>
void radio_clock_sntp_sample(uint32_t seconds, uint32_t fraction);
void radio_clock_sntp_nonce(uint32_t* seconds, uint32_t* microseconds);
#define SNTP_SERVER_DNS 1
#define SNTP_CHECK_RESPONSE 2
#define SNTP_COMP_ROUNDTRIP 0
#define SNTP_SET_SYSTEM_TIME_NTP(sec, frac) radio_clock_sntp_sample((uint32_t)(sec), (uint32_t)(frac))
#define SNTP_GET_SYSTEM_TIME(sec, us) radio_clock_sntp_nonce(&(sec), &(us))

struct pbuf;
int radio_clock_sntp_filter(struct pbuf* packet);
#define LWIP_HOOK_IP4_INPUT(packet, interface) radio_clock_sntp_filter(packet)
