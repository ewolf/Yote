#include <errno.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "util.h"

void
_files( char *diry, void (*fun)(char*) ) {
  DIR *d;
  struct dirent *dir;
  char *filedir;
  char **filearry;
  int count = 0;
  int max_idx;
  
  int dirlen = strlen( diry ) + 1;
  
  d = opendir( diry );
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        fileidx = atoi( dir->d_name );
        if ( fileidx > 0 || strcmp( dir->d_name, "0" ) == 0 )
          {
            count++;
            max_idx = fileidx > max_idx ? fileidx : max_idx;
            filedir = malloc( sizeof( char *) * (dirlen + strlen( dir->d_name ) ) );
            filedir[0] = '\0';
            strcat( filedir, diry );
            strcat( filedir, "/" );
            strcat( filedir, dir->d_name );
            fun( filedir );
            free( filedir );
          }
      }
    if( count > 0 ) {
      rewinddir( d );
      filearry = malloc( max_idx * (char*) );
      while ( NULL != (dir = readdir(d)) )
        {
          fileidx = atoi( dir->d_name );
          if ( fileidx > 0 || strcmp( dir->d_name, "0" ) == 0 )
            {
              filearry[fileidx] = strdup( dir->d_name );
              printf( "%d -> %s\n", fileidx, dir->d_name );
            }
        }
      
    }
  }

  closedir(d);
}

void _pr( char * fn ) {
  printf( "\t%s\n", fn );
}

void main()
{
  //  char zapp[] = "/home/wolf/foo/bar/baz";
  //  char zapp[] = "foo/bar/baz";
  //  make_path( zapp );
  //                 1000 (mem location for foo)  2000 (mem location for bar)  3000 for baz, ack at 4000
  //  char   foo -> [8]    <---- foo is 8, &foo is 1000
  //  char * bar -> [1000] <---- *bar is 8, bar is 1000, &bar is 2000
  //  char **baz -> [2000] <---- **baz is 8 *baz is 1000, baz is 2000, &baz is 3000
  //  char ***ack -> [3000] <---- ***ack is 8, **ack is 3000, ack is 3000. &ack is 4000
  //  _files("foo/bar/baz", _pr);
  printf( "%d it is?\n", atoi( "" ) );
}
