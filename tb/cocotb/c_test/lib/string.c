/* minimal freestanding string functions. plain rv32i C, no assembly -- gcc at
 * -O2 turns the byte loops into word accesses where it is safe to. linked into
 * every program by the build scripts, not as a library */

#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n)
{
  char *d = dst;
  const char *s = src;
  while (n--) *d++ = *s++;
  return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
  char *d = dst;
  const char *s = src;
  if (d < s) {
    while (n--) *d++ = *s++;
  } else {
    d += n;
    s += n;
    while (n--) *--d = *--s;
  }
  return dst;
}

void *memset(void *dst, int c, size_t n)
{
  char *d = dst;
  while (n--) *d++ = (char)c;
  return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
  const unsigned char *x = a;
  const unsigned char *y = b;
  while (n--) {
    if (*x != *y) return *x - *y;
    x++;
    y++;
  }
  return 0;
}

size_t strlen(const char *s)
{
  const char *p = s;
  while (*p) p++;
  return p - s;
}

char *strcpy(char *dst, const char *src)
{
  char *d = dst;
  while ((*d++ = *src++));
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n)
{
  char *d = dst;
  while (n && (*d++ = *src++)) n--;
  while (n--) *d++ = '\0';
  return dst;
}

int strcmp(const char *a, const char *b)
{
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
  while (n && *a && *a == *b) {
    n--;
    a++;
    b++;
  }
  return n ? (unsigned char)*a - (unsigned char)*b : 0;
}

char *strcat(char *dst, const char *src)
{
  char *d = dst;
  while (*d) d++;
  while ((*d++ = *src++));
  return dst;
}

char *strncat(char *dst, const char *src, size_t n)
{
  char *d = dst;
  while (*d) d++;
  while (n-- && (*d++ = *src++));
  *d = '\0';
  return dst;
}

char *strchr(const char *s, int c)
{
  while (*s) {
    if (*s == (char)c) return (char *)s;
    s++;
  }
  return (c == '\0') ? (char *)s : 0;
}

char *strrchr(const char *s, int c)
{
  const char *found = 0;
  while (*s) {
    if (*s == (char)c) found = s;
    s++;
  }
  return (c == '\0') ? (char *)s : (char *)found;
}

char *strstr(const char *hay, const char *needle)
{
  if (!*needle) return (char *)hay;
  for (; *hay; hay++) {
    const char *h = hay;
    const char *n = needle;
    while (*h && *n && *h == *n) {
      h++;
      n++;
    }
    if (!*n) return (char *)hay;
  }
  return 0;
}
