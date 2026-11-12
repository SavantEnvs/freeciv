/* Savegame loader: the `load` command / `--file` path (server/stdinhand.c
 * load_command) run in-process on an input registry file, with the server
 * state brought up the way srv_prepare() does but without any sockets.
 * Rulesets named by the save are read from the data directory next to the
 * binary (FREECIV_DATA_PATH overrides). */
#ifdef HAVE_CONFIG_H
#include <fc_config.h>
#endif

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "log.h"
#include "fuzz_log.h"
#include "registry.h"

#include "modpack.h"

#include "ai.h"
#include "edithand.h"
#include "sanitycheck.h"
#include "savemain.h"
#include "sernet.h"
#include "settings.h"
#include "srv_main.h"
#include "stdinhand.h"
#include "voting.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  char exe[PATH_MAX];
  ssize_t n;

  if (getenv("FREECIV_DATA_PATH") == NULL) {
    n = readlink("/proc/self/exe", exe, sizeof(exe) - 16);
    if (n > 0) {
      char *slash;

      exe[n] = '\0';
      slash = strrchr(exe, '/');
      if (slash != NULL) {
        strcpy(slash, "/data");
        setenv("FREECIV_DATA_PATH", exe, 0);
      }
    }
  }

  srv_init();
  init_connections();
  log_init(NULL, LOG_FATAL, fuzz_log_callback, NULL, -1);
  settings_init(TRUE);
  stdinhand_init();
  edithand_init();
  voting_init();
  ai_timer_init();
  modpacks_init();
  server_game_init(FALSE);

  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  struct section_file *sf;
  char *buf;

  if (size < 1 || size > (1 << 24)) {
    return -1;
  }

  buf = malloc(size);
  memcpy(buf, data, size);
  sf = secfile_from_stream(fz_from_memory(buf, (int) size, TRUE), FALSE);
  if (sf == NULL) {
    return -1;
  }

  /* savegame_load() writes the save's [settings] into the global setting
   * table and server_game_init(TRUE) keeps game.server.rulesetdir; reset both
   * so an input's result does not depend on the ones before it. */
  server_game_free();
  settings_free();
  settings_init(TRUE);
  server_game_init(FALSE);

  savegame_load(sf);
  secfile_destroy(sf);
  sanity_check();

  return 0;
}
