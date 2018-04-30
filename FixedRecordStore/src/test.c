#include <errno.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "util.h"
#include "silo.h"
#include "record_store.h"

#define VERB 1

typedef struct
{
  int tests_run;
  int tests_fail;
} Test;

void chkb( int a, char * desc, Test *t ) {
  t->tests_run++;
  if( ! a ) {
    t->tests_fail++;
    printf( "Failed : Failed : %s\n", desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
    
}

void chkl( long a, long b, char * desc, Test *t ) {
  t->tests_run++;
  if( a != b ) {
    t->tests_fail++;
    printf( "Failed : Got %ld and expected %ld : %s\n", a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}

void chks( char * a, char * b, char * desc, Test *t ) {
  t->tests_run++;
  if( a == NULL || strcmp(a, b) != 0 ) {
    t->tests_fail++;
    printf( "Failed : Got '%s' and expected '%s' : %s\n", a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}

void test_util( Test * t )
{
  LinkedList * list, * listB;
  char * thing[10];
  chkl( make_path( "///tmp/fooby/blecch/" ), 0, "make path double slash", t );
  chkl( make_path( "/tmp/fooby/blecch/" ), 0, "remake path without double", t );
  chkl( make_path( "/tmp/fooby/blecch" ), 0, "remake path no trailing /", t );
  chkl( make_path( "/usr/sicklydo" ), 2, "make path no perms", t );

  creat( "/tmp/nothingy", 0666 );
  chkl( make_path( "/tmp/nothingy" ), 1, "make path against file", t );

  // linked list test
  thing[0] = strdup("THIS IS THING A");
  thing[1] = strdup("THIS IS THING N");
  thing[2] = strdup("THIS IS THING C");
  thing[3] = strdup("THIS IS THING D");
  thing[4] = strdup("THIS IS THING E");
  thing[5] = strdup("THIS IS THING F");

  list = create_linked_list( thing[0] );
  
  chks( (char*)list->item, "THIS IS THING A", "linked list head string set properly", t );
  listB = insert_next( list, thing[1] );
  chks( list->next->item, "THIS IS THING N", "next string set properly", t );
  chkb( list->prev == 0, "no prev yet", t );
  chkb( listB->prev == list, "prev link to list", t );
  chkb( list->next == listB, "list to prev link", t );
  chks( listB->prev->item, "THIS IS THING A", "next links back", t );

  listB = insert_next( list, thing[2] );
  chks( listB->next->item, "THIS IS THING N", "insert next string set properly", t );
  chks( list->next->next->prev->item, "THIS IS THING C", "bouncy bouncy", t );
  chks( list->item, "THIS IS THING A", "list still list", t );
  
  listB = insert_prev( list, thing[3] );
  chks( listB->next->item, "THIS IS THING A", "prev link back", t );
  chks( list->prev->item, "THIS IS THING D", "prev link to", t );

  listB = insert_prev( list, thing[4] );
  chks( listB->next->item, "THIS IS THING A", "prev ins link back", t );
  chks( listB->prev->item, "THIS IS THING D", "prev ins updated link to", t );
  chks( list->prev->item, "THIS IS THING E", "prev inst link to", t );

  chkb( find_in_list( list, thing[0] ) == list, "found first thing put in", t );
  chkb( find_in_list( list, thing[5] ) == 0, "nothere not found", t );

  
  free_linked_list( list, 1 );
  free( thing[5] );
} //test_util

void test_silo( Test * t )
{
  char dir[] = "SILOONE";
  char  F1[] = "SILOONE/0";
  char  F2[] = "SILOONE/1";
  Silo *silo;
  unsigned long id;
  char * res;
  TransactionEntry * trans;
  struct stat * stat_buffer = malloc( sizeof( struct stat ) );
  
  if ( 0 == stat( dir, stat_buffer ) && S_ISDIR( stat_buffer->st_mode ) )
    {
      printf( "Unlink %s\n", F1 );
      if( 0 != rmdir( F1 ) ) {
        perror( "unlink F1" );
      }
      if( 0 != rmdir( F2 ) ) {
        perror( "unlink F2" );
      }
      if( 0 != rmdir( dir ) ) {
            perror( "unlink dir" );
      }
    }

  silo = open_silo( dir, 11, 44 );
  chkb( silo != NULL, "opened silo", t );
  chkl( stat( dir, stat_buffer ), 0, "Directory created", t );
  chkl( stat( F1, stat_buffer ), 0, "First silo file created", t );
  
  stat( dir, stat_buffer );
  if ( ! S_ISDIR( stat_buffer->st_mode ) )
    {
      printf( "FAIL : silo directory not created. bailing\n" );
      exit( 0 );
    }
  chkl( filecount( dir ), 1, "One file", t );
  chkl( silo_entry_count(silo), 0, "starts at zero entry count", t );
  chkl( silo_put_record( silo, 1, "012345678901", 0 ), 0, "record too large", t );
  chkl( silo_entry_count(silo), 0, "still zero entry count", t );
  chkl( filesize( F1 ), 0, "size 0", t );

  id = silo_next_id( silo );
  chkl( id, 1, "first id", t );
  chkl( filesize( F1 ), 11, "size 1", t );
  
  chkl( silo_put_record( silo, id, "0123456789", 0 ), 1, "first record put", t );
  
  res = silo_get_record( silo, id );
  chks( res, "0123456789", "first entry", t );

  free( res );
  res = silo_last_entry(silo);
  chks( res, "0123456789", "last entry", t );
  chkl( silo_entry_count(silo), 1, "first entry count", t );
  chkl( silo_put_record( silo, id, "0123456789", 0 ), 1, "put first valid record", t );
  
  free( res );
  res = silo_last_entry(silo);
  chks( res, "0123456789", "first last entry still same", t );
  free( res );
  res = silo_get_record(silo,1);
  chks( res, "0123456789", "first entry still same", t );
  chkl( silo_entry_count(silo), 1, "first entry count still same", t );

  id = silo_push( silo, "POOOPYTWO", 0 );
  chkl( id, 2, "second entry id", t );
  chkl( filesize( F1 ), 22, "size 2", t );
  chkl( silo_entry_count(silo), 2, "second entry count", t );
  free( res );
  res = silo_get_record( silo, 1 );
  chks( res, "0123456789", "Still first entry", t );
  free( res );
  res = silo_get_record( silo, 2 );
  chks( res, "POOOPYTWO", "second entry", t );
  free( res );
  res = silo_last_entry( silo );
  chks( res, "POOOPYTWO", "second and last entry", t );
  
  free( res );
  res = silo_pop( silo );
  chkl( filesize( F1 ), 11, "back to size 1", t );
  chks( res, "POOOPYTWO", "second entry popped off", t );
  chkl( silo_entry_count(silo), 1, "popped entry count", t );

  free( res );
  res = silo_last_entry( silo );
  chks( res, "0123456789", "last entry after pop", t );

  id = silo_next_id( silo );
  chkl( id, 2, "next id after pop", t );
  chkl( silo_entry_count(silo), 2, "entry count after next_id", t );

  // make sure there is just one file
  chkl( filecount( dir ), 1, "One file", t ); 
  
  chkl( silo_put_record( silo, 6, "9876543210", 0 ), 1, "put first valid record", t );  
  chkl( filesize( F1 ), 44, "full size for file 1", t );
  chkl( filesize( F2 ), 22, "half size for file 2", t );
  chkl( silo_entry_count(silo), 6, "6 records now", t );
  
  free( res );
  res = silo_get_record( silo, 5 );
  chks( res, "", "empty record 5", t );
  
  free( res );
  res = silo_get_record( silo, 4 );
  chks( res, "", "empty record 4", t );
  free( res );

  // test emtpy_silo
  empty_silo( silo );
  chkl( silo_entry_count(silo), 0, "entry count after empty", t );
  stat( dir, stat_buffer );
  chkb( S_ISDIR( stat_buffer->st_mode ), "Directory still exists after empty", t );

  // test unlink_silo
  unlink_silo( silo );
  chkb( 0 != stat( dir, stat_buffer ), "Directory gone after unlink", t );
  
  cleanup_silo( silo );
  free( silo );
  free( stat_buffer );

  // new silo for TransactionEntry
  silo  = open_silo( dir, sizeof( TransactionEntry ), 1000 );
  trans = calloc( sizeof( TransactionEntry ), 1 );
  trans->type = 1;
  trans->rid  = 2;
  trans->from_silo_idx = 3;
  trans->from_sid = 4;
  trans->to_silo_idx = 5;
  trans->to_sid = 6;

  id = silo_next_id( silo );
  chkl( silo_put_record( silo, id, (char*)trans, sizeof( TransactionEntry ) ), 1, "Put Trans Record", t );
  free( trans );

  trans = (TransactionEntry*)silo_get_record( silo, 1 );
  chkl( trans->type, 1, "Trans E a", t );
  chkl( trans->rid, 2, "Trans E b", t );
  chkl( trans->from_silo_idx, 3, "Trans E c", t );
  chkl( trans->from_sid, 4, "Trans E d", t );
  chkl( trans->to_silo_idx, 5, "Trans E e", t );
  chkl( trans->to_sid, 6, "Trans E f", t );

  free( trans );
  unlink_silo( silo );
  
  cleanup_silo( silo );
  free( silo );
  
} //test_silo

void test_record_store( Test *t )
{
  unsigned long id;
  RecordStore * store = open_store( "RECSTORE", 80 );
  chkl( silo_entry_count(store->index_silo), 0, "store created and nothing in index", t );
  char * res;
  
  id = next_id( store );
  chkl( id, 1, "first record id", t );

  stow( store, "0123456789" , 1, 0 );
  
  res = fetch( store, 1 );
  chks( res, "0123456789" , "first item", t );
  free( res );
  stow( store, "1123456789" , 5, 0 );

  id = next_id( store );
  chkl( id, 6, "rec id now", t );  

  chkl( store_entry_count( store ), 6, "6 entries in store", t );

  chkb( has_id( store, 1 ), "has first id", t );
  chkb( ! has_id( store, 2 ), "no second id", t );
  chkb( ! has_id( store, 3 ), "no third id", t );
  chkb( ! has_id( store, 4 ), "no fourth id", t );
  chkb( has_id( store, 5 ), "has fifth id", t );
  chkb( !has_id( store, 6 ), "no sixth id", t );

  chkl( silo_entry_count( store->silos[3] ), 2, "two entries in second silo", t );

  delete_record( store, 5 );
  chkl( silo_entry_count( store->silos[3] ), 1, "one entry in second silo after deletion and swap", t );
  chkl( store_entry_count( store ), 6, "still 6 entries in store fater delete", t );

  stow( store, "2123456789" , 5, 0 );
  chkl( silo_entry_count( store->silos[3] ), 2, "two entries in second silo", t );
  chkl( store_entry_count( store ), 6, "still 6 entries in store", t );
  recycle_id( store, 6 );
  chkl( store_entry_count( store ), 5, "now 5 entries in store", t );
  recycle_id( store, 5 );
  chkl( store_entry_count( store ), 4, "now 4 entries in store", t );
  chkl( silo_entry_count( store->silos[3] ), 1, "one entry in second silo after recycle", t );
  id = next_id( store );
  chkl( id, 5, "recycled id 5", t );
  id = next_id( store );
  chkl( id, 6, "recycled id 6", t );
  
  // this is in silo index 3
  res = fetch( store, 5 );
  chkb( res == 0, "nothing for recycled id", t );
  delete_record( store, 3 );
  unlink_store( store );
  
  cleanup_store( store );
  free( store );

}//test_record_store

int main() {
  var x = buildstring( "THIS", "/", "IS A", " BIGSTRING" );
  printf( "'%s'\n", x );
  return;
  
  printf( "Starting tests\n" );
  Test * t = malloc( sizeof(Test) );
  t->tests_run = 0;
  t->tests_fail = 0;

  test_util( t );
  test_silo( t );
  test_record_store( t );
    
  // TODO BUSYWORK - make sure all of these have return values that can be analyzed
  // for success, etc.
  if ( t->tests_fail == 0 )
    {
      printf( "Passed all %d tests\n", t->tests_run );
    }
  else
    {
      printf( "Passed %d / %d tests\n", (t->tests_run - t->tests_fail), t->tests_run );
    }
  free( t );
  return 0;
}

