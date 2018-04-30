#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "record_store.h"
typedef RecordStore RecordStorey;

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

RecordStorey *
store_open(directory)
     char *directory
CODE:
    printf( "opening store '%s'\n", directory );
    RETVAL = open_store( directory );
OUTPUT:
    RETVAL

uint64_t
stow( store, data, rid, write_amount )
     RecordStorey * store
     char * data
     uint64_t rid
     uint64_t write_amount
CODE:
     RETVAL = stow( store, data, rid, write_amount );
OUTPUT:
     RETVAL

uint64_t
store_next_id( store )
     RecordStorey * store
PREINIT:
    RecordStorey *thisrs;
CODE:
     thisrs = (RecordStorey*)store;
     RETVAL = next_id( thisrs );
OUTPUT:
     RETVAL
       
     
MODULE = Data::RecordStore::XS		PACKAGE = Data::RecordStore::Silo::XS
