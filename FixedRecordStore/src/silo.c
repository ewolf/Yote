#include "silo.h"
#include "util.h"

void _files( char *directory, void (*fun)(char*,int) );

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


Silo *
open_silo( char        * directory,
           unsigned int  record_size,
           unsigned long max_file_size )
{
  unsigned int file_max_records;
  Silo *silo;
  char *zeroFilename;

  // create the directory if it doesnt exist.
  // print to stderr and return NULL if there is an error.
  if( 0 != make_path( directory ) ) {
    fprintf( stderr, "Errorish : %s", strerror(errno) );
    return NULL;
  }
  zeroFilename = malloc( 3 + strlen( directory ) );
  sprintf( zeroFilename, "%s%s0", directory, PATHSEP );
  creat( zeroFilename, 0644 );
  free( zeroFilename );

  file_max_records = (max_file_size / record_size);

  if ( file_max_records == 0 ) {
    file_max_records = 1;
  }

  // malloc the silo and set its data
  silo = (Silo *)malloc( sizeof( Silo ) );
  
  silo->record_size      = record_size;
  silo->directory        = strdup( directory );
  silo->file_max_records = file_max_records;
  silo->file_max_size    = file_max_records * record_size;

  return silo;
  
} //open_silo

void
cleanup_silo( Silo *silo )
{
  free( silo->directory );
} //cleanup_silo

silo_dir_info *
_sum_filesizes( char *filename, int file_number )
{
  struct stat statbuf;
  silo_dir_info *ret;
  static silo_dir_info info = { 0, 0, 0, -1, NULL };
  
  if( filename ) {
    stat( filename, &statbuf );
    info.total_filesize += statbuf.st_size;
    info.files++;
    if ( file_number > info.last_filenumber )
      {
        info.last_filenumber = file_number;
        if( info.last_filename ) {
          free( info.last_filename );
        }
        info.last_filename = strdup( filename );
        info.last_filesize = statbuf.st_size;
      }
    return NULL;
  }
  ret = malloc( sizeof( silo_dir_info ) );
  memcpy( ret, &info, sizeof( silo_dir_info ) );
  
  info.total_filesize  = 0;
  info.last_filesize   = 0;
  info.last_filenumber = -1;
  info.last_filename   = NULL;
  info.files           = 0;
  return ret;

} //_sum_filesizes

unsigned long
silo_entry_count( Silo *silo )
{
  silo_dir_info *info;
  unsigned long long size;
  _files( silo->directory, (void*)_sum_filesizes );
  info = _sum_filesizes( NULL, 0 );
  size = info->total_filesize / silo->record_size;
  free( info->last_filename );
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
  if( 0 != rmdir( silo->directory ) ) {
    perror( "unlink_silo" );
  }
}

int
silo_put_record( Silo *silo, unsigned long id, char *data, unsigned long write_amount )
{
  FILE * silo_file;
  int file_number, record_position, file_position;
  char * filename;
  unsigned long idx = id - 1;
  
  if ( write_amount == 0 )
    {
      write_amount = strlen( data );
    }

  if( write_amount >= silo->record_size ) {
    // too big. must be at least one less than the record size for the '\0' byte.
    return 0;
  }
  
  silo_ensure_entry_count( silo, id );
  
  // find which file and where in the file to seek to
  // based on the idx
  file_number     = idx / silo->file_max_records;
  record_position = idx % silo->file_max_records;
  file_position   = silo->record_size * record_position;

  filename = malloc( strlen( silo->directory ) + 4 ); //TODO : reallyfix
  sprintf( filename, "%s/%d", silo->directory, file_number );
  
  silo_file = fopen( filename, "r+" );
  fseek( silo_file, file_position, SEEK_SET );

  
  fwrite( data, write_amount, 1, silo_file );
  fclose( silo_file );
  free( filename );
  return 1;
} //silo_put_record

unsigned long
silo_next_id( Silo *silo )
{
  unsigned long next_id;
  next_id = 1 + silo_entry_count( silo );
  silo_ensure_entry_count( silo, next_id );

  return next_id;
} //silo_next_id


char *
silo_pop( Silo * silo )
{
  int file_number, file_position;  
  char * ret, * filename;
  unsigned long entries = silo_entry_count( silo );
  
  if( entries > 0 ) {
    ret = silo_get_record( silo, entries );
    
    file_number     = entries / silo->file_max_records;
    file_position   = silo->record_size * ((entries-1) % silo->file_max_records);
    filename = malloc( 2 + strlen( silo->directory ) + ( file_number > 1 ? ceil(log10(file_number)) : 1 ) );
    sprintf( filename, "%s%s%d", silo->directory, PATHSEP, file_number );
    if( file_position > 0 ) {
      if( 0 != truncate( filename, file_position ) ) {
        perror( "TRUNCATE" );
      }
    } else {
      unlink( filename );
    }
    
    free( filename );
    
    return ret;
  }
  return NULL;
} //pop

unsigned long
silo_push( Silo *silo, char *data, unsigned long write_amount )
{
  unsigned long nextid = silo_next_id( silo );
  silo_put_record( silo, nextid, data, write_amount );
  return nextid;
} //silo_push

char *
silo_last_entry( Silo * silo )
{
  unsigned long entries = silo_entry_count( silo );
  if( entries > 0 ) {
    return silo_get_record( silo, entries );
  }
  return NULL;
} //silo_last_entry

char *
silo_get_record( Silo *silo, unsigned long id )
{
  FILE * silo_file;
  int file_number, record_position, file_position;
  char * filename;
  char * data;
  unsigned long long idx = id - 1;

  if ( silo_entry_count( silo ) >= id ) {
  
    file_number     = idx / silo->file_max_records;
    record_position = idx % silo->file_max_records;
    file_position   = silo->record_size * record_position;
  
    filename = malloc( 2 + strlen( silo->directory ) + ( file_number > 1 ? ceil(log10(file_number)) : 1 ) );
    sprintf( filename, "%s%s%d", silo->directory, PATHSEP, file_number );
  
    silo_file = fopen( filename, "r+" );
    fseek( silo_file, file_position, SEEK_SET );

    data = malloc( silo->record_size );
    fread( data, silo->record_size, 1, silo_file );  
    fclose( silo_file );
    free( filename );

    return data;
  }
  
  return NULL;
} //silo_get_record


// _files iterates over the silo files in the silos directory
// and runs the fun for each one of them.
void
_files( char *directory, void (*fun)(char*,int) )
{
  int file_number;
  DIR *d;
  struct dirent *dir;
  char *filedir;

  d = opendir( directory );
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        file_number = atoi( dir->d_name );
        if ( file_number > 0 || strcmp( dir->d_name, "0" ) == 0 )
          {
            filedir = malloc( 2 + strlen( directory ) + strlen( dir->d_name ) );
            sprintf( filedir, "%s%s%s", directory, PATHSEP, dir->d_name );
            fun( filedir, file_number );
            free( filedir );
          }
      }
    closedir(d);
  }

} //_files

void
silo_ensure_entry_count( Silo *silo, unsigned long count )
{
  char *newfile;
  int needed, records_needed_to_fill, existing_file_records, new_record_count;
  silo_dir_info * info;
  _files( silo->directory, (void*)_sum_filesizes );
  info = _sum_filesizes( NULL, 0 );
  
  needed = count - info->total_filesize / silo->record_size;

  if( needed > 0 ) {
    
    existing_file_records = info->last_filesize / silo->record_size;
    records_needed_to_fill = silo->file_max_records - existing_file_records;
    records_needed_to_fill = records_needed_to_fill > needed ? needed : records_needed_to_fill;
    new_record_count = records_needed_to_fill + existing_file_records;
    if ( records_needed_to_fill > 0 )
      {
        // fill the record with nulls to its max size
        if( 0 != truncate( info->last_filename, new_record_count * silo->record_size ) ) {
          perror( "TRUNCATE" );
        }
        needed -= records_needed_to_fill;
      }
    while ( needed > silo->file_max_records )
      {
        // create a new file and fill it will nulls
        ++info->last_filenumber;
        newfile = malloc( 2 + strlen( silo->directory ) + (info->last_filenumber > 1 ? ceil(log10(info->last_filenumber)) : 1 ) );
        sprintf( newfile, "%s%s%d", silo->directory, PATHSEP, info->last_filenumber );
        creat( newfile, 0644 );
        if( 0 != truncate( newfile, silo->file_max_size ) ) {
          perror( "TRUNCATE" );
        }
        free( newfile );
        needed -= silo->file_max_records;
      }
    if ( needed > 0 )
      {
        // create a new file and fill it will nulls
        newfile = malloc( strlen( silo->directory ) + 4 ); //TODO : reallyfix
        sprintf( newfile, "%s/%d", silo->directory, ++info->last_filenumber );
        creat( newfile, 0644 );
        if( 0 != truncate( newfile, needed * silo->record_size ) ) {
          perror( "TRUNCATE" );
        }
        free( newfile );
      }
  }
  free( info->last_filename );
  free( info );
} //silo_ensure_entry_count
