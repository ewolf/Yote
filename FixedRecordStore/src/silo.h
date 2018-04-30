#ifndef _SILO
#define _SILO

#include <stdio.h>
#include <math.h>
// ooo, the preprocessor could check
// and we could have sizes above 2G

typedef struct
{
  char         * directory;
  unsigned int   record_size;
  unsigned int   file_max_size;
  unsigned int   file_max_records;
  unsigned int   silo_type;
  unsigned int   file_size_limit;
} Silo;

/* Silo methods */
Silo       *  open_silo( char *directory,
                         unsigned int record_size,
                         unsigned long max_file_size );
void          empty_silo( Silo *silo );
void          silo_ensure_entry_count( Silo *silo, unsigned long count );
unsigned long silo_entry_count( Silo *silo );
char       *  silo_get_record( Silo *silo, unsigned long idx );
unsigned long silo_next_id( Silo *silo );
char       *  silo_pop( Silo *silo );
char       *  silo_last_entry( Silo *silo );
unsigned long silo_push( Silo *silo, char *data );
int           silo_put_record( Silo *silo, unsigned long idx, char *data );
void          unlink_silo( Silo *silo );


#endif

/*
  // calculate the record size based on silo
  // type or use passed in value
  if ( silo_type == INDEX_SILO ) {
    record_size = sizeof( int ) + sizeof( long );
  } else if ( silo_type == RECYC_SILO ) {
    record_size = sizeof( long );
  } else if ( silo_type == TRANS_SILO ) {
    record_size = 2 * sizeof( int ) + sizeof( long );
  }
*/
