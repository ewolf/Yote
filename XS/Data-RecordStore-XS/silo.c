#include "silo.h"

Silo *
open_silo( char * directory, RECSIZE record_size )
{
  RECSIZE file_max_records;
  Silo *silo;
  file_max_records = (MAX_FILE_SIZE / record_size);

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

  silo->record_size      = record_size;
  silo->file_max_records = file_max_records;
  
  silo->directory        = strdup( directory );
  silo->dirl             = strlen( directory ) + 1; //for path sep

  // directory + / + (max file) \0
  silo->file_descriptors = malloc( sizeof( int ) * SILO_MAX_FILES );
  memset( silo->file_descriptors, -1, sizeof( int ) * SILO_MAX_FILES );
  silo->filename         = calloc( 2 + silo->dirl + (SILO_MAX_FILES > 10 ? ceil(log10(SILO_MAX_FILES)) : 1 ), 1 );
  memcpy( silo->filename, directory, silo->dirl );
  if ( silo->filename[ silo->dirl - 1 ] != PATHSEPCHAR )
    {
      silo->filename[ silo->dirl - 1 ] = PATHSEPCHAR;
    }

  SILO_FD( 0 );
  
  return silo;
  
} //open_silo

void
cleanup_silo( Silo *silo )
{
  int i;
  for( i=0; i<SILO_MAX_FILES; i++ )
    {
      if( 0 <= silo->file_descriptors[i] )
        {
          close( silo->file_descriptors[i] );
        }
    }
  free( silo->directory );
  free( silo->filename );
  free( silo->file_descriptors );
} //cleanup_silo

RECSIZE
silo_entry_count( Silo *silo )
{
  DIR *d;
  struct dirent *dir;
  struct stat statbuf;

  long last_filenum, filenum;
  
  last_filenum = -1;
  d = opendir( silo->directory );
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
  closedir( d );
  if( last_filenum >= 0 )
    {
      if( 0 == stat( silo->filename, &statbuf ) )
        {
          return last_filenum * silo->file_max_records + statbuf.st_size / silo->record_size;
        }
    }
  return 0;
  
} //silo_entry_count
 
int
empty_silo( Silo *silo )
{
  RECSIZE i;
  SILO_FD_ID( silo_entry_count(silo) );
  for ( i=silo->cur_silo_idx; i>0; i-- )
    {
      SILO_FD( i );
      if ( 0 != unlink( silo->filename ) )
        {
          perror( "empty_silo" );
          return 1;
        }
      close( silo->file_descriptors[i] );
    }
  SILO_FD( 0 );
  if( 0 != ftruncate( FD, 0 ) )
    {
      perror( "empty_silo" );
      return 1;
    }
  close( silo->file_descriptors[0] );
  memset( silo->file_descriptors, -1, sizeof( int ) * SILO_MAX_FILES );
  return 0;
} //empty_silo

int
unlink_silo( Silo *silo ) {
  long i;
  RECSIZE ec = silo_entry_count(silo);
  SILO_FD_ID( ec == 0 ?  1 : ec  );
  for ( i=silo->cur_silo_idx; i>=0; i-- )
    {
      SILO_FILE( (unsigned int)i );
      unlink( FN );
      if ( silo->file_descriptors[i] >= 0 )
        {
          close( silo->file_descriptors[i] );
        }
    }
  memset( silo->file_descriptors, -1, sizeof( int ) * SILO_MAX_FILES );
  if ( 0 != rmdir( silo->directory ) ) {
    perror( "unlink_silo" );
    return 1;
  }
  return 0;
} //unlink_silo

int
silo_put_record( Silo *silo, RECSIZE sid, void *data, RECSIZE write_amount )
{
  if ( write_amount == 0 )
    {
      write_amount = strlen( data );
    }

  if ( silo->record_size < write_amount )
    {
      // too big. must be at least one less than the record size for the '\0' byte.
      return 1;
    }
  
  silo_ensure_entry_count( silo, sid );
  SILO_FD_ID( sid );
  lseek( FD, FPOS, SEEK_SET );
  write( FD, data, write_amount );

  return 0;
} //silo_put_record

RECSIZE
silo_next_id( Silo *silo )
{
  RECSIZE next_id;
  next_id = 1 + silo_entry_count( silo );
  silo_ensure_entry_count( silo, next_id );

  return next_id;
} //silo_next_id


void *
silo_pop( Silo * silo )
{
  char * ret;
  RECSIZE entries = silo_entry_count( silo );
  
  if ( entries > 0 )
    {
      ret = silo_get_record( silo, entries );
      SILO_FD_ID( entries );
      
      if ( FPOS > 0 )
        {
          if ( 0 != ftruncate( FD, FPOS ) )
            {
              perror( "silo_pop" );
            }
        }
      else if( 0 != unlink( silo->filename ) )
        {
          perror( "silo_pop" );
        }
    
    return ret;
  }
  return NULL;
} //pop

RECSIZE
silo_push( Silo *silo, void *data, RECSIZE write_amount )
{
  RECSIZE nextid = silo_next_id( silo );
  silo_put_record( silo, nextid, data, write_amount );
  return nextid;
} //silo_push

void *
silo_last_entry( Silo * silo )
{
  RECSIZE entries = silo_entry_count( silo );
  if( entries > 0 ) {
    return silo_get_record( silo, entries );
  }
  return NULL;
} //silo_last_entry

void *
silo_get_record( Silo *silo, RECSIZE id )
{
  char * data;

  if ( silo_entry_count( silo ) >= id )
    {
      SILO_FD_ID( id );
      lseek( FD, FPOS, SEEK_SET );
      data = calloc( 1 + silo->record_size, 1 );
      if ( -1 == read( FD, data, silo->record_size ) )
        {
          perror( "silo_get_record" );
        }
      return data;
    }
  
  return NULL;
} //silo_get_record



int
silo_ensure_entry_count( Silo *silo, RECSIZE count )
{
  RECSIZE          cur_count, records_in_last, to_fill_last;
  RECSIZE          needed;
  unsigned int last_silo_idx;

  // cur_count = (file_max_records * (files - 1)) + last_records
  // last_records = cur_count - (file_max_records * (files - 1)) 
  // files = cur_count % file_max_records ? 1 + cur_count / file_max_records : cur_count / file_max_records

  // say, records 7 per, cur count is 23 (files = 4)
  //  files = 1 + (23/7) = 4;
  //  last_records = 23 - ( 7 * 23/7 ) = 2
  //  filepos = 

  // say, 7 per, cur count is 21 (files = 3)
  //  files = 21 % 7 ? 1 + (21/7) = 4 : 21/7 = _3_
  //  last_records = 21 - ( 7 * 21/7 ) = 0
  
  cur_count = silo_entry_count( silo );
  needed = count - cur_count;
  if ( needed > 0 )
    {
      last_silo_idx = cur_count > 1 ? (cur_count-1) / silo->file_max_records : 0;
      
      records_in_last = cur_count - (silo->file_max_records * last_silo_idx );
      to_fill_last = silo->file_max_records - records_in_last;
      if ( to_fill_last > needed )
        {
          to_fill_last = needed;
        }
      // truncate the last_silo_idx;
      if ( to_fill_last > 0 )
        {
          SILO_FD( last_silo_idx );
          if ( 0 != ftruncate( FD, (records_in_last+to_fill_last) * silo->record_size ) )
            {
              perror( "silo_ensure_entry_count" );
              return 1;
            }
          needed -= to_fill_last;
        }

      to_fill_last = silo->file_max_records * silo->record_size;
      while ( needed > silo->file_max_records )
        {
          SILO_FD( ++last_silo_idx );
          if ( 0 != ftruncate( FD, to_fill_last ) )
            {
              perror( "silo_ensure_entry_count" );
              return 1;
            }
          needed -= silo->file_max_records;
        }

      if ( needed > 0 )
        {
          SILO_FD( ++last_silo_idx );
          if ( 0 != ftruncate( FD, needed * silo->record_size ) )
            {
              perror( "silo_ensure_entry_count" );
              return 1;
            }
        }
    } //if needed
  return 0;
} //silo_ensure_entry_count

// return 0 if lock was successfull. Non-blocking
int
silo_try_lock( Silo *silo )
{
  SILO_FD( 0 );
  return flock( FD, LOCK_EX | LOCK_NB );
} //silo_try_lock

// return 0 if lock was successfull. Blocks.
int
silo_lock( Silo *silo )
{
  SILO_FD( 0 );
  return flock( FD, LOCK_EX );
} //silo_lock
