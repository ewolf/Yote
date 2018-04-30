#include "record_store.h"
#include "util.h"

// rid  - record entry index id
// sid  - silo entry index id
// sidx - index of silo

void _swapout( RecordStore *store, Silo *silo, int silo_idx, unsigned long vacated_sid );

IndexEntry * _index_entry( RecordStore *store, unsigned long rid );
Silo * _get_silo( RecordStore *store, int sidx );

RecordStore *
open_store( char *directory, unsigned long max_file_size )
{
  int i;
  RecordStore * store;
  //   /S   /R   /I
  char * dir = malloc( strlen( directory ) + 3 );
  dir[0] = '\0';
  strcat( dir, directory );
  strcat( dir, PATHSEP );
  i =  strlen(directory);
  strcat( dir, "S" );
  make_path( dir );

  store = (RecordStore *)malloc( sizeof( RecordStore ) );

  store->version = RS_VERSION;
  store->max_file_size = max_file_size;
  
  dir[ i ] = 'I';
  store->index_silo = open_silo( dir, 1 + sizeof(int) + sizeof(long), max_file_size );


  dir[ i ] = 'R';
  store->recycle_silo = open_silo( dir, 1 + sizeof(int) + sizeof(long), max_file_size );  

  free( dir );

  return store;
} //open_store

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
} //empty_store

unsigned long
store_entry_count( RecordStore *store )
{
  return silo_entry_count( store->index_silo ) - silo_entry_count( store->recycle_silo );
} //store_entry_count

unsigned long
next_id( RecordStore *store )
{
  char *recycled_id = silo_pop( store->recycle_silo );
  if ( recycled_id != NULL ) {
    return atol(recycled_id);
  }
  return silo_next_id( store->index_silo );
} //next_id


int
has_id( RecordStore *store, unsigned long rid )
{
  int ret = 0;
  IndexEntry * ie = _index_entry( store, rid );
  if ( ie != NULL )
    {
      ret = ie->silo_idx > 0;
      free( ie );
      return ret;
    }
  return 0;
} //has_id

void
delete_record( RecordStore *store, unsigned long rid )
{
  int silo_idx;
  IndexEntry * ie = _index_entry( store, rid );
  char entry[sizeof(IndexEntry)];
  if ( ie != NULL )
    {
      silo_idx = ie->silo_idx;
      if ( silo_idx > 0 )
        {
          ie->silo_idx = 0;
          memcpy( &entry, ie, sizeof( IndexEntry ) );
          silo_put_record( store->index_silo, rid, entry );
          _swapout( store, store->silos[silo_idx], silo_idx, ie->sid );
          free( ie );
        }
    }
} //delete_record

unsigned long
stow( RecordStore *store, char *data, unsigned long rid )
{
  Silo        * silo;
  IndexEntry  * ie;
  RecordEntry   re;
  unsigned long save_size;
  char        * save_data;
  
  rid = rid == 0 ? silo_next_id( store->index_silo ) : rid;

  // one for the \0
  save_size = 1 + strlen( data ) + sizeof( unsigned long );
  save_data = malloc( save_size );
  
  silo_ensure_entry_count( store->index_silo, rid );
  ie = _index_entry( store, rid );
  if ( ie != NULL )
    {
      silo = _get_silo( store, ie->silo_idx );
      if ( save_size > silo->record_size )
        { // needs to find a new silo

          // remove it from the old silo
          _swapout( store, silo, ie->silo_idx, ie->sid );

          // add it to the new one
          ie->silo_idx = 1 + (int)round( logf( save_size ) );
          silo = _get_silo( store, ie->silo_idx );
          ie->sid = silo_next_id( silo );

        }
    }
  else
    { // new entry
      ie = malloc( sizeof( IndexEntry ) );
      ie->silo_idx = 1 + (int)round( logf( save_size ) );
      silo = _get_silo( store, ie->silo_idx );
      ie->sid = silo_next_id( silo );
    }

  // add the record
  re.rid  = rid;
  re.data = data;
  memcpy( save_data, &re, save_size );
  silo_put_record( silo, ie->sid, save_data );
  
  // update the index
  memcpy( &entry, ie, sizeof( IndexEntry ) );
  silo_put_record( store->index_silo, rid, entry );

  free( save_data );
  free( ie );
  return 0;
} //stow

char *
fetch( RecordStore *store, unsigned long rid )
{
  Silo       * silo;
  IndexEntry * ie;
  char       * record;
  
  ie     = _index_entry( store, rid );
  silo   = _get_silo( store, ie->silo_idx );
  record = silo_get_record( silo, ie->sid );
  record = (char*)record[ sizeof( unsigned long ) ];
  
  free( ie );
  return record;
}


void
recycle_id( RecordStore *store, unsigned long rid )
{
  char * cid = malloc( sizeof( unsigned long ) );
  sprintf( cid, "%ld", rid );
  silo_push( store->recycle_silo, cid );
  delete_record( store, rid );
} //recycle_id
void
empty_recycler( RecordStore *store )
{
  empty_silo( store->recycle_silo );
} //empty_recycler

Transaction *
create_transaction( RecordStore *store )
{
  return NULL;
} //create_transaction

Transaction *
list_transactions( RecordStore *store )
{
  return NULL;
} //list_transactions


IndexEntry *
_index_entry( RecordStore *store, unsigned long rid )
{
  IndexEntry * ie;
  char *index_entry = silo_get_record( store->index_silo, rid );
  if ( index_entry != NULL )
    {
      ie = malloc( sizeof( IndexEntry ) );
      memcpy( ie, index_entry, sizeof( IndexEntry ) );
      return ie;
    }
  
  return NULL;
  
} //_index_entry;

void _swapout( RecordStore *store, Silo *silo, int silo_idx, unsigned long vacated_sid )
{
  char        * swap_record;
  unsigned long swap_rid;
  IndexEntry  * swap_entry;
  unsigned long last_sid = silo_entry_count( silo );
  
  if ( vacated_sid < last_sid )
    {
      // move last record to the space left by the
      // vacating record. Do a copy to be safer rather
      // than a pop which could lose data
      swap_record = silo_get_record( silo, last_sid );
      memcpy( &swap_rid, swap_record, sizeof( unsigned long ) );
      printf( "Got swap record id of %ld\n", swap_rid );
      silo_put_record( silo, vacated_sid, swap_record );

      // update the index
      swap_entry = _index_entry( store, swap_rid );
      swap_entry->sid = vacated_sid;
      silo_put_record( store->index_silo, vacated_sid, swap_entry );
      free( swap_entry );

      // pop the old copy off
      free( swap_record );
      swap_record = silo_pop( silo );
    }
  else if ( vacated_sid == last_sid )
    {
      // at the end, so just pop it off
      swap_record = silo_pop( silo );
    }
  free( swap_record );
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
  record_size = (long)round( exp( sidx ) );
  
  dir = malloc( strlen( store->directory ) + 10 + record_size );
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
