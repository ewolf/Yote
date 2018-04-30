#ifndef _SILO
#define _SILO

#include <stdio.h>
#include <math.h>
#include <unistd.h>

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
  unsigned long  file_max_size;
  unsigned int   max_silo_files;

  // the rest are for convenience
  int            dirl;
  char         * filename;
  int          * file_descriptors;
  int            cur_fd;
} Silo;

#define SILO_FD( num )                                          \
  if ( silo->file_descriptors[num] > 0 ) {                      \
    silo->cur_fd = silo->file_descriptors[num];                 \
  } else {                                                      \
    sprintf( silo->filename + silo->dirl, "%d%c", num, '\0' );  \
    silo->cur_fd = open( silo->filename );                      \
    silo->file_descriptors[num] = silo->cur_fd;                 \
  }
#define FD silo->cur_fd
  

/* Silo methods */
Silo       *  open_silo( char *directory,
                         unsigned long record_size,
                         unsigned long max_file_size );
void          empty_silo( Silo *silo );
void          silo_ensure_entry_count( Silo *silo, unsigned long count );
unsigned long silo_entry_count( Silo *silo );
void       *  silo_get_record( Silo *silo, unsigned long idx );
unsigned long silo_next_id( Silo *silo );
void       *  silo_pop( Silo *silo );
void       *  silo_last_entry( Silo *silo );
unsigned long silo_push( Silo *silo, void *data, unsigned long write_amount );
int           silo_put_record( Silo *silo, unsigned long id, void *data, unsigned long write_amount );
int           silo_try_lock( Silo *silo );
int           silo_lock( Silo *silo );
void          unlink_silo( Silo *silo );
void          cleanup_silo( Silo *silo );


#endif
