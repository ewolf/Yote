#include "util.h"

/* like mkdir -p. Return 0 if success, 1 if cant, 2 if error making dir */
int
make_path( char *dirpath )
{
  struct stat stat_buffer;
  int i, len;
  char *path = strdup( dirpath );

  len = 1 + strlen( path );
  for( i=1; i<len; i++ )
    {
      if( path[i] == PATHSEPCHAR )
        {
          path[i] = '\0';
          if( 0 == stat( path, &stat_buffer ) )
            {
              if( ! S_ISDIR( stat_buffer.st_mode ) )
                {
                  // BAD, EXISTS AND IS NOT A DIRECTORY
                  path[i] = PATHSEPCHAR;
                  free( path );
                  return 1;
                }
            }
          else if( 0 != mkdir( path, 0775 ) )
            {
              perror( "make_path" );
              path[i] = PATHSEPCHAR;
              free( path );

              return 2;
            }
          path[i] = PATHSEPCHAR;
        }
      else if( path[i] == '\0' )
        {
          if( 0 == stat( path, &stat_buffer ) )
            {
              if( ! S_ISDIR( stat_buffer.st_mode ) )
                {
                  // BAD, EXISTS AND IS NOT A DIRECTORY
                  free( path );

                  return 1;
                }
            }
          else if( 0 != mkdir( path, 0775 ) )
            {
              perror( "make_path" );
              free( path );
              return 2;
            } // try to make the path
          free( path );
          return 0;
        }
    } //each i
  return 0;
} //make_path

int
rm_path( char *pathpart, char * rmpart )
{
  //  int i;
  char * path = malloc( 1 + strlen( pathpart ) + strlen( rmpart ) );
  strcat( path, pathpart );
  strcat( path, PATHSEP );
  strcat( path, rmpart );

  //  for( i=
  free( path );
  return 0;
} //rm_path

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
