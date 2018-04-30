#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
typedef IndexEntry IndexEntryy 
typedef RecordStore RecordStorey
typedef Silo Siloy

MODULE = Data::RecordStore::XS		PACKAGE = Data::RecordStore::XS

RecordStorey *
store_open(directory)
     char *directory
CODE:
     RETVAL = open_store( directory );
OUTPUT:
     RETVAL

uint64_t
store_stow( store, data, write_amount )
     RecordStorey * store
     char * data
     uint64_t write_amount
CODE:
     RETVAL = stow( store, data, write_amount );
     
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

MODULE = Data::RecordStore::XS		PACKAGE = Data::RecordStore::Silo::XS
  // silo_open
  // silo_empty
  // silo_next_id
  // silo_pop
  // silo_push
  // silo_put
  // silo_get
  // silo_unlink
