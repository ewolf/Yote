#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define PATHSEP "/"


void make_path( char * path ) {
  struct stat stat_buffer;
  char * tok;
  char * to;
  int errsv;
  
  // make a string large enough to hold the full path
  to = strdup( path );
  if ( '/' == path[0] ) {
    to[0] = '/';
    to[1] = '\0';
  } else {
    to[0] = '\0';
  }
  
  printf( "path : '%s'\n", path );
  
  tok = strtok( path, PATHSEP );
  while( tok ) {
    // check if path exists
    strcat( to, tok );
    fprintf( stderr, "Looking at %s --> %s\n", tok, to );
    if ( !( 0 == stat( tok, &stat_buffer ) && S_ISDIR( stat_buffer.st_mode ) ) ) {
      if( 0 != mkdir( to, 0775 ) ) {
        fprintf( stderr, "Errorish : %s", strerror(errno) );
      }
    }
    tok = strtok( NULL, PATHSEP );
    if( tok ) {
      strcat( to, PATHSEP );
    }
  }
}


void main()
{
  //  char zapp[] = "/home/wolf/foo/bar/baz";
  char zapp[] = "foo/bar/baz";
  make_path( zapp );
}
