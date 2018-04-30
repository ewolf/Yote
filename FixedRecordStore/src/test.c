#include <errno.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "util.h"
#include "silo.h"
//#include "record_store.h"

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
    printf( "Error : Failed : %s\n", desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
    
}

void chkl( long a, long b, char * desc, Test *t ) {
  t->tests_run++;
  if( a != b ) {
    t->tests_fail++;
    printf( "Error : Got %ld and expected %ld : %s\n", a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}

void chks( char * a, char * b, char * desc, Test *t ) {
  t->tests_run++;
  if( a == NULL || strcmp(a, b) != 0 ) {
    t->tests_fail++;
    printf( "Error : Got '%s' and expected '%s' : %s\n", a, b, desc );
  }
  else if( VERB ) {
    printf( "Passed : %s\n", desc );
  }
}

void test_silo( Test * t )
{
  char dir[] = "SILOONE";
  char F1[] = "SILOONE/0";
  char F2[] = "SILOONE/1";
  Silo *silo;
  unsigned long id;
  char * res;
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
  chkl( silo_put_record( silo, 1, "01234567890" ), 0, "record too large", t );
  chkl( silo_entry_count(silo), 0, "still zero entry count", t );
  chkl( filesize( F1 ), 0, "size 0", t );

  id = silo_next_id( silo );
  chkl( id, 1, "first id", t );
  chkl( filesize( F1 ), 11, "size 1", t );
  
  chkl( silo_put_record( silo, id, "0123456789" ), 1, "first record put", t );
  
  res = silo_get_record( silo, id );
  chks( res, "0123456789", "first entry", t );

  free( res );
  res = silo_last_entry(silo);
  chks( res, "0123456789", "last entry", t );
  chkl( silo_entry_count(silo), 1, "first entry count", t );
  chkl( silo_put_record( silo, id, "0123456789" ), 1, "put first valid record", t );
  
  free( res );
  res = silo_last_entry(silo);
  chks( res, "0123456789", "first last entry still same", t );
  free( res );
  res = silo_get_record(silo,1);
  chks( res, "0123456789", "first entry still same", t );
  chkl( silo_entry_count(silo), 1, "first entry count still same", t );

  id = silo_push( silo, "POOOPYTWO" );
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
  
  chkl( silo_put_record( silo, 6, "9876543210" ), 1, "put first valid record", t );  
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

  free( silo->directory );
  free( silo );
  free( stat_buffer );
} //test_silo

void test_record_store( Test *t )
{
  
}//test_record_store

int main() {
  printf( "Starting tests\n" );
  Test * t = malloc( sizeof(Test) );
  t->tests_run = 0;
  t->tests_fail = 0;

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
