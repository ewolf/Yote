#include "record_store.h"
#include "util.h"

// rid  - record entry index id
// sid  - silo entry index id
// sidx - index of silo

void _swapout( RecordStore *store, Silo *silo, int silo_idx, unsigned long vacated_sid );

Silo * _get_silo( RecordStore *store, int sidx );

RecordStore *
open_store( char *directory, unsigned long max_file_size )
{
  RecordStore * store;
  //   /S  -silos   /R  -recyclesilo  /I  -indexsilo  /T -transcata /A - transActions

  store = (RecordStore *)malloc( sizeof( RecordStore ) );
  store->version       = RS_VERSION;
  store->max_file_size = max_file_size;
  store->silos         = calloc( MAX_SILOS, sizeof( Silo * ) );
  store->directory     = strdup(directory);

  
  char * dir = malloc( strlen( directory ) + 3  );
  sprintf( dir, "%s%s%s", directory, PATHSEP, "S" );

  make_path( dir );
  
  sprintf( dir, "%s%s%s", directory, PATHSEP, "I" );
  
  store->index_silo = open_silo( dir, sizeof(int) + sizeof(long), max_file_size );

  sprintf( dir, "%s%s%s", directory, PATHSEP, "R" );
  store->recycle_silo = open_silo( dir, sizeof(long), max_file_size );

  sprintf( dir, "%s%s%s", directory, PATHSEP, "T" );  
  store->index_silo = open_silo( dir,
                                 sizeof( unsigned long ) +  // transaction id
                                 sizeof( unsigned long ) +  // process id
                                 sizeof( unsigned long ) +  // update time
                                 sizeof( int ),             // state
                                 max_file_size );
  
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
  cleanup_silo( store->transaction_catalog_silo );
  free( store->transaction_catalog_silo );
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
  empty_silo( store->transaction_catalog_silo );
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
  unlink_silo( store->transaction_catalog_silo );
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

unsigned long
store_entry_count( RecordStore *store )
{
  return silo_entry_count( store->index_silo ) - silo_entry_count( store->recycle_silo );
} //store_entry_count

unsigned long
next_id( RecordStore *store )
{
  unsigned long recycled_rid;
  char *recycled;
  recycled = silo_pop( store->recycle_silo );
  if ( recycled != NULL ) {
    memcpy( &recycled_rid, recycled, sizeof( unsigned long ) );
    free( recycled );
    return recycled_rid;
  }
  return silo_next_id( store->index_silo );
} //next_id


int
has_id( RecordStore *store, unsigned long rid )
{
  int    silo_idx;
  char * index_data;
  
  index_data = silo_get_record( store->index_silo, rid );
  if ( index_data ) {
    memcpy( &silo_idx, index_data, sizeof( int ) );
    free( index_data );
    return silo_idx > 0;
  }
  return 0;
} //has_id

void
delete_record( RecordStore *store, unsigned long rid )
{
  int           silo_idx;
  char *        index_data;
  unsigned long sid;
  
  index_data = silo_get_record( store->index_silo, rid );
  if ( index_data != NULL )
    {
      memcpy( &silo_idx, index_data, sizeof( int ) );
      if ( silo_idx > 0 )
        {
          memcpy( &sid, index_data + sizeof( int ), sizeof( unsigned long ) );
          // write a blank index record and swap out the old data          
          _swapout( store, store->silos[silo_idx], silo_idx, sid );
          index_data[0] = '\0';
          silo_put_record( store->index_silo, rid, index_data, 1 );
        }
      free( index_data );
    }      
} //delete_record

unsigned long
stow( RecordStore *store, char *data, unsigned long rid, unsigned long save_size )
{
  Silo        * silo;
  int           silo_idx;
  
  unsigned long sid;
  
  char        * entry_data;
  
  char        * index_data;
  
  rid = rid == 0 ? silo_next_id( store->index_silo ) : rid;

  if ( save_size == 0 )
    {
      save_size = 1 + strlen( data );
    }
  save_size = save_size + sizeof( unsigned long );
  entry_data = malloc( save_size );
  index_data = silo_get_record( store->index_silo, rid );
  if ( index_data && strlen( index_data ) > 0 )
    {
      memcpy( &silo_idx, index_data, sizeof( int ));
      memcpy( &sid, index_data + sizeof( int ), sizeof( unsigned long ));
      silo = _get_silo( store, silo_idx );
      if ( save_size > silo->record_size )
        { // needs to find a new silo

          // remove it from the old silo
          _swapout( store, silo, silo_idx, sid );

          // add it to the new one
          silo_idx = save_size < 21 ? 3 : (int)round( logf( save_size ) );
          silo = _get_silo( store, silo_idx );
          sid = silo_next_id( silo );

        }
    }
  else
    { // new entry
      silo_idx = save_size < 21 ? 3 : (int)round( logf( save_size ) );

      silo = _get_silo( store, silo_idx );
      sid = silo_next_id( silo );
    }
  
  // update the entry, which is id/data
  memcpy( entry_data, &rid, sizeof( unsigned long ) );
  memcpy( entry_data + sizeof(unsigned long), data, strlen( data ) );
  entry_data[sizeof(unsigned long) + strlen( data )] = '\0';
  silo_put_record( silo, sid, entry_data, 1 + strlen(data) + sizeof(unsigned long) );
  
  // update the index
  free( index_data );
  index_data = malloc( 1 + sizeof( int ) + sizeof( unsigned long )  );
  memcpy( index_data, &silo_idx, sizeof( int ) );
  memcpy( index_data + sizeof( int ), &sid, sizeof( unsigned long ) );
   
  silo_put_record( store->index_silo, rid, index_data, sizeof( int ) + sizeof( unsigned long ) );

  free( index_data );
  free( entry_data );
  
  return 0;
} //stow

char *
fetch( RecordStore *store, unsigned long rid )
{
  Silo       *  silo;
  int           silo_idx;
  
  unsigned long sid;
  char       *  index_data;
  
  char       *  entry;
  char       *  record;
  unsigned long size;
  
  index_data = silo_get_record( store->index_silo, rid );
  if( index_data )
    {
      memcpy( &silo_idx, index_data, sizeof( int ));
      if( silo_idx > 0 )
        {
          memcpy( &sid, index_data + sizeof( int ), sizeof( unsigned long ));
          silo   = _get_silo( store, silo_idx );
          entry  = silo_get_record( silo, sid );
          
          size   = 1 + strlen(entry+sizeof( unsigned long ) );
          record = malloc( size );
          memcpy( record, entry + sizeof( unsigned long ), size );
          
          free( entry );
          free( index_data );
          
          return record;
        }
      free( index_data );
    }
  return NULL;
}


void
recycle_id( RecordStore *store, unsigned long rid )
{
  char * cid = malloc( sizeof( unsigned long ) );
  memcpy( cid, &rid, sizeof( unsigned long ) );
  silo_push( store->recycle_silo, cid, 0 );
  delete_record( store, rid );
  free( cid );
} //recycle_id


void
empty_recycler( RecordStore *store )
{
  empty_silo( store->recycle_silo );
} //empty_recycler


void _swapout( RecordStore *store, Silo *silo, int silo_idx, unsigned long vacated_sid )
{
  char        * swap_record;
  unsigned long swap_rid;
  char        * index_entry;
  unsigned long last_sid = silo_entry_count( silo );
  if ( vacated_sid < last_sid )
    {
      // move last record to the space left by the
      // vacating record. Do a copy to be safer rather
      // than a pop which could lose data
      swap_record = silo_get_record( silo, last_sid );
      memcpy( &swap_rid, swap_record, sizeof( unsigned long ) );
      silo_put_record( silo, vacated_sid, swap_record, silo->record_size );

      // update the index
      index_entry = malloc( sizeof( int ) + sizeof( unsigned long ) );
      memcpy( index_entry, &silo_idx, sizeof( int ) );
      memcpy( index_entry + sizeof( int ), &swap_rid, sizeof( unsigned long ) );
      silo_put_record( silo, swap_rid, index_entry, sizeof( int ) + sizeof( unsigned long ) );

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


Silo *
_get_silo( RecordStore *store, int sidx )
{
  Silo *s;
  unsigned long record_size;
  char * dir;
  if ( sidx >= MAX_SILOS )
    {
      return NULL;
    }
  
  s = store->silos[ sidx ];
  if ( s != NULL )
    {
      return s;
    }
  record_size = (unsigned long)round( exp( sidx ) );
  dir = malloc( 4 + strlen( store->directory ) + (sidx > 10 ? ceil(log10(sidx)) : 1 ) );
  dir[0] = '\0';
  sprintf( dir, "%s%s%s%s%d",
           store->directory,
           PATHSEP,
           "S",
           PATHSEP,
           sidx
           );
  
  s = open_silo( dir, record_size, store->max_file_size );
  store->silos[ sidx ] = s;
  free( dir );
  return s;
} //_get_silo

int _trans( Transaction *trans, int trans_type, unsigned long ridA, unsigned long ridB );


Transaction *
create_transaction( RecordStore *store )
{
  // creates an entry in the transaction_catalog silo and
  // creates a silo for this record
  Transaction * trans;
  char        * silo_dir;
  
  trans = malloc( store->transaction_catalog_silo->record_size + 
                  sizeof( Silo * ) + sizeof( RecordStore * ) );
  trans->tid         = silo_next_id( store->transaction_catalog_silo );
  trans->pid         = getpid();
  trans->update_time = time(NULL);
  trans->state       = TRA_ACTIVE;

  silo_put_record( store->transaction_catalog_silo,
                   trans->tid,
                   trans,
                   store->transaction_catalog_silo->record_size );
  
  trans->store = store;

  // DIR/A/ID
  silo_dir = malloc( 4 + sizeof( store->directory ) + (trans->tid > 10 ? ceil(log10(trans->tid)) : 1 ) );
  sprintf( silo_dir, "%s%s%s%s%d",
           store->directory,
           PATHSEP,
           "A",
           PATHSEP,
           trans->tid );
  
  trans->silo = open_silo( silo_dir, sizeof( TransactionEntry ), store->max_file_size );
  
  free( silo_dir );
       
  return trans;
} //create_transaction


Transaction *
open_transaction( RecordStore *store, unsigned long tid )
{
  // creates an entry in the transaction_catalog silo and
  // creates a silo for this record
  Transaction * trans;
  char        * silo_dir;
  
  trans = silo_get_record( store->transaction_catalog_silo, tid );

  // DIR/A/ID
  silo_dir = malloc( 4 + sizeof( store->directory ) + (trans->tid > 10 ? ceil(log10(tid)) : 1 ) );
  sprintf( silo_dir, "%s%s%s%s%d",
           store->directory,
           PATHSEP,
           "A",
           PATHSEP,
           tid );
  
  trans->silo = open_silo( silo_dir, sizeof( TransactionEntry ), store->max_file_size );
  
  free( silo_dir );
       
  return trans;
} //open_transaction


Transaction *
list_transactions( RecordStore *store )
{
  /*
  char * meta_dir;
  char * meta_data;
  unsigned long items, i;
  Silo * meta_silo;
  Transaction *trans;
  meta_dir = malloc( 5 + strlen(store->directory) );
  sprintf( meta_dir, "%s%s%s%s%s", store->directory, PATHSEP, "T", PATHSEP, "M" );
  meta_silo = open_silo( meta_dir,
                         sizeof( unsigned long ) + sizeof( int ) + sizeof( int ) + sizeof( unsigned long ),
                         store->max_file_size );
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

unsigned long
trans_stow( Transaction *trans, char *data, unsigned long rid, unsigned long write_amount )
{
  char * record;
  char * trans_record;
  unsigned long trans_rid;
  if( trans->state == TRA_ACTIVE )
    {
      trans_rid = silo_next_id( trans->store->index_silo );
      stow( trans->store, data, trans_rid, write_amount );
      
      return _trans( trans, TRA_STOW, rid, trans_rid );
    }
  return 1;
} //trans_stow

int
trans_delete_record( Transaction *trans, unsigned long rid )
{
  return _trans( trans, TRA_DELETE, rid, 0 );
} //trans_delete_record

int
trans_recycle_id( Transaction *trans, unsigned long rid )
{
  return _trans( trans, TRA_RECYCLE, rid, 0 );
}

int
_trans( Transaction *trans, int trans_type, unsigned long ridA, unsigned long ridB )
{
  char *        record;
  int           silo_idx;
  unsigned long sid;
  
  char *        trans_record;
  
  unsigned long next_trans_sid;
  if( trans->state == TRA_ACTIVE )
    {
      record = silo_get_record( trans->store->index_silo, ridA );
      memcpy( &silo_idx, record, sizeof( int ) );
      memcpy( &sid, record + sizeof( int ), sizeof( unsigned long ) );
      free( record );
      
      next_trans_sid = silo_next_id( trans->silo );
      trans_record = malloc( trans->silo->record_size );
      memcpy( trans_record, &trans_type, sizeof( int ) );
      memcpy( trans_record + sizeof( int ), &ridA, sizeof( unsigned long ) );
      memcpy( trans_record + sizeof( int ) + sizeof( unsigned long ), &silo_idx, sizeof( int ) );
      memcpy( trans_record + sizeof( int ) + sizeof( unsigned long ) + sizeof( int ),
              &sid, sizeof( unsigned long ) );

      if ( ridB > 0 )
        {
          record = silo_get_record( trans->store->index_silo, ridB );
          memcpy( &silo_idx, record, sizeof( int ) );
          memcpy( &sid, record + sizeof( int ), sizeof( unsigned long ) );
          free( record );
          memcpy( trans_record + sizeof( int ) + sizeof( unsigned long ) +
                  sizeof( int ) + sizeof( unsigned long ),
                  &silo_idx, sizeof( int ) );
          memcpy( trans_record + sizeof( int ) + sizeof( unsigned long ) +
                  sizeof( int ) + sizeof( unsigned long ) + sizeof( int ),
                  &sid, sizeof( unsigned long ) );
        }
      
      
      silo_put_record( trans->silo, next_trans_sid, trans_record, trans->silo->record_size );
      free( trans_record );

      return 0;
    }
  return 1;
} //trans_recycle_id



int
commit( Transaction *trans )
{
  unsigned long i;
  unsigned long actions;
  TransactionEntry * entry;
  if ( trans->state == TRA_ACTIVE         ||
       trans->state == TRA_IN_COMMIT      ||
       trans->state == TRA_IN_ROLLBACK    ||
       trans->state == TRA_CLEANUP_COMMIT )
    {
      actions = silo_entry_count( trans->silo );
      for ( i=actions; i > 0; i++ )
        {
          entry = silo_get_record( trans->silo, i );
          
        }
    }
  else {
    return 1;
  }
} //commit


int
rollback( Transaction *trans )
{

} //rollback
