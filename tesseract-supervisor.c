/*
 * tesseract-supervisor: monitor and restart tesseract-daemon on crashes.
 *
 * Forks and execs tesseract-daemon, passing through all arguments.
 * On clean exit (code 0): supervisor exits 0.
 * On crash (signal or non-zero exit): logs, waits 1s, restarts.
 * Rapid crash protection: 5 crashes within 60 seconds = give up.
 * Forwards SIGINT/SIGTERM to the child for clean shutdown.
 *
 * Usage: tesseract-supervisor [tesseract-daemon args...]
 */

#include <errno.h>
#include <libgen.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_CRASHES	5
#define CRASH_WINDOW	60	/* seconds */

static volatile sig_atomic_t got_signal = 0;
static volatile pid_t child_pid = 0;

static void forward_signal(int sig)
{
	got_signal = sig;
	if (child_pid > 0)
		kill(child_pid, sig);
}

/*
 * Derive the daemon path from argv[0].
 * If argv[0] contains a '/', replace the basename with "tesseract-daemon".
 * Otherwise use "tesseract-daemon" and rely on PATH.
 */
static char *daemon_path(const char *argv0)
{
	static char path[4096];
	const char *slash = strrchr(argv0, '/');

	if (slash) {
		size_t dirlen = slash - argv0 + 1;
		if (dirlen + strlen("tesseract-daemon") >= sizeof(path)) {
			fprintf(stderr, "supervisor: path too long\n");
			exit(1);
		}
		memcpy(path, argv0, dirlen);
		memcpy(path + dirlen, "tesseract-daemon", strlen("tesseract-daemon") + 1);
	} else {
		snprintf(path, sizeof(path), "tesseract-daemon");
	}
	return path;
}

int main(int argc, char **argv)
{
	time_t crashes[MAX_CRASHES];
	int crash_idx = 0;
	int crash_count = 0;

	char *daemon = daemon_path(argv[0]);

	/* build child argv: daemon + original args (skip argv[0]) */
	char **child_argv = calloc(argc + 1, sizeof(char *));
	if (!child_argv) {
		perror("calloc");
		return 1;
	}
	child_argv[0] = daemon;
	for (int i = 1; i < argc; i++)
		child_argv[i] = argv[i];
	child_argv[argc] = NULL;

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = forward_signal;
	sa.sa_flags = SA_RESTART;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	fprintf(stderr, "supervisor: starting %s\n", daemon);

	for (;;) {
		pid_t pid = fork();
		if (pid < 0) {
			perror("supervisor: fork");
			free(child_argv);
			return 1;
		}

		if (pid == 0) {
			/* child: reset signals and exec */
			signal(SIGINT, SIG_DFL);
			signal(SIGTERM, SIG_DFL);
			execv(daemon, child_argv);
			perror("supervisor: execv");
			_exit(127);
		}

		child_pid = pid;
		got_signal = 0;

		int status;
		while (waitpid(pid, &status, 0) < 0) {
			if (errno != EINTR) {
				perror("supervisor: waitpid");
				free(child_argv);
				return 1;
			}
		}
		child_pid = 0;

		/* clean exit */
		if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
			fprintf(stderr, "supervisor: daemon exited cleanly\n");
			free(child_argv);
			return 0;
		}

		/* we forwarded a signal and child exited — clean shutdown */
		if (got_signal) {
			fprintf(stderr, "supervisor: shutdown on signal %d\n", got_signal);
			free(child_argv);
			return 0;
		}

		/* crash — log details */
		if (WIFSIGNALED(status)) {
			fprintf(stderr, "supervisor: daemon killed by signal %d\n",
				WTERMSIG(status));
		} else if (WIFEXITED(status)) {
			fprintf(stderr, "supervisor: daemon exited with code %d\n",
				WEXITSTATUS(status));
		}

		/* rapid crash protection */
		time_t now = time(NULL);
		crashes[crash_idx] = now;
		crash_idx = (crash_idx + 1) % MAX_CRASHES;
		if (crash_count < MAX_CRASHES)
			crash_count++;

		if (crash_count == MAX_CRASHES) {
			/* check if oldest tracked crash is within the window */
			time_t oldest = crashes[crash_idx % MAX_CRASHES];
			if (now - oldest < CRASH_WINDOW) {
				fprintf(stderr, "supervisor: %d crashes in %d seconds, giving up\n",
					MAX_CRASHES, CRASH_WINDOW);
				free(child_argv);
				return 1;
			}
		}

		fprintf(stderr, "supervisor: restarting in 1 second...\n");
		sleep(1);
	}
}
