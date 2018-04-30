#ifndef _UTIL_SEEN
#define _UTIL_SEEN

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>


#if defined _WIN32 || defined __CYGWIN__
#define PATHSEP "\\"
#define PATHSEPCHAR '\\'
#else
#define PATHSEP "/"
#define PATHSEPCHAR '/'
#endif

#define CRY printf

int make_path( char *path );
int filecount( char *directory );
int filesize( char *file );
#endif
