#ifndef _SILO
#define _SILO

#include "util.h"

#define RECSIZE unsigned long long

/*
  A Silo is a fixed width bucket of data.
  This allows it to be indexed very quickly. Since filesystems have max
  file sizes, the silo itself may be composed of multiple files.

  The silo is represented by a struct that contains the data that does
  not change about the silo - the directory location, record size, max
  number of records and max file size.

  Information that changes about the silo is *ONLY* kept on disc and in
  the files themselves, including current number of records. The files are
  canonical and multiple processes may work on the same silo.
 */
typedef struct 
{
  char  * directory;
  RECSIZE record_size;
  RECSIZE file_max_records;
  RECSIZE file_max_size;
  
  // the rest are for convenience
  int          dirl;
  char       * filename;
  int        * file_descriptors;
  int          cur_fd;
  unsigned int cur_silo_idx;
  RECSIZE      cur_filepos;
  
} Silo;


#define SILO_FILE( silo_idx ) sprintf( silo->filename + silo->dirl, "%d%c", silo_idx, '\0');

#define SILO_FD( silo_idx )                                             \
  silo->cur_silo_idx = silo_idx;                                        \
  sprintf( silo->filename + silo->dirl, "%d%c", silo->cur_silo_idx, '\0'); \
  if ( silo->file_descriptors[silo_idx] >= 0 ) {                        \
    silo->cur_fd = silo->file_descriptors[silo_idx];                    \
  } else {                                                              \
    silo->cur_fd = open( silo->filename, O_RDWR|O_CREAT, S_IRUSR|S_IWUSR ); \
    if ( silo->cur_fd == -1 ) {                                         \
      WARN("SILO_FD");                                                  \
    }                                                                   \
    silo->file_descriptors[silo_idx] = silo->cur_fd;                    \
  }                                                                     \
  silo->cur_filepos = silo->record_size * ( silo_idx % silo->file_max_records ); 

#define SILO_FD_ID( id )                                                \
  silo->cur_silo_idx = (id-1)/silo->file_max_records;                   \
  sprintf( silo->filename + silo->dirl, "%d%c", silo->cur_silo_idx, '\0'); \
  if ( silo->file_descriptors[silo->cur_silo_idx] >= 0 ) {              \
    silo->cur_fd = silo->file_descriptors[silo->cur_silo_idx];          \
  } else {                                                              \
    silo->cur_fd = open( silo->filename, O_RDWR|O_CREAT, S_IRUSR|S_IWUSR ); \
    silo->file_descriptors[silo->cur_silo_idx] = silo->cur_fd;          \
  }                                                                     \
  silo->cur_filepos = silo->record_size * ( (id - 1) % silo->file_max_records ); 

#define FN silo->filename
#define FD silo->cur_fd
#define FPOS silo->cur_filepos

#define _FILE_OFFSET_BITS 64
#define MAX_FILE_SIZE 10000000000000LL
#define SILO_MAX_FILES 1000

/* Silo methods */
Silo  * open_silo( char *directory, RECSIZE record_size );
int     empty_silo( Silo *silo );
int     silo_ensure_entry_count( Silo *silo, RECSIZE count );
RECSIZE     silo_entry_count( Silo *silo );
void  * silo_get_record( Silo *silo, RECSIZE sid );
RECSIZE     silo_next_id( Silo *silo );
void  * silo_pop( Silo *silo );
void  * silo_last_entry( Silo *silo );
RECSIZE     silo_push( Silo *silo, void *data, RECSIZE write_amount );
int     silo_put_record( Silo *silo, RECSIZE id, void *data, RECSIZE write_amount );
int     silo_try_lock( Silo *silo );
int     silo_lock( Silo *silo );
int     unlink_silo( Silo *silo );
void    cleanup_silo( Silo *silo );


#endif
