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

  store = (RecordStore *)malloc( sizeof( RecordStore ) );
  store->version       = RS_VERSION;
  store->max_file_size = max_file_size;
  store->silos         = calloc( MAX_SILOS, sizeof( Silo * ) );
  store->directory     = strdup(directory);

  
  char * dir = malloc( strlen( directory ) + 3  );
  sprintf( dir, "%s%s%s", directory, PATHSEP, "S" );
  i = strlen(dir);

  make_path( dir );
  
  sprintf( dir, "%s%s%s", directory, PATHSEP, "I" );
  
  store->index_silo = open_silo( dir, 1 + sizeof(int) + sizeof(long), max_file_size );

  sprintf( dir, "%s%s%s", directory, PATHSEP, "R" );
  store->recycle_silo = open_silo( dir, 1 + sizeof(long), max_file_size );  
  
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
} //empty_store

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
stow( RecordStore *store, char *data, unsigned long rid )
{
  Silo        * silo;
  int           silo_idx;
  
  unsigned long sid;
  unsigned long save_size;
  char        * entry_data;
  
  char        * index_data;
  
  rid = rid == 0 ? silo_next_id( store->index_silo ) : rid;

  save_size = 1 + strlen( data ) + sizeof( unsigned long );
  entry_data = malloc( save_size );
  index_data = silo_get_record( store->index_silo, rid );
  if ( strlen( index_data ) > 0 )
    {
      memcpy( &silo_idx, index_data, sizeof( int ));
      memcpy( &sid, index_data + sizeof( int ), sizeof( unsigned long ));
      silo = _get_silo( store, silo_idx );
      if ( save_size > silo->record_size )
        { // needs to find a new silo

          // remove it from the old silo
          _swapout( store, silo, silo_idx, sid );

          // add it to the new one
          silo_idx = 1 + (int)round( logf( save_size ) );
          silo = _get_silo( store, silo_idx );
          sid = silo_next_id( silo );

        }
    }
  else
    { // new entry
      silo_idx = 1 + (int)round( logf( save_size ) );
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
          CRY("SILO IDX %d\n",silo_idx);
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
  if ( strlen( index_entry ) > 0 )
    {
      ie = malloc( sizeof( IndexEntry ) );
      memcpy( ie, index_entry, sizeof( IndexEntry ) );
      free( index_entry );
      return ie;
    }
  
  return NULL;
  
} //_index_entry;

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
      silo_put_record( silo, vacated_sid, swap_record, 0 );

      // update the index
      index_entry = silo_get_record( store->index_silo, swap_rid );
      if( index_entry )
        {
          
        }
      swap_entry = _index_entry( store, swap_rid );
      swap_entry->sid = vacated_sid;
      silo_put_record( store->index_silo, vacated_sid, swap_entry, 0 );
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
  record_size = (unsigned long)round( exp( sidx ) );
  dir = malloc( 4 + strlen( store->directory ) + (sidx > 1 ? (1+((int)ceil(log10(sidx)))) : 1 ) );
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

