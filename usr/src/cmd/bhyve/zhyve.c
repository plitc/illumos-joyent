/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Copyright (c) 2018, Joyent, Inc.
 */

/*
 * This small 'zhyve' stub is init for the zone: we therefore need to pick up
 * our command-line arguments placed in ZHYVE_CMD_FILE by the boot stub, do a
 * little administration, and exec the real bhyve binary.
 */

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <libnvpair.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/corectl.h>

#define	ZHYVE_CMD_FILE	"/var/run/bhyve/zhyve.cmd"

/*
 * Do a read of the specified size or return an error.  Returns 0 on success
 * and -1 on error.  Sets errno to EINVAL if EOF is encountered.  For other
 * errors, see read(2).
 */
static int
full_read(int fd, char *buf, size_t len)
{
	ssize_t nread = 0;
	size_t totread = 0;

	while (totread < len) {
		nread = read(fd, buf + totread, len - totread);
		if (nread == 0) {
			errno = EINVAL;
			return (-1);
		}
		if (nread < 0) {
			if (errno == EINTR || errno == EAGAIN) {
				continue;
			}
			return (-1);
		}
		totread += nread;
	}
	assert(totread == len);

	return (0);
}

/*
 * Reads the command line options from the packed nvlist in the file referenced
 * by path.  On success, 0 is returned and the members of *argv reference memory
 * allocated from an nvlist.  On failure, -1 is returned.
 */

static int
parse_options_file(const char *path, uint_t *argcp, char ***argvp)
{
	int fd = -1;
	struct stat stbuf;
	char *buf = NULL;
	nvlist_t *nvl = NULL;
	int ret;

	if ((fd = open(path, O_RDONLY)) < 0 ||
	    fstat(fd, &stbuf) != 0 ||
	    (buf = malloc(stbuf.st_size)) == NULL ||
	    full_read(fd, buf, stbuf.st_size) != 0 ||
	    nvlist_unpack(buf, stbuf.st_size, &nvl, 0) != 0 ||
	    nvlist_lookup_string_array(nvl, "bhyve_args", argvp, argcp) != 0) {
		nvlist_free(nvl);
		ret = -1;
	} else {
		ret = 0;
	}

	free(buf);
	(void) close(fd);

	(void) printf("Configuration from %s:\n", path);
	nvlist_print(stdout, nvl);

	return (ret);
}

/*
 * Setup to suppress core dumps within the zone.
 */
static void
config_core_dumps()
{
	(void) core_set_options(0x0);
}

int
main(int argc, char **argv)
{
	char **tmpargs;
	uint_t zargc;
	char **zargv;
	int fd;

	config_core_dumps();

	fd = open("/dev/null", O_WRONLY);
	assert(fd >= 0);
	if (fd != STDIN_FILENO) {
		(void) dup2(fd, STDIN_FILENO);
		(void) close(fd);
	}

	fd = open("/dev/zfd/1", O_WRONLY);
	assert(fd >= 0);
	if (fd != STDOUT_FILENO) {
		(void) dup2(fd, STDOUT_FILENO);
		(void) close(fd);
	}
	setvbuf(stdout, NULL, _IONBF, 0);

	fd = open("/dev/zfd/2", O_WRONLY);
	assert(fd >= 0);
	if (fd != STDERR_FILENO) {
		(void) dup2(fd, STDERR_FILENO);
		(void) close(fd);
	}
	setvbuf(stderr, NULL, _IONBF, 0);

	if (parse_options_file(ZHYVE_CMD_FILE, &zargc, &zargv) != 0) {
		(void) fprintf(stderr, "%s: failed to parse %s: %s\n",
		    argv[0], ZHYVE_CMD_FILE, strerror(errno));
		return (EXIT_FAILURE);
	}

	/*
	 * Annoyingly, we need a NULL at the end.
	 */

	if ((tmpargs = malloc(sizeof (*zargv) * (zargc + 1))) == NULL) {
		perror("malloc failed");
		return (EXIT_FAILURE);
	}

	memcpy(tmpargs, zargv, sizeof (*zargv) * zargc);
	tmpargs[zargc] = NULL;

	(void) execv("/usr/sbin/bhyve", tmpargs);

	perror("execv failed");
	return (EXIT_FAILURE);
}
