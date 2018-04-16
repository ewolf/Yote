#include "record_store.h"
#include "util.h"

void main() {
  Silo *silo;
  silo = open_silo( INDEX_SILO, "/tmp/store", 0 );
  make_path( "/tmp/foo/bar" );
  printf("Hello world %d from %s (%d)\n", silo->record_size, silo->directory, errno);
}


Silo *
open_silo( unsigned int silo_type,
           char         *directory,
           unsigned int record_size )
{
  unsigned int file_max_records;
  Silo *silo;

  // create the directory if it doesnt exist.
  // print to stderr and return NULL if there is an error.
  if( 0 == make_path( directory ) ) {
    fprintf( stderr, "Errorish : %s", strerror(errno) );
    return NULL;
  }

  // calculate the record size based on silo
  // type or use passed in value
  if ( silo_type == INDEX_SILO ) {
    record_size = sizeof( int ) + sizeof( long );
  } else if ( silo_type == RECYC_SILO ) {
    record_size = sizeof( long );
  } else if ( silo_type == TRANS_SILO ) {
    record_size = 2 * sizeof( int ) + sizeof( long );
  }

  file_max_records = (MAX_SILO_FILE_SIZE / record_size);
  if ( file_max_records == 0 ) {
    file_max_records = 1;
  }

  // malloc the silo and set its data
  silo = (Silo *)malloc( sizeof( Silo ) );
  
  silo->silo_type        = silo_type;
  silo->record_size      = record_size;
  silo->directory        = strdup( directory );
  silo->file_max_records = file_max_records;
  silo->file_max_size    = file_max_records * record_size;

  return silo;
  
} //open_silo

const char *
_files( Silo *silo )
{
  DIR *d;
  struct dirent *dir;
  char *results;
  int files = 0;
  
  d = opendir( silo->directory );
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        if( strcmp( dir->d_name, "0" ) == 0 || 0 < atoi( dir->d_name ) ) {
          files++;
        }
        // array of strings?
      }
    if( files > 0 ) {
      rewinddir(d);
      while ( NULL != (dir = readdir(d)) )
        {
          if( strcmp( dir->d_name, "0" ) == 0 || 0 < atoi( dir->d_name ) ) {
            
          }
          // array of strings?
        }
    }
  }

  closedir(d);
  return "AOO";
} //_files

void
empty_silo( Silo *silo )
{

} //empty_silo

unsigned long
silo_entry_count( Silo *silo )
{
  
} //empty_silo

unsigned long
put_record( Silo *silo, long idx, const char *data )
{

} //put_record
