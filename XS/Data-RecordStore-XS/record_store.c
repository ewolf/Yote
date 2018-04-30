#include "record_store.h"
#include "silo.h"
#include "util.h"

// rid  - record entry index id
// sid  - silo entry index id
// sidx - index of silo

RecordStore *
open_store( char *directory )
{
  RecordStore * store;
  //   /S  -silos   /R  -recyclesilo  /I  -indexsilo  /T -trans_cata /A - transActions

  store = (RecordStore *)malloc( sizeof( RecordStore ) );
  store->version       = RS_VERSION;
  store->silos         = calloc( MAX_SILOS, sizeof( Silo * ) );
  store->directory     = strdup(directory);

  
  char * dir = malloc( strlen( directory ) + 3  );
  sprintf( dir, "%s%s%s", directory, PATHSEP, "S" );

  make_path( dir );

  sprintf( dir, "%s%s%s", directory, PATHSEP, "I" );
  
  store->index_silo = open_silo( dir, sizeof( IndexEntry ) );
  
  sprintf( dir, "%s%s%s", directory, PATHSEP, "R" );
  store->recycle_silo = open_silo( dir, sizeof(RECSIZE) );

  sprintf( dir, "%s%s%s", directory, PATHSEP, "T" );  
  store->trans_silo = open_silo( dir, sizeof( Transaction ) );
  store->skeletonKey = malloc( sizeof( IndexEntry ) );
  
  free( dir );
  
  return store;
} //open_store


void
cleanup_store( RecordStore *store )
{
  Silo * silo;
  int i = 0;
  
  cleanup_silo( store->index_silo );
  free( store->index_silo );
  
  cleanup_silo( store->recycle_silo );
  free( store->recycle_silo );
  
  cleanup_silo( store->trans_silo );
  free( store->trans_silo );
  
  for( i=0; i<MAX_SILOS; i++ )
    {
      silo = store->silos[i];
      if( NULL != silo )
        {
          cleanup_silo( silo );
          free( silo );
        }
    }
  free( store->silos );
  free( store->directory );
  free( store->skeletonKey );

  // SILO is freed by the loop above
  
} //cleanup_silo

void
empty_store( RecordStore *store )
{
  int i;
  Silo *s;
  for ( i=0; i<MAX_SILOS; i++ )
    {
      s = store->silos[i];
      if ( s != NULL ) {
        store->silos[i] = NULL;
        empty_silo( s );
        free( s );
      }
    }
  empty_silo( store->recycle_silo );
  empty_silo( store->index_silo );
  empty_silo( store->trans_silo );
} //empty_store

void
unlink_store( RecordStore *store )
{
  int i;
  Silo * s;
  char * dir;
  for ( i=0; i<MAX_SILOS; i++ )
    {
      s = store->silos[i];
      if ( s != NULL ) {
        store->silos[i] = NULL;
        unlink_silo( s );
        cleanup_silo( s );
        free( s );
      }
    }
  unlink_silo( store->recycle_silo );
  unlink_silo( store->index_silo );
  unlink_silo( store->trans_silo );
  dir = malloc( 3 + strlen( store->directory ));
  sprintf( dir, "%s%s%s", store->directory, PATHSEP, "S" );
  if ( 0 == rmdir( dir ) )
    {
      if ( 0 != rmdir( store->directory ) )
        {
          perror( "unlink_store" );
        }
    }
  else
    {
      perror( "unlink_store" );
    }
  
  free( dir );

} //unlink_store

RECSIZE
store_entry_count( RecordStore *store )
{
  return silo_entry_count( store->index_silo ) - silo_entry_count( store->recycle_silo );
} //store_entry_count

RECSIZE
next_id( RecordStore *store )
{
  RECSIZE recycled_rid;
  char *recycled;
  recycled = silo_pop( store->recycle_silo );
  if ( recycled != NULL ) {
    memcpy( &recycled_rid, recycled, sizeof( RECSIZE ) );
    free( recycled );
    return recycled_rid;
  }
  return silo_next_id( store->index_silo );
} //next_id

int
has_id( RecordStore *store, RECSIZE rid )
{
  PREP_INDEX;
  LOAD_INDEX( store, rid );
  return SID;// > 0;
} //has_id

void
delete_record( RecordStore *store, RECSIZE rid )
{
  PREP_INDEX;
  LOAD_INDEX( store, rid );
  if ( SID > 0 )
    {
      // write a blank index record and swap out the old data      
      PREP_SWAP;
      SWAP( store, SILO, SILO_IDX, SID );
      SAVE_INDEX( store, rid, 0, 0 );      
    }
} //delete_record

RECSIZE
stow( RecordStore *store, char *data, RECSIZE rid, RECSIZE save_size )
{
  char    * entry_data;
  RECSIZE entry_size;
  int       ret;

  rid = rid == 0 ? silo_next_id( store->index_silo ) : rid;
  if ( save_size == 0 )
    {
      save_size = 1 + strlen( data );
    }
  entry_size = save_size + sizeof( RECSIZE );
  entry_data = calloc( entry_size, 1 );
  PREP_INDEX;
  PREP_SILO;
  LOAD_INDEX( store, rid );
  if ( SID > 0 )
    {
      SET_SILO( store, SILO_IDX );
      if ( entry_size > SILO->record_size )
        { // needs to find a new silo
          // remove it from the old silo
          PREP_SWAP;
          SWAP( store, SILO, SILO_IDX, SID );

          // add it to the new one
          SILO_IDX = entry_size < 21 ? 3 : (int)round( logf( entry_size ) );
          SET_SILO( store, SILO_IDX );
          SID = silo_next_id( SILO );

        }
    }
  else
    { // new entry
      SILO_IDX = entry_size < 21 ? 3 : (int)round( logf( entry_size ) );
      SET_SILO( store, SILO_IDX );
      SID = silo_next_id( SILO );
    }
  // update the entry, which is id/data
  memcpy( entry_data, &rid, sizeof( RECSIZE ) );
  memcpy( entry_data + sizeof(RECSIZE), data, save_size );
  if ( 0 == silo_put_record( SILO, SID, entry_data, entry_size ) )
    {
      // update the index
      SAVE_INDEX( store, rid, SILO_IDX, SID );
    }
  
  free( entry_data );
  
  return rid;
} //stow

char *
fetch( RecordStore *store, RECSIZE rid )
{
  char       * entry;
  char       * record;
  RECSIZE    size;

  PREP_INDEX;
  LOAD_INDEX( store, rid );
  if ( SID > 0 )
    {
      PREP_SILO;
      SET_SILO( store, SILO_IDX );
      entry = silo_get_record( SILO, SID );
          
      size   = 1 + SILO->record_size - sizeof( RECSIZE );
      record = calloc( size, 1 );
      memcpy( record, entry + sizeof( RECSIZE ), size );
      
      free( entry );
      
      return record;
    }
  return NULL;
}


void
recycle_id( RecordStore *store, RECSIZE rid )
{
  char * cid = malloc( sizeof( RECSIZE ) );
  memcpy( cid, &rid, sizeof( RECSIZE ) );
  silo_push( store->recycle_silo, cid, 0 );
  delete_record( store, rid );
  free( cid );
} //recycle_id


void
empty_recycler( RecordStore *store )
{
  empty_silo( store->recycle_silo );
} //empty_recycler


Transaction *
create_transaction( RecordStore *store )
{
  // creates an entry in the transaction silo and
  // creates a silo for this record
  Transaction * trans;
  char        * silo_dir;
  
  trans = calloc( sizeof( Transaction ), 1 );
  trans->tid         = silo_next_id( store->trans_silo );
  trans->pid         = getpid();
  trans->update_time = time(NULL);
  trans->state       = TRA_ACTIVE;

  silo_put_record( store->trans_silo,
                   trans->tid,
                   trans,
                   sizeof( Transaction ) );
  
  trans->store = store;

  // DIR/A/ID
  silo_dir = malloc( 4 + sizeof( store->directory ) + (trans->tid > 10 ? ceil(log10(trans->tid)) : 1 ) );
  sprintf( silo_dir, "%s%s%s%s%lld",
           store->directory,
           PATHSEP,
           "A",
           PATHSEP,
           trans->tid );
  
  trans->silo = open_silo( silo_dir, sizeof( TransactionEntry ) );
  
  free( silo_dir );
       
  return trans;
} //create_transaction


Transaction *
open_transaction( RecordStore *store, RECSIZE tid )
{
  // creates an entry in the transaction silo and
  // creates a silo for this record
  Transaction * trans;
  char        * silo_dir;
  
  trans = (Transaction*)silo_get_record( store->trans_silo, tid );

  // DIR/A/ID
  silo_dir = malloc( 4 + sizeof( store->directory ) + (trans->tid > 10 ? ceil(log10(tid)) : 1 ) );
  sprintf( silo_dir, "%s%s%s%s%lld",
           store->directory,
           PATHSEP,
           "A",
           PATHSEP,
           tid );
  
  trans->silo  = open_silo( silo_dir, sizeof( TransactionEntry ) );
  trans->store = store;
  
  free( silo_dir );
       
  return trans;
} //open_transaction


Transaction ** 
list_transactions( RecordStore *store )
{
  Transaction ** tlist;
  Transaction  * trans;
  RECSIZE entry_count = silo_entry_count( store->trans_silo );
  RECSIZE i, ts;
  tlist = calloc( sizeof(Transaction*), 1 + entry_count );
  for ( i=0; i<entry_count; i++ )
    {
      trans = silo_get_record( store->trans_silo, i );
      if ( trans->state != TRA_DONE )
        {
          tlist[ ts++ ] = trans;
        }
    }
  return tlist;
} //list_transactions

RECSIZE
trans_stow( Transaction *trans, char *data, RECSIZE rid, RECSIZE write_amount )
{
  RECSIZE trans_rid;
  if( trans->state == TRA_ACTIVE )
    {
      trans_rid = silo_next_id( trans->store->index_silo );
      stow( trans->store, data, trans_rid, write_amount );
      
      TRANS( trans, TRA_STOW, rid, trans_rid );
      return TRANS_RES;
    }
  return 1;
} //trans_stow

int
trans_delete_record( Transaction *trans, RECSIZE rid )
{
  TRANS( trans, TRA_DELETE, rid, 0 );
  return TRANS_RES;
} //trans_delete_record

int
trans_recycle_id( Transaction *trans, RECSIZE rid )
{
  TRANS( trans, TRA_RECYCLE, rid, 0 );
  return TRANS_RES;
}

int
commit( Transaction *trans )
{
  /*
    We all know what a commit is for transactions.

    There are 3 transaction actions that operate on 
       a record : STOW, DELETE, RECYCLE.

    The records are indexed by rid (record id). When
       a STOW happens, a new data entry is recorded with
       the new stow data and the old entry is preserved.
       The master record index still points to the original location
       until the commit.

    DELETE and RECYCLE remove an entry, with RECYCLE
       making its rid available for reuse.

    Commit looks at each action in a transaction, starting
       with the latest one. DELETE and RECYCLE are easy, their
       order doesn't matter. with STOW, the order can matter since
       a single record may be stowed multiple times. The last one
       is the 'final' one for this transaction. The master record
       index is updated to this new locatoin and the old location(s)
       are purged of the old data and that space recovered.

    The space recovery is done by moving the last data entry in the 
       silo files to the now available spot and updating the master
       record index for the swapped out entry to point to this spot.
   */
  RecordStore      *  store;
  
  RECSIZE           i, j;
  TransactionEntry *  entry;
  RECSIZE   *       rid_list;
  
  RECSIZE   *       purged_rids;
  long int            purged_rid_count;
  
  RECSIZE           entry_count;
  RECSIZE           entries;
  
  int                 had_entry;
  
  TransactionEntry ** purge_to_list;
  RECSIZE           purge_to_count;
  
  TransactionEntry ** purge_from_list;
  RECSIZE           purge_from_count;
  
  if ( trans->state == TRA_ACTIVE         ||
       trans->state == TRA_IN_COMMIT      ||
       trans->state == TRA_IN_ROLLBACK    ||
       trans->state == TRA_CLEANUP_COMMIT )
    {
      store = trans->store;
      
      purge_to_count   = 0;
      purge_from_count = 0;
      entry_count  = 0;

      
      trans->state = TRA_IN_COMMIT;
      trans->pid   = getpid();
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );

      
      entries = silo_entry_count( trans->silo );
      rid_list        = calloc( sizeof(RECSIZE), entries );
      purge_to_list   = calloc( sizeof(TransactionEntry*), entries );
      purge_from_list = calloc( sizeof(TransactionEntry*), entries );

      // update the indexes for the transaction entries.
      for ( i=entries; i > 0; i-- )
        {
          entry = (TransactionEntry*)silo_get_record( trans->silo, i );

          // if we have encountered
          had_entry = 0;
          for ( j=0; j<entry_count; j++ )
            {
              if ( rid_list[j] == entry->rid )
                {
                  had_entry = 1;
                  break;
                }
            }
          
          if ( had_entry )
            {
              if ( entry->type == TRA_STOW )
                {
                  // purge the 'to'
                  purge_to_list[purge_to_count++] = entry;
                }
            }
          else
            {
              rid_list[entry_count++] = entry->rid;
              if ( entry->type == TRA_STOW )
                {
                  // update index
                  SAVE_INDEX( store, entry->rid, entry->to_silo_idx, entry->to_sid );
                }
              else //deletion
                {
                  SAVE_INDEX( store, entry->rid, 0, 0 );
                }
              // purge the 'from'
              purge_from_list[purge_from_count++] = entry;
            }
        } // update index for each transaction entry

      trans->state = TRA_CLEANUP_COMMIT;
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );

      // purge to contains prevoius STOWS for a single rid.
      // the destination locations for these are no longer
      // valid and can be swapped away.
      purged_rid_count = 0;
      purged_rids = calloc( sizeof( RECSIZE ), purge_to_count );
      PREP_SWAP;
      for ( i=0; i<purge_to_count; i++ )
        {
          entry = purge_to_list[i];
          SWAP( store, store->silos[entry->to_silo_idx], entry->to_silo_idx, entry->to_sid );
          purged_rids[ purged_rid_count++ ] = entry->rid;
        } //each purge_to
      
      // the from_count is to purge items that are either deleted
      // or have a single stow (multiple stows cruft was removed above )
      
      for ( i=0; i<purge_from_count; i++ )
        {
          entry = purge_from_list[i];
          if ( entry->type == TRA_STOW )
            {
              // check if this 'from' had already been purged by a 'to'
              // if so, don't swapout
              had_entry = 0;
              for ( j=0; j<purged_rid_count; j++ )
                {
                  if ( purged_rids[ j ] == entry->rid )
                    {
                      had_entry = 1;
                      break;
                    }
                }
              if ( 0 == had_entry )
                {
                  SWAP( store, store->silos[entry->from_silo_idx], entry->from_silo_idx, entry->from_sid );
                }
            }
          else if ( entry->type == TRA_DELETE )
            {
              delete_record( store, entry->rid );
            }
          else // if ( entry->type == TRA_RECYCLE )
            {
              recycle_id( store, entry->rid );
            }
        } //each purge from 

      // update catalog
      trans->state = TRA_DONE;
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );
      unlink_silo( trans->silo );

      return 0;
    } // if reasonable state
  
  return 1;

} //commit


int
rollback( Transaction *trans )
{
  RecordStore      *  store;

  RECSIZE           i;
  TransactionEntry *  entry;
  
  TransactionEntry ** swapouts;
  long int            swapout_count;
  
  RECSIZE           entries;

  // CLEANUP COMMIT might be dangerous, the state may be
  // inconsistant
  if ( trans->state == TRA_ACTIVE         ||
       trans->state == TRA_IN_COMMIT      ||
       trans->state == TRA_IN_ROLLBACK    ||
       trans->state == TRA_CLEANUP_COMMIT )
    {
      store = trans->store;
      
      trans->state = TRA_IN_ROLLBACK;
      trans->pid   = getpid();
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );

      entries = silo_entry_count( trans->silo );
      swapouts = calloc( sizeof( TransactionEntry * ), entries );
      swapout_count = 0;
      //  [ from, to-rom ]  --> [ to-rom to-rom2 ] ---> [ to-rom2 to  ]
      //    swapout to, to-rom2, to-rom
      for ( i=entries; i > 0; i-- )
        {
          entry = (TransactionEntry *)silo_get_record( trans->silo, i );
          if ( entry->from_sid )
            {
              SAVE_INDEX( store, entry->rid, entry->from_silo_idx, entry->from_sid );
            }
          else
            {
              // a first time stow
              SAVE_INDEX( store, entry->rid, 0, 0LL );
            }
          if ( entry->to_sid )
            {
              // add to swapouts
              swapouts[ swapout_count++ ] = entry;
            }
        } // each entry
      
      trans->state = TRA_CLEANUP_ROLLBACK;
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );
      PREP_SWAP;
      for ( i=0; i<swapout_count; i++ )
        {
          entry = swapouts[ i ];
          SWAP( store, store->silos[entry->to_silo_idx], entry->to_silo_idx, entry->to_sid );
        }
      
      // now do the swapouts
      
      trans->state = TRA_DONE;
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );
      
      return 0;
    } // if okey state
  return 1;
} //rollback
