#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  if (argc < 2 || argv[1][0] != '/') {
    fputs("expected an absolute executable path\n", stderr);
    return 64;
  }
  if (setpgid(0, 0) != 0) {
    perror("setpgid");
    return 71;
  }
  execv(argv[1], &argv[1]);
  int error = errno;
  perror("execv");
  return error == ENOENT ? 69 : 70;
}
