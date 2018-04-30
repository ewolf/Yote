#include "util.h"

/* like mkdir -p. Return 1 if success */
int
make_path( char *path )
{
  struct stat stat_buffer;
  char * tok;
  char * to;
  char * saveptr;

  // make a string large enough to hold the full path
  to = strdup( path );
  if ( '/' == path[0] ) {
    to[0] = '/';
    to[1] = '\0';
  } else {
    to[0] = '\0';
  }
  
  //  printf( "path : '%s' (%s)\n", path, PATHSEP );
  tok = strtok_r( path, PATHSEP, &saveptr );


  if( tok == NULL ) {
    //    printf( "NULLY\n" );
  } else {
    //    printf( " path part %s (%s)\n", tok, to );
  }
  
  while( tok ) {
    // check if path exists
    strcat( to, tok );
    if ( !( 0 == stat( tok, &stat_buffer ) && S_ISDIR( stat_buffer.st_mode ) ) ) {
      if( 0 != mkdir( to, 0775 ) ) {
        return 0;
      }
    }
    tok = strtok_r( NULL, PATHSEP, &saveptr );
    //    printf( " path part %s (%s)\n", tok, to );
    if( tok ) {
      strcat( to, PATHSEP );
    }
  }
  free( to );
  return 1;
} //make_path

int
filecount( char *directory )
{
  int filecount = 0;
  DIR *d = opendir( directory );
  struct dirent *dir;
  
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        if( 0 != strcmp( dir->d_name, ".." ) && 0 != strcmp( dir->d_name, "." ) ) {
          filecount++;
        }
      }
    closedir(d);
  }
  
  return filecount;
} //filecount

int
filesize( char *file ) {
    struct stat statbuf;
    if( stat( file, &statbuf ) ) {
      perror( "filesize" );
    }
    return statbuf.st_size;
} //filesize
