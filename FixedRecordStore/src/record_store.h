
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
  Silo        * transaction_catalog_silo;
  Silo       ** silos;
  char        * version;
  unsigned long max_file_size;
  // TODO - add options
} RecordStore;


/* RecordStore methods */
RecordStore * open_store( char *directory, unsigned long max_file_size );
void          empty_store( RecordStore *store );
void          unlink_store( RecordStore *store );
void          cleanup_store( RecordStore *store );

unsigned long store_entry_count( RecordStore *store );
unsigned long next_id( RecordStore *store );
int           has_id( RecordStore *store, unsigned long rid );
void          delete_record( RecordStore *store, unsigned long rid );

unsigned long stow( RecordStore *store, char *data, unsigned long rid, unsigned long save_size );
char       *  fetch( RecordStore *store, unsigned long rid );


void          recycle_id( RecordStore *store, unsigned long rid );
void          empty_recycler( RecordStore *store );

/* Transactions */

#define TRA_ACTIVE 1
#define TRA_IN_COMMIT 2
#define TRA_IN_ROLLBACK 3
#define TRA_CLEANUP_COMMIT 4
#define TRA_CLEANUP_ROLLBACK 5
#define TRA_DONE 6

#define TRA_STOW 1
#define TRA_DELETE 1
#define TRA_RECYCLE 2

// transactions are cataloged in RecordStore transaction silo
// and each transaction gets its own instance silo
typedef struct
{
  unsigned long tid;           // transaction id
  pid_t         pid;           // process id
  time_t        update_time;   // update time
  unsigned int  state;         // TRA_ACTIVE, TRA_IN_COMMIT, TRA_IN_ROLLBACK, TRA_CLEANUP_COMIT, TRA_CLEANUP_ROLLBACK, TRA_DONE
  Silo        * silo;    
  RecordStore * store;    
} Transaction;

typedef struct
{
  unsigned int  type;          // TRA_STOW, TRA_DELETE, TRA_RECYCLE
  unsigned long rid;           // record id
  unsigned int  from_silo_idx; // location before transaction
  unsigned long from_sid;      // 
  unsigned int  to_silo_idx;   // location after transaction
  unsigned long to_sid;        // 
} TransactionEntry;


Transaction * create_transaction( RecordStore *store );
Transaction * open_transaction( RecordStore *store, unsigned long tid );
Transaction * list_transactions( RecordStore *store );

unsigned long trans_stow( Transaction *trans, char *data, unsigned long id, unsigned long write_amount );
int           trans_delete_record( Transaction *trans, unsigned long id );
int           trans_recycle_id( Transaction *trans, unsigned long id );

int          commit( Transaction *trans );
int          rollback( Transaction *trans );


#endif
