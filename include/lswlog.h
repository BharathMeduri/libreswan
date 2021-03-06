/* logging declaratons
 *
 * Copyright (C) 1998-2001,2013 D. Hugh Redelmeier <hugh@mimosa.com>
 * Copyright (C) 2004 Michael Richardson <mcr@xelerance.com>
 * Copyright (C) 2012-2013 Paul Wouters <paul@libreswan.org>
 * Copyright (C) 2017 Andrew Cagney <cagney@gnu.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.  See <http://www.fsf.org/copyleft/gpl.txt>.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 */

#ifndef _LSWLOG_H_
#define _LSWLOG_H_

#include <libreswan.h>
#include <stdarg.h>
#include <stdio.h>
#include <stddef.h>

/* moved common code to library file */
#include "libreswan/passert.h"

#include "constants.h"

/*
 * NOTE: DBG's action can be a { } block, but that block must not
 * contain commas that are outside quotes or parenthesis.
 * If it does, they will be interpreted by the C preprocesser
 * as macro argument separators.  This happens accidentally if
 * multiple variables are declared in one declaration.
 *
 * IMPAIR currently uses the same lset_t as DBG.  Define a separate
 * macro so that, one day, that can change.
 */

extern lset_t cur_debugging;	/* current debugging level */

#define DBGP(cond)	(cur_debugging & (cond))
#define IMPAIR(BEHAVIOUR) (cur_debugging & (IMPAIR_##BEHAVIOUR))

#define DEBUG_PREFIX "| "

#define DBG(cond, action)	{ if (DBGP(cond)) { action; } }

/* signature needs to match printf() */
#define DBG_log libreswan_DBG_log
int libreswan_DBG_log(const char *message, ...) PRINTF_LIKE(1);

#define DBG_dump libreswan_DBG_dump
extern void libreswan_DBG_dump(const char *label, const void *p, size_t len);

#define DBG_dump_chunk(label, ch) DBG_dump(label, (ch).ptr, (ch).len)

#define DBG_cond_dump(cond, label, p, len) DBG(cond, DBG_dump(label, p, len))
#define DBG_cond_dump_chunk(cond, label, ch) DBG(cond, DBG_dump_chunk(label, \
								      ch))

/* Build up a diagnostic in a static buffer -- NOT RE-ENTRANT.
 * Although this would be a generally useful function, it is very
 * hard to come up with a discipline that prevents different uses
 * from interfering.  It is intended that by limiting it to building
 * diagnostics, we will avoid this problem.
 * Juggling is performed to allow an argument to be a previous
 * result: the new string may safely depend on the old one.  This
 * restriction is not checked in any way: violators will produce
 * confusing results (without crashing!).
 */
#define LOG_WIDTH	((size_t)1024)	/* roof of number of chars in log line */

extern err_t builddiag(const char *fmt, ...) PRINTF_LIKE(1);	/* NOT RE-ENTRANT */

extern bool log_to_stderr;          /* should log go to stderr? */

/*
 * For stand-alone tools.
 */
extern const char *progname;
extern void tool_init_log(const char *name);

/* Codes for status messages returned to whack.
 * These are 3 digit decimal numerals.  The structure
 * is inspired by section 4.2 of RFC959 (FTP).
 * Since these will end up as the exit status of whack, they
 * must be less than 256.
 * NOTE: ipsec_auto(8) knows about some of these numbers -- change carefully.
 */
enum rc_type {
	RC_COMMENT,		/* non-commital utterance (does not affect exit status) */
	RC_WHACK_PROBLEM,	/* whack-detected problem */
	RC_LOG,			/* message aimed at log (does not affect exit status) */
	RC_LOG_SERIOUS,		/* serious message aimed at log (does not affect exit status) */
	RC_SUCCESS,		/* success (exit status 0) */
	RC_INFORMATIONAL,	/* should get relayed to user - if there is one */
	RC_INFORMATIONAL_TRAFFIC, /* status of an established IPSEC (aka Phase 2) state */

	/* failure, but not definitive */
	RC_RETRANSMISSION = 10,

	/* improper request */
	RC_DUPNAME = 20,	/* attempt to reuse a connection name */
	RC_UNKNOWN_NAME,	/* connection name unknown or state number */
	RC_ORIENT,		/* cannot orient connection: neither end is us */
	RC_CLASH,		/* clash between two Road Warrior connections OVERLOADED */
	RC_DEAF,		/* need --listen before --initiate */
	RC_ROUTE,		/* cannot route */
	RC_RTBUSY,		/* cannot unroute: route busy */
	RC_BADID,		/* malformed --id */
	RC_NOKEY,		/* no key found through DNS */
	RC_NOPEERIP,		/* cannot initiate when peer IP is unknown */
	RC_INITSHUNT,		/* cannot initiate a shunt-oly connection */
	RC_WILDCARD,		/* cannot initiate when ID has wildcards */
	RC_CRLERROR,		/* CRL fetching disabled or obsolete reread cmd */

	/* permanent failure */
	RC_BADWHACKMESSAGE = 30,
	RC_NORETRANSMISSION,
	RC_INTERNALERR,
	RC_OPPOFAILURE,		/* Opportunism failed */
	RC_CRYPTOFAILED,	/* system too busy to perform required
				* cryptographic operations */
	RC_AGGRALGO,		/* multiple algorithms requested in phase 1 aggressive */
	RC_FATAL,		/* fatal error encountered, and negotiation aborted */

	/* entry of secrets */
	RC_ENTERSECRET = 40,
	RC_USERPROMPT = 41,

	/* progress: start of range for successful state transition.
	 * Actual value is RC_NEW_STATE plus the new state code.
	 */
	RC_NEW_STATE = 100,

	/* start of range for notification.
	 * Actual value is RC_NOTIFICATION plus code for notification
	 * that should be generated by this Pluto.
	 */
	RC_NOTIFICATION = 200	/* as per IKE notification messages */
};

/*
 * Log to both main log and whack log at level RC.
 */
#define loglog	libreswan_loglog
extern void libreswan_loglog(enum rc_type, const char *fmt, ...) PRINTF_LIKE(2);

/*
 * Log to both main log and whack log at level RC_LOG.
 */
#define plog	libreswan_log
/* signature needs to match printf() */
extern int libreswan_log(const char *fmt, ...) PRINTF_LIKE(1);

/*
 * Wrap <message> in a prefix and suffix where the suffix contains
 * errno and message.  Since __VA_ARGS__ may alter ERRNO, it needs to
 * be saved.
 */

void libreswan_log_errno(int e, const char *prefix,
			 const char *message, ...) PRINTF_LIKE(3);
void libreswan_exit(enum rc_type rc) NEVER_RETURNS;

#define LOG_ERRNO(ERRNO, ...)						\
	{								\
		int log_errno = ERRNO; /* save the value */		\
		libreswan_log_errno(log_errno, "ERROR: ", __VA_ARGS__);	\
	}

#define EXIT_LOG_ERRNO(ERRNO, ...)					\
	{								\
		int exit_log_errno = ERRNO; /* save the value */	\
		libreswan_log_errno(exit_log_errno, "FATAL ERROR: ", __VA_ARGS__); \
		libreswan_exit(PLUTO_EXIT_FAIL);			\
	}

/*
 * general utilities
 */

/* sanitize a string */
extern void sanitize_string(char *buf, size_t size);

/*
 * A generic buffer for accumulating unbounded output.
 */

struct lswlog;

/*
 * Standard routines for appending output to the log buffer.
 *
 * If there is insufficient space, the output is truncated and "..."
 * is appended.
 *
 * Similar to C99 snprintf() et.al., always return the untruncated
 * message length (the value can never be negative).
 *
 * XXX: is returning the length useful?
 */

size_t lswlogvf(struct lswlog *log, const char *format, va_list ap);
size_t lswlogf(struct lswlog *log, const char *format, ...) PRINTF_LIKE(2);
size_t lswlogs(struct lswlog *log, const char *string);
size_t lswlogl(struct lswlog *log, struct lswlog *buf);

/* _(SECERR: N (0xX): <error-string>) */
size_t lswlog_nss_error(struct lswlog *log);
/* _(in FUNC() at FILE:LINE) */
size_t lswlog_source_line(struct lswlog *log, const char *func,
			  const char *file, unsigned long line);
/* <string without binary characters> */
size_t lswlog_sanitized(struct lswlog *log, const char *string);
/* _Errno E: <strerror(E)> */
size_t lswlog_errno(struct lswlog *log, int e);
/* <hex-byte>:<hex-byte>... */
size_t lswlog_bytes(struct lswlog *log, const uint8_t *bytes,
		    size_t sizeof_bytes);
/* ipstr() */
size_t lswlog_ip(struct lswlog *log, const ip_address*);

/*
 * The logging output streams used by libreswan.
 *
 * So far three^D^D^D^D^D four^D^D^D^D five have been identified; and
 * lets not forget STDOUT and STDERR which are also written to
 * directly.
 *
 * The streams differ in the syslog severity and what PREFIX is
 * assumed to be present.
 *
 *                SEVERITY     WHACK   PREFIX
 *   log        LOG_WARNING     -      state
 *   debug      LOG_DEBUG       -      "| "
 *   logwhack   LOG_WARNING    yes     state
 *   error      LOG_ERR         -      ERROR ..
 *   whack         -           yes     NNN
 *
 * The streams will then add additional prefixes as required.  For
 * instance, the logwhack stream will prefix a timestamp when sending
 * to a file (optional), and will prefix NNN(RC) when sending to
 * whack.
 *
 * For tools, the log stream goes to STDERR when enabled; and the
 * debug stream goes to STDERR conditional on debug flags.
 */

void lswlog_to_log_stream(struct lswlog *buf);
void lswlog_to_debug_stream(struct lswlog *buf);
void lswlog_to_error_stream(struct lswlog *buf);
void lswlog_to_logwhack_stream(struct lswlog *buf, enum rc_type rc);
void lswlog_to_whack_stream(struct lswlog *buf);

/*
 * Code wrappers that cover up the details of allocating,
 * initializing, de-allocating (and possibly logging) a 'struct
 * lswlog' buffer.
 *
 * BUF (a C variable name) is declared locally as a pointer to the
 * 'struct lswlog' buffer.
 *
 * Implementation notes:
 *
 * This implementation puts the 'struct lswlog' on the stack.  Could
 * just as easily use the heap.  BUF is a pointer so that this
 * implementation detail is hidden.
 *
 * This implementation, unlike DBG(), does not have a code block
 * parameter.  Instead it uses for-loops to set things up for a code
 * block.  This avoids problems with "," within macro parameters
 * confusing the parser.  It also permits a simple consistent
 * indentation style.
 *
 * Apparently chaining void function calls using a comma is valid C?
 */

#define LSWBUF_ARRAY_(ARRAY, SIZEOF_ARRAY, BUF)				\
	for (struct lswlog lswlog = { .array = ARRAY, .len = 0, .bound = SIZEOF_ARRAY - 2, .roof = SIZEOF_ARRAY - 1, .dots = "...", }; \
	     lswlog_p; lswlog_p = false)				\
		for (struct lswlog *BUF = &lswlog;			\
		     lswlog_p; lswlog_p = false)			\
			for (BUF->array[BUF->len] = BUF->array[BUF->bound] = '\0', \
				     BUF->array[BUF->roof] = LSWBUF_CANARY; \
			     lswlog_p; lswlog_p = false)

#define LSWBUF_(BUF)							\
	for (char lswbuf[LOG_WIDTH]; lswlog_p; lswlog_p = false)	\
		LSWBUF_ARRAY_(lswbuf, sizeof(lswbuf), BUF)

/*
 * Wrap an existing array so lswlog*() routines can be called.
 *
 * For instance:
 */

#if 0
void lswbuf_array(char *b, size_t sizeof_b)
{
	LSWBUF_ARRAY(b, sizeof_b, buf) {
		lswlogf(buf, "written to the array");
	}
}
#endif

#define LSWBUF_ARRAY(ARRAY, SIZEOF_ARRAY, BUF)				\
	for (bool lswlog_p = true; lswlog_p; lswlog_p = false)		\
		LSWBUF_ARRAY_(ARRAY, SIZEOF_ARRAY, BUF)

/*
 * Scratch buffer for accumulating extra output.
 *
 * XXX: case should be expanded to illustrate how to stuff a truncated
 * version of the output into the LOG buffer.
 *
 * For instance:
 */

#if 0
void lswbuf(struct lswlog *log)
{
	LSWBUF(buf) {
		lswlogf(buf, "written to buf");
		lswlogl(log, buf); /* add to calling array */
	}
}
#endif

#define LSWBUF(BUF)							\
	for (bool lswlog_p = true; lswlog_p; lswlog_p = false)		\
		LSWBUF_(BUF)

/*
 * Write output to a FILE stream as a single block.
 *
 * For instance:
 */

#if 0
void lswlog_file(FILE f)
{
	LSWLOG_FILE(f, buf) {
		lswlogf(buf, "written to file");
	}
}
#endif

#define LSWLOG_FILE(FILE, BUF)						\
	for (bool lswlog_p = true; lswlog_p; lswlog_p = false)		\
		LSWBUF_(BUF)						\
			for (; lswlog_p;				\
			     lswlog_p = false,				\
				     lswlogs(BUF, "\n"),		\
				     fwrite(BUF->array, BUF->len, 1, FILE))


/*
 * Send output to WHACK (if attached).
 *
 * XXX: See programs/pluto/log.h for interface; should only be used in
 * pluto.  This code assumes that it is being called from the main
 * thread.
 */

#define LSWLOG_WHACK(RC, BUF)						\
	for (bool lswlog_p = whack_log_p(); lswlog_p; lswlog_p = false) \
		LSWBUF_(BUF)						\
			for (whack_log_pre(RC, BUF); lswlog_p;		\
			     lswlog_to_whack_stream(BUF),		\
				     lswlog_p = false)

/*
 * Send debug output to the logging streams (but not WHACK).
 */

void lswlog_dbg_pre(struct lswlog *buf);

#define LSWDBG_(PREDICATE, BUF)						\
	for (bool lswlog_p = PREDICATE; lswlog_p; lswlog_p = false)	\
		LSWBUF_(BUF)						\
			for (lswlog_dbg_pre(BUF); lswlog_p;		\
			     lswlog_to_debug_stream(BUF),		\
				     lswlog_p = false)

#define LSWDBGP(DEBUG, BUF) LSWDBG_(DBGP(DEBUG), BUF)
#define LSWLOG_DEBUG(BUF) LSWDBG_(true, BUF)

/*
 * Send log output the logging streams and WHACK (if connected).
 */

void lswlog_log_prefix(struct lswlog *buf);

#define LSWLOG(BUF)  LSWLOG_LOGWHACK(RC_LOG, BUF)

#define LSWLOG_LOGWHACK(RC, BUF)					\
	for (bool lswlog_p = true; lswlog_p; lswlog_p = false)		\
		LSWBUF_(BUF)						\
			for (lswlog_log_prefix(BUF); lswlog_p;			\
			     lswlog_to_logwhack_stream(BUF, RC),	\
				     lswlog_p = false)

/*
 * Send log output to the logging stream but not WHACK.
 */

#define LSWLOG_LOG(BUF)							\
	for (bool lswlog_p = true; lswlog_p; lswlog_p = false)		\
		LSWBUF_(BUF)						\
			for (lswlog_log_prefix(BUF); lswlog_p;		\
			     lswlog_to_log_stream(BUF),			\
				     lswlog_p = false)

/*
 * ARRAY, a previously allocated array, containing the accumulated
 * NUL-terminated output.
 *
 * The following offsets into ARRAY are maintained:
 *
 *    0 <= LEN <= BOUND < ROOF < sizeof(ARRAY)
 *
 * ROOF < sizeof(ARRAY); ARRAY[ROOF]==CANARY
 *
 * The offset to the last character in the array.  It contains a
 * canary intended to catch overflows.  When sizeof(ARRAY) is needed,
 * ROOF should be used as otherwise the canary may be corrupted.
 *
 * BOUND < ROOF; ARRAY[BOUND]=='\0'
 *
 * Limit on how many characters can be appended.
 *
 * LEN < BOUND; ARRAY[LEN]=='\0'
 *
 * Equivalent to strlen(BUF).  BOUND-LEN is always the amount of
 * unused space in the array.
 *
 * When LEN<BOUND, space for BOUND-LEN characters, including the
 * terminating NUL, is still available (when BOUND-LEN==1, a single
 * NUL (empty string) write is possible).
 *
 * When LEN==BOUND, the array is full and writes are discarded.
 *
 * When the ARRAY fills, the last few characters are overwritten with
 * DOTS.
 */

struct lswlog {
	char *array;
	/* 0 <= LEN < BOUND < ROOF */
	size_t len;
	size_t bound;
	size_t roof;
	const char *dots;
};

/*
 * To debug, set this to printf or similar.
 */
extern int (*lswlog_debugf)(const char *format, ...) PRINTF_LIKE(1);

/*
 * Since 'char' can be unsigned need to cast -2 onto a char sized
 * value.
 *
 * The octal equivalent would be something like '\376' but who uses
 * octal :-)
 */
#define LSWBUF_CANARY ((char) -2)

#endif /* _LSWLOG_H_ */
