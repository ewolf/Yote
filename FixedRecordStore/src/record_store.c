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

// _files iterates over the silo files in the silos directory
// and runs the fun for each one of them.
void
_files( char *directory, void (*fun)(char*,int) )
{
  int file_number;
  DIR *d;
  struct dirent *dir;
  char *filedir;

  int dirlen = strlen( directory ) + 1; // the 1 is for the seperator
  d = opendir( directory );
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        file_number = atoi( dir->d_name );
        if ( file_number > 0 || strcmp( dir->d_name, "0" ) == 0 )
          {
            filedir = malloc( sizeof(char *) * (dirlen + strlen( dir->d_name ) ) );
            filedir[0] = '\0';
            strcat( filedir, directory );
            strcat( filedir, PATHSEP );
            strcat( filedir, dir->d_name );
            fun( filedir, file_number );
            free( filedir );
          }
      }
  }

  closedir(d);
} //_files

// reentrant function that sums filesizes.
// if passed in NULL, it returns the tally and
// resets it to zero
typedef struct {
  unsigned int       files;
  unsigned long long total_filesize;
  unsigned long long last_filesize;
  int                last_filenumber;
  char             * last_filename;
} silo_dir_info;

silo_dir_info *
_sum_filesizes( char *filename, int file_number )
{
  struct stat statbuf;
  int filenum;
  static silo_dir_info *ret, info = { 0, 0, 0, 0 };
  
  if( filename ) {
    stat( filename, &statbuf );
    info.total_filesize += statbuf.st_size;
    info.files++;
    if ( file_number > info.last_filenumber )
      {
        info.last_filenumber = file_number;
        info.last_filename = strdup( filename );
        last_filesize = statbuf.st_size;
      }
    return NULL;
  }
  memcpy( ret, &info, sizeof( silo_dir_info ) );
  info->total_filesize  = 0;
  info->last_filesize   = 0;
  info->last_filenumber = 0;
  info->last_filename   = NULL;
  info->files           = 0;
  return ret;

} //_sum_filesizes

unsigned long
silo_entry_count( Silo *silo )
{
  silo_dir_info *info;
  unsigned long long size;
  _files( silo->directory, (void*)_sum_filesizes );
  info = _sum_filesizes( NULL );
  size = info.total_filesize / silo->record_size;
  free( info );
  return size;
} //silo_entry_count

 void _unlink( char *filename, int nada )
 {
   unlink( filename );
 }
 
void
empty_silo( Silo *silo )
{
  _files( silo->directory, _unlink );
} //empty_silo

void unlink_silo( Silo *silo ) {
  empty_silo( silo );
  unlink( silo->directory );
}

unsigned long
put_record( Silo *silo, long idx, const char *data )
{

} //put_record

void
_ensure_entry_count( Silo *silo, unsigned long count )
{
  char *newfile;
  int needed, records_needed_to_fill, existing_file_records;
  silo_dir_info * info;

  _files( silo->directory, (void*)_sum_filesizes );
  info = _sum_filesizes( NULL );
  
  needed = count - info.total_filesize / silo->record_size;

  if( needed > 0 ) {
    
    existing_file_records = info.last_filesize / silo->record_size;
    records_needed_to_fill = $silo->file_max_records - existing_file_records;
    records_needed_to_fill = records_needed_to_fill > needed ? needed : records_needed_to_fill;

    if ( records_needed_to_fill > 0 )
      {
        // fill the record with nulls to its max size
        truncate( info.last_filename, records_needed_to_fill );
        needed -= records_needed_to_fill;
      }
    while ( needed > silo->file_max_records )
      {
        // create a new file and fill it will nulls
        newfile = sprintf( "%s/%d", silo->directory, ++info.last_filenumber );
        creat( newfile, 0644 );
        truncate( newfile, silo->file_max_size );
        free( newfile );
        needed -= silo->file_max_records;
      }
    if ( needed > 0 )
      {
        // create a new file and fill it will nulls
        newfile = sprintf( "%s/%d", silo->directory, ++info.last_filenumber );
        creat( newfile, 0644 );
        truncate( newfile, needed );
        free( newfile );
      }
  }
  free( info.last_filename );
  free( info );
} //_ensure_entry_count
