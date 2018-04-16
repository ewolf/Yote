#ifndef _UTIL_SEEN
#define _UTIL_SEEN

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>


#if defined _WIN32 || defined __CYGWIN__
#define PATHSEP "\\"
#else
#define PATHSEP "/"
#endif

int make_path( char *path );

#endif
