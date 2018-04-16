#include "util.h"

/* like mkdir -p. Return 1 if success */
int
make_path( char *path )
{
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
    free( tok );
    if ( !( 0 == stat( tok, &stat_buffer ) && S_ISDIR( stat_buffer.st_mode ) ) ) {
      if( 0 != mkdir( to, 0775 ) ) {
        return 0;
      }
    }
    tok = strtok( NULL, PATHSEP );
    if( tok ) {
      strcat( to, PATHSEP );
    }
  }
  free( to );
  return 1;
} //make_path
