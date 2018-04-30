
#ifndef _RECORD_STORE_SEEN
#define _RECORD_STORE_SEEN

#include <math.h>
#include "silo.h"
#include "util.h"

#define RS_VERSION "1.0"

#define MAX_SILOS 100

/* public interface */
typedef struct
{
  char        * directory;
  Silo        * index_silo;
  Silo        * recycle_silo;
  Silo       ** silos;
  char        * version;
  unsigned long max_file_size;
  // TODO - add options
} RecordStore;

typedef struct
{
  int silo_idx;
  unsigned long sid; //silo entry id
} IndexEntry;

typedef struct
{
  
} Transaction;

/* RecordStore methods */
RecordStore * open_store( char *directory, unsigned long max_file_size );
void          empty_store( RecordStore *store );
void          cleanup_store( RecordStore *store );

unsigned long store_entry_count( RecordStore *store );
unsigned long next_id( RecordStore *store );
int           has_id( RecordStore *store, unsigned long rid );
void          delete_record( RecordStore *store, unsigned long rid );

unsigned long stow( RecordStore *store, char *data, unsigned long rid );
char       *  fetch( RecordStore *store, unsigned long rid );


void          recycle_id( RecordStore *store, unsigned long rid );
void          empty_recycler( RecordStore *store );

Transaction * create_transaction( RecordStore *store );
Transaction * list_transactions( RecordStore *store );


/* Transaction methods */
unsigned long get_update_time( Transaction *trans );
unsigned int  get_process_id( Transaction *trans );
unsigned int  get_state( Transaction *trans );
unsigned int  get_id( Transaction *trans );
unsigned long trans_stow( Transaction *trans, char *data, unsigned long id );
void          trans_delete_record( Transaction *trans, unsigned long id );
void          trans_recycle_id( Transaction *trans, unsigned long id );
void          commit( Transaction *trans );
void          rollback( Transaction *trans );

#endif
