
#ifndef _RECORD_STORE_SEEN
#define _RECORD_STORE_SEEN

#include <errno.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* public interface */
typedef struct
{
  
} RecordStore;

typedef struct
{
  
} Transaction;

#define  INDEX_SILO 1
#define  RECYC_SILO 2
#define  TRANS_SILO 3
#define  DATA_SILO  4

#define  INDEX_SILO 1
#define  RECYC_SILO 2
#define  TRANS_SILO 3
#define  DATA_SILO  4

#define MAX_SILO_FILE_SIZE 2000000000

typedef struct
{
  const char     * directory;
  unsigned int   record_size;
  unsigned int   file_max_size;
  unsigned int   file_max_records;
  unsigned int   silo_type;
} Silo;

/* RecordStore methods */
RecordStore * open_store( const char *directory );
void          empty( RecordStore *store );
unsigned long entry_count( RecordStore *store );
unsigned long next_id( RecordStore *store );
int           has_id( RecordStore *store, unsigned long id );
void          delete_record( RecordStore *store, unsigned long id );

unsigned long stow( RecordStore *store, const char *data, unsigned long id );
const char *  fetch( RecordStore *store, unsigned long id );


void          recycle_id( RecordStore *store, unsigned long id );
void          empty_recycler( RecordStore *store );

Transaction * create_transaction( RecordStore *store );
Transaction * list_transactions( RecordStore *store );

/* Silo methods */
Silo *        open_silo( unsigned int silo_type, char *directory, unsigned int record_size );
void          empty_silo( Silo *silo );
unsigned long silo_entry_count( Silo *silo );
const char *  get_record( Silo *silo, long idx );
unsigned long silo_next_id( Silo *silo );
const char *  pop( Silo *silo );
const char *  last_entry( Silo *silo );
unsigned long push( Silo *silo, const char *data );
unsigned long put_record( Silo *silo, long idx, const char *data );
void          unlink_store( Silo *silo );

/* Transaction methods */
unsigned long get_update_time( Transaction *trans );
unsigned int  get_process_id( Transaction *trans );
unsigned int  get_state( Transaction *trans );
unsigned int  get_id( Transaction *trans );
unsigned long trans_stow( Transaction *trans, const char *data, unsigned long id );
void          trans_delete_record( Transaction *trans, unsigned long id );
void          trans_recycle_id( Transaction *trans, unsigned long id );
void          commit( Transaction *trans );
void          rollback( Transaction *trans );

#endif
