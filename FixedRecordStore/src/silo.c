#include "silo.h"
#include "util.h"

// reentrant function that sums filesizes.
// if passed in NULL, it returns the tally and
// resets it to zero
void _files( char *directory, void (*fun)(char*,int) );

typedef struct {
  unsigned int       files;
  unsigned long long total_filesize;
  unsigned long long last_filesize;
  int                last_filenumber;
  char             * last_filename;
} silo_dir_info;


Silo *
open_silo( char        * directory,
           unsigned long record_size,
           unsigned long max_file_size,
           unsigned int  max_silo_files )
{
  unsigned int file_max_records;
  Silo *silo;

  file_max_records = (max_file_size / record_size);

  if ( file_max_records == 0 ) {
    return NULL;
  }

  // create the directory if it doesnt exist.
  // print to stderr and return NULL if there is an error.
  if( 0 != make_path( directory ) ) {
    fprintf( stderr, "Errorish : %s", strerror(errno) );
    return NULL;
  }
  
  // malloc the silo and set its data
  silo = (Silo *)malloc( sizeof( Silo ) );

  silo->max_silo_files   = max_silo_files;
  silo->record_size      = record_size;
  silo->file_max_records = file_max_records;
  silo->file_max_size    = file_max_records * record_size;
  
  silo->directory        = strdup( directory );
  silo->dirl             = sizeof( directory ); // includes path sep

  // directory + / + (max file) \0
  silo->file_descriptors = calloc( sizeof( int ), max_silo_files );
  silo->filename         = calloc( 2 + silo->dirl + (max_silo_files > 10 ? ceil(log10(max_silo_files)) : 1 ), 1 );
  memcpy( silo->filename, directory, silo->dirl );
  silo->filename[ silo->dirl - 1 ] = PATHSEPCHAR;

  return silo;
  
} //open_silo

void
cleanup_silo( Silo *silo )
{
  close( silo->first_fd );
  free( silo->directory );
  free( silo->filename );
  free( silo->file_descriptors );
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
  DIR *d;
  struct dirent *dir;
  struct stat statbuf;

  long last_filenum, filenum;
  
  d = opendir( silo->directory );
  if ( d == NULL )
    {
      perror( "silo_entry_count" );
      return 0;
    }
  last_filenum = -1;
  while ( NULL != (dir = readdir(d)) )
    {
      filenum = atoi( dir->d_name );
      if ( filenum > last_filenum  &&
           ( filenum > 0 || 0 == strcmp( dir->d_name, "0" ) ) )
        {
          memcpy( silo->filename + silo->dirl, dir->d_name, 1+strlen(dir->d_name)  );
          last_filenum = filenum;
        }
    }
  if( last_filenum >= 0 )
    {
      if( 0 == stat( silo->filename, &statbuf ) )
        {
          // record count = last_filenum * file_max_records + filesize / record_size;
          closedir( d );
          return last_filenum * silo->file_max_records + statbuf.st_size / silo->record_size;
        }
    }
  closedir( d );
  
  return 0;
  
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
silo_put_record( Silo *silo, unsigned long id, void *data, unsigned long write_amount )
{
  int silo_fd;
  int file_number, record_position, file_position;
  char * filename;
  unsigned long idx = id - 1;
  if ( write_amount == 0 )
    {
      write_amount = strlen( data );
    }

  if ( silo->record_size < write_amount )
    {
      // too big. must be at least one less than the record size for the '\0' byte.
      return 0;
    }
  
  silo_ensure_entry_count( silo, id );
  
  // find which file and where in the file to seek to
  // based on the idx
  file_number     = idx / silo->file_max_records;
  record_position = idx % silo->file_max_records;
  file_position   = silo->record_size * record_position;

  filename = malloc( strlen( silo->directory ) + 4 );
  sprintf( filename, "%s/%d", silo->directory, file_number );
  
  silo_fd = open( filename, O_WRONLY|O_CREAT, 0644 );
  lseek( silo_fd, file_position, SEEK_SET );
  write( silo_fd, data, write_amount );
  close( silo_fd );
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


void *
silo_pop( Silo * silo )
{
  int file_number, file_position;  
  char * ret, * filename;
  unsigned long entries = silo_entry_count( silo );
  
  if( entries > 0 ) {
    ret = silo_get_record( silo, entries );
    
    file_number     = entries / silo->file_max_records;
    file_position   = silo->record_size * ((entries-1) % silo->file_max_records);
    filename = malloc( 2 + strlen( silo->directory ) + ( file_number > 10 ? ceil(log10(file_number)) : 1 ) );
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
silo_push( Silo *silo, void *data, unsigned long write_amount )
{
  unsigned long nextid = silo_next_id( silo );
  silo_put_record( silo, nextid, data, write_amount );
  return nextid;
} //silo_push

void *
silo_last_entry( Silo * silo )
{
  unsigned long entries = silo_entry_count( silo );
  if( entries > 0 ) {
    return silo_get_record( silo, entries );
  }
  return NULL;
} //silo_last_entry

void *
silo_get_record( Silo *silo, unsigned long id )
{
  int silo_fd;
  int file_number, record_position, file_position;
  char * filename;
  char * data;
  unsigned long long idx = id - 1;

  if ( silo_entry_count( silo ) > idx ) {
  
    file_number     = idx / silo->file_max_records;
    record_position = idx % silo->file_max_records;
    file_position   = silo->record_size * record_position;
  
    filename = malloc( 2 + strlen( silo->directory ) + ( file_number > 10 ? ceil(log10(file_number)) : 1 ) );
    sprintf( filename, "%s%s%d", silo->directory, PATHSEP, file_number );

    silo_fd = open( filename, O_RDONLY );
    lseek( silo_fd, file_position, SEEK_SET );
    data = calloc( 1 + silo->record_size, 1 );
    if ( -1 == read( silo_fd, data, silo->record_size ) )
      {
        perror( "silo_get_record" );
      }
    close( silo_fd );
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
          perror( "silo_ensure_entry_count" );
        }
        needed -= records_needed_to_fill;
      }
    while ( needed > silo->file_max_records )
      {
        // create a new file and fill it will nulls
        ++info->last_filenumber;
        newfile = malloc( 2 + strlen( silo->directory ) + (info->last_filenumber > 10 ? ceil(log10(info->last_filenumber)) : 1 ) );
        sprintf( newfile, "%s%s%d", silo->directory, PATHSEP, info->last_filenumber );
        creat( newfile, 0644 );
        if( 0 != truncate( newfile, silo->file_max_size ) ) {
          perror( "silo_ensure_entry_count" );
        }
        free( newfile );
        needed -= silo->file_max_records;
      }
    if ( needed > 0 )
      {
        // create a new file and fill it will nulls
        newfile = malloc( strlen( silo->directory ) + 10 );
        sprintf( newfile, "%s/%d", silo->directory, ++info->last_filenumber );
        creat( newfile, 0644 );
        if( 0 != truncate( newfile, needed * silo->record_size ) ) {
          perror( "silo_ensure_entry_count" );
        }
        free( newfile );
      }
  }
  free( info->last_filename );
  free( info );
} //silo_ensure_entry_count

// return 0 if lock was successfull. Non-blocking
int
silo_try_lock( Silo *silo )
{
  int ret = flock( silo->first_fd, LOCK_EX | LOCK_NB );
  if ( ret == 0 )
    {
      return 0;
    }
  if( ret == EBADF )
    {
      close( silo->first_fd );
      silo->first_fd = open( silo->first_fn, O_WRONLY|O_CREAT, 0644 );
      ret = flock( silo->first_fd, LOCK_EX | LOCK_NB );
    }
  return ret;
} //silo_try_lock

// return 0 if lock was successfull. Blocks.
int
silo_lock( Silo *silo )
{
  int ret = flock( silo->first_fd, LOCK_EX );
  if( ret == EBADF )
    {
      close( silo->first_fd );
      silo->first_fd = open( silo->first_fn, O_WRONLY|O_CREAT, 0644 );
      ret = flock( silo->first_fd, LOCK_EX | LOCK_NB );
    }
  return ret;
} //silo_lock
