#include "util.h"

/* like mkdir -p. Return 1 if success */
int
make_path( char *path )
{
  struct stat stat_buffer;
  char * tok, * to;
  char * saveptr;
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
  
  tok = strtok_r( path, PATHSEP, &saveptr );

  printf( " path part %s (%s)\n", tok, to );
  
  while( tok ) {
    // check if path exists
    strcat( to, tok );
    if ( !( 0 == stat( tok, &stat_buffer ) && S_ISDIR( stat_buffer.st_mode ) ) ) {
      if( 0 != mkdir( to, 0775 ) ) {
        return 0;
      }
    }
    tok = strtok_r( NULL, PATHSEP, &saveptr );
    printf( " path part %s (%s)\n", tok, to );
    if( tok ) {
      strcat( to, PATHSEP );
    }
  }
  free( to );
  return 1;
} //make_path
