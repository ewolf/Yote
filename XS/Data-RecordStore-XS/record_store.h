
#ifndef _RECORD_STORE_SEEN
#define _RECORD_STORE_SEEN

#include "silo.h"
#include "util.h"

#define RS_VERSION "1.0"

#define MAX_SILOS 100

/* public interface */
typedef struct
{
  unsigned int silo_idx;
  RECSIZE    sid;
} IndexEntry;

typedef struct
{
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

#define SAVE_INDEX( store, rid, silo_idx, sid  )                        \
  SILO_IDX = silo_idx;                                                  \
  SID = sid;                                                            \
  silo_put_record( store->index_silo, rid,                              \
                     (char*)store->skeletonKey, sizeof( IndexEntry ) )

#define SET_SILO( store, idx )                                      \
  if ( idx < MAX_SILOS && idx >= 0 ) {                              \
    SILO = store->silos[ idx ];                                     \
    if ( SILO == NULL )                                             \
      {                                                             \
        __record_size = (RECSIZE)round( exp( SILO_IDX ) );              \
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
  RECSIZE __record_size;                            \
  char    * __dir                               \

#define LOAD_INDEX( store, rid )                                    \
  index_data = silo_get_record( store->index_silo, rid );           \
  if ( index_data ) {                                               \
    memcpy( store->skeletonKey, index_data, sizeof( IndexEntry ) ); \
    free( index_data );                                             \
  } else {                                                          \
    SILO_IDX = 0;                                                   \
  }  

#define PREP_SWAP                               \
  char        * swap_record;                    \
  RECSIZE     swap_rid;                             \
  char        * index_entry;                    \
  RECSIZE     last_sid

// move last record to the space left by the
// vacating record. Do a copy to be safer rather
// than a pop which could lose data
#define SWAP( store, silo, silo_idx, vacated_sid )                      \
  last_sid = silo_entry_count( silo );                                  \
  if ( vacated_sid < last_sid )                                         \
    {                                                                   \
      swap_record = silo_get_record( silo, last_sid );                  \
      memcpy( &swap_rid, swap_record, sizeof( RECSIZE ) );                  \
      silo_put_record( silo, vacated_sid, swap_record, silo->record_size ); \
      index_entry = calloc( sizeof( unsigned int ) + sizeof( RECSIZE ), 1 ); \
      memcpy( index_entry, &silo_idx, sizeof( unsigned int ) );         \
      memcpy( index_entry + sizeof( int ), &swap_rid, sizeof( RECSIZE ) );  \
      silo_put_record( silo, swap_rid, index_entry, sizeof( unsigned int ) + sizeof( RECSIZE ) ); \
      free( index_entry );                                              \
      free( swap_record );                                              \
      swap_record = silo_pop( silo );                                   \
      free( swap_record );                                              \
    }                                                                   \
  else if ( vacated_sid == last_sid )                                   \
    {                                                                   \
      swap_record = silo_pop( silo );                                   \
      free( swap_record );                                              \
    }



/* RecordStore methods */
RecordStore * open_store( char *directory );
void          empty_store( RecordStore *store );
void          unlink_store( RecordStore *store );
void          cleanup_store( RecordStore *store );

RECSIZE  store_entry_count( RecordStore *store );
RECSIZE  next_id( RecordStore *store );
int  has_id( RecordStore *store, RECSIZE rid );
void delete_record( RecordStore *store, RECSIZE rid );

RECSIZE    stow( RecordStore *store, char *data, RECSIZE rid, RECSIZE save_size );
char * fetch( RecordStore *store, RECSIZE rid );

void recycle_id( RecordStore *store, RECSIZE rid );
void empty_recycler( RecordStore *store );

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

#define TRANS( trans, trans_type, ridA, ridB )                          \
  RecordStore      * store;                                             \
  TransactionEntry * trans_record;                                      \
  RECSIZE          next_trans_sid;                                          \
  int                TRANS_RES;                                         \
                                                                        \
  if( trans->state == TRA_ACTIVE )                                      \
    {                                                                   \
     store = trans->store;                                              \
     PREP_INDEX;                                                        \
     LOAD_INDEX( store, ridA );                                         \
                                                                        \
     next_trans_sid = silo_next_id( trans->silo );                      \
     trans_record = (TransactionEntry*)calloc( sizeof(TransactionEntry), 1 ); \
     trans_record->type          = trans_type;                          \
     trans_record->rid           = ridA;                                \
     trans_record->from_silo_idx = SILO_IDX;                            \
     trans_record->from_sid      = SID;                                 \
     if ( ridB > 0 )                                                    \
       {                                                                \
         LOAD_INDEX( store, ridB );                                     \
         trans_record->to_silo_idx = SILO_IDX;                          \
         trans_record->to_sid      = SID;                               \
       }                                                                \
     silo_put_record( trans->silo, next_trans_sid, trans_record, sizeof( TransactionEntry ) ); \
     free( trans_record );                                              \
     TRANS_RES = 0;                                                     \
    }                                                                   \
  TRANS_RES = 1

// transactions are cataloged in RecordStore transaction silo
// and each transaction gets its own instance silo
typedef struct
{
  RECSIZE           tid;            // transaction id
  pid_t         pid;            // process id
  time_t        update_time;    // update time
  unsigned int  state;          // TRA_ACTIVE, TRA_IN_COMMIT, TRA_IN_ROLLBACK, TRA_CLEANUP_COMIT, TRA_CLEANUP_ROLLBACK, TRA_DONE
  Silo        * silo;    
  RecordStore * store;    
} Transaction;

typedef struct
{
  unsigned int type;            // TRA_STOW, TRA_DELETE, TRA_RECYCLE
  unsigned int completed;       // 1 if completed
  RECSIZE          rid;             // record id
  unsigned int from_silo_idx;   // location before transaction
  RECSIZE          from_sid;        // 
  unsigned int to_silo_idx;     // location after transaction
  RECSIZE          to_sid;          // 
} TransactionEntry;
 

Transaction * create_transaction( RecordStore *store );
Transaction * open_transaction( RecordStore *store, RECSIZE tid );
Transaction ** list_transactions( RecordStore *store );

RECSIZE trans_stow( Transaction *trans, char *data, RECSIZE id, RECSIZE write_amount );

int trans_delete_record( Transaction *trans, RECSIZE id );
int trans_recycle_id( Transaction *trans, RECSIZE id );

int commit( Transaction *trans );
int rollback( Transaction *trans );


#endif
