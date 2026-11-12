/* Network packet decoder over bytes read from a socket, without the dispatch
 * (server/sernet.c incoming_client_packets for the server role). Built twice:
 * as fuzz_packets for the client role (server-to-client packets) and, with
 * -DFUZZ_PACKETS_SERVER, as fuzz_packets_server for the server role
 * (client-to-server packets). The role is fixed per process because libfreeciv
 * caches the packet handler tables on first use. Byte 0 picks the header
 * layout (bit 0) and the handler set, initial or full capability (bit 1);
 * the rest is the socket buffer. */
#ifdef HAVE_CONFIG_H
#include <fc_config.h>
#endif

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "capstr.h"
#include "connection.h"
#include "dataio.h"
#include "fc_interface.h"
#include "log.h"
#include "fuzz_log.h"
#include "packets.h"

static void close_cb(struct connection *pconn)
{
  (void) pconn;
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  log_init(NULL, LOG_FATAL, fuzz_log_callback, NULL, -1);
#ifdef FUZZ_PACKETS_SERVER
  i_am_server();
#else
  i_am_client();
#endif
  init_our_capability();
  connections_set_close_callback(close_cb);
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  struct connection conn;
  enum packet_type type;
  void *packet;
  int budget = 64;

  if (size < 1) {
    return -1;
  }

  memset(&conn, 0, sizeof(conn));
  conn.sock = -1;
  connection_common_init(&conn);
  if (data[0] & 1) {
    conn.packet_header.type = DIOT_UINT16;
  }
  if (data[0] & 2) {
    conn_set_capability(&conn, our_capability);
  }

  size--;
  data++;
  if (size > (size_t) conn.buffer->nsize) {
    size = conn.buffer->nsize;
  }
  memcpy(conn.buffer->data, data, size);
  conn.buffer->ndata = (int) size;

  while (budget-- > 0
         && (packet = get_packet_from_connection(&conn, &type, FALSE))
            != NULL) {
    packet_destroy(packet, type);
  }

  connection_common_close(&conn);

  return 0;
}
