// Minimal self-serving HTTP server: serves its own executable as text/html.
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <fcntl.h>
#include <cosmo.h>                   // GetProgramExecutableName()

#define PORT 8080
static char self[1 << 20];           // whole file, read once at startup

int main(void) {
  int fd = open(GetProgramExecutableName(), O_RDONLY);
  long n = read(fd, self, sizeof self);
  int s = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {AF_INET, htons(PORT), {htonl(INADDR_LOOPBACK)}};
  if (bind(s, (void *)&a, sizeof a)) return 1;  // port taken: exit
  listen(s, SOMAXCONN);
  for (;;) {
    int c = accept(s, 0, 0);
    char junk[4096];
    read(c, junk, sizeof junk);      // drain the request, never parse it
    static const char hdr[] = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n";
    write(c, hdr, sizeof hdr - 1);
    write(c, self, n);
    close(c);
  }
}
