/* Log sink shared by the harnesses. freeciv's non-fatal fc_assert*() checks
 * (fc_fatal_assertions = -1) print "assertion '...' failed." and carry on by
 * returning an error value; on wire/save-controlled ids they fire on most
 * inputs and Mayhem files the printed line as a crash with no backtrace.
 * Only LOG_FATAL is kept; the checks and their error returns still run. */
#ifndef MAYHEM_FUZZ_LOG_H
#define MAYHEM_FUZZ_LOG_H

#include <stdio.h>

#include "log.h"

static void fuzz_log_callback(enum log_level level, const char *msg,
                              bool file_too)
{
  (void) file_too;
  if (level <= LOG_FATAL) {
    fprintf(stderr, "%s\n", msg);
  }
}

#endif
