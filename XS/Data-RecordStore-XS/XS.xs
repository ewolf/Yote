#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "record_store.h"

  // store_fetch
  // store_delete
  // store_recycle
  // store_has_id
  // store_empty
  // store_unlink
  // store_empty_recyler
  
  // store_create_transaction
  // store_list_transactions
  // transaction_stow
  // transaction_delete
  // transaction_recycle
  // transaction_commit
  // transaction_rollback

  // silo_open
  // silo_empty
  // silo_next_id
  // silo_pop
  // silo_push
  // silo_put
  // silo_get
  // silo_unlink

MODULE = Data::RecordStore::XS		PACKAGE = Data::RecordStore::XS

RecordStore *
store_open(directory)
     char *directory
CODE:
    RETVAL = open_store( directory );
OUTPUT:
    RETVAL

char *
store_fetch( store, rid )
     RecordStore * store
     uint64_t rid
CODE:
     RETVAL = fetch( store, rid );
OUTPUT:
    RETVAL
        
uint64_t
store_stow( store, data, rid, write_amount )
     RecordStore * store
     char * data
     uint64_t rid
     uint64_t write_amount
CODE:
     RETVAL = stow( store, data, rid, write_amount );
OUTPUT:
     RETVAL

    
uint64_t
store_next_id( store )
     RecordStore * store
CODE:
     RETVAL = next_id( store );
OUTPUT:
     RETVAL
       
     
MODULE = Data::RecordStore::XS		PACKAGE = Data::RecordStore::Silo::XS

Silo *
silo_open( directory, size )
    char * directory
    uint64_t size
CODE:
    RETVAL = open_silo( directory, size );
OUTPUT:
    RETVAL    

uint64_t
next_id_silo( silo )
     Silo * silo
CODE:
     RETVAL = silo_next_id( silo );
OUTPUT:
     RETVAL

int
put_record_silo( silo, sid, data, write_size )
     Silo * silo
     uint64_t sid
     char * data
     uint64_t write_size
CODE:
     RETVAL = silo_put_record( silo, sid, data, write_size );
OUTPUT:
     RETVAL

char *
get_record_silo( silo, sid )
     Silo * silo
     uint64_t sid
CODE:
     RETVAL = silo_get_record( silo, sid );
OUTPUT:
     RETVAL
    
    
int
_silo_set_max_records( silo, recs )
    Silo * silo
    int recs
CODE:
    silo->file_max_records = recs;
    RETVAL = silo->file_max_records;
OUTPUT:
    RETVAL