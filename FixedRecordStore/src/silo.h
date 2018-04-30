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
unsigned long silo_push( Silo *silo, char *data, unsigned long write_amount );
int           silo_put_record( Silo *silo, unsigned long id, char *data, unsigned long write_amount );
void          unlink_silo( Silo *silo );
void          cleanup_silo( Silo *silo );


#endif
