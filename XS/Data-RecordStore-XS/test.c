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

void _chkb( int a, char * desc, unsigned int line, Test *t ) {
  t->tests_run++;
  if( ! a ) {
    t->tests_fail++;
    printf( "Failed : Failed (line %d) : %s\n", line, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
    
}
#define CHKB( a, d ) _chkb( a, d, __LINE__, t );

void _chkl( long a, long b, char * desc, unsigned int line, Test *t ) {
  t->tests_run++;
  if( a != b ) {
    t->tests_fail++;
    printf( "Failed : (line %d) Got %ld and expected %ld : %s\n", line, a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}

#define CHKL( a, b, d ) _chkl( a, b, d, __LINE__, t );
  

void _chks( char * a, char * b, char * desc, unsigned int line, Test *t ) {
  t->tests_run++;
  if( a == NULL || strcmp(a, b) != 0 ) {
    t->tests_fail++;
    printf( "Failed : (line %d) Got '%s' and expected '%s' : %s\n", line, a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}
#define CHKS( a, b, d ) _chks( a, b, d, __LINE__, t );

void test_util( Test * t )
{
  LinkedList * list, * listB;
  char * thing[10];
  CHKL( make_path( "///tmp/fooby/blecch/" ), 0, "make path double slash" );
  CHKL( make_path( "/tmp/fooby/blecch/" ), 0, "remake path without double" );
  CHKL( make_path( "/tmp/fooby/blecch" ), 0, "remake path no trailing /" );
  CHKL( make_path( "/usr/sicklydo" ), 2, "make path no perms" );

  creat( "/tmp/nothingy", 0666 );
  CHKL( make_path( "/tmp/nothingy" ), 1, "make path against file" );

  // linked list test
  thing[0] = strdup("THIS IS THING A");
  thing[1] = strdup("THIS IS THING N");
  thing[2] = strdup("THIS IS THING C");
  thing[3] = strdup("THIS IS THING D");
  thing[4] = strdup("THIS IS THING E");
  thing[5] = strdup("THIS IS THING F");

  list = create_linked_list( thing[0] );
  
  CHKS( (char*)list->item, "THIS IS THING A", "linked list head string set properly" );
  listB = insert_next( list, thing[1] );
  CHKS( list->next->item, "THIS IS THING N", "next string set properly" );
  CHKB( list->prev == 0, "no prev yet" );
  CHKB( listB->prev == list, "prev link to list" );
  CHKB( list->next == listB, "list to prev link" );
  CHKS( listB->prev->item, "THIS IS THING A", "next links back" );

  listB = insert_next( list, thing[2] );
  CHKS( listB->next->item, "THIS IS THING N", "insert next string set properly" );
  CHKS( list->next->next->prev->item, "THIS IS THING C", "bouncy bouncy" );
  CHKS( list->item, "THIS IS THING A", "list still list" );
  
  listB = insert_prev( list, thing[3] );
  CHKS( listB->next->item, "THIS IS THING A", "prev link back" );
  CHKS( list->prev->item, "THIS IS THING D", "prev link to" );

  listB = insert_prev( list, thing[4] );
  CHKS( listB->next->item, "THIS IS THING A", "prev ins link back" );
  CHKS( listB->prev->item, "THIS IS THING D", "prev ins updated link to" );
  CHKS( list->prev->item, "THIS IS THING E", "prev inst link to" );

  CHKB( find_in_list( list, thing[0] ) == list, "found first thing put in" );
  CHKB( find_in_list( list, thing[5] ) == 0, "nothere not found" );

  char * s = buildstring( 3, "THIS", "/", "WAS" );
  CHKS( s, "THIS/WAS", "buildstring" );
  free( s );
  s = buildstringn( 3, "THIS", "/", 4444 );
  CHKS( s, "THIS/4444", "buildstringn" );
  free( s );
  
  free_linked_list( list, 1 );
  free( thing[5] );
} //test_util

void test_silo( Test * t )
{
  char dir[] = "SILOONE";
  char  F1[] = "SILOONE/0";
  char  F2[] = "SILOONE/1";
  Silo *silo;
  long long id;
  char * res;
  TransactionEntry * trans;
  struct stat stat_buffer;

  // TEST common and edge cases
  /*
    
    open_silo( dir, rec_size )
       - test with dir already there
       - test with dir not there
       - test with unwriteable dir
       - different record_sizes (0, small, big)
       - different max_file_size (0, small, big)

    empty_silo   <---- tested

    unlink_silo  <--- tested

    cleanup_silo <--- valgrind tested

    silo_ensure_entry_count
       - 0 and an other count
       - a count with larger than record_size*max_file_size
    
    silo_entry_count
       - when empty
       - when at end of silo file
       - when at start of silo file past the first
       - after pop

    silo_next_id
       - when empty
       - when at end of silo file
       - when at start of silo file past the first

    silo_get_record( silo, idx )
       - when empty
       - when at end of silo file
       - when at start of silo file past the first
       - at an index past the last index

    silo_pop
       - when empty
       - when at end of silo file
       - when at start of silo file past the first

    silo_put_record( silo, id, data, amount )

    silo_push
       - when empty
       - when at end of silo file
       - when at start of silo file past the first

    create_transaction

    open_transaction

    list_transactions

    trans_stow

    trans_delete_record

    trans_recycle_id

    commit

    rollback

   */
  
  
  if ( 0 == stat( dir, &stat_buffer ) && S_ISDIR( stat_buffer.st_mode ) )
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

  // want the MAX_FILE_SIZE to be defined as 44 for the test ( or 4 entries per )
  silo = open_silo( dir, 11 );
  silo->file_max_records = 4;
  CHKB( silo != NULL, "opened silo" );
  CHKL( stat( dir, &stat_buffer ), 0, "Directory created" );
  CHKL( stat( F1, &stat_buffer ), 0, "First silo file created" ); 
  //cleanup_silo(silo);free(silo);return;
  stat( dir, &stat_buffer );
  if ( ! S_ISDIR( stat_buffer.st_mode ) )
    {
      printf( "FAIL : silo directory not created. bailing\n" );
      exit( 0 );
    }
  CHKL( filecount( dir ), 1, "One file" );
  CHKL( silo_entry_count(silo), 0, "starts at zero entry count" );
  CHKL( silo_put_record( silo, 0, "012345678901", 0 ), 1, "record too large" );
  CHKL( silo_entry_count(silo), 0, "still zero entry count" );
  CHKL( filesize( F1 ), 0, "size 0" );

  id = silo_next_id( silo );
  CHKL( id, 1, "first id" );
  CHKL( filesize( F1 ), 11, "size 1" );
  CHKL( silo_entry_count(silo), 1, "first (empty) entry from silo_next_id" );
  CHKL( silo_put_record( silo, id, "0123456789", 0 ), 0, "first record put" );

  CHKL( filesize( F1 ), 11, "still size 1" );
    
  res = silo_get_record( silo, id );
  CHKS( res, "0123456789", "first entry" );
  free( res );

  cleanup_silo( silo );
  free( silo );
  // reopen silo, verify the entry is still there
  CHKL( filesize( F1 ), 11, "still size 1  before reopen" );
  silo = open_silo( dir, 11 );
  silo->file_max_records = 4;
  CHKL( silo_entry_count(silo), 1, "entry count after reopen" );
  
  res = silo_get_record( silo, id );
  CHKS( res, "0123456789", "first entry after reopen" );
  
  CHKL( silo_entry_count(silo), 1, "entry count after reopen and get" );
  CHKL( silo_put_record( silo, id, "0123456789", 0 ), 0, "put first valid record" );
  
  free( res );
  res = silo_get_record(silo,1);
  CHKS( res, "0123456789", "first entry still same" );
  CHKL( silo_entry_count(silo), 1, "first entry count still same" );

  id = silo_push( silo, "POOOPYTWO", 0 );
  CHKL( id, 2, "second entry id" );
  CHKL( filesize( F1 ), 22, "size 2" );
  CHKL( silo_entry_count(silo), 2, "second entry count" );
  free( res );
  res = silo_get_record( silo, 1 );
  CHKS( res, "0123456789", "Still first entry" );
  free( res );
  res = silo_get_record( silo, 2 );
  CHKS( res, "POOOPYTWO", "second entry" );
  free( res );
  res = silo_pop( silo );
  CHKL( filesize( F1 ), 11, "back to size 1" );
  CHKS( res, "POOOPYTWO", "second entry popped off" );
  CHKL( silo_entry_count(silo), 1, "popped entry count" );

  id = silo_next_id( silo );
  CHKL( id, 2, "next id after pop" );
  CHKL( silo_entry_count(silo), 2, "entry count after next_id" );

  // make sure there is just one file
  CHKL( filecount( dir ), 1, "One file" ); 
  
  CHKL( silo_put_record( silo, 6, "9876543210", 0 ), 0, "put first valid record" );  
  CHKL( filesize( F1 ), 44, "full size for file 1" );
  CHKL( filesize( F2 ), 22, "half size for file 2" );
  CHKL( silo_entry_count(silo), 6, "6 records now" );
  
  free( res );
  res = silo_get_record( silo, 5 );
  CHKS( res, "", "empty record 5" );
  
  free( res );
  res = silo_get_record( silo, 4 );
  CHKS( res, "", "empty record 4" );
  free( res );

  // test emtpy_silo
  empty_silo( silo );
  CHKL( silo_entry_count(silo), 0, "entry count after empty" );
  stat( dir, &stat_buffer );
  CHKB( S_ISDIR( stat_buffer.st_mode ), "Directory still exists after empty" );

  // test unlink_silo
  unlink_silo( silo );
  CHKB( 0 != stat( dir, &stat_buffer ), "Directory gone after unlink" );
  
  cleanup_silo( silo );
  free( silo );

  // new silo for TransactionEntry
  silo  = open_silo( dir, sizeof( TransactionEntry ) );
  trans = calloc( sizeof( TransactionEntry ), 1 );
  trans->type = 1;
  trans->rid  = 2;
  trans->from_silo_idx = 3;
  trans->from_sid = 4;
  trans->to_silo_idx = 5;
  trans->to_sid = 6;

  id = silo_next_id( silo );
  CHKL( id, 1, "FIRST ID" );
  CHKL( silo_put_record( silo, id, trans, sizeof( TransactionEntry ) ), 0, "Put Trans Record" );
  free( trans );

  trans = (TransactionEntry*)silo_get_record( silo, id );
  CHKL( trans->type, 1, "Trans E a" );
  CHKL( trans->rid, 2, "Trans E b" );
  CHKL( trans->from_silo_idx, 3, "Trans E c" );
  CHKL( trans->from_sid, 4, "Trans E d" );
  CHKL( trans->to_silo_idx, 5, "Trans E e" );
  CHKL( trans->to_sid, 6, "Trans E f" );

  free( trans );
  unlink_silo( silo );

  // make sure directory is removed
  CHKB( 0 != stat( dir, &stat_buffer ), "Directory gone after unlink" );
  
  cleanup_silo( silo );
  free( silo );
  
} //test_silo

void test_record_store( Test *t )
{
  struct stat stat_buffer;
   
  long long id;
  // want the max filesize to be defined as 80 for the store
  RecordStore * store = open_store( "RECSTORE" );
  CHKL( silo_entry_count(store->index_silo), 0, "store created and nothing in index" );
  char * res;
  
  id = next_id( store );
  CHKL( id, 1, "first record id" );
  stow( store, "0123456789" , 1, 0 );

  res = fetch( store, 1 );
  CHKS( res, "0123456789" , "first item" );
  free( res );
  CHKL( store_entry_count( store ), 1, "start with 1 entry in store" );
  stow( store, "1123456789" , 5, 0 );
  CHKL( store_entry_count( store ), 5, "Now with 5 entries in store" );
  
  id = next_id( store );
  CHKL( id, 6, "rec id now" );  

  CHKL( store_entry_count( store ), 6, "6 entries in store" );

  CHKB( has_id( store, 1 ), "has first id" );
  CHKB( ! has_id( store, 2 ), "no second id" );
  CHKB( ! has_id( store, 3 ), "no third id" );
  CHKB( ! has_id( store, 4 ), "no fourth id" );
  CHKB( has_id( store, 5 ), "has fifth id" );
  CHKB( !has_id( store, 6 ), "no sixth id" );

  CHKL( silo_entry_count( store->silos[3] ), 2, "two entries in second silo" );

  delete_record( store, 5 );
  CHKL( silo_entry_count( store->silos[3] ), 1, "one entry in second silo after deletion and swap" );
  CHKL( store_entry_count( store ), 6, "still 6 entries in store fater delete" );

  stow( store, "2123456789" , 5, 0 );
  CHKL( silo_entry_count( store->silos[3] ), 2, "two entries in second silo" );
  CHKL( store_entry_count( store ), 6, "still 6 entries in store" );
  recycle_id( store, 6 );
  CHKL( store_entry_count( store ), 5, "now 5 entries in store" );
  recycle_id( store, 5 );
  CHKL( store_entry_count( store ), 4, "now 4 entries in store" );
  CHKL( silo_entry_count( store->silos[3] ), 1, "one entry in second silo after recycle" );
  id = next_id( store );
  CHKL( id, 5, "recycled id 5" );
  id = next_id( store );
  CHKL( id, 6, "recycled id 6" );
  
  // this is in silo index 3
  res = fetch( store, 5 );
  CHKB( res == 0, "nothing for recycled id" );
  delete_record( store, 3 );
  unlink_store( store );

  // make sure directory is removed
  CHKB( 0 != stat( "RECSTORE", &stat_buffer ), "Directory gone after store unlink" );
  
  cleanup_store( store );
  free( store );

}//test_record_store

int main() {

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

