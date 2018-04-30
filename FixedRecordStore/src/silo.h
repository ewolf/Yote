#ifndef _SILO
#define _SILO

#include "util.h"

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
  char         * directory;

  unsigned long  record_size;
  unsigned long  file_max_records;
  unsigned int   max_silo_files;

  // the rest are for convenience
  int            dirl;
  char         * filename;
  int          * file_descriptors;
  int            cur_fd;
  unsigned long  cur_silo_idx;
  unsigned long  cur_filepos;
} Silo;

#define SILO_FILE( silo_idx )   sprintf( silo->filename + silo->dirl, "%ld%c", silo_idx, '\0');

#define SILO_FD( silo_idx )                                             \
  silo->cur_silo_idx = silo_idx;                                        \
  sprintf( silo->filename + silo->dirl, "%ld%c", silo->cur_silo_idx, '\0'); \
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
  sprintf( silo->filename + silo->dirl, "%ld%c", silo->cur_silo_idx, '\0'); \
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
  

/* Silo methods */
Silo       *  open_silo( char *directory,
                         unsigned long record_size,
                         unsigned long max_file_size,
                         unsigned int  max_silo_files );
int           empty_silo( Silo *silo );
int           silo_ensure_entry_count( Silo *silo, unsigned long count );
unsigned long silo_entry_count( Silo *silo );
void       *  silo_get_record( Silo *silo, unsigned long idx );
unsigned long silo_next_id( Silo *silo );
void       *  silo_pop( Silo *silo );
void       *  silo_last_entry( Silo *silo );
unsigned long silo_push( Silo *silo, void *data, unsigned long write_amount );
int           silo_put_record( Silo *silo, unsigned long id, void *data, unsigned long write_amount );
int           silo_try_lock( Silo *silo );
int           silo_lock( Silo *silo );
int           unlink_silo( Silo *silo );
void          cleanup_silo( Silo *silo );


#endif
