
#ifndef _RECORD_STORE_SEEN
#define _RECORD_STORE_SEEN

#include "silo.h"
#include "util.h"

#define RS_VERSION "1.0"

#define MAX_SILOS 100

/* public interface */
typedef struct {
  unsigned int silo_idx;
  long long    sid;
} IndexEntry;

typedef struct {
  char        * directory;
  Silo        * index_silo;
  Silo        * recycle_silo;
  Silo        * trans_silo;
  Silo       ** silos;
  char        * version;
  
  IndexEntry  * skeletonKey;
  Silo        * current_silo;
  // TODO - add options
} RecordStore;


#define SILO_IDX store->skeletonKey->silo_idx
#define SID store->skeletonKey->sid
#define SILO store->current_silo

#define SAVE_INDEX( store, rid, silo_idx, sid  )                \
  SILO_IDX = silo_idx;                                          \
  SID = sid;                                                    \
  silo_put_record( store->index_silo, rid,                      \
                   (char*)store->skeletonKey, sizeof( IndexEntry ) )

#define SET_SILO( store, idx )                                      \
  if ( idx < MAX_SILOS && idx >= 0 ) {                              \
    SILO = store->silos[ idx ];                                     \
    if ( SILO == NULL )                                             \
      {                                                             \
        __record_size = (long long)round( exp( SILO_IDX ) );    \
        __dir = malloc( 4 + strlen( store->directory )              \
                        + (SILO_IDX > 10 ?                          \
                           ceil(log10(SILO_IDX)) : 1 ) );           \
        sprintf( __dir, "%s%s%s%s%d", store->directory, PATHSEP,    \
                 "S", PATHSEP, SILO_IDX );                          \
        SILO = open_silo( __dir, __record_size );                   \
        store->silos[ idx ] = SILO;                                 \
        free( __dir );                                              \
      }                                                             \
  }

#define PREP_INDEX char * index_data;

#define PREP_SILO                               \
  long long __record_size;                      \
  char    * __dir                               \

#define LOAD_INDEX( store, rid )                                    \
  index_data = silo_get_record( store->index_silo, rid );           \
  if ( index_data ) {                                               \
    memcpy( store->skeletonKey, index_data, sizeof( IndexEntry ) ); \
    free( index_data );                                             \
  } else {                                                          \
    SILO_IDX = 0;                                                   \
  }  


/* RecordStore methods */
RecordStore * open_store( char *directory );
void          empty_store( RecordStore *store );
void          unlink_store( RecordStore *store );
void          cleanup_store( RecordStore *store );

long long store_entry_count( RecordStore *store );
long long next_id( RecordStore *store );
int           has_id( RecordStore *store, long long rid );
void          delete_record( RecordStore *store, long long rid );

long long stow( RecordStore *store, char *data, long long rid, long long save_size );
char       *  fetch( RecordStore *store, long long rid );


void          recycle_id( RecordStore *store, long long rid );
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
  long long tid;           // transaction id
  pid_t         pid;           // process id
  time_t        update_time;   // update time
  unsigned int  state;         // TRA_ACTIVE, TRA_IN_COMMIT, TRA_IN_ROLLBACK, TRA_CLEANUP_COMIT, TRA_CLEANUP_ROLLBACK, TRA_DONE
  Silo        * silo;    
  RecordStore * store;    
} Transaction;

typedef struct
{
  unsigned int type;            // TRA_STOW, TRA_DELETE, TRA_RECYCLE
  unsigned int completed;       // 1 if completed
  long long    rid;             // record id
  unsigned int from_silo_idx;   // location before transaction
  long long    from_sid;        // 
  unsigned int to_silo_idx;     // location after transaction
  long long    to_sid;          // 
} TransactionEntry;


Transaction * create_transaction( RecordStore *store );
Transaction * open_transaction( RecordStore *store, long long tid );
Transaction * list_transactions( RecordStore *store );

long long trans_stow( Transaction *trans, char *data, long long id, long long write_amount );

int       trans_delete_record( Transaction *trans, long long id );
int       trans_recycle_id( Transaction *trans, long long id );

int       commit( Transaction *trans );
int       rollback( Transaction *trans );


#endif
