/* Registry (secfile) text parser: the format of savegames, rulesets and
 * the server settings. Takes bytes only from the fuzzer; the first byte
 * selects allow_duplicates, like the two modes real callers use. */
#ifdef HAVE_CONFIG_H
#include <fc_config.h>
#endif

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "log.h"
#include "fuzz_log.h"
#include "registry.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  log_init(NULL, LOG_FATAL, fuzz_log_callback, NULL, -1);
  return 0;
}

static void walk(struct section_file *sf)
{
  const struct section_list *sections = secfile_sections(sf);
  char path[256];

  if (sections == NULL) {
    return;
  }
  section_list_iterate(sections, psection) {
    entry_list_iterate(section_entries(psection), pentry) {
      int ival;
      bool bval;
      float fval;

      if (entry_path(pentry, path, sizeof(path)) <= 0) {
        continue;
      }
      switch (entry_type_get(pentry)) {
      case ENTRY_INT:
        (void) secfile_lookup_int(sf, &ival, "%s", path);
        break;
      case ENTRY_BOOL:
        (void) secfile_lookup_bool(sf, &bval, "%s", path);
        break;
      case ENTRY_FLOAT:
        (void) secfile_lookup_float(sf, &fval, "%s", path);
        break;
      case ENTRY_STR:
        (void) secfile_lookup_str(sf, "%s", path);
        break;
      default:
        break;
      }
    } entry_list_iterate_end;
  } section_list_iterate_end;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  struct section_file *sf;
  char *buf;
  const char *tmpdir;
  char out[4096];
  int fd;

  if (size < 1 || size > (1 << 24)) {
    return -1;
  }

  buf = malloc(size - 1 + 1);
  memcpy(buf, data + 1, size - 1);
  sf = secfile_from_stream(fz_from_memory(buf, (int) (size - 1), TRUE),
                           data[0] & 1);
  if (sf == NULL) {
    return -1;
  }

  walk(sf);

  tmpdir = getenv("TMPDIR");
  snprintf(out, sizeof(out), "%s/fuzz_secfile.XXXXXX",
           tmpdir != NULL ? tmpdir : "/tmp");
  fd = mkstemp(out);
  if (fd >= 0) {
    close(fd);
    secfile_save(sf, out, 0, FZ_PLAIN, TRUE);
    unlink(out);
  }

  secfile_destroy(sf);

  return 0;
}
