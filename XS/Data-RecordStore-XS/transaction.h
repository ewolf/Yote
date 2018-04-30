#ifndef _TRANS_SEEN
#define _TRANS_SEEN

#include "record_store.h"
#include "silo.h"

#define TRA_ACTIVE 1
#define TRA_IN_COMMIT 2
#define TRA_IN_ROLLBACK 3
#define TRA_CLEANUP_COMMIT 4
#define TRA_CLEANUP_ROLLBACK 5
#define TRA_DONE 6

#define TRA_STOW 1
#define TRA_DELETE 1
#define TRA_RECYCLE 2

typedef struct
{
  unsigned long id;
  unsigned long pid;
  unsigned long update_time;
  unsigned int  state;
  RecordStore * store;
  Silo *        silo;
  Silo *        catalog_silo;
} Transaction;


Transaction * create_transaction( RecordStore *store );
Transaction * list_transactions( RecordStore *store );

unsigned long trans_stow( Transaction *trans, char *data, unsigned long id );
int           trans_delete_record( Transaction *trans, unsigned long id );
int           trans_recycle_id( Transaction *trans, unsigned long id );

void          commit( Transaction *trans );
void          rollback( Transaction *trans );

#endif
