#include "record_store.h"
#include "util.h"

// rid  - record entry index id
// sid  - silo entry index id
// sidx - index of silo

void _swapout( RecordStore *store, Silo *silo, int silo_idx, long long vacated_sid );

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
  store->recycle_silo = open_silo( dir, sizeof(long long) );

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

long long
store_entry_count( RecordStore *store )
{
  return silo_entry_count( store->index_silo ) - silo_entry_count( store->recycle_silo );
} //store_entry_count

long long
next_id( RecordStore *store )
{
  long long recycled_rid;
  char *recycled;
  recycled = silo_pop( store->recycle_silo );
  if ( recycled != NULL ) {
    memcpy( &recycled_rid, recycled, sizeof( long long ) );
    free( recycled );
    return recycled_rid;
  }
  return silo_next_id( store->index_silo );
} //next_id

int
has_id( RecordStore *store, long long rid )
{
  PREP_INDEX;
  LOAD_INDEX( store, rid );
  return SID > 0;
} //has_id

void
delete_record( RecordStore *store, long long rid )
{
  PREP_INDEX;
  LOAD_INDEX( store, rid );
  if ( SID > 0 )
    {
      // write a blank index record and swap out the old data
      _swapout( store, SILO, SILO_IDX, SID );
      SAVE_INDEX( store, rid, 0, 0 );
    }
} //delete_record

long long
stow( RecordStore *store, char *data, long long rid, long long save_size )
{
  char    * entry_data;
  long long entry_size;
  
  rid = rid == 0 ? silo_next_id( store->index_silo ) : rid;
  if ( save_size == 0 )
    {
      save_size = 1 + strlen( data );
    }
  entry_size = save_size + sizeof( long long );
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
          _swapout( store, SILO, SILO_IDX, SID );

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
  memcpy( entry_data, &rid, sizeof( long long ) );
  memcpy( entry_data + sizeof(long long), data, save_size );
  silo_put_record( SILO, SID, entry_data, entry_size );
  
  // update the index
  SAVE_INDEX( store, rid, SILO_IDX, SID );

  free( entry_data );
  
  return 0;
} //stow

char *
fetch( RecordStore *store, long long rid )
{
  char       * entry;
  char       * record;
  long long    size;

  PREP_INDEX;
  LOAD_INDEX( store, rid );
  if ( SID > 0 )
    {
      PREP_SILO;
      SET_SILO( store, SILO_IDX );
      entry = silo_get_record( SILO, SID );
          
      size   = 1 + SILO->record_size - sizeof( long long );
      record = calloc( size, 1 );
      memcpy( record, entry + sizeof( long long ), size );
      
      free( entry );
      
      return record;
    }
  return NULL;
}


void
recycle_id( RecordStore *store, long long rid )
{
  char * cid = malloc( sizeof( long long ) );
  memcpy( cid, &rid, sizeof( long long ) );
  silo_push( store->recycle_silo, cid, 0 );
  delete_record( store, rid );
  free( cid );
} //recycle_id


void
empty_recycler( RecordStore *store )
{
  empty_silo( store->recycle_silo );
} //empty_recycler


void _swapout( RecordStore *store, Silo *silo, int silo_idx, long long vacated_sid )
{
  char        * swap_record;
  long long     swap_rid;
  char        * index_entry;
  long long     last_sid = silo_entry_count( silo );
  
  if ( vacated_sid < last_sid )
    {
      // move last record to the space left by the
      // vacating record. Do a copy to be safer rather
      // than a pop which could lose data
      swap_record = silo_get_record( silo, last_sid );
      memcpy( &swap_rid, swap_record, sizeof( long long ) );
      silo_put_record( silo, vacated_sid, swap_record, silo->record_size );

      // update the index
      index_entry = calloc( sizeof( unsigned int ) + sizeof( long long ), 1 );
      memcpy( index_entry, &silo_idx, sizeof( unsigned int ) );
      memcpy( index_entry + sizeof( int ), &swap_rid, sizeof( long long ) );
      silo_put_record( silo, swap_rid, index_entry, sizeof( unsigned int ) + sizeof( long long ) );

      free( index_entry );
      free( swap_record );

      // remove the last record which has been moved
      swap_record = silo_pop( silo );
      free( swap_record );
    }
  else if ( vacated_sid == last_sid )
    {
      // at the end, so just pop it off
      swap_record = silo_pop( silo );
      free( swap_record );
    }
} //_swapout


int _trans( Transaction *trans, int trans_type, long long ridA, long long ridB );


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
open_transaction( RecordStore *store, long long tid )
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


Transaction *
list_transactions( RecordStore *store )
{
  /*
  char * meta_dir;
  char * meta_data;
  long long items, i;
  Silo * meta_silo;
  Transaction *trans;
  meta_dir = malloc( 5 + strlen(store->directory) );
  sprintf( meta_dir, "%s%s%s%s%s", store->directory, PATHSEP, "T", PATHSEP, "M" );
  meta_silo = open_silo( meta_dir,
                         sizeof( long long ) + sizeof( int ) + sizeof( int ) + sizeof( long long ),
                         store->max_file_size, 1000 );
  items = silo_entry_count( meta_silo );
  for ( i = items ; i > 0; i-- )
    {
      meta_data = silo_get_record( meta_silo, i );
      trans = trans_create( store, meta_data );
      if ( trans && trans->state == TRA_DONE )
        {
          
        }
    }
  free( meta_dir );
  */
  return NULL;
} //list_transactions

long long
trans_stow( Transaction *trans, char *data, long long rid, long long write_amount )
{
  long long trans_rid;
  if( trans->state == TRA_ACTIVE )
    {
      trans_rid = silo_next_id( trans->store->index_silo );
      stow( trans->store, data, trans_rid, write_amount );
      
      return _trans( trans, TRA_STOW, rid, trans_rid );
    }
  return 1;
} //trans_stow

int
trans_delete_record( Transaction *trans, long long rid )
{
  return _trans( trans, TRA_DELETE, rid, 0 );
} //trans_delete_record

int
trans_recycle_id( Transaction *trans, long long rid )
{
  return _trans( trans, TRA_RECYCLE, rid, 0 );
}

int
_trans( Transaction *trans, int trans_type, long long ridA, long long ridB )
{
  RecordStore      * store;
  TransactionEntry * trans_record;
  long long          next_trans_sid;
  
  if( trans->state == TRA_ACTIVE )
    {
      store = trans->store;
      PREP_INDEX;
      LOAD_INDEX( store, ridA );
      
      next_trans_sid = silo_next_id( trans->silo );
      trans_record = (TransactionEntry*)calloc( sizeof(TransactionEntry), 1 );
      trans_record->type          = trans_type;
      trans_record->rid           = ridA;
      trans_record->from_silo_idx = SILO_IDX;
      trans_record->from_sid      = SID;

      if ( ridB > 0 )
        {
          LOAD_INDEX( store, ridB );
          trans_record->to_silo_idx = SILO_IDX;
          trans_record->to_sid      = SID;
        }
      
      silo_put_record( trans->silo, next_trans_sid, trans_record, sizeof( TransactionEntry ) );
      free( trans_record );

      return 0;
    }
  return 1;
} //trans_recycle_id

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
  
  long long           i, j;
  long long           actions;
  TransactionEntry *  entry;
  long long   *       rid_list;
  
  long long   *       purged_rids;
  long int            purged_rid_count;
  
  long long           entry_count;
  long long           entries;
  
  int                 had_entry;
  
  TransactionEntry ** purge_to_list;
  long long           purge_to_count;
  
  TransactionEntry ** purge_from_list;
  long long           purge_from_count;
  
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
      rid_list        = calloc( sizeof(long long), entries );
      purge_to_list   = calloc( sizeof(TransactionEntry*), entries );
      purge_from_list = calloc( sizeof(TransactionEntry*), entries );

      // update the indexes for the transaction entries.
      for ( i=entries; i > 0; i-- )
        {
          entry = (TransactionEntry *)silo_get_record( trans->silo, i );

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
      for ( i=0; i<purge_to_count; i++ )
        {
          entry = purge_to_list[i];
          _swapout( store, store->silos[entry->to_silo_idx], entry->to_silo_idx, entry->to_sid );
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
                  _swapout( store, store->silos[entry->from_silo_idx], entry->from_silo_idx, entry->from_sid );
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
  RecordStore      * store;

  long long          i, j;
  long long          actions;  
  TransactionEntry * entry;
  
  long long        * rid_list;
  long long        * purged_rids;
  long int           purged_rid_count;
  
  long long          entry_count;
  long long          entries;
  int                had_entry;

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
            }
        } // each entry
      
      trans->state = TRA_CLEANUP_ROLLBACK;
      trans->update_time = time(NULL);
      silo_put_record( store->trans_silo,
                       trans->tid,
                       trans,
                       sizeof( Transaction ) );

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
